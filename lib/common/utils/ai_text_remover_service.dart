import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:worship_chat/common/utils/ai_inpainting_service.dart';

/// Individual word/symbol quad inside a detected line for tight oriented masking.
class TextWordRegion {
  final String text;
  final Rect boundingBox;
  final List<Offset> cornerPoints;
  final double lineHeight;

  const TextWordRegion({
    required this.text,
    required this.boundingBox,
    this.cornerPoints = const [],
    double? lineHeight,
  }) : lineHeight = lineHeight ?? 0.0;

  Map<String, dynamic> toMap() => {
        'l': boundingBox.left,
        't': boundingBox.top,
        'r': boundingBox.right,
        'b': boundingBox.bottom,
        'lh': lineHeight,
        'pts': cornerPoints.map((p) => [p.dx, p.dy]).toList(),
      };

  factory TextWordRegion.fromMap(Map<String, dynamic> map) {
    final rawPts = map['pts'] as List? ?? const [];
    return TextWordRegion(
      text: '',
      boundingBox: Rect.fromLTRB(
        (map['l'] as num).toDouble(),
        (map['t'] as num).toDouble(),
        (map['r'] as num).toDouble(),
        (map['b'] as num).toDouble(),
      ),
      lineHeight: (map['lh'] as num?)?.toDouble() ?? 0.0,
      cornerPoints: rawPts
          .map((e) => Offset((e[0] as num).toDouble(), (e[1] as num).toDouble()))
          .toList(),
    );
  }
}

/// Line-level text block surfaced in UI with nested word-level polygons for accurate erasure.
class DetectedTextBlock {
  final String text;
  final Rect boundingBox;
  final List<Offset> cornerPoints;
  final List<TextWordRegion> words;

  const DetectedTextBlock({
    required this.text,
    required this.boundingBox,
    this.cornerPoints = const [],
    this.words = const [],
  });
}

class _EraseTextParams {
  final Uint8List imageBytes;
  final List<Map<String, dynamic>> wordRegions;
  final List<List<double>> fallbackRects;
  final Uint8List? additionalMaskBytes;
  final int additionalMaskWidth;
  final int additionalMaskHeight;
  final double marginFraction;
  final bool scrubTextHalos;
  final bool preferPng;

  const _EraseTextParams({
    required this.imageBytes,
    required this.wordRegions,
    required this.fallbackRects,
    this.additionalMaskBytes,
    this.additionalMaskWidth = 0,
    this.additionalMaskHeight = 0,
    this.marginFraction = 0.22,
    this.scrubTextHalos = true,
    this.preferPng = false,
  });
}

/// On-device ML Kit text detection and oriented texture-preserving text removal service.
class AiTextRemoverService {
  AiTextRemoverService._();
  static final AiTextRemoverService instance = AiTextRemoverService._();

  TextRecognizer? _textRecognizer;

  TextRecognizer get _getRecognizer {
    _textRecognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
    return _textRecognizer!;
  }

  /// Scans [sourceImage] via ML Kit OCR and returns line blocks with word-level corner quads.
  Future<List<DetectedTextBlock>> detectText(File sourceImage) async {
    final inputImage = InputImage.fromFile(sourceImage);
    final recognizedText = await _getRecognizer.processImage(inputImage);

    final blocks = <DetectedTextBlock>[];
    for (final block in recognizedText.blocks) {
      for (final line in block.lines) {
        if (line.text.trim().isEmpty) continue;

        final lineBox = line.boundingBox;
        final lineCorners = line.cornerPoints
            .map((p) => Offset(p.x.toDouble(), p.y.toDouble()))
            .toList();

        final words = <TextWordRegion>[];
        for (final element in line.elements) {
          if (element.text.trim().isEmpty) continue;
          final eCorners = element.cornerPoints
              .map((p) => Offset(p.x.toDouble(), p.y.toDouble()))
              .toList();
          words.add(
            TextWordRegion(
              text: element.text,
              boundingBox: element.boundingBox,
              cornerPoints: eCorners,
              lineHeight: lineBox.height,
            ),
          );
        }

        if (words.isEmpty) {
          words.add(
            TextWordRegion(
              text: line.text,
              boundingBox: lineBox,
              cornerPoints: lineCorners,
              lineHeight: lineBox.height,
            ),
          );
        }

        blocks.add(
          DetectedTextBlock(
            text: line.text,
            boundingBox: lineBox,
            cornerPoints: lineCorners,
            words: words,
          ),
        );
      }
    }
    return blocks;
  }

