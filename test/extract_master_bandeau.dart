import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('inspect and extract master bandeau', () async {
    final bytes = File('assets/emojis/aura_elixiria_rear.png').readAsBytesSync();
    final codec = await ui.instantiateImageCodec(bytes);
    final image = (await codec.getNextFrame()).image;
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final raw = byteData!.buffer.asUint8List();

    print('Rear image: ${image.width}x${image.height}');

    // The bandeau is the curved headband in the lower-middle section
    // Let's create an extracted 1024x512 master bandeau asset:
    // Cropping from y=480 to y=880 (height 400), x=140 to x=884 (width 744)
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 1024, 480));

    // Draw the bandeau centered in 1024x480
    final srcRect = const Rect.fromLTWH(140, 480, 744, 400);
    final destRect = const Rect.fromLTWH(0, 0, 1024, 480);
    canvas.drawImageRect(image, srcRect, destRect, Paint()..filterQuality = FilterQuality.high);

    final picture = recorder.endRecording();
    final bandeauImg = await picture.toImage(1024, 480);
    final outBytes = await bandeauImg.toByteData(format: ui.ImageByteFormat.png);
    File('assets/emojis/royal_circlet_bandeau.png')
        .writeAsBytesSync(outBytes!.buffer.asUint8List());
    print('Saved assets/emojis/royal_circlet_bandeau.png');
  });
}
