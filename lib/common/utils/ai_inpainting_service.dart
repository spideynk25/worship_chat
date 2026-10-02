import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Configuration parameters for AI Inpainting operation
class InpaintParams {
  final Uint8List imageBytes;
  final Uint8List maskBytes; // Grayscale or Alpha mask (255 = inpaint, 0 = keep)
  final int width;
  final int height;
  final int patchRadius;

  InpaintParams({
    required this.imageBytes,
    required this.maskBytes,
    required this.width,
    required this.height,
    this.patchRadius = 6,
  });
}

/// 100% Free, On-Device, Open-Source Inpainting & Object Removal Service
class AiInpaintingService {
  AiInpaintingService._();
  static final AiInpaintingService instance = AiInpaintingService._();

  /// Erases an object or region defined by the mask bytes from the source file.
  /// Runs inside an isolate via [compute] to keep the UI smooth and responsive.
  Future<File> inpaintImage({
    required File sourceImage,
    required Uint8List maskBytes,
    required int maskWidth,
    required int maskHeight,
    required String outputPath,
    int patchRadius = 6,
  }) async {
    final imageBytes = await sourceImage.readAsBytes();

    final params = InpaintParams(
      imageBytes: imageBytes,
      maskBytes: maskBytes,
      width: maskWidth,
      height: maskHeight,
      patchRadius: patchRadius,
    );

    final Uint8List resultBytes = await compute(_runInpaintingIsolate, params);

    final outputFile = File(outputPath);
    await outputFile.writeAsBytes(resultBytes);
    return outputFile;
  }

