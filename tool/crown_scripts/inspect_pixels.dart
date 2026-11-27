import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('inspect aura_elixiria pixels', () async {
    final bytes = File('assets/emojis/aura_elixiria.png').readAsBytesSync();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final data = byteData!.buffer.asUint8List();

    print('Image size: ${image.width}x${image.height}');

    int minX = 999, maxX = -1, minY = 999, maxY = -1;
    for (int y = 0; y < 256; y++) {
      for (int x = 0; x < 256; x++) {
        final a = data[(y * 256 + x) * 4 + 3];
        if (a > 20) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }
    print('Global Bounding Box: X=[$minX, $maxX], Y=[$minY, $maxY]');

    for (int x in [minX, minX + 10, minX + 25, 64, 128, 192, maxX - 25, maxX - 10, maxX]) {
      int topY = -1, botY = -1;
      for (int y = 0; y < 256; y++) {
        final a = data[(y * 256 + x) * 4 + 3];
        if (a > 20) {
          if (topY == -1) topY = y;
          botY = y;
        }
      }
      print('Column X=$x: Y=[$topY, $botY]');
    }
  });
}
