import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:worship_chat/common/utils/ai_inpainting_service.dart';
import 'package:worship_chat/common/utils/ai_text_remover_service.dart';
import 'package:worship_chat/features/chat/screens/ai_magic_studio_screen.dart';

void main() {
  group('AiTextRemover & AiInpainting Accuracy Tests', () {
    test(
      'preserves full native resolution (>1280px) and removes text with dark outline cleanly',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('text_rem_hd_');
        addTearDown(() => tempDir.delete(recursive: true));

        const w = 1400;
        const h = 900;
        final canvas = img.Image(width: w, height: h);

        // Paint smooth sky-to-horizon vertical gradient
        for (int y = 0; y < h; y++) {
          final r = (40 + (y / h) * 140).round();
          final g = (90 + (y / h) * 100).round();
          final b = (210 - (y / h) * 80).round();
          for (int x = 0; x < w; x++) {
            canvas.setPixelRgba(x, y, r, g, b, 255);
          }
        }

        // Stamp thick dark drop-shadow / outline + bright white text block at (500..720, 400..448)
        for (int y = 398; y <= 450; y++) {
          for (int x = 498; x <= 722; x++) {
            final isInnerText =
                x >= 500 && x <= 720 && y >= 400 && y <= 448 && ((x - 500) % 24 < 12);
            if (isInnerText) {
              canvas.setPixelRgba(x, y, 255, 255, 255, 255);
            } else if (x == 498 || x == 499 || y == 398 || y == 399) {
              // Dark shadow overhang 2px outside OCR bounding box!
              canvas.setPixelRgba(x, y, 10, 10, 10, 255);
            }
          }
        }

        final srcFile = File('${tempDir.path}/src.png');
        await srcFile.writeAsBytes(img.encodePng(canvas));
        final outPath = '${tempDir.path}/out.png';

        final result = await AiTextRemoverService.instance.eraseDetectedText(
          sourceImage: srcFile,
          textBlocks: [
            DetectedTextBlock(
              text: 'WATERMARK',
              boundingBox: const Rect.fromLTRB(500, 400, 720, 448),
              words: [
                TextWordRegion(
                  text: 'WATERMARK',
                  boundingBox: const Rect.fromLTRB(500, 400, 720, 448),
                  lineHeight: 48,
                  cornerPoints: const [
                    Offset(500, 400),
                    Offset(720, 400),
                    Offset(720, 448),
                    Offset(500, 448),
                  ],
                ),
              ],
            ),
          ],
          outputPath: outPath,
        );

        final outDecoded = img.decodeImage(await result.readAsBytes())!;
        // Must NOT shrink the >1280px image down
        expect(outDecoded.width, equals(w));
        expect(outDecoded.height, equals(h));

        // Unmasked distant pixels remain bit-identical
        final untouched = outDecoded.getPixel(50, 50);
        final origUntouched = canvas.getPixel(50, 50);
        expect(untouched.r, equals(origUntouched.r));
        expect(untouched.g, equals(origUntouched.g));
        expect(untouched.b, equals(origUntouched.b));

        // Inside erased zone (including 2px shadow overhang), text/shadow spikes must be gone
        double maxChannelErr = 0;
        for (int y = 398; y <= 450; y++) {
          final expectedR = 40 + (y / h) * 140;
          final expectedG = 90 + (y / h) * 100;
          final expectedB = 210 - (y / h) * 80;
          for (int x = 498; x <= 722; x++) {
            final p = outDecoded.getPixel(x, y);
            final err = [
              (p.r - expectedR).abs(),
              (p.g - expectedG).abs(),
              (p.b - expectedB).abs(),
            ].reduce((a, b) => a > b ? a : b);
            if (err > maxChannelErr) maxChannelErr = err;
          }
        }
        expect(maxChannelErr, lessThan(22.0));
      },
    );

    test(
      'exemplar patch synthesis continues repeating stripe patterns cleanly across text gap',
      () {
        const w = 180;
        const h = 140;
        final canvas = img.Image(width: w, height: h);

        // Alternating vertical bright & dark stripes (period 16px: 8px light, 8px dark)
        for (int y = 0; y < h; y++) {
          for (int x = 0; x < w; x++) {
            final isLightStripe = (x ~/ 8).isEven;
            final val = isLightStripe ? 210 : 50;
            canvas.setPixelRgba(x, y, val, val - 10, val - 20, 255);
          }
        }

        // Stamp bright solid text bar across stripes from x=40..140, y=56..78
        for (int y = 56; y <= 78; y++) {
          for (int x = 40; x <= 140; x++) {
            canvas.setPixelRgba(x, y, 250, 20, 20, 255);
          }
        }

        final mask = Uint8List(w * h);
        for (int y = 54; y <= 80; y++) {
          for (int x = 38; x <= 142; x++) {
            mask[y * w + x] = 255;
          }
        }

        final encoded = Uint8List.fromList(img.encodePng(canvas));
        final outBytes = AiInpaintingService.inpaintImageBytes(
          InpaintParams(
            imageBytes: encoded,
            maskBytes: mask,
            width: w,
            height: h,
            patchRadius: 6,
            preferPng: true,
          ),
        );

        final out = img.decodeImage(outBytes)!;

        // Middle row inside erased box should continue light/dark vertical stripes cleanly
        final lightColSample = out.getPixel(52, 67); // (52 ~/ 8) = 6 (even -> light ~210)
        final darkColSample = out.getPixel(60, 67); // (60 ~/ 8) = 7 (odd -> dark ~50)
        expect(lightColSample.r - darkColSample.r, greaterThan(90));
        expect(lightColSample.g, greaterThan(150)); // Not red text residue
        expect(darkColSample.r, lessThan(90));
      },
    );

    test(
      'buildCombinedMask2D supports oriented rotated word quads merged with manual brush mask',
      () {
        const w = 200;
        const h = 200;

        // Rotated word quad tilted along diagonal
        final tiltedWord = TextWordRegion(
          text: 'HELLO',
          boundingBox: const Rect.fromLTRB(40, 40, 120, 120),
          lineHeight: 24,
          cornerPoints: const [
            Offset(40, 60),
            Offset(100, 40),
            Offset(110, 65),
            Offset(50, 85),
          ],
        );

        // Separate manual brush stroke at bottom-right (165, 165)
        final brushMask = Uint8List(w * h);
        for (int y = 160; y <= 170; y++) {
          for (int x = 160; x <= 170; x++) {
            brushMask[y * w + x] = 255;
          }
        }

        final combined = AiTextRemoverService.buildCombinedMask2D(
          imgW: w,
          imgH: h,
          words: [tiltedWord],
          additionalMaskBytes: brushMask,
          additionalMaskWidth: w,
          additionalMaskHeight: h,
          marginFraction: 0.22,
        );

        // Center of tilted word should be masked
        expect(combined[62][75], equals(255));
        // Far bottom-left corner of axis-aligned Rect(40,40,120,120) should remain unmasked
        expect(combined[118][42], equals(0));
        // Manual brush stroke pixel should also be masked
        expect(combined[165][165], equals(255));
      },
    );

    test('decodeAndBakeImage honors EXIF orientation so coordinates stay aligned', () {
      final raw = img.Image(width: 80, height: 40);
      raw.exif.imageIfd.orientation = 6; // 90 deg CW camera portrait flag
      final encoded = Uint8List.fromList(img.encodeJpg(raw));

      final baked = AiInpaintingService.decodeAndBakeImage(encoded)!;
      expect(baked.width, equals(40));
      expect(baked.height, equals(80));
    });
  });

  group('AiMagicStudioScreen Text-Only UI Tests', () {
    testWidgets(
      'keeps only Text Remover UI, toggles boxes/margins/brush, and runs on compact phone width',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 720));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final tempDir = Directory.systemTemp.createTempSync('studio_ui_');
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });

        final sampleImg = img.Image(width: 240, height: 180);
        img.fill(sampleImg, color: img.ColorRgb8(40, 80, 120));
        // Stamp bright text box in region 40..120, 30..55
        for (int y = 30; y <= 55; y++) {
          for (int x = 40; x <= 120; x++) {
            sampleImg.setPixelRgba(x, y, 255, 255, 255, 255);
          }
        }
        final imgFile = File('${tempDir.path}/sample.png')
          ..writeAsBytesSync(img.encodePng(sampleImg));

        final initialBlocks = [
          DetectedTextBlock(
            text: '@watermark',
            boundingBox: const Rect.fromLTRB(40, 30, 120, 55),
            words: const [
              TextWordRegion(
                text: '@watermark',
                boundingBox: Rect.fromLTRB(40, 30, 120, 55),
                lineHeight: 25,
                cornerPoints: [
                  Offset(40, 30),
                  Offset(120, 30),
                  Offset(120, 55),
                  Offset(40, 55),
                ],
              ),
            ],
          ),
          DetectedTextBlock(
            text: '2026',
            boundingBox: const Rect.fromLTRB(140, 120, 200, 145),
            words: const [
              TextWordRegion(
                text: '2026',
                boundingBox: Rect.fromLTRB(140, 120, 200, 145),
                lineHeight: 25,
              ),
            ],
          ),
        ];

        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 720),
              textScaler: TextScaler.linear(1.15),
            ),
            child: MaterialApp(
              home: AiMagicStudioScreen(
                initialImage: imgFile,
                initialDetectedTextBlocks: initialBlocks,
                autoDetectOnOpen: false,
                outputDirectoryPath: tempDir.path,
              ),
            ),
          ),
        );

        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull);
        expect(tester.getRect(find.text('Erase Text')).bottom <= 720, isTrue);
        expect(tester.getRect(find.text('None')).top > 400, isTrue);

        // Object Remover & Background/Cutout Remover must be completely gone
        expect(find.text('Object Remover'), findsNothing);
        expect(find.text('Cutout & BG'), findsNothing);
        expect(find.text('Transparent'), findsNothing);
        expect(find.text('Portrait Blur'), findsNothing);

        // Only Text Remover controls remain
        expect(find.text('Text Remover'), findsOneWidget);
        expect(find.text('Tight'), findsOneWidget);
        expect(find.text('Normal'), findsOneWidget);
        expect(find.text('Wide'), findsOneWidget);
        expect(find.text('Erase Text'), findsOneWidget);
        expect(find.textContaining('2/2 text boxes'), findsOneWidget);

        // Toggle all off & back on via 'None' / 'All'
        await tester.tap(find.text('None'));
        await tester.pump();
        expect(find.textContaining('0/2 text boxes'), findsOneWidget);

        await tester.tap(find.text('All'));
        await tester.pump();
        expect(find.textContaining('2/2 text boxes'), findsOneWidget);

        // Switch padding margin to Wide and execute Erase Text
        await tester.tap(find.text('Wide'));
        await tester.pump();
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Erase Text'));
        await tester.pump();

        File? generatedOutFile;
        for (int i = 0; i < 30; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pump();
          final matches = tempDir
              .listSync()
              .whereType<File>()
              .where((f) => f.path.contains('text_removed_'))
              .toList();
          if (matches.isNotEmpty) {
            generatedOutFile = matches.first;
            if (find.text('Tap text boxes or brush missed text').evaluate().isNotEmpty) {
              break;
            }
          }
        }
        await tester.pump(const Duration(milliseconds: 150));

        expect(tester.takeException(), isNull);
        expect(generatedOutFile, isNotNull);
        expect(find.text('Tap text boxes or brush missed text'), findsOneWidget);

        final undoButton = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.undo_rounded),
        );
        expect(undoButton.onPressed, isNotNull);

        // White text pixel at (80, 42) in output should now match background (40, 80, 120)
        final outImg = img.decodeImage(generatedOutFile!.readAsBytesSync())!;
        final restoredPixel = outImg.getPixel(80, 42);
        expect((restoredPixel.r - 40).abs(), lessThan(20));
        expect((restoredPixel.g - 80).abs(), lessThan(20));
        expect((restoredPixel.b - 120).abs(), lessThan(20));
      },
    );
  });
}
