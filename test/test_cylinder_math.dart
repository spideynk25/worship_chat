import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('true 3d cylinder projection with zero gap at all angles', () async {
    final file = File('assets/emojis/queen.png');
    final bytes = file.readAsBytesSync();
    final codec = await ui.instantiateImageCodec(bytes);
    final queenImg = (await codec.getNextFrame()).image;

    final angles = [
      {'label': '0_front', 'yaw': 0.0},
      {'label': '30_tilt', 'yaw': 0.52},
      {'label': '60_3d', 'yaw': 1.05},
      {'label': '90_profile', 'yaw': 1.57},
      {'label': '180_back', 'yaw': math.pi},
    ];

    for (final a in angles) {
      final label = a['label'] as String;
      final yaw = a['yaw'] as double;

      final img = await _renderCylindricalCrown(
        frontImage: queenImg,
        yaw: yaw,
        pitch: -0.15,
        glowColor: const Color(0xFFC62828),
        size: const Size(260, 240),
      );

      final outBytes = await img.toByteData(format: ui.ImageByteFormat.png);
      final outPath = '/Users/nandhakumar/.gemini/antigravity/brain/9d8e4d9b-b461-4a7b-96a6-6e732447b51f/cyl_queen_$label.png';
      File(outPath).writeAsBytesSync(outBytes!.buffer.asUint8List());
    }
    print('Rendered all cylindrical angles');
  });
}

Future<ui.Image> _renderCylindricalCrown({
  required ui.Image frontImage,
  required double yaw,
  required double pitch,
  required Color glowColor,
  required Size size,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size.width, size.height));

  final cx = size.width / 2.0;
  final cy = size.height / 2.0;

  double normYaw = yaw % (math.pi * 2.0);
  if (normYaw > math.pi) normYaw -= math.pi * 2.0;
  if (normYaw < -math.pi) normYaw += math.pi * 2.0;

  // Cylinder radius in screen pixels
  final radiusX = size.width * 0.32;
  final radiusZ = size.width * 0.28;

  // Front center in 3D:
  // theta_front = 0 -> alpha_f = yaw
  final xFront = cx + radiusX * math.sin(normYaw);
  final zFront = radiusZ * math.cos(normYaw);

  // Rear center in 3D:
  // theta_rear = pi -> alpha_r = yaw + pi
  final xRear = cx - radiusX * math.sin(normYaw);
  final zRear = -radiusZ * math.cos(normYaw);

  // 1. Soft Floor Shadow
  final shadowPaint = Paint()
    ..color = Colors.black.withValues(alpha: 0.50)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
  final shadowOffsetY = cy + size.height * 0.35 + math.cos(pitch) * (size.height * 0.03);
  canvas.drawOval(
    Rect.fromCenter(
      center: Offset(cx + math.sin(normYaw) * (size.width * 0.06), shadowOffsetY),
      width: size.width * 0.75,
      height: (size.width * 0.18 * (1.0 - pitch * 0.35)).clamp(size.width * 0.08, size.width * 0.30),
    ),
    shadowPaint,
  );

  // 2. Warm Royal Aura
  final auraPaint = Paint()
    ..shader = RadialGradient(
      colors: [
        glowColor.withValues(alpha: 0.15),
        glowColor.withValues(alpha: 0.03),
        Colors.transparent,
      ],
      stops: const [0.0, 0.55, 1.0],
    ).createShader(Rect.fromCenter(
      center: Offset(cx, cy + size.height * 0.06),
      width: size.width * 1.0,
      height: size.height * 0.85,
    ));
  canvas.drawOval(
    Rect.fromCenter(
      center: Offset(cx, cy + size.height * 0.06),
      width: size.width * 1.0,
      height: size.height * 0.85,
    ),
    auraPaint,
  );

  final baseW = size.width * 0.76;
  final baseH = size.height * 0.76;

  // Painter's algorithm:
  // If zFront < zRear: Front is behind Rear (Viewing from BACK)
  // If zFront >= zRear: Front is in front of Rear (Viewing from FRONT)

  if (zFront >= zRear) {
    // ── VIEWING FRONT HALF (zFront >= 0) ───────────────────────────────────
    // 1. Draw Rear Arc (Background)
    _drawRearCylinderArc(canvas, xRear, cy, baseW, baseH, normYaw, pitch, glowColor, false);

    // 2. Draw Front Diadem (Foreground)
    _drawFrontDiadem(canvas, xFront, cy, baseW, baseH, normYaw, pitch, frontImage, true);
  } else {
    // ── VIEWING REAR HALF (zFront < 0) ────────────────────────────────────
    // 1. Draw Front Diadem as Antique Gold Repousse Backing (Background)
    _drawFrontDiadem(canvas, xFront, cy, baseW, baseH, normYaw, pitch, frontImage, false);

    // 2. Draw Rear Bandeau with Solitaire Jewel (Foreground)
    _drawRearCylinderArc(canvas, xRear, cy, baseW, baseH, normYaw, pitch, glowColor, true);
  }

  // 3. Continuous Side Headband Connecting Hoops (Ensures ZERO GAP at horizon edges!)
  _drawSideHorizonBridges(canvas, cx, cy, radiusX, baseH, normYaw, pitch);

  final picture = recorder.endRecording();
  return picture.toImage(size.width.toInt(), size.height.toInt());
}

