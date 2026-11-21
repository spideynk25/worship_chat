import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum WishCategory {
  birthday,
  deity,
  general,
}

class WishHelper {
  /// Determines if a message represents a celebratory or devotional wish.
  /// Checks explicit messageType ('wish') as well as recognized wish text patterns.
  static bool isWish({String? messageType, String? text}) {
    if (messageType == 'wish') return true;
    if (text == null) return false;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    final lower = trimmed.toLowerCase();

    // 1. Bowing / prayer emojis commonly used in worship deity wishes
    if (trimmed.contains('🙇') ||
        trimmed.contains('🙇‍♀️') ||
        trimmed.contains('🙇🏻‍♂️') ||
        trimmed.contains('🙏')) {
      if (lower.contains('mercy') ||
          lower.contains('live') ||
          lower.contains('praise') ||
          lower.contains('hail') ||
          lower.contains('goddess') ||
          lower.contains('queen') ||
          lower.contains('princess') ||
          lower.contains('aura') ||
          lower.contains('blossom') ||
          lower.contains('elfwitch') ||
          lower.contains('enchantress') ||
          lower.contains('wish')) {
        return true;
      }
    }

    // 2. Birthday wishes
    if (lower.startsWith('wishing ') ||
        lower.contains('happy birthday') ||
        lower.contains('royal birthday wish') ||
        lower.contains('birthday blessing')) {
      return true;
    }

    // 3. Deity / Sanctuary template patterns
    if (lower.contains('have mercy on us') ||
        lower.contains('long live supreme') ||
        lower.contains('long live golden blossom') ||
        lower.contains('be praised') ||
        lower.contains('hail queen') ||
        lower.contains('hail elfwitch') ||
        lower.contains('hail enchantress') ||
        lower.contains('hail first born princess') ||
        lower.contains('hail second born princess') ||
        lower.contains('hail third born princess') ||
        lower.contains('hail princess')) {
      return true;
    }

    // 4. Cake with wishes
    if (trimmed.contains('🎂') &&
        (lower.contains('birthday') ||
            lower.contains('wishing') ||
            lower.contains('bless') ||
            lower.contains('grace') ||
            lower.contains('joy'))) {
      return true;
    }

    return false;
  }

