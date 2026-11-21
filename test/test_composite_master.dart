import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('composite master jewelry bandeau onto Queen and Demi Goddess', () async {
    // 1. Load aura rear to extract master bandeau
    final auraRearFile = File('assets/emojis/aura_elixiria_rear.png');
    final auraBytes = auraRearFile.readAsBytesSync();
    final auraCodec = await ui.instantiateImageCodec(auraBytes);
    final auraRearImg = (await auraCodec.getNextFrame()).image;

    // Clean headband crop bounds:
    // x: 195 to 829 (width 634), y: 532 to 678 (height 146)
    const bandSrcRect = Rect.fromLTWH(195, 532, 634, 146);

    final bandRecorder = ui.PictureRecorder();
    final bandCanvas = Canvas(bandRecorder, Rect.fromLTWH(0, 0, bandSrcRect.width, bandSrcRect.height));
    bandCanvas.drawImageRect(
      auraRearImg,
      bandSrcRect,
      Rect.fromLTWH(0, 0, bandSrcRect.width, bandSrcRect.height),
      Paint()..filterQuality = FilterQuality.high,
    );
    final bandPicture = bandRecorder.endRecording();
    final masterBandImg = await bandPicture.toImage(bandSrcRect.width.toInt(), bandSrcRect.height.toInt());

    // 2. Test Queen
    await _renderCrownRear(
      name: 'queen',
      masterBandImg: masterBandImg,
      gemColor: const Color(0xFFC62828), // Royal Ruby
      hasVelvetCap: true,
      velvetColor: const Color(0xFF5C0E1B),
      bandYRatio: 0.76,
      bandWidthRatio: 0.84,
      bandHeightRatio: 0.22,
    );

    // 3. Test Demi Goddess
    await _renderCrownRear(
      name: 'demi_goddess',
      masterBandImg: masterBandImg,
      gemColor: const Color(0xFFE1F5FE), // Luminous Moonstone
      hasVelvetCap: false,
      bandYRatio: 0.70,
      bandWidthRatio: 0.84,
      bandHeightRatio: 0.22,
    );
  });
}

