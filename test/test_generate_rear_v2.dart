import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class CrownMaterialConfig {
  final String name;
  final Color baseMetal;
  final Color highlightMetal;
  final Color shadowMetal;
  final Color primaryGem;
  final Color? secondaryGem;
  final Color? velvetCapColor;
  final bool hasVelvetCap;
  final double bandCenterYRatio;
  final double bandHeightRatio;
  final double bandWidthRatio;
  final double bandCurveDip;

  const CrownMaterialConfig({
    required this.name,
    required this.baseMetal,
    required this.highlightMetal,
    required this.shadowMetal,
    required this.primaryGem,
    this.secondaryGem,
    this.velvetCapColor,
    this.hasVelvetCap = false,
    this.bandCenterYRatio = 0.82,
    this.bandHeightRatio = 0.17,
    this.bandWidthRatio = 0.76,
    this.bandCurveDip = 4.0,
  });
}

void main() {
  test('generate authentic rear view for Queen and Demi Goddess', () async {
    final queenConfig = CrownMaterialConfig(
      name: 'queen',
      baseMetal: const Color(0xFFD4AF37),
      highlightMetal: const Color(0xFFFFF7D6),
      shadowMetal: const Color(0xFF4A3205),
      primaryGem: const Color(0xFFC62828), // Ruby
      secondaryGem: const Color(0xFFFFFFFF), // Diamond
      hasVelvetCap: true,
      velvetCapColor: const Color(0xFF5C0E1B), // Crimson velvet
      bandCenterYRatio: 0.81,
      bandHeightRatio: 0.18,
      bandWidthRatio: 0.77,
      bandCurveDip: 5.0,
    );

    final demiGoddessConfig = CrownMaterialConfig(
      name: 'demi_goddess',
      baseMetal: const Color(0xFFD4AF37),
      highlightMetal: const Color(0xFFFFF7D6),
      shadowMetal: const Color(0xFF5A3E08),
      primaryGem: const Color(0xFFE1F5FE), // Luminous Moonstone
      secondaryGem: const Color(0xFF1565C0), // Sapphire
      hasVelvetCap: false,
      bandCenterYRatio: 0.70,
      bandHeightRatio: 0.16,
      bandWidthRatio: 0.78,
      bandCurveDip: 4.0,
    );

    for (final cfg in [queenConfig, demiGoddessConfig]) {
      final file = File('assets/emojis/${cfg.name}.png');
      final bytes = file.readAsBytesSync();
      final codec = await ui.instantiateImageCodec(bytes);
      final frontImg = (await codec.getNextFrame()).image;

      final w = frontImg.width;
      final h = frontImg.height;

      // 1. Process front image into Antique Gold Repousse Backing
      final frontByteData = await frontImg.toByteData(format: ui.ImageByteFormat.rawRgba);
      final pixels = frontByteData!.buffer.asUint8List();
      final repoussePixels = Uint8List(w * h * 4);

      final mr = cfg.baseMetal.r;
      final mg = cfg.baseMetal.g;
      final mb = cfg.baseMetal.b;

      final hr = cfg.highlightMetal.r;
      final hg = cfg.highlightMetal.g;
      final hb = cfg.highlightMetal.b;

      final sr = cfg.shadowMetal.r;
      final sg = cfg.shadowMetal.g;
      final sb = cfg.shadowMetal.b;

      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final srcIdx = (y * w + x) * 4;
          // Mirror horizontally for true back perspective
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

          // Luminance
          final lum = (0.299 * r + 0.587 * g + 0.114 * b).clamp(0.0, 1.0);

          // Map luminance into antique repousse gold metal
          double outR, outG, outB;
          if (lum < 0.45) {
            final t = lum / 0.45;
            outR = sr + (mr - sr) * t;
            outG = sg + (mg - sg) * t;
            outB = sb + (mb - sb) * t;
          } else {
            final t = (lum - 0.45) / 0.55;
            outR = mr + (hr - mr) * t;
            outG = mg + (hg - mg) * t;
            outB = mb + (hb - mb) * t;
          }

          // Satin back patina & occlusion shading
          outR *= 0.85;
          outG *= 0.83;
          outB *= 0.74;

          repoussePixels[dstIdx] = (outR * 255).round().clamp(0, 255);
          repoussePixels[dstIdx + 1] = (outG * 255).round().clamp(0, 255);
          repoussePixels[dstIdx + 2] = (outB * 255).round().clamp(0, 255);
          repoussePixels[dstIdx + 3] = a;
        }
      }

      final repousseImg = await _imageFromPixels(repoussePixels, w, h);

      // 2. Compose into final rear image
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));

      // A. Royal Velvet Cushion Cap (for imperial dome crowns like Queen)
      if (cfg.hasVelvetCap && cfg.velvetCapColor != null) {
        final capRect = Rect.fromCenter(
          center: Offset(w * 0.50, h * 0.56),
          width: w * 0.65,
          height: h * 0.42,
        );
        final capPaint = Paint()
          ..shader = RadialGradient(
            center: const Alignment(0.0, -0.3),
            radius: 0.85,
            colors: [
              Color.lerp(cfg.velvetCapColor!, Colors.white, 0.22)!,
              cfg.velvetCapColor!,
              Color.lerp(cfg.velvetCapColor!, Colors.black, 0.68)!,
            ],
            stops: const [0.0, 0.50, 1.0],
          ).createShader(capRect);
        canvas.drawOval(capRect, capPaint);
      }

      // B. Repousse Backing in background (recessed slightly 0.96 scale for depth)
      canvas.save();
      const scale = 0.96;
      final dx = (w * (1.0 - scale)) / 2.0;
      final dy = (h * (1.0 - scale)) * 0.85;
      canvas.translate(dx, dy);
      canvas.scale(scale, scale);
      canvas.drawImage(
        repousseImg,
        Offset.zero,
        Paint()..filterQuality = FilterQuality.high,
      );
      canvas.restore();

      // C. Master Rear Circlet Bandeau in FOREGROUND
      _drawMasterRearBandeau(
        canvas: canvas,
        w: w.toDouble(),
        h: h.toDouble(),
        config: cfg,
      );

      final picture = recorder.endRecording();
      final finalRear = await picture.toImage(w, h);
      final outBytes = await finalRear.toByteData(format: ui.ImageByteFormat.png);

      final outPath = '/Users/nandhakumar/.gemini/antigravity/brain/9d8e4d9b-b461-4a7b-96a6-6e732447b51f/test_v2_rear_${cfg.name}.png';
      File(outPath).writeAsBytesSync(outBytes!.buffer.asUint8List());
      print('Saved $outPath');
    }
  });
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

