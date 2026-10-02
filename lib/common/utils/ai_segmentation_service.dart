import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_selfie_segmentation/google_mlkit_selfie_segmentation.dart';
import 'package:image/image.dart' as img;

/// Background replacement options
enum BackgroundMode {
  transparent, // Cutout sticker (PNG)
  portraitBlur, // DSLR Bokeh blur
  studioDark, // Charcoal studio backdrop
  studioWhite, // Clean white e-commerce / profile backdrop
  studioGradient, // Vibrant royal/neon studio gradient
}

class SegmentationParams {
  final Uint8List imageBytes;
  final List<double> confidences;
  final int maskWidth;
  final int maskHeight;
  final BackgroundMode mode;
  final int blurRadius;
  final int bgColorR;
  final int bgColorG;
  final int bgColorB;

  SegmentationParams({
    required this.imageBytes,
    required this.confidences,
    required this.maskWidth,
    required this.maskHeight,
    required this.mode,
    this.blurRadius = 16,
    this.bgColorR = 18,
    this.bgColorG = 17,
    this.bgColorB = 26,
  });
}

/// 100% Free, On-Device, Open-Source Background Removal & Portrait Studio Service
class AiSegmentationService {
  AiSegmentationService._();
  static final AiSegmentationService instance = AiSegmentationService._();

  SelfieSegmenter? _segmenter;

  SelfieSegmenter get _getSegmenter {
    _segmenter ??= SelfieSegmenter(
      mode: SegmenterMode.single,
      enableRawSizeMask: true,
    );
    return _segmenter!;
  }

  /// Processes subject segmentation and generates a cutout or studio background image.
  Future<File> processBackground({
    required File sourceImage,
    required String outputPath,
    required BackgroundMode mode,
    int blurRadius = 16,
    int bgColorR = 18,
    int bgColorG = 17,
    int bgColorB = 26,
  }) async {
    final inputImage = InputImage.fromFile(sourceImage);
    final mask = await _getSegmenter.processImage(inputImage);

    if (mask == null) {
      throw Exception('Subject segmentation could not detect foreground in this image.');
    }

    final imageBytes = await sourceImage.readAsBytes();

    final params = SegmentationParams(
      imageBytes: imageBytes,
      confidences: mask.confidences,
      maskWidth: mask.width,
      maskHeight: mask.height,
      mode: mode,
      blurRadius: blurRadius,
      bgColorR: bgColorR,
      bgColorG: bgColorG,
      bgColorB: bgColorB,
    );

    final Uint8List outputBytes = await compute(_runSegmentationIsolate, params);

    final outputFile = File(outputPath);
    await outputFile.writeAsBytes(outputBytes);
    return outputFile;
  }

