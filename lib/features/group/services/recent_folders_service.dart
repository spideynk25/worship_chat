import 'dart:convert';
import 'dart:developer';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Represents a folder or archive recently opened in FolderGalleryScreen.
class RecentFolderItem {
  final String path;
  final String name;
  final bool isZip;
  final DateTime lastOpened;

  const RecentFolderItem({
    required this.path,
    required this.name,
    required this.isZip,
    required this.lastOpened,
  });

  Map<String, dynamic> toMap() => {
    'path': path,
    'name': name,
    'isZip': isZip,
    'lastOpened': lastOpened.millisecondsSinceEpoch,
  };

  factory RecentFolderItem.fromMap(Map<String, dynamic> map) {
    return RecentFolderItem(
      path: map['path'] as String? ?? '',
      name: map['name'] as String? ?? '',
      isZip: map['isZip'] as bool? ?? false,
      lastOpened: DateTime.fromMillisecondsSinceEpoch(
        map['lastOpened'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  String toJson() => jsonEncode(toMap());

  factory RecentFolderItem.fromJson(String source) =>
      RecentFolderItem.fromMap(jsonDecode(source) as Map<String, dynamic>);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecentFolderItem &&
          runtimeType == other.runtimeType &&
          p.normalize(path) == p.normalize(other.path);

  @override
  int get hashCode => p.normalize(path).hashCode;
}

/// Persistent service managing recently opened storage folders and ZIP archives.
class RecentFoldersService {
  static const String _storageKey = 'worship_recent_folders_v1';
  static const int maxRecentFolders = 15;

  static SharedPreferences? _prefsOverride;

  @visibleForTesting
  static void setMockPrefs(SharedPreferences? prefs) {
    _prefsOverride = prefs;
  }

  static Future<SharedPreferences> _getPrefs() async {
    return _prefsOverride ?? await SharedPreferences.getInstance();
  }

  /// Retrieves the list of recently opened folders, ordered newest first.
  static Future<List<RecentFolderItem>> getRecentFolders() async {
    try {
      final prefs = await _getPrefs();
      final rawList = prefs.getStringList(_storageKey) ?? [];
      final List<RecentFolderItem> items = [];

      for (final raw in rawList) {
        try {
          if (raw.startsWith('{')) {
            final item = RecentFolderItem.fromJson(raw);
            if (item.path.trim().isNotEmpty) {
              items.add(item);
            }
          } else {
            // Support legacy raw path entries if present
            final trimmed = raw.trim();
            if (trimmed.isNotEmpty) {
              final isZip = trimmed.toLowerCase().endsWith('.zip');
              final name = isZip
                  ? p.basenameWithoutExtension(trimmed)
                  : p.basename(trimmed);
              items.add(
                RecentFolderItem(
                  path: trimmed,
                  name: name.isEmpty ? trimmed : name,
                  isZip: isZip,
                  lastOpened: DateTime.now(),
                ),
              );
            }
          }
        } catch (e) {
          log('RecentFoldersService: parsing error for "$raw": $e');
        }
      }

      return items;
    } catch (e) {
      log('RecentFoldersService: getRecentFolders error: $e');
      return [];
    }
  }

  /// Adds or updates a folder/archive in the recent list.
  static Future<void> addRecentFolder(String rawPath) async {
    final cleanPath = rawPath.trim();
    if (cleanPath.isEmpty) return;

    try {
      final prefs = await _getPrefs();
      final current = await getRecentFolders();
      final isZip = cleanPath.toLowerCase().endsWith('.zip');
      final name = isZip
          ? p.basenameWithoutExtension(cleanPath)
          : p.basename(cleanPath);

      // Remove any prior entry matching this normalized path
      current.removeWhere(
        (item) => p.normalize(item.path) == p.normalize(cleanPath),
      );

      // Insert at the front as the most recently opened
      current.insert(
        0,
        RecentFolderItem(
          path: cleanPath,
          name: name.isEmpty ? cleanPath : name,
          isZip: isZip,
          lastOpened: DateTime.now(),
        ),
      );

      // Cap at maximum entries
      final trimmed = current.take(maxRecentFolders).toList();
      final serialized = trimmed.map((e) => e.toJson()).toList();
      await prefs.setStringList(_storageKey, serialized);
    } catch (e) {
      log('RecentFoldersService: addRecentFolder error: $e');
    }
  }

  /// Removes a folder from the recents list.
  static Future<void> removeRecentFolder(String rawPath) async {
    try {
      final prefs = await _getPrefs();
      final current = await getRecentFolders();
      current.removeWhere(
        (item) => p.normalize(item.path) == p.normalize(rawPath.trim()),
      );
      final serialized = current.map((e) => e.toJson()).toList();
      await prefs.setStringList(_storageKey, serialized);
    } catch (e) {
      log('RecentFoldersService: removeRecentFolder error: $e');
    }
  }

  /// Clears all stored recent folders.
  static Future<void> clearRecentFolders() async {
    try {
      final prefs = await _getPrefs();
      await prefs.remove(_storageKey);
    } catch (e) {
      log('RecentFoldersService: clearRecentFolders error: $e');
    }
  }
}

