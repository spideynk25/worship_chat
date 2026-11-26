import 'package:flutter/material.dart';
import 'package:worship_chat/features/group/widgets/royal_3d_crown_widget.dart';
export 'package:worship_chat/features/group/widgets/royal_3d_crown_widget.dart';

/// Helper and widgets for rendering custom Queendom royal emblems instead of
/// generic Unicode phone emojis.
class QueendomEmblemHelper {
  static const Map<String, String> _positionToAsset = {
    'Aura Elixiria': 'assets/emojis/aura_elixiria.png',
    'Aura Elixiria Goddess': 'assets/emojis/aura_elixiria.png',
    'Aura Elixiria Goddesses': 'assets/emojis/aura_elixiria.png',
    'Aura Goddesses': 'assets/emojis/aura_elixiria.png',
    'Aura Goddess': 'assets/emojis/aura_elixiria.png',
    'Core Supreme': 'assets/emojis/core_supreme.png',
    'Core Supreme Goddess': 'assets/emojis/core_supreme.png',
    'Core Supreme Goddesses': 'assets/emojis/core_supreme.png',
    'Supreme': 'assets/emojis/supreme_goddess.png',
    'Supreme Goddess': 'assets/emojis/supreme_goddess.png',
    'Supreme Goddesses': 'assets/emojis/supreme_goddess.png',
    'Golden Blossom': 'assets/emojis/golden_blossom.png',
    'Golden Blossom Goddess': 'assets/emojis/golden_blossom.png',
    'Golden Blossom Goddesses': 'assets/emojis/golden_blossom.png',
    'Goddesses': 'assets/emojis/goddess.png',
    'Goddess': 'assets/emojis/goddess.png',
    'Demi': 'assets/emojis/demi_goddess.png',
    'Demi Goddess': 'assets/emojis/demi_goddess.png',
    'Demi Goddesses': 'assets/emojis/demi_goddess.png',
    'Dark Angels': 'assets/emojis/dark_angel.png',
    'Dark Angel': 'assets/emojis/dark_angel.png',
    'Queens': 'assets/emojis/queen.png',
    'Queen': 'assets/emojis/queen.png',
    'Elfwitches': 'assets/emojis/elfwitch.png',
    'Elfwitch': 'assets/emojis/elfwitch.png',
    'Enchantresses': 'assets/emojis/enchantress.png',
    'Enchantress': 'assets/emojis/enchantress.png',
    'First Born Princess': 'assets/emojis/first_born_princess.png',
    'First Born Princesses': 'assets/emojis/first_born_princess.png',
    'Second Born Princess': 'assets/emojis/second_born_princess.png',
    'Second Born Princesses': 'assets/emojis/second_born_princess.png',
    'Third Born Princess': 'assets/emojis/third_born_princess.png',
    'Third Born Princesses': 'assets/emojis/third_born_princess.png',
  };

  /// Checks whether a given position, category, or title represents a Wife or Fuck Toy role.
  static bool isWifeOrFuckToy(String? text) {
    if (text == null || text.trim().isEmpty) return false;
    final lower = text.trim().toLowerCase();
    if (lower == 'wife' ||
        lower == 'fuck toy' ||
        lower == 'fucktoy' ||
        lower == 'fuck_toy' ||
        lower == 'fuck toys' ||
        lower == 'fucktoys' ||
        lower == 'wives') {
      return true;
    }
    if (lower.startsWith('wife of ') ||
        lower.startsWith('wife ') ||
        lower.contains(' - wife') ||
        lower.contains('wife of ')) {
      return true;
    }
    if (lower.startsWith('fuck toy of ') ||
        lower.startsWith('fuck toy ') ||
        lower.startsWith('fucktoy of ') ||
        lower.startsWith('fucktoy ') ||
        lower.contains(' - fuck toy') ||
        lower.contains(' - fucktoy') ||
        lower.contains('fuck toy of ') ||
        lower.contains('fucktoy of ')) {
      return true;
    }
    return false;
  }

