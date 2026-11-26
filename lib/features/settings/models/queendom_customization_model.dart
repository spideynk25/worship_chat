import 'package:flutter/material.dart';

/// Representation of a Queendom Category / Position.
class QueendomCategory {
  final String title;
  final String position;
  final Color color;
  final String emoji;
  final bool hasOtherFamilies;
  final bool isCustom;

  const QueendomCategory({
    required this.title,
    required this.position,
    required this.color,
    required this.emoji,
    this.hasOtherFamilies = false,
    this.isCustom = false,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'position': position,
        'color': color.toARGB32(),
        'emoji': emoji,
        'hasOtherFamilies': hasOtherFamilies,
        'isCustom': isCustom,
      };

  factory QueendomCategory.fromJson(Map<String, dynamic> json) {
    final colorVal = json['color'];
    final color = colorVal is int ? Color(colorVal) : const Color(0xFFFFD700);
    return QueendomCategory(
      title: json['title'] as String? ?? '',
      position: json['position'] as String? ?? '',
      color: color,
      emoji: json['emoji'] as String? ?? '',
      hasOtherFamilies: json['hasOtherFamilies'] as bool? ?? false,
      isCustom: json['isCustom'] as bool? ?? true,
    );
  }

  QueendomCategory copyWith({
    String? title,
    String? position,
    Color? color,
    String? emoji,
    bool? hasOtherFamilies,
    bool? isCustom,
  }) {
    return QueendomCategory(
      title: title ?? this.title,
      position: position ?? this.position,
      color: color ?? this.color,
      emoji: emoji ?? this.emoji,
      hasOtherFamilies: hasOtherFamilies ?? this.hasOtherFamilies,
      isCustom: isCustom ?? this.isCustom,
    );
  }

  /// Default 13 Queendom Categories with their authentic colors, emblems, and family behaviors
  static const List<QueendomCategory> defaultCategories = [
    QueendomCategory(
      title: 'Aura Elixiria Goddesses',
      position: 'Aura Elixiria',
      color: Color(0xFFFFD700),
      emoji: '',
      hasOtherFamilies: false,
    ),
    QueendomCategory(
      title: 'Core Supreme Goddesses',
      position: 'Core Supreme Goddess',
      color: Color(0xFF4A90E2),
      emoji: '',
      hasOtherFamilies: false,
    ),
    QueendomCategory(
      title: 'Supreme Goddesses',
      position: 'Supreme Goddess',
      color: Color(0xFFE74C3C),
      emoji: '',
      hasOtherFamilies: true,
    ),
    QueendomCategory(
      title: 'Golden Blossom Goddesses',
      position: 'Golden Blossom Goddess',
      color: Color(0xFFCFAB09),
      emoji: '',
      hasOtherFamilies: false,
    ),
    QueendomCategory(
      title: 'Goddesses',
      position: 'Goddess',
      color: Color(0xFF9B59B6),
      emoji: '',
      hasOtherFamilies: true,
    ),
    QueendomCategory(
      title: 'Demi Goddesses',
      position: 'Demi Goddess',
      color: Color(0xFFFF69B4),
      emoji: '',
      hasOtherFamilies: false,
    ),
    QueendomCategory(
      title: 'Dark Angels',
      position: 'Dark Angel',
      color: Color(0xFF4A3570),
      emoji: '',
      hasOtherFamilies: false,
    ),
    QueendomCategory(
      title: 'Queens',
      position: 'Queen',
      color: Color(0xFFFF6347),
      emoji: '',
      hasOtherFamilies: false,
    ),
    QueendomCategory(
      title: 'Elfwitches',
      position: 'Elfwitch',
      color: Color(0xFF2ECC71),
      emoji: '',
      hasOtherFamilies: true,
    ),
    QueendomCategory(
      title: 'Enchantresses',
      position: 'Enchantress',
      color: Color(0xFF1ABC9C),
      emoji: '',
      hasOtherFamilies: true,
    ),
    QueendomCategory(
      title: 'First Born Princesses',
      position: 'First Born Princess',
      color: Color(0xFF8E44AD),
      emoji: '',
      hasOtherFamilies: true,
    ),
    QueendomCategory(
      title: 'Second Born Princesses',
      position: 'Second Born Princess',
      color: Color(0xFFBA68C8),
      emoji: '',
      hasOtherFamilies: true,
    ),
    QueendomCategory(
      title: 'Third Born Princesses',
      position: 'Third Born Princess',
      color: Color(0xFFCE93D8),
      emoji: '',
      hasOtherFamilies: true,
    ),
  ];

  /// Default 13 Queendom Royal Families
  static const List<String> defaultFamilies = [
    'Aura',
    'Core',
    'Main',
    'Eternal',
    'Divine',
    'Wicked',
    'Lustra',
    'Rumia',
    'Erotica',
    'Elegant',
    'Elora',
    'Zyra',
    'Velisse',
  ];

  static const List<String> familyOrder = defaultFamilies;
}

/// State container for Queendom Customization (families & categories).
class QueendomCustomizationState {
  final List<String> families;
  final List<QueendomCategory> categories;

