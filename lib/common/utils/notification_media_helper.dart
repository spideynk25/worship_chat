import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Resolved local file handles attached to a system notification.
class NotificationMediaAssets {
  final File? primaryAvatarFile;
  final File? senderAvatarFile;
  final File? mediaPreviewFile;

  const NotificationMediaAssets({
    this.primaryAvatarFile,
    this.senderAvatarFile,
    this.mediaPreviewFile,
  });
}

/// Downloads, transforms, circular-crops, and caches notification images and
/// sender/group avatars so local notifications render WhatsApp-style previews
/// without stalling on slow networks.
class NotificationMediaHelper {
  NotificationMediaHelper._();

  static const Duration defaultPreviewTimeout = Duration(seconds: 4);
  static const Duration defaultAvatarTimeout = Duration(seconds: 3);
  static const int _maxCachedFiles = 80;
  static const Duration _avatarCacheTtl = Duration(hours: 24);
  static const Duration _previewCacheTtl = Duration(days: 7);

  /// Normalizes `http://` image URLs to `https://`. Returns `null` if blank or
  /// not an HTTP(S) URL.
  static String? normalizeHttpUrl(String? rawUrl) {
    if (rawUrl == null) return null;
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('https://')) return trimmed;
    if (trimmed.startsWith('http://')) {
      return 'https://${trimmed.substring(7)}';
    }
    return null;
  }

  /// Extracts a clean HTTPS image URL from raw `fileMessageData`, supporting
  /// plain URLs and grouped-media JSON objects (`{"url": ..., "groupId": ...}`).
  static String? extractMediaUrl(String? rawFileData) {
    if (rawFileData == null) return null;
    final trimmed = rawFileData.trim();
    if (trimmed.isEmpty) return null;

    if (trimmed.startsWith('{')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map) {
          final candidate = decoded['url'] ?? decoded['secure_url'];
          if (candidate is String) {
            return normalizeHttpUrl(candidate);
          }
        }
      } catch (_) {
        return null;
      }
      return null;
    }

    return normalizeHttpUrl(trimmed);
  }

  /// Returns `true` when [messageType] represents a visual photo/GIF preview.
  static bool supportsPhotoPreview({
    required String? messageType,
    required String? notificationType,
    String? rawFileData,
    String? statusUrl,
  }) {
    final normalizedMsgType = (messageType ?? '').trim().toLowerCase();
    if (normalizedMsgType == 'image' || normalizedMsgType == 'gif') {
      return extractMediaUrl(rawFileData) != null;
    }
    if ((notificationType ?? '').trim().toLowerCase() == 'story') {
      final storyMedia = extractMediaUrl(rawFileData) ?? normalizeHttpUrl(statusUrl);
      return storyMedia != null && normalizedMsgType != 'video';
    }
    return false;
  }

  /// Rewrites Cloudinary `/image/upload/` URLs to fetch a lightweight preview
  /// sized for mobile notifications (converting GIFs to first-frame JPEG).
  static String buildPreviewUrl(
    String url, {
    int maxWidth = 900,
    bool isGif = false,
  }) {
    final clean = normalizeHttpUrl(url) ?? url.trim();
    const marker = '/image/upload/';
    final markerIdx = clean.indexOf(marker);
    if (markerIdx == -1) return clean;

    final prefix = clean.substring(0, markerIdx + marker.length);
    final rest = clean.substring(markerIdx + marker.length);
    if (rest.isEmpty) return clean;

    // Avoid duplicating transforms when URL already begins with a transform block.
    final firstSegment = rest.split('/').first;
    final hasExplicitTransform = firstSegment.contains(',') ||
        RegExp(r'^(w|h|c|f|q|g|e|t)_').hasMatch(firstSegment);
    if (hasExplicitTransform) {
      return clean;
    }

    final transform = isGif
        ? 'w_$maxWidth,c_limit,q_auto,f_jpg,pg_1'
        : 'w_$maxWidth,c_limit,q_auto,f_jpg';
    return '$prefix$transform/$rest';
  }

  /// Rewrites Cloudinary `/image/upload/` avatar URLs for compact square crops.
  static String buildAvatarUrl(String url, {int sizePx = 256}) {
    final clean = normalizeHttpUrl(url) ?? url.trim();
    const marker = '/image/upload/';
    final markerIdx = clean.indexOf(marker);
    if (markerIdx == -1) return clean;

    final prefix = clean.substring(0, markerIdx + marker.length);
    final rest = clean.substring(markerIdx + marker.length);
    if (rest.isEmpty) return clean;

    final firstSegment = rest.split('/').first;
    final hasExplicitTransform = firstSegment.contains(',') ||
        RegExp(r'^(w|h|c|f|q|g|e|t)_').hasMatch(firstSegment);
    if (hasExplicitTransform) {
      return clean;
    }

    return '${prefix}w_$sizePx,h_$sizePx,c_fill,g_face,q_auto,f_png/$rest';
  }

  static Future<Directory> _resolveCacheDir(Directory? override) async {
    if (override != null) {
      if (!override.existsSync()) {
        await override.create(recursive: true);
      }
      return override;
    }
    final tempDir = await getTemporaryDirectory();
    final dir = Directory(p.join(tempDir.path, 'notif_media'));
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static String _hashKey(String key) {
    return sha1.convert(utf8.encode(key)).toString();
  }

  static Dio _createDio(Dio? override, Duration timeout) {
    if (override != null) return override;
    return Dio(
      BaseOptions(
        connectTimeout: timeout,
        receiveTimeout: timeout,
        sendTimeout: timeout,
        responseType: ResponseType.bytes,
      ),
    );
  }

  static bool _isJpeg(Uint8List bytes) {
    return bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF;
  }

  static bool _isPng(Uint8List bytes) {
    return bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47;
  }

  /// Downloads and caches a notification photo preview file. Returns `null` on
  /// invalid URLs, unsupported bytes, or network errors/timeouts.
  static Future<File?> downloadPreviewImage({
    required String url,
    bool isGif = false,
    Dio? dioOverride,
    Directory? cacheDirOverride,
    Duration timeout = defaultPreviewTimeout,
  }) async {
    try {
      final cleanUrl = extractMediaUrl(url) ?? normalizeHttpUrl(url);
      if (cleanUrl == null) return null;

      final cacheDir = await _resolveCacheDir(cacheDirOverride);
      final fetchUrl = buildPreviewUrl(cleanUrl, isGif: isGif);
      final hash = _hashKey('preview:${isGif ? "gif" : "img"}:$cleanUrl');

      for (final ext in const ['jpg', 'png']) {
        final existing = File(p.join(cacheDir.path, 'preview_$hash.$ext'));
        if (existing.existsSync() && existing.lengthSync() > 0) {
          final age = DateTime.now().difference(existing.lastModifiedSync());
          if (age < _previewCacheTtl) {
            return existing;
          }
        }
      }

      final dio = _createDio(dioOverride, timeout);
      final response = await dio.get<List<int>>(
        fetchUrl,
        options: Options(responseType: ResponseType.bytes),
      );
      final rawBytes = response.data;
      if (rawBytes == null || rawBytes.isEmpty) return null;

      final bytes = Uint8List.fromList(rawBytes);

      // Fast path for already compact JPEG/PNG payloads returned by CDN.
      if (_isJpeg(bytes) && bytes.length <= 1500 * 1024) {
        final outFile = File(p.join(cacheDir.path, 'preview_$hash.jpg'));
        await outFile.writeAsBytes(bytes, flush: true);
        await _pruneCacheDir(cacheDir);
        return outFile;
      }
      if (_isPng(bytes) && bytes.length <= 1500 * 1024) {
        final outFile = File(p.join(cacheDir.path, 'preview_$hash.png'));
        await outFile.writeAsBytes(bytes, flush: true);
        await _pruneCacheDir(cacheDir);
        return outFile;
      }

      // Normalize WebP / GIF / oversized bitmaps into a compact JPEG for OEMs & iOS.
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      final resized = decoded.width > 900
          ? img.copyResize(
              decoded,
              width: 900,
              interpolation: img.Interpolation.linear,
            )
          : decoded;
      final encoded = img.encodeJpg(resized, quality: 85);
      final outFile = File(p.join(cacheDir.path, 'preview_$hash.jpg'));
      await outFile.writeAsBytes(encoded, flush: true);
      await _pruneCacheDir(cacheDir);
      return outFile;
    } catch (e) {
      log('⚠️ NotificationMediaHelper.downloadPreviewImage skipped: $e');
      return null;
    }
  }

  /// Downloads an avatar URL, center-crops it to a square, applies an
  /// anti-aliased circular alpha mask, and caches the resulting PNG.
  static Future<File?> downloadCircularAvatar({
    required String url,
    int sizePx = 192,
    Dio? dioOverride,
    Directory? cacheDirOverride,
    Duration timeout = defaultAvatarTimeout,
  }) async {
    try {
      final cleanUrl = normalizeHttpUrl(url);
      if (cleanUrl == null) return null;

      final cacheDir = await _resolveCacheDir(cacheDirOverride);
      final hash = _hashKey('avatar:$cleanUrl');
      final cacheFile =
          File(p.join(cacheDir.path, 'avatar_${hash}_$sizePx.png'));

      if (cacheFile.existsSync() && cacheFile.lengthSync() > 0) {
        final age = DateTime.now().difference(cacheFile.lastModifiedSync());
        if (age < _avatarCacheTtl) {
          return cacheFile;
        }
      }

      final dio = _createDio(dioOverride, timeout);
      final fetchUrl = buildAvatarUrl(cleanUrl);
      List<int>? rawBytes;

      try {
        final response = await dio.get<List<int>>(
          fetchUrl,
          options: Options(responseType: ResponseType.bytes),
        );
        rawBytes = response.data;
      } catch (_) {
        // Retry once with the untransformed original URL if CDN rejects crop args.
        if (fetchUrl != cleanUrl) {
          final fallback = await dio.get<List<int>>(
            cleanUrl,
            options: Options(responseType: ResponseType.bytes),
          );
          rawBytes = fallback.data;
        }
      }

      if (rawBytes == null || rawBytes.isEmpty) return null;

      final decoded = img.decodeImage(Uint8List.fromList(rawBytes));
      if (decoded == null) return null;

      final minDim = math.min(decoded.width, decoded.height);
      final cropX = (decoded.width - minDim) ~/ 2;
      final cropY = (decoded.height - minDim) ~/ 2;
      final square = (decoded.width == minDim && decoded.height == minDim)
          ? decoded
          : img.copyCrop(
              decoded,
              x: cropX,
              y: cropY,
              width: minDim,
              height: minDim,
            );

      final resized = (square.width == sizePx && square.height == sizePx)
          ? square
          : img.copyResize(
              square,
              width: sizePx,
              height: sizePx,
              interpolation: img.Interpolation.linear,
            );

      final circular = _maskCircle(resized, sizePx);
      final pngBytes = img.encodePng(circular);
      await cacheFile.writeAsBytes(pngBytes, flush: true);
      await _pruneCacheDir(cacheDir);
      return cacheFile;
    } catch (e) {
      log('⚠️ NotificationMediaHelper.downloadCircularAvatar skipped: $e');
      return null;
    }
  }

  static img.Image _maskCircle(img.Image source, int sizePx) {
    final out = img.Image(width: sizePx, height: sizePx, numChannels: 4);
    final radius = sizePx / 2.0;
    final center = radius - 0.5;

    for (int y = 0; y < sizePx; y++) {
      for (int x = 0; x < sizePx; x++) {
        final dx = x - center;
        final dy = y - center;
        final dist = math.sqrt(dx * dx + dy * dy);
        if (dist <= radius) {
          final pixel = source.getPixel(x, y);
          final edgeAlpha =
              dist > radius - 1.0 ? (radius - dist).clamp(0.0, 1.0) : 1.0;
          final alpha =
              (pixel.aNormalized * edgeAlpha * 255).round().clamp(0, 255);
          out.setPixelRgba(
            x,
            y,
            pixel.r.toInt().clamp(0, 255),
            pixel.g.toInt().clamp(0, 255),
            pixel.b.toInt().clamp(0, 255),
            alpha,
          );
        } else {
          out.setPixelRgba(x, y, 0, 0, 0, 0);
        }
      }
    }
    return out;
  }

  static Future<void> _pruneCacheDir(Directory dir) async {
    try {
      final entities = dir.listSync().whereType<File>().toList();
      if (entities.length <= _maxCachedFiles) return;
      entities.sort(
        (a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()),
      );
      final toDelete = entities.length - _maxCachedFiles;
      for (int i = 0; i < toDelete; i++) {
        await entities[i].delete();
      }
    } catch (_) {}
  }

  /// Resolves the best available group icon URL from payload, local Hive cache,
  /// or Firestore (with a short network timeout).
  static Future<String?> resolveGroupAvatarUrl({
    String? directGroupPic,
    String? groupId,
    FirebaseFirestore? firestoreOverride,
  }) async {
    final fromPayload = normalizeHttpUrl(directGroupPic);
    if (fromPayload != null) return fromPayload;

    if (groupId == null || groupId.isEmpty) return null;

    try {
      if (Hive.isBoxOpen('groups_cache')) {
        final box = Hive.box('groups_cache');
        final direct = box.get(groupId);
        if (direct is Map) {
          final fromHive = normalizeHttpUrl(direct['groupPic']?.toString());
          if (fromHive != null) return fromHive;
        }
        for (final key in box.keys) {
          final entry = box.get(key);
          if (entry is Map && entry['groupId']?.toString() == groupId) {
            final fromHive = normalizeHttpUrl(entry['groupPic']?.toString());
            if (fromHive != null) return fromHive;
          } else if (entry is List) {
            for (final item in entry) {
              if (item is Map && item['groupId']?.toString() == groupId) {
                final fromHive =
                    normalizeHttpUrl(item['groupPic']?.toString());
                if (fromHive != null) return fromHive;
              }
            }
          }
        }
      }
    } catch (_) {}

    try {
      final fs = firestoreOverride ?? FirebaseFirestore.instance;
      final doc = await fs
          .collection('groups')
          .doc(groupId)
          .get()
          .timeout(const Duration(seconds: 2));
      if (doc.exists && doc.data() != null) {
        return normalizeHttpUrl(doc.data()!['groupPic']?.toString());
      }
    } catch (_) {}

    return null;
  }

  /// Resolves a user's profile picture URL from payload, local Hive contact
  /// cache, or Firestore (with a short network timeout).
  static Future<String?> resolveUserAvatarUrl({
    String? directProfilePic,
    String? uid,
    FirebaseFirestore? firestoreOverride,
  }) async {
    final fromPayload = normalizeHttpUrl(directProfilePic);
    if (fromPayload != null) return fromPayload;

    if (uid == null || uid.isEmpty) return null;

    try {
      if (Hive.isBoxOpen('contacts_cache')) {
        final box = Hive.box('contacts_cache');
        final byKey = box.get(uid);
        if (byKey is Map) {
          final fromHive = normalizeHttpUrl(byKey['profilePic']?.toString());
          if (fromHive != null) return fromHive;
        }
        for (final value in box.values) {
          if (value is Map && value['uid']?.toString() == uid) {
            final fromHive =
                normalizeHttpUrl(value['profilePic']?.toString());
            if (fromHive != null) return fromHive;
          } else if (value is List) {
            for (final item in value) {
              if (item is Map && item['uid']?.toString() == uid) {
                final fromHive =
                    normalizeHttpUrl(item['profilePic']?.toString());
                if (fromHive != null) return fromHive;
              }
            }
          }
        }
      }
    } catch (_) {}

    try {
      final fs = firestoreOverride ?? FirebaseFirestore.instance;
      final doc = await fs
          .collection('users')
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 2));
      if (doc.exists && doc.data() != null) {
        return normalizeHttpUrl(doc.data()!['profilePic']?.toString());
      }
    } catch (_) {}

    return null;
  }

  /// Downloads local bitmap files for a notification in parallel so slow links
  /// add at most a single bounded wait.
  static Future<NotificationMediaAssets> fetchNotificationAssets({
    String? primaryAvatarUrl,
    String? senderAvatarUrl,
    String? mediaPreviewUrl,
    bool isGif = false,
    Dio? dioOverride,
    Directory? cacheDirOverride,
  }) async {
    final cleanPrimary = normalizeHttpUrl(primaryAvatarUrl);
    final cleanSender = normalizeHttpUrl(senderAvatarUrl);
    final cleanMedia = extractMediaUrl(mediaPreviewUrl);

    final sameAvatar = cleanPrimary != null && cleanPrimary == cleanSender;

    final primaryFuture = cleanPrimary != null
        ? downloadCircularAvatar(
            url: cleanPrimary,
            dioOverride: dioOverride,
            cacheDirOverride: cacheDirOverride,
          )
        : Future<File?>.value(null);

    final senderFuture = sameAvatar
        ? primaryFuture
        : (cleanSender != null
            ? downloadCircularAvatar(
                url: cleanSender,
                dioOverride: dioOverride,
                cacheDirOverride: cacheDirOverride,
              )
            : Future<File?>.value(null));

    final mediaFuture = cleanMedia != null
        ? downloadPreviewImage(
            url: cleanMedia,
            isGif: isGif,
            dioOverride: dioOverride,
            cacheDirOverride: cacheDirOverride,
          )
        : Future<File?>.value(null);

    final results = await Future.wait<File?>([
      primaryFuture,
      senderFuture,
      mediaFuture,
    ]);

    return NotificationMediaAssets(
      primaryAvatarFile: results[0],
      senderAvatarFile: results[1],
      mediaPreviewFile: results[2],
    );
  }
}
