import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Universal 360° Royal Crown Painter.
/// Provides authentic 3D cylindrical depth, seamless lateral horizon connections,
/// antique gold repoussé backing, and a master 24K gold circlet bandeau for the rear view.
class CylinderCrownPainter extends CustomPainter {
  final ui.Image frontImage;
  final ui.Image? rearImage;
  final double yaw;
  final double pitch;
  final Color glowColor;
  final double depthRatio;
  final bool hasVelvet;

  const CylinderCrownPainter({
    required this.frontImage,
    this.rearImage,
    required this.yaw,
    required this.pitch,
    required this.glowColor,
    this.depthRatio = 0.80,
    this.hasVelvet = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2.0;
    final cy = size.height / 2.0;

    // Normalize yaw to [-pi, pi]
    double normYaw = yaw % (math.pi * 2.0);
    if (normYaw > math.pi) normYaw -= math.pi * 2.0;
    if (normYaw < -math.pi) normYaw += math.pi * 2.0;

    final absYaw = normYaw.abs();
    final isBackHalf = absYaw >= math.pi * 0.50;

    _paintShadowAndAura(canvas, size, cx, cy, normYaw, pitch);

    final drawW = size.width * 0.82;
    final drawH = size.height * 0.82;
    final destRect = Rect.fromCenter(
      center: Offset(cx, cy - size.height * 0.03),
      width: drawW,
      height: drawH,
    );

    // Soft, realistic directional jewelry lighting without harsh specular glare or jitter
    final cosLight = math.cos(normYaw);
    final light = (0.90 + 0.10 * cosLight - 0.06 * math.sin(normYaw)).clamp(0.78, 1.10);

    final lightFilter = ColorFilter.matrix(<double>[
      light, 0, 0, 0, 0,
      0, light, 0, 0, 0,
      0, 0, light * 0.98, 0, 0,
      0, 0, 0, 1.0, 0,
    ]);

    if (!isBackHalf) {
      // ── FRONT HALF (-90° to +90°) ──────────────────────────────────────────
      // When rotated towards profile or 3D (yaw >= 25°), draw the rear circlet
      // in the background inside the arches to give authentic cylindrical depth with ZERO gap!
      if (absYaw >= math.pi * 0.14) {
        _drawRearBandeau(
          canvas: canvas,
          cx: cx,
          cy: cy,
          size: size,
          destRect: destRect,
          yaw: normYaw,
          pitch: pitch,
          glowColor: glowColor,
          isForeground: false,
        );
      }

      // Foreground: Front Diadem with smooth 3D perspective matrix transform
      canvas.save();
      final effectiveYaw = (normYaw.abs() > math.pi * 0.40)
          ? (normYaw.sign * (math.pi * 0.40 + (normYaw.abs() - math.pi * 0.40) * 0.28))
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
      // ── REAR HALF (90° to 180° / -90° to -180°) ───────────────────────────
      final localYaw = normYaw > 0 ? (normYaw - math.pi) : (normYaw + math.pi);

      // 1. Imperial Velvet Cap (for Queen imperial crowns)
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

      // 2. BACKGROUND: Reverse side of front crest in rich Antique Gold Repoussé
      canvas.save();
      final effectiveBgYaw = (localYaw.abs() > math.pi * 0.40)
          ? (localYaw.sign * (math.pi * 0.40 + (localYaw.abs() - math.pi * 0.40) * 0.28))
          : localYaw;

      final bgTransform = Matrix4.identity()
        ..setEntry(3, 2, 0.0018)
        ..translateByDouble(cx, cy - size.height * 0.03, 0.0, 1.0)
        ..rotateY(effectiveBgYaw)
        ..rotateX(pitch)
        ..scaleByDouble(0.95, 0.95, 1.0, 1.0)
        ..translateByDouble(-cx, -cy + size.height * 0.03, 0.0, 1.0);
      canvas.transform(bgTransform.storage);

      // Warm Antique Gold Repoussé Backing
      final repousseFilter = ColorFilter.matrix(const <double>[
        0.52, 0.38, 0.12, 0, 16,
        0.40, 0.32, 0.10, 0, 10,
        0.18, 0.14, 0.06, 0, 2,
        0.00, 0.00, 0.00, 1.0, 0,
      ]);

      // Mirror horizontally so reverse side matches 3D shape
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

      // 3. FOREGROUND: Master Royal Circlet Bandeau hugging back of head
      _drawRearBandeau(
        canvas: canvas,
        cx: cx,
        cy: cy,
        size: size,
        destRect: destRect,
        yaw: localYaw,
        pitch: pitch,
        glowColor: glowColor,
        isForeground: true,
      );
    }
  }

  void _drawRearBandeau({
    required Canvas canvas,
    required double cx,
    required double cy,
    required Size size,
    required Rect destRect,
    required double yaw,
    required double pitch,
    required Color glowColor,
    required bool isForeground,
  }) {
    canvas.save();
    if (isForeground) {
      final fgTransform = Matrix4.identity()
        ..setEntry(3, 2, 0.0018)
        ..translateByDouble(cx, cy - size.height * 0.03, 0.0, 1.0)
        ..rotateY(yaw * 0.65)
        ..rotateX(pitch)
        ..translateByDouble(-cx, -cy + size.height * 0.03, 0.0, 1.0);
      canvas.transform(fgTransform.storage);
    }

    // Exact baseline matching: The base band of the front crown is at the bottom 17% of destRect
    final bandCenterY = destRect.bottom - destRect.height * 0.17;
    final bandHeight = destRect.height * 0.18;
    final bandWidth = isForeground ? (destRect.width * 0.85) : (destRect.width * 0.82);
    final startX = cx - bandWidth / 2.0;
    final endX = cx + bandWidth / 2.0;
    final topY = bandCenterY - bandHeight / 2.0;
    final botY = bandCenterY + bandHeight / 2.0;
    final curveDip = isForeground
        ? (5.0 - pitch * 7.0).clamp(2.0, 9.0)
        : (-5.0 * math.cos(pitch));

    final bandPath = Path()
      ..moveTo(startX, topY)
      ..quadraticBezierTo(cx, topY + curveDip, endX, topY)
      ..lineTo(endX, botY)
      ..quadraticBezierTo(cx, botY + curveDip, startX, botY)
      ..close();

    if (!isForeground) {
      // Interior concave gold seen through front arches
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
      canvas.drawPath(bandPath, hoopPaint);
      canvas.restore();
      return;
    }

    // ── FOREGROUND REAR BANDEAU (seen at 180° BACK) ─────────────────────────
    // Soft drop shadow on background
    canvas.drawPath(
      bandPath,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5.0),
    );

    // 24K Royal Gold Gradient with rich luster (no harsh glitter)
    final goldPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: const [
          Color(0xFFFFF7D6),
          Color(0xFFFFE082),
          Color(0xFFD4AF37),
          Color(0xFF9E7812),
          Color(0xFF5A3E08),
        ],
        stops: const [0.0, 0.22, 0.52, 0.82, 1.0],
      ).createShader(Rect.fromLTWH(startX, topY, bandWidth, bandHeight));
    canvas.drawPath(bandPath, goldPaint);

