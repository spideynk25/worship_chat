import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/utils/ai_inpainting_service.dart';
import 'package:worship_chat/common/utils/ai_segmentation_service.dart';
import 'package:worship_chat/common/utils/ai_text_remover_service.dart';
import 'package:worship_chat/common/utils/utils.dart';

enum StudioTool {
  objectRemover,
  textRemover,
  bgRemover,
}

class AiMagicStudioScreen extends StatefulWidget {
  final File initialImage;

  const AiMagicStudioScreen({
    super.key,
    required this.initialImage,
  });

  @override
  State<AiMagicStudioScreen> createState() => _AiMagicStudioScreenState();
}

class _AiMagicStudioScreenState extends State<AiMagicStudioScreen> {
  late File _originalImage;
  late File _currentImage;

  // History stack for Undo / Redo
  final List<File> _history = [];
  int _historyIndex = -1;

  StudioTool _activeTool = StudioTool.objectRemover;

  // Brush state
  double _brushRadius = 24.0;
  bool _isPanMode = false;
  final List<_DrawnStroke> _strokes = [];
  _DrawnStroke? _activeStroke;

  // Text remover state
  List<DetectedTextBlock> _detectedTextBlocks = [];
  final Set<int> _selectedTextIndices = {};
  bool _isDetectingText = false;

  // Background remover state
  BackgroundMode _selectedBgMode = BackgroundMode.transparent;
  final int _blurIntensity = 16;

  // Processing state
  bool _isProcessing = false;
  String _processingMessage = '';
  bool _isShowingOriginal = false;

  // Image size caching
  ui.Image? _decodedUiImage;

  final TransformationController _transformationController = TransformationController();

  @override
  void initState() {
    super.initState();
    _originalImage = widget.initialImage;
    _currentImage = widget.initialImage;
    _pushHistory(_currentImage);
    _decodeUiImage(_currentImage);
  }

  @override
  void dispose() {
    _transformationController.dispose();
    _decodedUiImage?.dispose();
    AiSegmentationService.instance.dispose();
    AiTextRemoverService.instance.dispose();
    super.dispose();
  }

  Future<void> _decodeUiImage(File file) async {
    final bytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    if (mounted) {
      setState(() {
        _decodedUiImage = frame.image;
      });
    }
  }

  void _pushHistory(File file) {
    // If we branched from an earlier state, truncate subsequent history
    if (_historyIndex < _history.length - 1) {
      _history.removeRange(_historyIndex + 1, _history.length);
    }
    _history.add(file);
    _historyIndex = _history.length - 1;
  }

  void _undo() {
    if (_historyIndex > 0) {
      HapticFeedback.lightImpact();
      setState(() {
        _historyIndex--;
        _currentImage = _history[_historyIndex];
        _strokes.clear();
        _selectedTextIndices.clear();
      });
      _decodeUiImage(_currentImage);
    }
  }

  void _redo() {
    if (_historyIndex < _history.length - 1) {
      HapticFeedback.lightImpact();
      setState(() {
        _historyIndex++;
        _currentImage = _history[_historyIndex];
        _strokes.clear();
        _selectedTextIndices.clear();
      });
      _decodeUiImage(_currentImage);
    }
  }

  Future<String> _getNewOutputPath({String ext = 'jpg'}) async {
    final dir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '${dir.path}/magic_edit_$timestamp.$ext';
  }

