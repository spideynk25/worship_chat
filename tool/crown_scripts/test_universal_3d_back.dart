import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('refine universal 3d crown rendering with seamless profile and back', () async {
    final crowns = [
      {'name': 'queen', 'color': const Color(0xFFC62828), 'hasVelvet': true},
      {'name': 'core_supreme', 'color': const Color(0xFFFFB300), 'hasVelvet': false},
      {'name': 'supreme_goddess', 'color': const Color(0xFF1565C0), 'hasVelvet': false},
      {'name': 'golden_blossom', 'color': const Color(0xFFFFB74D), 'hasVelvet': false},
      {'name': 'demi_goddess', 'color': const Color(0xFFE1F5FE), 'hasVelvet': false},
      {'name': 'elfwitch', 'color': const Color(0xFF7B1FA2), 'hasVelvet': false},
    ];

    for (final c in crowns) {
      final name = c['name'] as String;
      final color = c['color'] as Color;
      final hasVelvet = c['hasVelvet'] as bool;

      final file = File('assets/emojis/$name.png');
      final bytes = file.readAsBytesSync();
      final codec = await ui.instantiateImageCodec(bytes);
      final frontImg = (await codec.getNextFrame()).image;

      // 1. Render 180° BACK
      final rearImg = await _renderCrown(
        frontImage: frontImg,
        yaw: math.pi,
        pitch: -0.15,
        glowColor: color,
        hasVelvet: hasVelvet,
        size: const Size(260, 240),
      );
      final rearBytes = await rearImg.toByteData(format: ui.ImageByteFormat.png);
      File('/Users/nandhakumar/.gemini/antigravity/brain/9d8e4d9b-b461-4a7b-96a6-6e732447b51f/refined_180_$name.png')
          .writeAsBytesSync(rearBytes!.buffer.asUint8List());

      // 2. Render 90° PROFILE
      final profImg = await _renderCrown(
        frontImage: frontImg,
        yaw: math.pi * 0.50,
        pitch: -0.15,
        glowColor: color,
        hasVelvet: hasVelvet,
        size: const Size(260, 240),
      );
      final profBytes = await profImg.toByteData(format: ui.ImageByteFormat.png);
      File('/Users/nandhakumar/.gemini/antigravity/brain/9d8e4d9b-b461-4a7b-96a6-6e732447b51f/refined_90_$name.png')
          .writeAsBytesSync(profBytes!.buffer.asUint8List());

      // 3. Render 60° 3D TILT
      final tiltImg = await _renderCrown(
        frontImage: frontImg,
        yaw: 1.05,
        pitch: -0.15,
        glowColor: color,
        hasVelvet: hasVelvet,
        size: const Size(260, 240),
      );
      final tiltBytes = await tiltImg.toByteData(format: ui.ImageByteFormat.png);
      File('/Users/nandhakumar/.gemini/antigravity/brain/9d8e4d9b-b461-4a7b-96a6-6e732447b51f/refined_60_$name.png')
          .writeAsBytesSync(tiltBytes!.buffer.asUint8List());
    }
    print('All refined renders complete');
  });
}

