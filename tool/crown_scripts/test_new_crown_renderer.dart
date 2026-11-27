import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('test new 360 crown renderer with front and rear master textures', () async {
    final frontBytes = File('assets/emojis/aura_elixiria.png').readAsBytesSync();
    final frontCodec = await ui.instantiateImageCodec(frontBytes);
    final frontImage = (await frontCodec.getNextFrame()).image;

    final rearBytes = File('assets/emojis/aura_elixiria_rear.png').readAsBytesSync();
    final rearCodec = await ui.instantiateImageCodec(rearBytes);
    final rearImage = (await rearCodec.getNextFrame()).image;

    print('Loaded front: ${frontImage.width}x${frontImage.height}, rear: ${rearImage.width}x${rearImage.height}');

    final angles = {
      'front_0': (0.0, -0.15),
      'tilt_30': (0.52, -0.20),
      'angle_60': (1.05, -0.16),
      'profile_90': (math.pi / 2.0, -0.12),
      'back_180': (math.pi, -0.15),
    };

    const totalSlices = 96;
    const sliceAngle = (math.pi * 2) / totalSlices;
    const cameraDist = 900.0;

    for (final entry in angles.entries) {
      final yaw = entry.value.$1;
      final pitch = entry.value.$2;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 400, 360));
      canvas.drawColor(const Color(0xFF0F0E17), BlendMode.src);

      const w = 400.0;
      const h = 360.0;
      final cx = w / 2.0;
      final cy = h / 2.0;

      final radiusX = w * 0.44;
      final radiusZ = w * 0.35;
      final crownH = h * 0.82;

      // Interior velvet cushion floor
      final velvetPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFF1E1628).withValues(alpha: 0.85),
            const Color(0xFF0F0B15).withValues(alpha: 0.95),
          ],
        ).createShader(Rect.fromCenter(
          center: Offset(cx, cy + crownH * 0.36),
          width: radiusX * 1.6,
          height: radiusZ * 1.25,
        ));
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx, cy + crownH * 0.36),
          width: radiusX * 1.6,
          height: radiusZ * 1.25,
        ),
        velvetPaint,
      );

      // Collect all slices
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
        final sliceW = (arcSliceW * cosA.abs() + 2.0).clamp(arcSliceW * 0.70, arcSliceW * 1.45);
        final sliceH = crownH * scale;

        final isFacingViewer = cosA * math.cos(pitch) > 0;

        final double light;
        if (isFacingViewer) {
          light = (0.75 - 0.25 * math.sin(alpha) + 0.30 * math.cos(alpha)).clamp(0.55, 1.30);
        } else {
          light = (0.50 - 0.15 * math.sin(alpha) - 0.18 * math.cos(alpha)).clamp(0.35, 0.75);
        }

        // Texture selection: front or rear
        final bool isFront = theta.abs() <= math.pi / 2.0;
        final ui.Image activeImg = isFront ? frontImage : rearImage;
        final double imgW = activeImg.width.toDouble();
        final double imgH = activeImg.height.toDouble();

        // Calculate continuous U coordinate across [0, 1]
        final double u;
        if (isFront) {
          // theta in [-pi/2, pi/2] -> u in [0, 1]
          u = (theta + math.pi / 2.0) / math.pi;
        } else {
          // theta in [-pi, -pi/2] or [pi/2, pi]
          if (theta < 0) {
            // theta in [-pi, -pi/2] -> u in [0.5, 0.0]
            final t = (-theta - math.pi / 2.0) / (math.pi / 2.0);
            u = 0.5 - t * 0.5;
          } else {
            // theta in [pi/2, pi] -> u in [1.0, 0.5]
            final t = (theta - math.pi / 2.0) / (math.pi / 2.0);
            u = 1.0 - t * 0.5;
          }
        }

        final srcSliceW = imgW / (totalSlices / 2.0);
        final srcX = (u * (imgW - srcSliceW)).clamp(0.0, imgW - srcSliceW);
        final srcRect = Rect.fromLTWH(srcX, 0, srcSliceW, imgH);
        final destRect = Rect.fromLTWH(
          screenX - sliceW / 2.0,
          screenY - sliceH / 2.0,
          sliceW,
          sliceH,
        );

        slices.add({
          'z': zRot,
          'screenX': screenX,
          'screenY': screenY,
          'width': sliceW,
          'height': sliceH,
          'light': light,
          'isFacingViewer': isFacingViewer,
          'isFront': isFront,
          'image': activeImg,
          'srcRect': srcRect,
          'destRect': destRect,
        });
      }

      // Sort back to front (Painter's algorithm)
      slices.sort((a, b) => (a['z'] as double).compareTo(b['z'] as double));

      // Draw all slices
      for (final s in slices) {
        final light = s['light'] as double;
        final isFacing = s['isFacingViewer'] as bool;
        final img = s['image'] as ui.Image;
        final srcRect = s['srcRect'] as Rect;
        final destRect = s['destRect'] as Rect;

        final Paint slicePaint;
        if (isFacing) {
          slicePaint = Paint()
            ..colorFilter = (light < 0.97 || light > 1.03)
                ? ColorFilter.matrix(<double>[
                    light, 0, 0, 0, 0,
                    0, light, 0, 0, 0,
                    0, 0, light * 0.98, 0, 0,
                    0, 0, 0, 1.0, 0,
                  ])
                : null;
        } else {
          // Shaded interior backing
          slicePaint = Paint()
            ..colorFilter = ColorFilter.matrix(<double>[
              0.48 * light, 0, 0, 0, 0,
              0, 0.38 * light, 0, 0, 0,
              0, 0, 0.24 * light, 0, 0,
              0, 0, 0, 0.95, 0,
            ]);
        }

        canvas.drawImageRect(img, srcRect, destRect, slicePaint);
      }

      final picture = recorder.endRecording();
      final renderedImg = await picture.toImage(400, 360);
      final byteData = await renderedImg.toByteData(format: ui.ImageByteFormat.png);
      final outBytes = byteData!.buffer.asUint8List();
      File('/Users/nandhakumar/.gemini/antigravity/brain/9d8e4d9b-b461-4a7b-96a6-6e732447b51f/new_crown_${entry.key}.png')
          .writeAsBytesSync(outBytes);
      print('Rendered: new_crown_${entry.key}.png');
    }
  });
}