    // Top and bottom bevel rails
    final topRail = Path()
      ..moveTo(startX, topY)
      ..quadraticBezierTo(cx, topY + curveDip, endX, topY);
    canvas.drawPath(
      topRail,
      Paint()
        ..color = const Color(0xFFFFF7D6)
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke,
    );

    final botRail = Path()
      ..moveTo(startX, botY)
      ..quadraticBezierTo(cx, botY + curveDip, endX, botY);
    canvas.drawPath(
      botRail,
      Paint()
        ..color = const Color(0xFF382303)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke,
    );

    // Dual Pearl Rails (natural, warm, matte-luminous pearls)
    final pearlCount = (bandWidth / 13.0).round().clamp(12, 22);
    final pRad = (bandHeight * 0.13).clamp(2.5, 3.8);

    void drawPearl(Offset pt) {
      final pShader = RadialGradient(
        center: const Alignment(-0.35, -0.35),
        radius: 0.85,
        colors: const [
          Color(0xFFFFFFFF),
          Color(0xFFF7F2E8),
          Color(0xFFDDD5C7),
          Color(0xFFA69986),
        ],
      ).createShader(Rect.fromCircle(center: pt, radius: pRad));
      canvas.drawCircle(pt, pRad, Paint()..shader = pShader);
      // Subtle specular dot
      canvas.drawCircle(
        pt - Offset(pRad * 0.30, pRad * 0.30),
        pRad * 0.25,
        Paint()..color = Colors.white,
      );
    }

