import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('refined rear bandeau and seamless temple joints', () async {
    final assetFile = File('assets/emojis/aura_elixiria.png');
    final bytes = assetFile.readAsBytesSync();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;

    final imgW = image.width.toDouble();
    final imgH = image.height.toDouble();

    // 512x128 rear texture with center Solitaire Sapphire
    final rearRecorder = ui.PictureRecorder();
    final rearCanvas = Canvas(rearRecorder, const Rect.fromLTWH(0, 0, 512, 128));
    const highlightGold = Color(0xFFFFF7D6);
    const brightGold = Color(0xFFFFE28A);
    const richGold = Color(0xFFE5B03C);
    const deepGold = Color(0xFFB8860B);
    const antiqueGold = Color(0xFF7A5408);
    const shadowBronze = Color(0xFF382303);

    final bandRect = const Rect.fromLTWH(0, 16, 512, 96);
    final bandPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [highlightGold, brightGold, richGold, deepGold, antiqueGold, shadowBronze],
        stops: [0.0, 0.15, 0.40, 0.70, 0.88, 1.0],
      ).createShader(bandRect);
    rearCanvas.drawRect(bandRect, bandPaint);

    final topBevel = Paint()..color = highlightGold..strokeWidth = 2.0..style = PaintingStyle.stroke;
    rearCanvas.drawLine(const Offset(0, 16), const Offset(512, 16), topBevel);
    final botBevel = Paint()..color = shadowBronze..strokeWidth = 2.5..style = PaintingStyle.stroke;
    rearCanvas.drawLine(const Offset(0, 112), const Offset(512, 112), botBevel);

    // Beaded pearl rails
    void drawPearl(Offset center, double radius) {
      final pPaint = Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.35),
          radius: 0.85,
          colors: const [Color(0xFFFFFFFF), Color(0xFFF7F2E7), Color(0xFFDDD4C4), Color(0xFFA89C88)],
          stops: const [0.0, 0.38, 0.72, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: radius));
      rearCanvas.drawCircle(center, radius, pPaint);
    }

    for (double px = 6.0; px <= 506.0; px += 13.0) {
      drawPearl(Offset(px, 26), 4.2);
      drawPearl(Offset(px, 102), 4.2);
    }

    // Gemstones
    void drawGem(Rect rect, Color gemColor, {bool isOval = true}) {
      final bezel = isOval ? (Path()..addOval(rect.inflate(4))) : (Path()..addRRect(RRect.fromRectAndRadius(rect.inflate(4), const Radius.circular(3))));
      final bezelPaint = Paint()
        ..shader = const LinearGradient(
          colors: [highlightGold, brightGold, deepGold, shadowBronze],
        ).createShader(rect.inflate(5));
      rearCanvas.drawPath(bezel, bezelPaint);

      final gemPaint = Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.3),
          radius: 0.9,
          colors: [
            Color.lerp(gemColor, Colors.white, 0.5)!,
            gemColor,
            Color.lerp(gemColor, Colors.black, 0.7)!,
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(rect);

      if (isOval) {
        rearCanvas.drawOval(rect, gemPaint);
      } else {
        rearCanvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(2)), gemPaint);
      }
      final glare = Paint()..color = Colors.white.withValues(alpha: 0.95);
      rearCanvas.drawCircle(rect.center - Offset(rect.width * 0.22, rect.height * 0.22), 2.0, glare);
    }

    // Center Back Solitaire Sapphire (X=256)
    drawGem(Rect.fromCenter(center: const Offset(256, 64), width: 42, height: 28), const Color(0xFF1565C0), isOval: true);
    // Flanking Emeralds (X = 145, 367)
    drawGem(Rect.fromCenter(center: const Offset(145, 64), width: 24, height: 24), const Color(0xFF0F6E38), isOval: false);
    drawGem(Rect.fromCenter(center: const Offset(367, 64), width: 24, height: 24), const Color(0xFF0F6E38), isOval: false);
    // Lateral Rubies (X = 60, 452)
    drawGem(Rect.fromCenter(center: const Offset(60, 64), width: 20, height: 20), const Color(0xFFC2185B), isOval: true);
    drawGem(Rect.fromCenter(center: const Offset(452, 64), width: 20, height: 20), const Color(0xFFC2185B), isOval: true);

    final rearTexture = await rearRecorder.endRecording().toImage(512, 128);

    const totalSlices = 72;
    const sliceAngle = (math.pi * 2) / totalSlices;

    final angles = {
      'front': (0.0, -0.15),
      'profile_90': (math.pi / 2.0, -0.12),
      'back_180': (math.pi, -0.15),
    };

    const frontArc = 0.72 * math.pi;

    for (final entry in angles.entries) {
      final yaw = entry.value.$1;
      final pitch = entry.value.$2;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 400, 360));
      canvas.drawColor(const Color(0xFF0F0E17), BlendMode.src);

      final w = 400.0;
      final h = 360.0;
      final cx = w / 2.0;
      final cy = h / 2.0;

      final radiusX = w * 0.44;
      final radiusZ = w * 0.35;
      final crownH = h * 0.78;
      const cameraDist = 900.0;

      // Soft floor shadow
      final shadowPaint = Paint()..color = Colors.black.withValues(alpha: 0.60)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
      final shadowOffsetX = math.sin(yaw) * (w * 0.08);
      final shadowOffsetY = (h * 0.44) + math.cos(pitch) * (h * 0.03);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx + shadowOffsetX, cy + shadowOffsetY),
          width: w * 0.88,
          height: (w * 0.26 * (1.0 - pitch * 0.40)).clamp(w * 0.12, w * 0.44),
        ),
        shadowPaint,
      );

      final contentInset = 0.0; // full natural wings
      final effectiveImgW = imgW;
      final srcSliceW = effectiveImgW / (totalSlices * (frontArc / math.pi));
      final rearImgW = 512.0;
      final rearSliceW = rearImgW / (totalSlices * ((math.pi - frontArc * 0.75) / math.pi));

      final slices = <Map<String, dynamic>>[];

      for (int i = 0; i < totalSlices; i++) {
        final theta = -math.pi + (i + 0.5) * sliceAngle;
        final alpha = theta + yaw;

        final x0 = radiusX * math.sin(alpha);
        final z0 = radiusZ * math.cos(alpha);

        final yRot = -z0 * math.sin(pitch);
        final zRot = z0 * math.cos(pitch);

        final scale = cameraDist / (cameraDist - zRot);
        final screenX = cx + x0 * scale;
        final screenY = (cy - h * 0.04) + yRot * scale;

        final cosA = math.cos(alpha);
        final arcSliceW = ((math.pi * 2 * radiusX) / totalSlices) * scale;
        // Overlap prevents visible vertical seams
        final sliceW = (arcSliceW * cosA.abs() + 2.0).clamp(arcSliceW * 0.65, arcSliceW * 1.45);
        final sliceH = crownH * scale;

        final isFacingViewer = cosA * math.cos(pitch) > 0;
        final double light;
        if (isFacingViewer) {
          light = (0.72 - 0.28 * math.sin(alpha) + 0.32 * math.cos(alpha)).clamp(0.55, 1.35);
        } else {
          light = (0.48 - 0.16 * math.sin(alpha) - 0.20 * math.cos(alpha)).clamp(0.32, 0.78);
        }

        // 1. FRONT TIARA SLICE (|theta| <= frontArc)
        if (theta.abs() <= frontArc) {
          final u = (theta + frontArc) / (frontArc * 2.0);
          final srcX = (u * (effectiveImgW - srcSliceW)).clamp(0.0, effectiveImgW - srcSliceW);
          final srcRect = Rect.fromLTWH(srcX, 0, srcSliceW, imgH);
          final destRect = Rect.fromLTWH(
            screenX - sliceW / 2.0,
            screenY - sliceH / 2.0,
            sliceW,
            sliceH,
          );
          slices.add({
            'z': zRot,
            'light': light,
            'srcRect': srcRect,
            'destRect': destRect,
            'isFacingViewer': isFacingViewer,
            'isRearBand': false,
          });
        }

        // 2. REAR HEADBAND SLICE (|theta| >= frontArc - 0.18 * pi)
        if (theta.abs() >= (frontArc - 0.20 * math.pi)) {
          final rearCoverage = math.pi - (frontArc - 0.20 * math.pi);
          final t = (theta.abs() - (frontArc - 0.20 * math.pi)) / rearCoverage;
          // Center Back (t = 1) -> u = 0.5 (Solitaire Sapphire)
          // Temples (t = 0) -> u = 0.0 (left temple) or 1.0 (right temple)
          final double u;
          if (theta <= 0) {
            u = 0.0 + t * 0.5; // Left temple (0.0) -> Center Back (0.5)
          } else {
            u = 1.0 - t * 0.5; // Right temple (1.0) -> Center Back (0.5)
          }
          final srcX = (u * (rearImgW - rearSliceW)).clamp(0.0, rearImgW - rearSliceW);
          final srcRect = Rect.fromLTWH(srcX, 16, rearSliceW, 96);

          final bandTop = (screenY - sliceH * 0.5) + (imgH * 0.56 / imgH) * sliceH;
          final bandH = (imgH * 0.145 / imgH) * sliceH;
          final destRect = Rect.fromLTWH(
            screenX - sliceW / 2.0,
            bandTop,
            sliceW,
            bandH,
          );

          slices.add({
            'z': zRot,
            'light': light,
            'srcRect': srcRect,
            'destRect': destRect,
            'isFacingViewer': isFacingViewer,
            'isRearBand': true,
          });
        }
      }

      slices.sort((a, b) => (a['z'] as double).compareTo(b['z'] as double));

      for (final s in slices) {
        final isRearBand = s['isRearBand'] as bool;
        final isFacingViewer = s['isFacingViewer'] as bool;
        final light = s['light'] as double;
        final srcRect = s['srcRect'] as Rect;
        final destRect = s['destRect'] as Rect;

        if (!isRearBand) {
          final Paint slicePaint;
          if (isFacingViewer) {
            slicePaint = Paint()
              ..colorFilter = light < 0.97 || light > 1.03
                  ? ColorFilter.matrix(<double>[
                      light, 0, 0, 0, 0,
                      0, light, 0, 0, 0,
                      0, 0, light * 0.98, 0, 0,
                      0, 0, 0, 1.0, 0,
                    ])
                  : null;
          } else {
            slicePaint = Paint()
              ..colorFilter = ColorFilter.matrix(<double>[
                0.48 * light, 0, 0, 0, 0,
                0, 0.36 * light, 0, 0, 0,
                0, 0, 0.22 * light, 0, 0,
                0, 0, 0, 0.95, 0,
              ]);
          }
          canvas.drawImageRect(image, srcRect, destRect, slicePaint);
        } else {
          final Paint bandPaint;
          if (isFacingViewer) {
            bandPaint = Paint()
              ..colorFilter = ColorFilter.matrix(<double>[
                light, 0, 0, 0, 0,
                0, light, 0, 0, 0,
                0, 0, light * 0.96, 0, 0,
                0, 0, 0, 1.0, 0,
              ]);
          } else {
            bandPaint = Paint()
              ..colorFilter = ColorFilter.matrix(<double>[
                0.36 * light, 0, 0, 0, 0,
                0, 0.26 * light, 0, 0, 0,
                0, 0, 0.14 * light, 0, 0,
                0, 0, 0, 0.95, 0,
              ]);
          }
          canvas.drawImageRect(rearTexture, srcRect, destRect, bandPaint);
        }
      }

      final pic = recorder.endRecording();
      final rendered = await pic.toImage(400, 360);
      final byteData = await rendered.toByteData(format: ui.ImageByteFormat.png);
      File('/Users/nandhakumar/.gemini/antigravity/brain/9d8e4d9b-b461-4a7b-96a6-6e732447b51f/arc_v2_${entry.key}.png')
          .writeAsBytesSync(byteData!.buffer.asUint8List());
      print('Saved arc_v2_${entry.key}.png');
    }
  });
}
