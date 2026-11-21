import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('feathered seamless clone for queen rear', () async {
    final file = File('assets/emojis/queen.png');
    final bytes = file.readAsBytesSync();
    final codec = await ui.instantiateImageCodec(bytes);
    final queenImg = (await codec.getNextFrame()).image;

    final w = queenImg.width.toDouble();
    final h = queenImg.height.toDouble();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w, h));

    // 1. Draw base crown
    canvas.drawImage(queenImg, Offset.zero, Paint()..filterQuality = FilterQuality.high);

    // 2. We want to seamlessly remove the front heart ruby (center x: 128, y: 138, radius: 36)
    // and replace it with the continuous red velvet cap and the rear arch!
    // In queen.png:
    // Notice that at x: 45 to 80, y: 100 to 160 is pure red velvet.
    // At x: 175 to 210, y: 100 to 160 is pure red velvet.
    // Let's create a feathered patch of that velvet and draw it over the heart ruby:
    final patchRecorder = ui.PictureRecorder();
    final patchCanvas = Canvas(patchRecorder, const Rect.fromLTWH(0, 0, 90, 90));

    // Draw velvet from left side
    patchCanvas.drawImageRect(
      queenImg,
      const Rect.fromLTWH(40, 100, 40, 60),
      const Rect.fromLTWH(0, 0, 90, 90),
      Paint()..filterQuality = FilterQuality.high,
    );

    // Feather with radial alpha mask using dstIn
    final maskPaint = Paint()
      ..blendMode = BlendMode.dstIn
      ..shader = const RadialGradient(
        colors: [Colors.black, Colors.black, Colors.transparent],
        stops: [0.0, 0.55, 1.0],
      ).createShader(const Rect.fromLTWH(0, 0, 90, 90));
    patchCanvas.drawRect(const Rect.fromLTWH(0, 0, 90, 90), maskPaint);

    final patchPic = patchRecorder.endRecording();
    final velvetPatch = await patchPic.toImage(90, 90);

    // Draw the feathered velvet patch centered right over the heart ruby (x: 128 - 45 = 83, y: 136 - 45 = 91)
    canvas.drawImage(velvetPatch, const Offset(83, 91), Paint()..filterQuality = FilterQuality.high);
    // Draw once more slightly offset to ensure full coverage of heart ruby
    canvas.drawImage(velvetPatch, const Offset(83, 98), Paint()..filterQuality = FilterQuality.high);

    // 3. Now draw the real 3D gold arch from the left side (x: 24 to 64, y: 80 to 180)
    // with feathered left/right edges so it rises naturally up the center of the velvet!
    final archRecorder = ui.PictureRecorder();
    final archCanvas = Canvas(archRecorder, const Rect.fromLTWH(0, 0, 48, 100));

    // Sample arch from queenImg
    archCanvas.drawImageRect(
      queenImg,
      const Rect.fromLTWH(24, 82, 42, 98),
      const Rect.fromLTWH(0, 0, 48, 100),
      Paint()..filterQuality = FilterQuality.high,
    );

    // Feather top and bottom
    final archMask = Paint()
      ..blendMode = BlendMode.dstIn
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent],
        stops: [0.0, 0.15, 0.85, 1.0],
      ).createShader(const Rect.fromLTWH(0, 0, 48, 100));
    archCanvas.drawRect(const Rect.fromLTWH(0, 0, 48, 100), archMask);

    final archPic = archRecorder.endRecording();
    final archPatch = await archPic.toImage(48, 100);

    // Draw arch patch in center
    canvas.drawImage(archPatch, const Offset(104, 86), Paint()..filterQuality = FilterQuality.high);

    // 4. Foreground: Base headband (y: 184 to 232)
    const bandSrcRect = Rect.fromLTWH(10, 184, 236, 48);
    canvas.drawImageRect(queenImg, bandSrcRect, bandSrcRect, Paint()..filterQuality = FilterQuality.high);

    final pic = recorder.endRecording();
    final img = await pic.toImage(w.toInt(), h.toInt());
    final outBytes = await img.toByteData(format: ui.ImageByteFormat.png);

    final outPath = '/Users/nandhakumar/.gemini/antigravity/brain/9d8e4d9b-b461-4a7b-96a6-6e732447b51f/queen_rear_feathered.png';
    File(outPath).writeAsBytesSync(outBytes!.buffer.asUint8List());
    print('Saved $outPath');
  });
}
