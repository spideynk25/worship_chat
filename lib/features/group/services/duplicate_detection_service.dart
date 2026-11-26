import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image/image.dart' as img;
import 'package:worship_chat/common/utils/media_cache_service.dart';
import 'package:worship_chat/models/group_gallery_image.dart';

enum DuplicateMatchType {
  exactUrl,
  normalizedUrl,
  exactHash,
  nearDuplicate,
}

class DuplicateItem {
  final GroupGalleryImage image;
  final DuplicateMatchType matchType;
  final double similarity; // 0.0 to 1.0
  final int hammingDistance;
  final String? groupName;

  const DuplicateItem({
    required this.image,
    required this.matchType,
    required this.similarity,
    required this.hammingDistance,
    this.groupName,
  });

  String get matchLabel {
    switch (matchType) {
      case DuplicateMatchType.exactUrl:
        return 'Exact URL (100%)';
      case DuplicateMatchType.normalizedUrl:
        return 'Exact Asset (100%)';
      case DuplicateMatchType.exactHash:
        return 'Visual Clone (100%)';
      case DuplicateMatchType.nearDuplicate:
        final pct = (similarity * 100).toStringAsFixed(0);
        return 'Near-Duplicate ($pct%)';
    }
  }

  bool get isExact =>
      matchType == DuplicateMatchType.exactUrl ||
      matchType == DuplicateMatchType.normalizedUrl ||
      matchType == DuplicateMatchType.exactHash;
}

class DuplicateCluster {
  final String clusterId;
  final GroupGalleryImage canonical;
  final List<DuplicateItem> duplicates;
  final String? canonicalGroupName;

  const DuplicateCluster({
    required this.clusterId,
    required this.canonical,
    required this.duplicates,
    this.canonicalGroupName,
  });

  int get totalImages => 1 + duplicates.length;

  double get highestSimilarity {
    if (duplicates.isEmpty) return 1.0;
    return duplicates
        .map((d) => d.similarity)
        .reduce((a, b) => a > b ? a : b);
  }

  bool get hasExactMatch => duplicates.any((d) => d.isExact);
}

enum DuplicateScanPhase {
  preparing,
  exactMatching,
  computingHashes,
  comparingHashes,
  completed,
}

class DuplicateScanProgress {
  final DuplicateScanPhase phase;
  final int current;
  final int total;
  final int clustersFound;
  final String message;

  const DuplicateScanProgress({
    required this.phase,
    required this.current,
    required this.total,
    required this.clustersFound,
    required this.message,
  });

  double get fraction => total > 0 ? (current / total).clamp(0.0, 1.0) : 0.0;
}

/// Service providing multi-level exact & perceptual near-duplicate detection
/// for Worship Chat photo galleries.
class DuplicateDetectionService {
  static final DuplicateDetectionService _instance =
      DuplicateDetectionService._internal();
  factory DuplicateDetectionService() => _instance;
  DuplicateDetectionService._internal();

  static const String _hashBoxName = 'duplicate_hashes_cache';
  static final Map<String, String> _inMemoryHashes = {};