  /// Automatically erases selected [textBlocks], optional [textRects], and any manual
  /// [additionalMaskBytes] brush strokes in a single resolution-preserving isolate pass.
  Future<File> eraseDetectedText({
    required File sourceImage,
    List<DetectedTextBlock> textBlocks = const [],
    List<Rect> textRects = const [],
    Uint8List? additionalMaskBytes,
    int additionalMaskWidth = 0,
    int additionalMaskHeight = 0,
    required String outputPath,
    double marginFraction = 0.22,
    bool scrubTextHalos = true,
  }) async {
    final imageBytes = await sourceImage.readAsBytes();
    final preferPng = outputPath.toLowerCase().endsWith('.png');

    final serializedWords = <Map<String, dynamic>>[];
    final serializedRects = <List<double>>[
      for (final r in textRects) [r.left, r.top, r.right, r.bottom],
    ];

    for (final block in textBlocks) {
      if (block.words.isNotEmpty) {
        for (final w in block.words) {
          serializedWords.add(w.toMap());
        }
      } else {
        serializedWords.add(
          TextWordRegion(
            text: block.text,
            boundingBox: block.boundingBox,
            cornerPoints: block.cornerPoints,
            lineHeight: block.boundingBox.height,
          ).toMap(),
        );
      }
    }

    final params = _EraseTextParams(
      imageBytes: imageBytes,
      wordRegions: serializedWords,
      fallbackRects: serializedRects,
      additionalMaskBytes: additionalMaskBytes,
      additionalMaskWidth: additionalMaskWidth,
      additionalMaskHeight: additionalMaskHeight,
      marginFraction: marginFraction,
      scrubTextHalos: scrubTextHalos,
      preferPng: preferPng,
    );

    final resultBytes = await compute(_eraseTextIsolate, params);
    final outFile = File(outputPath);
    await outFile.writeAsBytes(resultBytes);
    return outFile;
  }

  static Uint8List _eraseTextIsolate(_EraseTextParams params) {
    final baked = AiInpaintingService.decodeAndBakeImage(params.imageBytes);
    if (baked == null) return params.imageBytes;

    final imgW = baked.width;
    final imgH = baked.height;

    final words = params.wordRegions.map(TextWordRegion.fromMap).toList();
    final rects = params.fallbackRects
        .map((r) => Rect.fromLTRB(r[0], r[1], r[2], r[3]))
        .toList();

    final mask2D = buildCombinedMask2D(
      imgW: imgW,
      imgH: imgH,
      words: words,
      rects: rects,
      additionalMaskBytes: params.additionalMaskBytes,
      additionalMaskWidth: params.additionalMaskWidth,
      additionalMaskHeight: params.additionalMaskHeight,
      marginFraction: params.marginFraction,
    );

    AiInpaintingService.inpaintDecodedImage(
      baked,
      mask2D,
      patchRadius: 6,
      scrubTextHalos: params.scrubTextHalos,
    );

    return AiInpaintingService.encodeOutputImage(baked, preferPng: params.preferPng);
  }

  /// Rasterizes oriented word quads, fallback rects, and manual strokes into [imgH x imgW].
  static List<Uint8List> buildCombinedMask2D({
    required int imgW,
    required int imgH,
    List<TextWordRegion> words = const [],
    List<Rect> rects = const [],
    Uint8List? additionalMaskBytes,
    int additionalMaskWidth = 0,
    int additionalMaskHeight = 0,
    double marginFraction = 0.22,
  }) {
    final mask2D = (additionalMaskBytes != null &&
            additionalMaskWidth > 0 &&
            additionalMaskHeight > 0)
        ? AiInpaintingService.buildNormalizedMask(
            additionalMaskBytes,
            additionalMaskWidth,
            additionalMaskHeight,
            imgW,
            imgH,
          )
        : List<Uint8List>.generate(imgH, (_) => Uint8List(imgW));

    for (final word in words) {
      _paintWordRegionMask(mask2D, imgW, imgH, word, marginFraction);
    }

    for (final rect in rects) {
      final refH = math.max(rect.height, 14.0);
      final padX = (refH * (marginFraction * 0.9)).clamp(4.0, 28.0);
      final padY = (refH * (marginFraction * 1.15)).clamp(5.0, 32.0);
      _fillAxisAlignedRect(mask2D, imgW, imgH, rect, padX, padY);
    }

    return mask2D;
  }

