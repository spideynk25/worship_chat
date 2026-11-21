import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_chat/features/group/widgets/royal_3d_crown_widget.dart';

void main() {
  test('render crown at angles', () async {
    // Load real asset aura_elixiria.png
    final assetFile = File('assets/emojis/aura_elixiria.png');
    final bytes = assetFile.readAsBytesSync();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final realImage = frame.image;

    final angles = {
      'front': (0.0, -0.15),
      'tilt_30': (0.52, -0.22),
      'angle_60': (1.05, -0.18),
      'profile_90': (math.pi / 2.0, -0.12),
      'back_180': (math.pi, -0.15),
    };

    for (final entry in angles.entries) {
      final yaw = entry.value.$1;
      final pitch = entry.value.$2;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 400, 360));

      // Draw background
      canvas.drawColor(const Color(0xFF0F0E17), BlendMode.src);

      final painter = VolumetricCrownPainter(
        image: realImage,
        rearImage: null,
        yaw: yaw,
        pitch: pitch,
        glowColor: const Color(0xFFE5A93C),
        enableBackWall: true,
        enableExtrusion: true,
        enableBaseRing: false,
        enableGlint: true,
        glintOffset: 0.0,
      );

      painter.paint(canvas, const Size(400, 360));
      final picture = recorder.endRecording();
      final img = await picture.toImage(400, 360);
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      final outBytes = byteData!.buffer.asUint8List();
      File('/Users/nandhakumar/.gemini/antigravity/brain/9d8e4d9b-b461-4a7b-96a6-6e732447b51f/crown_angle_${entry.key}.png')
          .writeAsBytesSync(outBytes);
      print('Saved crown_angle_${entry.key}.png');
    }
  });
}