  /// Inpainting algorithm running on background isolate:
  /// Uses Fast Marching / Gradient-Weighted Boundary Inpainting
  static Uint8List _runInpaintingIsolate(InpaintParams params) {
    var decoded = img.decodeImage(params.imageBytes);
    if (decoded == null) return params.imageBytes;

    // Smart memory optimization: If image is exceptionally huge (e.g. 48MP raw capture),
    // downscale to max 1280px to guarantee instant computation & minimal RAM usage
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

    // Rescale mask to match decoded image dimensions if needed
    final mask2D = _buildNormalizedMask(
      params.maskBytes,
      params.width,
      params.height,
      imgW,
      imgH,
    );

    // If mask is completely empty, return original encoded image
    bool hasMask = false;
    for (int y = 0; y < imgH; y++) {
      for (int x = 0; x < imgW; x++) {
        if (mask2D[y][x] > 0) {
          hasMask = true;
          break;
        }
      }
      if (hasMask) break;
    }
    if (!hasMask) {
      return Uint8List.fromList(img.encodeJpg(decoded, quality: 92));
    }

    // Find bounding box of masked pixels to speed up processing
    int minX = imgW, maxX = 0, minY = imgH, maxY = 0;
    for (int y = 0; y < imgH; y++) {
      for (int x = 0; x < imgW; x++) {
        if (mask2D[y][x] > 0) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }

    const padding = 16;
    minX = math.max(0, minX - padding);
    minY = math.max(0, minY - padding);
    maxX = math.min(imgW - 1, maxX + padding);
    maxY = math.min(imgH - 1, maxY + padding);

    // Working pixel buffer (R, G, B channels as float for precision)
    final rChannel = List<Float64List>.generate(imgH, (_) => Float64List(imgW));
    final gChannel = List<Float64List>.generate(imgH, (_) => Float64List(imgW));
    final bChannel = List<Float64List>.generate(imgH, (_) => Float64List(imgW));
    final known = List<Uint8List>.generate(imgH, (_) => Uint8List(imgW));

    for (int y = 0; y < imgH; y++) {
      for (int x = 0; x < imgW; x++) {
        final p = decoded.getPixel(x, y);
        rChannel[y][x] = p.r.toDouble();
        gChannel[y][x] = p.g.toDouble();
        bChannel[y][x] = p.b.toDouble();
        known[y][x] = (mask2D[y][x] > 30) ? 0 : 1; // 1 = original clean pixel
      }
    }

    // Boundary marching queue
    final queue = Queue<_PixelPoint>();
    final inQueue = List<Uint8List>.generate(imgH, (_) => Uint8List(imgW));

    // Find initial boundary pixels
    for (int y = minY; y <= maxY; y++) {
      for (int x = minX; x <= maxX; x++) {
        if (known[y][x] == 0) {
          // Check if it neighbors a known pixel
          if (_hasKnownNeighbor(known, x, y, imgW, imgH)) {
            queue.add(_PixelPoint(x, y));
            inQueue[y][x] = 1;
          }
        }
      }
    }

    final radius = params.patchRadius;

    // Fast Marching Inpainting Loop
    while (queue.isNotEmpty) {
      final pt = queue.removeFirst();
      final px = pt.x;
      final py = pt.y;

      double sumW = 0.0;
      double sumR = 0.0;
      double sumG = 0.0;
      double sumB = 0.0;

      // Sample neighboring known pixels within window
      final startY = math.max(minY, py - radius);
      final endY = math.min(maxY, py + radius);
      final startX = math.max(minX, px - radius);
      final endX = math.min(maxX, px + radius);

      for (int ny = startY; ny <= endY; ny++) {
        for (int nx = startX; nx <= endX; nx++) {
          if (known[ny][nx] == 1) {
            final dx = (nx - px).toDouble();
            final dy = (ny - py).toDouble();
            final distSq = dx * dx + dy * dy;
            if (distSq == 0) continue;

            // Distance weight (closer known pixels have stronger influence)
            final w = 1.0 / (distSq * math.sqrt(distSq));

            sumW += w;
            sumR += rChannel[ny][nx] * w;
            sumG += gChannel[ny][nx] * w;
            sumB += bChannel[ny][nx] * w;
          }
        }
      }

      if (sumW > 0.0) {
        rChannel[py][px] = (sumR / sumW).clamp(0.0, 255.0);
        gChannel[py][px] = (sumG / sumW).clamp(0.0, 255.0);
        bChannel[py][px] = (sumB / sumW).clamp(0.0, 255.0);
      }

      // Mark current pixel as known (resolved)
      known[py][px] = 1;

      // Add neighboring unresolved masked pixels to the queue
      const neighborOffsets = [
        [-1, 0], [1, 0], [0, -1], [0, 1],
        [-1, -1], [1, -1], [-1, 1], [1, 1],
      ];

      for (final off in neighborOffsets) {
        final nx = px + off[0];
        final ny = py + off[1];
        if (nx >= minX && nx <= maxX && ny >= minY && ny <= maxY) {
          if (known[ny][nx] == 0 && inQueue[ny][nx] == 0) {
            queue.add(_PixelPoint(nx, ny));
            inQueue[ny][nx] = 1;
          }
        }
      }
    }

    // Write back resolved pixels to image with subtle smoothing over filled regions
    for (int y = minY; y <= maxY; y++) {
      for (int x = minX; x <= maxX; x++) {
        if (mask2D[y][x] > 30) {
          // Subtle 3x3 local blend to soften edge transitions
          double blendR = 0, blendG = 0, blendB = 0, count = 0;
          for (int dy = -1; dy <= 1; dy++) {
            for (int dx = -1; dx <= 1; dx++) {
              final sx = (x + dx).clamp(0, imgW - 1);
              final sy = (y + dy).clamp(0, imgH - 1);
              blendR += rChannel[sy][sx];
              blendG += gChannel[sy][sx];
              blendB += bChannel[sy][sx];
              count += 1.0;
            }
          }

          final r = (blendR / count).round().clamp(0, 255);
          final g = (blendG / count).round().clamp(0, 255);
          final b = (blendB / count).round().clamp(0, 255);

          decoded.setPixelRgba(x, y, r, g, b, 255);
        }
      }
    }

    return Uint8List.fromList(img.encodeJpg(decoded, quality: 94));
  }

  static bool _hasKnownNeighbor(
    List<Uint8List> known,
    int x,
    int y,
    int w,
    int h,
  ) {
    if (x > 0 && known[y][x - 1] == 1) return true;
    if (x < w - 1 && known[y][x + 1] == 1) return true;
    if (y > 0 && known[y - 1][x] == 1) return true;
    if (y < h - 1 && known[y + 1][x] == 1) return true;
    return false;
  }

  /// Builds a 2D byte array for the mask scaled to target image dimensions
  static List<Uint8List> _buildNormalizedMask(
    Uint8List rawMask,
    int srcW,
    int srcH,
    int targetW,
    int targetH,
  ) {
    final result = List<Uint8List>.generate(targetH, (_) => Uint8List(targetW));

    final scaleX = srcW / targetW;
    final scaleY = srcH / targetH;

    for (int ty = 0; ty < targetH; ty++) {
      final sy = (ty * scaleY).floor().clamp(0, srcH - 1);
      final rowOffset = sy * srcW;
      for (int tx = 0; tx < targetW; tx++) {
        final sx = (tx * scaleX).floor().clamp(0, srcW - 1);
        final val = rawMask[rowOffset + sx];
        result[ty][tx] = val;
      }
    }

    return result;
  }
}

class _PixelPoint {
  final int x;
  final int y;
  _PixelPoint(this.x, this.y);
}
