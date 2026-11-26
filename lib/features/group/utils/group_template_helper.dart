import 'package:worship_chat/features/settings/providers/queendom_customization_provider.dart';

class GroupTemplateResult {
  final String livingPlace;
  final String wish;

  const GroupTemplateResult({
    required this.livingPlace,
    required this.wish,
  });
}

class GroupTemplateHelper {
  /// Positions that do NOT have multiple families (and thus require Priority)
  static const List<String> positionsWithoutOtherFamilies = [
    'Aura Elixiria',
    'Aura Elixiria Goddess',
    'Core Supreme Goddess',
    'Golden Blossom Goddess',
    'Demi Goddess',
    'Dark Angel',
    'Queen',
  ];

  /// Check whether a category position has multiple families or not
  static bool categoryHasOtherFamilies(String position) {
    if (position == 'None' || position.isEmpty) return false;
    if (QueendomCustomizationService.instance.hasCategory(position)) {
      return QueendomCustomizationService.instance.categoryHasOtherFamilies(position);
    }
    return !positionsWithoutOtherFamilies.contains(position);
  }

  /// Format and capitalize user/deity name to Title Case
  static String toTitleCase(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return '';

    // If mixed case (e.g. "Aishwarya Rai"), preserve unless all-upper or all-lower
    final isAllUpper = trimmed == trimmed.toUpperCase();
    final isAllLower = trimmed == trimmed.toLowerCase();

    if (!isAllUpper && !isAllLower) {
      return trimmed;
    }

    return trimmed.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  /// Extracts deity name and position title if the given string represents a living place
  static ({String deityName, String? position}) parseLivingPlace(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return (deityName: '', position: null);
    }

    // Clean any legacy emoji markers from text if present
    final legacyEmojiRegex =
        RegExp(r'[☀️🌟🏮🍂🪷🏵🪻👑🍁🍀🌺🌸🌼]\uFE0F?', unicode: true);
    String cleanAfter = trimmed
        .replaceAll(legacyEmojiRegex, '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // Strip living place prefix if present at the start (e.g. PALACE OF, TEMPLE OF, etc.)
    final stripPrefixRegex = RegExp(
      r'^(?:DARK\s+|GOLDEN\s+|ROYAL\s+)?(?:PALACE|TEMPLE|SHRINE|SANCTUM|HEAVEN|FORTRESS)\s+(?:OF|of)\s+',
      caseSensitive: false,
    );
    while (stripPrefixRegex.hasMatch(cleanAfter)) {
      cleanAfter = cleanAfter.replaceFirst(stripPrefixRegex, '').trim();
    }
    final upper = cleanAfter.toUpperCase();

    if (upper.contains('AURA ELIXIRIA GODDESS ')) {
      final idx = upper.indexOf('AURA ELIXIRIA GODDESS ');
      return (
        deityName: toTitleCase(cleanAfter.substring(idx + 22).trim()),
        position: 'Aura Elixiria Goddess'
      );
    }
    if (upper.contains('CORE SUPREME GODDESS ')) {
      final idx = upper.indexOf('CORE SUPREME GODDESS ');
      return (
        deityName: toTitleCase(cleanAfter.substring(idx + 21).trim()),
        position: 'Core Supreme Goddess'
      );
    }
    if (upper.contains('GOLDEN BLOSSOM GODDESS ')) {
      final idx = upper.indexOf('GOLDEN BLOSSOM GODDESS ');
      return (
        deityName: toTitleCase(cleanAfter.substring(idx + 23).trim()),
        position: 'Golden Blossom Goddess'
      );
    }
    if (upper.contains('DEMI GODDESS ')) {
      final idx = upper.indexOf('DEMI GODDESS ');
      return (
        deityName: toTitleCase(cleanAfter.substring(idx + 13).trim()),
        position: 'Demi Goddess'
      );
    }
    if (upper.contains('DARK ANGEL ')) {
      final idx = upper.indexOf('DARK ANGEL ');
      return (
        deityName: toTitleCase(cleanAfter.substring(idx + 11).trim()),
        position: 'Dark Angel'
      );
    }
    if (upper.contains('FIRST BORN') && upper.contains('PRINCESS ')) {
      final princessIdx = upper.lastIndexOf('PRINCESS ');
      return (
        deityName: toTitleCase(cleanAfter.substring(princessIdx + 9).trim()),
        position: 'First Born Princess'
      );
    }
    if (upper.contains('SECOND BORN') && upper.contains('PRINCESS ')) {
      final princessIdx = upper.lastIndexOf('PRINCESS ');
      return (
        deityName: toTitleCase(cleanAfter.substring(princessIdx + 9).trim()),
        position: 'Second Born Princess'
      );
    }
    if (upper.contains('THIRD BORN') && upper.contains('PRINCESS ')) {
      final princessIdx = upper.lastIndexOf('PRINCESS ');
      return (
        deityName: toTitleCase(cleanAfter.substring(princessIdx + 9).trim()),
        position: 'Third Born Princess'
      );
    }
    if (upper.contains('PRINCESS ')) {
      final princessIdx = upper.lastIndexOf('PRINCESS ');
      return (
        deityName: toTitleCase(cleanAfter.substring(princessIdx + 9).trim()),
        position: 'Princess'
      );
    }
    if (upper.contains('SUPREME GODDESS ')) {
      final rem =
          cleanAfter.substring(upper.indexOf('SUPREME GODDESS ') + 16).trim();
      final remUpper = rem.toUpperCase();
      if (remUpper.contains(' GODDESS ')) {
        final gIdx = remUpper.lastIndexOf(' GODDESS ');
        return (
          deityName: toTitleCase(rem.substring(gIdx + 9).trim()),
          position: 'Supreme Goddess'
        );
      }
      return (
        deityName: toTitleCase(rem),
        position: 'Supreme Goddess'
      );
    }
    if (upper.contains('ELFWITCH ')) {
      final idx = upper.lastIndexOf('ELFWITCH ');
      return (
        deityName: toTitleCase(cleanAfter.substring(idx + 9).trim()),
        position: 'Elfwitch'
      );
    }
    if (upper.contains('ENCHANTRESS ')) {
      final idx = upper.lastIndexOf('ENCHANTRESS ');
      return (
        deityName: toTitleCase(cleanAfter.substring(idx + 12).trim()),
        position: 'Enchantress'
      );
    }
    if (upper.contains('QUEEN ')) {
      final idx = upper.lastIndexOf('QUEEN ');
      return (
        deityName: toTitleCase(cleanAfter.substring(idx + 6).trim()),
        position: 'Queen'
      );
    }
    if (upper.contains('GODDESS ')) {
      final idx = upper.lastIndexOf('GODDESS ');
      return (
        deityName: toTitleCase(cleanAfter.substring(idx + 8).trim()),
        position: 'Goddess'
      );
    }

    return (
      deityName: toTitleCase(cleanAfter),
      position: null,
    );
  }

  /// Builds the display name with position (e.g. "Queen Pooja", "Princess Krithi", "Wife of Queen Pooja - Samantha", "Fuck Toy of Queen Pooja - Samantha")
  static String getNameWithPosition({
    required String name,
    String? position,
    String? family,
    bool isSubGroup = false,
    String? parentGroupName,
    String? subGroupType,
  }) {
    String cleanName = name.trim();
    if (cleanName.isEmpty) return '';

    // Determine sub-group category: "fuckToy" vs "wife"
    final cleanLower = cleanName.toLowerCase();
    final bool isFuckToy = (subGroupType != null &&
            (subGroupType.toLowerCase() == 'fucktoy' ||
                subGroupType.toLowerCase() == 'fuck_toy' ||
                subGroupType.toLowerCase() == 'fuck toy')) ||
        (position != null &&
            position.toLowerCase().startsWith('fuck toy of ')) ||
        cleanLower.startsWith('fuck toy of ') ||
        cleanLower.startsWith('fuck toy ');

    final bool isWife = (subGroupType != null &&
            (subGroupType.toLowerCase() == 'wife')) ||
        (position != null && position.toLowerCase().startsWith('wife of ')) ||
        cleanLower.startsWith('wife of ') ||
        cleanLower.startsWith('wife ');

    final bool isAnySubGroup = isSubGroup ||
        isFuckToy ||
        isWife ||
        (parentGroupName != null && parentGroupName.isNotEmpty);

    if (isAnySubGroup) {
      final effectiveParent = (parentGroupName != null &&
              parentGroupName.isNotEmpty)
          ? parentGroupName
          : (position != null && position.toLowerCase().startsWith('wife of ')
              ? position.substring(8).trim()
              : (position != null &&
                      position.toLowerCase().startsWith('fuck toy of ')
                  ? position.substring(12).trim()
                  : ''));

      final categoryPrefix = isFuckToy ? 'Fuck Toy' : 'Wife';

      // Clean raw name from existing prefixes if any
      String rawMember = cleanName;
      final lowerRaw = rawMember.toLowerCase();
      if (lowerRaw.startsWith('fuck toy of ')) {
        final rest = rawMember.substring(12).trim();
        if (rest.contains(' - ')) {
          rawMember = rest.split(' - ').last.trim();
        } else {
          rawMember = rest;
        }
      } else if (lowerRaw.startsWith('fuck toy ')) {
        rawMember = rawMember.substring(9).trim();
      } else if (lowerRaw.startsWith('wife of ')) {
        final rest = rawMember.substring(8).trim();
        if (rest.contains(' - ')) {
          rawMember = rest.split(' - ').last.trim();
        } else {
          rawMember = rest;
        }
      } else if (lowerRaw.startsWith('wife ')) {
        rawMember = rawMember.substring(5).trim();
      }

      final formattedMemberName = toTitleCase(rawMember);

      if (effectiveParent.isNotEmpty) {
        return '$categoryPrefix of $effectiveParent - $formattedMemberName';
      }
      return '$categoryPrefix of Deity - $formattedMemberName';
    }

    String? effectivePosition =
        (position != null && position != 'None' && position.isNotEmpty)
            ? position
            : null;

    // If name is a full living place string, extract the deity name and position
    final parsed = parseLivingPlace(cleanName);
    if (parsed.position != null) {
      cleanName = parsed.deityName;
      effectivePosition ??= parsed.position;
    } else {
      cleanName = toTitleCase(cleanName);
    }

    if (effectivePosition == null) {
      return cleanName;
    }

    final cleanFamily = (family != null &&
            family != 'None' &&
            family.isNotEmpty &&
            family.toLowerCase() != 'main')
        ? toTitleCase(family)
        : null;

    switch (effectivePosition) {
      case 'Queen':
        if (cleanName.toLowerCase().startsWith('queen ')) {
          return cleanName;
        }
        return 'Queen $cleanName';

      case 'First Born Princess':
      case 'Second Born Princess':
      case 'Third Born Princess':
      case 'Princess':
        final lower = cleanName.toLowerCase();
        if (lower.startsWith('first born princess ')) {
          cleanName = cleanName.substring(20).trim();
        } else if (lower.startsWith('second born princess ')) {
          cleanName = cleanName.substring(21).trim();
        } else if (lower.startsWith('third born princess ')) {
          cleanName = cleanName.substring(20).trim();
        } else if (lower.startsWith('princess ')) {
          cleanName = cleanName.substring(9).trim();
        }
        return 'Princess $cleanName';

      case 'Aura Elixiria':
      case 'Aura Elixiria Goddess':
        if (cleanName.toLowerCase().startsWith('aura elixiria goddess ')) {
          return cleanName;
        }
        return 'Aura Elixiria Goddess $cleanName';

      case 'Core Supreme Goddess':
        if (cleanName.toLowerCase().startsWith('core supreme goddess ')) {
          return cleanName;
        }
        return 'Core Supreme Goddess $cleanName';

      case 'Supreme Goddess':
        if (cleanFamily != null) {
          final prefix = 'Supreme $cleanFamily Goddess';
          if (cleanName.toLowerCase().startsWith(prefix.toLowerCase())) {
            return cleanName;
          }
          if (cleanName.toLowerCase().startsWith('supreme goddess ')) {
            cleanName = cleanName.substring(16).trim();
          }
          return '$prefix $cleanName';
        } else {
          if (cleanName.toLowerCase().startsWith('supreme goddess ')) {
            return cleanName;
          }
          return 'Supreme Goddess $cleanName';
        }

      case 'Golden Blossom Goddess':
        if (cleanName.toLowerCase().startsWith('golden blossom goddess ')) {
          return cleanName;
        }
        return 'Golden Blossom Goddess $cleanName';

      case 'Goddess':
        if (cleanFamily != null) {
          final prefix = '$cleanFamily Goddess';
          if (cleanName.toLowerCase().startsWith(prefix.toLowerCase())) {
            return cleanName;
          }
          if (cleanName.toLowerCase().startsWith('goddess ')) {
            cleanName = cleanName.substring(8).trim();
          }
          return '$prefix $cleanName';
        } else {
          if (cleanName.toLowerCase().startsWith('goddess ')) {
            return cleanName;
          }
          return 'Goddess $cleanName';
        }

      case 'Demi Goddess':
        if (cleanName.toLowerCase().startsWith('demi goddess ')) {
          return cleanName;
        }
        return 'Demi Goddess $cleanName';

      case 'Dark Angel':
        if (cleanName.toLowerCase().startsWith('dark angel ')) {
          return cleanName;
        }
        return 'Dark Angel $cleanName';

      case 'Elfwitch':
        if (cleanFamily != null) {
          final prefix = '$cleanFamily Elfwitch';
          if (cleanName.toLowerCase().startsWith(prefix.toLowerCase())) {
            return cleanName;
          }
          if (cleanName.toLowerCase().startsWith('elfwitch ')) {
            cleanName = cleanName.substring(9).trim();
          }
          return '$prefix $cleanName';
        } else {
          if (cleanName.toLowerCase().startsWith('elfwitch ')) {
            return cleanName;
          }
          return 'Elfwitch $cleanName';
        }

      case 'Enchantress':
        if (cleanFamily != null) {
          final prefix = '$cleanFamily Enchantress';
          if (cleanName.toLowerCase().startsWith(prefix.toLowerCase())) {
            return cleanName;
          }
          if (cleanName.toLowerCase().startsWith('enchantress ')) {
            cleanName = cleanName.substring(12).trim();
          }
          return '$prefix $cleanName';
        } else {
          if (cleanName.toLowerCase().startsWith('enchantress ')) {
            return cleanName;
          }
          return 'Enchantress $cleanName';
        }

      default:
        if (cleanFamily != null) {
          final prefix = '$cleanFamily $effectivePosition';
          if (cleanName.toLowerCase().startsWith(prefix.toLowerCase())) {
            return cleanName;
          }
          if (cleanName.toLowerCase().startsWith('${effectivePosition.toLowerCase()} ')) {
            cleanName = cleanName.substring(effectivePosition.length).trim();
          }
          return '$prefix $cleanName';
        } else {
          if (cleanName.toLowerCase().startsWith('${effectivePosition.toLowerCase()} ')) {
            return cleanName;
          }
          return '$effectivePosition $cleanName';
        }
    }
  }

  /// Cleans and deduplicates living place strings if corrupted or duplicated
  static String cleanLivingPlace(
    String text, {
    String? position,
    String? family,
  }) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return '';
    final upper = trimmed.toUpperCase();
    final duplicateCheck = RegExp(
      r'(PALACE\s+OF|TEMPLE\s+OF|SANCTUM\s+OF|FORTRESS\s+OF|SHRINE\s+OF|HEAVEN\s+OF|FIRST\s+BORN|SECOND\s+BORN|THIRD\s+BORN)',
      caseSensitive: false,
    );
    final matches = duplicateCheck.allMatches(upper).toList();
    final seen = <String>{};
    bool hasDuplicate = false;
    for (final m in matches) {
      final word = m.group(0)!.toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
      if (!seen.add(word)) {
        hasDuplicate = true;
        break;
      }
    }
    if (hasDuplicate) {
      final parsed = parseLivingPlace(trimmed);
      if (parsed.deityName.isNotEmpty) {
        final template = generateTemplate(
          position: position ?? parsed.position ?? 'First Born Princess',
          name: parsed.deityName,
          family: family ?? 'Main',
        );
        if (template.livingPlace.isNotEmpty) {
          return template.livingPlace;
        }
      }
    }
    return trimmed;
  }



