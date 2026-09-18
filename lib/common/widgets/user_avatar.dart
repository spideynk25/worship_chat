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

  const UserAvatar({
    super.key,
    required this.url,
    this.radius = 20,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? tabColor.withOpacity(0.12);
    final double size = radius * 2;

    final hasUrl = url != null && url!.isNotEmpty;

    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: hasUrl
            ? CachedNetworkImage(
                imageUrl: url!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                // Show a coloured circle while loading
                placeholder: (_, __) => _fallback(bg, size),
                errorWidget: (_, __, ___) => _fallback(bg, size),
              )
            : _fallback(bg, size),
      ),
    );
  }

  Widget _fallback(Color bg, double size) {
    return Container(
      width: size,
      height: size,
      color: bg,
      child: Icon(
        Icons.person_rounded,
        color: tabColor.withOpacity(0.6),
        size: size * 0.55,
      ),
    );
  }
}
