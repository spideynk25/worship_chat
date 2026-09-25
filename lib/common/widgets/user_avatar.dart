import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:worship_chat/colors.dart';

/// A consistent circular avatar used across every screen.
///
/// Always renders as a perfect circle with [radius].
/// Uses [CachedNetworkImage] so images are cached and never re-fetched.
/// Falls back to a person icon if [url] is null/empty or fails to load.
class UserAvatar extends StatelessWidget {
  final String? url;
  final double radius;
  final Color? backgroundColor;
  final bool? isOnline;
  final bool showOnlineIndicator;
  final Color? borderColor;

  const UserAvatar({
    super.key,
    required this.url,
    this.radius = 20,
    this.backgroundColor,
    this.isOnline,
    this.showOnlineIndicator = false,
    this.borderColor,
  });

  /// Sanitizes any profile picture URL: trims whitespace, skips "null",
  /// and automatically upgrades insecure http:// to https:// so Android/iOS
  /// network security policies do not block cleartext image loading.
  static String? sanitizeUrl(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed == 'null') return null;
    if (trimmed.startsWith('http://')) {
      return trimmed.replaceFirst('http://', 'https://');
    }
    return trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? tabColor.withValues(alpha: 0.12);
    final double size = radius * 2;
    final cleanUrl = sanitizeUrl(url);

    final avatarWidget = ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: (cleanUrl != null && cleanUrl.isNotEmpty)
            ? CachedNetworkImage(
                imageUrl: cleanUrl,
                width: size,
                height: size,
                fit: BoxFit.cover,
                memCacheWidth: (size * 2).toInt(),
                memCacheHeight: (size * 2).toInt(),
                // Show a coloured circle while loading
                placeholder: (_, __) => _fallback(bg, size),
                errorWidget: (context, errorUrl, error) {
                  debugPrint('⚠️ UserAvatar CachedNetworkImage failed for $errorUrl: $error');
                  return _fallback(bg, size);
                },
              )
            : _fallback(bg, size),
      ),
    );

    if (!showOnlineIndicator || isOnline == null) {
      return avatarWidget;
    }

    final badgeSize = (radius * 0.55).clamp(8.0, 14.0);
    final rimColor = borderColor ?? appBarColor;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatarWidget,
        Positioned(
          bottom: 0,
          right: 0,
          child: Container(
            width: badgeSize,
            height: badgeSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isOnline == true
                  ? const Color(0xFF00E676)
                  : const Color(0xFF757575),
              border: Border.all(
                color: rimColor,
                width: (badgeSize * 0.18).clamp(1.5, 2.5),
              ),
              boxShadow: isOnline == true
                  ? [
                      BoxShadow(
                        color: const Color(0xFF00E676).withValues(alpha: 0.6),
                        blurRadius: 4,
                      ),
                    ]
                  : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _fallback(Color bg, double size) {
    return Container(
      width: size,
      height: size,
      color: bg,
      child: Icon(
        Icons.person_rounded,
        color: tabColor.withValues(alpha: 0.6),
        size: size * 0.55,
      ),
    );
  }
}
