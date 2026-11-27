import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Renders a multi-angle 3D crown view with smooth angle interpolation,
/// 3D perspective transform, directional vault lighting, and velvet plinth.
void main() {
  test('render multi-angle 3D crown vault views', () async {
    final frontBytes = File('assets/emojis/aura_elixiria.png').readAsBytesSync();
    final frontCodec = await ui.instantiateImageCodec(frontBytes);
    final frontImage = (await frontCodec.getNextFrame()).image;

    final rearBytes = File('assets/emojis/aura_elixiria_rear.png').readAsBytesSync();
    final rearCodec = await ui.instantiateImageCodec(rearBytes);
    final rearImage = (await rearCodec.getNextFrame()).image;

    final profileBytes = File('assets/emojis/aura_elixiria_profile.png').readAsBytesSync();
    final profileCodec = await ui.instantiateImageCodec(profileBytes);
    final profileImage = (await profileCodec.getNextFrame()).image;

    final testAngles = {
      '0_front': (0.0, -0.15),
      '30_tilt': (0.52, -0.20),
      '60_3d': (1.05, -0.16),
      '90_profile': (math.pi / 2.0, -0.12),
      '180_back': (math.pi, -0.15),
      'minus_90_left': (-math.pi / 2.0, -0.12),
    };

    const size = Size(260, 240);
    final cx = size.width / 2.0;
    final cy = size.height / 2.0;

    for (final entry in testAngles.entries) {
      final yaw = entry.value.$1;
      final pitch = entry.value.$2;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size.width, size.height));

      // Draw background
      canvas.drawColor(const Color(0xFF0F0E17), BlendMode.src);

      // Exhibition Plinth (Bottom floor)
      final plinthPaint = Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFF221F30), Color(0xFF0F0E17)],
        ).createShader(Rect.fromCenter(
          center: Offset(cx, size.height - 24),
          width: 170,
          height: 26,
        ));
      canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, size.height - 24), width: 170, height: 26),
        plinthPaint,
      );
      final plinthBorder = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0xFFE5A93C).withValues(alpha: 0.65);
      canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, size.height - 24), width: 170, height: 26),
        plinthBorder,
      );

      // Normalize yaw to [-pi, pi]
      double normYaw = yaw % (math.pi * 2.0);
      if (normYaw > math.pi) normYaw -= math.pi * 2.0;
      if (normYaw < -math.pi) normYaw += math.pi * 2.0;

      // Select active cardinal view and local offset angle
      ui.Image activeImage;
      bool flipHorizontal = false;
      double localYawOffset = 0.0;

      if (normYaw.abs() <= math.pi * 0.28) {
        // Front zone (-50° to +50°)
        activeImage = frontImage;
        localYawOffset = normYaw;
      } else if (normYaw.abs() >= math.pi * 0.72) {
        // Rear zone (130° to 180° / -130° to -180°)
        activeImage = rearImage;
        localYawOffset = normYaw > 0 ? (normYaw - math.pi) : (normYaw + math.pi);
      } else if (normYaw > 0) {
        // Right Profile zone (50° to 130°)
        activeImage = profileImage;
        localYawOffset = normYaw - math.pi * 0.50;
      } else {
        // Left Profile zone (-50° to -130°)
        activeImage = profileImage;
        flipHorizontal = true;
        localYawOffset = normYaw + math.pi * 0.50;
      }

      // Compute directional vault lighting
      final cosLight = math.cos(normYaw);
      final light = (0.85 + 0.15 * cosLight - 0.10 * math.sin(normYaw)).clamp(0.70, 1.15);

      final imagePaint = Paint()
        ..filterQuality = FilterQuality.high
        ..isAntiAlias = true;

      if (light < 0.98 || light > 1.02) {
        imagePaint.colorFilter = ColorFilter.matrix(<double>[
          light, 0, 0, 0, 0,
          0, light, 0, 0, 0,
          0, 0, light * 0.98, 0, 0,
          0, 0, 0, 1.0, 0,
        ]);
      }

      // 3D Perspective Matrix Transformation
      canvas.save();
      final transform = Matrix4.identity()
        ..setEntry(3, 2, 0.0018)
        ..translate(cx, cy - 8.0, 0.0)
        ..rotateY(localYawOffset)
        ..rotateX(pitch)
        ..translate(-cx, -cy + 8.0, 0.0);

      canvas.transform(transform.storage);

      // Draw active image centered
      const drawW = 205.0;
      const drawH = 205.0;
      final destRect = Rect.fromCenter(
        center: Offset(cx, cy - 8.0),
        width: drawW,
        height: drawH,
      );

      if (flipHorizontal) {
        canvas.save();
        canvas.translate(cx, cy);
        canvas.scale(-1.0, 1.0);
        canvas.translate(-cx, -cy);
      }

      canvas.drawImageRect(
        activeImage,
        Rect.fromLTWH(0, 0, activeImage.width.toDouble(), activeImage.height.toDouble()),
        destRect,
        imagePaint,
      );

      if (flipHorizontal) {
        canvas.restore();
      }

      canvas.restore();

      final picture = recorder.endRecording();
      final img = await picture.toImage(size.width.toInt(), size.height.toInt());
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      File('/Users/nandhakumar/.gemini/antigravity/brain/9d8e4d9b-b461-4a7b-96a6-6e732447b51f/vault_test_${entry.key}.png')
          .writeAsBytesSync(byteData!.buffer.asUint8List());
      print('Saved: vault_test_${entry.key}.png');
    }
  });
}
