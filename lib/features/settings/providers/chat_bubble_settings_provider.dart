import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worship_chat/colors.dart';

/// Represents typography and contrast parameters adapted to a background color.
class BubbleTextContrast {
  final Color primaryTextColor;
  final Color secondaryTextColor;
  final Color linkColor;
  final List<Shadow> textShadows;
  final Color statusIconColor;
  final bool isLightBackground;

  const BubbleTextContrast({
    required this.primaryTextColor,
    required this.secondaryTextColor,
    required this.linkColor,
    required this.textShadows,
    required this.statusIconColor,
    required this.isLightBackground,
  });
}

/// Configuration and persistence for chat bubble appearance.
class ChatBubbleSettings {
  /// Transparency value from 0.0 (completely solid) to 1.0 (completely transparent glass).
  /// Default is 0.70 (which maps to the app's default frosted glass appearance).
  final double transparency;

  const ChatBubbleSettings({
    this.transparency = defaultTransparency,
  });

  /// Default transparency value (70% transparent / 30% base opacity).
  static const double defaultTransparency = 0.70;

  /// Opacity multiplier where 0.0 = fully transparent glass, 1.0 = solid.
  double get opacity => (1.0 - transparency).clamp(0.0, 1.0);

  ChatBubbleSettings copyWith({double? transparency}) {
    return ChatBubbleSettings(
      transparency: transparency ?? this.transparency,
    );
  }

  /// Dynamically computes alpha based on the original base alpha at default transparency.
  /// When transparency is at default (0.70), it returns exactly [baseAtDefault].
  /// When transparency is 0.0 (0% transparent = solid), it returns [maxAlpha].
  /// When transparency is 1.0 (100% transparent), it returns [minAlpha].
  double computeAlpha(
    double baseAtDefault, {
    double minAlpha = 0.02,
    double maxAlpha = 0.95,
  }) {
    final currentOpacity = opacity;
    const defaultOpacity = 1.0 - defaultTransparency; // 0.30

    if (currentOpacity <= defaultOpacity) {
      final t = (defaultOpacity > 0) ? (currentOpacity / defaultOpacity) : 0.0;
      return minAlpha + (baseAtDefault - minAlpha) * t;
    } else {
      final remaining = 1.0 - defaultOpacity;
      final u = (remaining > 0) ? ((currentOpacity - defaultOpacity) / remaining) : 0.0;
      // Perceptual quadratic curve so intermediate tint levels (e.g. 26%-35%)
      // stay pleasantly translucent instead of solidifying prematurely.
      final t = (u * u).clamp(0.0, 1.0);
      return baseAtDefault + (maxAlpha - baseAtDefault) * t;
    }
  }

  /// Adjusts a color's alpha dynamically based on the current transparency setting.
  Color adjustColor(
    Color baseColor,
    double defaultAlpha, {
    double minAlpha = 0.02,
    double maxAlpha = 0.95,
  }) {
    return baseColor.withValues(
      alpha: computeAlpha(defaultAlpha, minAlpha: minAlpha, maxAlpha: maxAlpha),
    );
  }