  /// Checks whether a given text specifically represents a Fuck Toy role.
  static bool isFuckToy(String? text) {
    if (text == null || text.trim().isEmpty) return false;
    final lower = text.trim().toLowerCase();
    return lower == 'fuck toy' ||
        lower == 'fucktoy' ||
        lower == 'fuck_toy' ||
        lower == 'fuck toys' ||
        lower == 'fucktoys' ||
        lower.startsWith('fuck toy of ') ||
        lower.startsWith('fuck toy ') ||
        lower.startsWith('fucktoy of ') ||
        lower.startsWith('fucktoy ') ||
        lower.contains(' - fuck toy') ||
        lower.contains(' - fucktoy') ||
        lower.contains('fuck toy of ') ||
        lower.contains('fucktoy of ');
  }

  /// Checks whether a given text specifically represents a Wife role.
  static bool isWife(String? text) {
    if (text == null || text.trim().isEmpty) return false;
    if (isFuckToy(text)) return false;
    final lower = text.trim().toLowerCase();
    return lower == 'wife' ||
        lower == 'wives' ||
        lower.startsWith('wife of ') ||
        lower.startsWith('wife ') ||
        lower.contains(' - wife') ||
        lower.contains('wife of ');
  }

  /// Returns the asset path for a position name or title directly using photos without emojis.
  static String? getAsset({String? position, String? emoji}) {
    if (isWifeOrFuckToy(position)) return null;
    if (position != null && _positionToAsset.containsKey(position)) {
      return _positionToAsset[position];
    }
    return null;
  }

  /// Extracts the matching emblem asset from a living place or title string directly
  /// using royal position titles without relying on flower emojis.
  static String? getAssetFromLivingPlace(String text) {
    if (isWifeOrFuckToy(text)) return null;
    final upper = text.toUpperCase();

    if (upper.contains('AURA ELIXIRIA')) {
      return _positionToAsset['Aura Elixiria'];
    }
    if (upper.contains('CORE SUPREME')) {
      return _positionToAsset['Core Supreme Goddess'];
    }
    if (upper.contains('GOLDEN BLOSSOM')) {
      return _positionToAsset['Golden Blossom Goddess'];
    }
    if (upper.contains('FIRST BORN') && upper.contains('PRINCESS')) {
      return _positionToAsset['First Born Princess'];
    }
    if (upper.contains('SECOND BORN') && upper.contains('PRINCESS')) {
      return _positionToAsset['Second Born Princess'];
    }
    if (upper.contains('THIRD BORN') && upper.contains('PRINCESS')) {
      return _positionToAsset['Third Born Princess'];
    }
    if (upper.contains('DEMI GODDESS') || upper.contains('DEMI')) {
      return _positionToAsset['Demi Goddess'];
    }
    if (upper.contains('DARK ANGEL')) {
      return _positionToAsset['Dark Angel'];
    }
    if (upper.contains('SUPREME GODDESS') || upper.contains('SUPREME')) {
      return _positionToAsset['Supreme Goddess'];
    }
    if (upper.contains('ELFWITCH')) {
      return _positionToAsset['Elfwitch'];
    }
    if (upper.contains('ENCHANTRESS')) {
      return _positionToAsset['Enchantress'];
    }
    if (upper.contains('QUEEN')) {
      return _positionToAsset['Queen'];
    }
    if (upper.contains('GODDESS')) {
      return _positionToAsset['Goddess'];
    }

    for (final entry in _positionToAsset.entries) {
      if (upper.contains(entry.key.toUpperCase())) {
        return entry.value;
      }
    }
    return null;
  }

  /// Extracts the matching emblem asset from a text string by checking living place,
  /// position names, or direct position titles.
  static String? getAssetFromText(String text) {
    if (isWifeOrFuckToy(text)) return null;
    final fromLivingPlace = getAssetFromLivingPlace(text);
    if (fromLivingPlace != null) return fromLivingPlace;
    final upper = text.toUpperCase();
    for (final entry in _positionToAsset.entries) {
      if (upper.contains(entry.key.toUpperCase())) {
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
    if (isWifeOrFuckToy(position) || isWifeOrFuckToy(livingPlace)) {
      return null;
    }
    String? asset = getAsset(position: position, emoji: emoji);
    if (asset == null && livingPlace != null && livingPlace.isNotEmpty) {
      asset =
          getAssetFromLivingPlace(livingPlace) ?? getAssetFromText(livingPlace);
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
          Positioned(top: -2, right: -2, child: overlayWidget),
        ],
      );
    }

    return badgeChild;
  }

