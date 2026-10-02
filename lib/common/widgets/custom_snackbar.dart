import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:worship_chat/colors.dart';

enum SnackBarType {
  info,
  success,
  error,
  warning,
}

/// A modern, beautiful, unified floating SnackBar for Worship Chat.
class AppSnackBar {
  AppSnackBar._();

  /// Create a styled [SnackBar] widget
  static SnackBar create({
    required BuildContext context,
    required String message,
    String? title,
    SnackBarType type = SnackBarType.info,
    Duration duration = const Duration(milliseconds: 3200),
    String? actionLabel,
    VoidCallback? onAction,
    IconData? customIcon,
  }) {
    final colors = _getColorsForType(type);
    final iconData = customIcon ?? _getIconForType(type);

    return SnackBar(
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.transparent,
      duration: duration,
      padding: EdgeInsets.zero,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      content: _SnackBarContent(
        message: message,
        title: title,
        accentColor: colors.accent,
        iconData: iconData,
        actionLabel: actionLabel,
        onAction: onAction,
        onDismiss: () {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
        },
      ),
    );
  }

  /// Display a floating snackbar with modern design
  static void show(
    BuildContext context, {
    required String message,
    String? title,
    SnackBarType? type,
    Duration duration = const Duration(milliseconds: 3200),
    String? actionLabel,
    VoidCallback? onAction,
    IconData? customIcon,
  }) {
    if (!context.mounted) return;

    final resolvedType = type ?? _inferType(message);

    // Haptic feedback
    if (resolvedType == SnackBarType.error || resolvedType == SnackBarType.warning) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.lightImpact();
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();

    messenger.showSnackBar(
      create(
        context: context,
        message: message,
        title: title,
        type: resolvedType,
        duration: duration,
        actionLabel: actionLabel,
        onAction: onAction,
        customIcon: customIcon,
      ),
    );
  }

  /// Convenience helper for Success
  static void success(
    BuildContext context,
    String message, {
    String? title,
    Duration duration = const Duration(milliseconds: 3000),
    String? actionLabel,
    VoidCallback? onAction,
    IconData? customIcon,
  }) {
    show(
      context,
      message: message,
      title: title,
      type: SnackBarType.success,
      duration: duration,
      actionLabel: actionLabel,
      onAction: onAction,
      customIcon: customIcon,
    );
  }

  /// Convenience helper for Error
  static void error(
    BuildContext context,
    String message, {
    String? title,
    Duration duration = const Duration(milliseconds: 3500),
    String? actionLabel,
    VoidCallback? onAction,
    IconData? customIcon,
  }) {
    show(
      context,
      message: message,
      title: title,
      type: SnackBarType.error,
      duration: duration,
      actionLabel: actionLabel,
      onAction: onAction,
      customIcon: customIcon,
    );
  }

  /// Convenience helper for Info
  static void info(
    BuildContext context,
    String message, {
    String? title,
    Duration duration = const Duration(milliseconds: 3000),
    String? actionLabel,
    VoidCallback? onAction,
    IconData? customIcon,
  }) {
    show(
      context,
      message: message,
      title: title,
      type: SnackBarType.info,
      duration: duration,
      actionLabel: actionLabel,
      onAction: onAction,
      customIcon: customIcon,
    );
  }

  /// Convenience helper for Warning
  static void warning(
    BuildContext context,
    String message, {
    String? title,
    Duration duration = const Duration(milliseconds: 3200),
    String? actionLabel,
    VoidCallback? onAction,
    IconData? customIcon,
  }) {
    show(
      context,
      message: message,
      title: title,
      type: SnackBarType.warning,
      duration: duration,
      actionLabel: actionLabel,
      onAction: onAction,
      customIcon: customIcon,
    );
  }

  static SnackBarType _inferType(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('error') ||
        lower.contains('failed') ||
        lower.contains('could not') ||
        lower.contains('denied') ||
        lower.contains('unable') ||
        lower.contains('cannot') ||
        lower.contains('not found')) {
      return SnackBarType.error;
    }
    if (lower.contains('success') ||
        lower.contains('copied') ||
        lower.contains('saved') ||
        lower.contains('updated') ||
        lower.contains('sent') ||
        lower.contains('connected') ||
        lower.contains('joined') ||
        lower.contains('created') ||
        lower.contains('done')) {
      return SnackBarType.success;
    }
    if (lower.contains('warning') ||
        lower.contains('please') ||
        lower.contains('required') ||
        lower.contains('enter') ||
        lower.contains('select')) {
      return SnackBarType.warning;
    }
    return SnackBarType.info;
  }

  static _SnackBarColors _getColorsForType(SnackBarType type) {
    switch (type) {
      case SnackBarType.success:
        return const _SnackBarColors(
          accent: Color(0xFF00E676),
        );
      case SnackBarType.error:
        return const _SnackBarColors(
          accent: Color(0xFFFF5252),
        );
      case SnackBarType.warning:
        return const _SnackBarColors(
          accent: Color(0xFFFFB300),
        );
      case SnackBarType.info:
        return const _SnackBarColors(
          accent: tabColor,
        );
    }
  }

  static IconData _getIconForType(SnackBarType type) {
    switch (type) {
      case SnackBarType.success:
        return Icons.check_circle_rounded;
      case SnackBarType.error:
        return Icons.error_outline_rounded;
      case SnackBarType.warning:
        return Icons.warning_amber_rounded;
      case SnackBarType.info:
        return Icons.info_outline_rounded;
    }
  }
}

class _SnackBarColors {
  final Color accent;
  const _SnackBarColors({required this.accent});
}

class _SnackBarContent extends StatelessWidget {
  final String message;
  final String? title;
  final Color accentColor;
  final IconData iconData;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onDismiss;

  const _SnackBarContent({
    required this.message,
    this.title,
    required this.accentColor,
    required this.iconData,
    this.actionLabel,
    this.onAction,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1B172B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.38),
          width: 1.1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 18,
            spreadRadius: 1,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: accentColor.withValues(alpha: 0.16),
            blurRadius: 14,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          // Icon badge with soft background glow
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accentColor.withValues(alpha: 0.14),
              border: Border.all(
                color: accentColor.withValues(alpha: 0.3),
                width: 1.0,
              ),
            ),
            child: Icon(
              iconData,
              color: accentColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),

          // Message & optional title
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null && title!.isNotEmpty) ...[
                  Text(
                    title!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.1,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  message,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1.25,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // Action button if provided
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: () {
                onDismiss();
                onAction!();
              },
              style: TextButton.styleFrom(
                foregroundColor: accentColor,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                actionLabel!,
                style: TextStyle(
                  color: accentColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ),
          ],

          const SizedBox(width: 6),

          // Subtle close dismiss button
          GestureDetector(
            onTap: onDismiss,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
              child: const Icon(
                Icons.close_rounded,
                size: 14,
                color: Colors.white54,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