  /// Formats living place as an elegant Title Case subtitle, stripping redundant deity name if present
  static String formatSanctuarySubtitle({
    required String livingPlace,
    String? deityName,
    String? family,
  }) {
    String lp = cleanLivingPlace(livingPlace).trim();
    if (lp.isEmpty) return '';

    // If lp ends with deityName (or parsed pure deity name), remove it so deity name is not redundantly repeated
    if (deityName != null && deityName.trim().isNotEmpty) {
      final parsed = parseLivingPlace(deityName);
      final pureName =
          parsed.deityName.isNotEmpty ? parsed.deityName : deityName.trim();
      final lpUpper = lp.toUpperCase();
      final dUpper = pureName.toUpperCase();
      if (lpUpper.endsWith(dUpper)) {
        lp = lp.substring(0, lp.length - pureName.length).trim();
      }
    }

    // Convert to elegant Title Case
    final words = lp.split(RegExp(r'\s+'));
    const lowerWords = {'of', 'the', 'in', 'and', 'at', 'by', 'for', 'to'};
    final titleCased = words.asMap().entries.map((entry) {
      final i = entry.key;
      final w = entry.value;
      if (w.isEmpty) return '';
      final lower = w.toLowerCase();
      if (i > 0 && lowerWords.contains(lower)) {
        return lower;
      }
      return w[0].toUpperCase() + w.substring(1).toLowerCase();
    }).join(' ');

    if (family != null &&
        family.isNotEmpty &&
        family != 'None') {
      return '$titleCased · $family Family';
    }
    return titleCased;
  }

