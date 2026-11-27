import 'dart:developer';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/utils/app_capabilities.dart';
import 'package:worship_chat/common/utils/google_lens_service.dart';
import 'package:worship_chat/common/utils/utils.dart';
import 'package:worship_chat/common/widgets/photo_text_remover_sheet.dart';
import 'package:worship_chat/common/widgets/set_as_profile_pic_sheet.dart';
import 'package:worship_chat/common/widgets/wallpaper_widget_sheet.dart';
import 'package:worship_chat/features/chat/widgets/forward_message_sheet.dart';
import 'package:worship_chat/features/group/screens/slide_show_screen.dart';
import 'package:worship_chat/features/group/services/recent_folders_service.dart';
import 'package:worship_chat/features/group/widgets/folder_picker_bottom_sheet.dart';
import 'package:worship_chat/features/group/widgets/gallery_navigation_controls.dart';
import 'package:worship_chat/models/group_gallery_image.dart';

/// Sanitizes and resolves filesystem paths returned by Android Storage Access Framework (SAF),
/// iOS document pickers, or desktop file dialogs.
/// Fixes Android issues with `raw:`, `/storage/raw/`, URL encoding (`%20`), and `content://` URIs.
String resolveActualDirectoryPath(String rawPath) {
  var path = rawPath.trim();
  if (path.isEmpty) return path;

  // 1. Decode URL encoding (%20, %3A, %2F, etc.)
  try {
    path = Uri.decodeFull(path);
  } catch (_) {}

  // 2. Strip file:// scheme
  if (path.startsWith('file://')) {
    try {
      path = Uri.parse(path).toFilePath();
    } catch (_) {
      path = path.replaceFirst('file://', '');
    }
  }

  // 3. Android SAF treeUri cleanups
  final emulatedIdx = path.indexOf('/storage/emulated/');
  if (emulatedIdx != -1) {
    path = path.substring(emulatedIdx);
  } else {
    final primaryIdx = path.indexOf('primary:');
    if (primaryIdx != -1) {
      final sub = path.substring(primaryIdx + 'primary:'.length);
      path = '/storage/emulated/0/$sub';
    } else {
      final storageMatch =
          RegExp(r'/storage/[A-Za-z0-9_-]+/[^:]*').firstMatch(path);
      if (storageMatch != null &&
          !storageMatch.group(0)!.contains('/storage/raw')) {
        path = storageMatch.group(0)!;
      } else {
        path = path.replaceFirst(RegExp(r'^.*?/storage/raw[:/]*'), '/');
        path = path.replaceFirst(RegExp(r'^raw:/*'), '/');
      }
    }
  }

  // 4. Normalize path separators
  path = p.normalize(path);

  // If path exists on filesystem directly, return it
  if (Directory(path).existsSync() || File(path).existsSync()) {
    return path;
  }

  // Fallback checks for standard Android Download / WorshipChat paths
  final candidateDownload = Directory('/storage/emulated/0/Download/$path');
  if (candidateDownload.existsSync()) return candidateDownload.path;

  final candidateWorship =
      Directory('/storage/emulated/0/Download/WorshipChat/$path');
  if (candidateWorship.existsSync()) return candidateWorship.path;

  return path;
}

/// Opens a local device storage folder and presents photos with the same
/// layout, shuffle, and slideshow features as the online group gallery.
class FolderGalleryScreen extends ConsumerStatefulWidget {
  final String? initialFolderPath;
  final Color accentColor;

  const FolderGalleryScreen({
    super.key,
    this.initialFolderPath,
    this.accentColor = tabColor,
  });

  /// Opens [FolderGalleryScreen] directly, showing recent folders if no folder was selected yet.
  static void open(
    BuildContext context, {
    Color accentColor = tabColor,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FolderGalleryScreen(
          accentColor: accentColor,
        ),
      ),
    );
  }

  /// Opens the folder/archive picker options bottom sheet so the user can
  /// choose between a normal folder, a ZIP archive, or recently opened items.
  static Future<void> showPickerOptions(
    BuildContext context, {
    Color accentColor = tabColor,
  }) {
    return FolderPickerBottomSheet.show(context, accentColor: accentColor);
  }

  /// Opens the native folder picker and pushes [FolderGalleryScreen] on success.
  static Future<void> openFolder(
    BuildContext context, {
    Color accentColor = tabColor,
  }) async {
    try {
      final selectedPath = await FilePicker.getDirectoryPath(
        dialogTitle: 'Select Photos Folder',
      );
      if (selectedPath == null || selectedPath.trim().isEmpty) return;
      if (!context.mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FolderGalleryScreen(
            initialFolderPath: selectedPath,
            accentColor: accentColor,
          ),
        ),
      );
    } catch (e) {
      log('FolderGalleryScreen.openFolder error: $e');
      if (context.mounted) {
        showSnackBar(
          context: context,
          content: 'Could not access device folder: $e',
        );
      }
    }
  }

  /// Opens a ZIP archive directly and pushes [FolderGalleryScreen] on success.
  static Future<void> openZipArchive(
    BuildContext context, {
    Color accentColor = tabColor,
  }) async {
    try {
      final picked = await FilePicker.pickFiles(
        dialogTitle: 'Select Gallery ZIP Archive',
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );
      if (picked.isEmpty) return;
      final filePath = picked.first.path;
      if (filePath == null || filePath.trim().isEmpty) return;
      if (!context.mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FolderGalleryScreen(
            initialFolderPath: filePath.trim(),
            accentColor: accentColor,
          ),
        ),
      );
    } catch (e) {
      log('FolderGalleryScreen.openZipArchive error: $e');
      if (context.mounted) {
        showSnackBar(
          context: context,
          content: 'Could not access ZIP file: $e',
        );
      }
    }
  }

  @override
  ConsumerState<FolderGalleryScreen> createState() =>
      _FolderGalleryScreenState();
}