  /// Normalizes a media URL across Cloudinary, Firebase, and CDN hosts
  /// so that transformations (e.g. w_500, c_scale, q_auto) and auth tokens
  /// resolve to the exact underlying asset identifier.
  static String normalizeUrl(String rawUrl) {
    if (rawUrl.isEmpty) return '';
    final trimmed = rawUrl.trim();

    // 1. Cloudinary URL normalization
    if (trimmed.contains('cloudinary.com') && trimmed.contains('/upload/')) {
      try {
        final uri = Uri.parse(trimmed);
        final uploadIndex = uri.pathSegments.indexOf('upload');
        if (uploadIndex != -1 && uploadIndex < uri.pathSegments.length - 1) {
          // Segments after /upload/: skip versioning (v12345) and transformations (w_500,c_scale)
          final remaining = uri.pathSegments.sublist(uploadIndex + 1);
          final cleanSegments = remaining.where((seg) {
            // Version tag e.g. v1700000000
            if (RegExp(r'^v\d+$').hasMatch(seg)) return false;
            // Transformation tags e.g. w_500, c_crop, q_auto, f_auto, etc.
            if (seg.contains(',') ||
                seg.startsWith('w_') ||
                seg.startsWith('h_') ||
                seg.startsWith('c_') ||
                seg.startsWith('q_') ||
                seg.startsWith('f_') ||
                seg.startsWith('b_') ||
                seg.startsWith('e_') ||
                seg.startsWith('r_')) {
              return false;
            }
            return true;
          }).toList();

          if (cleanSegments.isNotEmpty) {
            final publicPath = cleanSegments.join('/');
            // Strip file extension to group .jpg and .webp versions of same asset
            final dotIndex = publicPath.lastIndexOf('.');
            final assetKey = dotIndex != -1
                ? publicPath.substring(0, dotIndex)
                : publicPath;
            return 'cloudinary:$assetKey';
          }
        }
      } catch (_) {}
    }

    // 2. Firebase Storage URL normalization
    if (trimmed.contains('firebasestorage.googleapis.com')) {
      try {
        final uri = Uri.parse(trimmed);
        // Strips token and alt=media queries
        return 'firebase:${uri.path}';
      } catch (_) {}
    }

    // 3. Generic web / local URL normalization
    try {
      final uri = Uri.parse(trimmed);
      final host = uri.host;
      final path = uri.path;
      if (host.isNotEmpty) {
        return '$host$path';
      }
      return uri.path;
    } catch (_) {
      return trimmed;
    }
  }

