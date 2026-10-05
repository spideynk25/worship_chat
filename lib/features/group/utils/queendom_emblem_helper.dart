import 'package:flutter/material.dart';

/// Helper and widgets for rendering custom Queendom royal emblems instead of
/// generic Unicode phone emojis.
class QueendomEmblemHelper {
  static const Map<String, String> _positionToAsset = {
    'Aura Elixiria': 'assets/emojis/aura_elixiria.png',
    'Aura Elixiria Goddess': 'assets/emojis/aura_elixiria.png',
    'Aura Goddesses': 'assets/emojis/aura_elixiria.png',
    'Core Supreme': 'assets/emojis/core_supreme.png',
    'Core Supreme Goddess': 'assets/emojis/core_supreme.png',
    'Supreme': 'assets/emojis/supreme_goddess.png',
    'Supreme Goddess': 'assets/emojis/supreme_goddess.png',
    'Golden Blossom': 'assets/emojis/golden_blossom.png',
    'Golden Blossom Goddess': 'assets/emojis/golden_blossom.png',
    'Goddesses': 'assets/emojis/goddess.png',
    'Goddess': 'assets/emojis/goddess.png',
    'Demi': 'assets/emojis/demi_goddess.png',
    'Demi Goddess': 'assets/emojis/demi_goddess.png',
    'Dark Angels': 'assets/emojis/dark_angel.png',
    'Dark Angel': 'assets/emojis/dark_angel.png',
    'Queens': 'assets/emojis/queen.png',
    'Queen': 'assets/emojis/queen.png',
    'Elfwitches': 'assets/emojis/elfwitch.png',
    'Elfwitch': 'assets/emojis/elfwitch.png',
    'Enchantresses': 'assets/emojis/enchantress.png',
    'Enchantress': 'assets/emojis/enchantress.png',
    'First Born Princess': 'assets/emojis/first_born_princess.png',
    'Second Born Princess': 'assets/emojis/second_born_princess.png',
    'Third Born Princess': 'assets/emojis/third_born_princess.png',
  };

  static const Map<String, String> _emojiToAsset = {
    '☀️': 'assets/emojis/aura_elixiria.png',
    '🌟': 'assets/emojis/core_supreme.png',
    '🏮': 'assets/emojis/supreme_goddess.png',
    '🍂': 'assets/emojis/golden_blossom.png',
    '🪷': 'assets/emojis/goddess.png',
    '🏵️': 'assets/emojis/demi_goddess.png',
    '🏵': 'assets/emojis/demi_goddess.png',
    '🪻': 'assets/emojis/dark_angel.png',
    '👑': 'assets/emojis/queen.png',
    '🍁': 'assets/emojis/elfwitch.png',
    '🍀': 'assets/emojis/enchantress.png',
    '🌺': 'assets/emojis/first_born_princess.png',
    '🌸': 'assets/emojis/second_born_princess.png',
    '🌼': 'assets/emojis/third_born_princess.png',
  };

  /// Returns the asset path for a position name or emoji, if found.
  static String? getAsset({String? position, String? emoji}) {
    if (position != null && _positionToAsset.containsKey(position)) {
      return _positionToAsset[position];
    }
    if (emoji != null) {
      final clean = emoji.replaceAll('\uFE0F', '');
      return _emojiToAsset[emoji] ?? _emojiToAsset[clean];
    }
    return null;
  }

  /// Extracts the matching emblem asset from a living place string (e.g. 'PALACE OF 🌺 FIRST BORN PRINCESS ...')
  static String? getAssetFromLivingPlace(String text) {
    final emojiRegex =
        RegExp(r'[☀️🌟🏮🍂🪷🏵🪻👑🍁🍀🌺🌸🌼]\uFE0F?', unicode: true);
    final match = emojiRegex.firstMatch(text);
    if (match != null) {
      final raw = match.group(0)!;
      final clean = raw.replaceAll('\uFE0F', '');
      return _emojiToAsset[raw] ?? _emojiToAsset[clean];
    }
    return null;
  }

  /// Extracts the matching emblem asset from a text string by checking living place,
  /// position names, and emoji codes.
  static String? getAssetFromText(String text) {
    final fromLivingPlace = getAssetFromLivingPlace(text);
    if (fromLivingPlace != null) return fromLivingPlace;
    for (final entry in _positionToAsset.entries) {
      if (text.contains(entry.key)) {
        return entry.value;
      }
    }
    return null;
  }

