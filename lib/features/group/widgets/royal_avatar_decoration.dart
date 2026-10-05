import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:worship_chat/features/group/utils/queendom_emblem_helper.dart';

/// Animation style for the royal crown avatar decoration.
enum RoyalCrownAnimationStyle {
  /// Two radiant celestial halves sweep in from the left and right,
  /// collide at the apex in a burst of light, forge the 3D crown, hover majestically, and repeat.
  convergeAndCreate,

  /// Discord-style floating, breathing, and fading in place.
  floatAndBreathe,
}

/// Data model for an animated celestial stardust dot in the vortex.
class _StardustDot {
  /// -1.0 for left flank origin, +1.0 for right flank origin
  final double streamSide;

  /// Base angle in the orbital vortex (0 to 2*pi radians)
  final double orbitAngle;

  /// Radial variance for natural cosmic distribution (0.75 to 1.25)
  final double radiusFactor;

  /// Vertical tilt in the tilted ellipse (-0.25 to 0.25)
  final double verticalTilt;

  /// Radius/size of the particle (2.4 to 4.8)
  final double size;

  /// Speed multiplier for angular velocity
  final double speedFactor;

  /// Inward delay offset (0.0 to 0.08)
  final double delay;

  /// Peak brightness / opacity multiplier (0.75 to 1.0)
  final double brightness;

  const _StardustDot({
    required this.streamSide,
    required this.orbitAngle,
    required this.radiusFactor,
    required this.verticalTilt,
    required this.size,
    required this.speedFactor,
    required this.delay,
    required this.brightness,
  });
}

/// High-performance painter rendering the swirling stardust dots and celestial vortex rings.
class _StardustVortexPainter extends CustomPainter {
  final double t; // 0.0 to 1.0 loop progress
  final double crownSize;
  final Color accentColor;

