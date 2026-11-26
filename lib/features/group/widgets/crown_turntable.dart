import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:worship_chat/features/group/widgets/cylinder_crown_painter.dart';

/// Set to true if dragging feels like it rotates the crown the wrong way.
const bool kFlipTurntable = false;

/// Loads and caches the pre-rendered turntable frames of a crown.
class CrownTurntableCache {
  static const int frameCount = 36; // must match FRAMES in render_crowns.py
  static const int decodeWidth = 320;
  static const int maxCachedCrowns = 3;

  static final Map<String, List<ui.Image?>> _frames = {};
  static final Map<String, List<VoidCallback>> _listeners = {};
  static final Set<String> _loading = {};
  static final Set<String> _missing = {};
  static final List<String> _order = [];

  /// assets/emojis/queen.png -> "queen"
  static String keyFromAsset(String asset) {
    final file = asset.split('/').last;
    final dot = file.lastIndexOf('.');
    return dot == -1 ? file : file.substring(0, dot);
  }

  static String framePath(String key, int i) =>
      'assets/crowns/$key/${key}_${i.toString().padLeft(2, '0')}.png';

  static bool isReady(String key) {
    final f = _frames[key];
    return f != null && !f.any((e) => e == null);
  }

  static List<ui.Image?>? framesFor(String key) =>
      isReady(key) ? _frames[key] : null;

  static void load(BuildContext context, String key, VoidCallback onUpdate) {
    if (isReady(key) || _missing.contains(key)) {
      onUpdate();
      return;
    }
    _listeners.putIfAbsent(key, () => []).add(onUpdate);
    if (!_loading.add(key)) return;

    final frames = List<ui.Image?>.filled(frameCount, null);
    _frames[key] = frames;
    _order.remove(key);
    _order.add(key);
    while (_order.length > maxCachedCrowns) {
      final old = _order.removeAt(0);
      _frames.remove(old); // let GC free it (may still be painting)
    }

    var done = 0;
    var failed = false;
    final config = createLocalImageConfiguration(context);

    void finish() {
      _loading.remove(key);
      final cbs = _listeners.remove(key) ?? [];
      for (final cb in cbs) {
        cb();
      }
    }

    for (int i = 0; i < frameCount; i++) {
      final stream = ResizeImage(
        AssetImage(framePath(key, i)),
        width: decodeWidth,
        allowUpscaling: false,
      ).resolve(config);

      ImageStreamListener? l;
      l = ImageStreamListener(
        (info, _) {
          frames[i] = info.image;
          stream.removeListener(l!);
          done++;
          if (done == frameCount && !failed) finish();
        },
        onError: (e, s) {
          stream.removeListener(l!);
          if (!failed) {
            failed = true;
            _missing.add(key);
            _frames.remove(key);
            finish();
          }
        },
      );
      stream.addListener(l);
    }
  }
}

/// Picks (and cross-fades) the pre-rendered frames for the current yaw.
class TurntableCrownPainter extends CustomPainter {
  final List<ui.Image?> frames;
  final double yaw;
  final Color glowColor;

  const TurntableCrownPainter({
    required this.frames,
    required this.yaw,
    required this.glowColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height, cx = w / 2, cy = h / 2;

    // Floor shadow
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, cy + h * 0.40),
        width: w * 0.70,
        height: w * 0.16,
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );

    // Soft aura
    final auraRect = Rect.fromCenter(
      center: Offset(cx, cy + h * 0.05),
      width: w,
      height: h * 0.85,
    );
    canvas.drawOval(
      auraRect,
      Paint()
        ..shader = RadialGradient(
          colors: [
            glowColor.withValues(alpha: 0.15),
            glowColor.withValues(alpha: 0.03),
            Colors.transparent,
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(auraRect),
    );

    final n = frames.length;
    final a = kFlipTurntable ? -yaw : yaw;
    final turns = a / (math.pi * 2);
    final f = (turns - turns.floorToDouble()) * n;
    final i0 = f.floor() % n;
    final i1 = (i0 + 1) % n;
    final t = f - f.floor();

    final dest = Rect.fromCenter(
      center: Offset(cx, cy - h * 0.02),
      width: w * 0.92,
      height: h * 0.92,
    );

    void draw(ui.Image? img, double opacity) {
      if (img == null) return;
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        dest,
        Paint()
          ..filterQuality = FilterQuality.medium
          ..color = Colors.white.withValues(alpha: opacity),
      );
    }

    draw(frames[i0], 1.0);
    if (t > 0.02) draw(frames[i1], t);
  }

  @override
  bool shouldRepaint(covariant TurntableCrownPainter old) =>
      old.yaw != yaw || old.frames != frames || old.glowColor != glowColor;
}

/// Real 3D frames if they exist for this crown, otherwise the universal royal 3D painter.
CustomPainter buildCrownPainter({
  required String assetPath,
  required ui.Image frontImage,
  ui.Image? rearImage,
  required double yaw,
  required double pitch,
  required Color glowColor,
}) {
  final key = CrownTurntableCache.keyFromAsset(assetPath);
  final frames = CrownTurntableCache.framesFor(key);
  if (frames != null) {
    return TurntableCrownPainter(
      frames: frames,
      yaw: yaw,
      glowColor: glowColor,
    );
  }
  final isQueenImperial = assetPath.toLowerCase().contains('queen.png');
  return CylinderCrownPainter(
    frontImage: frontImage,
    rearImage: rearImage,
    yaw: yaw,
    pitch: pitch,
    glowColor: glowColor,
    hasVelvet: isQueenImperial,
  );
}