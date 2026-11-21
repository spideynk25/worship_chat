import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('test refined crown rendering', () async {
    final assetFile = File('assets/emojis/aura_elixiria.png');
    final bytes = assetFile.readAsBytesSync();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;

    final imgW = image.width.toDouble();
    final imgH = image.height.toDouble();

    // Generate bespoke rear band texture
    final rearRecorder = ui.PictureRecorder();
    final rearCanvas = Canvas(rearRecorder, const Rect.fromLTWH(0, 0, 512, 128));
    
    // Draw 24K gold headband
    const highlightGold = Color(0xFFFFF7D6);
    const brightGold = Color(0xFFFFE28A);
    const richGold = Color(0xFFE5B03C);
    const deepGold = Color(0xFFB8860B);
    const antiqueGold = Color(0xFF7A5408);
    const shadowBronze = Color(0xFF382303);

    final bandRect = const Rect.fromLTWH(0, 20, 512, 88);
    final bandPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [highlightGold, brightGold, richGold, deepGold, antiqueGold, shadowBronze],
        stops: [0.0, 0.15, 0.40, 0.70, 0.90, 1.0],
      ).createShader(bandRect);
    rearCanvas.drawRect(bandRect, bandPaint);

    // Beaded pearl rails (top and bottom)
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

    for (double px = 8.0; px <= 504.0; px += 14.0) {
      drawPearl(Offset(px, 28), 4.5);
      drawPearl(Offset(px, 100), 4.5);
    }

    // Bevel borders
    final bevelPaint = Paint()
      ..color = highlightGold
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    rearCanvas.drawLine(const Offset(0, 20), const Offset(512, 20), bevelPaint);
    final botBevel = Paint()
      ..color = shadowBronze
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    rearCanvas.drawLine(const Offset(0, 108), const Offset(512, 108), botBevel);

    // Gemstones on rear band
    void drawGem(Rect rect, Color gemColor, {bool isOval = true}) {
      final bezelPaint = Paint()..color = brightGold;
      if (isOval) {
        rearCanvas.drawOval(rect.inflate(4), bezelPaint);
      } else {
        rearCanvas.drawRRect(RRect.fromRectAndRadius(rect.inflate(4), const Radius.circular(3)), bezelPaint);
      }
      final gemPaint = Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.3),
          radius: 0.9,
          colors: [
            Color.lerp(gemColor, Colors.white, 0.45)!,
            gemColor,
            Color.lerp(gemColor, Colors.black, 0.65)!,
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(rect);
      if (isOval) {
        rearCanvas.drawOval(rect, gemPaint);
      } else {
        rearCanvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(2)), gemPaint);
      }
      // Facet glare
      final glarePaint = Paint()..color = Colors.white.withValues(alpha: 0.9);
      rearCanvas.drawCircle(rect.center - Offset(rect.width * 0.2, rect.height * 0.2), 2.0, glarePaint);
    }

    // Center Back Solitaire Sapphire (X = 256, Y = 64)
    drawGem(Rect.fromCenter(center: const Offset(256, 64), width: 36, height: 26), const Color(0xFF1976D2), isOval: true);
    // Flanking Emeralds (X = 140, 372)
    drawGem(Rect.fromCenter(center: const Offset(140, 64), width: 22, height: 22), const Color(0xFF0F6E38), isOval: false);
    drawGem(Rect.fromCenter(center: const Offset(372, 64), width: 22, height: 22), const Color(0xFF0F6E38), isOval: false);
    // Lateral Amethysts (X = 50, 462)
    drawGem(Rect.fromCenter(center: const Offset(50, 64), width: 18, height: 18), const Color(0xFF8E24AA), isOval: true);
    drawGem(Rect.fromCenter(center: const Offset(462, 64), width: 18, height: 18), const Color(0xFF8E24AA), isOval: true);

    final rearPicture = rearRecorder.endRecording();
    final rearTexture = await rearPicture.toImage(512, 128);

    print('Generated rear texture: ${rearTexture.width}x${rearTexture.height}');
  });
}
