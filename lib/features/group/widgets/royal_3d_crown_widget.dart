import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:worship_chat/features/group/utils/queendom_emblem_helper.dart';
import 'package:worship_chat/features/group/widgets/crown_turntable.dart';

/// In-memory cache for decoded crown [ui.Image]s (front + optional rear).
class CrownImageCache {
  static final Map<String, ui.Image> _cache = {};
  static final Map<String, List<VoidCallback>> _listeners = {};

  static ui.Image? get(String assetPath) => _cache[assetPath];

  /// e.g. assets/emojis/queen.png -> assets/emojis/queen_rear.png
  static String? getRearPath(String frontPath) {
    final dot = frontPath.lastIndexOf('.');
    if (dot == -1) return null;
    return '${frontPath.substring(0, dot)}_rear${frontPath.substring(dot)}';
  }

  static void load(
    BuildContext context,
    String assetPath,
    VoidCallback onLoaded,
  ) {
    if (_cache.containsKey(assetPath)) {
      onLoaded();
      return;
    }

    _listeners.putIfAbsent(assetPath, () => []).add(onLoaded);
    if (_listeners[assetPath]!.length > 1) return;

    // Decode at max 768px wide: sharper downscaling + less memory.
    final imageProvider = ResizeImage(
      AssetImage(assetPath),
      width: 768,
      allowUpscaling: false,
    );
    final stream = imageProvider.resolve(createLocalImageConfiguration(context));
    ImageStreamListener? listener;
    listener = ImageStreamListener(
      (ImageInfo info, bool syncCall) {
        _cache[assetPath] = info.image;
        final callbacks = _listeners.remove(assetPath) ?? [];
        for (final cb in callbacks) {
          cb();
        }
        stream.removeListener(listener!);
      },
      onError: (err, stack) {
        _listeners.remove(assetPath);
        stream.removeListener(listener!);
      },
    );
    stream.addListener(listener);
  }

  /// Preloads the front image, the rear image (if the asset exists) and the
  /// pre-rendered 3D turntable frames (if they exist).
  static void loadSuite(
    BuildContext context,
    String frontPath,
    VoidCallback onLoaded,
  ) {
    load(context, frontPath, onLoaded);
    final rear = getRearPath(frontPath);
    if (rear != null) {
      load(context, rear, onLoaded);
    }
    CrownTurntableCache.load(
      context,
      CrownTurntableCache.keyFromAsset(frontPath),
      onLoaded,
    );
  }
}

/// Interactive volumetric 3D royal crown.
///
/// - If pre-rendered 3D turntable frames exist for the crown
///   (`assets/crowns/[name]/[name]_00..35.png`) they are used: real back,
///   real depth, real detail.
/// - Otherwise falls back to the cylinder-wrapped painter.
/// - Touch / hover tilt, idle floating sway, tap-to-inspect vault.
class Royal3dCrownWidget extends StatefulWidget {
  final String? position;
  final String? emoji;
  final String? assetPath;
  final double size;
  final Widget? fallback;
  final bool interactive;
  final bool idleFloating;
  final bool enableGlint;
  final bool enableShadow;
  final bool enableInspect;
  final Color? glowColor;
  final VoidCallback? onTap;

  const Royal3dCrownWidget({
    super.key,
    this.position,
    this.emoji,
    this.assetPath,
    this.size = 48.0,
    this.fallback,
    this.interactive = true,
    this.idleFloating = true,
    this.enableGlint = false,
    this.enableShadow = true,
    this.enableInspect = true,
    this.glowColor,
    this.onTap,
  });

  @override
  State<Royal3dCrownWidget> createState() => _Royal3dCrownWidgetState();

  static void showVault({
    required BuildContext context,
    String? position,
    String? emoji,
    String? assetPath,
    Color? glowColor,
  }) {
    final asset = assetPath ??
        QueendomEmblemHelper.getAsset(position: position, emoji: emoji);
    if (asset == null) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _RoyalCrownInspectSheet(
        assetPath: asset,
        title: position ?? 'Royal Crown',
        emoji: emoji,
        glowColor: glowColor,
      ),
    );
  }
}