Future<void> _renderCrownRear({
  required String name,
  required ui.Image masterBandImg,
  required Color gemColor,
  required bool hasVelvetCap,
  Color? velvetColor,
  required double bandYRatio,
  required double bandWidthRatio,
  required double bandHeightRatio,
}) async {
  final file = File('assets/emojis/$name.png');
  final bytes = file.readAsBytesSync();
  final codec = await ui.instantiateImageCodec(bytes);
  final frontImg = (await codec.getNextFrame()).image;

  final w = frontImg.width;
  final h = frontImg.height;

  // Process front image into Antique Gold Repousse Backing
  final frontByteData = await frontImg.toByteData(format: ui.ImageByteFormat.rawRgba);
  final pixels = frontByteData!.buffer.asUint8List();
  final repoussePixels = Uint8List(w * h * 4);

  const goldBase = Color(0xFFD4AF37);
  const goldHighlight = Color(0xFFFFF7D6);
  const goldShadow = Color(0xFF4A3205);

  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final srcIdx = (y * w + x) * 4;
      final mirrorX = w - 1 - x;
      final dstIdx = (y * w + mirrorX) * 4;

      final a = pixels[srcIdx + 3];
      if (a == 0) {
        repoussePixels[dstIdx + 3] = 0;
        continue;
      }

      final r = pixels[srcIdx] / 255.0;
      final g = pixels[srcIdx + 1] / 255.0;
      final b = pixels[srcIdx + 2] / 255.0;

      final lum = (0.299 * r + 0.587 * g + 0.114 * b).clamp(0.0, 1.0);

      double outR, outG, outB;
      if (lum < 0.45) {
        final t = lum / 0.45;
        outR = goldShadow.r + (goldBase.r - goldShadow.r) * t;
        outG = goldShadow.g + (goldBase.g - goldShadow.g) * t;
        outB = goldShadow.b + (goldBase.b - goldShadow.b) * t;
      } else {
        final t = (lum - 0.45) / 0.55;
        outR = goldBase.r + (goldHighlight.r - goldBase.r) * t;
        outG = goldBase.g + (goldHighlight.g - goldBase.g) * t;
        outB = goldBase.b + (goldHighlight.b - goldBase.b) * t;
      }

      // Noble museum patina
      outR *= 0.88;
      outG *= 0.85;
      outB *= 0.76;

      repoussePixels[dstIdx] = (outR * 255).round().clamp(0, 255);
      repoussePixels[dstIdx + 1] = (outG * 255).round().clamp(0, 255);
      repoussePixels[dstIdx + 2] = (outB * 255).round().clamp(0, 255);
      repoussePixels[dstIdx + 3] = a;
    }
  }

  final repousseImg = await _imageFromPixels(repoussePixels, w, h);

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));

  // 1. Velvet cap (if applicable)
  if (hasVelvetCap && velvetColor != null) {
    final capRect = Rect.fromCenter(
      center: Offset(w * 0.50, h * 0.55),
      width: w * 0.65,
      height: h * 0.42,
    );
    final capPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.0, -0.3),
        radius: 0.85,
        colors: [
          Color.lerp(velvetColor, Colors.white, 0.20)!,
          velvetColor,
          Color.lerp(velvetColor, Colors.black, 0.70)!,
        ],
        stops: const [0.0, 0.50, 1.0],
      ).createShader(capRect);
    canvas.drawOval(capRect, capPaint);
  }

  // 2. Repousse Backing in background (perspective recession scale 0.95)
  canvas.save();
  const scale = 0.95;
  final dx = (w * (1.0 - scale)) / 2.0;
  final dy = (h * (1.0 - scale)) * 0.80;
  canvas.translate(dx, dy);
  canvas.scale(scale, scale);
  canvas.drawImage(
    repousseImg,
    Offset.zero,
    Paint()..filterQuality = FilterQuality.high,
  );
  canvas.restore();

  // 3. Foreground Master Royal Bandeau
  final bandW = w * bandWidthRatio;
  final bandH = h * bandHeightRatio;
  final bandCenterX = w / 2.0;
  final bandCenterY = h * bandYRatio;

  final bandDestRect = Rect.fromCenter(
    center: Offset(bandCenterX, bandCenterY),
    width: bandW,
    height: bandH,
  );

  // Soft occlusion shadow behind bandeau
  final shadowPaint = Paint()
    ..color = Colors.black.withValues(alpha: 0.55)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5.0);
  canvas.drawRRect(
    RRect.fromRectAndRadius(bandDestRect.deflate(2.0), const Radius.circular(8.0)),
    shadowPaint,
  );

  // Draw master bandeau image
  canvas.drawImageRect(
    masterBandImg,
    Rect.fromLTWH(0, 0, masterBandImg.width.toDouble(), masterBandImg.height.toDouble()),
    bandDestRect,
    Paint()
      ..filterQuality = FilterQuality.high
      ..isAntiAlias = true,
  );

  // 4. Overpaint the center stone with the crown's custom signature gem!
  // Center stone in masterBandImg is at normalized x: 0.50, y: 0.52, width: 0.14, height: 0.65
  final centerStoneRect = Rect.fromCenter(
    center: Offset(bandCenterX, bandCenterY + bandH * 0.02),
    width: bandW * 0.145,
    height: bandH * 0.62,
  );

  // Faceted cut gemstone in gold bezel
  final stonePaint = Paint()
    ..shader = RadialGradient(
      center: const Alignment(-0.35, -0.35),
      radius: 0.85,
      colors: [
        Color.lerp(gemColor, Colors.white, 0.50)!,
        gemColor,
        Color.lerp(gemColor, Colors.black, 0.70)!,
      ],
      stops: const [0.0, 0.45, 1.0],
    ).createShader(centerStoneRect);

  canvas.drawRRect(
    RRect.fromRectAndRadius(centerStoneRect, const Radius.circular(3.0)),
    stonePaint,
  );

  // Facet table bezel border
  canvas.drawRRect(
    RRect.fromRectAndRadius(centerStoneRect, const Radius.circular(3.0)),
    Paint()
      ..color = const Color(0xFFFFF7D6).withValues(alpha: 0.80)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0,
  );

  // Specular facet reflection (calm, museum-lighting)
  canvas.drawCircle(
    centerStoneRect.center - Offset(centerStoneRect.width * 0.22, centerStoneRect.height * 0.22),
    centerStoneRect.shortestSide * 0.20,
    Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.0),
  );

  final picture = recorder.endRecording();
  final finalRear = await picture.toImage(w, h);
  final outBytes = await finalRear.toByteData(format: ui.ImageByteFormat.png);

  final outPath = '/Users/nandhakumar/.gemini/antigravity/brain/9d8e4d9b-b461-4a7b-96a6-6e732447b51f/master_v3_rear_$name.png';
  File(outPath).writeAsBytesSync(outBytes!.buffer.asUint8List());
  print('Saved $outPath');
}

Future<ui.Image> _imageFromPixels(Uint8List pixels, int width, int height) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}