  static const List<_StardustDot> _dots = [
    // ── Left stream dots (sweep from left flank into vortex) ───────────
    _StardustDot(
        streamSide: -1.0,
        orbitAngle: 0.00,
        radiusFactor: 1.00,
        verticalTilt: 0.00,
        size: 4.2,
        speedFactor: 1.10,
        delay: 0.00,
        brightness: 1.00),
    _StardustDot(
        streamSide: -1.0,
        orbitAngle: 0.52,
        radiusFactor: 0.85,
        verticalTilt: -0.15,
        size: 3.2,
        speedFactor: 0.90,
        delay: 0.02,
        brightness: 0.85),
    _StardustDot(
        streamSide: -1.0,
        orbitAngle: 1.05,
        radiusFactor: 1.15,
        verticalTilt: 0.20,
        size: 4.5,
        speedFactor: 1.20,
        delay: 0.04,
        brightness: 0.95),
    _StardustDot(
        streamSide: -1.0,
        orbitAngle: 1.57,
        radiusFactor: 0.90,
        verticalTilt: -0.10,
        size: 2.8,
        speedFactor: 1.00,
        delay: 0.01,
        brightness: 0.80),
    _StardustDot(
        streamSide: -1.0,
        orbitAngle: 2.09,
        radiusFactor: 1.20,
        verticalTilt: 0.25,
        size: 4.8,
        speedFactor: 1.15,
        delay: 0.05,
        brightness: 1.00),
    _StardustDot(
        streamSide: -1.0,
        orbitAngle: 2.62,
        radiusFactor: 0.80,
        verticalTilt: -0.20,
        size: 3.0,
        speedFactor: 0.85,
        delay: 0.03,
        brightness: 0.85),
    _StardustDot(
        streamSide: -1.0,
        orbitAngle: 3.14,
        radiusFactor: 1.05,
        verticalTilt: 0.05,
        size: 4.0,
        speedFactor: 1.05,
        delay: 0.06,
        brightness: 0.90),
    _StardustDot(
        streamSide: -1.0,
        orbitAngle: 3.66,
        radiusFactor: 0.95,
        verticalTilt: -0.15,
        size: 3.5,
        speedFactor: 1.25,
        delay: 0.02,
        brightness: 0.90),
    _StardustDot(
        streamSide: -1.0,
        orbitAngle: 4.19,
        radiusFactor: 1.10,
        verticalTilt: 0.18,
        size: 4.4,
        speedFactor: 0.95,
        delay: 0.05,
        brightness: 0.95),
    _StardustDot(
        streamSide: -1.0,
        orbitAngle: 4.71,
        radiusFactor: 0.75,
        verticalTilt: -0.25,
        size: 2.6,
        speedFactor: 1.30,
        delay: 0.01,
        brightness: 0.75),
    _StardustDot(
        streamSide: -1.0,
        orbitAngle: 5.23,
        radiusFactor: 1.25,
        verticalTilt: 0.10,
        size: 4.6,
        speedFactor: 1.10,
        delay: 0.07,
        brightness: 1.00),
    _StardustDot(
        streamSide: -1.0,
        orbitAngle: 5.76,
        radiusFactor: 0.88,
        verticalTilt: -0.08,
        size: 3.4,
        speedFactor: 1.00,
        delay: 0.03,
        brightness: 0.85),

    // ── Right stream dots (sweep from right flank into vortex) ──────────
    _StardustDot(
        streamSide: 1.0,
        orbitAngle: 0.26,
        radiusFactor: 0.92,
        verticalTilt: 0.12,
        size: 4.0,
        speedFactor: 1.05,
        delay: 0.01,
        brightness: 0.95),
    _StardustDot(
        streamSide: 1.0,
        orbitAngle: 0.78,
        radiusFactor: 1.10,
        verticalTilt: -0.18,
        size: 3.6,
        speedFactor: 1.20,
        delay: 0.03,
        brightness: 0.85),
    _StardustDot(
        streamSide: 1.0,
        orbitAngle: 1.31,
        radiusFactor: 0.82,
        verticalTilt: 0.22,
        size: 4.6,
        speedFactor: 0.90,
        delay: 0.05,
        brightness: 1.00),
    _StardustDot(
        streamSide: 1.0,
        orbitAngle: 1.83,
        radiusFactor: 1.18,
        verticalTilt: -0.12,
        size: 2.9,
        speedFactor: 1.15,
        delay: 0.02,
        brightness: 0.80),
    _StardustDot(
        streamSide: 1.0,
        orbitAngle: 2.35,
        radiusFactor: 0.88,
        verticalTilt: 0.15,
        size: 4.3,
        speedFactor: 1.00,
        delay: 0.06,
        brightness: 0.95),
    _StardustDot(
        streamSide: 1.0,
        orbitAngle: 2.88,
        radiusFactor: 1.05,
        verticalTilt: -0.22,
        size: 3.3,
        speedFactor: 1.25,
        delay: 0.00,
        brightness: 0.90),
    _StardustDot(
        streamSide: 1.0,
        orbitAngle: 3.40,
        radiusFactor: 0.78,
        verticalTilt: 0.08,
        size: 4.5,
        speedFactor: 0.85,
        delay: 0.04,
        brightness: 1.00),
    _StardustDot(
        streamSide: 1.0,
        orbitAngle: 3.92,
        radiusFactor: 1.12,
        verticalTilt: -0.16,
        size: 3.1,
        speedFactor: 1.10,
        delay: 0.02,
        brightness: 0.85),
    _StardustDot(
        streamSide: 1.0,
        orbitAngle: 4.45,
        radiusFactor: 0.96,
        verticalTilt: 0.24,
        size: 4.7,
        speedFactor: 1.30,
        delay: 0.07,
        brightness: 1.00),
    _StardustDot(
        streamSide: 1.0,
        orbitAngle: 4.97,
        radiusFactor: 1.22,
        verticalTilt: -0.10,
        size: 2.7,
        speedFactor: 0.95,
        delay: 0.03,
        brightness: 0.75),
    _StardustDot(
        streamSide: 1.0,
        orbitAngle: 5.50,
        radiusFactor: 0.85,
        verticalTilt: 0.16,
        size: 4.1,
        speedFactor: 1.15,
        delay: 0.05,
        brightness: 0.90),
    _StardustDot(
        streamSide: 1.0,
        orbitAngle: 6.02,
        radiusFactor: 1.08,
        verticalTilt: -0.20,
        size: 3.8,
        speedFactor: 1.05,
        delay: 0.01,
        brightness: 0.95),
  ];

