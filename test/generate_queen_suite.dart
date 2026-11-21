import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('generate authentic Queen rear and profile suite', () async {
    final file = File('assets/emojis/queen.png');
    final bytes = file.readAsBytesSync();
    final codec = await ui.instantiateImageCodec(bytes);
    final queenImg = (await codec.getNextFrame()).image;

    final w = queenImg.width.toDouble();
    final h = queenImg.height.toDouble();

    // ── 1. GENERATE QUEEN REAR (assets/emojis/queen_rear.png) ───────────────
    // Rear view shows:
    // - Background: Antique gold repousse backing of the arches and top star crest
    // - Midground: Rich crimson velvet cap dome
    // - Foreground: Continuous 24K gold base headband with ruby collets and pearl rails
    {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w, h));

      // A. Deep Crimson Velvet Cap in Background
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
            Color(0xFF8B1527),
            Color(0xFF5E0B19),
            Color(0xFF280308),
          ],
          stops: const [0.0, 0.50, 1.0],
        ).createShader(capRect);
      canvas.drawOval(capRect, capPaint);

      // B. Background Arches & Star Crest in Antique Gold Repousse
      canvas.save();
      final repousseFilter = ColorFilter.matrix(const <double>[
        0.45, 0.35, 0.10, 0, 18,
        0.35, 0.30, 0.08, 0, 12,
        0.15, 0.12, 0.05, 0, 2,
        0.00, 0.00, 0.00, 1.0, 0,
      ]);

      // Mirror horizontally
      canvas.translate(w, 0);
      canvas.scale(-1.0, 1.0);

      canvas.drawImage(
        queenImg,
        Offset.zero,
        Paint()
          ..filterQuality = FilterQuality.high
          ..isAntiAlias = true
          ..colorFilter = repousseFilter,
      );
      canvas.restore();

      // C. Cover front heart ruby area with velvet cap and rear vertical pearl arch
      final centerVelvetRect = Rect.fromCenter(
        center: Offset(w * 0.50, h * 0.56),
        width: w * 0.38,
        height: h * 0.40,
      );
      canvas.drawOval(
        centerVelvetRect,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(0.0, -0.25),
            radius: 0.85,
            colors: const [Color(0xFF8B1527), Color(0xFF5E0B19), Color(0xFF280308)],
            stops: const [0.0, 0.50, 1.0],
          ).createShader(centerVelvetRect),
      );

      // Rear vertical arch rising to top star
      final rearArch = Path()
        ..moveTo(w * 0.50 - 9, h * 0.76)
        ..lineTo(w * 0.50 - 6, h * 0.34)
        ..lineTo(w * 0.50 + 6, h * 0.34)
        ..lineTo(w * 0.50 + 9, h * 0.76)
        ..close();
      canvas.drawPath(
        rearArch,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFF7D6), Color(0xFFD4AF37), Color(0xFF6A4805)],
          ).createShader(Rect.fromLTWH(w * 0.5 - 10, h * 0.34, 20, h * 0.42)),
      );

      // Pearls on rear vertical arch
      for (double py = h * 0.38; py <= h * 0.74; py += 10.0) {
        final pt = Offset(w * 0.50, py);
        canvas.drawCircle(pt, 3.2, Paint()..color = Colors.white);
        canvas.drawCircle(
          pt,
          3.2,
          Paint()
            ..shader = RadialGradient(
              center: const Alignment(-0.35, -0.35),
              radius: 0.85,
              colors: const [Color(0xFFFFFFFF), Color(0xFFF7F2E8), Color(0xFFDDD5C7), Color(0xFFA69986)],
            ).createShader(Rect.fromCircle(center: pt, radius: 3.2)),
        );
        canvas.drawCircle(pt - const Offset(1.0, 1.0), 1.0, Paint()..color = Colors.white);
      }

      // D. Foreground Continuous 24K Gold Base Headband (y: 185 to 232)
      // Uses the authentic hand-crafted base band from queenImg
      const bandSrcRect = Rect.fromLTWH(12, 185, 232, 48);
      canvas.drawImageRect(
        queenImg,
        bandSrcRect,
        bandSrcRect,
        Paint()..filterQuality = FilterQuality.high,
      );

      final picture = recorder.endRecording();
      final rearImg = await picture.toImage(w.toInt(), h.toInt());
      final outBytes = await rearImg.toByteData(format: ui.ImageByteFormat.png);
      File('assets/emojis/queen_rear.png')
          .writeAsBytesSync(outBytes!.buffer.asUint8List());
      File('/Users/nandhakumar/.gemini/antigravity/brain/9d8e4d9b-b461-4a7b-96a6-6e732447b51f/queen_rear_master.png')
          .writeAsBytesSync(outBytes.buffer.asUint8List());
      print('Saved assets/emojis/queen_rear.png');
    }

    // ── 2. GENERATE QUEEN PROFILE (assets/emojis/queen_profile.png) ──────────
    // 90° Profile view shows:
    // - Full 3D width (zero gap!)
    // - Arch 2 in center foreground rising to the apex star
    // - Front and rear arches rising at the sides
    // - Deep crimson velvet cap dome filling the space
    // - Base headband curving in perspective
    {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w, h));

      // A. Velvet Cap
      final capRect = Rect.fromCenter(
        center: Offset(w * 0.50, h * 0.58),
        width: w * 0.62,
        height: h * 0.44,
      );
      canvas.drawOval(
        capRect,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.2, -0.2),
            radius: 0.85,
            colors: const [Color(0xFF8B1527), Color(0xFF5E0B19), Color(0xFF280308)],
            stops: const [0.0, 0.50, 1.0],
          ).createShader(capRect),
      );

      // B. Top Diamond Star Crest
      const starRect = Rect.fromLTWH(96, 26, 64, 64);
      canvas.drawImageRect(queenImg, starRect, starRect, Paint()..filterQuality = FilterQuality.high);

      // C. Left (Rear) and Right (Front) Arches
      const leftArchRect = Rect.fromLTWH(10, 68, 86, 128);
      const rightArchRect = Rect.fromLTWH(160, 68, 86, 128);
      canvas.drawImageRect(queenImg, leftArchRect, leftArchRect, Paint()..filterQuality = FilterQuality.high);
      canvas.drawImageRect(queenImg, rightArchRect, rightArchRect, Paint()..filterQuality = FilterQuality.high);

      // D. Central Side Arch (Arch 2) in Foreground (rising up the center)
      // Sample Arch 2 from queenImg (x: 170 to 240) and draw centered
      final centerArchPath = Path()
        ..moveTo(w * 0.50 - 18, h * 0.78)
        ..quadraticBezierTo(w * 0.50 - 24, h * 0.52, w * 0.50 - 8, h * 0.32)
        ..lineTo(w * 0.50 + 8, h * 0.32)
        ..quadraticBezierTo(w * 0.50 + 24, h * 0.52, w * 0.50 + 18, h * 0.78)
        ..close();

      canvas.drawPath(
        centerArchPath,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFF7D6), Color(0xFFD4AF37), Color(0xFF8B6508)],
          ).createShader(Rect.fromLTWH(w * 0.5 - 25, h * 0.32, 50, h * 0.46)),
      );

      // Arch 2 Center Rectangular Ruby Collet
      final rubyColletRect = Rect.fromCenter(center: Offset(w * 0.50, h * 0.52), width: 22, height: 26);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rubyColletRect.inflate(3), const Radius.circular(5)),
        Paint()..color = const Color(0xFFD4AF37),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rubyColletRect, const Radius.circular(3)),
        Paint()
          ..shader = const RadialGradient(
            center: Alignment(-0.3, -0.3),
            radius: 0.85,
            colors: [Color(0xFFFF5252), Color(0xFFC62828), Color(0xFF4A0007)],
            stops: [0.0, 0.50, 1.0],
          ).createShader(rubyColletRect),
      );
      // Diamond Specular
      canvas.drawCircle(
        rubyColletRect.center - const Offset(5, 5),
        4.0,
        Paint()..color = Colors.white.withValues(alpha: 0.88),
      );

      // Pearls running up the side arch
      for (double py = h * 0.35; py <= h * 0.75; py += 12.0) {
        if (py >= h * 0.46 && py <= h * 0.58) continue; // Skip ruby collet
        final pt1 = Offset(w * 0.50 - 12, py);
        final pt2 = Offset(w * 0.50 + 12, py);
        for (final pt in [pt1, pt2]) {
          canvas.drawCircle(pt, 3.2, Paint()..color = Colors.white);
          canvas.drawCircle(
            pt,
            3.2,
            Paint()
              ..shader = RadialGradient(
                center: const Alignment(-0.35, -0.35),
                radius: 0.85,
                colors: const [Color(0xFFFFFFFF), Color(0xFFF7F2E8), Color(0xFFDDD5C7), Color(0xFFA69986)],
              ).createShader(Rect.fromCircle(center: pt, radius: 3.2)),
          );
        }
      }

      // E. Continuous Base Headband in Foreground (y: 185 to 232)
      const bandSrcRect = Rect.fromLTWH(12, 185, 232, 48);
      canvas.drawImageRect(
        queenImg,
        bandSrcRect,
        bandSrcRect,
        Paint()..filterQuality = FilterQuality.high,
      );

      final picture = recorder.endRecording();
      final profImg = await picture.toImage(w.toInt(), h.toInt());
      final outBytes = await profImg.toByteData(format: ui.ImageByteFormat.png);
      File('assets/emojis/queen_profile.png')
          .writeAsBytesSync(outBytes!.buffer.asUint8List());
      File('/Users/nandhakumar/.gemini/antigravity/brain/9d8e4d9b-b461-4a7b-96a6-6e732447b51f/queen_profile_master.png')
          .writeAsBytesSync(outBytes.buffer.asUint8List());
      print('Saved assets/emojis/queen_profile.png');
    }
  });
}