  static Uint8List _runSegmentationIsolate(SegmentationParams params) {
    var decoded = img.decodeImage(params.imageBytes);
    if (decoded == null) return params.imageBytes;

    // Smart memory optimization for huge camera photos
    final maxDim = math.max(decoded.width, decoded.height);
    if (maxDim > 1280) {
      final scale = 1280.0 / maxDim;
      decoded = img.copyResize(
        decoded,
        width: (decoded.width * scale).round(),
        height: (decoded.height * scale).round(),
        interpolation: img.Interpolation.linear,
      );
    }

    final imgW = decoded.width;
    final imgH = decoded.height;
    final maskW = params.maskWidth;
    final maskH = params.maskHeight;

    final confidences = params.confidences;

    // Helper to get bilinear-interpolated confidence for any (x, y) in original image
    double getConfidence(int x, int y) {
      final mx = (x / imgW) * maskW;
      final my = (y / imgH) * maskH;

      final x0 = mx.floor().clamp(0, maskW - 1);
      final y0 = my.floor().clamp(0, maskH - 1);
      final x1 = (x0 + 1).clamp(0, maskW - 1);
      final y1 = (y0 + 1).clamp(0, maskH - 1);

      final fx = mx - x0;
      final fy = my - y0;

      final c00 = confidences[y0 * maskW + x0];
      final c10 = confidences[y0 * maskW + x1];
      final c01 = confidences[y1 * maskW + x0];
      final c11 = confidences[y1 * maskW + x1];

      final top = c00 * (1 - fx) + c10 * fx;
      final bottom = c01 * (1 - fx) + c11 * fx;
      return top * (1 - fy) + bottom * fy;
    }

    if (params.mode == BackgroundMode.portraitBlur) {
      // Create a blurred copy of the original image
      final blurred = img.gaussianBlur(img.Image.from(decoded), radius: params.blurRadius);

      for (int y = 0; y < imgH; y++) {
        for (int x = 0; x < imgW; x++) {
          final conf = getConfidence(x, y);
          // Sigmoid / smoothstep thresholding
          final alpha = (conf - 0.25) / 0.5;
          final clampedAlpha = alpha.clamp(0.0, 1.0);

          if (clampedAlpha < 1.0) {
            final fg = decoded.getPixel(x, y);
            final bg = blurred.getPixel(x, y);

            final r = (fg.r * clampedAlpha + bg.r * (1 - clampedAlpha)).round().clamp(0, 255);
            final g = (fg.g * clampedAlpha + bg.g * (1 - clampedAlpha)).round().clamp(0, 255);
            final b = (fg.b * clampedAlpha + bg.b * (1 - clampedAlpha)).round().clamp(0, 255);

            decoded.setPixelRgba(x, y, r, g, b, 255);
          }
        }
      }

      return Uint8List.fromList(img.encodeJpg(decoded, quality: 94));
    } else if (params.mode == BackgroundMode.transparent) {
      // Output RGBA PNG with alpha matte
      final result = img.Image(width: imgW, height: imgH, numChannels: 4);

      for (int y = 0; y < imgH; y++) {
        for (int x = 0; x < imgW; x++) {
          final conf = getConfidence(x, y);
          final fg = decoded.getPixel(x, y);

          // Feathered alpha
          final alpha = (conf * 255).round().clamp(0, 255);
          if (alpha > 15) {
            result.setPixelRgba(x, y, fg.r.toInt(), fg.g.toInt(), fg.b.toInt(), alpha);
          } else {
            result.setPixelRgba(x, y, 0, 0, 0, 0);
          }
        }
      }

      return Uint8List.fromList(img.encodePng(result));
    } else {
      // Solid or Gradient Studio Background
      for (int y = 0; y < imgH; y++) {
        // Vertical gradient interpolation if studio gradient
        final t = y / imgH;
        final bgR = (params.mode == BackgroundMode.studioGradient)
            ? (26 * (1 - t) + 106 * t).round().clamp(0, 255)
            : params.bgColorR;
        final bgG = (params.mode == BackgroundMode.studioGradient)
            ? (35 * (1 - t) + 27 * t).round().clamp(0, 255)
            : params.bgColorG;
        final bgB = (params.mode == BackgroundMode.studioGradient)
            ? (126 * (1 - t) + 154 * t).round().clamp(0, 255)
            : params.bgColorB;

        for (int x = 0; x < imgW; x++) {
          final conf = getConfidence(x, y);
          final clampedAlpha = ((conf - 0.2) / 0.6).clamp(0.0, 1.0);

          if (clampedAlpha < 1.0) {
            final fg = decoded.getPixel(x, y);
            final r = (fg.r * clampedAlpha + bgR * (1 - clampedAlpha)).round().clamp(0, 255);
            final g = (fg.g * clampedAlpha + bgG * (1 - clampedAlpha)).round().clamp(0, 255);
            final b = (fg.b * clampedAlpha + bgB * (1 - clampedAlpha)).round().clamp(0, 255);

            decoded.setPixelRgba(x, y, r, g, b, 255);
          }
        }
      }

      return Uint8List.fromList(img.encodeJpg(decoded, quality: 94));
    }
  }

  void dispose() {
    _segmenter?.close();
    _segmenter = null;
  }
}
