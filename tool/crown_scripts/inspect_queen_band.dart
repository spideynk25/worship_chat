import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('inspect queen.png base band', () async {
    final file = File('assets/emojis/queen.png');
    final bytes = file.readAsBytesSync();
    final codec = await ui.instantiateImageCodec(bytes);
    final image = (await codec.getNextFrame()).image;

    print('queen.png size: ${image.width}x${image.height}');

    // Let's crop just the base band: y = 190 to 230, x = 20 to 236
    const rect = Rect.fromLTWH(20, 190, 216, 40);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, rect.width, rect.height));
    canvas.drawImageRect(image, rect, Rect.fromLTWH(0, 0, rect.width, rect.height), Paint());
    final pic = recorder.endRecording();
    final cropped = await pic.toImage(rect.width.toInt(), rect.height.toInt());
    final outBytes = await cropped.toByteData(format: ui.ImageByteFormat.png);

    final outPath = '/Users/nandhakumar/.gemini/antigravity/brain/9d8e4d9b-b461-4a7b-96a6-6e732447b51f/queen_base_band.png';
    File(outPath).writeAsBytesSync(outBytes!.buffer.asUint8List());
    print('Saved $outPath');
  });
}