  /// Classifies the wish category for contextual icons, titles, and gradients.
  static WishCategory getWishCategory(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('birthday') ||
        lower.contains('🎂') ||
        lower.contains('cake') ||
        lower.contains('born')) {
      return WishCategory.birthday;
    }
    if (lower.contains('mercy') ||
        lower.contains('goddess') ||
        lower.contains('sanctum') ||
        lower.contains('hail') ||
        lower.contains('praised') ||
        lower.contains('supreme') ||
        lower.contains('queen') ||
        lower.contains('princess') ||
        lower.contains('aura elixiria') ||
        lower.contains('golden blossom')) {
      return WishCategory.deity;
    }
    return WishCategory.general;
  }

  /// Formatted badge title displayed at the top of the wish bubble.
  static String getWishHeaderBadge(String text) {
    final category = getWishCategory(text);
    switch (category) {
      case WishCategory.birthday:
        return 'ROYAL BIRTHDAY PROCLAMATION';
      case WishCategory.deity:
        return 'DIVINE SANCTUARY DEVOTION';
      case WishCategory.general:
        return 'ROYAL CELEBRATION WISH';
    }
  }

  /// Leading icon emoji for the wish badge.
  static String getWishBadgeIcon(String text) {
    final category = getWishCategory(text);
    switch (category) {
      case WishCategory.birthday:
        return '🎂';
      case WishCategory.deity:
        return '👑';
      case WishCategory.general:
        return '✨';
    }
  }

  /// Notification title for wishes (clean sender/group name without extra decorative labels).
  static String getNotificationTitle({
    required String senderName,
    String? groupName,
    required String text,
  }) {
    final hasGroup = groupName != null && groupName.trim().isNotEmpty;
    return hasGroup ? groupName : senderName;
  }

  /// Notification body formatted with distinctive royal cursive calligraphy.
  static String getNotificationBody({
    required String senderName,
    required String text,
  }) {
    return toRoyalScript(text.trim());
  }

  /// Converts alphanumeric text to majestic Unicode Mathematical Bold Script characters.
  /// Renders genuine royal cursive calligraphy across Android and iOS system notifications.
  static String toRoyalScript(String input) {
    final buffer = StringBuffer();
    for (final char in input.runes) {
      if (char >= 0x41 && char <= 0x5A) {
        // A-Z -> Mathematical Bold Script 𝓐-𝓩 (U+1D4D0)
        buffer.writeCharCode(0x1D4D0 + (char - 0x41));
      } else if (char >= 0x61 && char <= 0x7A) {
        // a-z -> Mathematical Bold Script 𝓪-𝔃 (U+1D4EA)
        buffer.writeCharCode(0x1D4EA + (char - 0x61));
      } else if (char >= 0x30 && char <= 0x39) {
        // 0-9 -> Mathematical Bold 𝟎-𝟗 (U+1D7CE)
        buffer.writeCharCode(0x1D7CE + (char - 0x30));
      } else {
        buffer.writeCharCode(char);
      }
    }
    return buffer.toString();
  }

  /// Backward-compatible alias for toRoyalScript
  static String toStylizedSerif(String input) => toRoyalScript(input);

  /// Stately Imperial Proclamation Arch bubble shape for wishing messages.
  /// Features a majestic cathedral arch at the top with a tailored royal decree base,
  /// immediately distinguishing it as an authentic royal proclamation tablet.
  static BorderRadius getBubbleRadius({
    required bool isMe,
    bool isSmallScreen = false,
  }) {
    final arch = isSmallScreen ? 22.0 : 26.0;
    final baseCurve = isSmallScreen ? 14.0 : 18.0;
    final anchor = isSmallScreen ? 4.0 : 5.0;

    if (isMe) {
      // Sent wish: Romanesque arch at top, tailored anchor at bottom-right
      return BorderRadius.only(
        topLeft: Radius.circular(arch),
        topRight: Radius.circular(arch),
        bottomLeft: Radius.circular(baseCurve),
        bottomRight: Radius.circular(anchor),
      );
    } else {
      // Received wish: Romanesque arch at top, tailored anchor at bottom-left
      return BorderRadius.only(
        topLeft: Radius.circular(arch),
        topRight: Radius.circular(arch),
        bottomLeft: Radius.circular(anchor),
        bottomRight: Radius.circular(baseCurve),
      );
    }
  }

  /// Inner contour radius matching the Imperial Proclamation Arch with a 3.5px inset
  /// for the embossed minted coin-edge relief frame.
  static BorderRadius getInnerBubbleRadius({
    required bool isMe,
    bool isSmallScreen = false,
  }) {
    final outer = getBubbleRadius(isMe: isMe, isSmallScreen: isSmallScreen);
    return BorderRadius.only(
      topLeft: Radius.circular((outer.topLeft.x - 3.5).clamp(2.0, 26.0)),
      topRight: Radius.circular((outer.topRight.x - 3.5).clamp(2.0, 26.0)),
      bottomLeft: Radius.circular((outer.bottomLeft.x - 3.5).clamp(2.0, 26.0)),
      bottomRight: Radius.circular((outer.bottomRight.x - 3.5).clamp(2.0, 26.0)),
    );
  }

  /// Aristocratic French Royal Court serif font with calligraphic swashes
  /// and crisp letterpress depth for antique royal gold contrast.
  static TextStyle getWishTextStyle({
    bool isSmallScreen = false,
    Color color = const Color(0xFFFFF9E8), // Royal Champagne Pearl
  }) {
    return GoogleFonts.cormorantGaramond(
      fontSize: isSmallScreen ? 16.5 : 18.0,
      fontStyle: FontStyle.italic,
      fontWeight: FontWeight.w700,
      color: color,
      height: 1.35,
      letterSpacing: 0.4,
      shadows: const [
        Shadow(
          color: Color(0x99000000), // Crisp dark letterpress depth
          blurRadius: 2,
          offset: Offset(0, 1),
        ),
      ],
    );
  }

  /// Unified Rich Antique Royal Gold gradient for all wish bubbles
  /// (mature, deep, and regal without blinding bright yellow glare).
  static LinearGradient getBubbleGradient({
    bool isMe = true,
    String? text,
    bool isSending = false,
    double pulse = 0.0,
  }) {
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isSending
          ? [
              Color.lerp(
                const Color(0xFFA17724).withValues(alpha: 0.55),
                const Color(0xFFBA8B2B).withValues(alpha: 0.65),
                pulse * 0.45,
              )!,
              Color.lerp(
                const Color(0xFF785412).withValues(alpha: 0.60),
                const Color(0xFF8F6516).withValues(alpha: 0.70),
                pulse * 0.45,
              )!,
              Color.lerp(
                const Color(0xFF503506).withValues(alpha: 0.68),
                const Color(0xFF634208).withValues(alpha: 0.76),
                pulse * 0.45,
              )!,
            ]
          : [
              const Color(0xFFA17724).withValues(alpha: 0.55), // Lustrous Antique Gold Sheen
              const Color(0xFF785412).withValues(alpha: 0.60), // Deep Burnished Aureate Gold
              const Color(0xFF503506).withValues(alpha: 0.68), // Imperial Dark Gold Base
            ],
    );
  }

  /// Refined Antique Gold hairline border for the wishing bubble
  /// (identical for both sender and receiver).
  static Border getBubbleBorder({
    String? text,
    bool isSending = false,
    double pulse = 0.0,
  }) {
    const baseColor = Color(0xFFC49530); // Refined Antique Gold rim

    return Border.all(
      color: isSending
          ? Color.lerp(baseColor.withValues(alpha: 0.55), const Color(0xFFDFB045), pulse)!
          : baseColor.withValues(alpha: 0.70),
      width: isSending ? (1.2 + 0.3 * pulse) : 1.25,
    );
  }

  /// Subtle royal halo depth with warm antique gold glow
  /// (soft and tasteful, avoiding blinding neon yellow auras).
  static List<BoxShadow> getBubbleShadow({
    String? text,
    bool isSending = false,
    double pulse = 0.0,
  }) {
    const glowColor = Color(0xFFC49530); // Warm antique gold

    return [
      BoxShadow(
        color: isSending
            ? Color.lerp(glowColor.withValues(alpha: 0.18), glowColor.withValues(alpha: 0.35), pulse)!
            : glowColor.withValues(alpha: 0.22),
        blurRadius: isSending ? (12.0 + 4.0 * pulse) : 12.0,
        spreadRadius: isSending ? (0.2 + 0.4 * pulse) : 0.3,
        offset: const Offset(0, 2),
      ),
      const BoxShadow(
        color: Color(0x3D000000),
        blurRadius: 8,
        offset: Offset(0, 2),
      ),
    ];
  }
}
