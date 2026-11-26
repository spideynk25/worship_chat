import 'dart:io';
import 'dart:math' as math;

import 'package:extended_image/extended_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:worship_chat/colors.dart';

Future<Uint8List?> _cropSquareImageIsolate(Map<String, dynamic> params) async {
  try {
    final Uint8List rawData = params['rawData'] as Uint8List;
    final double left = params['left'] as double;
    final double top = params['top'] as double;
    final double width = params['width'] as double;
    final double height = params['height'] as double;
    final double rotate = (params['rotate'] as num?)?.toDouble() ?? 0.0;
    final bool flipY = params['flipY'] as bool? ?? false;

    img.Image? decoded = img.decodeImage(rawData);
    if (decoded == null) return null;

    // Normalize EXIF orientation before applying manual rotation/crop.
    decoded = img.bakeOrientation(decoded);

    final double degrees =
        rotate.abs() <= 2 * math.pi ? rotate * 180 / math.pi : rotate;
    if (degrees % 360 != 0) {
      decoded = img.copyRotate(decoded, angle: degrees);
    }

    if (flipY) {
      decoded = img.flipHorizontal(decoded);
    }

    final int x = left.round().clamp(0, decoded.width - 1);
    final int y = top.round().clamp(0, decoded.height - 1);
    final int w = width.round().clamp(1, decoded.width - x);
    final int h = height.round().clamp(1, decoded.height - y);

    final cropped = img.copyCrop(decoded, x: x, y: y, width: w, height: h);
    return Uint8List.fromList(img.encodeJpg(cropped, quality: 92));
  } catch (_) {
    return null;
  }
}

/// Navigates to [SquareImageCropScreen] and returns the cropped JPG file, or `null` if cancelled.
Future<File?> cropImageToSquare(
  BuildContext context,
  File imageFile, {
  String title = 'Crop Profile Photo',
}) {
  return Navigator.of(context).push<File?>(
    MaterialPageRoute(
      builder: (_) => SquareImageCropScreen(
        imageFile: imageFile,
        title: title,
      ),
    ),
  );
}

/// Shared 1:1 square image cropper used when setting User or Group profile photos.
class SquareImageCropScreen extends StatefulWidget {
  final File imageFile;
  final String title;

  const SquareImageCropScreen({
    super.key,
    required this.imageFile,
    this.title = 'Crop Profile Photo',
  });

  @override
  State<SquareImageCropScreen> createState() => _SquareImageCropScreenState();
}

class _SquareImageCropScreenState extends State<SquareImageCropScreen> {
  final GlobalKey<ExtendedImageEditorState> _editorKey =
      GlobalKey<ExtendedImageEditorState>();
  bool _isCropping = false;

  Future<void> _applyCrop() async {
    if (_isCropping) return;
    final state = _editorKey.currentState;
    if (state == null) return;

    final cropRect = state.getCropRect();
    final action = state.editAction;
    if (cropRect == null || action == null) return;

    setState(() => _isCropping = true);
    try {
      final croppedData = await compute(_cropSquareImageIsolate, {
        'rawData': state.rawImageData,
        'left': cropRect.left,
        'top': cropRect.top,
        'width': cropRect.width,
        'height': cropRect.height,
        'rotate': action.rotateAngle,
        'flipY': action.flipY,
      });

      if (!mounted || croppedData == null) return;

      final tempDir = await getTemporaryDirectory();
      final outFile = File(
        '${tempDir.path}/cropped_profile_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await outFile.writeAsBytes(croppedData);
      if (mounted) {
        Navigator.pop(context, outFile);
      }
    } finally {
      if (mounted) {
        setState(() => _isCropping = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0E17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161426),
        elevation: 0,
        title: Text(
          widget.title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.rotate_right_rounded, color: Colors.white70),
            tooltip: 'Rotate',
            onPressed: _isCropping
                ? null
                : () => _editorKey.currentState?.rotate(right: true),
          ),
          IconButton(
            icon: _isCropping
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: tabColor,
                    ),
                  )
                : const Icon(Icons.check_rounded, color: tabColor),
            tooltip: 'Apply crop',
            onPressed: _isCropping ? null : _applyCrop,
          ),
        ],
      ),
      body: Stack(
        children: [
          ExtendedImage.file(
            widget.imageFile,
            fit: BoxFit.contain,
            mode: ExtendedImageMode.editor,
            cacheRawData: true,
            extendedImageEditorKey: _editorKey,
            initEditorConfigHandler: (_) => EditorConfig(
              maxScale: 4.0,
              cropRectPadding: const EdgeInsets.all(24),
              hitTestSize: 36,
              cropAspectRatio: 1.0,
              cornerColor: tabColor,
              cornerSize: const Size(34, 34),
              lineColor: Colors.white.withValues(alpha: 0.85),
              editorMaskColorHandler: (_, pointerDown) =>
                  Colors.black.withValues(alpha: pointerDown ? 0.65 : 0.45),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161426).withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: tabColor.withValues(alpha: 0.35),
                        width: 0.8,
                      ),
                    ),
                    child: const Text(
                      'Drag or pinch to frame square profile photo',
                      style: TextStyle(color: Colors.white, fontSize: 12.5),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