  const _StardustVortexPainter({
    required this.t,
    required this.crownSize,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final scaleRatio = (crownSize / 40.0).clamp(0.65, 1.4);

    // ── Phase A: Inward Approach & Swirling Vortex (0.0 <= t < 0.38) ───
    if (t < 0.38) {
      final p = (t / 0.38).clamp(0.0, 1.0);

      // Faint glowing cosmic orbital ring along vortex path
      if (p >= 0.18) {
        final ringP = ((p - 0.18) / 0.82).clamp(0.0, 1.0);
        final ringAlpha = (math.sin(ringP * math.pi) * 0.45).clamp(0.0, 1.0);
        final ringR =
            crownSize * 0.65 * (1.0 - Curves.easeInQuad.transform(ringP));
        if (ringR > 3.0 && ringAlpha > 0.02) {
          final ringPaint = Paint()
            ..color = accentColor.withValues(alpha: ringAlpha)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);
          canvas.drawOval(
            Rect.fromCenter(
              center: center,
              width: ringR * 2.0,
              height: ringR * 1.25,
            ),
            ringPaint,
          );
        }
      }

      // Draw each stardust dot
      for (final dot in _dots) {
        double x, y, alpha;

        if (p < 0.20) {
          // Approach stage: flying in from left & right flanks towards orbit
          final subP = (p / 0.20).clamp(0.0, 1.0);
          final ease = Curves.easeOutCubic.transform(subP);

          final startX =
              dot.streamSide * crownSize * (1.75 + 0.35 * dot.delay);
          final startY = crownSize * (0.15 + dot.verticalTilt * 0.65);

          final orbitR = crownSize * 0.68 * dot.radiusFactor;
          final targetX = orbitR * math.cos(dot.orbitAngle);
          final targetY = orbitR * math.sin(dot.orbitAngle) * 0.60;

          x = startX + (targetX - startX) * ease;
          y = startY + (targetY - startY) * ease;
          alpha =
              ((t - dot.delay * 0.2) / 0.06).clamp(0.0, 1.0) * dot.brightness;
        } else {
          // Swirling Vortex stage: active rotation & inward spiral into core
          final rotP = ((p - 0.20) / 0.80).clamp(0.0, 1.0);
          final spinAngle = dot.orbitAngle +
              (2.6 * math.pi * dot.speedFactor * math.pow(rotP, 1.15));
          final currentR = crownSize *
              0.68 *
              dot.radiusFactor *
              (1.0 - Curves.easeInQuad.transform(rotP));

          x = currentR * math.cos(spinAngle);
          y = currentR * math.sin(spinAngle) * 0.60;
          alpha = (dot.brightness * (0.85 + 0.35 * rotP)).clamp(0.0, 1.0);

          // Subtle motion tail behind large dots
          if (dot.size >= 4.0 && currentR > 6.0) {
            final tailAngle = spinAngle - 0.28 * dot.speedFactor;
            final tailR = currentR * 1.08;
            final tailX = tailR * math.cos(tailAngle);
            final tailY = tailR * math.sin(tailAngle) * 0.60;
            final tailPaint = Paint()
              ..color =
                  accentColor.withValues(alpha: (alpha * 0.35).clamp(0.0, 1.0))
              ..strokeWidth = 1.4
              ..strokeCap = StrokeCap.round
              ..style = PaintingStyle.stroke;
            canvas.drawLine(
              center + Offset(tailX, tailY),
              center + Offset(x, y),
              tailPaint,
            );
          }
        }

        if (alpha > 0.02) {
          _drawGlowingDot(
            canvas: canvas,
            pos: center + Offset(x, y),
            size: dot.size * scaleRatio,
            alpha: alpha,
            accentColor: accentColor,
          );
        }
      }
    }
    // ── Phase B: Ambient Floating Embers during Crown Hover (0.38 <= t < 0.82)
    else if (t >= 0.38 && t < 0.82) {
      final norm = ((t - 0.38) / 0.44).clamp(0.0, 1.0);
      for (final dot in _dots) {
        if (dot.size < 3.4) continue; // Ambient subset
        final angle =
            dot.orbitAngle + norm * math.pi * 0.85 * dot.speedFactor;
        final r = crownSize *
            (0.48 + 0.16 * math.sin(norm * math.pi * 3 + dot.delay * 10));
        final x = r * math.cos(angle);
        final y = r * math.sin(angle) * 0.55;
        final alpha = (0.55 *
                (0.35 +
                    0.65 *
                        math
                            .sin(norm * math.pi * 4 + dot.orbitAngle)
                            .abs()) *
                dot.brightness)
            .clamp(0.0, 1.0);

        if (alpha > 0.02) {
          _drawGlowingDot(
            canvas: canvas,
            pos: center + Offset(x, y),
            size: dot.size * scaleRatio * 0.85,
            alpha: alpha,
            accentColor: accentColor,
          );
        }
      }
    }
    // ── Phase C: Crown Dissolve & Stardust Dispersal (0.82 <= t <= 1.00) ─
    else if (t >= 0.82) {
      final dispP = ((t - 0.82) / 0.18).clamp(0.0, 1.0);
      final dispEase = Curves.easeOutQuad.transform(dispP);

      for (final dot in _dots) {
        final dispR = crownSize * 0.95 * dot.radiusFactor * dispEase;
        final dispAngle = dot.orbitAngle + dispP * 0.6 * dot.speedFactor;
        final x = dispR * math.cos(dispAngle);
        final y = dispR * math.sin(dispAngle) * 0.65;
        final alpha = ((1.0 - dispP) * dot.brightness).clamp(0.0, 1.0);

        if (alpha > 0.02) {
          _drawGlowingDot(
            canvas: canvas,
            pos: center + Offset(x, y),
            size: dot.size * scaleRatio * (1.0 - 0.25 * dispP),
            alpha: alpha,
            accentColor: accentColor,
          );
        }
      }
    }
  }