Future<ui.Image> _renderCrown({
  required ui.Image frontImage,
  required double yaw,
  required double pitch,
  required Color glowColor,
  required bool hasVelvet,
  required Size size,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size.width, size.height));

  final cx = size.width / 2.0;
  final cy = size.height / 2.0;

  double normYaw = yaw % (math.pi * 2.0);
  if (normYaw > math.pi) normYaw -= math.pi * 2.0;
  if (normYaw < -math.pi) normYaw += math.pi * 2.0;

  final absYaw = normYaw.abs();
  final isBackHalf = absYaw >= math.pi * 0.48; // Viewing back half of crown
  final isProfile = absYaw >= math.pi * 0.30 && absYaw <= math.pi * 0.70;

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

  final drawW = size.width * 0.82;
  final drawH = size.height * 0.82;
  final destRect = Rect.fromCenter(
    center: Offset(cx, cy - size.height * 0.03),
    width: drawW,
    height: drawH,
  );

  // Directional lighting
  final cosLight = math.cos(normYaw);
  final light = (0.88 + 0.12 * cosLight - 0.08 * math.sin(normYaw)).clamp(0.72, 1.15);

  final lightFilter = ColorFilter.matrix(<double>[
    light, 0, 0, 0, 0,
    0, light, 0, 0, 0,
    0, 0, light * 0.98, 0, 0,
    0, 0, 0, 1.0, 0,
  ]);

  if (!isBackHalf) {
    // ── FRONT HALF (-86° to +86°) ──────────────────────────────────────────
    // If approaching profile (60° to 86°), we also draw the rear hoop in the background
    // to give it authentic cylindrical depth with ZERO side gap!
    if (absYaw >= math.pi * 0.28) {
      _drawRearHoopBackground(
        canvas: canvas,
        cx: cx,
        cy: cy,
        size: size,
        destRect: destRect,
        yaw: normYaw,
        pitch: pitch,
        glowColor: glowColor,
      );
    }

    // Foreground: Front diadem with 3D perspective matrix
    canvas.save();
    // Clamp perspective rotation around profile to prevent paper-thin collapse!
    final effectiveYaw = (normYaw.abs() > math.pi * 0.38)
        ? (normYaw.sign * (math.pi * 0.38 + (normYaw.abs() - math.pi * 0.38) * 0.25))
        : normYaw;

    final transform = Matrix4.identity()
      ..setEntry(3, 2, 0.0018)
      ..translateByDouble(cx, cy - size.height * 0.03, 0.0, 1.0)
      ..rotateY(effectiveYaw)
      ..rotateX(pitch)
      ..translateByDouble(-cx, -cy + size.height * 0.03, 0.0, 1.0);
    canvas.transform(transform.storage);

    canvas.drawImageRect(
      frontImage,
      Rect.fromLTWH(0, 0, frontImage.width.toDouble(), frontImage.height.toDouble()),
      destRect,
      Paint()
        ..filterQuality = FilterQuality.high
        ..isAntiAlias = true
        ..colorFilter = lightFilter,
    );
    canvas.restore();
  } else {
    // ── REAR HALF (86° to 180° / -86° to -180°) ───────────────────────────
    final localYaw = normYaw > 0 ? (normYaw - math.pi) : (normYaw + math.pi);

    // 1. Velvet cap in background (for Queen/imperial crowns)
    if (hasVelvet) {
      final capCenter = Offset(cx, cy - size.height * 0.02);
      final capRect = Rect.fromCenter(
        center: capCenter,
        width: destRect.width * 0.62,
        height: destRect.height * 0.45,
      );
      final capPaint = Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.0, -0.3),
          radius: 0.85,
          colors: const [
            Color(0xFF8B1527),
            Color(0xFF5E0B19),
            Color(0xFF2E040B),
          ],
          stops: const [0.0, 0.50, 1.0],
        ).createShader(capRect);
      canvas.drawOval(capRect, capPaint);
    }

    // 2. BACKGROUND: Reverse side of front crest in solid Antique Gold Repousse
    canvas.save();
    final effectiveBgYaw = (localYaw.abs() > math.pi * 0.38)
        ? (localYaw.sign * (math.pi * 0.38 + (localYaw.abs() - math.pi * 0.38) * 0.25))
        : localYaw;

    final bgTransform = Matrix4.identity()
      ..setEntry(3, 2, 0.0018)
      ..translateByDouble(cx, cy - size.height * 0.03, 0.0, 1.0)
      ..rotateY(effectiveBgYaw)
      ..rotateX(pitch)
      ..scaleByDouble(0.95, 0.95, 1.0, 1.0) // Depth recession
      ..translateByDouble(-cx, -cy + size.height * 0.03, 0.0, 1.0);
    canvas.transform(bgTransform.storage);

    // Antique Gold Repousse Color Matrix
    final repousseFilter = ColorFilter.matrix(const <double>[
      0.45, 0.35, 0.10, 0, 18,
      0.35, 0.30, 0.08, 0, 12,
      0.15, 0.12, 0.05, 0, 2,
      0.00, 0.00, 0.00, 1.0, 0,
    ]);

    // Mirror horizontally so reverse side matches true 3D architecture
    canvas.save();
    canvas.translate(cx, cy);
    canvas.scale(-1.0, 1.0);
    canvas.translate(-cx, -cy);

    canvas.drawImageRect(
      frontImage,
      Rect.fromLTWH(0, 0, frontImage.width.toDouble(), frontImage.height.toDouble()),
      destRect,
      Paint()
        ..filterQuality = FilterQuality.high
        ..isAntiAlias = true
        ..colorFilter = repousseFilter,
    );
    canvas.restore();
    canvas.restore();

    // 3. FOREGROUND: Master Royal Circlet Bandeau enclosing back of the head
    _drawForegroundRearBandeau(
      canvas: canvas,
      cx: cx,
      cy: cy,
      size: size,
      destRect: destRect,
      localYaw: localYaw,
      pitch: pitch,
      glowColor: glowColor,
    );
  }

  final picture = recorder.endRecording();
  return picture.toImage(size.width.toInt(), size.height.toInt());
}

