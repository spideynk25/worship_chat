import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Universal 360° crown painter. Works for every crown:
///  - front image only   -> back = mirrored front (same metal, gems, pearls)
///  - front + rear image -> back half uses the real rear artwork
class CylinderCrownPainter extends CustomPainter {
  final ui.Image frontImage;
  final ui.Image? rearImage;
  final double yaw;
  final double pitch;
  final Color glowColor;

  /// Head ellipse depth relative to half-width. 0.8 = slightly oval head.
  final double depthRatio;

  const CylinderCrownPainter({
    required this.frontImage,
    this.rearImage,
    required this.yaw,
    required this.pitch,
    required this.glowColor,
    this.depthRatio = 0.80,
  });

  // Must be a multiple of 4 so ±90° land exactly on a column edge.
  static const int _cols = 72;
  // Light direction (x, z).
  static const double _lx = -0.38, _lz = 0.92;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height, cx = w / 2;

    _paintShadowAndAura(canvas, size);

    final dest = Rect.fromCenter(
      center: Offset(cx, h / 2 - h * 0.03),
      width: w * 0.82,
      height: h * 0.82,
    );
    final rx = dest.width / 2;
    final rz = rx * depthRatio;
    final hh = dest.height / 2;
    final cy = dest.center.dy;
    final cam = w * 3.4;

    final cosY = math.cos(yaw), sinY = math.sin(yaw);
    final cosP = math.cos(pitch), sinP = math.sin(pitch);
    const dTheta = math.pi * 2 / _cols;
    const vCount = (_cols + 1) * 2;

    final pos = Float32List(vCount * 2);
    final uvFront = Float32List(vCount * 2);
    final uvRear = Float32List(vCount * 2);
    final colExt = Int32List(vCount);
    final colInt = Int32List(vCount);

    final fw = frontImage.width.toDouble();
    final fh = frontImage.height.toDouble();
    final rear = rearImage;
    final rw = (rear ?? frontImage).width.toDouble();
    final rh = (rear ?? frontImage).height.toDouble();

    for (int j = 0; j <= _cols; j++) {
      final th = -math.pi + j * dTheta;
      final sx = rx * math.sin(th);
      final cz = rz * math.cos(th);

      // Ring point rotated around Y.
      final x = sx * cosY + cz * sinY;
      final z = -sx * sinY + cz * cosY;

      // Ellipse surface normal, rotated by yaw, for lighting.
      var nx = math.sin(th) / rx;
      var nz = math.cos(th) / rz;
      final nl = math.sqrt(nx * nx + nz * nz);
      nx /= nl;
      nz /= nl;
      final nxr = nx * cosY + nz * sinY;
      final nzr = -nx * sinY + nz * cosY;
      final dot = nxr * _lx + nzr * _lz;

      final gExt = (0.80 + 0.20 * dot).clamp(0.58, 1.0);
      final gInt = (0.34 + 0.10 * -dot).clamp(0.28, 0.50);

      final uF = (0.5 + 0.5 * math.sin(th)) * fw;
      final uR = rear != null
          ? (0.5 - 0.5 * math.sin(th)) * rw // seen from behind, x flips
          : (0.5 + 0.5 * math.sin(th)) * fw; // mirrored front

      for (int k = 0; k < 2; k++) {
        final yl = k == 0 ? -hh : hh;
        final yy = yl * cosP - z * sinP;
        final zz = yl * sinP + z * cosP;
        final s = cam / (cam - zz);
        final vi = j * 2 + k;

        pos[vi * 2] = cx + x * s;
        pos[vi * 2 + 1] = cy + yy * s;

        uvFront[vi * 2] = uF;
        uvFront[vi * 2 + 1] = k == 0 ? 0 : fh;

        uvRear[vi * 2] = uR;
        uvRear[vi * 2 + 1] = k == 0 ? 0 : (rear != null ? rh : fh);

        colExt[vi] = _gray(gExt);
        colInt[vi] = _gray(gInt);
      }
    }

    // idx[half][exterior]: half 0 = front texture, 1 = back texture.
    final idx = <List<List<int>>>[
      [<int>[], <int>[]],
      [<int>[], <int>[]],
    ];
    for (int j = 0; j < _cols; j++) {
      final thm = -math.pi + (j + 0.5) * dTheta;
      var nx = math.sin(thm) / rx;
      var nz = math.cos(thm) / rz;
      final nl = math.sqrt(nx * nx + nz * nz);
      nx /= nl;
      nz /= nl;
      final exterior = (-nx * sinY + nz * cosY) > 0;
      final half = math.cos(thm) >= 0 ? 0 : 1;
      final a = j * 2, b = a + 1, c = a + 2, d = a + 3;
      idx[half][exterior ? 1 : 0].addAll([a, c, b, c, d, b]);
    }

    ui.ImageShader makeShader(ui.Image img) => ui.ImageShader(
          img,
          TileMode.clamp,
          TileMode.clamp,
          Matrix4.identity().storage,
          filterQuality: FilterQuality.medium,
        );

    final frontShader = makeShader(frontImage);
    final backShader = rear != null ? makeShader(rear) : frontShader;

    void draw(
      ui.ImageShader sh,
      Float32List uv,
      List<int> tri,
      Int32List colors,
    ) {
      if (tri.isEmpty) return;
      final v = ui.Vertices.raw(
        ui.VertexMode.triangles,
        pos,
        textureCoordinates: uv,
        colors: colors,
        indices: Uint16List.fromList(tri),
      );
      canvas.drawVertices(v, BlendMode.modulate, Paint()..shader = sh);
      v.dispose();
    }

    // 1) Interior (faces pointing away) first -> visible through open filigree.
    draw(frontShader, uvFront, idx[0][0], colInt);
    draw(backShader, uvRear, idx[1][0], colInt);
    // 2) Exterior (faces toward viewer) on top.
    draw(frontShader, uvFront, idx[0][1], colExt);
    draw(backShader, uvRear, idx[1][1], colExt);

    frontShader.dispose();
    if (rear != null) backShader.dispose();
  }

  static int _gray(double g) {
    final v = (g * 255).round().clamp(0, 255);
    return (0xFF << 24) | (v << 16) | (v << 8) | v;
  }

  void _paintShadowAndAura(Canvas canvas, Size size) {
    final w = size.width, h = size.height, cx = w / 2, cy = h / 2;

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx + math.sin(yaw) * w * 0.05, cy + h * 0.38),
        width: w * 0.75,
        height: (w * 0.18 * (1.0 - pitch * 0.35)).clamp(w * 0.08, w * 0.30),
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );

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
            glowColor.withValues(alpha: 0.15),
            glowColor.withValues(alpha: 0.03),
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
      old.depthRatio != depthRatio;
}