  /// Draws a single celestial stardust dot with radiant aura glow and white-hot core.
  void _drawGlowingDot({
    required Canvas canvas,
    required Offset pos,
    required double size,
    required double alpha,
    required Color accentColor,
  }) {
    // Outer aura glow
    final auraPaint = Paint()
      ..color = accentColor.withValues(alpha: (alpha * 0.60).clamp(0.0, 1.0))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
    canvas.drawCircle(pos, size * 1.5, auraPaint);

    // Inner bright/white core
    final corePaint = Paint()
      ..color = Colors.white.withValues(alpha: alpha.clamp(0.0, 1.0));
    canvas.drawCircle(pos, size * 0.70, corePaint);
  }

  @override
  bool shouldRepaint(_StardustVortexPainter oldDelegate) =>
      oldDelegate.t != t ||
      oldDelegate.crownSize != crownSize ||
      oldDelegate.accentColor != accentColor;
}

/// An animated avatar decoration that creates the group's bespoke royal crown
/// with effects sweeping from left and right, colliding at the apex, and forging
/// the complete crown.
class RoyalAvatarDecoration extends StatefulWidget {
  /// The avatar widget (e.g. CircleAvatar or Hero-wrapped CircleAvatar).
  final Widget child;

  /// Radius of the avatar circle.
  final double avatarRadius;

  /// Queendom position name (e.g. 'Queen', 'First Born Princess', etc.).
  final String? position;

  /// Emoji fallback to identify the crown.
  final String? emoji;

  /// Optional living place string to extract the crown from.
  final String? livingPlace;

  /// Direct path to the crown PNG asset if known.
  final String? crownAsset;

  /// Radiant accent color for the crown glow and aura ring.
  final Color accentColor;

  /// Size of the crown. Defaults to ~62% of avatar diameter.
  final double? crownSize;

  /// Top offset for crown placement relative to top of avatar.
  final double? crownTopOffset;

  /// Animation mode: convergeAndCreate (default) or floatAndBreathe.
  final RoyalCrownAnimationStyle animationStyle;

  /// Optional duration of the animation loop. Defaults to 5200ms for converge, 4200ms for float.
  final Duration? animationDuration;

  /// Whether the animation is active.
  final bool enableAnimation;

  /// Whether to display a pulsing aura ring around the avatar border.
  final bool showAuraRing;

  /// Whether to render micro-sparkles around the crown.
  final bool showSparkles;

  /// Optional bottom-right badge (e.g. zoom indicator or unread status dot).
  final Widget? badge;

  /// Whether to perch the crown fully outside above the avatar rim (default: true).
  /// When true, the crown sits on top of the rim without overlapping/clipping into the avatar photo.
  final bool perchOutside;

  /// Optional bottom offset for badge placement.
  final double? badgeBottomOffset;

  /// Optional right offset for badge placement.
  final double? badgeRightOffset;

  /// Optional tap handler for the entire avatar.
  final VoidCallback? onTap;

