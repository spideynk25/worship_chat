import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worship_chat/common/utils/media_cache_service.dart';
import 'package:worship_chat/common/utils/utils.dart';

/// Input descriptor for pinning or syncing an image into the Home Screen Widget.
class HomeWidgetPhotoInput {
  final String id;
  final String? imageUrl;
  final String? localPath;
  final String title;
  final String subtitle;

  const HomeWidgetPhotoInput({
    required this.id,
    this.imageUrl,
    this.localPath,
    this.title = '',
    this.subtitle = '',
  });
}

/// Persisted photo entry cached on-disk for the Android Home Screen Widget.
class HomeWidgetPhoto {
  final String id;
  final String localPath;
  final String sourceUrl;
  final String title;
  final String subtitle;

  const HomeWidgetPhoto({
    required this.id,
    required this.localPath,
    this.sourceUrl = '',
    this.title = '',
    this.subtitle = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'path': localPath,
        'url': sourceUrl,
        'title': title,
        'subtitle': subtitle,
      };

  static HomeWidgetPhoto? fromJson(Map<String, dynamic>? map) {
    if (map == null) return null;
    final path = map['path']?.toString().trim() ?? '';
    if (path.isEmpty) return null;
    final rawId = map['id']?.toString().trim() ?? '';
    return HomeWidgetPhoto(
      id: rawId.isNotEmpty ? rawId : path,
      localPath: path,
      sourceUrl: map['url']?.toString().trim() ?? '',
      title: map['title']?.toString().trim() ?? '',
      subtitle: map['subtitle']?.toString().trim() ?? '',
    );
  }
}

/// Persisted configuration for the Android Home Screen Photo Widget.
class HomeWidgetConfig {
  final List<HomeWidgetPhoto> photos;
  final int currentIndex;
  final bool showTitle;
  final int intervalMinutes;
  final String sourceLabel;

  const HomeWidgetConfig({
    this.photos = const [],
    this.currentIndex = 0,
    this.showTitle = true,
    this.intervalMinutes = 60,
    this.sourceLabel = 'Custom Pins',
  });

  HomeWidgetConfig copyWith({
    List<HomeWidgetPhoto>? photos,
    int? currentIndex,
    bool? showTitle,
    int? intervalMinutes,
    String? sourceLabel,
  }) {
    final nextPhotos = photos ?? this.photos;
    final rawIndex = currentIndex ?? this.currentIndex;
    final safeIndex = nextPhotos.isEmpty
        ? 0
        : ((rawIndex % nextPhotos.length) + nextPhotos.length) %
              nextPhotos.length;

    return HomeWidgetConfig(
      photos: nextPhotos,
      currentIndex: safeIndex,
      showTitle: showTitle ?? this.showTitle,
      intervalMinutes: intervalMinutes ?? this.intervalMinutes,
      sourceLabel: sourceLabel ?? this.sourceLabel,
    );
  }

  String toJsonString() => jsonEncode({
        'photos': photos.map((p) => p.toJson()).toList(),
        'currentIndex': currentIndex,
        'showTitle': showTitle,
        'intervalMinutes': intervalMinutes,
        'sourceLabel': sourceLabel,
      });

  static HomeWidgetConfig fromJsonString(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const HomeWidgetConfig();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const HomeWidgetConfig();
      final map = Map<String, dynamic>.from(decoded);
      final rawList = map['photos'];
      final photos = <HomeWidgetPhoto>[];
      if (rawList is List) {
        for (final item in rawList) {
          if (item is Map) {
            final parsed = HomeWidgetPhoto.fromJson(
              Map<String, dynamic>.from(item),
            );
            if (parsed != null) photos.add(parsed);
          }
        }
      }
      final rawIdx = (map['currentIndex'] as num?)?.toInt() ?? 0;
      final safeIdx = photos.isEmpty ? 0 : rawIdx.clamp(0, photos.length - 1);
      return HomeWidgetConfig(
        photos: photos,
        currentIndex: safeIdx,
        showTitle: map['showTitle'] != false,
        intervalMinutes: (map['intervalMinutes'] as num?)?.toInt() ?? 60,
        sourceLabel:
            map['sourceLabel']?.toString().trim().isNotEmpty == true
                ? map['sourceLabel'].toString().trim()
                : 'Custom Pins',
      );
    } catch (_) {
      return const HomeWidgetConfig();
    }
  }
}

/// Snapshot of launcher widget placement state reported by Android.
class HomeWidgetNativeStatus {
  final int installedCount;
  final bool canPin;
  final int currentIndex;

  const HomeWidgetNativeStatus({
    this.installedCount = 0,
    this.canPin = false,
    this.currentIndex = 0,
  });
}

typedef WidgetDirectoryProvider = Future<Directory> Function();
typedef WidgetMediaResolver = Future<String?> Function(String url);

