import 'dart:developer';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/utils/media_cache_service.dart';
import 'package:worship_chat/common/utils/utils.dart';

enum WallpaperTarget {
  home('home', 'Home Screen'),
  lock('lock', 'Lock Screen'),
  both('both', 'Home & Lock Screens');

  final String nativeKey;
  final String label;
  const WallpaperTarget(this.nativeKey, this.label);
}

class WallpaperApplyResult {
  final bool success;
  final bool cancelled;
  final String message;

  const WallpaperApplyResult({
    required this.success,
    this.cancelled = false,
    required this.message,
  });
}

typedef WallpaperResolver = Future<String?> Function(String url);

/// Handles resolving, optionally cropping, and setting Android phone wallpapers.
class PhoneWallpaperService {
  PhoneWallpaperService({
    MethodChannel? channelOverride,
    WallpaperResolver? resolverOverride,
    bool? isAndroidOverride,
  })  : _channel = channelOverride ?? const MethodChannel('worship_chat/device'),
        _resolverOverride = resolverOverride,
        _isAndroidOverride = isAndroidOverride;

  static final PhoneWallpaperService instance = PhoneWallpaperService();

  final MethodChannel _channel;
  final WallpaperResolver? _resolverOverride;
  final bool? _isAndroidOverride;

  bool get isSupported =>
      _isAndroidOverride ??
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  /// Resolves a local [File] from either [localPath] or a remote [imageUrl].
  Future<File?> resolveImageFile({String? imageUrl, String? localPath}) async {
    final trimmedLocal = localPath?.trim().replaceFirst('file://', '');
    if (trimmedLocal != null && trimmedLocal.isNotEmpty) {
      final f = File(trimmedLocal);
      if (await f.exists() && await f.length() > 0) return f;
    }

    final rawUrl = imageUrl?.trim() ?? '';
    if (rawUrl.isEmpty) return null;

    if (rawUrl.startsWith('/') || rawUrl.startsWith('file://')) {
      final f = File(rawUrl.replaceFirst('file://', ''));
      if (await f.exists() && await f.length() > 0) return f;
      return null;
    }

    final highResUrl = getOriginalHighQualityImageUrl(rawUrl);
    final cachedPath = _resolverOverride != null
        ? await _resolverOverride(highResUrl)
        : await MediaCacheService().getMediaPath(highResUrl);
    if (cachedPath == null || cachedPath.isEmpty) return null;

    final file = File(cachedPath);
    if (await file.exists() && await file.length() > 0) return file;
    return null;
  }

  /// Opens an optional phone-screen cropper matching the device aspect ratio.
  Future<File?> cropForScreen(BuildContext context, File sourceFile) async {
    final size = MediaQuery.of(context).size;
    final ratio =
        size.height > 0 ? (size.width / size.height).clamp(0.3, 1.5) : 9 / 19.5;

    final cropped = await ImageCropper().cropImage(
      sourcePath: sourceFile.path,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 100,
      aspectRatio: CropAspectRatio(ratioX: ratio, ratioY: 1.0),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Adjust Wallpaper Crop',
          toolbarColor: const Color(0xFF161426),
          toolbarWidgetColor: Colors.white,
          backgroundColor: Colors.black,
          activeControlsWidgetColor: tabColor,
          initAspectRatio: CropAspectRatioPreset.original,
          lockAspectRatio: false,
          hideBottomControls: false,
          showCropGrid: true,
        ),
      ],
    );

    if (cropped == null) return null;
    return File(cropped.path);
  }

  /// Downloads/resolves and applies the image to [target] on Android.
  Future<WallpaperApplyResult> applyWallpaper({
    BuildContext? context,
    String? imageUrl,
    String? localPath,
    required WallpaperTarget target,
    bool cropFirst = false,
  }) async {
    if (!isSupported) {
      return const WallpaperApplyResult(
        success: false,
        message: 'Setting phone wallpaper is supported on Android devices.',
      );
    }

    final resolved = await resolveImageFile(
      imageUrl: imageUrl,
      localPath: localPath,
    );
    if (resolved == null) {
      return const WallpaperApplyResult(
        success: false,
        message: 'Could not load high-resolution image for wallpaper.',
      );
    }

    var fileToApply = resolved;
    if (cropFirst && context != null && context.mounted) {
      final cropped = await cropForScreen(context, resolved);
      if (cropped == null) {
        return const WallpaperApplyResult(
          success: false,
          cancelled: true,
          message: 'Wallpaper crop cancelled.',
        );
      }
      fileToApply = cropped;
    }

    try {
      final applied = await _channel.invokeMethod<bool>('setWallpaper', {
        'path': fileToApply.path,
        'target': target.nativeKey,
      });
      if (applied == true) {
        return WallpaperApplyResult(
          success: true,
          message: 'Applied to ${target.label}!',
        );
      }
      return const WallpaperApplyResult(
        success: false,
        message: 'Could not apply wallpaper on this device.',
      );
    } on PlatformException catch (e) {
      log('PhoneWallpaperService PlatformException: $e');
      return WallpaperApplyResult(
        success: false,
        message: e.message ?? 'Failed to set wallpaper.',
      );
    } catch (e) {
      log('PhoneWallpaperService error: $e');
      return WallpaperApplyResult(
        success: false,
        message: 'Failed to set wallpaper: $e',
      );
    }
  }
}