  /// Generates comfortable, eye-friendly gradient colors across the entire transparency range.
  ///
  /// In default glass mode (0.70), matches the app's signature frosted glass look.
  /// In solid mode (0.0), provides comfortable, eye-friendly jewel tones for sent messages
  /// and rich, comfortable slate-violet cards for received messages (never glaring white!).
  List<Color> getBubbleGradientColors({
    required bool isMe,
    bool isSending = false,
    double pulse = 0.0,
  }) {
    if (isMe) {
      // Sent bubble (MyMessageCard) - authentic luxury wine & velvety burgundy tones
      if (transparency >= defaultTransparency) {
        // Frosted glass (0.70) to clear glass (1.0)
        final t = ((transparency - defaultTransparency) / (1.0 - defaultTransparency)).clamp(0.0, 1.0);
        final a1 = lerpDouble(0.32, 0.06, t)!;
        final a2 = lerpDouble(0.25, 0.04, t)!;
        final a3 = lerpDouble(0.30, 0.06, t)!;

        final c1 = const Color(0xFF7D1F55).withValues(alpha: a1);
        final c2 = const Color(0xFF661845).withValues(alpha: a2);
        final c3 = const Color(0xFF4E1135).withValues(alpha: a3);

        if (isSending) {
          final s1 = const Color(0xFF8E2361).withValues(alpha: lerpDouble(0.45, 0.10, t)!);
          final s2 = const Color(0xFF7A1D54).withValues(alpha: lerpDouble(0.38, 0.08, t)!);
          final s3 = const Color(0xFF5E1641).withValues(alpha: lerpDouble(0.42, 0.10, t)!);
          return [
            Color.lerp(c1, s1, pulse)!,
            Color.lerp(c2, s2, pulse)!,
            Color.lerp(c3, s3, pulse)!,
          ];
        }
        return [c1, c2, c3];
      } else {
        // Solid (0.0) to frosted glass (0.70)
        // Uses perceptual quadratic curve to ensure comfortable translucency at 26%-35%
        final u = ((defaultTransparency - transparency) / defaultTransparency).clamp(0.0, 1.0);
        final t = u * u;
        final a1 = lerpDouble(0.32, 0.95, t)!;
        final a2 = lerpDouble(0.25, 0.95, t)!;
        final a3 = lerpDouble(0.30, 0.95, t)!;

        final baseC1 = Color.lerp(const Color(0xFF7D1F55), const Color(0xFF6E1C4B), t)!;
        final baseC2 = Color.lerp(const Color(0xFF661845), const Color(0xFF5E1740), t)!;
        final baseC3 = const Color(0xFF4E1135);

        final c1 = baseC1.withValues(alpha: a1);
        final c2 = baseC2.withValues(alpha: a2);
        final c3 = baseC3.withValues(alpha: a3);

        if (isSending) {
          final s1 = Color.lerp(const Color(0xFF8E2361), const Color(0xFF8B2360), t)!
              .withValues(alpha: lerpDouble(0.45, 0.98, t)!);
          final s2 = Color.lerp(const Color(0xFF7A1D54), const Color(0xFF751C4F), t)!
              .withValues(alpha: lerpDouble(0.38, 0.98, t)!);
          final s3 = Color.lerp(const Color(0xFF5E1641), const Color(0xFF631644), t)!
              .withValues(alpha: lerpDouble(0.42, 0.98, t)!);
          return [
            Color.lerp(c1, s1, pulse)!,
            Color.lerp(c2, s2, pulse)!,
            Color.lerp(c3, s3, pulse)!,
          ];
        }
        return [c1, c2, c3];
      }
    } else {
      // Received bubble (SenderMessageCard) - authentic rich obsidian violet & deep slate dusk
      if (transparency >= defaultTransparency) {
        // Frosted glass (0.70) to clear glass (1.0)
        final t = ((transparency - defaultTransparency) / (1.0 - defaultTransparency)).clamp(0.0, 1.0);
        final a1 = lerpDouble(0.32, 0.06, t)!;
        final a2 = lerpDouble(0.24, 0.04, t)!;
        final a3 = lerpDouble(0.30, 0.06, t)!;
        return [
          const Color(0xFF382F52).withValues(alpha: a1),
          const Color(0xFF282138).withValues(alpha: a2),
          const Color(0xFF1B1728).withValues(alpha: a3),
        ];
      } else {
        // Solid (0.0) to frosted glass (0.70)
        // Transitions smoothly to authentic obsidian violet & deep slate dusk.
        // NOTE: Never lerp with Colors.white! That caused chalky grey at intermediate values (e.g. 26%).
        final u = ((defaultTransparency - transparency) / defaultTransparency).clamp(0.0, 1.0);
        final t = u * u;
        final a1 = lerpDouble(0.32, 0.95, t)!;
        final a2 = lerpDouble(0.24, 0.95, t)!;
        final a3 = lerpDouble(0.30, 0.95, t)!;

        final baseC1 = Color.lerp(const Color(0xFF382F52), const Color(0xFF262137), t)!;
        final baseC2 = Color.lerp(const Color(0xFF282138), const Color(0xFF201B2E), t)!;
        final baseC3 = const Color(0xFF1B1728);

        return [
          baseC1.withValues(alpha: a1),
          baseC2.withValues(alpha: a2),
          baseC3.withValues(alpha: a3),
        ];
      }
    }
  }