void _drawRearHoopBackground({
  required Canvas canvas,
  required double cx,
  required double cy,
  required Size size,
  required Rect destRect,
  required double yaw,
  required double pitch,
  required Color glowColor,
}) {
  final bandCenterY = destRect.bottom - destRect.height * 0.18;
  final bandHeight = destRect.height * 0.16;
  final bandWidth = destRect.width * 0.82;
  final startX = cx - bandWidth / 2.0;
  final endX = cx + bandWidth / 2.0;
  final topY = bandCenterY - bandHeight / 2.0;
  final botY = bandCenterY + bandHeight / 2.0;
  final curveDip = -5.0 * math.cos(pitch);

  final hoopPath = Path()
    ..moveTo(startX, topY)
    ..quadraticBezierTo(cx, topY + curveDip, endX, topY)
    ..lineTo(endX, botY)
    ..quadraticBezierTo(cx, botY + curveDip, startX, botY)
    ..close();

  // Interior shadowed gold
  final hoopPaint = Paint()
    ..shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: const [
        Color(0xFF8B6508),
        Color(0xFF5A3E08),
        Color(0xFF382303),
      ],
    ).createShader(Rect.fromLTWH(startX, topY, bandWidth, bandHeight));
  canvas.drawPath(hoopPath, hoopPaint);
}

