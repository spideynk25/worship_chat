import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('generate authentic bespoke queen rear', () async {
    final file = File('assets/emojis/queen.png');
    final bytes = file.readAsBytesSync();
    final codec = await ui.instantiateImageCodec(bytes);
    final queenImg = (await codec.getNextFrame()).image;

    final w = queenImg.width;
    final h = queenImg.height;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));

    // 1. First, create the solid red velvet cap in the background (center x: 128, y: 150, width: 150, height: 110)
    final capRect = Rect.fromCenter(
      center: Offset(w * 0.50, h * 0.58),
      width: w * 0.62,
      height: h * 0.44,
    );
    final capPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.0, -0.2),
        radius: 0.85,
        colors: const [
          Color(0xFF8B1527), // Crimson velvet highlight
          Color(0xFF5E0B19), // Deep royal crimson
          Color(0xFF2E040B), // Velvet shadow
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(capRect);
    canvas.drawOval(capRect, capPaint);

    // 2. Draw the background arches and star crest:
    // Take queenImg, clip out the front heart jewel, and draw the arches & top star
    // The top star is at y = 25 to 85, x = 90 to 166.
    // The left arch is at x = 10 to 100, y = 70 to 190.
    // The right arch is at x = 156 to 246, y = 70 to 190.
    canvas.drawImage(
      queenImg,
      Offset.zero,
      Paint()..filterQuality = FilterQuality.high,
    );

    // 3. Now cover the FRONT heart ruby and pear diamond with the rich red velvet cap & rear central arch!
    // The front heart ruby and pear diamond are inside x: 86 to 170, y: 88 to 186.
    final coverRect = Rect.fromCenter(
      center: Offset(w * 0.50, h * 0.54),
      width: w * 0.36,
      height: h * 0.38,
    );
    final coverPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.0, -0.3),
        radius: 0.85,
        colors: const [
          Color(0xFF8B1527),
          Color(0xFF5E0B19),
          Color(0xFF2E040B),
        ],
        stops: const [0.0, 0.50, 1.0],
      ).createShader(coverRect);
    canvas.drawOval(coverRect, coverPaint);

    // Rear vertical arch rising up the back of the velvet cap to the apex star!
    // Real imperial crowns (like St Edward's or Imperial State Crown) have a gold arch with pearls rising up the back.
    final archPath = Path()
      ..moveTo(w * 0.50 - 10, h * 0.72)
      ..lineTo(w * 0.50 - 7, h * 0.32)
      ..lineTo(w * 0.50 + 7, h * 0.32)
      ..lineTo(w * 0.50 + 10, h * 0.72)
      ..close();

    final archPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: const [
          Color(0xFFFFF7D6),
          Color(0xFFD4AF37),
          Color(0xFF8B6508),
        ],
      ).createShader(Rect.fromLTWH(w * 0.5 - 12, h * 0.32, 24, h * 0.40));
    canvas.drawPath(archPath, archPaint);

    // Pearls rising along the rear arch
    void drawPearl(Offset c, double r) {
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.35, -0.35),
            radius: 0.85,
            colors: const [Color(0xFFFFFFFF), Color(0xFFE0D7C6), Color(0xFF9E917E)],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
      canvas.drawCircle(c - Offset(r * 0.3, r * 0.3), r * 0.3, Paint()..color = Colors.white);
    }

    for (double py = h * 0.36; py <= h * 0.70; py += 10.0) {
      drawPearl(Offset(w * 0.50, py), 3.2);
    }

    // 4. Draw the base headband in the foreground (y: 185 to 232)
    // Sample base band from queenImg
    const bandSrcRect = Rect.fromLTWH(10, 185, 236, 48);
    canvas.drawImageRect(
      queenImg,
      bandSrcRect,
      bandSrcRect,
      Paint()..filterQuality = FilterQuality.high,
    );

    final picture = recorder.endRecording();
    final rearImg = await picture.toImage(w, h);
    final outBytes = await rearImg.toByteData(format: ui.ImageByteFormat.png);

    final outPath = '/Users/nandhakumar/.gemini/antigravity/brain/9d8e4d9b-b461-4a7b-96a6-6e732447b51f/test_bespoke_queen_rear.png';
    File(outPath).writeAsBytesSync(outBytes!.buffer.asUint8List());
    print('Saved $outPath');
  });
}