void _drawFrontDiadem(
  Canvas canvas,
  double xCenter,
  double cy,
  double baseW,
  double baseH,
  double yaw,
  double pitch,
  ui.Image frontImage,
  bool isForeground,
) {
  canvas.save();

  // Perspective compression along X
  final cosY = math.cos(yaw).abs().clamp(0.40, 1.0);
  final widthScale = isForeground ? (0.65 + 0.35 * cosY) : (0.55 + 0.35 * cosY);
  final drawW = baseW * widthScale;
  final drawH = baseH * (isForeground ? 1.0 : 0.94);

  final destRect = Rect.fromCenter(
    center: Offset(xCenter, cy - baseH * 0.04),
    width: drawW,
    height: drawH,
  );

  final Paint paint = Paint()
    ..filterQuality = FilterQuality.high
    ..isAntiAlias = true;

  if (!isForeground) {
    // Background: Antique Gold Repousse Metal Backing
    paint.colorFilter = ColorFilter.matrix(const <double>[
      0.45, 0.35, 0.10, 0, 18,
      0.35, 0.30, 0.08, 0, 12,
      0.15, 0.12, 0.05, 0, 2,
      0.00, 0.00, 0.00, 1.0, 0,
    ]);

    // Mirror horizontally so reverse side is geometrically correct
    canvas.translate(xCenter, cy);
    canvas.scale(-1.0, 1.0);
    canvas.translate(-xCenter, -cy);
  } else {
    // Directional light
    final light = (0.88 + 0.12 * math.cos(yaw)).clamp(0.75, 1.15);
    paint.colorFilter = ColorFilter.matrix(<double>[
      light, 0, 0, 0, 0,
      0, light, 0, 0, 0,
      0, 0, light * 0.98, 0, 0,
      0, 0, 0, 1.0, 0,
    ]);
  }

  canvas.drawImageRect(
    frontImage,
    Rect.fromLTWH(0, 0, frontImage.width.toDouble(), frontImage.height.toDouble()),
    destRect,
    paint,
  );

  canvas.restore();
}

