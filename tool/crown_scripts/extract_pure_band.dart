import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('extract pure headband without flowers or wings', () async {
    final file = File('assets/emojis/aura_elixiria_rear.png');
    final bytes = file.readAsBytesSync();
    final codec = await ui.instantiateImageCodec(bytes);
    final image = (await codec.getNextFrame()).image;

    // Crop rectangle:
    // Top pearl rail starts around y = 520, bottom rail ends around y = 680
    // Width is roughly x = 180 to 844
    const srcRect = Rect.fromLTWH(180, 520, 664, 165);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, srcRect.width, srcRect.height));

    canvas.drawImageRect(
      image,
      srcRect,
      Rect.fromLTWH(0, 0, srcRect.width, srcRect.height),
      Paint()..filterQuality = FilterQuality.high,
    );

    final picture = recorder.endRecording();
    final cropped = await picture.toImage(srcRect.width.toInt(), srcRect.height.toInt());
    final outBytes = await cropped.toByteData(format: ui.ImageByteFormat.png);

    final outPath = '/Users/nandhakumar/.gemini/antigravity/brain/9d8e4d9b-b461-4a7b-96a6-6e732447b51f/inspect_pure_band.png';
    File(outPath).writeAsBytesSync(outBytes!.buffer.asUint8List());
    print('Saved $outPath');
  });
}