  /// Builds a glowing circular royal badge displaying the Queendom position emblem
  /// outside the avatar/profile circle.
  static Widget? buildEmblemBadge({
    String? position,
    String? emoji,
    String? livingPlace,
    required Color accentColor,
    double size = 16.0,
    Widget? overlayWidget,
  }) {
    String? asset = getAsset(position: position, emoji: emoji);
    if (asset == null && livingPlace != null && livingPlace.isNotEmpty) {
      asset = getAssetFromLivingPlace(livingPlace) ?? getAssetFromText(livingPlace);
    }
    if (asset == null) return null;

    final badgeChild = Container(
      padding: EdgeInsets.all((size * 0.16).clamp(2.0, 4.0)),
      decoration: BoxDecoration(
        color: const Color(0xFF141322),
        shape: BoxShape.circle,
        border: Border.all(
          color: accentColor.withValues(alpha: 0.95),
          width: (size * 0.09).clamp(1.2, 2.2),
        ),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.55),
            blurRadius: (size * 0.35).clamp(4.0, 10.0),
            spreadRadius: 1.0,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.7),
            blurRadius: 4.0,
            offset: const Offset(0, 1.5),
          ),
        ],
      ),
      child: Image.asset(
        asset,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      ),
    );

    if (overlayWidget != null) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          badgeChild,
          Positioned(
            top: -2,
            right: -2,
            child: overlayWidget,
          ),
        ],
      );
    }

    return badgeChild;
  }

  /// Strips known queendom emojis from a title or text string.
  static String cleanTitle(String text) {
    final emojiRegex =
        RegExp(r'[☀️🌟🏮🍂🪷🏵🪻👑🍁🍀🌺🌸🌼]\uFE0F?', unicode: true);
    return text
        .replaceAll(emojiRegex, '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Builds a rich text widget where known Unicode emojis are seamlessly replaced
  /// with their corresponding custom glowing emblem image, and optionally prepends
  /// a leading position emblem or leading widget inline.
  /// If a [family] or [fallbackFamily] is present, displays the Royal Family Crest
  /// at the end of the title.
  static Widget buildRichTitle({
    required String title,
    required TextStyle style,
    String? family,
    String? fallbackFamily,
    String? leadingPosition,
    Widget? leadingWidget,
    double emblemSize = 18.0,
    double? familyEmblemSize,
    TextAlign textAlign = TextAlign.start,
    int? maxLines,
    TextOverflow? overflow,
  }) {
    final spans = <InlineSpan>[];
    final effectiveFamilySize = familyEmblemSize ?? emblemSize;
    final cleanFamily =
        (family != null && family.isNotEmpty && family != 'None')
            ? family
            : fallbackFamily;
    final familyAsset = cleanFamily != null
        ? QueendomFamilyEmblemHelper.getAsset(cleanFamily)
        : null;

    if (leadingWidget != null) {
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.only(right: 4.5),
            child: leadingWidget,
          ),
        ),
      );
    } else if (leadingPosition != null &&
        leadingPosition.isNotEmpty &&
        leadingPosition != 'None') {
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.only(right: 3.0),
            child: QueendomEmblemWidget(
              position: leadingPosition,
              size: emblemSize,
            ),
          ),
        ),
      );
    }

    final emojiRegex =
        RegExp(r'[☀️🌟🏮🍂🪷🏵🪻👑🍁🍀🌺🌸🌼]\uFE0F?', unicode: true);
    final matches = emojiRegex.allMatches(title);
    if (matches.isEmpty && spans.isEmpty && familyAsset == null) {
      return Text(
        title,
        style: style,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow,
      );
    }

    int lastEnd = 0;

    for (final match in matches) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: title.substring(lastEnd, match.start)));
      }

      final rawEmoji = match.group(0)!;
      final cleanEmoji = rawEmoji.replaceAll('\uFE0F', '');
      final asset = _emojiToAsset[rawEmoji] ?? _emojiToAsset[cleanEmoji];

      if (asset != null) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.5),
              child: Image.asset(
                asset,
                width: emblemSize,
                height: emblemSize,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Text(rawEmoji, style: style),
              ),
            ),
          ),
        );
      } else {
        spans.add(TextSpan(text: rawEmoji));
      }
      lastEnd = match.end;
    }

    if (lastEnd < title.length) {
      spans.add(TextSpan(text: title.substring(lastEnd)));
    }

    // Place the family emblem at the end of the title
    if (familyAsset != null) {
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.only(left: 4.5),
            child: Image.asset(
              familyAsset,
              width: effectiveFamilySize,
              height: effectiveFamilySize,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        ),
      );
    }

    return Text.rich(
      TextSpan(
        style: style,
        children: spans,
      ),
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}