  /// Computes a 64-bit difference hash (dHash) from raw image bytes.
  /// 1. Downscales to 9x8 pixels (72 pixels).
  /// 2. Converts to grayscale.
  /// 3. Computes 8 relative brightness bits per row = 64-bit hex hash.
  static String? computeDHashFromBytes(Uint8List bytes) {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      return computeDHashFromImage(decoded);
    } catch (e) {
      log('Error decoding image for dHash: $e');
      return null;
    }
  }

  /// Computes a 64-bit difference hash (dHash) from an [img.Image].
  static String computeDHashFromImage(img.Image image) {
    // Resize to 9 columns x 8 rows
    final resized = img.copyResize(
      image,
      width: 9,
      height: 8,
      interpolation: img.Interpolation.average,
    );
    final gray = img.grayscale(resized);

    // Build 64-bit hash (16 hex chars)
    int highBits = 0; // rows 0..3 (32 bits)
    int lowBits = 0;  // rows 4..7 (32 bits)

    for (int y = 0; y < 8; y++) {
      for (int x = 0; x < 8; x++) {
        final left = gray.getPixel(x, y).luminance;
        final right = gray.getPixel(x + 1, y).luminance;
        final bit = left > right ? 1 : 0;

        if (y < 4) {
          final shift = (y * 8) + x;
          if (bit == 1) highBits |= (1 << shift);
        } else {
          final shift = ((y - 4) * 8) + x;
          if (bit == 1) lowBits |= (1 << shift);
        }
      }
    }

    final hexHigh = highBits.toRadixString(16).padLeft(8, '0');
    final hexLow = lowBits.toRadixString(16).padLeft(8, '0');
    return '$hexHigh$hexLow';
  }

  /// Calculates the Hamming distance between two 16-character hex dHashes.
  /// Represents the number of differing bits out of 64.
  static int hammingDistance(String hashA, String hashB) {
    if (hashA.length != 16 || hashB.length != 16) return 64;
    int distance = 0;
    for (int i = 0; i < 16; i++) {
      final int valA = int.parse(hashA[i], radix: 16);
      final int valB = int.parse(hashB[i], radix: 16);
      int xor = valA ^ valB;
      while (xor > 0) {
        distance += xor & 1;
        xor >>= 1;
      }
    }
    return distance;
  }

  /// Calculates visual similarity percentage (0.0 to 1.0) from Hamming distance.
  static double similarityFromDistance(int distance) {
    return ((64 - distance) / 64.0).clamp(0.0, 1.0);
  }

  /// Returns cached dHash for an image if available from memory or Hive.
  static Future<String?> getCachedHash(String imageKey) async {
    if (_inMemoryHashes.containsKey(imageKey)) {
      return _inMemoryHashes[imageKey];
    }
    try {
      if (Hive.isBoxOpen(_hashBoxName)) {
        final box = Hive.box(_hashBoxName);
        final val = box.get(imageKey);
        if (val is String && val.length == 16) {
          _inMemoryHashes[imageKey] = val;
          return val;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Persists a computed dHash into memory and Hive.
  static Future<void> cacheHash(String imageKey, String hash) async {
    _inMemoryHashes[imageKey] = hash;
    try {
      final box = Hive.isBoxOpen(_hashBoxName)
          ? Hive.box(_hashBoxName)
          : await Hive.openBox(_hashBoxName);
      await box.put(imageKey, hash);
    } catch (_) {}
  }

  /// Loads image bytes from local disk cache, file, or network download.
  static Future<Uint8List?> getImageBytes(String url) async {
    if (url.isEmpty) return null;

    // 1. Check if it's already a local file path
    final clean = url.startsWith('file://') ? url.replaceFirst('file://', '') : url;
    if (!clean.startsWith('http://') && !clean.startsWith('https://')) {
      final file = File(clean);
      if (file.existsSync()) {
        try {
          return await file.readAsBytes();
        } catch (_) {}
      }
    }

    // 2. Check MediaCacheService
    try {
      final cachedPath = MediaCacheService().getCachedSync(url);
      if (cachedPath != null) {
        final f = File(cachedPath);
        if (f.existsSync()) {
          return await f.readAsBytes();
        }
      }

      // Download if not in cache
      final path = await MediaCacheService().getMediaPath(url);
      if (path != null) {
        final f = File(path);
        if (f.existsSync()) {
          return await f.readAsBytes();
        }
      }
    } catch (e) {
      log('Error getting image bytes for hash: $e');
    }
    return null;
  }

  /// Main detection scan across a list of [GroupGalleryImage] items.
  /// Supports both fast URL-based clustering and deep perceptual visual dHash matching.
  ///
  /// [minSimilarity]: Minimum similarity threshold for near-duplicates (default: 0.88, distance <= 7).
  /// [maxHammingDistance]: Maximum differing bits to consider near-duplicate (default: 6, ~90.6% similarity).
  /// [deepPerceptualScan]: Whether to compute perceptual hashes for non-exact images.
  /// [groupNames]: Optional mapping of groupId -> groupName for display context.
  static Future<List<DuplicateCluster>> scanForDuplicates({
    required List<GroupGalleryImage> images,
    double minSimilarity = 0.88,
    int maxHammingDistance = 6,
    bool deepPerceptualScan = true,
    Map<String, String>? groupNames,
    void Function(DuplicateScanProgress)? onProgress,
  }) async {
    final photoImages = images.where((m) => m.isImage).toList();
    if (photoImages.length < 2) {
      onProgress?.call(const DuplicateScanProgress(
        phase: DuplicateScanPhase.completed,
        current: 0,
        total: 0,
        clustersFound: 0,
        message: 'No images to scan.',
      ));
      return [];
    }

    onProgress?.call(DuplicateScanProgress(
      phase: DuplicateScanPhase.preparing,
      current: 0,
      total: photoImages.length,
      clustersFound: 0,
      message: 'Analyzing ${photoImages.length} images...',
    ));

    final Map<String, DuplicateCluster> clustersMap = {};
    final Set<String> assignedImageIds = {};

    // ── Phase 1: Fast Exact Match by Normalized URL ─────────────────────────
    onProgress?.call(DuplicateScanProgress(
      phase: DuplicateScanPhase.exactMatching,
      current: 0,
      total: photoImages.length,
      clustersFound: 0,
      message: 'Checking exact and CDN asset matches...',
    ));

    final Map<String, List<GroupGalleryImage>> normalizedBuckets = {};
    for (final img in photoImages) {
      final key = normalizeUrl(img.imageUrl);
      normalizedBuckets.putIfAbsent(key, () => []).add(img);
    }

    int exactClusterIndex = 0;
    final List<GroupGalleryImage> remainingUnmatched = [];

    for (final entry in normalizedBuckets.entries) {
      final bucket = entry.value;
      if (bucket.length > 1) {
        // Pick canonical (earliest uploadedAt)
        bucket.sort((a, b) => a.uploadedAt.compareTo(b.uploadedAt));
        final canonical = bucket.first;
        final duplicates = <DuplicateItem>[];

        for (int i = 1; i < bucket.length; i++) {
          final dupImg = bucket[i];
          final isSameUrl = dupImg.imageUrl == canonical.imageUrl;
          duplicates.add(DuplicateItem(
            image: dupImg,
            matchType: isSameUrl
                ? DuplicateMatchType.exactUrl
                : DuplicateMatchType.normalizedUrl,
            similarity: 1.0,
            hammingDistance: 0,
            groupName: groupNames?[dupImg.groupId],
          ));
          assignedImageIds.add(dupImg.imageId);
        }

        assignedImageIds.add(canonical.imageId);
        exactClusterIndex++;
        final clusterId = 'cluster_exact_$exactClusterIndex';
        clustersMap[clusterId] = DuplicateCluster(
          clusterId: clusterId,
          canonical: canonical,
          duplicates: duplicates,
          canonicalGroupName: groupNames?[canonical.groupId],
        );
      } else {
        remainingUnmatched.add(bucket.first);
      }
    }

    log('⚡ [Duplicate Finder] Phase 1 found ${clustersMap.length} exact clusters');

    // If deep perceptual scan is disabled or less than 2 unmatched images remain, finish
    if (!deepPerceptualScan || remainingUnmatched.length < 2) {
      final results = clustersMap.values.toList()
        ..sort((a, b) => b.totalImages.compareTo(a.totalImages));
      onProgress?.call(DuplicateScanProgress(
        phase: DuplicateScanPhase.completed,
        current: photoImages.length,
        total: photoImages.length,
        clustersFound: results.length,
        message: 'Scan complete! Found ${results.length} duplicate groups.',
      ));
      return results;
    }

    // ── Phase 2: Compute Perceptual Difference Hashes (dHash) ───────────────
    final Map<String, String> imageHashes = {};
    int hashedCount = 0;
    final int totalUnmatched = remainingUnmatched.length;

    DateTime lastProgressNotify = DateTime.now();

    void notifyProgress(int current, {bool force = false}) {
      final now = DateTime.now();
      if (force ||
          now.difference(lastProgressNotify).inMilliseconds >= 80 ||
          current == totalUnmatched) {
        lastProgressNotify = now;
        onProgress?.call(DuplicateScanProgress(
          phase: DuplicateScanPhase.computingHashes,
          current: current,
          total: totalUnmatched,
          clustersFound: clustersMap.length,
          message:
              'Calculating perceptual hashes ($current/$totalUnmatched)...',
        ));
      }
    }

    notifyProgress(0, force: true);

    // Parallel worker pool to compute hashes across CPU cores in background isolates
    const int concurrency = 4;
    int nextIndex = 0;

    Future<void> worker() async {
      while (true) {
        if (nextIndex >= remainingUnmatched.length) break;
        final imgItem = remainingUnmatched[nextIndex++];

        final imageKey = imgItem.imageId.isNotEmpty
            ? imgItem.imageId
            : md5.convert(utf8.encode(imgItem.imageUrl)).toString();

        String? hash = await getCachedHash(imageKey);
        if (hash == null) {
          final bytes = await getImageBytes(imgItem.imageUrl);
          if (bytes != null && bytes.isNotEmpty) {
            hash = await compute(computeDHashFromBytes, bytes);
            if (hash != null) {
              await cacheHash(imageKey, hash);
            }
          }
        }

        if (hash != null) {
          imageHashes[imgItem.imageId] = hash;
        }

        hashedCount++;
        notifyProgress(hashedCount);
      }
    }

    final workers = List.generate(
      concurrency.clamp(1, remainingUnmatched.length),
      (_) => worker(),
    );
    await Future.wait(workers);

    notifyProgress(hashedCount, force: true);

    // ── Phase 3: Pairwise Hamming Distance Comparison ───────────────────────
    final candidateImages = remainingUnmatched
        .where((img) => imageHashes.containsKey(img.imageId))
        .toList();

    onProgress?.call(DuplicateScanProgress(
      phase: DuplicateScanPhase.comparingHashes,
      current: 0,
      total: candidateImages.length,
      clustersFound: clustersMap.length,
      message: 'Comparing visual similarity across images...',
    ));

    int nearClusterIndex = 0;
    final Set<String> processedNearIds = {};

    for (int i = 0; i < candidateImages.length; i++) {
      final imgA = candidateImages[i];
      if (processedNearIds.contains(imgA.imageId)) continue;

      final hashA = imageHashes[imgA.imageId]!;
      final List<DuplicateItem> nearDuplicates = [];

      for (int j = i + 1; j < candidateImages.length; j++) {
        final imgB = candidateImages[j];
        if (processedNearIds.contains(imgB.imageId)) continue;

        final hashB = imageHashes[imgB.imageId]!;
        final distance = hammingDistance(hashA, hashB);
        final sim = similarityFromDistance(distance);

        if (distance <= maxHammingDistance && sim >= minSimilarity) {
          final isExactHash = distance == 0;
          nearDuplicates.add(DuplicateItem(
            image: imgB,
            matchType: isExactHash
                ? DuplicateMatchType.exactHash
                : DuplicateMatchType.nearDuplicate,
            similarity: sim,
            hammingDistance: distance,
            groupName: groupNames?[imgB.groupId],
          ));
          processedNearIds.add(imgB.imageId);
        }
      }

      if (nearDuplicates.isNotEmpty) {
        processedNearIds.add(imgA.imageId);
        nearClusterIndex++;
        final clusterId = 'cluster_near_$nearClusterIndex';
        clustersMap[clusterId] = DuplicateCluster(
          clusterId: clusterId,
          canonical: imgA,
          duplicates: nearDuplicates,
          canonicalGroupName: groupNames?[imgA.groupId],
        );
      }
    }

    final finalResults = clustersMap.values.toList()
      ..sort((a, b) {
        // Sort by total duplicate count first, then by highest similarity
        final countCompare = b.totalImages.compareTo(a.totalImages);
        if (countCompare != 0) return countCompare;
        return b.highestSimilarity.compareTo(a.highestSimilarity);
      });

    onProgress?.call(DuplicateScanProgress(
      phase: DuplicateScanPhase.completed,
      current: photoImages.length,
      total: photoImages.length,
      clustersFound: finalResults.length,
      message: 'Done! Found ${finalResults.length} duplicate groups.',
    ));

    return finalResults;
  }

  /// Checks if a local file being uploaded already exists in target gallery images
  /// by comparing file hash (MD5) or perceptual dHash.
  static Future<GroupGalleryImage?> findDuplicateForLocalFile({
    required File file,
    required List<GroupGalleryImage> existingImages,
  }) async {
    if (!file.existsSync() || existingImages.isEmpty) return null;

    try {
      final bytes = await file.readAsBytes();
      final localDHash = computeDHashFromBytes(bytes);
      if (localDHash == null) return null;

      for (final existing in existingImages) {
        if (!existing.isImage) continue;

        // Check if existing image is cached locally and has identical dHash
        final imageKey = existing.imageId.isNotEmpty
            ? existing.imageId
            : md5.convert(utf8.encode(existing.imageUrl)).toString();

        final cachedHash = await getCachedHash(imageKey);
        if (cachedHash != null) {
          final distance = hammingDistance(localDHash, cachedHash);
          if (distance <= 2) {
            // Highly identical duplicate found
            return existing;
          }
        }
      }
    } catch (e) {
      log('Error checking local file for duplicate: $e');
    }
    return null;
  }
}