  const QueendomCustomizationState({
    this.families = QueendomCategory.defaultFamilies,
    this.categories = QueendomCategory.defaultCategories,
  });

  /// All families available for dropdowns, starting with 'None' followed by active families.
  List<String> get allFamilies {
    final list = <String>['None'];
    for (final fam in families) {
      if (!list.contains(fam)) list.add(fam);
    }
    return list;
  }

  /// All families in priority order for grouping and sorting (without 'None').
  List<String> get familyOrder => families;

  /// All categories (default + custom).
  List<QueendomCategory> get allCategories => categories;

  /// Custom categories (non-default or user-added)
  List<QueendomCategory> get customCategories =>
      categories.where((c) => c.isCustom).toList();

  /// Custom families (families added beyond default 13)
  List<String> get customFamilies =>
      families.where((f) => !QueendomCategory.defaultFamilies.contains(f)).toList();

  /// All positions for dropdowns, starting with 'None'.
  List<String> get allPositions {
    final list = <String>['None'];
    for (final cat in categories) {
      if (!list.contains(cat.position)) {
        list.add(cat.position);
      }
    }
    return list;
  }

  /// Checks whether a given category/position has multiple families.
  bool categoryHasOtherFamilies(String position) {
    if (position == 'None' || position.isEmpty) return false;
    for (final cat in categories) {
      if (cat.position.toLowerCase() == position.toLowerCase() ||
          cat.title.toLowerCase() == position.toLowerCase()) {
        return cat.hasOtherFamilies;
      }
    }
    // Fallback: check if standard position without other families
    const withoutFamilies = [
      'Aura Elixiria',
      'Aura Elixiria Goddess',
      'Core Supreme Goddess',
      'Golden Blossom Goddess',
      'Demi Goddess',
      'Dark Angel',
      'Queen',
    ];
    return !withoutFamilies.any((p) => p.toLowerCase() == position.toLowerCase());
  }

  /// Checks whether a category is one of the original 13 default categories
  bool isDefaultCategory(String position) {
    return QueendomCategory.defaultCategories.any(
      (c) => c.position.toLowerCase() == position.toLowerCase(),
    );
  }

  /// Checks whether a family is one of the original 13 default families
  bool isDefaultFamily(String name) {
    return QueendomCategory.defaultFamilies.any(
      (f) => f.toLowerCase() == name.toLowerCase(),
    );
  }

  /// Find category by its position or title.
  QueendomCategory? getCategoryByPosition(String position) {
    for (final cat in categories) {
      if (cat.position.toLowerCase() == position.toLowerCase() ||
          cat.title.toLowerCase() == position.toLowerCase()) {
        return cat;
      }
    }
    return null;
  }

  QueendomCustomizationState copyWith({
    List<String>? families,
    List<QueendomCategory>? categories,
    List<String>? customFamilies,
    List<QueendomCategory>? customCategories,
  }) {
    return QueendomCustomizationState(
      families: families ??
          (customFamilies != null
              ? [...QueendomCategory.defaultFamilies, ...customFamilies]
              : this.families),
      categories: categories ??
          (customCategories != null
              ? [...QueendomCategory.defaultCategories, ...customCategories]
              : this.categories),
    );
  }
}