  const RoyalAvatarDecoration({
    super.key,
    required this.child,
    this.avatarRadius = 50.0,
    this.position,
    this.emoji,
    this.livingPlace,
    this.crownAsset,
    this.accentColor = const Color(0xFFFFD700),
    this.crownSize,
    this.crownTopOffset,
    this.animationStyle = RoyalCrownAnimationStyle.convergeAndCreate,
    this.animationDuration,
    this.enableAnimation = true,
    this.showAuraRing = true,
    this.showSparkles = true,
    this.badge,
    this.perchOutside = true,
    this.badgeBottomOffset,
    this.badgeRightOffset,
    this.onTap,
  });

  @override
  State<RoyalAvatarDecoration> createState() => _RoyalAvatarDecorationState();
}

class _RoyalAvatarDecorationState extends State<RoyalAvatarDecoration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  Duration _resolveDuration() {
    if (widget.animationDuration != null) return widget.animationDuration!;
    final isConverge =
        widget.animationStyle == RoyalCrownAnimationStyle.convergeAndCreate;
    return Duration(milliseconds: isConverge ? 5200 : 4200);
  }

  @override
  void initState() {
    super.initState();
    final isConverge =
        widget.animationStyle == RoyalCrownAnimationStyle.convergeAndCreate;
    _controller = AnimationController(
      vsync: this,
      duration: _resolveDuration(),
    );

    if (widget.enableAnimation) {
      if (isConverge) {
        _controller.repeat();
      } else {
        _controller.repeat(reverse: true);
      }
    }
  }

  @override
  void didUpdateWidget(RoyalAvatarDecoration oldWidget) {
    super.didUpdateWidget(oldWidget);
    final isConverge =
        widget.animationStyle == RoyalCrownAnimationStyle.convergeAndCreate;

    if (widget.animationStyle != oldWidget.animationStyle ||
        widget.animationDuration != oldWidget.animationDuration) {
      _controller.duration = _resolveDuration();
      _controller.reset();
      if (widget.enableAnimation) {
        if (isConverge) {
          _controller.repeat();
        } else {
          _controller.repeat(reverse: true);
        }
      }
    } else if (widget.enableAnimation != oldWidget.enableAnimation) {
      if (widget.enableAnimation) {
        if (widget.animationStyle ==
            RoyalCrownAnimationStyle.convergeAndCreate) {
          _controller.repeat();
        } else {
          _controller.repeat(reverse: true);
        }
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _resolveCrownAsset() {
    if (widget.crownAsset != null) return widget.crownAsset;
    final fromPosOrEmoji = QueendomEmblemHelper.getAsset(
      position: widget.position,
      emoji: widget.emoji,
    );
    if (fromPosOrEmoji != null) return fromPosOrEmoji;
    if (widget.livingPlace != null && widget.livingPlace!.isNotEmpty) {
      return QueendomEmblemHelper.getAssetFromLivingPlace(widget.livingPlace!);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final crownAsset = _resolveCrownAsset();
    final diameter = widget.avatarRadius * 2;
    final crownSize = widget.crownSize ?? (diameter * 0.62).clamp(28.0, 84.0);
    // When perchOutside is true, crown perches directly above the top rim of the avatar (y = 8.0)
    // without cutting down into the circular avatar photo clip box.
    final crownTopOffset = widget.crownTopOffset ??
        (widget.perchOutside ? (8.0 - crownSize * 0.85) : (-crownSize * 0.48));
    final showSparkles = widget.showSparkles && crownSize >= 26.0;

    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = widget.enableAnimation ? _controller.value : 0.6;

          return SizedBox(
            width: diameter + 16,
            height: diameter + 16,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                // ── Pulsing Aura Border Ring ─────────────────────────────────
                if (widget.showAuraRing)
                  _buildAuraRing(diameter, t, widget.accentColor),

                // ── Core Avatar Child ─────────────────────────────────────────
                widget.child,

                // ── Animated Crown Decoration ────────────────────────────────
                if (crownAsset != null)
                  widget.animationStyle ==
                          RoyalCrownAnimationStyle.convergeAndCreate
                      ? _buildConvergeCrown(
                          crownAsset: crownAsset,
                          crownSize: crownSize,
                          crownTopOffset: crownTopOffset,
                          t: t,
                          accentColor: widget.accentColor,
                          showSparkles: showSparkles,
                        )
                      : _buildFloatBreatheCrown(
                          crownAsset: crownAsset,
                          crownSize: crownSize,
                          crownTopOffset: crownTopOffset,
                          t: t,
                          accentColor: widget.accentColor,
                          showSparkles: showSparkles,
                        ),

                // ── Optional Zoom / Action / Unread / Position Badge ──────────
                if (widget.badge != null)
                  Positioned(
                    bottom: widget.badgeBottomOffset ?? 0,
                    right: widget.badgeRightOffset ?? 0,
                    child: widget.badge!,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Builds the pulsing outer aura border around the avatar circle.
  Widget _buildAuraRing(double diameter, double t, Color accentColor) {
    // Smooth breathing alpha across the loop
    final ringAlpha = (0.45 + 0.45 * math.sin(t * math.pi * 2)).clamp(0.2, 0.95);
    final glowRadius = (6.0 + 10.0 * math.sin(t * math.pi * 2)).clamp(4.0, 18.0);

    return Container(
      width: diameter + 8,
      height: diameter + 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: accentColor.withValues(alpha: ringAlpha),
          width: 2.2,
        ),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: (0.35 * ringAlpha).clamp(0.0, 1.0)),
            blurRadius: glowRadius,
            spreadRadius: 1.5,
          ),
        ],
      ),
    );
  }

  /// The Stardust Vortex & Crown Creation Animation.
  /// Phase 1 (0.00 -> 0.38): Stardust dots stream in from left & right, rotate in a swirling vortex, and spiral into the center.
  /// Phase 2 (0.34 -> 0.48): Celestial radial flash burst & expanding shockwave ring upon dot coalescence.
  /// Phase 3 (0.36 -> 0.82): Unified 3D crown forms from the stardust with elastic pop, hover bobbing, and sparkling stars.
  /// Phase 4 (0.82 -> 1.00): Crown softly dissolves into dispersing starlight dots and loops.
  Widget _buildConvergeCrown({
    required String crownAsset,
    required double crownSize,
    required double crownTopOffset,
    required double t,
    required Color accentColor,
    required bool showSparkles,
  }) {
    final showFlash = t >= 0.34 && t <= 0.48;

    return Positioned(
      top: crownTopOffset,
      child: SizedBox(
        width: crownSize,
        height: crownSize,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // ── Swirling Stardust Dots & Celestial Vortex ─────────────────────
            CustomPaint(
              size: Size(crownSize, crownSize),
              painter: _StardustVortexPainter(
                t: t,
                crownSize: crownSize,
                accentColor: accentColor,
              ),
            ),

            // ── Collision Flash Burst & Shockwave ─────────────────────────────
            if (showFlash)
              _buildFlashBurst(
                crownSize: crownSize,
                t: t,
                accentColor: accentColor,
              ),

            // ── Unified Forged 3D Crown ───────────────────────────────────────
            _buildUnifiedCrown(
              crownAsset: crownAsset,
              crownSize: crownSize,
              t: t,
              accentColor: accentColor,
              showSparkles: showSparkles,
            ),
          ],
        ),
      ),
    );
  }

  /// Renders the flash burst and shockwave ring upon collision.
  Widget _buildFlashBurst({
    required double crownSize,
    required double t,
    required Color accentColor,
  }) {
    final flashNorm = ((t - 0.34) / 0.14).clamp(0.0, 1.0);
    final flashOpacity = math.sin(flashNorm * math.pi).clamp(0.0, 1.0);
    final flashDiameter = crownSize * (0.5 + 1.1 * flashNorm);

    return Opacity(
      opacity: flashOpacity,
      child: Container(
        width: flashDiameter,
        height: flashDiameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              Colors.white,
              accentColor.withValues(alpha: 0.8),
              accentColor.withValues(alpha: 0.0),
            ],
            stops: const [0.0, 0.45, 1.0],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.8 * flashOpacity),
              blurRadius: 20.0,
              spreadRadius: 4.0,
            ),
          ],
        ),
      ),
    );
  }

  /// Renders the unified forged crown with elastic spring pop, hovering, and fadeout.
  Widget _buildUnifiedCrown({
    required String crownAsset,
    required double crownSize,
    required double t,
    required Color accentColor,
    required bool showSparkles,
  }) {
    // Hidden during incoming swirl vortex (pre-warmed for instant GPU display)
    if (t < 0.36) {
      return Opacity(
        opacity: 0.0,
        child: Image.asset(
          crownAsset,
          width: crownSize,
          height: crownSize,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      );
    }

    // Elastic spring pop on initial creation
    final popNorm = ((t - 0.36) / 0.14).clamp(0.0, 1.0);
    final popScale =
        popNorm < 1.0 ? Curves.easeOutBack.transform(popNorm) : 1.0;

    // Gentle levitating bobbing during display
    final hoverBob =
        math.sin(((t - 0.36) / 0.46).clamp(0.0, 1.0) * math.pi * 2) * 2.8;

    // Fadeout & dissolve in final phase
    double crownOpacity = 1.0;
    double dissolveScale = 1.0;
    if (t >= 0.82) {
      final dissolveNorm = ((t - 0.82) / 0.18).clamp(0.0, 1.0);
      crownOpacity = 1.0 - Curves.easeInOut.transform(dissolveNorm);
      dissolveScale = 1.0 + 0.08 * dissolveNorm;
    }

    // Sparkles twinkle between 0.45 and 0.80
    final sparkleAlpha = (t >= 0.42 && t <= 0.80)
        ? math.sin(((t - 0.42) / 0.38).clamp(0.0, 1.0) * math.pi)
        : 0.0;

    return Transform.translate(
      offset: Offset(0, -hoverBob),
      child: Transform.scale(
        scale: (0.7 + 0.3 * popScale) * dissolveScale,
        child: Opacity(
          opacity: crownOpacity.clamp(0.0, 1.0),
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // Radiant golden glow backdrop
              Container(
                width: crownSize * 0.85,
                height: crownSize * 0.85,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: accentColor.withValues(alpha: 0.50 * crownOpacity),
                      blurRadius: 18.0,
                      spreadRadius: 3.0,
                    ),
                  ],
                ),
              ),

              // Bespoke 3D Royal Crown Asset
              Image.asset(
                crownAsset,
                width: crownSize,
                height: crownSize,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),

              // Left micro-sparkle twinkle
              if (showSparkles && sparkleAlpha > 0.05) ...[
                Positioned(
                  top: 2,
                  left: -4,
                  child: Opacity(
                    opacity: (sparkleAlpha * crownOpacity).clamp(0.0, 1.0),
                    child: Icon(
                      Icons.auto_awesome,
                      size: crownSize * 0.24,
                      color: const Color(0xFFFFF9C4),
                    ),
                  ),
                ),
                // Right micro-sparkle twinkle
                Positioned(
                  top: 4,
                  right: -4,
                  child: Opacity(
                    opacity:
                        (sparkleAlpha * 0.85 * crownOpacity).clamp(0.0, 1.0),
                    child: Icon(
                      Icons.star_rounded,
                      size: crownSize * 0.22,
                      color: const Color(0xFFFFE082),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Fallback: Discord-style continuous float & breathe.
  Widget _buildFloatBreatheCrown({
    required String crownAsset,
    required double crownSize,
    required double crownTopOffset,
    required double t,
    required Color accentColor,
    required bool showSparkles,
  }) {
    final fadeVal = 0.25 + 0.75 * math.sin(t * math.pi);
    final floatVal = -3.5 * math.sin(t * math.pi);
    final scaleVal = 0.95 + 0.08 * math.sin(t * math.pi);

    return Positioned(
      top: crownTopOffset + floatVal,
      child: Transform.scale(
        scale: scaleVal,
        child: Opacity(
          opacity: fadeVal.clamp(0.0, 1.0),
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Container(
                width: crownSize * 0.85,
                height: crownSize * 0.85,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: accentColor.withValues(alpha: 0.50 * fadeVal),
                      blurRadius: 18.0,
                      spreadRadius: 3.0,
                    ),
                  ],
                ),
              ),
              Image.asset(
                crownAsset,
                width: crownSize,
                height: crownSize,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
              if (showSparkles) ...[
                Positioned(
                  top: 2,
                  left: -4,
                  child: Opacity(
                    opacity: (fadeVal * 0.9).clamp(0.0, 1.0),
                    child: Icon(
                      Icons.auto_awesome,
                      size: crownSize * 0.24,
                      color: const Color(0xFFFFF9C4),
                    ),
                  ),
                ),
                Positioned(
                  top: 4,
                  right: -4,
                  child: Opacity(
                    opacity: (fadeVal * 0.8).clamp(0.0, 1.0),
                    child: Icon(
                      Icons.star_rounded,
                      size: crownSize * 0.22,
                      color: const Color(0xFFFFE082),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