  // ── Object Inpainting ────────────────────────────────────────────────────────
  Future<void> _applyObjectRemoval() async {
    if (_strokes.isEmpty) {
      AppSnackBar.info(context, 'Brush over an object or person first');
      return;
    }

    if (_decodedUiImage == null) return;

    HapticFeedback.mediumImpact();
    setState(() {
      _isProcessing = true;
      _processingMessage = 'Erasing object on-device...';
    });

    try {
      final imgW = _decodedUiImage!.width;
      final imgH = _decodedUiImage!.height;

      // Rasterize strokes to a binary mask buffer (imgW x imgH)
      final maskBytes = await _rasterizeStrokesToMask(imgW, imgH);
      final outputPath = await _getNewOutputPath();

      final resultFile = await AiInpaintingService.instance.inpaintImage(
        sourceImage: _currentImage,
        maskBytes: maskBytes,
        maskWidth: imgW,
        maskHeight: imgH,
        outputPath: outputPath,
        patchRadius: math.max(4, (_brushRadius * 0.25).round()),
      );

      setState(() {
        _currentImage = resultFile;
        _strokes.clear();
        _pushHistory(resultFile);
        _isProcessing = false;
      });

      await _decodeUiImage(resultFile);
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      AppSnackBar.success(context, 'Object removed successfully');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      AppSnackBar.error(context, 'Object removal error: $e');
    }
  }

  // ── Text Detection & Removal ────────────────────────────────────────────────
  Future<void> _detectTextInImage() async {
    HapticFeedback.selectionClick();
    setState(() {
      _isDetectingText = true;
      _detectedTextBlocks.clear();
      _selectedTextIndices.clear();
    });

    try {
      final blocks = await AiTextRemoverService.instance.detectText(_currentImage);
      if (!mounted) return;
      setState(() {
        _detectedTextBlocks = blocks;
        // Pre-select all detected text for 1-tap removal
        for (int i = 0; i < blocks.length; i++) {
          _selectedTextIndices.add(i);
        }
        _isDetectingText = false;
      });

      if (blocks.isEmpty) {
        AppSnackBar.info(context, 'No text detected. You can also brush over text manually.');
      } else {
        AppSnackBar.success(context, 'Found ${blocks.length} text elements');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isDetectingText = false);
      AppSnackBar.error(context, 'Text detection error: $e');
    }
  }

  Future<void> _applyTextRemoval() async {
    if (_strokes.isEmpty && _selectedTextIndices.isEmpty) {
      AppSnackBar.info(context, 'Select detected text or brush over text first');
      return;
    }

    if (_decodedUiImage == null) return;

    HapticFeedback.mediumImpact();
    setState(() {
      _isProcessing = true;
      _processingMessage = 'Removing text on-device...';
    });

    try {
      final imgW = _decodedUiImage!.width;
      final imgH = _decodedUiImage!.height;
      final outputPath = await _getNewOutputPath();

      // If user selected detected text blocks
      if (_selectedTextIndices.isNotEmpty) {
        final rectsToErase = _selectedTextIndices
            .map((idx) => _detectedTextBlocks[idx].boundingBox)
            .toList();

        final result = await AiTextRemoverService.instance.eraseDetectedText(
          sourceImage: _currentImage,
          textRects: rectsToErase,
          outputPath: outputPath,
        );

        setState(() {
          _currentImage = result;
          _detectedTextBlocks.clear();
          _selectedTextIndices.clear();
          _strokes.clear();
          _pushHistory(result);
          _isProcessing = false;
        });

        await _decodeUiImage(result);
      } else {
        // If user manually brushed over text
        final maskBytes = await _rasterizeStrokesToMask(imgW, imgH);
        final result = await AiInpaintingService.instance.inpaintImage(
          sourceImage: _currentImage,
          maskBytes: maskBytes,
          maskWidth: imgW,
          maskHeight: imgH,
          outputPath: outputPath,
          patchRadius: 5,
        );

        setState(() {
          _currentImage = result;
          _strokes.clear();
          _pushHistory(result);
          _isProcessing = false;
        });

        await _decodeUiImage(result);
      }

      HapticFeedback.mediumImpact();
      if (!mounted) return;
      AppSnackBar.success(context, 'Text removed successfully');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      AppSnackBar.error(context, 'Text removal error: $e');
    }
  }