class _Royal3dCrownWidgetState extends State<Royal3dCrownWidget>
    with TickerProviderStateMixin {
  late final AnimationController _idleController;
  late final AnimationController _springController;
  late final AnimationController _pulseController;

  double _dragTiltX = 0.0; // yaw   (-1.2 .. 1.2)
  double _dragTiltY = 0.0; // pitch (-1.2 .. 1.2)
  double _releasedTiltX = 0.0;
  double _releasedTiltY = 0.0;
  bool _isInteracting = false;
  String? _loadedAsset;

  @override
  void initState() {
    super.initState();
    _idleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3400),
    )..repeat();

    _springController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveImage();
  }

  @override
  void didUpdateWidget(covariant Royal3dCrownWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assetPath != widget.assetPath ||
        oldWidget.position != widget.position ||
        oldWidget.emoji != widget.emoji) {
      _resolveImage();
    }
  }

  String? _asset() =>
      widget.assetPath ??
      QueendomEmblemHelper.getAsset(
        position: widget.position,
        emoji: widget.emoji,
      );

  void _resolveImage() {
    final asset = _asset();
    if (asset != null && asset != _loadedAsset) {
      _loadedAsset = asset;
      CrownImageCache.loadSuite(context, asset, () {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _idleController.dispose();
    _springController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _onPanStart(DragStartDetails details) {
    if (!widget.interactive) return;
    setState(() {
      _isInteracting = true;
      _springController.stop();
    });
    _updateTilt(details.localPosition);
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (!widget.interactive) return;
    _updateTilt(details.localPosition);
  }

  void _onPanEnd(DragEndDetails details) {
    if (!widget.interactive) return;
    _releasedTiltX = _dragTiltX;
    _releasedTiltY = _dragTiltY;
    setState(() => _isInteracting = false);
    _springController.forward(from: 0.0);
  }

  void _onHover(PointerEvent event) {
    if (!widget.interactive) return;
    setState(() {
      _isInteracting = true;
      _springController.stop();
    });
    _updateTilt(event.localPosition);
  }

  void _onExit(PointerEvent event) {
    if (!widget.interactive) return;
    _releasedTiltX = _dragTiltX;
    _releasedTiltY = _dragTiltY;
    setState(() => _isInteracting = false);
    _springController.forward(from: 0.0);
  }

  void _updateTilt(Offset localPosition) {
    final half = widget.size / 2.0;
    if (half <= 0) return;
    final nx = ((localPosition.dx - half) / half).clamp(-1.2, 1.2);
    final ny = ((localPosition.dy - half) / half).clamp(-1.2, 1.2);
    setState(() {
      _dragTiltX = nx;
      _dragTiltY = ny;
    });
  }

  void _handleTap() {
    _pulseController.forward(from: 0.0);
    if (widget.onTap != null) {
      widget.onTap!();
    } else if (widget.enableInspect) {
      final asset = _asset();
      if (asset == null) return;
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (ctx) => _RoyalCrownInspectSheet(
          assetPath: asset,
          title: widget.position ?? 'Royal Crown',
          emoji: widget.emoji,
          glowColor: widget.glowColor,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final asset = _asset();

    if (asset == null) {
      return widget.fallback ?? const SizedBox.shrink();
    }

    final cachedUiImage = CrownImageCache.get(asset);
    final rearAsset = CrownImageCache.getRearPath(asset);
    final rearImage = rearAsset != null ? CrownImageCache.get(rearAsset) : null;
    final effectiveGlow = widget.glowColor ?? const Color(0xFFE5A93C);

    return AnimatedBuilder(
      animation: Listenable.merge([
        _idleController,
        _springController,
        _pulseController,
      ]),
      builder: (context, child) {
        double currentX;
        double currentY;

        if (_isInteracting) {
          currentX = _dragTiltX;
          currentY = _dragTiltY;
        } else {
          final springProgress =
              Curves.elasticOut.transform(_springController.value);
          final springX =
              ui.lerpDouble(_releasedTiltX, 0.0, springProgress) ?? 0.0;
          final springY =
              ui.lerpDouble(_releasedTiltY, 0.0, springProgress) ?? 0.0;

          if (widget.idleFloating) {
            final t = _idleController.value * math.pi * 2;
            currentX = springX + math.sin(t) * 0.16;
            currentY = springY + math.cos(t * 0.8) * 0.10;
          } else {
            currentX = springX;
            currentY = springY;
          }
        }

        // Tap pulse: 1.0 -> 0.94 -> 1.05 -> 1.0
        double tapScale = 1.0;
        if (_pulseController.isAnimating) {
          final p = _pulseController.value;
          if (p < 0.3) {
            tapScale = 1.0 - (p / 0.3) * 0.06;
          } else if (p < 0.7) {
            tapScale = 0.94 + ((p - 0.3) / 0.4) * 0.11;
          } else {
            tapScale = 1.05 - ((p - 0.7) / 0.3) * 0.05;
          }
        }

        final yawAngle = currentX * 0.52; // ~30°
        final pitchAngle = -currentY * 0.32; // ~18°

        final Widget crownDisplay;
        if (cachedUiImage != null) {
          crownDisplay = CustomPaint(
            size: Size(widget.size, widget.size),
            painter: buildCrownPainter(
              assetPath: asset,
              frontImage: cachedUiImage,
              rearImage: rearImage,
              yaw: yawAngle,
              pitch: pitchAngle,
              glowColor: effectiveGlow,
            ),
          );
        } else {
          crownDisplay = Image.asset(
            asset,
            width: widget.size,
            height: widget.size,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) =>
                widget.fallback ?? const SizedBox.shrink(),
          );
        }

        final transformed = Transform(
          transform: Matrix4.diagonal3Values(tapScale, tapScale, tapScale),
          alignment: Alignment.center,
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: crownDisplay,
          ),
        );

        if (!widget.interactive) return transformed;

        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onHover: _onHover,
          onExit: _onExit,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: _onPanStart,
            onPanUpdate: _onPanUpdate,
            onPanEnd: _onPanEnd,
            onTap: _handleTap,
            child: transformed,
          ),
        );
      },
    );
  }
}

/// Luxury 3D Royal Vault modal sheet for interactive crown inspection.
class _RoyalCrownInspectSheet extends StatefulWidget {
  final String assetPath;
  final String title;
  final String? emoji;
  final Color? glowColor;

  const _RoyalCrownInspectSheet({
    required this.assetPath,
    required this.title,
    this.emoji,
    this.glowColor,
  });

  @override
  State<_RoyalCrownInspectSheet> createState() =>
      _RoyalCrownInspectSheetState();
}

class _RoyalCrownInspectSheetState extends State<_RoyalCrownInspectSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turntableController;
  double _manualRotX = -0.15; // pitch
  double _manualRotY = 0.0; // yaw
  bool _isDragging = false;
  bool _autoTurntable = true;

  @override
  void initState() {
    super.initState();
    _turntableController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    CrownImageCache.loadSuite(context, widget.assetPath, () {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _turntableController.dispose();
    super.dispose();
  }

  void _setPresetAngle(double targetYaw, double targetPitch) {
    setState(() {
      _autoTurntable = false;
      _manualRotY = targetYaw;
      _manualRotX = targetPitch;
    });
  }

  @override
  Widget build(BuildContext context) {
    final effectiveColor = widget.glowColor ?? const Color(0xFFE5A93C);
    final cachedImage = CrownImageCache.get(widget.assetPath);
    final rearAsset = CrownImageCache.getRearPath(widget.assetPath);
    final rearImage = rearAsset != null ? CrownImageCache.get(rearAsset) : null;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0E17).withValues(alpha: 0.97),
        borderRadius: _verticalTopRadius,
        border: Border.all(
          color: effectiveColor.withValues(alpha: 0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: effectiveColor.withValues(alpha: 0.25),
            blurRadius: 30,
            spreadRadius: 2,
          ),
          const BoxShadow(
            color: Colors.black,
            blurRadius: 40,
            spreadRadius: 10,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Header
          Text(
            widget.title.toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            '3D ROYAL CROWN VAULT',
            style: TextStyle(
              color: effectiveColor,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.2,
            ),
          ),
          const SizedBox(height: 18),

          // 3D turntable box
          GestureDetector(
            onPanStart: (_) => setState(() {
              _isDragging = true;
              _autoTurntable = false;
            }),
            onPanUpdate: (d) {
              setState(() {
                _manualRotY += d.delta.dx * 0.015;
                _manualRotX =
                    (_manualRotX - d.delta.dy * 0.015).clamp(-0.55, 0.40);
              });
            },
            onPanEnd: (_) => setState(() => _isDragging = false),
            child: Container(
              height: 275,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    effectiveColor.withValues(alpha: 0.18),
                    Colors.black.withValues(alpha: 0.5),
                  ],
                  radius: 0.85,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _isDragging
                      ? effectiveColor
                      : effectiveColor.withValues(alpha: 0.25),
                  width: _isDragging ? 1.8 : 1.0,
                ),
              ),
              child: AnimatedBuilder(
                animation: _turntableController,
                builder: (context, _) {
                  final autoY = _autoTurntable
                      ? _turntableController.value * math.pi * 2
                      : 0.0;
                  final totalYaw = _manualRotY + autoY;
                  final totalPitch = _manualRotX;

                  if (cachedImage != null) {
                    return Center(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Exhibition plinth
                          Positioned(
                            bottom: 12,
                            child: Container(
                              width: 170,
                              height: 26,
                              decoration: BoxDecoration(
                                borderRadius: const BorderRadius.all(
                                  Radius.elliptical(85, 13),
                                ),
                                gradient: const RadialGradient(
                                  colors: [
                                    Color(0xFF221F30),
                                    Color(0xFF0F0E17),
                                  ],
                                ),
                                border: Border.all(
                                  color: effectiveColor.withValues(alpha: 0.65),
                                  width: 1.2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        effectiveColor.withValues(alpha: 0.25),
                                    blurRadius: 18,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          CustomPaint(
                            size: const Size(260, 240),
                            painter: buildCrownPainter(
                              assetPath: widget.assetPath,
                              frontImage: cachedImage,
                              rearImage: rearImage,
                              yaw: totalYaw,
                              pitch: totalPitch,
                              glowColor: effectiveColor,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  // Fallback while the image resolves.
                  final transform = Matrix4.identity()
                    ..setEntry(3, 2, 0.0018)
                    ..rotateY(totalYaw)
                    ..rotateX(totalPitch);

                  return Center(
                    child: Transform(
                      transform: transform,
                      alignment: Alignment.center,
                      child: Image.asset(
                        widget.assetPath,
                        width: 200,
                        height: 200,
                        fit: BoxFit.contain,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Angle preset chips
          Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              _buildPresetChip(
                  "0° FRONT", () => _setPresetAngle(0.0, -0.15), effectiveColor),
              _buildPresetChip(
                  "30° TILT", () => _setPresetAngle(0.52, -0.15), effectiveColor),
              _buildPresetChip(
                  "60° 3D", () => _setPresetAngle(1.05, -0.15), effectiveColor),
              _buildPresetChip("90° PROFILE",
                  () => _setPresetAngle(1.57, -0.15), effectiveColor),
              _buildPresetChip("180° BACK",
                  () => _setPresetAngle(math.pi, -0.15), effectiveColor),
              _buildPresetChip(
                _autoTurntable ? "AUTO: 360°" : "AUTO-SPIN",
                () => setState(() => _autoTurntable = !_autoTurntable),
                effectiveColor,
                isActive: _autoTurntable,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Hint
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.threed_rotation_rounded,
                  size: 16, color: effectiveColor),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Drag in any direction to rotate in 3D',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Dismiss
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: effectiveColor,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'CLOSE VAULT',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetChip(
    String label,
    VoidCallback onTap,
    Color color, {
    bool isActive = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isActive
              ? color.withValues(alpha: 0.25)
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? color : Colors.white.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? color : Colors.white.withValues(alpha: 0.8),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }
}

const BorderRadius _verticalTopRadius =
    BorderRadius.vertical(top: Radius.circular(28));
BorderRadius verticalTopRadius(double r) =>
    BorderRadius.vertical(top: Radius.circular(r));