/// A reusable widget that renders a custom Queendom Emblem
class QueendomEmblemWidget extends StatelessWidget {
  final String? position;
  final String? emoji;
  final double size;
  final Widget? fallback;

  const QueendomEmblemWidget({
    super.key,
    this.position,
    this.emoji,
    this.size = 24.0,
    this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    final asset = QueendomEmblemHelper.getAsset(position: position, emoji: emoji);
    if (asset == null) {
      return fallback ??
          (emoji != null
              ? Text(emoji!, style: TextStyle(fontSize: size * 0.8))
              : const SizedBox.shrink());
    }

    return Image.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) =>
          fallback ??
          (emoji != null
              ? Text(emoji!, style: TextStyle(fontSize: size * 0.8))
              : const SizedBox.shrink()),
    );
  }
}

/// Helper and widgets for rendering custom Queendom Royal House Family Crests
class QueendomFamilyEmblemHelper {
  static const Map<String, String> _familyToAsset = {
    'Aura': 'assets/emojis/family_aura.png',
    'Core': 'assets/emojis/family_core.png',
    'Main': 'assets/emojis/family_main.png',
    'Eternal': 'assets/emojis/family_eternal.png',
    'Divine': 'assets/emojis/family_divine.png',
    'Wicked': 'assets/emojis/family_wicked.png',
    'Lustra': 'assets/emojis/family_lustra.png',
    'Rumia': 'assets/emojis/family_rumia.png',
    'Erotica': 'assets/emojis/family_erotica.png',
    'Elegant': 'assets/emojis/family_elegant.png',
    'Elora': 'assets/emojis/family_elora.png',
    'Zyra': 'assets/emojis/family_zyra.png',
    'Velisse': 'assets/emojis/family_velisse.png',
  };


  /// Returns the asset path for a family name, case-insensitively.
  static String? getAsset(String? family) {
    if (family == null || family.isEmpty || family == 'None') return null;
    final trimmed = family.trim();
    if (_familyToAsset.containsKey(trimmed)) {
      return _familyToAsset[trimmed];
    }
    final lower = trimmed.toLowerCase();
    for (final entry in _familyToAsset.entries) {
      if (entry.key.toLowerCase() == lower) {
        return entry.value;
      }
    }
    return null;
  }

  /// Extracts the matching family crest asset from a text string by checking known family names.
  static String? getAssetFromText(String text) {
    if (text.isEmpty) return null;
    for (final entry in _familyToAsset.entries) {
      if (RegExp(r'\b' + entry.key + r'\b', caseSensitive: false)
          .hasMatch(text)) {
        return entry.value;
      }
    }
    return null;
  }

  /// Builds a glowing circular royal badge displaying the Queendom Family Crest
  /// outside the avatar/profile circle.
  static Widget? buildFamilyEmblemBadge({
    String? family,
    String? fallbackText,
    required Color accentColor,
    double size = 16.0,
    Widget? overlayWidget,
  }) {
    String? asset = getAsset(family);
    if (asset == null && fallbackText != null && fallbackText.isNotEmpty) {
      asset = getAssetFromText(fallbackText);
    }
    if (asset == null) return null;

    final badgeChild = Container(
      padding: EdgeInsets.all((size * 0.16).clamp(2.0, 4.0)),
      decoration: BoxDecoration(
        color: const Color(0xFF141322),
        shape: BoxShape.circle,
        border: Border.all(
          color: accentColor.withValues(alpha: 0.95),
          width: (size * 0.09).clamp(1.2, 2.2),
        ),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.55),
            blurRadius: (size * 0.35).clamp(4.0, 10.0),
            spreadRadius: 1.0,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.7),
            blurRadius: 4.0,
            offset: const Offset(0, 1.5),
          ),
        ],
      ),
      child: Image.asset(
        asset,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      ),
    );

    if (overlayWidget != null) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          badgeChild,
          Positioned(
            top: -2,
            right: -2,
            child: overlayWidget,
          ),
        ],
      );
    }

    return badgeChild;
  }
}

/// A reusable widget that renders a custom Queendom Family Crest
class QueendomFamilyEmblemWidget extends StatelessWidget {
  final String? family;
  final double size;
  final Widget? fallback;

  const QueendomFamilyEmblemWidget({
    super.key,
    required this.family,
    this.size = 14.0,
    this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    final asset = QueendomFamilyEmblemHelper.getAsset(family);
    if (asset == null) {
      return fallback ?? const SizedBox.shrink();
    }

    return Image.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => fallback ?? const SizedBox.shrink(),
    );
  }
}