  static void _paintWordRegionMask(
    List<Uint8List> mask2D,
    int imgW,
    int imgH,
    TextWordRegion word,
    double marginFraction,
  ) {
    final refHeight = math.max(
      word.boundingBox.height,
      word.lineHeight * 0.78,
    ).clamp(14.0, 400.0);

    final padX = (refHeight * (marginFraction * 0.9)).clamp(4.0, 28.0);
    final padY = (refHeight * (marginFraction * 1.15)).clamp(5.0, 32.0);

    final pts = word.cornerPoints;
    if (pts.length == 4) {
      final p0 = pts[0];
      final p1 = pts[1];
      final p2 = pts[2];
      final p3 = pts[3];

      final bx = p1.dx - p0.dx;
      final by = p1.dy - p0.dy;
      final bw = math.sqrt(bx * bx + by * by);

      final hx = p3.dx - p0.dx;
      final hy = p3.dy - p0.dy;
      final bh = math.sqrt(hx * hx + hy * hy);

      if (bw >= 2.0 && bh >= 2.0) {
        final ux = bx / bw;
        final uy = by / bw;
        final vx = hx / bh;
        final vy = hy / bh;
        final crossMag = (ux * vy - uy * vx).abs();

        if (crossMag > 0.25) {
          // Ensure vertical span also comfortably covers ascenders/descenders
          final extraV = math.max(0.0, (refHeight - bh) * 0.45);
          final effPadY = padY + extraV;

          final q0 = Offset(
            p0.dx - ux * padX - vx * effPadY,
            p0.dy - uy * padX - vy * effPadY,
          );
          final q1 = Offset(
            p1.dx + ux * padX - vx * effPadY,
            p1.dy + uy * padX - vy * effPadY,
          );
          final q2 = Offset(
            p2.dx + ux * padX + vx * effPadY,
            p2.dy + uy * padX + vy * effPadY,
          );
          final q3 = Offset(
            p3.dx - ux * padX + vx * effPadY,
            p3.dy - uy * padX + vy * effPadY,
          );

          _fillConvexQuad(mask2D, imgW, imgH, q0, q1, q2, q3);
          return;
        }
      }
    }

    _fillAxisAlignedRect(mask2D, imgW, imgH, word.boundingBox, padX, padY);
  }

  static void _fillAxisAlignedRect(
    List<Uint8List> mask2D,
    int imgW,
    int imgH,
    Rect rect,
    double padX,
    double padY,
  ) {
    final left = (rect.left - padX).floor().clamp(0, imgW - 1);
    final top = (rect.top - padY).floor().clamp(0, imgH - 1);
    final right = (rect.right + padX).ceil().clamp(0, imgW - 1);
    final bottom = (rect.bottom + padY).ceil().clamp(0, imgH - 1);

    for (int y = top; y <= bottom; y++) {
      final row = mask2D[y];
      for (int x = left; x <= right; x++) {
        row[x] = 255;
      }
    }
  }

  static void _fillConvexQuad(
    List<Uint8List> mask2D,
    int imgW,
    int imgH,
    Offset q0,
    Offset q1,
    Offset q2,
    Offset q3,
  ) {
    final minX = math.min(math.min(q0.dx, q1.dx), math.min(q2.dx, q3.dx))
        .floor()
        .clamp(0, imgW - 1);
    final maxX = math.max(math.max(q0.dx, q1.dx), math.max(q2.dx, q3.dx))
        .ceil()
        .clamp(0, imgW - 1);
    final minY = math.min(math.min(q0.dy, q1.dy), math.min(q2.dy, q3.dy))
        .floor()
        .clamp(0, imgH - 1);
    final maxY = math.max(math.max(q0.dy, q1.dy), math.max(q2.dy, q3.dy))
        .ceil()
        .clamp(0, imgH - 1);

    // Compute oriented edges to handle either winding order cleanly
    final e0x = q1.dx - q0.dx, e0y = q1.dy - q0.dy;
    final e1x = q2.dx - q1.dx, e1y = q2.dy - q1.dy;
    final e2x = q3.dx - q2.dx, e2y = q3.dy - q2.dy;
    final e3x = q0.dx - q3.dx, e3y = q0.dy - q3.dy;

    const eps = 1e-4;
    for (int y = minY; y <= maxY; y++) {
      final py = y + 0.5;
      final row = mask2D[y];
      for (int x = minX; x <= maxX; x++) {
        final px = x + 0.5;
        final c0 = e0x * (py - q0.dy) - e0y * (px - q0.dx);
        final c1 = e1x * (py - q1.dy) - e1y * (px - q1.dx);
        final c2 = e2x * (py - q2.dy) - e2y * (px - q2.dx);
        final c3 = e3x * (py - q3.dy) - e3y * (px - q3.dx);

        final allNonNeg = c0 >= -eps && c1 >= -eps && c2 >= -eps && c3 >= -eps;
        final allNonPos = c0 <= eps && c1 <= eps && c2 <= eps && c3 <= eps;
        if (allNonNeg || allNonPos) {
          row[x] = 255;
        }
      }
    }
  }

  void dispose() {
    _textRecognizer?.close();
    _textRecognizer = null;
  }
}