void _drawMasterRearBandeau({
  required Canvas canvas,
  required double w,
  required double h,
  required CrownMaterialConfig config,
}) {
  final bandCenterY = h * config.bandCenterYRatio;
  final bandHeight = h * config.bandHeightRatio;
  final bandWidth = w * config.bandWidthRatio;
  final startX = (w - bandWidth) / 2.0;
  final endX = startX + bandWidth;
  final topY = bandCenterY - bandHeight / 2.0;
  final botY = bandCenterY + bandHeight / 2.0;
  final dip = config.bandCurveDip;

  // 1. Occlusion cast shadow behind bandeau onto backing/velvet
  final shadowPath = Path()
    ..moveTo(startX, topY)
    ..quadraticBezierTo(w / 2.0, topY + dip, endX, topY)
    ..lineTo(endX, botY)
    ..quadraticBezierTo(w / 2.0, botY + dip, startX, botY)
    ..close();

  final shadowPaint = Paint()
    ..color = Colors.black.withValues(alpha: 0.65)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
  canvas.drawPath(shadowPath, shadowPaint);

  // 2. Curved 24K Gold Band (Headband Body)
  final bandRect = Rect.fromCenter(
    center: Offset(w / 2.0, bandCenterY),
    width: bandWidth,
    height: bandHeight,
  );

  final bandPaint = Paint()
    ..shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        config.highlightMetal,
        config.baseMetal,
        Color.lerp(config.baseMetal, config.shadowMetal, 0.40)!,
        config.shadowMetal,
      ],
      stops: const [0.0, 0.25, 0.70, 1.0],
    ).createShader(bandRect);

  canvas.drawPath(shadowPath, bandPaint);

  // 3. Top and Bottom Bevel Highlight / Shadow Lines
  final topBevel = Path()
    ..moveTo(startX, topY)
    ..quadraticBezierTo(w / 2.0, topY + dip, endX, topY);
  canvas.drawPath(
    topBevel,
    Paint()
      ..color = config.highlightMetal
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke,
  );

  final botBevel = Path()
    ..moveTo(startX, botY)
    ..quadraticBezierTo(w / 2.0, botY + dip, endX, botY);
  canvas.drawPath(
    botBevel,
    Paint()
      ..color = config.shadowMetal
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke,
  );

  // 4. Upper & Lower Pearl Rails
  final pearlCount = (bandWidth / 14.0).round();
  final pearlRadius = (bandHeight * 0.16).clamp(2.5, 4.5);

  void drawPearl(Offset center, double radius) {
    // Pearl drop shadow
    canvas.drawCircle(
      center + Offset(0, radius * 0.3),
      radius,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.40)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.3),
    );

    // Luminous nacre gradient
    final pPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.35, -0.35),
        radius: 0.85,
        colors: const [
          Color(0xFFFFFFFF),
          Color(0xFFF7F2E8),
          Color(0xFFDDD5C7),
          Color(0xFFA69986),
        ],
        stops: const [0.0, 0.40, 0.75, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, pPaint);

    // Pearl specular gleam
    canvas.drawCircle(
      center - Offset(radius * 0.32, radius * 0.32),
      radius * 0.30,
      Paint()..color = Colors.white.withValues(alpha: 0.95),
    );
  }

  for (int i = 0; i < pearlCount; i++) {
    final t = i / (pearlCount - 1);
    final px = startX + t * bandWidth;
    final curveY = math.sin(t * math.pi) * dip;

    final topPy = topY + pearlRadius + 1.5 + curveY;
    final botPy = botY - pearlRadius - 1.5 + curveY;

    drawPearl(Offset(px, topPy), pearlRadius);
    drawPearl(Offset(px, botPy), pearlRadius);
  }

  // 5. Filigree Engraving Channels
  final midY = bandCenterY;
  final filigreeLine = Path()
    ..moveTo(startX + 8, midY - bandHeight * 0.12)
    ..quadraticBezierTo(w / 2.0, midY - bandHeight * 0.12 + dip, endX - 8, midY - bandHeight * 0.12);
  canvas.drawPath(
    filigreeLine,
    Paint()
      ..color = config.shadowMetal.withValues(alpha: 0.60)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke,
  );

  // 6. Centerpiece Royal Solitaire Jewel Collet (At w/2, midY + dip/2)
  final jewelCenter = Offset(w / 2.0, midY + dip * 0.5);
  final jewelW = bandHeight * 1.05;
  final jewelH = bandHeight * 0.65;
  final jewelRect = Rect.fromCenter(center: jewelCenter, width: jewelW, height: jewelH);

  // Gold Bezel Rim
  final bezelRect = jewelRect.inflate(3.5);
  final bezelPaint = Paint()
    ..shader = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [config.highlightMetal, config.baseMetal, config.shadowMetal],
      stops: const [0.0, 0.50, 1.0],
    ).createShader(bezelRect);
  canvas.drawRRect(RRect.fromRectAndRadius(bezelRect, const Radius.circular(5)), bezelPaint);

  // Milgrain pearl dots around bezel rim
  final milgrainPaint = Paint()..color = config.highlightMetal;
  const dotCount = 12;
  for (int d = 0; d < dotCount; d++) {
    final ang = (d * 2 * math.pi) / dotCount;
    final mx = jewelCenter.dx + (jewelW * 0.58) * math.cos(ang);
    final my = jewelCenter.dy + (jewelH * 0.58) * math.sin(ang);
    canvas.drawCircle(Offset(mx, my), 1.2, milgrainPaint);
  }

  // Faceted Royal Gemstone
  final gemPaint = Paint()
    ..shader = RadialGradient(
      center: const Alignment(-0.30, -0.30),
      radius: 0.90,
      colors: [
        Color.lerp(config.primaryGem, Colors.white, 0.45)!,
        config.primaryGem,
        Color.lerp(config.primaryGem, Colors.black, 0.65)!,
      ],
      stops: const [0.0, 0.55, 1.0],
    ).createShader(jewelRect);
  canvas.drawRRect(RRect.fromRectAndRadius(jewelRect, const Radius.circular(3)), gemPaint);

  // Diamond Facet Reflection (Calm, non-flashing)
  canvas.drawCircle(
    jewelCenter - Offset(jewelW * 0.22, jewelH * 0.22),
    jewelH * 0.20,
    Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.0),
  );

  // 7. Flanking Secondary Jewels (Left & Right)
  final secColor = config.secondaryGem ?? config.primaryGem;
  final secW = bandHeight * 0.55;
  final secH = bandHeight * 0.55;

  void drawSecondaryGem(Offset center) {
    final rect = Rect.fromCenter(center: center, width: secW, height: secH);
    // Gold collet
    canvas.drawCircle(center, secW * 0.60, bezelPaint);
    // Gem
    final sPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.3, -0.3),
        radius: 0.85,
        colors: [
          Color.lerp(secColor, Colors.white, 0.40)!,
          secColor,
          Color.lerp(secColor, Colors.black, 0.60)!,
        ],
        stops: const [0.0, 0.50, 1.0],
      ).createShader(rect);
    canvas.drawCircle(center, secW * 0.45, sPaint);
    // Specular
    canvas.drawCircle(
      center - Offset(secW * 0.15, secH * 0.15),
      secW * 0.14,
      Paint()..color = Colors.white.withValues(alpha: 0.90),
    );
  }

  final secOffsetDist = bandWidth * 0.22;
  final leftSecCenter = Offset(w / 2.0 - secOffsetDist, midY + dip * 0.4);
  final rightSecCenter = Offset(w / 2.0 + secOffsetDist, midY + dip * 0.4);

  drawSecondaryGem(leftSecCenter);
  drawSecondaryGem(rightSecCenter);
}
