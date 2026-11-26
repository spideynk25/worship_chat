import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/utils/ai_text_remover_service.dart';
import 'package:worship_chat/common/utils/utils.dart';

enum _TextMarginPreset {
  tight('Tight', 0.12),
  normal('Normal', 0.22),
  wide('Wide', 0.34);

  final String label;
  final double fraction;
  const _TextMarginPreset(this.label, this.fraction);
}

class AiMagicStudioScreen extends StatefulWidget {
  final File initialImage;
  final List<DetectedTextBlock>? initialDetectedTextBlocks;
  final bool autoDetectOnOpen;
  final Future<List<DetectedTextBlock>> Function(File image)? detectTextOverride;
  final String? outputDirectoryPath;

  const AiMagicStudioScreen({
    super.key,
    required this.initialImage,
    this.initialDetectedTextBlocks,
    this.autoDetectOnOpen = true,
    this.detectTextOverride,
    this.outputDirectoryPath,
  });

  @override
  State<AiMagicStudioScreen> createState() => _AiMagicStudioScreenState();
}

class _AiMagicStudioScreenState extends State<AiMagicStudioScreen> {
  static const Color _accentCyan = Color(0xFF00E5FF);
  static const Color _brushAccent = Color(0xFFFF6B6B);

  late File _originalImage;
  late File _currentImage;

  final List<File> _history = [];
  int _historyIndex = -1;

  // Manual brush state for missed logos/watermarks
  double _brushRadius = 18.0;
  bool _isPanMode = false;
  final List<_DrawnStroke> _strokes = [];
  _DrawnStroke? _activeStroke;

  // Detected text state
  List<DetectedTextBlock> _detectedTextBlocks = [];
  final Set<int> _selectedTextIndices = {};
  bool _isDetectingText = false;
  _TextMarginPreset _marginPreset = _TextMarginPreset.normal;

  // Processing & preview state
  bool _isProcessing = false;
  String _processingMessage = '';
  bool _isShowingOriginal = false;

  ui.Image? _decodedUiImage;
  final TransformationController _transformationController =
      TransformationController();

  @override
  void initState() {
    super.initState();
    _originalImage = widget.initialImage;
    _currentImage = widget.initialImage;
    _pushHistory(_currentImage);

    if (widget.initialDetectedTextBlocks != null) {
      _detectedTextBlocks = List<DetectedTextBlock>.from(
        widget.initialDetectedTextBlocks!,
      );
      for (int i = 0; i < _detectedTextBlocks.length; i++) {
        _selectedTextIndices.add(i);
      }
    }

    _decodeUiImage(_currentImage).then((_) {
      if (!mounted) return;
      if (widget.initialDetectedTextBlocks == null && widget.autoDetectOnOpen) {
        _detectTextInImage(silentEmpty: true);
      }
    });
  }

  @override
  void dispose() {
    _transformationController.dispose();
    _decodedUiImage?.dispose();
    AiTextRemoverService.instance.dispose();
    super.dispose();
  }

  Future<void> _decodeUiImage(File file) async {
    final bytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    if (!mounted) {
      frame.image.dispose();
      return;
    }
    final previous = _decodedUiImage;
    setState(() {
      _decodedUiImage = frame.image;
    });
    previous?.dispose();
  }

  void _pushHistory(File file) {
    if (_historyIndex < _history.length - 1) {
      _history.removeRange(_historyIndex + 1, _history.length);
    }
    _history.add(file);
    _historyIndex = _history.length - 1;
  }

  void _undo() {
    if (_historyIndex <= 0) return;
    HapticFeedback.lightImpact();
    setState(() {
      _historyIndex--;
      _currentImage = _history[_historyIndex];
      _strokes.clear();
      _detectedTextBlocks.clear();
      _selectedTextIndices.clear();
    });
    _decodeUiImage(_currentImage);
  }

  void _redo() {
    if (_historyIndex >= _history.length - 1) return;
    HapticFeedback.lightImpact();
    setState(() {
      _historyIndex++;
      _currentImage = _history[_historyIndex];
      _strokes.clear();
      _detectedTextBlocks.clear();
      _selectedTextIndices.clear();
    });
    _decodeUiImage(_currentImage);
  }

