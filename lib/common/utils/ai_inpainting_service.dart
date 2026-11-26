import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Configuration parameters for background isolate inpainting.
class InpaintParams {
  final Uint8List imageBytes;
  final Uint8List maskBytes; // 255 = inpaint, 0 = keep
  final int width;
  final int height;
  final int patchRadius;
  final bool scrubTextHalos;
  final bool preferPng;

  const InpaintParams({
    required this.imageBytes,
    required this.maskBytes,
    required this.width,
    required this.height,
    this.patchRadius = 6,
    this.scrubTextHalos = true,
    this.preferPng = false,
  });
}

/// 100% on-device, resolution-preserving texture & structure inpainting service.
class AiInpaintingService {
  AiInpaintingService._();
  static final AiInpaintingService instance = AiInpaintingService._();

  /// Erases regions marked in [maskBytes] from [sourceImage] on a background isolate.
  Future<File> inpaintImage({
    required File sourceImage,
    required Uint8List maskBytes,
    required int maskWidth,
    required int maskHeight,
    required String outputPath,
    int patchRadius = 6,
    bool scrubTextHalos = true,
  }) async {
    final imageBytes = await sourceImage.readAsBytes();
    final preferPng = outputPath.toLowerCase().endsWith('.png');

    final params = InpaintParams(
      imageBytes: imageBytes,
      maskBytes: maskBytes,
      width: maskWidth,
      height: maskHeight,
      patchRadius: patchRadius,
      scrubTextHalos: scrubTextHalos,
      preferPng: preferPng,
    );

    final resultBytes = await compute(_runInpaintingIsolate, params);
    final outputFile = File(outputPath);
    await outputFile.writeAsBytes(resultBytes);
    return outputFile;
  }

  /// Decodes, EXIF-bakes, inpaints masked regions at full native resolution, and encodes.
  static Uint8List inpaintImageBytes(InpaintParams params) {
    return _runInpaintingIsolate(params);
  }

  static Uint8List _runInpaintingIsolate(InpaintParams params) {
    final decoded = decodeAndBakeImage(params.imageBytes);
    if (decoded == null) return params.imageBytes;

    final imgW = decoded.width;
    final imgH = decoded.height;

    final mask2D = buildNormalizedMask(
      params.maskBytes,
      params.width,
      params.height,
      imgW,
      imgH,
    );

    inpaintDecodedImage(
      decoded,
      mask2D,
      patchRadius: params.patchRadius,
      scrubTextHalos: params.scrubTextHalos,
    );

    return encodeOutputImage(decoded, preferPng: params.preferPng);
  }