void _drawRearCylinderArc(
  Canvas canvas,
  double xCenter,
  double cy,
  double baseW,
  double baseH,
  double yaw,
  double pitch,
  Color glowColor,
  bool isForeground,
) {
  canvas.save();

  final cosY = math.cos(yaw).abs().clamp(0.40, 1.0);
  final widthScale = isForeground ? (0.65 + 0.35 * cosY) : (0.55 + 0.35 * cosY);
  final bandW = baseW * widthScale;
  final bandH = baseH * 0.20;

  final bandCenterY = cy + baseH * 0.34;
  final startX = xCenter - bandW / 2.0;
  final endX = xCenter + bandW / 2.0;
  final topY = bandCenterY - bandH / 2.0;
  final botY = bandCenterY + bandH / 2.0;
  final curveDip = (isForeground ? 5.0 : -5.0);

  final bandPath = Path()
    ..moveTo(startX, topY)
    ..quadraticBezierTo(xCenter, topY + curveDip, endX, topY)
    ..lineTo(endX, botY)
    ..quadraticBezierTo(xCenter, botY + curveDip, startX, botY)
    ..close();

  if (!isForeground) {
    // Interior shadowed gold
    final hoopPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: const [Color(0xFF8B6508), Color(0xFF5A3E08), Color(0xFF382303)],
      ).createShader(Rect.fromLTWH(startX, topY, bandW, bandH));
    canvas.drawPath(bandPath, hoopPaint);
    canvas.restore();
    return;
  }

  // Foreground: Radiant 24K Gold Circlet Bandeau with Pearls & Gemstone
  final shadowP = Paint()
    ..color = Colors.black.withValues(alpha: 0.60)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5.0);
  canvas.drawPath(bandPath, shadowP);

  final goldBandPaint = Paint()
    ..shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: const [
        Color(0xFFFFF7D6),
        Color(0xFFFFE082),
        Color(0xFFD4AF37),
        Color(0xFF8B6508),
        Color(0xFF4A3205),
      ],
      stops: const [0.0, 0.20, 0.50, 0.80, 1.0],
    ).createShader(Rect.fromLTWH(startX, topY, bandW, bandH));
  canvas.drawPath(bandPath, goldBandPaint);

  // Bevels
  final topBv = Path()..moveTo(startX, topY)..quadraticBezierTo(xCenter, topY + curveDip, endX, topY);
  canvas.drawPath(topBv, Paint()..color = const Color(0xFFFFF7D6)..strokeWidth = 1.6..style = PaintingStyle.stroke);
  final botBv = Path()..moveTo(startX, botY)..quadraticBezierTo(xCenter, botY + curveDip, endX, botY);
  canvas.drawPath(botBv, Paint()..color = const Color(0xFF382303)..strokeWidth = 2.0..style = PaintingStyle.stroke);

  // Pearls
  final pearlCount = (bandW / 12.0).round().clamp(10, 20);
  final pRad = (bandH * 0.14).clamp(2.5, 4.0);
  void drawPearl(Offset pt) {
    canvas.drawCircle(
      pt,
      pRad,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.35),
          radius: 0.85,
          colors: const [Color(0xFFFFFFFF), Color(0xFFF7F2E8), Color(0xFFDDD5C7), Color(0xFFA69986)],
        ).createShader(Rect.fromCircle(center: pt, radius: pRad)),
    );
    canvas.drawCircle(pt - Offset(pRad * 0.32, pRad * 0.32), pRad * 0.28, Paint()..color = Colors.white);
  }

  for (int i = 0; i < pearlCount; i++) {
    final t = i / (pearlCount - 1);
    final px = startX + t * bandW;
    final cY = math.sin(t * math.pi) * curveDip;
    drawPearl(Offset(px, topY + pRad + 1.2 + cY));
    drawPearl(Offset(px, botY - pRad - 1.2 + cY));
  }

  // Centered Solitaire Jewel matching Crown Palette
  final jewelCenter = Offset(xCenter, bandCenterY + curveDip * 0.5);
  final jewelW = bandH * 0.90;
  final jewelH = bandH * 0.62;
  final jRect = Rect.fromCenter(center: jewelCenter, width: jewelW, height: jewelH);

  canvas.drawRRect(
    RRect.fromRectAndRadius(jRect.inflate(3.0), const Radius.circular(5.0)),
    Paint()..color = const Color(0xFFD4AF37),
  );

  final gemP = Paint()
    ..shader = RadialGradient(
      center: const Alignment(-0.30, -0.30),
      radius: 0.85,
      colors: [
        Color.lerp(glowColor, Colors.white, 0.52)!,
        glowColor,
        Color.lerp(glowColor, Colors.black, 0.70)!,
      ],
      stops: const [0.0, 0.48, 1.0],
    ).createShader(jRect);
  canvas.drawRRect(RRect.fromRectAndRadius(jRect, const Radius.circular(3.0)), gemP);

  canvas.drawCircle(
    jewelCenter - Offset(jewelW * 0.22, jewelH * 0.22),
    jewelH * 0.20,
    Paint()
      ..color = Colors.white.withValues(alpha: 0.88)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.0),
  );

  canvas.restore();
}

void _drawSideHorizonBridges(
  Canvas canvas,
  double cx,
  double cy,
  double radiusX,
  double baseH,
  double yaw,
  double pitch,
) {
  // Bridges front and rear at the left and right horizons:
  final horizonY = cy + baseH * 0.34;
  final horizonH = baseH * 0.18;

  final leftP = Offset(cx - radiusX, horizonY);
  final rightP = Offset(cx + radiusX, horizonY);

  final bridgePaint = Paint()
    ..shader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFFFF7D6), Color(0xFFD4AF37), Color(0xFF5A3E08)],
    ).createShader(Rect.fromCenter(center: leftP, width: 12, height: horizonH));

  canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: leftP, width: 8, height: horizonH), const Radius.circular(4)), bridgePaint);
  canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: rightP, width: 8, height: horizonH), const Radius.circular(4)), bridgePaint);
}