  // ── Background Removal / Cutout ─────────────────────────────────────────────
  Future<void> _applyBackgroundRemoval() async {
    HapticFeedback.mediumImpact();
    setState(() {
      _isProcessing = true;
      _processingMessage = 'Segmenting subject on-device...';
    });

    try {
      final isPng = _selectedBgMode == BackgroundMode.transparent;
      final outputPath = await _getNewOutputPath(ext: isPng ? 'png' : 'jpg');

      final result = await AiSegmentationService.instance.processBackground(
        sourceImage: _currentImage,
        outputPath: outputPath,
        mode: _selectedBgMode,
        blurRadius: _blurIntensity,
        bgColorR: _selectedBgMode == BackgroundMode.studioWhite ? 255 : 18,
        bgColorG: _selectedBgMode == BackgroundMode.studioWhite ? 255 : 17,
        bgColorB: _selectedBgMode == BackgroundMode.studioWhite ? 255 : 26,
      );

      setState(() {
        _currentImage = result;
        _pushHistory(result);
        _isProcessing = false;
      });

      await _decodeUiImage(result);
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      AppSnackBar.success(context, 'Background transformed successfully');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      AppSnackBar.error(context, 'Background removal: $e');
    }
  }

  /// Converts drawn finger stroke paths into a 1-channel binary mask bitmap
  Future<Uint8List> _rasterizeStrokesToMask(int width, int height) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));

    // Black background (0 = clean pixel)
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = Colors.black,
    );

    // White brush strokes (255 = inpaint mask)
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
      }
      canvas.drawPath(path, maskPaint);
    }

    final picture = recorder.endRecording();
    final maskImage = await picture.toImage(width, height);
    final byteData = await maskImage.toByteData(format: ui.ImageByteFormat.rawRgba);

    if (byteData == null) return Uint8List(width * height);

    final rawBytes = byteData.buffer.asUint8List();
    final mask1Channel = Uint8List(width * height);

    for (int i = 0; i < width * height; i++) {
      // Sample R channel (since mask was drawn in white)
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
        children: [
          // ── Main Image Canvas ─────────────────────────────────────────────
          Positioned.fill(
            child: _buildCanvasArea(),
          ),

          // ── Top Glass Navigation & Undo/Redo Bar ──────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: _buildTopGlassBar(),
            ),
          ),

          // ── Floating Zoom / Brush Mode Toggle (Right Side) ────────────────
          Positioned(
            right: 14,
            top: 130,
            child: _buildModeToggleFab(),
          ),

          // ── Bottom Studio Control Panel ───────────────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildBottomPanel(),
          ),

          // ── Processing Overlay with Shimmer ───────────────────────────────
          if (_isProcessing)
            Positioned.fill(
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
                            color: Color(0xFF00E676),
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
                          '100% On-Device • Zero API Cost',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Canvas Area with Touch Drawing & Pan/Zoom ─────────────────────────────
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

        // Calculate fitted display size inside viewport
        final scale = math.min(constraints.maxWidth / imgW, constraints.maxHeight / imgH);
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
                onPanStart: _isPanMode ? null : (details) => _onDrawStart(details.localPosition, scale),
                onPanUpdate: _isPanMode ? null : (details) => _onDrawUpdate(details.localPosition, scale),
                onPanEnd: _isPanMode ? null : (details) => _onDrawEnd(),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Rendered Image
                    Image.file(
                      displayedFile,
                      fit: BoxFit.contain,
                    ),

                    // Custom Painter for Brush Mask & Detected Text Overlays
                    if (!_isShowingOriginal)
                      CustomPaint(
                        painter: _StudioMaskPainter(
                          strokes: _strokes,
                          activeStroke: _activeStroke,
                          scale: scale,
                          detectedBlocks: _detectedTextBlocks,
                          selectedTextIndices: _selectedTextIndices,
                          showTextBoxes: _activeTool == StudioTool.textRemover,
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

  void _onDrawStart(Offset localPos, double scale) {
    if (_activeTool == StudioTool.bgRemover) return;

    // Convert screen coordinates to original image coordinates
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

  // ── Top Glass Navigation Bar ──────────────────────────────────────────────
  Widget _buildTopGlassBar() {
    final canUndo = _historyIndex > 0;
    final canRedo = _historyIndex < _history.length - 1;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
              // Back / Close
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 22),
                tooltip: 'Cancel',
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 4),

              // Title pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: tabColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: tabColor.withValues(alpha: 0.4), width: 0.8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_fix_high_rounded, color: tabColor, size: 16),
                    SizedBox(width: 6),
                    Text(
                      'AI Magic Studio',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // Undo
              IconButton(
                icon: Icon(
                  Icons.undo_rounded,
                  color: canUndo ? Colors.white : Colors.white30,
                  size: 20,
                ),
                tooltip: 'Undo',
                onPressed: canUndo ? _undo : null,
              ),

              // Redo
              IconButton(
                icon: Icon(
                  Icons.redo_rounded,
                  color: canRedo ? Colors.white : Colors.white30,
                  size: 20,
                ),
                tooltip: 'Redo',
                onPressed: canRedo ? _redo : null,
              ),

              // Hold to Compare Eye Button
              GestureDetector(
                onTapDown: (_) => setState(() => _isShowingOriginal = true),
                onTapUp: (_) => setState(() => _isShowingOriginal = false),
                onTapCancel: () => setState(() => _isShowingOriginal = false),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: _isShowingOriginal
                        ? const Color(0xFF00E676).withValues(alpha: 0.25)
                        : Colors.white.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isShowingOriginal ? Icons.visibility_rounded : Icons.visibility_outlined,
                    color: _isShowingOriginal ? const Color(0xFF00E676) : Colors.white70,
                    size: 18,
                  ),
                ),
              ),

              const SizedBox(width: 4),

              // Save & Done Button
              ElevatedButton.icon(
                icon: const Icon(Icons.check_rounded, size: 18, color: Colors.white),
                label: const Text(
                  'Done',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: tabColor,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                onPressed: _finishAndSave,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Floating Toggle (Pan Mode vs Draw Mode) ───────────────────────────────
  Widget _buildModeToggleFab() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _isPanMode ? tabColor.withValues(alpha: 0.25) : const Color(0xFF161524).withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: _isPanMode ? tabColor : Colors.white.withValues(alpha: 0.14),
                  width: _isPanMode ? 1.5 : 0.8,
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(15),
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() => _isPanMode = !_isPanMode);
                  },
                  child: Center(
                    child: Icon(
                      _isPanMode ? Icons.pan_tool_rounded : Icons.brush_rounded,
                      color: _isPanMode ? tabColor : Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Reset Zoom & Position
        ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF161524).withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(15),
                  onTap: () {
                    HapticFeedback.lightImpact();
                    _transformationController.value = Matrix4.identity();
                  },
                  child: const Center(
                    child: Icon(Icons.fit_screen_rounded, color: Colors.white70, size: 20),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Bottom Control Panel ──────────────────────────────────────────────────
  Widget _buildBottomPanel() {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF161524).withValues(alpha: 0.94),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
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
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Active Tool Specific Controls
                  if (_activeTool == StudioTool.objectRemover) _buildObjectRemoverControls(),
                  if (_activeTool == StudioTool.textRemover) _buildTextRemoverControls(),
                  if (_activeTool == StudioTool.bgRemover) _buildBgRemoverControls(),

                  const Divider(color: Colors.white12, height: 24),

                  // 3 Master Tool Switcher Tabs
                  Row(
                    children: [
                      _buildToolTab(
                        tool: StudioTool.objectRemover,
                        title: 'Object Remover',
                        icon: Icons.auto_fix_high_rounded,
                        accentColor: const Color(0xFFFF5252),
                      ),
                      const SizedBox(width: 8),
                      _buildToolTab(
                        tool: StudioTool.textRemover,
                        title: 'Text Remover',
                        icon: Icons.text_fields_rounded,
                        accentColor: const Color(0xFF00E5FF),
                      ),
                      const SizedBox(width: 8),
                      _buildToolTab(
                        tool: StudioTool.bgRemover,
                        title: 'Cutout & BG',
                        icon: Icons.content_cut_rounded,
                        accentColor: const Color(0xFF00E676),
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

  Widget _buildToolTab({
    required StudioTool tool,
    required String title,
    required IconData icon,
    required Color accentColor,
  }) {
    final isSelected = _activeTool == tool;

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            setState(() {
              _activeTool = tool;
              _strokes.clear();
            });
            if (tool == StudioTool.textRemover && _detectedTextBlocks.isEmpty) {
              _detectTextInImage();
            }
          },
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: isSelected ? accentColor.withValues(alpha: 0.16) : const Color(0xFF1E1C2E),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected ? accentColor : Colors.white.withValues(alpha: 0.08),
                width: isSelected ? 1.5 : 0.8,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: isSelected ? accentColor : Colors.white70, size: 20),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white60,
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Object Remover Controls ───────────────────────────────────────────────
  Widget _buildObjectRemoverControls() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Brush size slider + circle preview
        Row(
          children: [
            const Icon(Icons.brush_rounded, color: Colors.white70, size: 18),
            const SizedBox(width: 8),
            Text(
              'Brush Size: ${_brushRadius.round()}px',
              style: const TextStyle(color: Colors.white70, fontSize: 12.5),
            ),
            const SizedBox(width: 8),
            // Live circle dot
            Container(
              width: _brushRadius * 0.6,
              height: _brushRadius * 0.6,
              decoration: const BoxDecoration(
                color: Color(0xFFFF5252),
                shape: BoxShape.circle,
              ),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: const Color(0xFFFF5252),
                  thumbColor: const Color(0xFFFF5252),
                  trackHeight: 3,
                ),
                child: Slider(
                  value: _brushRadius,
                  min: 8.0,
                  max: 60.0,
                  onChanged: (val) => setState(() => _brushRadius = val),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Action Buttons Row (Clear Mask & Erase Object)
        Row(
          children: [
            if (_strokes.isNotEmpty)
              OutlinedButton.icon(
                icon: const Icon(Icons.clear_rounded, size: 18, color: Colors.white70),
                label: const Text('Clear Mask', style: TextStyle(color: Colors.white70, fontSize: 13)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white24),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => setState(() => _strokes.clear()),
              ),
            if (_strokes.isNotEmpty) const SizedBox(width: 10),

            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.auto_fix_high_rounded, size: 18, color: Colors.white),
                label: Text(
                  _strokes.isEmpty ? 'Paint over an object to erase' : 'Erase Object Now',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13.5),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _strokes.isEmpty ? Colors.grey[800] : const Color(0xFFFF5252),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                onPressed: _strokes.isEmpty ? null : _applyObjectRemoval,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Text Remover Controls ─────────────────────────────────────────────────
  Widget _buildTextRemoverControls() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: _isDetectingText
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(color: Color(0xFF00E5FF), strokeWidth: 2),
                      )
                    : const Icon(Icons.search_rounded, size: 18, color: Color(0xFF00E5FF)),
                label: Text(
                  _detectedTextBlocks.isEmpty ? 'Auto-Detect Text' : 'Re-scan Text (${_detectedTextBlocks.length})',
                  style: const TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.w600, fontSize: 12.5),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF00E5FF)),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _isDetectingText ? null : _detectTextInImage,
              ),
            ),
            const SizedBox(width: 10),

            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.cleaning_services_rounded, size: 18, color: Colors.white),
                label: const Text(
                  'Erase Text',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E5FF),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                onPressed: (_strokes.isNotEmpty || _selectedTextIndices.isNotEmpty) ? _applyTextRemoval : null,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Background Remover Controls ───────────────────────────────────────────
  Widget _buildBgRemoverControls() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'SELECT BACKGROUND STYLE',
          style: TextStyle(
            color: Colors.white54,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),

        // Style Selector Carousel
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _buildBgStyleChip(
                mode: BackgroundMode.transparent,
                title: 'Transparent',
                icon: Icons.grid_view_rounded,
                accentColor: const Color(0xFF00E676),
              ),
              const SizedBox(width: 8),
              _buildBgStyleChip(
                mode: BackgroundMode.portraitBlur,
                title: 'Portrait Blur',
                icon: Icons.blur_on_rounded,
                accentColor: const Color(0xFF29B6F6),
              ),
              const SizedBox(width: 8),
              _buildBgStyleChip(
                mode: BackgroundMode.studioDark,
                title: 'Studio Dark',
                icon: Icons.dark_mode_rounded,
                accentColor: const Color(0xFFAB47BC),
              ),
              const SizedBox(width: 8),
              _buildBgStyleChip(
                mode: BackgroundMode.studioWhite,
                title: 'Studio White',
                icon: Icons.light_mode_rounded,
                accentColor: Colors.white,
              ),
              const SizedBox(width: 8),
              _buildBgStyleChip(
                mode: BackgroundMode.studioGradient,
                title: 'Royal Gradient',
                icon: Icons.gradient_rounded,
                accentColor: const Color(0xFFFFB300),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 1-Tap Background Removal Action
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.content_cut_rounded, size: 18, color: Colors.white),
            label: Text(
              _selectedBgMode == BackgroundMode.transparent
                  ? 'Cut Out Subject (Transparent PNG)'
                  : 'Apply Background Transformation',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13.5),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00E676),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            onPressed: _applyBackgroundRemoval,
          ),
        ),
      ],
    );
  }

  Widget _buildBgStyleChip({
    required BackgroundMode mode,
    required String title,
    required IconData icon,
    required Color accentColor,
  }) {
    final isSelected = _selectedBgMode == mode;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          setState(() => _selectedBgMode = mode);
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? accentColor.withValues(alpha: 0.18) : const Color(0xFF1E1C2E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? accentColor : Colors.white.withValues(alpha: 0.08),
              width: isSelected ? 1.5 : 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: isSelected ? accentColor : Colors.white70, size: 16),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
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

class _StudioMaskPainter extends CustomPainter {
  final List<_DrawnStroke> strokes;
  final _DrawnStroke? activeStroke;
  final double scale;
  final List<DetectedTextBlock> detectedBlocks;
  final Set<int> selectedTextIndices;
  final bool showTextBoxes;

  _StudioMaskPainter({
    required this.strokes,
    required this.activeStroke,
    required this.scale,
    required this.detectedBlocks,
    required this.selectedTextIndices,
    required this.showTextBoxes,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Paint detected text bounding boxes if in Text Remover mode
    if (showTextBoxes) {
      final boxPaint = Paint()
        ..color = const Color(0xFF00E5FF).withValues(alpha: 0.35)
        ..style = PaintingStyle.fill;

      final borderPaint = Paint()
        ..color = const Color(0xFF00E5FF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      for (int i = 0; i < detectedBlocks.length; i++) {
        final block = detectedBlocks[i];
        final rect = Rect.fromLTRB(
          block.boundingBox.left * scale,
          block.boundingBox.top * scale,
          block.boundingBox.right * scale,
          block.boundingBox.bottom * scale,
        );

        if (selectedTextIndices.contains(i)) {
          canvas.drawRect(rect, boxPaint);
          canvas.drawRect(rect, borderPaint);
        }
      }
    }

    // 2. Paint brush stroke masks (Neon Coral glowing highlight)
    final strokePaint = Paint()
      ..color = const Color(0xFFFF5252).withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final allStrokes = [...strokes, if (activeStroke != null) activeStroke!];

    for (final s in allStrokes) {
      if (s.points.isEmpty) continue;
      strokePaint.strokeWidth = s.radius * 2 * scale;

      final path = Path();
      path.moveTo(s.points.first.dx * scale, s.points.first.dy * scale);
      for (int i = 1; i < s.points.length; i++) {
        path.lineTo(s.points[i].dx * scale, s.points[i].dy * scale);
      }
      canvas.drawPath(path, strokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _StudioMaskPainter oldDelegate) => true;
}
