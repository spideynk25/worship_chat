import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('extract flawless continuous headband', () async {
    final bytes = File('assets/emojis/aura_elixiria_rear.png').readAsBytesSync();
    final codec = await ui.instantiateImageCodec(bytes);
    final image = (await codec.getNextFrame()).image;

    // Headband is precisely between y=515 and y=715, x=185 to x=839
    final w = 839 - 185;
    final h = 715 - 515;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));

    final srcRect = const Rect.fromLTWH(185, 515, 654, 200);
    final destRect = Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
    canvas.drawImageRect(image, srcRect, destRect, Paint()..filterQuality = FilterQuality.high);

    final picture = recorder.endRecording();
    final bandImg = await picture.toImage(w, h);
    final outBytes = await bandImg.toByteData(format: ui.ImageByteFormat.png);
    File('/Users/nandhakumar/.gemini/antigravity/brain/9d8e4d9b-b461-4a7b-96a6-6e732447b51f/extracted_headband.png')
        .writeAsBytesSync(outBytes!.buffer.asUint8List());
    print('Extracted headband: ${bandImg.width}x${bandImg.height}');
  });
}
