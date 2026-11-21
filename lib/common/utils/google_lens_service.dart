import 'dart:developer';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:worship_chat/common/utils/media_cache_service.dart';
import 'package:worship_chat/common/utils/utils.dart';

/// Service for launching Google Lens visual reverse-image search on images
/// across Chats, Bookmarks, and Gallery.
///
/// Supports both native Google Lens / QuickSearchBox intents on Android (using FileProvider
/// for local files) and Google Lens web endpoint (`https://lens.google.com/uploadbyurl`)
/// across all platforms.
class GoogleLensService {
  static const MethodChannel _channel = MethodChannel('worship_chat/device');

  /// Builds the official Google Lens reverse-image search URL for a hosted image.
  static String buildLensWebUrl(String imageUrl) {
    final cleanUrl = getOriginalHighQualityImageUrl(imageUrl.trim());
    return 'https://lens.google.com/uploadbyurl?url=${Uri.encodeComponent(cleanUrl)}';
  }

  /// Triggers a Google Lens search for the given image.
  ///
  /// Parameters:
  /// - [context]: BuildContext for displaying user feedback (e.g. snackbar if unavailable).
  /// - [imageUrl]: Remote web URL (e.g. Cloudinary, Firebase) or file URI.
  /// - [localPath]: Local filesystem path (e.g. from local gallery or device cache).
  /// - [showFeedback]: Whether to display a snackbar if launch fails.
  ///
  /// Returns `true` if Google Lens was successfully triggered, `false` otherwise.
  static Future<bool> search({
    BuildContext? context,
    String? imageUrl,
    String? localPath,
    bool showFeedback = true,
  }) async {
    HapticFeedback.lightImpact();

    String? resolvedUrl;
    String? resolvedPath;

    // 1. Resolve local path and remote URL
    if (localPath != null && localPath.trim().isNotEmpty) {
      resolvedPath = localPath.trim().replaceFirst('file://', '');
    }

    if (imageUrl != null && imageUrl.trim().isNotEmpty) {
      final trimmed = imageUrl.trim();
      if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
        resolvedUrl = getOriginalHighQualityImageUrl(trimmed);
      } else if (trimmed.startsWith('/') || trimmed.startsWith('file://')) {
        resolvedPath ??= trimmed.replaceFirst('file://', '');
      }
    }

    // Check media cache if we have a remote URL but no local path yet
    if (resolvedPath == null && resolvedUrl != null) {
      final cached = MediaCacheService().getCachedSync(resolvedUrl);
      if (cached != null && File(cached).existsSync()) {
        resolvedPath = cached;
      }
    }

    // Validate that at least one valid source is present
    final hasValidLocalFile =
        resolvedPath != null && File(resolvedPath).existsSync();
    final hasValidRemoteUrl = resolvedUrl != null && resolvedUrl.isNotEmpty;

    if (!hasValidLocalFile && !hasValidRemoteUrl) {
      if (context != null && context.mounted && showFeedback) {
        AppSnackBar.show(context, message: '⚠️ Image unavailable for Google Lens');
      }
      return false;
    }

    bool success = false;

    // 2. Try native channel on Android
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final result = await _channel.invokeMethod<bool>('openGoogleLens', {
          'path': hasValidLocalFile ? resolvedPath : null,
          'url': hasValidRemoteUrl ? resolvedUrl : null,
        });
        if (result == true) {
          success = true;
        }
      } catch (e) {
        log('GoogleLensService native error: $e');
      }
    }

    // 3. Fallback to Google Lens web URL if native didn't succeed and remote URL is available
    if (!success && hasValidRemoteUrl) {
      try {
        final lensUri = Uri.parse(buildLensWebUrl(resolvedUrl));
        success = await launchUrl(
          lensUri,
          mode: LaunchMode.externalApplication,
        );
        if (!success) {
          success = await launchUrl(
            lensUri,
            mode: LaunchMode.platformDefault,
          );
        }
      } catch (e) {
        log('GoogleLensService web url error: $e');
      }
    }

    // Feedback
    if (!success && context != null && context.mounted && showFeedback) {
      AppSnackBar.show(
        context,
        message: 'Could not open Google Lens for this image',
      );
    }

    return success;
  }
}