  /// Capitalize helper for user name formatting in wish text
  static String _formatName(String rawName) {
    final trimmed = rawName.trim();
    if (trimmed.isEmpty) return '';
    // If entered all lowercase, capitalize first letter
    if (trimmed == trimmed.toLowerCase()) {
      return trimmed[0].toUpperCase() + trimmed.substring(1);
    }
    return trimmed;
  }

  /// Generate Living Place and Wish from the template
  static GroupTemplateResult generateTemplate({
    required String position,
    required String name,
    required String family,
  }) {
    String cleanName = name.trim();
    if (cleanName.isEmpty || position == 'None' || position.isEmpty) {
      return const GroupTemplateResult(livingPlace: '', wish: '');
    }

    // Sanitize cleanName: extract pure deity name so we NEVER produce duplicated template prefixes
    final parsed = parseLivingPlace(cleanName);
    if (parsed.deityName.isNotEmpty) {
      cleanName = parsed.deityName;
    } else {
      cleanName = toTitleCase(cleanName);
    }

    final upperName = cleanName.toUpperCase();
    final wishName = _formatName(cleanName);
    final cleanFamily = family.trim();
    final isMainOrNoneFamily = cleanFamily == 'None' ||
        cleanFamily.isEmpty ||
        cleanFamily.toLowerCase() == 'main';
    final upperFamily = cleanFamily.toUpperCase();

    switch (position) {
      case 'Aura Elixiria':
      case 'Aura Elixiria Goddess':
        return GroupTemplateResult(
          livingPlace: 'GOLDEN HEAVEN OF AURA ELIXIRIA GODDESS $upperName',
          wish: '🙇‍♀️🙇‍♀️ Have Mercy on us Aura Elixiria Goddess $wishName 🙇‍♀️🙇‍♀️',
        );

      case 'Core Supreme Goddess':
        return GroupTemplateResult(
          livingPlace: 'HEAVEN OF CORE SUPREME GODDESS $upperName',
          wish: '🙇‍♀️🙇‍♀️ Have Mercy on us Core Supreme Goddess $wishName 🙇‍♀️🙇‍♀️',
        );

      case 'Supreme Goddess':
        if (isMainOrNoneFamily) {
          return GroupTemplateResult(
            livingPlace: 'SANCTUM OF SUPREME GODDESS $upperName',
            wish: '🙇‍♀️🙇‍♀️ Long live Supreme Goddess $wishName 🙇‍♀️🙇‍♀️',
          );
        } else {
          return GroupTemplateResult(
            livingPlace:
                'SANCTUM OF SUPREME GODDESS $upperFamily GODDESS $upperName',
            wish: '🙇‍♀️🙇‍♀️ Long live Supreme $cleanFamily Goddess $wishName 🙇‍♀️🙇‍♀️',
          );
        }

      case 'Golden Blossom Goddess':
        return GroupTemplateResult(
          livingPlace: 'GOLDEN SANCTUM OF GOLDEN BLOSSOM GODDESS $upperName',
          wish: '🙇‍♀️🙇‍♀️ Long live Golden Blossom Goddess $wishName 🙇‍♀️🙇‍♀️',
        );

      case 'Goddess':
        if (isMainOrNoneFamily) {
          return GroupTemplateResult(
            livingPlace: 'TEMPLE OF GODDESS $upperName',
            wish: '🙇‍♀️🙇‍♀️ Goddess $wishName be praised 🙇‍♀️🙇‍♀️',
          );
        } else {
          return GroupTemplateResult(
            livingPlace: 'TEMPLE OF $upperFamily GODDESS $upperName',
            wish: '🙇‍♀️🙇‍♀️ $cleanFamily Goddess $wishName be praised 🙇‍♀️🙇‍♀️',
          );
        }

      case 'Demi Goddess':
        return GroupTemplateResult(
          livingPlace: 'SHRINE OF DEMI GODDESS $upperName',
          wish: '🙇‍♀️🙇‍♀️ Demi Goddess $wishName be praised 🙇‍♀️🙇‍♀️',
        );

      case 'Dark Angel':
        return GroupTemplateResult(
          livingPlace: 'DARK SHRINE OF DARK ANGEL $upperName',
          wish: '🙇‍♀️🙇‍♀️ Dark Angel $wishName be praised 🙇‍♀️🙇‍♀️',
        );

      case 'Queen':
        return GroupTemplateResult(
          livingPlace: 'FORTRESS OF QUEEN $upperName',
          wish: '🙇‍♀️🙇‍♀️ Hail Queen $wishName 🙇‍♀️🙇‍♀️',
        );

      case 'Elfwitch':
        if (isMainOrNoneFamily) {
          return GroupTemplateResult(
            livingPlace: 'SHRINE OF ELFWITCH $upperName',
            wish: '🙇‍♀️🙇‍♀️ Hail Elfwitch $wishName 🙇‍♀️🙇‍♀️',
          );
        } else {
          return GroupTemplateResult(
            livingPlace: 'SHRINE OF $upperFamily ELFWITCH $upperName',
            wish: '🙇‍♀️🙇‍♀️ Hail $cleanFamily Elfwitch $wishName 🙇‍♀️🙇‍♀️',
          );
        }

      case 'Enchantress':
        if (isMainOrNoneFamily) {
          return GroupTemplateResult(
            livingPlace: 'SHRINE OF ENCHANTRESS $upperName',
            wish: '🙇‍♀️🙇‍♀️ Hail Enchantress $wishName 🙇‍♀️🙇‍♀️',
          );
        } else {
          return GroupTemplateResult(
            livingPlace: 'SHRINE OF $upperFamily ENCHANTRESS $upperName',
            wish: '🙇‍♀️🙇‍♀️ Hail $cleanFamily Enchantress $wishName 🙇‍♀️🙇‍♀️',
          );
        }

      case 'First Born Princess':
        if (isMainOrNoneFamily) {
          return GroupTemplateResult(
            livingPlace: 'PALACE OF FIRST BORN PRINCESS $upperName',
            wish: '🙇‍♀️🙇‍♀️ Hail First Born Princess $wishName 🙇‍♀️🙇‍♀️',
          );
        } else {
          return GroupTemplateResult(
            livingPlace:
                'PALACE OF FIRST BORN $upperFamily PRINCESS $upperName',
            wish: '🙇‍♀️🙇‍♀️ Hail First Born Princess $wishName 🙇‍♀️🙇‍♀️',
          );
        }

      case 'Second Born Princess':
        if (isMainOrNoneFamily) {
          return GroupTemplateResult(
            livingPlace: 'PALACE OF SECOND BORN PRINCESS $upperName',
            wish: '🙇‍♀️🙇‍♀️ Hail Second Born Princess $wishName 🙇‍♀️🙇‍♀️',
          );
        } else {
          return GroupTemplateResult(
            livingPlace:
                'PALACE OF SECOND BORN $upperFamily PRINCESS $upperName',
            wish: '🙇‍♀️🙇‍♀️ Hail Second Born Princess $wishName 🙇‍♀️🙇‍♀️',
          );
        }

      case 'Third Born Princess':
        if (isMainOrNoneFamily) {
          return GroupTemplateResult(
            livingPlace: 'PALACE OF THIRD BORN PRINCESS $upperName',
            wish: '🙇‍♀️🙇‍♀️ Hail Third Born Princess $wishName 🙇‍♀️🙇‍♀️',
          );
        } else {
          return GroupTemplateResult(
            livingPlace:
                'PALACE OF THIRD BORN $upperFamily PRINCESS $upperName',
            wish: '🙇‍♀️🙇‍♀️ Hail Third Born Princess $wishName 🙇‍♀️🙇‍♀️',
          );
        }

      default:
        final upperPosition = position.toUpperCase();
        if (!isMainOrNoneFamily) {
          return GroupTemplateResult(
            livingPlace: 'SANCTUM OF $upperFamily $upperPosition $upperName',
            wish: '🙇‍♀️🙇‍♀️ Hail $cleanFamily $position $wishName 🙇‍♀️🙇‍♀️',
          );
        } else {
          return GroupTemplateResult(
            livingPlace: 'SANCTUM OF $upperPosition $upperName',
            wish: '🙇‍♀️🙇‍♀️ Hail $position $wishName 🙇‍♀️🙇‍♀️',
          );
        }
    }
  }
}