  /// Generates comfortable border styling across transparency range.
  Color getBubbleBorderColor({
    required bool isMe,
    bool isSending = false,
    double pulse = 0.0,
  }) {
    if (isMe) {
      if (transparency >= defaultTransparency) {
        final t = ((transparency - defaultTransparency) / (1.0 - defaultTransparency)).clamp(0.0, 1.0);
        final a = lerpDouble(0.35, 0.12, t)!;
        final base = const Color(0xFFFF6DA4).withValues(alpha: a);
        if (isSending) {
          final s = const Color(0xFFFF4081).withValues(alpha: lerpDouble(0.65, 0.25, t)!);
          return Color.lerp(base, s, pulse)!;
        }
        return base;
      } else {
        final u = ((defaultTransparency - transparency) / defaultTransparency).clamp(0.0, 1.0);
        final t = u * u;
        final a = lerpDouble(0.35, 0.45, t)!;
        final baseColor = Color.lerp(const Color(0xFFFF6DA4), const Color(0xFFFF4081), t)!;
        final base = baseColor.withValues(alpha: a);
        if (isSending) {
          final s = const Color(0xFFFF4081).withValues(alpha: lerpDouble(0.65, 0.85, t)!);
          return Color.lerp(base, s, pulse)!;
        }
        return base;
      }
    } else {
      if (transparency >= defaultTransparency) {
        final t = ((transparency - defaultTransparency) / (1.0 - defaultTransparency)).clamp(0.0, 1.0);
        final a = lerpDouble(0.18, 0.08, t)!;
        return Colors.white.withValues(alpha: a);
      } else {
        final u = ((defaultTransparency - transparency) / defaultTransparency).clamp(0.0, 1.0);
        final t = u * u;
        final a = lerpDouble(0.18, 0.30, t)!;
        final baseColor = Color.lerp(Colors.white, const Color(0xFF453B60), t)!;
        return baseColor.withValues(alpha: a);
      }
    }
  }

  /// Generates roleplay message gradient colors.
  List<Color> getRoleplayGradientColors(Color accent) {
    if (transparency >= defaultTransparency) {
      final t = ((transparency - defaultTransparency) / (1.0 - defaultTransparency)).clamp(0.0, 1.0);
      final a1 = lerpDouble(0.25, 0.05, t)!;
      final a2 = lerpDouble(0.22, 0.05, t)!;
      final a3 = lerpDouble(0.28, 0.06, t)!;
      return [
        const Color(0xFF2E2448).withValues(alpha: a1),
        accent.withValues(alpha: a2),
        const Color(0xFF1B1530).withValues(alpha: a3),
      ];
    } else {
      final u = ((defaultTransparency - transparency) / defaultTransparency).clamp(0.0, 1.0);
      final t = u * u;
      final a1 = lerpDouble(0.25, 0.95, t)!;
      final a2 = lerpDouble(0.22, 0.95, t)!;
      final a3 = lerpDouble(0.28, 0.95, t)!;
      final baseC1 = Color.lerp(const Color(0xFF2E2448), const Color(0xFF261D3B), t)!;
      final baseC2 = Color.lerp(accent, Color.lerp(const Color(0xFF201732), accent, 0.45)!, t)!;
      final baseC3 = Color.lerp(const Color(0xFF1B1530), const Color(0xFF140F22), t)!;
      return [
        baseC1.withValues(alpha: a1),
        baseC2.withValues(alpha: a2),
        baseC3.withValues(alpha: a3),
      ];
    }
  }

