import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('perfect 4-way feathered clone for queen rear and profile', () async {
    final file = File('assets/emojis/queen.png');
    final bytes = file.readAsBytesSync();
    final codec = await ui.instantiateImageCodec(bytes);
    final queenImg = (await codec.getNextFrame()).image;

    final w = queenImg.width.toDouble();
    final h = queenImg.height.toDouble();

    // ── 1. PERFECT QUEEN REAR ───────────────────────────────────────────────
    {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w, h));

      // Draw base crown
      canvas.drawImage(queenImg, Offset.zero, Paint()..filterQuality = FilterQuality.high);

      // Velvet patch to cover the heart ruby
      final velvetPatchRec = ui.PictureRecorder();
      final vCanvas = Canvas(velvetPatchRec, const Rect.fromLTWH(0, 0, 100, 100));
      vCanvas.drawImageRect(
        queenImg,
        const Rect.fromLTWH(42, 100, 42, 60),
        const Rect.fromLTWH(0, 0, 100, 100),
        Paint()..filterQuality = FilterQuality.high,
      );
      vCanvas.drawRect(
        const Rect.fromLTWH(0, 0, 100, 100),
        Paint()
          ..blendMode = BlendMode.dstIn
          ..shader = const RadialGradient(
            radius: 0.85,
            colors: [Colors.black, Colors.black, Colors.transparent],
            stops: [0.0, 0.50, 1.0],
          ).createShader(const Rect.fromLTWH(0, 0, 100, 100)),
      );
      final velvetImg = await (velvetPatchRec.endRecording()).toImage(100, 100);

      // Stamp velvet patch smoothly over front heart
      canvas.drawImage(velvetImg, const Offset(78, 88), Paint()..filterQuality = FilterQuality.high);
      canvas.drawImage(velvetImg, const Offset(78, 96), Paint()..filterQuality = FilterQuality.high);

      // Arch patch: Soft radial/elliptical feather on all sides
      final archRec = ui.PictureRecorder();
      final aCanvas = Canvas(archRec, const Rect.fromLTWH(0, 0, 48, 100));
      aCanvas.drawImageRect(
        queenImg,
        const Rect.fromLTWH(26, 84, 40, 94),
        const Rect.fromLTWH(0, 0, 48, 100),
        Paint()..filterQuality = FilterQuality.high,
      );
      aCanvas.drawRect(
        const Rect.fromLTWH(0, 0, 48, 100),
        Paint()
          ..blendMode = BlendMode.dstIn
          ..shader = const RadialGradient(
            center: Alignment(0.0, 0.0),
            radius: 0.85,
            colors: [Colors.black, Colors.black, Colors.transparent],
            stops: [0.0, 0.65, 1.0],
          ).createShader(const Rect.fromLTWH(0, 0, 48, 100)),
      );
      final archImg = await (archRec.endRecording()).toImage(48, 100);

      // Draw arch centered at x: 104, y: 88
      canvas.drawImage(archImg, const Offset(104, 88), Paint()..filterQuality = FilterQuality.high);

      // Foreground base headband
      const bandSrcRect = Rect.fromLTWH(10, 184, 236, 48);
      canvas.drawImageRect(queenImg, bandSrcRect, bandSrcRect, Paint()..filterQuality = FilterQuality.high);

      final pic = recorder.endRecording();
      final rear = await pic.toImage(w.toInt(), h.toInt());
      final outBytes = await rear.toByteData(format: ui.ImageByteFormat.png);

      File('assets/emojis/queen_rear.png')
          .writeAsBytesSync(outBytes!.buffer.asUint8List());
      File('/Users/nandhakumar/.gemini/antigravity/brain/9d8e4d9b-b461-4a7b-96a6-6e732447b51f/queen_rear_perfect.png')
          .writeAsBytesSync(outBytes.buffer.asUint8List());
      print('Saved queen_rear.png');
    }

    // ── 2. PERFECT QUEEN PROFILE ────────────────────────────────────────────
    // Profile view of Queen crown:
    // Side view has:
    // - Full width across base (zero gap!)
    // - Central Arch 2 rising up to the star crest
    // - Front and rear arches on the sides
    // - Velvet cap in the middle
    // - Continuous base band
    {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w, h));

      // Draw Queen base
      canvas.drawImage(queenImg, Offset.zero, Paint()..filterQuality = FilterQuality.high);

      // Draw Arch 2 (x: 165 to 235, y: 75 to 185) into center foreground with feathering
      final arch2Rec = ui.PictureRecorder();
      final a2Canvas = Canvas(arch2Rec, const Rect.fromLTWH(0, 0, 56, 110));
      a2Canvas.drawImageRect(
        queenImg,
        const Rect.fromLTWH(175, 78, 48, 105),
        const Rect.fromLTWH(0, 0, 56, 110),
        Paint()..filterQuality = FilterQuality.high,
      );
      a2Canvas.drawRect(
        const Rect.fromLTWH(0, 0, 56, 110),
        Paint()
          ..blendMode = BlendMode.dstIn
          ..shader = const RadialGradient(
            radius: 0.85,
            colors: [Colors.black, Colors.black, Colors.transparent],
            stops: [0.0, 0.65, 1.0],
          ).createShader(const Rect.fromLTWH(0, 0, 56, 110)),
      );
      final arch2Img = await (arch2Rec.endRecording()).toImage(56, 110);

      // Stamp in center to represent side arch in profile
      canvas.drawImage(arch2Img, const Offset(100, 80), Paint()..filterQuality = FilterQuality.high);

      // Foreground base band
      const bandSrcRect = Rect.fromLTWH(10, 184, 236, 48);
      canvas.drawImageRect(queenImg, bandSrcRect, bandSrcRect, Paint()..filterQuality = FilterQuality.high);

      final pic = recorder.endRecording();
      final prof = await pic.toImage(w.toInt(), h.toInt());
      final outBytes = await prof.toByteData(format: ui.ImageByteFormat.png);

      File('assets/emojis/queen_profile.png')
          .writeAsBytesSync(outBytes!.buffer.asUint8List());
      File('/Users/nandhakumar/.gemini/antigravity/brain/9d8e4d9b-b461-4a7b-96a6-6e732447b51f/queen_profile_perfect.png')
          .writeAsBytesSync(outBytes.buffer.asUint8List());
      print('Saved queen_profile.png');
    }
  });
}