void _drawForegroundRearBandeau({
  required Canvas canvas,
  required double cx,
  required double cy,
  required Size size,
  required Rect destRect,
  required double localYaw,
  required double pitch,
  required Color glowColor,
}) {
  canvas.save();
  final fgTransform = Matrix4.identity()
    ..setEntry(3, 2, 0.0018)
    ..translateByDouble(cx, cy - size.height * 0.03, 0.0, 1.0)
    ..rotateY(localYaw * 0.65)
    ..rotateX(pitch)
    ..translateByDouble(-cx, -cy + size.height * 0.03, 0.0, 1.0);
  canvas.transform(fgTransform.storage);

  final bandCenterY = destRect.bottom - destRect.height * 0.16;
  final bandHeight = destRect.height * 0.19;
  final bandWidth = destRect.width * 0.84;
  final startX = cx - bandWidth / 2.0;
  final endX = cx + bandWidth / 2.0;
  final topY = bandCenterY - bandHeight / 2.0;
  final botY = bandCenterY + bandHeight / 2.0;
  final curveDip = (5.0 - pitch * 8.0).clamp(2.0, 10.0);

  // Cast shadow
  final bandPath = Path()
    ..moveTo(startX, topY)
    ..quadraticBezierTo(cx, topY + curveDip, endX, topY)
    ..lineTo(endX, botY)
    ..quadraticBezierTo(cx, botY + curveDip, startX, botY)
    ..close();

  final shadowP = Paint()
    ..color = Colors.black.withValues(alpha: 0.65)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5.0);
  canvas.drawPath(bandPath, shadowP);

  // 24K Gold Body
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
    ).createShader(Rect.fromLTWH(startX, topY, bandWidth, bandHeight));
  canvas.drawPath(bandPath, goldBandPaint);

  // Bevel Highlights
  final topBv = Path()..moveTo(startX, topY)..quadraticBezierTo(cx, topY + curveDip, endX, topY);
  canvas.drawPath(topBv, Paint()..color = const Color(0xFFFFF7D6)..strokeWidth = 1.6..style = PaintingStyle.stroke);
  final botBv = Path()..moveTo(startX, botY)..quadraticBezierTo(cx, botY + curveDip, endX, botY);
  canvas.drawPath(botBv, Paint()..color = const Color(0xFF382303)..strokeWidth = 2.0..style = PaintingStyle.stroke);

  // Pearl Rails
  final pearlCount = 18;
  final pRad = (bandHeight * 0.14).clamp(2.5, 4.0);
  void drawPearl(Offset pt) {
    canvas.drawCircle(
      pt,
      pRad,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.35),
          radius: 0.85,
          colors: const [Color(0xFFFFFFFF), Color(0xFFF7F2E8), Color(0xFFDDD5C7), Color(0xFFA69986)],
          stops: const [0.0, 0.40, 0.75, 1.0],
        ).createShader(Rect.fromCircle(center: pt, radius: pRad)),
    );
    canvas.drawCircle(pt - Offset(pRad * 0.32, pRad * 0.32), pRad * 0.28, Paint()..color = Colors.white);
  }

  for (int i = 0; i < pearlCount; i++) {
    final t = i / (pearlCount - 1);
    final px = startX + t * bandWidth;
    final cY = math.sin(t * math.pi) * curveDip;
    drawPearl(Offset(px, topY + pRad + 1.2 + cY));
    drawPearl(Offset(px, botY - pRad - 1.2 + cY));
  }

  // Centered Solitaire Jewel matching Crown Palette
  final jewelCenter = Offset(cx, bandCenterY + curveDip * 0.5);
  final jewelW = bandHeight * 0.90;
  final jewelH = bandHeight * 0.62;
  final jRect = Rect.fromCenter(center: jewelCenter, width: jewelW, height: jewelH);

  // Bezel Rim
  final bzRect = jRect.inflate(3.0);
  canvas.drawRRect(
    RRect.fromRectAndRadius(bzRect, const Radius.circular(5.0)),
    Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFFFF7D6), Color(0xFFD4AF37), Color(0xFF5A3E08)],
      ).createShader(bzRect),
  );

  // Faceted Royal Gemstone
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

  // Diamond Facet Reflection
  canvas.drawCircle(
    jewelCenter - Offset(jewelW * 0.22, jewelH * 0.22),
    jewelH * 0.20,
    Paint()
      ..color = Colors.white.withValues(alpha: 0.88)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.0),
  );

  // Flanking emeralds/accents
  void drawFlank(Offset pt, Color col, double rad) {
    canvas.drawCircle(pt, rad + 1.6, Paint()..color = const Color(0xFFD4AF37));
    canvas.drawCircle(
      pt,
      rad,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.3),
          radius: 0.85,
          colors: [Color.lerp(col, Colors.white, 0.45)!, col, Color.lerp(col, Colors.black, 0.65)!],
        ).createShader(Rect.fromCircle(center: pt, radius: rad)),
    );
    canvas.drawCircle(pt - Offset(rad * 0.28, rad * 0.28), rad * 0.28, Paint()..color = Colors.white);
  }

  final flankDist1 = bandWidth * 0.22;
  final flankDist2 = bandWidth * 0.36;
  drawFlank(Offset(cx - flankDist1, bandCenterY + curveDip * 0.4), const Color(0xFF0F6E38), jewelH * 0.30);
  drawFlank(Offset(cx + flankDist1, bandCenterY + curveDip * 0.4), const Color(0xFF0F6E38), jewelH * 0.30);
  drawFlank(Offset(cx - flankDist2, bandCenterY + curveDip * 0.3), glowColor, jewelH * 0.26);
  drawFlank(Offset(cx + flankDist2, bandCenterY + curveDip * 0.3), glowColor, jewelH * 0.26);

  canvas.restore();
}