/// Manages cached widget photos, rotation preferences, and Android AppWidget sync.
class HomeWidgetService {
  HomeWidgetService({
    MethodChannel? channelOverride,
    WidgetDirectoryProvider? directoryProviderOverride,
    WidgetMediaResolver? mediaResolverOverride,
    bool? isAndroidOverride,
  })  : _channel = channelOverride ?? const MethodChannel('worship_chat/device'),
        _directoryProviderOverride = directoryProviderOverride,
        _mediaResolverOverride = mediaResolverOverride,
        _isAndroidOverride = isAndroidOverride;

  static final HomeWidgetService instance = HomeWidgetService();

  static const String prefsKey = 'worship_photo_widget_config_v1';
  static const int maxPlaylistLength = 24;

  final MethodChannel _channel;
  final WidgetDirectoryProvider? _directoryProviderOverride;
  final WidgetMediaResolver? _mediaResolverOverride;
  final bool? _isAndroidOverride;

  final ValueNotifier<HomeWidgetConfig> configNotifier =
      ValueNotifier<HomeWidgetConfig>(const HomeWidgetConfig());

  bool get isSupportedPlatform =>
      _isAndroidOverride ??
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  Future<Directory> _getWidgetDirectory() async {
    final base = _directoryProviderOverride != null
        ? await _directoryProviderOverride()
        : await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/photo_widget');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Loads stored config, syncs current index from native Android widget prefs
  /// (if advanced via the home screen Next button), and updates [configNotifier].
  Future<HomeWidgetConfig> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    var config = HomeWidgetConfig.fromJsonString(prefs.getString(prefsKey));

    // Keep only photos whose local files still exist on disk.
    final valid = <HomeWidgetPhoto>[];
    for (final p in config.photos) {
      if (await File(p.localPath).exists()) {
        valid.add(p);
      }
    }
    if (valid.length != config.photos.length) {
      config = config.copyWith(photos: valid);
      await prefs.setString(prefsKey, config.toJsonString());
    }

    if (isSupportedPlatform && config.photos.isNotEmpty) {
      final nativeStatus = await getNativeStatus();
      if (nativeStatus.currentIndex != config.currentIndex &&
          nativeStatus.currentIndex >= 0 &&
          nativeStatus.currentIndex < config.photos.length) {
        config = config.copyWith(currentIndex: nativeStatus.currentIndex);
        await prefs.setString(prefsKey, config.toJsonString());
      }
    }

    configNotifier.value = config;
    return config;
  }

  /// Resolves a photo from local disk or network URL into `<appDocs>/photo_widget/`
  /// so Android's widget provider always has reliable offline access.
  Future<HomeWidgetPhoto?> _materializePhoto(HomeWidgetPhotoInput input) async {
    String? sourcePath = input.localPath?.trim().replaceFirst('file://', '');
    final cleanUrl = input.imageUrl?.trim() ?? '';
    final normalizedUrl =
        (cleanUrl.startsWith('http://') || cleanUrl.startsWith('https://'))
            ? getOriginalHighQualityImageUrl(cleanUrl)
            : cleanUrl;

    if ((sourcePath == null || sourcePath.isEmpty || !await File(sourcePath).exists()) &&
        normalizedUrl.isNotEmpty) {
      if (normalizedUrl.startsWith('/') || normalizedUrl.startsWith('file://')) {
        sourcePath = normalizedUrl.replaceFirst('file://', '');
      } else {
        sourcePath = _mediaResolverOverride != null
            ? await _mediaResolverOverride(normalizedUrl)
            : await MediaCacheService().getMediaPath(normalizedUrl);
      }
    }

    if (sourcePath == null || sourcePath.isEmpty) return null;
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists() || await sourceFile.length() == 0) {
      return null;
    }

    final widgetDir = await _getWidgetDirectory();
    final keySource =
        normalizedUrl.isNotEmpty ? normalizedUrl : sourceFile.path;
    final digest = sha1.convert(utf8.encode(keySource)).toString().substring(0, 16);
    final ext = _extractExtension(sourceFile.path);
    final targetFile = File('${widgetDir.path}/widget_$digest.$ext');

    if (sourceFile.path != targetFile.path) {
      if (!await targetFile.exists() || await targetFile.length() == 0) {
        await sourceFile.copy(targetFile.path);
      }
    }

