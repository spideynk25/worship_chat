import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worship_chat/features/settings/models/queendom_customization_model.dart';

/// Singleton service allowing synchronous access to customization state outside widget tree
class QueendomCustomizationService {
  static final QueendomCustomizationService instance = QueendomCustomizationService._internal();

  QueendomCustomizationService._internal();

  QueendomCustomizationState _state = const QueendomCustomizationState();

  QueendomCustomizationState get state => _state;

  void updateState(QueendomCustomizationState newState) {
    _state = newState;
  }

  bool categoryHasOtherFamilies(String position) {
    return _state.categoryHasOtherFamilies(position);
  }

  bool hasCategory(String position) {
    return _state.getCategoryByPosition(position) != null;
  }
}

/// StateNotifier managing Queendom Families and Categories (CRUD operations and persistence).
class QueendomCustomizationNotifier extends StateNotifier<QueendomCustomizationState> {
  static const String allFamiliesPrefKey = 'queendom_all_families_key';
  static const String allCategoriesPrefKey = 'queendom_all_categories_key';

  // Legacy keys for backwards-compatibility
  static const String legacyCustomFamiliesPrefKey = 'queendom_custom_families_key';
  static const String legacyCustomCategoriesPrefKey = 'queendom_custom_categories_key';

  QueendomCustomizationNotifier() : super(const QueendomCustomizationState()) {
    _loadFromPrefs();
  }

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 1. Load families (prefer allFamiliesPrefKey; fall back to legacy custom families)
      List<String> loadedFamilies;
      if (prefs.containsKey(allFamiliesPrefKey)) {
        final list = prefs.getStringList(allFamiliesPrefKey) ?? [];
        loadedFamilies = list.map((f) => f.trim()).where((f) => f.isNotEmpty).toList();
        if (loadedFamilies.isEmpty) {
          loadedFamilies = List.from(QueendomCategory.defaultFamilies);
        }
      } else if (prefs.containsKey(legacyCustomFamiliesPrefKey)) {
        final legacyCustom = prefs.getStringList(legacyCustomFamiliesPrefKey) ?? [];
        final cleanLegacy = legacyCustom
            .map((f) => f.trim())
            .where((f) => f.isNotEmpty && !QueendomCategory.defaultFamilies.contains(f))
            .toList();
        loadedFamilies = [...QueendomCategory.defaultFamilies, ...cleanLegacy];
      } else {
        loadedFamilies = List.from(QueendomCategory.defaultFamilies);
      }

      // 2. Load categories (prefer allCategoriesPrefKey; fall back to legacy custom categories)
      List<QueendomCategory> loadedCategories = [];
      if (prefs.containsKey(allCategoriesPrefKey)) {
        final rawList = prefs.getStringList(allCategoriesPrefKey) ?? [];
        for (final raw in rawList) {
          try {
            final map = jsonDecode(raw) as Map<String, dynamic>;
            final cat = QueendomCategory.fromJson(map);
            if (cat.position.isNotEmpty) {
              loadedCategories.add(cat);
            }
          } catch (_) {}
        }
        if (loadedCategories.isEmpty) {
          loadedCategories = List.from(QueendomCategory.defaultCategories);
        }
      } else if (prefs.containsKey(legacyCustomCategoriesPrefKey)) {
        final legacyRaw = prefs.getStringList(legacyCustomCategoriesPrefKey) ?? [];
        final customCats = <QueendomCategory>[];
        for (final raw in legacyRaw) {
          try {
            final map = jsonDecode(raw) as Map<String, dynamic>;
            final cat = QueendomCategory.fromJson(map);
            if (cat.position.isNotEmpty) {
              customCats.add(cat);
            }
          } catch (_) {}
        }
        loadedCategories = [...QueendomCategory.defaultCategories, ...customCats];
      } else {
        loadedCategories = List.from(QueendomCategory.defaultCategories);
      }

      state = state.copyWith(
        families: loadedFamilies,
        categories: loadedCategories,
      );
      QueendomCustomizationService.instance.updateState(state);
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FAMILY OPERATIONS
  // ─────────────────────────────────────────────────────────────────────────