/// A pixel-perfect, scalable widget that renders the iconic Google Lens viewfinder icon
/// using Google's signature 4-color palette (Blue, Red, Yellow, Green) or a custom color.
class GoogleLensIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final bool useGoogleColors;

  const GoogleLensIcon({
    super.key,
    this.size = 22.0,
    this.color,
    this.useGoogleColors = true,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GoogleLensPainter(
          color: color,
          useGoogleColors: useGoogleColors && color == null,
        ),
      ),
    );
  }
}

class _GoogleLensPainter extends CustomPainter {
  final Color? color;
  final bool useGoogleColors;

  const _GoogleLensPainter({
    this.color,
    required this.useGoogleColors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final strokeWidth = (w / 24.0) * 2.3;

    final blue =
        useGoogleColors ? const Color(0xFF4285F4) : (color ?? Colors.white);
    final red =
        useGoogleColors ? const Color(0xFFEA4335) : (color ?? Colors.white);
    final yellow =
        useGoogleColors ? const Color(0xFFFBBC05) : (color ?? Colors.white);
    final green =
        useGoogleColors ? const Color(0xFF34A853) : (color ?? Colors.white);

    final pad = w * 0.12;
    final left = pad;
    final top = pad;
    final right = w - pad;
    final bottom = h - pad;
    final cornerRadius = w * 0.22;
    final segment = w * 0.26;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Top-Left Corner (Blue)
    paint.color = blue;
    final tlPath = Path()
      ..moveTo(left, top + segment)
      ..lineTo(left, top + cornerRadius)
      ..arcToPoint(
        Offset(left + cornerRadius, top),
        radius: Radius.circular(cornerRadius),
      )
      ..lineTo(left + segment, top);
    canvas.drawPath(tlPath, paint);

    // Top-Right Corner (Red)
    paint.color = red;
    final trPath = Path()
      ..moveTo(right - segment, top)
      ..lineTo(right - cornerRadius, top)
      ..arcToPoint(
        Offset(right, top + cornerRadius),
        radius: Radius.circular(cornerRadius),
      )
      ..lineTo(right, top + segment);
    canvas.drawPath(trPath, paint);

    // Bottom-Right Corner (Yellow)
    paint.color = yellow;
    final brPath = Path()
      ..moveTo(right, bottom - segment)
      ..lineTo(right, bottom - cornerRadius)
      ..arcToPoint(
        Offset(right - cornerRadius, bottom),
        radius: Radius.circular(cornerRadius),
      )
      ..lineTo(right - segment, bottom);
    canvas.drawPath(brPath, paint);

    // Bottom-Left Corner (Green)
    paint.color = green;
    final blPath = Path()
      ..moveTo(left + segment, bottom)
      ..lineTo(left + cornerRadius, bottom)
      ..arcToPoint(
        Offset(left, bottom - cornerRadius),
        radius: Radius.circular(cornerRadius),
      )
      ..lineTo(left, bottom - segment);
    canvas.drawPath(blPath, paint);

    // Center Lens Circle (Blue)
    paint.color = blue;
    paint.style = PaintingStyle.stroke;
    canvas.drawCircle(
      Offset(w / 2, h / 2),
      w * 0.15,
      paint,
    );

    // Inner dot (Red sensor)
    paint.style = PaintingStyle.fill;
    paint.color = red;
    canvas.drawCircle(
      Offset(w / 2 + w * 0.04, h / 2 - h * 0.04),
      w * 0.045,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _GoogleLensPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.useGoogleColors != useGoogleColors;
  }
}
