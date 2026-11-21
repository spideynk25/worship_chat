import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('create authentic queen rear and profile', () async {
    final bytes = File('assets/emojis/queen.png').readAsBytesSync();
    final codec = await ui.instantiateImageCodec(bytes);
    final image = (await codec.getNextFrame()).image;

    final w = image.width.toDouble();
    final h = image.height.toDouble();

    // Queen rear:
    // When viewed from behind, the rear of Queen's crown shows:
    // 1. The velvet cap and arches (same as front, but the center heart ruby is the back setting)
    // 2. The rear band with matching ruby and pearls.
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w, h));

    // Draw base front image
    canvas.drawImage(image, Offset.zero, Paint()..filterQuality = FilterQuality.high);

    // In the center of Queen's crown (x: 100..156, y: 110..175) is the front heart ruby.
    // In the back of an imperial crown, the central arch has an antique gold fleur-de-lis setting
    // and red velvet cap behind it, with a square ruby in the band below.
    // We can sample the side arch/velvet from x=60..100 and x=156..196 to cover the front heart:
    final sideArchRect = Rect.fromLTWH(w * 0.22, h * 0.40, w * 0.18, h * 0.28);
    final centerHeartRect = Rect.fromCenter(center: Offset(w * 0.50, h * 0.54), width: w * 0.28, height: h * 0.24);

    // Draw antique gold backing over the front heart jewel to represent the interior gold mounting
    final backingPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF6A1B29), // Deep velvet shadow
          const Color(0xFF8B6508), // Antique gold bezel backing
          const Color(0xFF5A3E08),
        ],
        stops: const [0.0, 0.65, 1.0],
      ).createShader(centerHeartRect);
    canvas.drawOval(centerHeartRect, backingPaint);

    // Center fleur-de-lis gold repousse mount
    final mountPaint = Paint()
      ..color = const Color(0xFFD4AF37)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawOval(centerHeartRect.deflate(4), mountPaint);

    // Center ruby on rear band: Rectangular ruby bezel at (w*0.5, h*0.83)
    final rubyRect = Rect.fromCenter(center: Offset(w * 0.50, h * 0.83), width: w * 0.16, height: h * 0.085);
    final rubyPaint = Paint()
      ..shader = const RadialGradient(
        colors: [
          Color(0xFFFF5252),
          Color(0xFFB71C1C),
          Color(0xFF4A0007),
        ],
        stops: [0.0, 0.60, 1.0],
      ).createShader(rubyRect);
    canvas.drawRRect(RRect.fromRectAndRadius(rubyRect, const Radius.circular(3)), rubyPaint);
    canvas.drawRRect(RRect.fromRectAndRadius(rubyRect, const Radius.circular(3)), Paint()..color = const Color(0xFFFFD54F)..style = PaintingStyle.stroke..strokeWidth = 1.2);

    final picture = recorder.endRecording();
    final rearImg = await picture.toImage(w.toInt(), h.toInt());
    final outBytes = await rearImg.toByteData(format: ui.ImageByteFormat.png);
    File('assets/emojis/queen_rear.png')
        .writeAsBytesSync(outBytes!.buffer.asUint8List());
    print('Saved assets/emojis/queen_rear.png');
  });
}