  /// Computes the effective background color of a bubble, accounting for:
  /// 1) Bubble gradient stops
  /// 2) Transparency / Alpha
  /// 3) Backdrop wallpaper color behind the bubble
  Color getBubbleEffectiveBackgroundColor({
    required bool isMe,
    Color backdropColor = const Color(0xFF0A0A0F),
  }) {
    final colors = getBubbleGradientColors(isMe: isMe);
    final avgR = colors.fold<double>(0, (sum, c) => sum + c.r) / colors.length;
    final avgG = colors.fold<double>(0, (sum, c) => sum + c.g) / colors.length;
    final avgB = colors.fold<double>(0, (sum, c) => sum + c.b) / colors.length;
    final avgA = colors.fold<double>(0, (sum, c) => sum + c.a) / colors.length;

    final avgColor = Color.fromARGB(
      (avgA * 255).round().clamp(0, 255),
      (avgR * 255).round().clamp(0, 255),
      (avgG * 255).round().clamp(0, 255),
      (avgB * 255).round().clamp(0, 255),
    );
    return Color.alphaBlend(avgColor, backdropColor);
  }

  /// Calculates typography contrast and styling dynamically depending on the background.
  /// If the effective background is bright (e.g. light wallpaper / light bubble),
  /// automatically returns high-contrast dark text and slate secondary colors.
  /// If dark, returns crisp white text and soft shadows.
  BubbleTextContrast getTextContrast({
    required bool isMe,
    Color backdropColor = const Color(0xFF0A0A0F),
  }) {
    final effectiveBg = getBubbleEffectiveBackgroundColor(
      isMe: isMe,
      backdropColor: backdropColor,
    );
    return contrastForBackground(effectiveBg);
  }

  /// Computes optimal typography contrast for any arbitrary background color.
  static BubbleTextContrast contrastForBackground(Color backgroundColor) {
    final luminance = backgroundColor.computeLuminance();
    final isLight = luminance > 0.45;

    if (isLight) {
      return const BubbleTextContrast(
        primaryTextColor: Color(0xFF14131D),
        secondaryTextColor: Color(0xFF555263),
        linkColor: Color(0xFFC2185B),
        textShadows: [
          Shadow(
            color: Color(0x33FFFFFF),
            blurRadius: 1.5,
            offset: Offset(0, 0.5),
          ),
        ],
        statusIconColor: Color(0xFF454256),
        isLightBackground: true,
      );
    } else {
      return const BubbleTextContrast(
        primaryTextColor: Colors.white,
        secondaryTextColor: Color(0xB8FFFFFF),
        linkColor: tabColor,
        textShadows: [
          Shadow(
            color: Color(0xCC000000),
            blurRadius: 3.0,
            offset: Offset(0, 1),
          ),
        ],
        statusIconColor: Colors.white70,
        isLightBackground: false,
      );
    }
  }
}

class ChatBubbleSettingsNotifier extends StateNotifier<ChatBubbleSettings> {
  static const String prefKey = 'chat_bubble_transparency_setting';

  ChatBubbleSettingsNotifier() : super(const ChatBubbleSettings()) {
    _loadFromPrefs();
  }

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey(prefKey)) {
        final val = prefs.getDouble(prefKey);
        if (val != null) {
          state = state.copyWith(transparency: val.clamp(0.0, 1.0));
        }
      }
    } catch (_) {}
  }

  Future<void> setTransparency(double value) async {
    final clamped = value.clamp(0.0, 1.0);
    state = state.copyWith(transparency: clamped);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(prefKey, clamped);
    } catch (_) {}
  }

  Future<void> resetToDefault() async {
    await setTransparency(ChatBubbleSettings.defaultTransparency);
  }
}

final chatBubbleSettingsProvider =
    StateNotifierProvider<ChatBubbleSettingsNotifier, ChatBubbleSettings>((ref) {
  return ChatBubbleSettingsNotifier();
});