  /// Strips known queendom emojis from a title or text string.
  static String cleanTitle(String text) {
    final emojiRegex = RegExp(
      r'[☀️🌟🏮🍂🪷🏵🪻👑🍁🍀🌺🌸🌼]\uFE0F?',
      unicode: true,
    );
    return text
        .replaceAll(emojiRegex, '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Builds a rich text widget where position emblems and family crests are seamlessly rendered
  /// as custom glowing royal images directly without using flower emojis.
  /// If a [family] or [fallbackFamily] is present, displays the Royal Family Crest at the end of the title.
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

    final cleanedText = cleanTitle(title);

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
      spans.add(TextSpan(text: cleanedText));
    } else if (leadingPosition != null &&
        leadingPosition.isNotEmpty &&
        leadingPosition != 'None') {
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.only(right: 3.5),
            child: QueendomEmblemWidget(
              position: leadingPosition,
              size: emblemSize,
            ),
          ),
        ),
      );
      spans.add(TextSpan(text: cleanedText));
    } else {
      // Check if title has a living place or position emblem to render directly
      final livingAsset =
          getAssetFromLivingPlace(title) ??
          getAssetFromLivingPlace(cleanedText) ??
          getAssetFromText(title) ??
          getAssetFromText(cleanedText);

      if (livingAsset != null) {
        // Check if title has a living place prefix ending with OF (e.g. "PALACE OF", "TEMPLE OF", "SANCTUM OF")
        final ofRegex = RegExp(
          r'^((?:DARK\s+|GOLDEN\s+|ROYAL\s+)?(?:PALACE|TEMPLE|SHRINE|SANCTUM|HEAVEN|FORTRESS)\s+(?:OF|of)\s+)(.*)$',
          caseSensitive: false,
        );
        final match = ofRegex.firstMatch(cleanedText);
        if (match != null) {
          final prefix = match.group(1)!;
          final rest = match.group(2)!;
          spans.add(TextSpan(text: prefix));
          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3.0),
                child: Image.asset(
                  livingAsset,
                  width: emblemSize,
                  height: emblemSize,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
          );
          spans.add(TextSpan(text: rest));
        } else {
          // Prepend emblem directly before text
          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.only(right: 3.5),
                child: Image.asset(
                  livingAsset,
                  width: emblemSize,
                  height: emblemSize,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
          );
          spans.add(TextSpan(text: cleanedText));
        }
      } else {
        spans.add(TextSpan(text: cleanedText));
      }
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

    if (spans.length == 1 && spans.first is TextSpan) {
      return Text(
        (spans.first as TextSpan).text ?? '',
        style: style,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow,
      );
    }

    return Text.rich(
      TextSpan(style: style, children: spans),
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
  final bool interactive3d;
  final bool enableInspect;

  const QueendomEmblemWidget({
    super.key,
    this.position,
    this.emoji,
    this.size = 24.0,
    this.fallback,
    this.interactive3d = false,
    this.enableInspect = false,
  });

  @override
  Widget build(BuildContext context) {
    if (QueendomEmblemHelper.isWifeOrFuckToy(position)) {
      return fallback ?? const SizedBox.shrink();
    }

    if (interactive3d) {
      return Royal3dCrownWidget(
        position: position,
        emoji: emoji,
        size: size,
        fallback: fallback,
        enableInspect: enableInspect,
      );
    }

    final asset = QueendomEmblemHelper.getAsset(position: position);
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
      if (RegExp(
        r'\b' + entry.key + r'\b',
        caseSensitive: false,
      ).hasMatch(text)) {
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
      if (!QueendomEmblemHelper.isWifeOrFuckToy(fallbackText)) {
        asset = getAssetFromText(fallbackText);
      }
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
          Positioned(top: -2, right: -2, child: overlayWidget),
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
      if (family != null && family!.isNotEmpty && family != 'None') {
        return fallback ??
            Icon(
              Icons.shield_rounded,
              size: size,
              color: const Color(0xFFFFD700),
            );
      }
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
