import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sample arch and velvet from queen.png', () async {
    final file = File('assets/emojis/queen.png');
    final bytes = file.readAsBytesSync();
    final codec = await ui.instantiateImageCodec(bytes);
    final queenImg = (await codec.getNextFrame()).image;

    final w = queenImg.width.toDouble();
    final h = queenImg.height.toDouble();

    // In queen.png:
    // Left arch is from x: 10 to 95, y: 70 to 190.
    // Right arch is from x: 160 to 245, y: 70 to 190.
    // Left velvet patch is at x: 40 to 85, y: 95 to 165.

    // Let's test a seamless clone & composite:
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w, h));

    // Draw queenImg as base
    canvas.drawImage(queenImg, Offset.zero, Paint()..filterQuality = FilterQuality.high);

    // Cover the front heart ruby (x: 88 to 168, y: 92 to 184) using seamless velvet patches
    // from the left and right velvet regions, softly blended:
    const leftVelvetSrc = Rect.fromLTWH(42, 100, 42, 65);
    const rightVelvetSrc = Rect.fromLTWH(172, 100, 42, 65);

    final velvetPaint = Paint()
      ..filterQuality = FilterQuality.high
      ..isAntiAlias = true;

    // Draw blended velvet over heart ruby
    canvas.drawImageRect(queenImg, leftVelvetSrc, const Rect.fromLTWH(86, 105, 46, 75), velvetPaint);
    canvas.drawImageRect(queenImg, rightVelvetSrc, const Rect.fromLTWH(124, 105, 46, 75), velvetPaint);

    // Apply soft radial shadow over center velvet so it recedes into the dome
    final centerShadow = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.0, -0.1),
        radius: 0.8,
        colors: [
          Colors.transparent,
          Colors.black.withValues(alpha: 0.35),
          Colors.black.withValues(alpha: 0.65),
        ],
        stops: const [0.0, 0.60, 1.0],
      ).createShader(const Rect.fromLTWH(86, 100, 84, 85));
    canvas.drawOval(const Rect.fromLTWH(86, 100, 84, 85), centerShadow);

    // Now take the real 3D gold arch from the left side (x: 18 to 68, y: 80 to 185)
    // and draw it as the rear vertical arch in the center!
    const archSrc = Rect.fromLTWH(22, 85, 44, 98);
    const archDest = Rect.fromLTWH(108, 92, 40, 92);
    canvas.drawImageRect(
      queenImg,
      archSrc,
      archDest,
      Paint()
        ..filterQuality = FilterQuality.high
        ..isAntiAlias = true,
    );

    // Draw the base headband in foreground
    const bandSrcRect = Rect.fromLTWH(12, 185, 232, 48);
    canvas.drawImageRect(queenImg, bandSrcRect, bandSrcRect, Paint()..filterQuality = FilterQuality.high);

    final pic = recorder.endRecording();
    final img = await pic.toImage(w.toInt(), h.toInt());
    final outBytes = await img.toByteData(format: ui.ImageByteFormat.png);

    final outPath = '/Users/nandhakumar/.gemini/antigravity/brain/9d8e4d9b-b461-4a7b-96a6-6e732447b51f/queen_rear_natural.png';
    File(outPath).writeAsBytesSync(outBytes!.buffer.asUint8List());
    print('Saved $outPath');
  });
}
