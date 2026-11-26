import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_chat/features/group/widgets/cylinder_crown_painter.dart';

void main() {
  test('inspect back of all crowns', () async {
    final crownNames = [
      'queen',
      'core_supreme',
      'supreme_goddess',
      'golden_blossom',
      'goddess',
      'demi_goddess',
      'elfwitch',
      'first_born_princess',
      'second_born_princess',
      'third_born_princess',
    ];

    const size = Size(260, 240);
    final cx = size.width / 2.0;
    final cy = size.height / 2.0;

    for (final name in crownNames) {
      final file = File('assets/emojis/$name.png');
      if (!file.existsSync()) continue;

      final bytes = file.readAsBytesSync();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;

      final rearAsset = CrownImageCache.getRearPath('assets/emojis/$name.png');
      final profileAsset = CrownImageCache.getProfilePath('assets/emojis/$name.png');
      ui.Image? rearImage;
      ui.Image? profileImage;

      if (rearAsset != null && File(rearAsset).existsSync()) {
        final rBytes = File(rearAsset).readAsBytesSync();
        final rCodec = await ui.instantiateImageCodec(rBytes);
        rearImage = (await rCodec.getNextFrame()).image;
      }
      if (profileAsset != null && File(profileAsset).existsSync()) {
        final pBytes = File(profileAsset).readAsBytesSync();
        final pCodec = await ui.instantiateImageCodec(pBytes);
        profileImage = (await pCodec.getNextFrame()).image;
      }

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size.width, size.height));
      canvas.drawColor(const Color(0xFF0F0E17), BlendMode.src);

      final painter = CylinderCrownPainter(
        frontImage: image,
        rearImage: rearImage,
        yaw: math.pi, // 180° BACK
        pitch: -0.15,
        glowColor: const Color(0xFFE5A93C),
      );

      painter.paint(canvas, size);

      final picture = recorder.endRecording();
      final img = await picture.toImage(size.width.toInt(), size.height.toInt());
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      File('/Users/nandhakumar/.gemini/antigravity/brain/9d8e4d9b-b461-4a7b-96a6-6e732447b51f/inspect_back_$name.png')
          .writeAsBytesSync(byteData!.buffer.asUint8List());
      print('Saved: inspect_back_$name.png');
    }
  });
}