  /// Decodes image bytes and bakes EXIF orientation so pixel dimensions match UI & OCR.
  static img.Image? decodeAndBakeImage(Uint8List imageBytes) {
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) return null;
    return img.bakeOrientation(decoded);
  }

  /// Encodes output image cleanly without aggressive quality degradation.
  static Uint8List encodeOutputImage(img.Image image, {bool preferPng = false}) {
    if (preferPng) {
      return Uint8List.fromList(img.encodePng(image));
    }
    return Uint8List.fromList(img.encodeJpg(image, quality: 96));
  }

  /// Rescales a 1-channel flat mask into a binary [targetH x targetW] 2D buffer.
  static List<Uint8List> buildNormalizedMask(
    Uint8List rawMask,
    int srcW,
    int srcH,
    int targetW,
    int targetH,
  ) {
    final result = List<Uint8List>.generate(targetH, (_) => Uint8List(targetW));
    if (srcW <= 0 || srcH <= 0 || rawMask.isEmpty) return result;

    if (srcW == targetW && srcH == targetH && rawMask.length >= targetW * targetH) {
      for (int y = 0; y < targetH; y++) {
        final offset = y * targetW;
        for (int x = 0; x < targetW; x++) {
          result[y][x] = rawMask[offset + x] > 30 ? 255 : 0;
        }
      }
      return result;
    }

    final scaleX = srcW / targetW;
    final scaleY = srcH / targetH;
    for (int ty = 0; ty < targetH; ty++) {
      final sy = (ty * scaleY).floor().clamp(0, srcH - 1);
      final rowOffset = sy * srcW;
      for (int tx = 0; tx < targetW; tx++) {
        final sx = (tx * scaleX).floor().clamp(0, srcW - 1);
        final idx = rowOffset + sx;
        if (idx < rawMask.length && rawMask[idx] > 30) {
          result[ty][tx] = 255;
        }
      }
    }
    return result;
  }

  /// Inpaints all regions marked > 0 in [mask2D] in-place on [image] while keeping
  /// unmasked pixels untouched at native resolution.
  static img.Image inpaintDecodedImage(
    img.Image image,
    List<Uint8List> mask2D, {
    int patchRadius = 6,
    bool scrubTextHalos = true,
  }) {
    final imgW = image.width;
    final imgH = image.height;
    final components = _extractMaskComponents(mask2D, imgW, imgH);
    if (components.isEmpty) return image;

    for (final bounds in components) {
      _inpaintRegionCrop(
        image: image,
        mask2D: mask2D,
        imgW: imgW,
        imgH: imgH,
        bounds: bounds,
        patchRadius: patchRadius,
        scrubTextHalos: scrubTextHalos,
      );
    }

    return image;
  }

  /// Finds merged local bounding boxes of masked components so full-res images only
  /// allocate work buffers for the neighborhood of actual text/brush regions.
  static List<_MaskBounds> _extractMaskComponents(
    List<Uint8List> mask2D,
    int imgW,
    int imgH,
  ) {
    const cell = 8;
    final gw = (imgW + cell - 1) ~/ cell;
    final gh = (imgH + cell - 1) ~/ cell;
    final occ = Uint8List(gw * gh);

    for (int y = 0; y < imgH; y++) {
      final row = mask2D[y];
      final gy = y ~/ cell;
      final gRow = gy * gw;
      for (int x = 0; x < imgW; x++) {
        if (row[x] > 0) {
          occ[gRow + (x ~/ cell)] = 1;
        }
      }
    }

    final visited = Uint8List(gw * gh);
    final rawBoxes = <_MaskBounds>[];
    final qx = <int>[];
    final qy = <int>[];

    for (int sy = 0; sy < gh; sy++) {
      for (int sx = 0; sx < gw; sx++) {
        final sIdx = sy * gw + sx;
        if (occ[sIdx] == 0 || visited[sIdx] == 1) continue;

        visited[sIdx] = 1;
        qx.add(sx);
        qy.add(sy);
        int head = 0;
        int minGx = sx, maxGx = sx, minGy = sy, maxGy = sy;

        while (head < qx.length) {
          final cx = qx[head];
          final cy = qy[head];
          head++;

          if (cx < minGx) minGx = cx;
          if (cx > maxGx) maxGx = cx;
          if (cy < minGy) minGy = cy;
          if (cy > maxGy) maxGy = cy;

          // Merge cells within 2 grid steps (16px) so adjacent letters share context
          for (int dy = -2; dy <= 2; dy++) {
            final ny = cy + dy;
            if (ny < 0 || ny >= gh) continue;
            for (int dx = -2; dx <= 2; dx++) {
              final nx = cx + dx;
              if (nx < 0 || nx >= gw) continue;
              final nIdx = ny * gw + nx;
              if (occ[nIdx] == 1 && visited[nIdx] == 0) {
                visited[nIdx] = 1;
                qx.add(nx);
                qy.add(ny);
              }
            }
          }
        }

        qx.clear();
        qy.clear();

        // Refine exact pixel bounds inside the grid component
        final startX = math.max(0, minGx * cell);
        final endX = math.min(imgW - 1, (maxGx + 1) * cell - 1);
        final startY = math.max(0, minGy * cell);
        final endY = math.min(imgH - 1, (maxGy + 1) * cell - 1);

        int pMinX = endX, pMaxX = startX, pMinY = endY, pMaxY = startY;
        bool any = false;
        for (int y = startY; y <= endY; y++) {
          final row = mask2D[y];
          for (int x = startX; x <= endX; x++) {
            if (row[x] > 0) {
              any = true;
              if (x < pMinX) pMinX = x;
              if (x > pMaxX) pMaxX = x;
              if (y < pMinY) pMinY = y;
              if (y > pMaxY) pMaxY = y;
            }
          }
        }
        if (any) {
          rawBoxes.add(_MaskBounds(pMinX, pMinY, pMaxX, pMaxY));
        }
      }
    }

    // Merge overlapping or nearby boxes (within 20px) to avoid double-edge artifacts
    const mergeGap = 20;
    final merged = <_MaskBounds>[];
    for (final box in rawBoxes) {
      var current = box;
      bool mergedIntoExisting = true;
      while (mergedIntoExisting) {
        mergedIntoExisting = false;
        for (int i = 0; i < merged.length; i++) {
          final other = merged[i];
          if (current.minX <= other.maxX + mergeGap &&
              current.maxX >= other.minX - mergeGap &&
              current.minY <= other.maxY + mergeGap &&
              current.maxY >= other.minY - mergeGap) {
            current = _MaskBounds(
              math.min(current.minX, other.minX),
              math.min(current.minY, other.minY),
              math.max(current.maxX, other.maxX),
              math.max(current.maxY, other.maxY),
            );
            merged.removeAt(i);
            mergedIntoExisting = true;
            break;
          }
        }
      }
      merged.add(current);
    }

    return merged;
  }

  static void _inpaintRegionCrop({
    required img.Image image,
    required List<Uint8List> mask2D,
    required int imgW,
    required int imgH,
    required _MaskBounds bounds,
    required int patchRadius,
    required bool scrubTextHalos,
  }) {
    final maskSpan = math.max(bounds.width, bounds.height);
    final contextPad = (maskSpan * 0.35).round().clamp(32, 64);

    final cropMinX = math.max(0, bounds.minX - contextPad);
    final cropMinY = math.max(0, bounds.minY - contextPad);
    final cropMaxX = math.min(imgW - 1, bounds.maxX + contextPad);
    final cropMaxY = math.min(imgH - 1, bounds.maxY + contextPad);

    final fullW = cropMaxX - cropMinX + 1;
    final fullH = cropMaxY - cropMinY + 1;
    final maxCropDim = math.max(fullW, fullH);

    // Work at full native resolution for normal text boxes; cap only huge strokes
    const maxWorkDim = 840;
    final needsDownscale = maxCropDim > maxWorkDim;
    final scale = needsDownscale ? maxWorkDim / maxCropDim : 1.0;
    final workW = needsDownscale ? math.max(16, (fullW * scale).round()) : fullW;
    final workH = needsDownscale ? math.max(16, (fullH * scale).round()) : fullH;

    final rBuf = Float64List(workW * workH);
    final gBuf = Float64List(workW * workH);
    final bBuf = Float64List(workW * workH);
    final mask = Uint8List(workW * workH);

    for (int wy = 0; wy < workH; wy++) {
      final sy = cropMinY + (needsDownscale ? (wy / scale).floor().clamp(0, fullH - 1) : wy);
      final wRow = wy * workW;
      for (int wx = 0; wx < workW; wx++) {
        final sx = cropMinX + (needsDownscale ? (wx / scale).floor().clamp(0, fullW - 1) : wx);
        final px = image.getPixel(sx, sy);
        final idx = wRow + wx;
        rBuf[idx] = px.r.toDouble();
        gBuf[idx] = px.g.toDouble();
        bBuf[idx] = px.b.toDouble();
        mask[idx] = mask2D[sy][sx] > 0 ? 1 : 0;
      }
    }

    if (scrubTextHalos) {
      _scrubBoundaryHalos(rBuf, gBuf, bBuf, mask, workW, workH);
    }

    final solved = _solveCropInpainting(
      rBuf: rBuf,
      gBuf: gBuf,
      bBuf: bBuf,
      mask: mask,
      w: workW,
      h: workH,
      patchRadius: patchRadius,
    );

    // Copy synthesized pixels back ONLY inside the masked region
    for (int fy = 0; fy < fullH; fy++) {
      final imgY = cropMinY + fy;
      final wy = needsDownscale ? (fy * scale).clamp(0.0, (workH - 1).toDouble()) : fy.toDouble();
      final wy0 = wy.floor();
      final wy1 = math.min(workH - 1, wy0 + 1);
      final ty = wy - wy0;

      for (int fx = 0; fx < fullW; fx++) {
        final imgX = cropMinX + fx;
        final isMasked = mask2D[imgY][imgX] > 0 ||
            (!needsDownscale && mask[fy * workW + fx] > 0);
        if (!isMasked) continue;

        if (!needsDownscale) {
          final idx = fy * workW + fx;
          final r = solved.r[idx].round().clamp(0, 255);
          final g = solved.g[idx].round().clamp(0, 255);
          final b = solved.b[idx].round().clamp(0, 255);
          final a = image.getPixel(imgX, imgY).a.round().clamp(0, 255);
          image.setPixelRgba(imgX, imgY, r, g, b, a);
        } else {
          final wx = (fx * scale).clamp(0.0, (workW - 1).toDouble());
          final wx0 = wx.floor();
          final wx1 = math.min(workW - 1, wx0 + 1);
          final tx = wx - wx0;

          final i00 = wy0 * workW + wx0;
          final i10 = wy0 * workW + wx1;
          final i01 = wy1 * workW + wx0;
          final i11 = wy1 * workW + wx1;

          final r = _bilerp(solved.r[i00], solved.r[i10], solved.r[i01], solved.r[i11], tx, ty)
              .round()
              .clamp(0, 255);
          final g = _bilerp(solved.g[i00], solved.g[i10], solved.g[i01], solved.g[i11], tx, ty)
              .round()
              .clamp(0, 255);
          final b = _bilerp(solved.b[i00], solved.b[i10], solved.b[i01], solved.b[i11], tx, ty)
              .round()
              .clamp(0, 255);
          final a = image.getPixel(imgX, imgY).a.round().clamp(0, 255);
          image.setPixelRgba(imgX, imgY, r, g, b, a);
        }
      }
    }
  }

  static double _bilerp(double c00, double c10, double c01, double c11, double tx, double ty) {
    final top = c00 + (c10 - c00) * tx;
    final bot = c01 + (c11 - c01) * tx;
    return top + (bot - top) * ty;
  }

  /// Expands mask by up to 2px at border pixels where anti-aliased letter fringes,
  /// outlines, or drop shadows deviate sharply from the adjacent outer clean ring.
  static void _scrubBoundaryHalos(
    Float64List rBuf,
    Float64List gBuf,
    Float64List bBuf,
    Uint8List mask,
    int w,
    int h,
  ) {
    final outDist = Uint8List(w * h);
    final queue = Queue<int>();

    for (int y = 0; y < h; y++) {
      final row = y * w;
      for (int x = 0; x < w; x++) {
        final idx = row + x;
        if (mask[idx] == 1) continue;
        if (_hasMaskNeighbor(mask, x, y, w, h)) {
          outDist[idx] = 1;
          queue.add(idx);
        }
      }
    }

    while (queue.isNotEmpty) {
      final idx = queue.removeFirst();
      final d = outDist[idx];
      if (d >= 6) continue;
      final x = idx % w;
      final y = idx ~/ w;
      const dirs = [[-1, 0], [1, 0], [0, -1], [0, 1]];
      for (final off in dirs) {
        final nx = x + off[0];
        final ny = y + off[1];
        if (nx < 0 || nx >= w || ny < 0 || ny >= h) continue;
        final nIdx = ny * w + nx;
        if (mask[nIdx] == 0 && outDist[nIdx] == 0) {
          outDist[nIdx] = d + 1;
          queue.add(nIdx);
        }
      }
    }

    // Pass 1 absorbs extreme fringe at d=1; Pass 2 only absorbs d=2 touching scrubbed pixels
    for (int targetD = 1; targetD <= 2; targetD++) {
      final toAdd = <int>[];
      for (int y = 1; y < h - 1; y++) {
        final row = y * w;
        for (int x = 1; x < w - 1; x++) {
          final idx = row + x;
          if (mask[idx] != 0 || outDist[idx] != targetD) continue;
          if (targetD == 2 && !_hasMaskNeighbor(mask, x, y, w, h)) continue;

          // Sample outer clean reference ring (outDist in 3..6) inside 13x13 window
          double sumR = 0, sumG = 0, sumB = 0;
          int count = 0;
          final minY = math.max(0, y - 6);
          final maxY = math.min(h - 1, y + 6);
          final minX = math.max(0, x - 6);
          final maxX = math.min(w - 1, x + 6);

          for (int ny = minY; ny <= maxY; ny++) {
            final nRow = ny * w;
            for (int nx = minX; nx <= maxX; nx++) {
              final nIdx = nRow + nx;
              if (mask[nIdx] == 0 && outDist[nIdx] >= 3) {
                sumR += rBuf[nIdx];
                sumG += gBuf[nIdx];
                sumB += bBuf[nIdx];
                count++;
              }
            }
          }
          if (count < 8) continue;

          final meanR = sumR / count;
          final meanG = sumG / count;
          final meanB = sumB / count;

          double madSum = 0;
          for (int ny = minY; ny <= maxY; ny++) {
            final nRow = ny * w;
            for (int nx = minX; nx <= maxX; nx++) {
              final nIdx = nRow + nx;
              if (mask[nIdx] == 0 && outDist[nIdx] >= 3) {
                madSum += (rBuf[nIdx] - meanR).abs() +
                    (gBuf[nIdx] - meanG).abs() +
                    (bBuf[nIdx] - meanB).abs();
              }
            }
          }
          final avgSpread = madSum / (count * 3.0);
          final dev = ((rBuf[idx] - meanR).abs() +
                  (gBuf[idx] - meanG).abs() +
                  (bBuf[idx] - meanB).abs()) /
              3.0;

          // Only absorb when pixel sharply contrasts with calm outer background ring
          if (dev > math.max(32.0, avgSpread * 2.8)) {
            toAdd.add(idx);
          }
        }
      }
      for (final idx in toAdd) {
        mask[idx] = 1;
      }
    }
  }

  /// Stage 2 (Distance-ordered Isophote-Weighted Fill) + Stage 3 (Coherent Exemplar Synthesis).
  static _RgbBuffers _solveCropInpainting({
    required Float64List rBuf,
    required Float64List gBuf,
    required Float64List bBuf,
    required Uint8List mask,
    required int w,
    required int h,
    required int patchRadius,
  }) {
    final total = w * h;
    final origKnown = Uint8List(total);
    final known = Uint8List(total);
    final inDist = Int32List(total);
    final queue = Queue<int>();

    for (int i = 0; i < total; i++) {
      if (mask[i] == 0) {
        origKnown[i] = 1;
        known[i] = 1;
      }
    }

    // Build inward distance layers using 8-connected BFS
    int maxLayer = 0;
    for (int y = 0; y < h; y++) {
      final row = y * w;
      for (int x = 0; x < w; x++) {
        final idx = row + x;
        if (mask[idx] == 1 && _hasKnown8Neighbor(origKnown, x, y, w, h)) {
          inDist[idx] = 1;
          queue.add(idx);
          if (maxLayer < 1) maxLayer = 1;
        }
      }
    }

    const dirs8 = [
      [-1, 0], [1, 0], [0, -1], [0, 1],
      [-1, -1], [1, -1], [-1, 1], [1, 1],
    ];

    while (queue.isNotEmpty) {
      final idx = queue.removeFirst();
      final nextD = inDist[idx] + 1;
      final x = idx % w;
      final y = idx ~/ w;
      for (final off in dirs8) {
        final nx = x + off[0];
        final ny = y + off[1];
        if (nx < 0 || nx >= w || ny < 0 || ny >= h) continue;
        final nIdx = ny * w + nx;
        if (mask[nIdx] == 1 && inDist[nIdx] == 0) {
          inDist[nIdx] = nextD;
          if (nextD > maxLayer) maxLayer = nextD;
          queue.add(nIdx);
        }
      }
    }

    // Group masked pixel indices by distance layer for strict boundary-inward progression
    final layers = List<List<int>>.generate(maxLayer + 1, (_) => <int>[]);
    int maskedCount = 0;
    for (int i = 0; i < total; i++) {
      if (mask[i] == 1 && inDist[i] > 0) {
        layers[inDist[i]].add(i);
        maskedCount++;
      }
    }

    if (maskedCount == 0) {
      return _RgbBuffers(rBuf, gBuf, bBuf);
    }

    // Precompute smooth luminance & gradients on clean unmasked pixels
    final lum = Float64List(total);
    final gx = Float64List(total);
    final gy = Float64List(total);
    for (int i = 0; i < total; i++) {
      lum[i] = 0.299 * rBuf[i] + 0.587 * gBuf[i] + 0.114 * bBuf[i];
    }
    for (int y = 1; y < h - 1; y++) {
      final row = y * w;
      for (int x = 1; x < w - 1; x++) {
        final idx = row + x;
        if (origKnown[idx] == 0) continue;
        final lx0 = origKnown[idx - 1] == 1 ? lum[idx - 1] : lum[idx];
        final lx1 = origKnown[idx + 1] == 1 ? lum[idx + 1] : lum[idx];
        final ly0 = origKnown[idx - w] == 1 ? lum[idx - w] : lum[idx];
        final ly1 = origKnown[idx + w] == 1 ? lum[idx + w] : lum[idx];
        gx[idx] = (lx1 - lx0) * 0.5;
        gy[idx] = (ly1 - ly0) * 0.5;
      }
    }

    // Stage 2: Directional Isophote-Guided Telea Fill
    final radius = patchRadius.clamp(5, 8);
    for (int layer = 1; layer <= maxLayer; layer++) {
      for (final idx in layers[layer]) {
        final px = idx % w;
        final py = idx ~/ w;

        final startY = math.max(0, py - radius);
        final endY = math.min(h - 1, py + radius);
        final startX = math.max(0, px - radius);
        final endX = math.min(w - 1, px + radius);

        double sumW = 0, sumR = 0, sumG = 0, sumB = 0;
        double minR = 255, minG = 255, minB = 255;
        double maxR = 0, maxG = 0, maxB = 0;

        for (int ny = startY; ny <= endY; ny++) {
          final nRow = ny * w;
          final dy = (py - ny).toDouble();
          for (int nx = startX; nx <= endX; nx++) {
            final nIdx = nRow + nx;
            if (known[nIdx] == 0) continue;

            final dx = (px - nx).toDouble();
            final distSq = dx * dx + dy * dy;
            if (distSq == 0) continue;

            final dist = math.sqrt(distSq);
            double geom = 1.0 / (distSq * dist);
            final trust = origKnown[nIdx] == 1 ? 1.7 : 0.85;

            // Alignment along isophote tangent (-gy, gx) preserves sharp scene edges
            final ngx = gx[nIdx];
            final ngy = gy[nIdx];
            final gMag = math.sqrt(ngx * ngx + ngy * ngy);
            double dirFactor = 1.0;
            if (gMag > 10.0) {
              final isoDot = (dx * (-ngy) + dy * ngx).abs() / (dist * gMag + 1e-4);
              dirFactor = 0.25 + 0.75 * isoDot * isoDot;
            }

            final wgt = geom * trust * dirFactor;
            final nr = rBuf[nIdx];
            final ng = gBuf[nIdx];
            final nb = bBuf[nIdx];

            sumW += wgt;
            sumR += nr * wgt;
            sumG += ng * wgt;
            sumB += nb * wgt;

            if (nr < minR) minR = nr;
            if (nr > maxR) maxR = nr;
            if (ng < minG) minG = ng;
            if (ng > maxG) maxG = ng;
            if (nb < minB) minB = nb;
            if (nb > maxB) maxB = nb;
          }
        }

        if (sumW > 0.0) {
          rBuf[idx] = (sumR / sumW).clamp(minR, maxR);
          gBuf[idx] = (sumG / sumW).clamp(minG, maxG);
          bBuf[idx] = (sumB / sumW).clamp(minB, maxB);
        }
        known[idx] = 1;
      }
    }

    // Precompute clean-5x5 mask lookup and nearest clean boundary rays for O(1) probes
    final clean5x5 = Uint8List(total);
    for (int y = 2; y < h - 2; y++) {
      for (int x = 2; x < w - 2; x++) {
        if (_isClean5x5Patch(origKnown, x, y, w)) {
          clean5x5[y * w + x] = 1;
        }
      }
    }

    // Nearest clean 5x5 exemplar along cardinal directions for instant structural lock
    final upCleanY = Int32List(total)..fillRange(0, total, -1);
    final downCleanY = Int32List(total)..fillRange(0, total, -1);
    final leftCleanX = Int32List(total)..fillRange(0, total, -1);
    final rightCleanX = Int32List(total)..fillRange(0, total, -1);

    for (int x = 2; x < w - 2; x++) {
      int lastClean = -1;
      for (int y = 0; y < h; y++) {
        final idx = y * w + x;
        if (clean5x5[idx] == 1) lastClean = y;
        upCleanY[idx] = lastClean;
      }
      lastClean = -1;
      for (int y = h - 1; y >= 0; y--) {
        final idx = y * w + x;
        if (clean5x5[idx] == 1) lastClean = y;
        downCleanY[idx] = lastClean;
      }
    }
    for (int y = 2; y < h - 2; y++) {
      final row = y * w;
      int lastClean = -1;
      for (int x = 0; x < w; x++) {
        final idx = row + x;
        if (clean5x5[idx] == 1) lastClean = x;
        leftCleanX[idx] = lastClean;
      }
      lastClean = -1;
      for (int x = w - 1; x >= 0; x--) {
        final idx = row + x;
        if (clean5x5[idx] == 1) lastClean = x;
        rightCleanX[idx] = lastClean;
      }
    }

    // Keep structural guide buffer separate for smooth gradient fallback/modulation
    final guideR = Float64List.fromList(rBuf);
    final guideG = Float64List.fromList(gBuf);
    final guideB = Float64List.fromList(bBuf);

    // Stage 3: Coherent Local Exemplar Patch Synthesis for crisp grain/pattern continuity
    final outR = Float64List.fromList(rBuf);
    final outG = Float64List.fromList(gBuf);
    final outB = Float64List.fromList(bBuf);
    final synthDone = Uint8List.fromList(origKnown);
    final matchX = Int32List(total)..fillRange(0, total, -1);
    final matchY = Int32List(total)..fillRange(0, total, -1);

    const sampleOffsets = [
      [-2, -2], [0, -2], [2, -2],
      [-1, -1], [1, -1],
      [-2, 0], [2, 0],
      [-1, 1], [1, 1],
      [-2, 2], [0, 2], [2, 2],
    ];

    const spatialWeight = 0.02;
    final gridStride = maskedCount > 25000 ? 7 : 4;
    const searchWindow = 36;

    for (int pass = 0; pass < 2; pass++) {
      for (int layer = 1; layer <= maxLayer; layer++) {
        for (final idx in layers[layer]) {
          final px = idx % w;
          final py = idx ~/ w;

          double bestCost = double.infinity;
          int bestExX = -1;
          int bestExY = -1;
          double bestSsd = double.infinity;

          void evaluateCandidate(int cx, int cy) {
            if (cx < 2 || cx >= w - 2 || cy < 2 || cy >= h - 2) return;
            if (clean5x5[cy * w + cx] == 0) return;

            final ddx = (px - cx).toDouble();
            final ddy = (py - cy).toDouble();
            final spatialPenalty = (ddx * ddx + ddy * ddy) * spatialWeight;
            if (spatialPenalty >= bestCost) return;

            final ssd = _patchSsd5x5(
              rBuf: outR,
              gBuf: outG,
              bBuf: outB,
              origR: rBuf,
              origG: gBuf,
              origB: bBuf,
              origKnown: origKnown,
              synthDone: synthDone,
              px: px,
              py: py,
              ex: cx,
              ey: cy,
              w: w,
              h: h,
              sampleOffsets: sampleOffsets,
            );

            final totalCost = ssd + spatialPenalty;
            if (totalCost < bestCost) {
              bestCost = totalCost;
              bestSsd = ssd;
              bestExX = cx;
              bestExY = cy;
            }
          }

          // 1. Test coherent shifted patches propagated from resolved neighbors
          const coherenceDirs = [
            [-1, 0], [0, -1], [1, 0], [0, 1],
            [-1, -1], [1, -1], [-1, 1], [1, 1],
          ];
          for (final dir in coherenceDirs) {
            final nx = px + dir[0];
            final ny = py + dir[1];
            if (nx < 0 || nx >= w || ny < 0 || ny >= h) continue;
            final nIdx = ny * w + nx;
            if (matchX[nIdx] >= 0) {
              evaluateCandidate(matchX[nIdx] - dir[0], matchY[nIdx] - dir[1]);
            }
          }

          // 2. Probe cardinal clean border exemplars straight out of mask
          if (upCleanY[idx] >= 2) {
            final baseY = upCleanY[idx];
            evaluateCandidate(px, baseY);
            evaluateCandidate(px, baseY - 2);
          }
          if (downCleanY[idx] >= 2) {
            final baseY = downCleanY[idx];
            evaluateCandidate(px, baseY);
            evaluateCandidate(px, baseY + 2);
          }
          if (leftCleanX[idx] >= 2) {
            final baseX = leftCleanX[idx];
            evaluateCandidate(baseX, py);
            evaluateCandidate(baseX - 2, py);
          }
          if (rightCleanX[idx] >= 2) {
            final baseX = rightCleanX[idx];
            evaluateCandidate(baseX, py);
            evaluateCandidate(baseX + 2, py);
          }

          // 3. On pass 0 or when coherent match has noticeable residual, probe local grid
          if (pass == 0 || bestSsd > 650.0) {
            final minGy = math.max(2, py - searchWindow);
            final maxGy = math.min(h - 3, py + searchWindow);
            final minGx = math.max(2, px - searchWindow);
            final maxGx = math.min(w - 3, px + searchWindow);
            for (int cy = minGy; cy <= maxGy; cy += gridStride) {
              final cRow = cy * w;
              for (int cx = minGx; cx <= maxGx; cx += gridStride) {
                if (clean5x5[cRow + cx] == 1) {
                  evaluateCandidate(cx, cy);
                }
              }
            }
          }

          if (bestExX >= 0) {
            final eIdx = bestExY * w + bestExX;
            matchX[idx] = bestExX;
            matchY[idx] = bestExY;

            final exR = rBuf[eIdx];
            final exG = gBuf[eIdx];
            final exB = bBuf[eIdx];

            final meanExR = _patchMean(rBuf, bestExX, bestExY, w);
            final meanExG = _patchMean(gBuf, bestExX, bestExY, w);
            final meanExB = _patchMean(bBuf, bestExX, bestExY, w);

            final detailR = exR - meanExR;
            final detailG = exG - meanExG;
            final detailB = exB - meanExB;

            final gTargetR = guideR[idx];
            final gTargetG = guideG[idx];
            final gTargetB = guideB[idx];

            // Trust direct exemplar copy whenever neighborhood SSD is tight or medium;
            // only fall back to smooth illumination transfer for far-away tone shifts.
            if (bestSsd < 900.0) {
              outR[idx] = (0.90 * exR + 0.10 * (gTargetR + detailR)).clamp(0.0, 255.0);
              outG[idx] = (0.90 * exG + 0.10 * (gTargetG + detailG)).clamp(0.0, 255.0);
              outB[idx] = (0.90 * exB + 0.10 * (gTargetB + detailB)).clamp(0.0, 255.0);
            } else {
              outR[idx] = (0.55 * exR + 0.45 * (gTargetR + detailR)).clamp(0.0, 255.0);
              outG[idx] = (0.55 * exG + 0.45 * (gTargetG + detailG)).clamp(0.0, 255.0);
              outB[idx] = (0.55 * exB + 0.45 * (gTargetB + detailB)).clamp(0.0, 255.0);
            }
          }
          synthDone[idx] = 1;
        }
      }
    }

    // Soften only the outermost 1px seam transition without diluting inner textures
    final finalR = Float64List.fromList(outR);
    final finalG = Float64List.fromList(outG);
    final finalB = Float64List.fromList(outB);

    if (maxLayer >= 1) {
      for (final idx in layers[1]) {
        final x = idx % w;
        final y = idx ~/ w;
        double sr = 0, sg = 0, sb = 0;
        int cnt = 0;
        for (int dy = -1; dy <= 1; dy++) {
          final ny = y + dy;
          if (ny < 0 || ny >= h) continue;
          final nRow = ny * w;
          for (int dx = -1; dx <= 1; dx++) {
            final nx = x + dx;
            if (nx < 0 || nx >= w) continue;
            final nIdx = nRow + nx;
            sr += outR[nIdx];
            sg += outG[nIdx];
            sb += outB[nIdx];
            cnt++;
          }
        }
        if (cnt > 0) {
          finalR[idx] = 0.80 * outR[idx] + 0.20 * (sr / cnt);
          finalG[idx] = 0.80 * outG[idx] + 0.20 * (sg / cnt);
          finalB[idx] = 0.80 * outB[idx] + 0.20 * (sb / cnt);
        }
      }
    }

    return _RgbBuffers(finalR, finalG, finalB);
  }

  static bool _isClean5x5Patch(Uint8List origKnown, int cx, int cy, int w) {
    for (int dy = -2; dy <= 2; dy++) {
      final row = (cy + dy) * w;
      for (int dx = -2; dx <= 2; dx++) {
        if (origKnown[row + cx + dx] == 0) return false;
      }
    }
    return true;
  }

  static double _patchMean(Float64List buf, int cx, int cy, int w) {
    double sum = 0;
    for (int dy = -1; dy <= 1; dy++) {
      final row = (cy + dy) * w;
      sum += buf[row + cx - 1] + buf[row + cx] + buf[row + cx + 1];
    }
    return sum / 9.0;
  }

  static double _patchSsd5x5({
    required Float64List rBuf,
    required Float64List gBuf,
    required Float64List bBuf,
    required Float64List origR,
    required Float64List origG,
    required Float64List origB,
    required Uint8List origKnown,
    required Uint8List synthDone,
    required int px,
    required int py,
    required int ex,
    required int ey,
    required int w,
    required int h,
    required List<List<int>> sampleOffsets,
  }) {
    double ssd = 0.0;
    double wSum = 0.0;

    for (final off in sampleOffsets) {
      final tx = px + off[0];
      final ty = py + off[1];
      if (tx < 0 || tx >= w || ty < 0 || ty >= h) continue;

      final tIdx = ty * w + tx;
      final eIdx = (ey + off[1]) * w + (ex + off[0]);
      final double sampleW;
      if (origKnown[tIdx] == 1) {
        sampleW = 3.0;
      } else if (synthDone[tIdx] == 1) {
        sampleW = 1.6;
      } else {
        sampleW = 0.3;
      }

      final dr = rBuf[tIdx] - origR[eIdx];
      final dg = gBuf[tIdx] - origG[eIdx];
      final db = bBuf[tIdx] - origB[eIdx];
      ssd += sampleW * (dr * dr + dg * dg + db * db);
      wSum += sampleW;
    }

    if (wSum <= 0.0) return double.infinity;
    return ssd / wSum;
  }

  static bool _hasKnown8Neighbor(Uint8List known, int x, int y, int w, int h) {
    for (int dy = -1; dy <= 1; dy++) {
      final ny = y + dy;
      if (ny < 0 || ny >= h) continue;
      final row = ny * w;
      for (int dx = -1; dx <= 1; dx++) {
        if (dx == 0 && dy == 0) continue;
        final nx = x + dx;
        if (nx >= 0 && nx < w && known[row + nx] == 1) return true;
      }
    }
    return false;
  }

  static bool _hasMaskNeighbor(Uint8List mask, int x, int y, int w, int h) {
    if (x > 0 && mask[y * w + x - 1] == 1) return true;
    if (x < w - 1 && mask[y * w + x + 1] == 1) return true;
    if (y > 0 && mask[(y - 1) * w + x] == 1) return true;
    if (y < h - 1 && mask[(y + 1) * w + x] == 1) return true;
    return false;
  }
}

class _MaskBounds {
  final int minX;
  final int minY;
  final int maxX;
  final int maxY;

  const _MaskBounds(this.minX, this.minY, this.maxX, this.maxY);

  int get width => maxX - minX + 1;
  int get height => maxY - minY + 1;
}

class _RgbBuffers {
  final Float64List r;
  final Float64List g;
  final Float64List b;

  const _RgbBuffers(this.r, this.g, this.b);
}