class _FolderGalleryScreenState extends ConsumerState<FolderGalleryScreen> {
  String? _folderPath;
  final List<String> _additionalFolderPaths = [];
  List<File> _allFiles = [];
  List<File>? _shuffledFiles;
  bool _isShuffled = false;
  bool _isLoading = false;
  final String _searchQuery = '';

  // Multi-selection state
  bool _isSelectionMode = false;
  final Set<String> _selectedFilePaths = {};

  // Recent folders state
  List<RecentFolderItem> _recentFolders = [];

  static const Set<String> _imageExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.gif',
    '.bmp',
    '.heic',
    '.heif',
    '.jfif',
    '.jpe',
  };

  Color get _accent => widget.accentColor;

  String get _folderName {
    if (_folderPath == null || _folderPath!.isEmpty) return 'Local Gallery';
    final clean = resolveActualDirectoryPath(_folderPath!);
    String base;
    if (clean.toLowerCase().endsWith('.zip')) {
      base = p.basenameWithoutExtension(clean);
    } else {
      final name = p.basename(clean.trim());
      base = name.isEmpty ? clean : name;
    }
    if (_additionalFolderPaths.isNotEmpty) {
      return '$base + ${_additionalFolderPaths.length} more';
    }
    return base;
  }

  @override
  void initState() {
    super.initState();
    _loadRecentFolders();
    if (widget.initialFolderPath != null &&
        widget.initialFolderPath!.trim().isNotEmpty) {
      _folderPath = widget.initialFolderPath!.trim();
      _allFiles = _scanFolder(_folderPath!);
      RecentFoldersService.addRecentFolder(_folderPath!).then((_) {
        _loadRecentFolders();
      });
    }
  }

  Future<void> _loadRecentFolders() async {
    final recents = await RecentFoldersService.getRecentFolders();
    if (mounted) {
      setState(() => _recentFolders = recents);
    }
  }

  Future<void> _pickAnotherFolder() async {
    try {
      final selectedPath = await FilePicker.getDirectoryPath(
        dialogTitle: 'Select Photos Folder',
        initialDirectory: _folderPath,
      );
      if (selectedPath != null && selectedPath.trim().isNotEmpty && mounted) {
        _loadFolder(selectedPath.trim());
      }
    } catch (e) {
      log('Pick folder error: $e');
      if (mounted) {
        AppSnackBar.show(context, message: 'Could not select folder: $e');
      }
    }
  }

  Future<void> _pickZipArchive() async {
    try {
      final picked = await FilePicker.pickFiles(
        dialogTitle: 'Select Gallery ZIP Archive',
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );
      if (picked.isEmpty) return;
      final filePath = picked.first.path;
      if (filePath != null && filePath.trim().isNotEmpty && mounted) {
        _loadFolder(filePath.trim());
      }
    } catch (e) {
      log('Pick zip error: $e');
      if (mounted) {
        AppSnackBar.show(context, message: 'Could not open ZIP: $e');
      }
    }
  }

  void _loadFolder(String folderPath) {
    setState(() {
      _folderPath = folderPath;
      _additionalFolderPaths.clear();
      _shuffledFiles = null;
      _isShuffled = false;
      _isSelectionMode = false;
      _selectedFilePaths.clear();
      _allFiles = _scanFolder(folderPath);
      _isLoading = false;
    });
    RecentFoldersService.addRecentFolder(folderPath).then((_) {
      _loadRecentFolders();
    });
  }

  Future<void> _addFolderToMultiShuffle() async {
    try {
      final selectedPath = await FilePicker.getDirectoryPath(
        dialogTitle: 'Select Additional Folder to Multi-Shuffle',
        initialDirectory: _folderPath,
      );
      if (selectedPath == null || selectedPath.trim().isEmpty) return;
      final cleanPath = selectedPath.trim();
      final newFiles = _scanFolder(cleanPath);
      if (newFiles.isEmpty) {
        if (mounted) {
          AppSnackBar.show(context,
              message: 'No photos found in selected folder');
        }
        return;
      }

      if (mounted) {
        setState(() {
          if (!_additionalFolderPaths.contains(cleanPath)) {
            _additionalFolderPaths.add(cleanPath);
          }
          final existingPaths =
              _allFiles.map((f) => p.canonicalize(f.path)).toSet();
          final uniqueNewFiles = newFiles
              .where((f) => !existingPaths.contains(p.canonicalize(f.path)))
              .toList();
          _allFiles = [..._allFiles, ...uniqueNewFiles];
          _shuffleImages(_allFiles);
        });
        AppSnackBar.show(
          context,
          message:
              'Added ${newFiles.length} photos. Multi-shuffled ${_allFiles.length} total photos!',
        );
      }
    } catch (e) {
      log('Add folder to multi-shuffle error: $e');
      if (mounted) {
        AppSnackBar.show(context, message: 'Could not add folder: $e');
      }
    }
  }

  static List<File> _extractZipImages(File zipFile) {
    try {
      if (!zipFile.existsSync()) return [];
      final bytes = zipFile.readAsBytesSync();
      if (bytes.isEmpty) return [];

      final archive = ZipDecoder().decodeBytes(bytes);
      final tempDir = Directory.systemTemp;
      final safeZipName = p
          .basenameWithoutExtension(zipFile.path)
          .replaceAll(RegExp(r'[^\w-]'), '_');
      final targetDir =
          Directory('${tempDir.path}/worship_chat_zip_cache/$safeZipName');
      if (!targetDir.existsSync()) {
        targetDir.createSync(recursive: true);
      }

      final extracted = <File>[];
      for (final file in archive) {
        if (!file.isFile) continue;
        final ext = p.extension(file.name).toLowerCase();
        if (!_imageExtensions.contains(ext)) continue;

        final safeFileName = p.basename(file.name);
        final outFile = File('${targetDir.path}/$safeFileName');
        if (!outFile.existsSync() || outFile.lengthSync() != file.size) {
          outFile.writeAsBytesSync(file.content as List<int>);
        }
        extracted.add(outFile);
      }
      return extracted;
    } catch (e) {
      log('Error extracting zip file ${zipFile.path}: $e');
      return [];
    }
  }

  List<File> _scanFolder(String folderPath) {
    try {
      final cleanPath = resolveActualDirectoryPath(folderPath);

      // 1. Direct ZIP archive support
      if (cleanPath.toLowerCase().endsWith('.zip')) {
        final zipFile = File(cleanPath);
        if (zipFile.existsSync()) {
          final zipImages = _extractZipImages(zipFile);
          zipImages.sort(
            (a, b) => p
                .basename(a.path)
                .toLowerCase()
                .compareTo(p.basename(b.path).toLowerCase()),
          );
          return zipImages;
        }
      }

      final dir = Directory(cleanPath);
      if (!dir.existsSync()) return [];

      final allPhotos = <File>[];
      final seenPaths = <String>{};

      void addFile(File file) {
        try {
          final canonical = p.canonicalize(file.path);
          if (!seenPaths.contains(canonical)) {
            seenPaths.add(canonical);
            allPhotos.add(file);
          }
        } catch (_) {
          allPhotos.add(file);
        }
      }

      // Safe recursive traversal: visits subdirectories without failing the entire scan
      // if any individual directory has permission restrictions
      void crawl(Directory current, int depth) {
        if (depth > 6) return;
        try {
          final entries = current.listSync(followLinks: false);
          for (final entity in entries) {
            try {
              if (entity is File) {
                final ext = p.extension(entity.path).toLowerCase();
                if (_imageExtensions.contains(ext)) {
                  addFile(entity);
                } else if (ext == '.zip') {
                  // If a zip archive is in the folder, unpack its photos into cache
                  final zipImages = _extractZipImages(entity);
                  for (final zImg in zipImages) {
                    addFile(zImg);
                  }
                }
              } else if (entity is Directory) {
                final name = p.basename(entity.path);
                // Ignore hidden directories (.thumbnails, .trash, .git, etc.)
                if (!name.startsWith('.')) {
                  crawl(entity, depth + 1);
                }
              }
            } catch (_) {}
          }
        } catch (_) {}
      }

      crawl(dir, 0);

      allPhotos.sort(
        (a, b) => p
            .basename(a.path)
            .toLowerCase()
            .compareTo(p.basename(b.path).toLowerCase()),
      );
      return allPhotos;
    } catch (e) {
      log('Error scanning folder $folderPath: $e');
      return [];
    }
  }

  void _shuffleImages(List<File> source) {
    final shuffled = List<File>.of(source)..shuffle();
    setState(() {
      _shuffledFiles = shuffled;
      _isShuffled = true;
    });
    HapticFeedback.lightImpact();
  }

  void _restoreOrder() {
    setState(() {
      _shuffledFiles = null;
      _isShuffled = false;
    });
  }

  List<File> _filterFiles(List<File> source) {
    if (_searchQuery.trim().isEmpty) return source;
    final query = _searchQuery.trim().toLowerCase();
    return source
        .where((f) => p.basename(f.path).toLowerCase().contains(query))
        .toList();
  }

  List<GroupGalleryImage> _toGalleryImages(List<File> files) {
    return files.asMap().entries.map((entry) {
      final index = entry.key;
      final file = entry.value;
      DateTime modTime;
      try {
        modTime = file.lastModifiedSync();
      } catch (_) {
        modTime = DateTime.now();
      }

      final fileName = p.basename(file.path);
      return GroupGalleryImage(
        imageId: 'local_${index}_${file.path.hashCode}',
        groupId: 'local_${_folderPath?.hashCode ?? 0}',
        imageUrl: file.path,
        uploadedBy: 'local_storage',
        uploadedByName: 'Device Storage',
        uploadedAt: modTime,
        caption: fileName,
      );
    }).toList();
  }

  void _startSlideshow({int initialIndex = 0}) {
    final activeFiles = _isShuffled && _shuffledFiles != null
        ? _shuffledFiles!
        : _allFiles;
    final filtered = _filterFiles(activeFiles);
    if (filtered.isEmpty) {
      AppSnackBar.show(context, message: 'No photos to start slideshow.');
      return;
    }

    final galleryImages = _toGalleryImages(filtered);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SlideshowScreen(
          images: galleryImages,
          initialIndex: initialIndex.clamp(0, galleryImages.length - 1),
          accentColor: _accent,
          groupName: _folderName,
        ),
      ),
    );
  }

  // ── Multi-selection Logic ──────────────────────────────────────────────────

  void _enterSelectionMode([String? initialPath]) {
    HapticFeedback.selectionClick();
    setState(() {
      _isSelectionMode = true;
      _selectedFilePaths.clear();
      if (initialPath != null) {
        _selectedFilePaths.add(initialPath);
      }
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedFilePaths.clear();
    });
  }

  void _toggleSelection(String path) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedFilePaths.contains(path)) {
        _selectedFilePaths.remove(path);
      } else {
        _selectedFilePaths.add(path);
      }
    });
  }

  void _toggleSelectAll(List<File> currentDisplayFiles) {
    HapticFeedback.selectionClick();
    final allPaths = currentDisplayFiles.map((f) => f.path).toSet();
    setState(() {
      if (_selectedFilePaths.containsAll(allPaths)) {
        _selectedFilePaths.clear();
      } else {
        _selectedFilePaths.addAll(allPaths);
      }
    });
  }

  void _startSlideshowOfSelected() {
    if (_selectedFilePaths.isEmpty) return;
    final selectedFiles = _allFiles
        .where((f) => _selectedFilePaths.contains(f.path))
        .toList();
    if (selectedFiles.isEmpty) return;

    final galleryImages = _toGalleryImages(selectedFiles);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SlideshowScreen(
          images: galleryImages,
          initialIndex: 0,
          accentColor: _accent,
          groupName: '$_folderName (${selectedFiles.length} Selected)',
        ),
      ),
    );
  }

  void _startShuffledSlideshowOfSelected() {
    if (_selectedFilePaths.isEmpty) return;
    final selectedFiles = _allFiles
        .where((f) => _selectedFilePaths.contains(f.path))
        .toList();
    if (selectedFiles.isEmpty) return;

    final shuffled = List<File>.of(selectedFiles)..shuffle();
    final galleryImages = _toGalleryImages(shuffled);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SlideshowScreen(
          images: galleryImages,
          initialIndex: 0,
          accentColor: _accent,
          groupName: '$_folderName (${selectedFiles.length} Shuffled)',
        ),
      ),
    );
  }

  // ── Deletion Logic ─────────────────────────────────────────────────────────

  void _removeFileFromLists(File file) {
    final canon = p.canonicalize(file.path);
    setState(() {
      _allFiles.removeWhere((f) => p.canonicalize(f.path) == canon);
      _shuffledFiles?.removeWhere((f) => p.canonicalize(f.path) == canon);
      _selectedFilePaths.remove(file.path);
      if (_allFiles.isEmpty) {
        _isSelectionMode = false;
      }
    });
  }

  void _handleLocalFileUpdated(File updatedFile) {
    final canon = p.canonicalize(updatedFile.path);
    setState(() {
      final exists = _allFiles.any((f) => p.canonicalize(f.path) == canon);
      if (!exists) {
        _allFiles.insert(0, updatedFile);
        _shuffledFiles?.insert(0, updatedFile);
      }
    });
  }

  void _showFileDetailsSheet(File file) {
    final fileName = p.basename(file.path);
    int size = 0;
    try {
      size = file.lengthSync();
    } catch (_) {}
    final sizeKb = (size / 1024).toStringAsFixed(1);

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1B1728),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: Icon(Icons.photo_outlined, color: _accent),
              title: Text(
                fileName,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                'Size: ${sizeKb}KB • ${file.path}',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ListTile(
              leading: const Icon(
                Icons.text_fields_rounded,
                color: Color(0xFF00E5FF),
              ),
              title: const Text(
                'Remove Text',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: const Text(
                'Erase captions, watermarks & overlaid text',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(ctx);
                PhotoTextRemoverSheet.open(
                  context,
                  origin: PhotoTextRemoverOrigin.localGallery,
                  localPath: file.path,
                  groupName: _folderName,
                  title: fileName,
                  onLocalFileUpdated: _handleLocalFileUpdated,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.account_circle_outlined, color: tabColor),
              title: const Text(
                'Set as Profile Pic',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: const Text(
                'Use for your profile or any group',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(ctx);
                SetAsProfilePicSheet.show(
                  context,
                  localPath: file.path,
                  title: fileName,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: Colors.redAccent),
              title: const Text(
                'Delete Photo',
                style: TextStyle(color: Colors.redAccent),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _deleteSingleFile(file);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteSingleFile(File file) async {
    final fileName = p.basename(file.path);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline_rounded,
                color: Colors.redAccent, size: 24),
            SizedBox(width: 8),
            Text(
              'Delete Photo?',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to permanently delete "$fileName" from your device storage? This action cannot be undone.',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        if (file.existsSync()) {
          file.deleteSync();
        }
        _removeFileFromLists(file);
        if (mounted) {
          AppSnackBar.show(context, message: 'Photo deleted from device');
        }
      } catch (e) {
        log('Error deleting file ${file.path}: $e');
        if (mounted) {
          AppSnackBar.show(context, message: 'Could not delete photo: $e');
        }
      }
    }
  }

  Future<void> _deleteSelectedFiles() async {
    if (_selectedFilePaths.isEmpty) return;
    final count = _selectedFilePaths.length;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.delete_outline_rounded,
                color: Colors.redAccent, size: 24),
            const SizedBox(width: 8),
            Text(
              'Delete $count Photos?',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to permanently delete these $count photos from your device storage? This action cannot be undone.',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      int successCount = 0;
      final pathsToDelete = Set<String>.from(_selectedFilePaths);

      for (final filePath in pathsToDelete) {
        try {
          final file = File(filePath);
          if (file.existsSync()) {
            file.deleteSync();
            successCount++;
          }
        } catch (e) {
          log('Error deleting file $filePath: $e');
        }
      }

      setState(() {
        _allFiles.removeWhere((f) => pathsToDelete.contains(f.path));
        _shuffledFiles?.removeWhere((f) => pathsToDelete.contains(f.path));
        _selectedFilePaths.clear();
        _isSelectionMode = false;
      });

      if (mounted) {
        AppSnackBar.show(
          context,
          message: successCount > 0
              ? 'Deleted $successCount photos from device'
              : 'No photos were deleted',
        );
      }
    }
  }

  // ── Recent Folders Bottom Sheet ────────────────────────────────────────────

  void _showRecentFoldersSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF171324),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.7,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 6),
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.history_rounded, color: _accent, size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        'Recently Opened Folders',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      if (_recentFolders.isNotEmpty)
                        TextButton(
                          onPressed: () async {
                            await RecentFoldersService.clearRecentFolders();
                            await _loadRecentFolders();
                            setSheetState(() {});
                          },
                          child: const Text(
                            'Clear all',
                            style: TextStyle(
                              color: Colors.redAccent,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const Divider(color: Colors.white12, height: 1),
                if (_recentFolders.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 36, horizontal: 24),
                    child: Column(
                      children: [
                        Icon(
                          Icons.folder_open_outlined,
                          size: 48,
                          color: Colors.white24,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'No recent folders yet',
                          style: TextStyle(color: Colors.white60, fontSize: 13),
                        ),
                      ],
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _recentFolders.length,
                      separatorBuilder: (_, __) =>
                          const Divider(color: Colors.white10, height: 1),
                      itemBuilder: (_, index) {
                        final item = _recentFolders[index];
                        final isCurrent = _folderPath != null &&
                            p.normalize(_folderPath!) == p.normalize(item.path);

                        return ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isCurrent
                                  ? _accent.withValues(alpha: 0.25)
                                  : Colors.white.withValues(alpha: 0.06),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              item.isZip
                                  ? Icons.folder_zip_rounded
                                  : Icons.folder_rounded,
                              color: isCurrent ? _accent : Colors.white70,
                              size: 20,
                            ),
                          ),
                          title: Text(
                            item.name,
                            style: TextStyle(
                              color: isCurrent ? _accent : Colors.white,
                              fontWeight: isCurrent
                                  ? FontWeight.bold
                                  : FontWeight.w600,
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            item.path,
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: IconButton(
                            icon: const Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: Colors.white38,
                            ),
                            tooltip: 'Remove from recents',
                            onPressed: () async {
                              await RecentFoldersService.removeRecentFolder(
                                  item.path);
                              await _loadRecentFolders();
                              setSheetState(() {});
                            },
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            _loadFolder(item.path);
                          },
                        );
                      },
                    ),
                  ),
                const Divider(color: Colors.white12, height: 1),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _pickAnotherFolder();
                          },
                          icon: const Icon(Icons.folder_open_rounded, size: 18),
                          label: const Text('Pick Folder'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _accent,
                            side: BorderSide(
                                color: _accent.withValues(alpha: 0.5)),
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _pickZipArchive();
                          },
                          icon: const Icon(Icons.folder_zip_rounded, size: 18),
                          label: const Text('Open ZIP'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _accent.withValues(alpha: 0.2),
                            foregroundColor: _accent,
                            elevation: 0,
                            side: BorderSide(
                                color: _accent.withValues(alpha: 0.4)),
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeFiles = _isShuffled && _shuffledFiles != null
        ? _shuffledFiles!
        : _allFiles;
    final displayFiles = _filterFiles(activeFiles);

    return PopScope(
      canPop: !_isSelectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_isSelectionMode) {
          _exitSelectionMode();
        }
      },
      child: Scaffold(
        backgroundColor: backgroundColor,
        appBar: _isSelectionMode
            ? _buildSelectionAppBar(displayFiles)
            : _buildAppBar(displayFiles),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _folderPath == null
                ? _buildNoFolderSelected()
                : displayFiles.isEmpty
                    ? _buildEmptyFolder()
                    : _buildGrid(displayFiles),
        bottomNavigationBar:
            _isSelectionMode ? _buildSelectionBottomBar() : null,
      ),
    );
  }

  PreferredSizeWidget _buildSelectionAppBar(List<File> displayFiles) {
    final allDisplayPaths = displayFiles.map((f) => f.path).toSet();
    final isAllSelected = displayFiles.isNotEmpty &&
        _selectedFilePaths.containsAll(allDisplayPaths);

    return AppBar(
      backgroundColor: const Color(0xFF1B1728),
      elevation: 2,
      leading: IconButton(
        icon: const Icon(Icons.close_rounded, color: Colors.white),
        tooltip: 'Cancel selection',
        onPressed: _exitSelectionMode,
      ),
      title: Text(
        _selectedFilePaths.isEmpty
            ? 'Select photos'
            : '${_selectedFilePaths.length} selected',
        style: TextStyle(
          color: _accent,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
      actions: [
        // Select All / Deselect All
        IconButton(
          icon: Icon(
            isAllSelected ? Icons.deselect_rounded : Icons.select_all_rounded,
            color: Colors.white,
          ),
          tooltip: isAllSelected ? 'Deselect all' : 'Select all',
          onPressed: () => _toggleSelectAll(displayFiles),
        ),

        if (_selectedFilePaths.isNotEmpty) ...[
          // Info for single selected
          if (_selectedFilePaths.length == 1)
            IconButton(
              icon:
                  const Icon(Icons.info_outline_rounded, color: Colors.white70),
              tooltip: 'Photo info',
              onPressed: () {
                final file = File(_selectedFilePaths.first);
                _showFileDetailsSheet(file);
              },
            ),

          // Slideshow of selected
          IconButton(
            icon: const Icon(Icons.slideshow_rounded, color: Colors.white),
            tooltip: 'Slideshow of selected',
            onPressed: _startSlideshowOfSelected,
          ),

          // Multi-shuffle selected
          if (_selectedFilePaths.length >= 2)
            IconButton(
              icon: const Icon(Icons.shuffle_rounded, color: Colors.white),
              tooltip: 'Multi-shuffle selected',
              onPressed: _startShuffledSlideshowOfSelected,
            ),

          // Delete selected
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded,
                color: Colors.redAccent),
            tooltip: 'Delete selected',
            onPressed: _deleteSelectedFiles,
          ),
        ],
      ],
    );
  }

  PreferredSizeWidget _buildAppBar(List<File> files) {
    return AppBar(
      backgroundColor: appBarColor,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
        onPressed: () => Navigator.pop(context),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  _folderName,
                  style: TextStyle(
                    color: _accent,
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_allFiles.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _accent.withValues(alpha: 0.35),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    '${_allFiles.length}',
                    style: TextStyle(
                      color: _accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
          Text(
            _folderPath ?? 'Select a folder to view photos',
            style: TextStyle(color: Colors.grey[400], fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      actions: [
        // ── Multi-select Toggle ─────────────────────────────
        if (files.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.checklist_rounded),
            tooltip: 'Select multiple',
            onPressed: () => _enterSelectionMode(),
          ),

        // ── Slideshow ──────────────────────────────────────
        if (files.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.slideshow_rounded),
            tooltip: 'Start slideshow',
            onPressed: () => _startSlideshow(initialIndex: 0),
          ),

        // ── Shuffle controls ───────────────────────────────
        if (_allFiles.isNotEmpty) ...[
          if (_isShuffled) ...[
            IconButton(
              icon: Icon(Icons.shuffle_rounded, color: _accent),
              tooltip: 'Shuffle again',
              onPressed: () => _shuffleImages(_allFiles),
            ),
            IconButton(
              icon: const Icon(
                Icons.format_list_numbered_rounded,
                color: Colors.white70,
              ),
              tooltip: 'Restore order',
              onPressed: _restoreOrder,
            ),
          ] else
            IconButton(
              icon: const Icon(Icons.shuffle_rounded, color: Colors.white54),
              tooltip: 'Shuffle photos',
              onPressed: () => _shuffleImages(_allFiles),
            ),
        ],

        // ── Add folder to multi-shuffle ─────────────────────
        if (_allFiles.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: 'Add folder to multi-shuffle',
            onPressed: _addFolderToMultiShuffle,
          ),

        // ── Recent Folders ─────────────────────────────────
        IconButton(
          icon: const Icon(Icons.history_rounded),
          tooltip: 'Recent folders',
          onPressed: _showRecentFoldersSheet,
        ),

        // ── Open ZIP archive directly ─────────────────────
        IconButton(
          icon: const Icon(Icons.folder_zip_rounded),
          tooltip: 'Open ZIP archive',
          onPressed: _pickZipArchive,
        ),

        // ── Choose another folder ──────────────────────────
        IconButton(
          icon: const Icon(Icons.folder_open_rounded),
          tooltip: 'Open different folder',
          onPressed: _pickAnotherFolder,
        ),
      ],
    );
  }

  Widget? _buildSelectionBottomBar() {
    if (_selectedFilePaths.isEmpty) return null;

    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        MediaQuery.paddingOf(context).bottom + 10,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF1B1728),
        border: Border(top: BorderSide(color: Colors.white12, width: 1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${_selectedFilePaths.length} photo${_selectedFilePaths.length == 1 ? '' : 's'} selected',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          OutlinedButton.icon(
            onPressed: _startSlideshowOfSelected,
            icon: const Icon(Icons.slideshow_rounded, size: 16),
            label: const Text('Slideshow'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _accent,
              side: BorderSide(color: _accent.withValues(alpha: 0.6)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          if (_selectedFilePaths.length >= 2) ...[
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _startShuffledSlideshowOfSelected,
              icon: const Icon(Icons.shuffle_rounded, size: 16),
              label: const Text('Shuffle'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.purpleAccent,
                side: BorderSide(
                    color: Colors.purpleAccent.withValues(alpha: 0.6)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _deleteSelectedFiles,
            icon: const Icon(Icons.delete_outline_rounded, size: 16),
            label: const Text('Delete'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoFolderSelected() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            Icons.folder_open_rounded,
            size: 64,
            color: _accent.withValues(alpha: 0.7),
          ),
          const SizedBox(height: 16),
          const Text(
            'No folder selected',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Choose a folder or ZIP archive from device storage to view photos',
            style: TextStyle(color: Colors.white60, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: _pickAnotherFolder,
                icon: const Icon(Icons.folder_open_rounded, size: 20),
                label: const Text('Select Folder'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _pickZipArchive,
                icon: const Icon(Icons.folder_zip_rounded, size: 20),
                label: const Text('Open ZIP Archive'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _accent,
                  side: BorderSide(color: _accent.withValues(alpha: 0.6)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),

          // ── Recently Opened Folders Section ─────────────────────────────
          if (_recentFolders.isNotEmpty) ...[
            const SizedBox(height: 36),
            Row(
              children: [
                Icon(Icons.history_rounded, color: _accent, size: 18),
                const SizedBox(width: 8),
                const Text(
                  'Recently Opened',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () async {
                    await RecentFoldersService.clearRecentFolders();
                    await _loadRecentFolders();
                  },
                  child: const Text(
                    'Clear all',
                    style: TextStyle(color: Colors.redAccent, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _recentFolders.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, index) {
                final item = _recentFolders[index];
                return Material(
                  color: const Color(0xFF1E1A2E),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _loadFolder(item.path),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: _accent.withValues(alpha: 0.18),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              item.isZip
                                  ? Icons.folder_zip_rounded
                                  : Icons.folder_rounded,
                              color: _accent,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  item.path,
                                  style: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 11,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: Colors.white38,
                            ),
                            tooltip: 'Remove from recents',
                            onPressed: () async {
                              await RecentFoldersService.removeRecentFolder(
                                  item.path);
                              await _loadRecentFolders();
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyFolder() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.photo_library_outlined,
            size: 60,
            color: _accent.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 18),
          const Text(
            'No photos found in this folder',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              _folderPath ?? '',
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: _pickAnotherFolder,
                icon: const Icon(Icons.folder_open_rounded, size: 18),
                label: const Text('Open Another Folder'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _accent,
                  side: BorderSide(color: _accent.withValues(alpha: 0.6)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _pickZipArchive,
                icon: const Icon(Icons.folder_zip_rounded, size: 18),
                label: const Text('Open ZIP Archive'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent.withValues(alpha: 0.2),
                  foregroundColor: _accent,
                  elevation: 0,
                  side: BorderSide(color: _accent.withValues(alpha: 0.4)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(List<File> files) {
    final width = MediaQuery.sizeOf(context).width;
    final crossAxisCount = (width / 200).floor().clamp(3, 12);

    return CustomScrollView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            3,
            3,
            3,
            MediaQuery.paddingOf(context).bottom + 80,
          ),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 3,
              mainAxisSpacing: 3,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final file = files[index];
                final isSelected = _selectedFilePaths.contains(file.path);

                return GestureDetector(
                  key: ValueKey('grid_photo_${file.path}'),
                  onTap: () {
                    if (_isSelectionMode) {
                      _toggleSelection(file.path);
                    } else {
                      final galleryImages = _toGalleryImages(files);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => _LocalFullscreenViewer(
                            files: files,
                            images: galleryImages,
                            initialIndex: index,
                            accentColor: _accent,
                            folderName: _folderName,
                            onSlideshow: () =>
                                _startSlideshow(initialIndex: index),
                            onFileDeleted: _removeFileFromLists,
                            onFileUpdated: _handleLocalFileUpdated,
                          ),
                        ),
                      );
                    }
                  },
                  onLongPress: () {
                    if (_isSelectionMode) {
                      _toggleSelection(file.path);
                    } else {
                      _enterSelectionMode(file.path);
                    }
                  },
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Hero(
                        tag: 'local_file_${file.path}',
                        child: Image.file(
                          file,
                          fit: BoxFit.cover,
                          cacheWidth: 400,
                          errorBuilder: (_, __, ___) => Container(
                            color: Colors.grey[900],
                            child: const Icon(
                              Icons.broken_image_rounded,
                              color: Colors.white24,
                            ),
                          ),
                        ),
                      ),

                      // Multi-selection overlay & checkbox
                      if (_isSelectionMode) ...[
                        IgnorePointer(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? _accent.withValues(alpha: 0.28)
                                  : Colors.black26,
                              border: isSelected
                                  ? Border.all(color: _accent, width: 2.5)
                                  : null,
                            ),
                          ),
                        ),
                        Positioned(
                          top: 6,
                          right: 6,
                          child: IgnorePointer(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: isSelected ? _accent : Colors.black54,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected ? _accent : Colors.white70,
                                  width: 1.5,
                                ),
                              ),
                              child: isSelected
                                  ? const Icon(
                                      Icons.check_rounded,
                                      size: 16,
                                      color: Colors.white,
                                    )
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
              childCount: files.length,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24.0),
            child: Center(
              child: Text(
                '${files.length} ${files.length == 1 ? 'Photo' : 'Photos'}',
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Local Fullscreen Photo Viewer
// ─────────────────────────────────────────────────────────────────────────────

class _LocalFullscreenViewer extends StatefulWidget {
  final List<File> files;
  final List<GroupGalleryImage> images;
  final int initialIndex;
  final Color accentColor;
  final String folderName;
  final VoidCallback onSlideshow;
  final void Function(File deletedFile) onFileDeleted;
  final void Function(File updatedFile)? onFileUpdated;

  const _LocalFullscreenViewer({
    required this.files,
    required this.images,
    required this.initialIndex,
    required this.accentColor,
    required this.folderName,
    required this.onSlideshow,
    required this.onFileDeleted,
    this.onFileUpdated,
  });

  @override
  State<_LocalFullscreenViewer> createState() => _LocalFullscreenViewerState();
}

class _LocalFullscreenViewerState extends State<_LocalFullscreenViewer> {
  late PageController _pageCtrl;
  late int _index;
  bool _overlayOn = true;
  late List<File> _files;
  late List<GroupGalleryImage> _images;

  @override
  void initState() {
    super.initState();
    _files = List<File>.from(widget.files);
    _images = List<GroupGalleryImage>.from(widget.images);
    _index = widget.initialIndex;
    _pageCtrl = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirmAndDeleteCurrentPhoto() async {
    if (_index < 0 || _index >= _files.length) return;
    final currentFile = _files[_index];
    final fileName = p.basename(currentFile.path);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline_rounded,
                color: Colors.redAccent, size: 24),
            SizedBox(width: 8),
            Text(
              'Delete Photo?',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to permanently delete "$fileName" from your device? This action cannot be undone.',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        if (currentFile.existsSync()) {
          currentFile.deleteSync();
        }
        widget.onFileDeleted(currentFile);

        if (_files.length <= 1) {
          if (mounted) {
            Navigator.pop(context);
            AppSnackBar.show(context,
                message: 'Photo deleted. Folder is now empty.');
          }
        } else {
          setState(() {
            _files.removeAt(_index);
            _images.removeAt(_index);
            if (_index >= _files.length) {
              _index = _files.length - 1;
            }
          });
          if (mounted) {
            AppSnackBar.show(context, message: 'Photo deleted from device');
          }
        }
      } catch (e) {
        log('Error deleting photo: $e');
        if (mounted) {
          AppSnackBar.show(context, message: 'Could not delete photo: $e');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_files.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            'No photos',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    final currentFile = _files[_index];
    final fileName = p.basename(currentFile.path);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PhotoViewGallery.builder(
            pageController: _pageCtrl,
            itemCount: _files.length,
            onPageChanged: (i) => setState(() => _index = i),
            scrollPhysics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            backgroundDecoration: const BoxDecoration(color: Colors.black),
            builder: (context, i) => PhotoViewGalleryPageOptions(
              imageProvider: FileImage(_files[i]),
              minScale: PhotoViewComputedScale.contained,
              maxScale: PhotoViewComputedScale.covered * 4,
              onTapUp: (_, __, ___) => setState(() => _overlayOn = !_overlayOn),
              heroAttributes: PhotoViewHeroAttributes(
                tag: 'local_file_${_files[i].path}',
              ),
            ),
            loadingBuilder: (_, __) =>
                const Center(child: CircularProgressIndicator()),
          ),

          GalleryNavigationControls(
            controller: _pageCtrl,
            currentIndex: _index,
            imageCount: _files.length,
          ),

          // ── Overlay Top Bar ──────────────────────────────────────────────
          IgnorePointer(
            ignoring: !_overlayOn,
            child: AnimatedOpacity(
              opacity: _overlayOn ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Stack(
                children: [
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.black87, Colors.transparent],
                        ),
                      ),
                      child: SafeArea(
                        bottom: false,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              child: Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(
                                      Icons.arrow_back_ios_new_rounded,
                                      color: Colors.white,
                                    ),
                                    onPressed: () => Navigator.pop(context),
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '${_index + 1} of ${_files.length}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          fileName,
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 11,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 2),
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    minWidth:
                                        MediaQuery.sizeOf(context).width - 32,
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceEvenly,
                                    children: [
                                  // ── Slideshow ──────────────────────────
                                  IconButton(
                                    icon: const Icon(
                                      Icons.slideshow_rounded,
                                      color: Colors.white,
                                    ),
                                    tooltip: 'Slideshow',
                                    onPressed: () {
                                      Navigator.pop(context);
                                      widget.onSlideshow();
                                    },
                                  ),

                                  // ── Forward photo ──────────────────────
                                  if (AppCapabilities.current.chatEnabled)
                                    IconButton(
                                      icon: const Icon(
                                        Icons.forward_rounded,
                                        color: Colors.white,
                                      ),
                                      tooltip: 'Forward photo',
                                      onPressed: () {
                                        ForwardMessageSheet.show(
                                          context,
                                          ForwardMessagePayload(
                                            text: fileName,
                                            messageType: 'image',
                                            fileMessageData: currentFile.path,
                                            caption: fileName,
                                            isFromGallery: true,
                                            sourceGroupId: 'local',
                                            sourceGroupName: widget.folderName,
                                          ),
                                        );
                                      },
                                    ),

                                  // ── Google Lens ────────────────────────
                                  IconButton(
                                    icon: const GoogleLensIcon(),
                                    tooltip: 'Search with Google Lens',
                                    onPressed: () => GoogleLensService.search(
                                      context: context,
                                      localPath: currentFile.path,
                                    ),
                                  ),

                                  // ── Remove Text ────────────────────────
                                  IconButton(
                                    icon: const Icon(
                                      Icons.text_fields_rounded,
                                      color: Color(0xFF00E5FF),
                                    ),
                                    tooltip: 'Remove Text',
                                    onPressed: () => PhotoTextRemoverSheet.open(
                                      context,
                                      origin:
                                          PhotoTextRemoverOrigin.localGallery,
                                      localPath: currentFile.path,
                                      groupName: widget.folderName,
                                      title: fileName,
                                      onLocalFileUpdated: (updatedFile) {
                                        widget.onFileUpdated?.call(updatedFile);
                                        if (!mounted) return;
                                        final canon =
                                            p.canonicalize(updatedFile.path);
                                        setState(() {
                                          if (!_files.any(
                                            (f) =>
                                                p.canonicalize(f.path) == canon,
                                          )) {
                                            _files.insert(_index + 1, updatedFile);
                                            _images.insert(
                                              _index + 1,
                                              GroupGalleryImage(
                                                imageId:
                                                    'local_${updatedFile.path.hashCode}',
                                                groupId: 'local',
                                                imageUrl: updatedFile.path,
                                                uploadedBy: 'local_storage',
                                                uploadedByName:
                                                    'Device Storage',
                                                uploadedAt: DateTime.now(),
                                                caption:
                                                    p.basename(updatedFile.path),
                                              ),
                                            );
                                          }
                                        });
                                      },
                                    ),
                                  ),

                                  // ── Wallpaper & Home Widget ────────────
                                  IconButton(
                                    icon: const Icon(
                                      Icons.wallpaper_rounded,
                                      color: Colors.white,
                                    ),
                                    tooltip: 'Wallpaper & Home Widget',
                                    onPressed: () =>
                                        WallpaperAndWidgetSheet.show(
                                      context,
                                      photoId:
                                          'loc_${currentFile.path.hashCode}',
                                      localPath: currentFile.path,
                                      title: fileName,
                                      subtitle: widget.folderName,
                                    ),
                                  ),

                                  // ── Set as Profile Pic ─────────────────
                                  IconButton(
                                    icon: const Icon(
                                      Icons.account_circle_outlined,
                                      color: Colors.white,
                                    ),
                                    tooltip: 'Set as Profile Pic',
                                    onPressed: () => SetAsProfilePicSheet.show(
                                      context,
                                      localPath: currentFile.path,
                                      title: fileName,
                                    ),
                                  ),

                                  // ── Delete photo ───────────────────────
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      color: Colors.redAccent,
                                    ),
                                    tooltip: 'Delete photo',
                                    onPressed: _confirmAndDeleteCurrentPhoto,
                                  ),
                                ],
                              ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // ── Bottom Folder Path ───────────────────────────────────
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Colors.black87, Colors.transparent],
                        ),
                      ),
                      child: SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.folder_rounded,
                                size: 14,
                                color: widget.accentColor,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  currentFile.path,
                                  style: const TextStyle(
                                    color: Colors.white60,
                                    fontSize: 11,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