    return HomeWidgetPhoto(
      id: input.id.trim().isNotEmpty ? input.id.trim() : digest,
      localPath: targetFile.path,
      sourceUrl: normalizedUrl,
      title: input.title.trim(),
      subtitle: input.subtitle.trim(),
    );
  }

  String _extractExtension(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'png';
    if (lower.endsWith('.webp')) return 'webp';
    return 'jpg';
  }

  /// Adds or moves a single photo to the front of the widget playlist and
  /// updates the Android Home Screen Widget immediately.
  Future<bool> pinSinglePhoto(HomeWidgetPhotoInput input) async {
    final materialized = await _materializePhoto(input);
    if (materialized == null) return false;

    final current = await loadConfig();
    final updatedList = <HomeWidgetPhoto>[
      materialized,
      ...current.photos.where(
        (p) =>
            p.localPath != materialized.localPath &&
            p.id != materialized.id,
      ),
    ];
    if (updatedList.length > maxPlaylistLength) {
      updatedList.removeRange(maxPlaylistLength, updatedList.length);
    }

    final nextConfig = current.copyWith(
      photos: updatedList,
      currentIndex: 0,
      sourceLabel: current.photos.isEmpty ? 'Pinned Photo' : current.sourceLabel,
    );
    await _persistAndPush(nextConfig);
    return true;
  }

  /// Replaces the widget playlist from a Collection or Queendom Group Gallery
  /// (caching up to [maxPlaylistLength] photos locally).
  Future<int> syncPlaylist({
    required List<HomeWidgetPhotoInput> items,
    required String sourceLabel,
  }) async {
    final current = await loadConfig();
    final capped = items.take(maxPlaylistLength).toList();
    final savedPhotos = <HomeWidgetPhoto>[];

    for (final item in capped) {
      try {
        final photo = await _materializePhoto(item);
        if (photo != null) {
          savedPhotos.add(photo);
        }
      } catch (e) {
        log('HomeWidgetService: skipped photo ${item.id}: $e');
      }
    }

    if (savedPhotos.isEmpty) return 0;

    final nextConfig = current.copyWith(
      photos: savedPhotos,
      currentIndex: 0,
      sourceLabel: sourceLabel.trim().isNotEmpty ? sourceLabel.trim() : 'Gallery',
    );
    await _persistAndPush(nextConfig);
    return savedPhotos.length;
  }

  /// Selects a specific photo index inside the existing playlist to show now.
  Future<void> selectIndex(int index) async {
    final current = await loadConfig();
    if (current.photos.isEmpty) return;
    await _persistAndPush(current.copyWith(currentIndex: index));
  }

  /// Advances the active widget photo immediately.
  Future<void> nextPhoto() async {
    final current = await loadConfig();
    if (current.photos.isEmpty) return;
    final nextIdx = (current.currentIndex + 1) % current.photos.length;
    await _persistAndPush(current.copyWith(currentIndex: nextIdx));
  }

  /// Removes a single photo from the widget playlist.
  Future<void> removePhoto(String id) async {
    final current = await loadConfig();
    final nextPhotos = current.photos.where((p) => p.id != id).toList();
    await _persistAndPush(current.copyWith(photos: nextPhotos));
  }

  /// Updates widget display / rotation settings and refreshes Android widgets.
  Future<void> updatePreferences({
    bool? showTitle,
    int? intervalMinutes,
  }) async {
    final current = await loadConfig();
    final nextConfig = current.copyWith(
      showTitle: showTitle ?? current.showTitle,
      intervalMinutes: intervalMinutes ?? current.intervalMinutes,
    );
    await _persistAndPush(nextConfig);
  }

  /// Clears the entire widget playlist and removes local widget cache files.
  Future<void> clearAll() async {
    final current = await loadConfig();
    await _persistAndPush(
      current.copyWith(
        photos: const [],
        currentIndex: 0,
        sourceLabel: 'Custom Pins',
      ),
    );
  }

  /// Requests Android 8+ launcher to pin the Worship Chat photo widget.
  Future<bool> requestPinWidget() async {
    if (!isSupportedPlatform) return false;
    try {
      final result = await _channel.invokeMethod<bool>('requestPinPhotoWidget');
      return result == true;
    } catch (e) {
      log('HomeWidgetService.requestPinWidget error: $e');
      return false;
    }
  }

  Future<HomeWidgetNativeStatus> getNativeStatus() async {
    if (!isSupportedPlatform) return const HomeWidgetNativeStatus();
    try {
      final map = await _channel.invokeMapMethod<String, dynamic>(
        'getPhotoWidgetInfo',
      );
      if (map == null) return const HomeWidgetNativeStatus();
      return HomeWidgetNativeStatus(
        installedCount: (map['installedCount'] as num?)?.toInt() ?? 0,
        canPin: map['canPin'] == true,
        currentIndex: (map['currentIndex'] as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      log('HomeWidgetService.getNativeStatus error: $e');
      return const HomeWidgetNativeStatus();
    }
  }

  Future<void> _persistAndPush(HomeWidgetConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, config.toJsonString());
    configNotifier.value = config;
    await _cleanupUnusedWidgetFiles(config);

    if (!isSupportedPlatform) return;
    try {
      await _channel.invokeMethod<bool>('updatePhotoWidget', {
        'photos': config.photos.map((p) => p.toJson()).toList(),
        'currentIndex': config.currentIndex,
        'showTitle': config.showTitle,
        'intervalMinutes': config.intervalMinutes,
        'sourceLabel': config.sourceLabel,
      });
    } catch (e) {
      log('HomeWidgetService.updatePhotoWidget error: $e');
    }
  }

  Future<void> _cleanupUnusedWidgetFiles(HomeWidgetConfig config) async {
    try {
      final widgetDir = await _getWidgetDirectory();
      final activePaths = config.photos.map((p) => p.localPath).toSet();
      await for (final entity in widgetDir.list()) {
        if (entity is File && !activePaths.contains(entity.path)) {
          await entity.delete();
        }
      }
    } catch (_) {}
  }
}