  Future<String> _getNewOutputPath() async {
    String? dirPath = widget.outputDirectoryPath;
    if (dirPath == null || dirPath.isEmpty) {
      try {
        final dir = await getTemporaryDirectory().timeout(
          const Duration(seconds: 2),
        );
        dirPath = dir.path;
      } catch (_) {
        dirPath = _originalImage.parent.path;
      }
    }
    final ext = _originalImage.path.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '$dirPath/text_removed_$timestamp.$ext';
  }

  // ── Text Detection & Removal ────────────────────────────────────────────────

  Future<void> _detectTextInImage({bool silentEmpty = false}) async {
    if (_isDetectingText || _isProcessing) return;
    HapticFeedback.selectionClick();
    setState(() {
      _isDetectingText = true;
      _detectedTextBlocks.clear();
      _selectedTextIndices.clear();
    });

    try {
      final blocks = widget.detectTextOverride != null
          ? await widget.detectTextOverride!(_currentImage)
          : await AiTextRemoverService.instance.detectText(_currentImage);
      if (!mounted) return;
      setState(() {
        _detectedTextBlocks = blocks;
        for (int i = 0; i < blocks.length; i++) {
          _selectedTextIndices.add(i);
        }
        _isDetectingText = false;
      });

      if (blocks.isEmpty) {
        if (!silentEmpty) {
          AppSnackBar.info(
            context,
            'No text detected. Brush manually over any watermark or caption.',
          );
        }
      } else {
        AppSnackBar.success(context, 'Found ${blocks.length} text region${blocks.length == 1 ? '' : 's'}');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isDetectingText = false);
      if (!silentEmpty) {
        AppSnackBar.error(context, 'Text detection error: $e');
      }
    }
  }

  Future<void> _applyTextRemoval() async {
    if (_strokes.isEmpty && _selectedTextIndices.isEmpty) {
      AppSnackBar.info(
        context,
        'Select detected text boxes or brush over text first',
      );
      return;
    }

    if (_strokes.isNotEmpty && _decodedUiImage == null) return;

    HapticFeedback.mediumImpact();
    setState(() {
      _isProcessing = true;
      _processingMessage = 'Removing text cleanly...';
    });

    try {
      final outputPath = await _getNewOutputPath();

      final selectedBlocks = _selectedTextIndices
          .where((idx) => idx >= 0 && idx < _detectedTextBlocks.length)
          .map((idx) => _detectedTextBlocks[idx])
          .toList();

      Uint8List? brushMask;
      int brushW = 0;
      int brushH = 0;
      if (_strokes.isNotEmpty && _decodedUiImage != null) {
        brushW = _decodedUiImage!.width;
        brushH = _decodedUiImage!.height;
        brushMask = await _rasterizeStrokesToMask(brushW, brushH);
      }

      final result = await AiTextRemoverService.instance.eraseDetectedText(
        sourceImage: _currentImage,
        textBlocks: selectedBlocks,
        additionalMaskBytes: brushMask,
        additionalMaskWidth: brushW,
        additionalMaskHeight: brushH,
        outputPath: outputPath,
        marginFraction: _marginPreset.fraction,
        scrubTextHalos: true,
      );

      if (!mounted) return;
      setState(() {
        _currentImage = result;
        _detectedTextBlocks.clear();
        _selectedTextIndices.clear();
        _strokes.clear();
        _pushHistory(result);
        _isProcessing = false;
      });

      await _decodeUiImage(result);
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      AppSnackBar.success(context, 'Text removed cleanly');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      AppSnackBar.error(context, 'Text removal error: $e');
    }
  }