    for (int i = 0; i < pearlCount; i++) {
      final t = i / (pearlCount - 1);
      final px = startX + t * bandWidth;
      final cY = math.sin(t * math.pi) * curveDip;
      drawPearl(Offset(px, topY + pRad + 1.2 + cY));
      drawPearl(Offset(px, botY - pRad - 1.2 + cY));
    }

    // Centered Solitaire Gemstone matching crown color
    final jewelCenter = Offset(cx, bandCenterY + curveDip * 0.5);
    final jewelW = bandHeight * 0.88;
    final jewelH = bandHeight * 0.60;
    final jRect = Rect.fromCenter(center: jewelCenter, width: jewelW, height: jewelH);

    // Gold Bezel Mount
    canvas.drawRRect(
      RRect.fromRectAndRadius(jRect.inflate(3.0), const Radius.circular(5.0)),
      Paint()..color = const Color(0xFFD4AF37),
    );

    // Gemstone with rich color
    final gemShader = RadialGradient(
      center: const Alignment(-0.30, -0.30),
      radius: 0.85,
      colors: [
        Color.lerp(glowColor, Colors.white, 0.45)!,
        glowColor,
        Color.lerp(glowColor, Colors.black, 0.65)!,
      ],
      stops: const [0.0, 0.50, 1.0],
    ).createShader(jRect);

    canvas.drawRRect(
      RRect.fromRectAndRadius(jRect, const Radius.circular(3.0)),
      Paint()..shader = gemShader,
    );

    // Gem Facet Highlight
    canvas.drawCircle(
      jewelCenter - Offset(jewelW * 0.20, jewelH * 0.20),
      jewelH * 0.18,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.80)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.8),
    );

    canvas.restore();
  }

  void _paintShadowAndAura(
    Canvas canvas,
    Size size,
    double cx,
    double cy,
    double normYaw,
    double pitch,
  ) {
    final w = size.width, h = size.height;

    // Floor Shadow
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx + math.sin(normYaw) * w * 0.05, cy + h * 0.38),
        width: w * 0.75,
        height: (w * 0.18 * (1.0 - pitch * 0.35)).clamp(w * 0.08, w * 0.30),
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.50)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );

    // Soft Warm Royal Aura (no harsh glitter or bloom)
    final auraRect = Rect.fromCenter(
      center: Offset(cx, cy + h * 0.06),
      width: w,
      height: h * 0.85,
    );
    canvas.drawOval(
      auraRect,
      Paint()
        ..shader = RadialGradient(
          colors: [
            glowColor.withValues(alpha: 0.12),
            glowColor.withValues(alpha: 0.02),
            Colors.transparent,
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(auraRect),
    );
  }

  @override
  bool shouldRepaint(covariant CylinderCrownPainter old) =>
      old.yaw != yaw ||
      old.pitch != pitch ||
      old.frontImage != frontImage ||
      old.rearImage != rearImage ||
      old.glowColor != glowColor ||
      old.depthRatio != depthRatio ||
      old.hasVelvet != hasVelvet;
}
