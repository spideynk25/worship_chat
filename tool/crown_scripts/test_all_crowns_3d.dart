import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('test universal 3D crown rear and profile for all crowns', () async {
    // Load master rear bandeau from aura_elixiria_rear.png
    final masterRearBytes = File('assets/emojis/aura_elixiria_rear.png').readAsBytesSync();
    final masterRearCodec = await ui.instantiateImageCodec(masterRearBytes);
    final masterRearImage = (await masterRearCodec.getNextFrame()).image;

    // We can extract just the bandeau portion of masterRearImage
    // In aura_elixiria_rear.png (1024x1024), the bandeau is from y=480 to y=820, x=140 to x=884
    print('Master rear image: ${masterRearImage.width}x${masterRearImage.height}');

    final crownsToTest = {
      'queen': const Color(0xFFD81B60),
      'demi_goddess': const Color(0xFFF39C12),
      'core_supreme': const Color(0xFF4A90E2),
      'supreme_goddess': const Color(0xFFE74C3C),
      'golden_blossom': const Color(0xFFE67E22),
      'elfwitch': const Color(0xFF27AE60),
    };

    const size = Size(260, 240);
    final cx = size.width / 2.0;
    final cy = size.height / 2.0;

    for (final entry in crownsToTest.entries) {
      final name = entry.key;
      final accentColor = entry.value;

      final file = File('assets/emojis/$name.png');
      if (!file.existsSync()) continue;

      final bytes = file.readAsBytesSync();
      final codec = await ui.instantiateImageCodec(bytes);
      final frontImage = (await codec.getNextFrame()).image;

      // Render 180° BACK view
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size.width, size.height));
      canvas.drawColor(const Color(0xFF0F0E17), BlendMode.src);

      // 1. Velvet floor
      final floorPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            accentColor.withValues(alpha: 0.25),
            const Color(0xFF0F0E17),
          ],
        ).createShader(Rect.fromCenter(
          center: Offset(cx, cy + size.height * 0.32),
          width: size.width * 0.70,
          height: size.height * 0.22,
        ));
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx, cy + size.height * 0.32),
          width: size.width * 0.70,
          height: size.height * 0.22,
        ),
        floorPaint,
      );

      // Plinth
      final plinthBorder = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = accentColor.withValues(alpha: 0.65);
      canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, size.height - 24), width: 170, height: 26),
        plinthBorder,
      );

      // 2. BACKGROUND: Reverse side of front crest (Antique Gold Repousse Backing)
      const pitch = -0.15;
      const yaw = math.pi; // 180°

      canvas.save();
      final bgTransform = Matrix4.identity()
        ..setEntry(3, 2, 0.0018)
        ..translate(cx, cy - size.height * 0.04, 0.0)
        ..scale(0.92, 0.92, 1.0)
        ..rotateX(pitch)
        ..translate(-cx, -cy + size.height * 0.04, 0.0);
      canvas.transform(bgTransform.storage);

      final bgDestRect = Rect.fromCenter(
        center: Offset(cx, cy - size.height * 0.04),
        width: size.width * 0.82,
        height: size.height * 0.82,
      );

      // Antique gold matrix: turns front illustration into rich, shadowed antique cast gold
      final antiqueGoldPaint = Paint()
        ..filterQuality = FilterQuality.high
        ..isAntiAlias = true
        ..colorFilter = const ColorFilter.matrix(<double>[
          0.44, 0, 0, 0, 0,
          0, 0.33, 0, 0, 0,
          0, 0, 0.18, 0, 0,
          0, 0, 0, 0.95, 0,
        ]);

      canvas.drawImageRect(
        frontImage,
        Rect.fromLTWH(0, 0, frontImage.width.toDouble(), frontImage.height.toDouble()),
        bgDestRect,
        antiqueGoldPaint,
      );
      canvas.restore();

      // 3. FOREGROUND: Continuous Master Royal Bandeau with Pearl Rails & Gem Solitaire
      canvas.save();
      final fgTransform = Matrix4.identity()
        ..setEntry(3, 2, 0.0018)
        ..translate(cx, cy + size.height * 0.12, 0.0)
        ..rotateX(pitch * 0.6)
        ..translate(-cx, -cy - size.height * 0.12, 0.0);
      canvas.transform(fgTransform.storage);

      // Source rectangle of the bandeau in aura_elixiria_rear.png
      // In aura_elixiria_rear.png: y from 490 to 820, x from 160 to 864
      final bandSrcRect = Rect.fromLTWH(
        160,
        490,
        masterRearImage.width.toDouble() - 320,
        330,
      );

      // Width and height of foreground bandeau
      final bandDestRect = Rect.fromCenter(
        center: Offset(cx, cy + size.height * 0.14),
        width: size.width * 0.80,
        height: size.height * 0.36,
      );

      // Tint gems of the bandeau to match the crown's accent color (e.g. ruby for queen, emerald for elfwitch)
      final bandPaint = Paint()
        ..filterQuality = FilterQuality.high
        ..isAntiAlias = true;

      // Color filter that preserves the 24K gold and pearls while tinting the gems to accentColor
      bandPaint.colorFilter = ColorFilter.mode(
        accentColor.withValues(alpha: 0.22),
        BlendMode.color,
      );

      canvas.drawImageRect(
        masterRearImage,
        bandSrcRect,
        bandDestRect,
        bandPaint,
      );
      canvas.restore();

      final picture = recorder.endRecording();
      final img = await picture.toImage(size.width.toInt(), size.height.toInt());
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      File('/Users/nandhakumar/.gemini/antigravity/brain/9d8e4d9b-b461-4a7b-96a6-6e732447b51f/test_universal_back_$name.png')
          .writeAsBytesSync(byteData!.buffer.asUint8List());
      print('Saved: test_universal_back_$name.png');
    }
  });
}
