import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_chat/features/group/widgets/royal_3d_crown_widget.dart';

void main() {
  test('render live MultiAngleCrownPainter across crowns and angles', () async {
    final testCases = [
      {'name': 'queen', 'color': const Color(0xFFC62828)},
      {'name': 'demi_goddess', 'color': const Color(0xFFE1F5FE)},
      {'name': 'core_supreme', 'color': const Color(0xFFFFB300)},
      {'name': 'supreme_goddess', 'color': const Color(0xFF1565C0)},
      {'name': 'aura_elixiria', 'color': const Color(0xFFE5A93C)},
    ];

    final angles = [
      {'label': '0_front', 'yaw': 0.0},
      {'label': '60_3d', 'yaw': 1.05},
      {'label': '90_profile', 'yaw': 1.57},
      {'label': '180_back', 'yaw': math.pi},
    ];

    for (final tc in testCases) {
      final name = tc['name'] as String;
      final color = tc['color'] as Color;

      final frontFile = File('assets/emojis/$name.png');
      final frontBytes = frontFile.readAsBytesSync();
      final frontCodec = await ui.instantiateImageCodec(frontBytes);
      final frontImg = (await frontCodec.getNextFrame()).image;

      ui.Image? rearImg;
      final rearFile = File('assets/emojis/${name}_rear.png');
      if (rearFile.existsSync()) {
        final rb = rearFile.readAsBytesSync();
        final rc = await ui.instantiateImageCodec(rb);
        rearImg = (await rc.getNextFrame()).image;
      }

      ui.Image? profileImg;
      final profFile = File('assets/emojis/${name}_profile.png');
      if (profFile.existsSync()) {
        final pb = profFile.readAsBytesSync();
        final pc = await ui.instantiateImageCodec(pb);
        profileImg = (await pc.getNextFrame()).image;
      }

      for (final a in angles) {
        final label = a['label'] as String;
        final yaw = a['yaw'] as double;

        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 260, 240));

        final painter = MultiAngleCrownPainter(
          frontImage: frontImg,
          rearImage: rearImg,
          profileImage: profileImg,
          yaw: yaw,
          pitch: -0.15,
          glowColor: color,
        );

        painter.paint(canvas, const Size(260, 240));
        final picture = recorder.endRecording();
        final img = await picture.toImage(260, 240);
        final outBytes = await img.toByteData(format: ui.ImageByteFormat.png);

        final outPath = '/Users/nandhakumar/.gemini/antigravity/brain/9d8e4d9b-b461-4a7b-96a6-6e732447b51f/live_${name}_$label.png';
        File(outPath).writeAsBytesSync(outBytes!.buffer.asUint8List());
      }
      print('Rendered all angles for $name');
    }
  });
}