  /// Rasterizes drawn brush strokes into a 1-channel bitmap at native image dimensions.
  Future<Uint8List> _rasterizeStrokesToMask(int width, int height) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    );

    canvas.drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = Colors.black,
    );

    final maskPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final stroke in _strokes) {
      maskPaint.strokeWidth = stroke.radius * 2;
      final path = Path();
      if (stroke.points.isNotEmpty) {
        path.moveTo(stroke.points.first.dx, stroke.points.first.dy);
        for (int i = 1; i < stroke.points.length; i++) {
          path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
        }
        if (stroke.points.length == 1) {
          canvas.drawCircle(
            stroke.points.first,
            stroke.radius,
            Paint()..color = Colors.white,
          );
          continue;
        }
      }
      canvas.drawPath(path, maskPaint);
    }

    final picture = recorder.endRecording();
    final maskImage = await picture.toImage(width, height);
    final byteData = await maskImage.toByteData(format: ui.ImageByteFormat.rawRgba);
    maskImage.dispose();

    if (byteData == null) return Uint8List(width * height);

    final rawBytes = byteData.buffer.asUint8List();
    final mask1Channel = Uint8List(width * height);
    for (int i = 0; i < width * height; i++) {
      mask1Channel[i] = rawBytes[i * 4];
    }
    return mask1Channel;
  }

  void _finishAndSave() {
    HapticFeedback.mediumImpact();
    Navigator.pop(context, _currentImage);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0E17),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: _buildCanvasArea()),

          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: _buildTopGlassBar(),
              ),
            ),
          ),

          Positioned(
            right: 14,
            top: 120,
            child: _buildModeToggleFab(),
          ),

          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildBottomPanel(),
          ),

          if (_isProcessing) _buildProcessingOverlay(),
        ],
      ),
    );
  }

  Widget _buildProcessingOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.65),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1C2E),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 20,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 38,
                  height: 38,
                  child: CircularProgressIndicator(
                    color: _accentCyan,
                    strokeWidth: 3,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  _processingMessage,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'On-device full resolution restore',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Canvas with Tap-to-Toggle Text Boxes & Manual Brush ────────────────────

  Widget _buildCanvasArea() {
    if (_decodedUiImage == null) {
      return const Center(
        child: CircularProgressIndicator(color: tabColor),
      );
    }

    final displayedFile = _isShowingOriginal ? _originalImage : _currentImage;

    return LayoutBuilder(
      builder: (context, constraints) {
        final imgW = _decodedUiImage!.width.toDouble();
        final imgH = _decodedUiImage!.height.toDouble();

        final scale = math.min(
          constraints.maxWidth / imgW,
          constraints.maxHeight / imgH,
        );
        final renderW = imgW * scale;
        final renderH = imgH * scale;

        return InteractiveViewer(
          transformationController: _transformationController,
          panEnabled: _isPanMode,
          scaleEnabled: true,
          minScale: 0.8,
          maxScale: 5.0,
          child: Center(
            child: SizedBox(
              width: renderW,
              height: renderH,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) => _onCanvasTap(details.localPosition, scale),
                onPanStart: _isPanMode
                    ? null
                    : (details) => _onDrawStart(details.localPosition, scale),
                onPanUpdate: _isPanMode
                    ? null
                    : (details) => _onDrawUpdate(details.localPosition, scale),
                onPanEnd: _isPanMode ? null : (_) => _onDrawEnd(),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(
                      displayedFile,
                      fit: BoxFit.contain,
                    ),
                    if (!_isShowingOriginal)
                      CustomPaint(
                        painter: _TextRemoverOverlayPainter(
                          strokes: _strokes,
                          activeStroke: _activeStroke,
                          scale: scale,
                          detectedBlocks: _detectedTextBlocks,
                          selectedTextIndices: _selectedTextIndices,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _onCanvasTap(Offset localPos, double scale) {
    if (_isShowingOriginal || _detectedTextBlocks.isEmpty) return;

    final imgPos = Offset(localPos.dx / scale, localPos.dy / scale);
    final hitPad = 10.0 / scale;

    for (int i = _detectedTextBlocks.length - 1; i >= 0; i--) {
      final expanded = _detectedTextBlocks[i].boundingBox.inflate(hitPad);
      if (expanded.contains(imgPos)) {
        HapticFeedback.selectionClick();
        setState(() {
          if (_selectedTextIndices.contains(i)) {
            _selectedTextIndices.remove(i);
          } else {
            _selectedTextIndices.add(i);
          }
        });
        return;
      }
    }
  }

  void _onDrawStart(Offset localPos, double scale) {
    final imgPos = Offset(localPos.dx / scale, localPos.dy / scale);
    setState(() {
      _activeStroke = _DrawnStroke(
        points: [imgPos],
        radius: _brushRadius / scale,
      );
    });
  }

  void _onDrawUpdate(Offset localPos, double scale) {
    if (_activeStroke == null) return;
    final imgPos = Offset(localPos.dx / scale, localPos.dy / scale);
    setState(() {
      _activeStroke!.points.add(imgPos);
    });
  }

  void _onDrawEnd() {
    if (_activeStroke != null && _activeStroke!.points.isNotEmpty) {
      setState(() {
        _strokes.add(_activeStroke!);
        _activeStroke = null;
      });
    }
  }

  // ── Top Glass Bar ───────────────────────────────────────────────────────────

  Widget _buildTopGlassBar() {
    final canUndo = _historyIndex > 0;
    final canRedo = _historyIndex < _history.length - 1;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF161524).withValues(alpha: 0.90),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 16,
              ),
            ],
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                tooltip: 'Cancel',
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                padding: EdgeInsets.zero,
                onPressed: () => Navigator.pop(context),
              ),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: _accentCyan.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _accentCyan.withValues(alpha: 0.4),
                      width: 0.8,
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.text_fields_rounded, color: _accentCyan, size: 15),
                      SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          'Text Remover',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: Icon(
                  Icons.undo_rounded,
                  color: canUndo ? Colors.white : Colors.white30,
                  size: 19,
                ),
                tooltip: 'Undo',
                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                padding: EdgeInsets.zero,
                onPressed: canUndo ? _undo : null,
              ),
              IconButton(
                icon: Icon(
                  Icons.redo_rounded,
                  color: canRedo ? Colors.white : Colors.white30,
                  size: 19,
                ),
                tooltip: 'Redo',
                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                padding: EdgeInsets.zero,
                onPressed: canRedo ? _redo : null,
              ),
              GestureDetector(
                onTapDown: (_) => setState(() => _isShowingOriginal = true),
                onTapUp: (_) => setState(() => _isShowingOriginal = false),
                onTapCancel: () => setState(() => _isShowingOriginal = false),
                child: Tooltip(
                  message: 'Hold to compare original',
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: _isShowingOriginal
                          ? const Color(0xFF00E676).withValues(alpha: 0.25)
                          : Colors.white.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isShowingOriginal
                          ? Icons.visibility_rounded
                          : Icons.visibility_outlined,
                      color: _isShowingOriginal
                          ? const Color(0xFF00E676)
                          : Colors.white70,
                      size: 17,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 2),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: tabColor,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                onPressed: _finishAndSave,
                child: const Text(
                  'Done',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Floating Pan / Zoom vs Draw Mode Toggle ────────────────────────────────

  Widget _buildModeToggleFab() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildGlassIconFab(
          icon: _isPanMode ? Icons.pan_tool_rounded : Icons.brush_rounded,
          isActive: _isPanMode,
          tooltip: _isPanMode ? 'Switch to brush' : 'Switch to pan/zoom',
          onTap: () {
            HapticFeedback.lightImpact();
            setState(() => _isPanMode = !_isPanMode);
          },
        ),
        const SizedBox(height: 8),
        _buildGlassIconFab(
          icon: Icons.fit_screen_rounded,
          isActive: false,
          tooltip: 'Reset zoom',
          onTap: () {
            HapticFeedback.lightImpact();
            _transformationController.value = Matrix4.identity();
          },
        ),
      ],
    );
  }

  Widget _buildGlassIconFab({
    required IconData icon,
    required bool isActive,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: isActive
                  ? _accentCyan.withValues(alpha: 0.22)
                  : const Color(0xFF161524).withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isActive
                    ? _accentCyan
                    : Colors.white.withValues(alpha: 0.14),
                width: isActive ? 1.4 : 0.8,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: onTap,
                child: Center(
                  child: Icon(
                    icon,
                    color: isActive ? _accentCyan : Colors.white,
                    size: 19,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Bottom Text Remover Control Panel ───────────────────────────────────────

  Widget _buildBottomPanel() {
    final selectedCount = _selectedTextIndices.length;
    final totalDetected = _detectedTextBlocks.length;
    final hasAnyTarget = _strokes.isNotEmpty || _selectedTextIndices.isNotEmpty;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF161524).withValues(alpha: 0.94),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 24,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Status & quick selection actions
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          totalDetected > 0
                              ? '$selectedCount/$totalDetected text boxes${_strokes.isNotEmpty ? ' • ${_strokes.length} brush' : ''} (tap box to toggle)'
                              : (_strokes.isNotEmpty
                                  ? '${_strokes.length} manual brush mask${_strokes.length == 1 ? '' : 's'} ready'
                                  : 'Tap text boxes or brush missed text'),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (totalDetected > 0) ...[
                        const SizedBox(width: 6),
                        _buildQuickChip(
                          label: selectedCount == totalDetected ? 'None' : 'All',
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() {
                              if (selectedCount == totalDetected) {
                                _selectedTextIndices.clear();
                              } else {
                                for (int i = 0; i < totalDetected; i++) {
                                  _selectedTextIndices.add(i);
                                }
                              }
                            });
                          },
                        ),
                      ],
                      if (_strokes.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        _buildQuickChip(
                          label: 'Clear Brush',
                          onTap: () => setState(() => _strokes.clear()),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Coverage Margin Selector (Tight / Normal / Wide)
                  Row(
                    children: [
                      const Text(
                        'Padding:',
                        style: TextStyle(color: Colors.white54, fontSize: 11.5),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Row(
                          children: _TextMarginPreset.values.map((preset) {
                            final active = _marginPreset == preset;
                            return Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 3),
                                child: GestureDetector(
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    setState(() => _marginPreset = preset);
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 5),
                                    decoration: BoxDecoration(
                                      color: active
                                          ? _accentCyan.withValues(alpha: 0.16)
                                          : Colors.white.withValues(alpha: 0.05),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: active
                                            ? _accentCyan
                                            : Colors.white.withValues(alpha: 0.08),
                                      ),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      preset.label,
                                      style: TextStyle(
                                        color: active ? _accentCyan : Colors.white60,
                                        fontSize: 11,
                                        fontWeight: active
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // Manual Brush Size Slider
                  Row(
                    children: [
                      const Icon(Icons.brush_rounded, color: Colors.white70, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'Brush: ${_brushRadius.round()}px',
                        style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        width: (_brushRadius * 0.45).clamp(6.0, 20.0),
                        height: (_brushRadius * 0.45).clamp(6.0, 20.0),
                        decoration: const BoxDecoration(
                          color: _brushAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: _brushAccent,
                            thumbColor: _brushAccent,
                            trackHeight: 2.5,
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 14,
                            ),
                          ),
                          child: Slider(
                            value: _brushRadius,
                            min: 8.0,
                            max: 48.0,
                            onChanged: (val) => setState(() => _brushRadius = val),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // Scan & Erase Action Row
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: _isDetectingText
                              ? const SizedBox(
                                  width: 15,
                                  height: 15,
                                  child: CircularProgressIndicator(
                                    color: _accentCyan,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.search_rounded,
                                  size: 17,
                                  color: _accentCyan,
                                ),
                          label: Text(
                            totalDetected == 0
                                ? 'Auto-Detect Text'
                                : 'Re-scan ($totalDetected)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _accentCyan,
                              fontWeight: FontWeight.w600,
                              fontSize: 12.5,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: _accentCyan),
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: _isDetectingText ? null : () => _detectTextInImage(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(
                            Icons.cleaning_services_rounded,
                            size: 17,
                            color: Color(0xFF0A0912),
                          ),
                          label: const Text(
                            'Erase Text',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Color(0xFF0A0912),
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _accentCyan,
                            disabledBackgroundColor: Colors.grey[800],
                            disabledForegroundColor: Colors.white38,
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          onPressed: hasAnyTarget && !_isProcessing
                              ? _applyTextRemoval
                              : null,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickChip({
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _DrawnStroke {
  final List<Offset> points;
  final double radius;

  _DrawnStroke({required this.points, required this.radius});
}

class _TextRemoverOverlayPainter extends CustomPainter {
  final List<_DrawnStroke> strokes;
  final _DrawnStroke? activeStroke;
  final double scale;
  final List<DetectedTextBlock> detectedBlocks;
  final Set<int> selectedTextIndices;

  _TextRemoverOverlayPainter({
    required this.strokes,
    required this.activeStroke,
    required this.scale,
    required this.detectedBlocks,
    required this.selectedTextIndices,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final selectedFillPaint = Paint()
      ..color = const Color(0xFF00E5FF).withValues(alpha: 0.28)
      ..style = PaintingStyle.fill;

    final selectedBorderPaint = Paint()
      ..color = const Color(0xFF00E5FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    final unselectedBorderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;

    for (int i = 0; i < detectedBlocks.length; i++) {
      final block = detectedBlocks[i];
      final isSelected = selectedTextIndices.contains(i);

      if (block.words.isNotEmpty) {
        for (final word in block.words) {
          if (word.cornerPoints.length == 4) {
            final path = Path()
              ..moveTo(
                word.cornerPoints[0].dx * scale,
                word.cornerPoints[0].dy * scale,
              )
              ..lineTo(
                word.cornerPoints[1].dx * scale,
                word.cornerPoints[1].dy * scale,
              )
              ..lineTo(
                word.cornerPoints[2].dx * scale,
                word.cornerPoints[2].dy * scale,
              )
              ..lineTo(
                word.cornerPoints[3].dx * scale,
                word.cornerPoints[3].dy * scale,
              )
              ..close();
            _drawBoxOrPath(
              canvas,
              isSelected: isSelected,
              fillPaint: selectedFillPaint,
              selectedBorderPaint: selectedBorderPaint,
              unselectedBorderPaint: unselectedBorderPaint,
              path: path,
            );
          } else {
            _drawBoxOrPath(
              canvas,
              isSelected: isSelected,
              fillPaint: selectedFillPaint,
              selectedBorderPaint: selectedBorderPaint,
              unselectedBorderPaint: unselectedBorderPaint,
              rect: _scaledRect(word.boundingBox, scale),
            );
          }
        }
      } else {
        _drawBoxOrPath(
          canvas,
          isSelected: isSelected,
          fillPaint: selectedFillPaint,
          selectedBorderPaint: selectedBorderPaint,
          unselectedBorderPaint: unselectedBorderPaint,
          rect: _scaledRect(block.boundingBox, scale),
        );
      }
    }

    final strokePaint = Paint()
      ..color = const Color(0xFFFF6B6B).withValues(alpha: 0.48)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final allStrokes = [...strokes, if (activeStroke != null) activeStroke!];
    for (final s in allStrokes) {
      if (s.points.isEmpty) continue;
      strokePaint.strokeWidth = s.radius * 2 * scale;
      if (s.points.length == 1) {
        canvas.drawCircle(
          Offset(s.points.first.dx * scale, s.points.first.dy * scale),
          s.radius * scale,
          Paint()..color = const Color(0xFFFF6B6B).withValues(alpha: 0.48),
        );
        continue;
      }

      final path = Path()
        ..moveTo(s.points.first.dx * scale, s.points.first.dy * scale);
      for (int i = 1; i < s.points.length; i++) {
        path.lineTo(s.points[i].dx * scale, s.points[i].dy * scale);
      }
      canvas.drawPath(path, strokePaint);
    }
  }

  void _drawBoxOrPath(
    Canvas canvas, {
    required bool isSelected,
    required Paint fillPaint,
    required Paint selectedBorderPaint,
    required Paint unselectedBorderPaint,
    Path? path,
    Rect? rect,
  }) {
    if (path != null) {
      if (isSelected) {
        canvas.drawPath(path, fillPaint);
        canvas.drawPath(path, selectedBorderPaint);
      } else {
        canvas.drawPath(path, unselectedBorderPaint);
      }
      return;
    }
    if (rect != null) {
      if (isSelected) {
        canvas.drawRect(rect, fillPaint);
        canvas.drawRect(rect, selectedBorderPaint);
      } else {
        canvas.drawRect(rect, unselectedBorderPaint);
      }
    }
  }

  Rect _scaledRect(Rect box, double s) {
    return Rect.fromLTRB(
      box.left * s,
      box.top * s,
      box.right * s,
      box.bottom * s,
    );
  }

  @override
  bool shouldRepaint(covariant _TextRemoverOverlayPainter oldDelegate) => true;
}