  /// Adds a new Queendom family. Returns true if added, false if already exists or invalid.
  Future<({bool success, String message})> addFamily(String rawName) async {
    final name = _toTitleCase(rawName.trim());
    if (name.isEmpty) {
      return (success: false, message: 'Family name cannot be empty');
    }

    if (name.toLowerCase() == 'none') {
      return (success: false, message: 'Invalid family name');
    }

    // Check if already exists in active families
    final exists = state.families.any(
      (f) => f.toLowerCase() == name.toLowerCase(),
    );
    if (exists) {
      return (success: false, message: 'Family "$name" already exists');
    }

    final updatedFamilies = [...state.families, name];
    state = state.copyWith(families: updatedFamilies);
    QueendomCustomizationService.instance.updateState(state);

    await _saveFamilies(updatedFamilies);
    return (success: true, message: 'Family "$name" added successfully');
  }

  /// Edits an existing family name.
  Future<({bool success, String message})> editFamily({
    required String originalName,
    required String updatedName,
  }) async {
    final cleanOriginal = originalName.trim();
    final cleanUpdated = _toTitleCase(updatedName.trim());

    if (cleanUpdated.isEmpty) {
      return (success: false, message: 'Family name cannot be empty');
    }
    if (cleanUpdated.toLowerCase() == 'none') {
      return (success: false, message: 'Invalid family name');
    }

    final index = state.families.indexWhere(
      (f) => f.toLowerCase() == cleanOriginal.toLowerCase(),
    );
    if (index == -1) {
      return (success: false, message: 'Family "$cleanOriginal" not found');
    }

    // Check collision with another family
    if (cleanOriginal.toLowerCase() != cleanUpdated.toLowerCase()) {
      final duplicate = state.families.any(
        (f) => f.toLowerCase() == cleanUpdated.toLowerCase(),
      );
      if (duplicate) {
        return (success: false, message: 'Family "$cleanUpdated" already exists');
      }
    }

    final updatedFamilies = List<String>.from(state.families);
    updatedFamilies[index] = cleanUpdated;

    state = state.copyWith(families: updatedFamilies);
    QueendomCustomizationService.instance.updateState(state);

    await _saveFamilies(updatedFamilies);
    return (success: true, message: 'Family renamed to "$cleanUpdated"');
  }

  /// Deletes a family from active families.
  Future<({bool success, String message})> deleteFamily(String name) async {
    final target = name.trim();
    final exists = state.families.any((f) => f.toLowerCase() == target.toLowerCase());
    if (!exists) {
      return (success: false, message: 'Family "$target" does not exist');
    }

    final updatedFamilies = state.families
        .where((f) => f.toLowerCase() != target.toLowerCase())
        .toList();
    state = state.copyWith(families: updatedFamilies);
    QueendomCustomizationService.instance.updateState(state);

    await _saveFamilies(updatedFamilies);
    return (success: true, message: 'Family "$target" removed successfully');
  }

  /// Resets all families back to original 13 defaults.
  Future<({bool success, String message})> resetFamiliesToDefault() async {
    final defaultFams = List<String>.from(QueendomCategory.defaultFamilies);
    state = state.copyWith(families: defaultFams);
    QueendomCustomizationService.instance.updateState(state);

    await _saveFamilies(defaultFams);
    return (success: true, message: 'Families reset to Queendom defaults');
  }

