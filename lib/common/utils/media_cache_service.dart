import 'dart:developer';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

class MediaCacheService {
  static final MediaCacheService _instance = MediaCacheService._internal();
  factory MediaCacheService() => _instance;
  MediaCacheService._internal();

  final Dio _dio = Dio();
  String? _cacheDir;
  final Map<String, String> _memoryCache = {};

  // Initialize cache directory
  Future<void> init() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      _cacheDir = '${appDir.path}/media_cache';
      final dir = Directory(_cacheDir!);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      log('Media cache directory initialized: $_cacheDir');
    } catch (e) {
      log('Error initializing cache directory: $e');
    }
  }

  /// Associate a remote URL with an already existing local file (e.g. freshly uploaded image/video).
  /// This prevents any re-downloading or flickering when transitioning from optimistic local path to remote URL.
  void registerLocalMapping(String url, String localPath) {
    if (url.isNotEmpty && localPath.isNotEmpty) {
      _memoryCache[url] = localPath;
    }
  }

  /// Synchronously get cached media path if available in memory or immediately on disk.
  /// Returns null if not cached yet.
  String? getCachedSync(String url) {
    if (url.isEmpty) return null;
    // Reject file:// scheme URIs — they are not valid remote URLs or plain paths
    if (url.startsWith('file://')) return null;
    if (_memoryCache.containsKey(url)) {
      return _memoryCache[url];
    }
    // If it's already a local file path
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      if (File(url).existsSync()) {
        _memoryCache[url] = url;
        return url;
      }
    }
    // Check if already in disk cache without async
    if (_cacheDir != null) {
      final fileName = _getFileNameFromUrl(url);
      final diskFile = File('$_cacheDir/$fileName');
      if (diskFile.existsSync() && diskFile.lengthSync() > 0) {
        final path = diskFile.path;
        _memoryCache[url] = path;
        return path;
      }
    }
    return null;
  }

  // Generate unique filename from URL safely without path traversal
  String _getFileNameFromUrl(String url) {
    final bytes = utf8.encode(url);
    final hash = md5.convert(bytes).toString();
    String extension = 'jpg';
    try {
      final uri = Uri.parse(url);
      final lastSegment = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
      if (lastSegment.contains('.')) {
        final ext = lastSegment.split('.').last.toLowerCase();
        if (RegExp(r'^[a-z0-9]{2,5}$').hasMatch(ext)) {
          extension = ext;
        }
      }
    } catch (_) {}
    return '$hash.$extension';
  }

  // Get local file path
  Future<String> _getLocalFilePath(String url) async {
    if (_cacheDir == null) await init();
    final fileName = _getFileNameFromUrl(url);
    return '$_cacheDir/$fileName';
  }

  // Check if file exists in cache
  Future<bool> isCached(String url) async {
    if (getCachedSync(url) != null) return true;
    try {
      final localPath = await _getLocalFilePath(url);
      final file = File(localPath);
      final exists = await file.exists();
      if (exists && (await file.length()) > 0) {
        _memoryCache[url] = localPath;
        return true;
      }
      return false;
    } catch (e) {
      log('Error checking cache: $e');
      return false;
    }
  }

  // Get cached file path or download if not cached
  Future<String?> getMediaPath(String url) async {
    if (url.isEmpty) return null;
    // Reject file:// scheme URIs — they are not valid remote or plain file paths
    if (url.startsWith('file://')) return null;

    // Check fast memory cache or local file first
    final fastSync = getCachedSync(url);
    if (fastSync != null) {
      return fastSync;
    }

    // If it's a local file path that exists on device
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      final localFile = File(url);
      if (await localFile.exists()) {
        _memoryCache[url] = url;
        return url;
      }
      return null;
    }

    try {
      final localPath = await _getLocalFilePath(url);
      final file = File(localPath);

      // If file exists and is valid, return local path
      if (await file.exists() && (await file.length()) > 0) {
        _memoryCache[url] = localPath;
        log('Media found in cache: $localPath');
        return localPath;
      }

      // Ensure directory exists
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }

      // Download file with reasonable timeouts
      log('Downloading media: $url');
      await _dio.download(
        url,
        localPath,
        options: Options(
          receiveTimeout: const Duration(seconds: 20),
          sendTimeout: const Duration(seconds: 15),
        ),
        onReceiveProgress: (received, total) {
          if (total != -1) {
            final progress = (received / total * 100).toStringAsFixed(0);
            log('Download progress: $progress%');
          }
        },
      );

      if (await file.exists() && (await file.length()) > 0) {
        _memoryCache[url] = localPath;
        log('Media downloaded successfully: $localPath');
        return localPath;
      } else {
        if (await file.exists()) {
          await file.delete();
        }
        return null;
      }
    } catch (e) {
      log('Error downloading media: $e');
      return null;
    }
  }

  // Clear all cached media
  Future<void> clearCache() async {
    try {
      if (_cacheDir == null) await init();
      final dir = Directory(_cacheDir!);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        await dir.create();
        log('Cache cleared successfully');
      }
    } catch (e) {
      log('Error clearing cache: $e');
    }
  }

  // Get cache size
  Future<int> getCacheSize() async {
    try {
      if (_cacheDir == null) await init();
      final dir = Directory(_cacheDir!);
      if (!await dir.exists()) return 0;

      int totalSize = 0;
      await for (var entity in dir.list(recursive: true)) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }
      return totalSize;
    } catch (e) {
      log('Error getting cache size: $e');
      return 0;
    }
  }

  // Delete specific cached file
  Future<void> deleteCachedFile(String url) async {
    try {
      final localPath = await _getLocalFilePath(url);
      final file = File(localPath);
      if (await file.exists()) {
        await file.delete();
        log('Deleted cached file: $localPath');
      }
    } catch (e) {
      log('Error deleting cached file: $e');
    }
  }
}