  Future<void> _saveFamilies(List<String> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(allFamiliesPrefKey, list);
      // Also update legacy custom families key for backward compatibility
      final customList = list.where((f) => !QueendomCategory.defaultFamilies.contains(f)).toList();
      await prefs.setStringList(legacyCustomFamiliesPrefKey, customList);
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CATEGORY OPERATIONS
  // ─────────────────────────────────────────────────────────────────────────

  /// Adds a new Queendom Category / Position.
  Future<({bool success, String message})> addCategory(QueendomCategory newCategory) async {
    final cleanPos = _toTitleCase(newCategory.position.trim());
    final cleanTitle = newCategory.title.trim().isNotEmpty
        ? _toTitleCase(newCategory.title.trim())
        : cleanPos;

    if (cleanPos.isEmpty) {
      return (success: false, message: 'Category position cannot be empty');
    }

    if (cleanPos.toLowerCase() == 'none') {
      return (success: false, message: 'Invalid category position');
    }

    // Check if position already exists in active categories
    final exists = state.categories.any(
      (c) => c.position.toLowerCase() == cleanPos.toLowerCase(),
    );
    if (exists) {
      return (success: false, message: 'Category position "$cleanPos" already exists');
    }

    final categoryToSave = newCategory.copyWith(
      position: cleanPos,
      title: cleanTitle,
      isCustom: true,
    );

    final updatedCategories = [...state.categories, categoryToSave];
    state = state.copyWith(categories: updatedCategories);
    QueendomCustomizationService.instance.updateState(state);

    await _saveCategories(updatedCategories);
    return (success: true, message: 'Category "$cleanTitle" added successfully');
  }

  /// Edits an existing category (title, position, color, emoji, hasOtherFamilies).
  Future<({bool success, String message})> editCategory({
    required String originalPosition,
    required QueendomCategory updatedCategory,
  }) async {
    final cleanOriginal = originalPosition.trim();
    final cleanNewPos = _toTitleCase(updatedCategory.position.trim());
    final cleanNewTitle = updatedCategory.title.trim().isNotEmpty
        ? _toTitleCase(updatedCategory.title.trim())
        : cleanNewPos;

    if (cleanNewPos.isEmpty) {
      return (success: false, message: 'Category position cannot be empty');
    }
    if (cleanNewPos.toLowerCase() == 'none') {
      return (success: false, message: 'Invalid category position');
    }

    final index = state.categories.indexWhere(
      (c) => c.position.toLowerCase() == cleanOriginal.toLowerCase(),
    );
    if (index == -1) {
      return (success: false, message: 'Category "$cleanOriginal" not found');
    }

    // Check position conflict if renamed
    if (cleanOriginal.toLowerCase() != cleanNewPos.toLowerCase()) {
      final conflict = state.categories.any(
        (c) => c.position.toLowerCase() == cleanNewPos.toLowerCase(),
      );
      if (conflict) {
        return (success: false, message: 'Category position "$cleanNewPos" already exists');
      }
    }

    final existingCat = state.categories[index];
    final savedCat = updatedCategory.copyWith(
      position: cleanNewPos,
      title: cleanNewTitle,
      isCustom: existingCat.isCustom,
    );

    final updatedCategories = List<QueendomCategory>.from(state.categories);
    updatedCategories[index] = savedCat;

    state = state.copyWith(categories: updatedCategories);
    QueendomCustomizationService.instance.updateState(state);

    await _saveCategories(updatedCategories);
    return (success: true, message: 'Category "$cleanNewTitle" updated successfully');
  }

  /// Deletes a category from active categories.
  Future<({bool success, String message})> deleteCategory(String position) async {
    final target = position.trim();
    final exists = state.categories.any((c) => c.position.toLowerCase() == target.toLowerCase());
    if (!exists) {
      return (success: false, message: 'Category "$target" does not exist');
    }

    final updatedCategories = state.categories
        .where((c) => c.position.toLowerCase() != target.toLowerCase())
        .toList();
    state = state.copyWith(categories: updatedCategories);
    QueendomCustomizationService.instance.updateState(state);

    await _saveCategories(updatedCategories);
    return (success: true, message: 'Category "$target" removed successfully');
  }

  /// Resets all categories back to original 13 defaults.
  Future<({bool success, String message})> resetCategoriesToDefault() async {
    final defaultCats = List<QueendomCategory>.from(QueendomCategory.defaultCategories);
    state = state.copyWith(categories: defaultCats);
    QueendomCustomizationService.instance.updateState(state);

    await _saveCategories(defaultCats);
    return (success: true, message: 'Categories reset to Queendom defaults');
  }

  /// Resets both families and categories back to defaults.
  Future<({bool success, String message})> resetAllToDefault() async {
    await resetFamiliesToDefault();
    await resetCategoriesToDefault();
    return (success: true, message: 'All Queendom settings restored to defaults');
  }

  Future<void> _saveCategories(List<QueendomCategory> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final fullList = list.map((c) => jsonEncode(c.toJson())).toList();
      await prefs.setStringList(allCategoriesPrefKey, fullList);

      // Also update legacy custom categories key
      final customList = list.where((c) => c.isCustom).map((c) => jsonEncode(c.toJson())).toList();
      await prefs.setStringList(legacyCustomCategoriesPrefKey, customList);
    } catch (_) {}
  }

  static String _toTitleCase(String text) {
    if (text.isEmpty) return '';
    return text.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }
}

final queendomCustomizationProvider =
    StateNotifierProvider<QueendomCustomizationNotifier, QueendomCustomizationState>((ref) {
  return QueendomCustomizationNotifier();
});
