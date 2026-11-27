import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/utils/app_capabilities.dart';
import 'package:worship_chat/common/utils/phone_wallpaper_service.dart';
import 'package:worship_chat/common/utils/utils.dart';
import 'package:worship_chat/common/widgets/square_image_crop_screen.dart';
import 'package:worship_chat/features/bookmark/controller/bookmark_controller.dart';
import 'package:worship_chat/features/group/controller/group_controller.dart';
import 'package:worship_chat/features/group/controller/group_gallery_controller.dart';
import 'package:worship_chat/models/bookmark_collection_model.dart';
import 'package:worship_chat/models/bookmark_model.dart';
import 'package:worship_chat/models/group.dart';
import 'package:worship_chat/models/group_gallery_image.dart';

enum AppMediaPickerTab { gallery, bookmarks }

/// Selection returned from [AppMediaPickerSheet].
class PickedAppMedia {
  final String? imageUrl;
  final File? imageFile;
  final String? label;

  const PickedAppMedia({
    this.imageUrl,
    this.imageFile,
    this.label,
  });
}

/// Shared source selector sheet for User Profile & Group/Deity avatar editors.
Future<void> showProfilePicSourceSheet({
  required BuildContext context,
  bool hasPhoto = false,
  VoidCallback? onViewPhoto,
  VoidCallback? onRemovePhoto,
  required Future<void> Function(File file) onLocalFileSelected,
  required Future<void> Function(String imageUrl) onRemoteUrlSelected,
  String? initialGroupId,
  String? initialGroupName,
}) async {
  final isDesktop = AppCapabilities.current.isDesktop;

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF161426),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (sheetCtx) {
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Profile Photo',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              if (hasPhoto && onViewPhoto != null)
                _SourceOptionTile(
                  icon: Icons.fullscreen_rounded,
                  color: const Color(0xFF38BDF8),
                  title: 'View Photo',
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    onViewPhoto();
                  },
                ),
              _SourceOptionTile(
                icon: Icons.collections_rounded,
                color: const Color(0xFFFFD700),
                title: 'Choose from App Gallery',
                subtitle: 'Pick directly from Queendom galleries',
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  final picked = await AppMediaPickerSheet.show(
                    context,
                    initialTab: AppMediaPickerTab.gallery,
                    initialGroupId: initialGroupId,
                    initialGroupName: initialGroupName,
                  );
                  if (picked == null) return;
                  if (picked.imageFile != null) {
                    await onLocalFileSelected(picked.imageFile!);
                  } else if (picked.imageUrl != null &&
                      picked.imageUrl!.isNotEmpty) {
                    await onRemoteUrlSelected(picked.imageUrl!);
                  }
                },
              ),
              _SourceOptionTile(
                icon: Icons.bookmarks_rounded,
                color: const Color(0xFFF59E0B),
                title: 'Choose from Bookmarks',
                subtitle: 'Pick from saved bookmarks & collections',
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  final picked = await AppMediaPickerSheet.show(
                    context,
                    initialTab: AppMediaPickerTab.bookmarks,
                    initialGroupId: initialGroupId,
                    initialGroupName: initialGroupName,
                  );
                  if (picked == null) return;
                  if (picked.imageFile != null) {
                    await onLocalFileSelected(picked.imageFile!);
                  } else if (picked.imageUrl != null &&
                      picked.imageUrl!.isNotEmpty) {
                    await onRemoteUrlSelected(picked.imageUrl!);
                  }
                },
              ),
              _SourceOptionTile(
                icon: Icons.photo_library_rounded,
                color: tabColor,
                title: 'Choose from Gallery',
                subtitle: 'Pick from device storage',
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  final file = await pickImageFromSource(
                    context,
                    source: ImageSource.gallery,
                  );
                  if (file != null) {
                    await onLocalFileSelected(file);
                  }
                },
              ),
              if (!isDesktop)
                _SourceOptionTile(
                  icon: Icons.camera_alt_rounded,
                  color: accentOrange,
                  title: 'Take Photo',
                  onTap: () async {
                    Navigator.pop(sheetCtx);
                    final file = await pickImageFromSource(
                      context,
                      source: ImageSource.camera,
                    );
                    if (file != null) {
                      await onLocalFileSelected(file);
                    }
                  },
                ),
              if (hasPhoto && onRemovePhoto != null)
                _SourceOptionTile(
                  icon: Icons.delete_outline_rounded,
                  color: const Color(0xFFFF5252),
                  title: 'Remove Photo',
                  textColor: const Color(0xFFFF6B6B),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    onRemovePhoto();
                  },
                ),
            ],
          ),
        ),
      );
    },
  );
}

class _SourceOptionTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final Color textColor;
  final VoidCallback onTap;

  const _SourceOptionTile({
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
    this.textColor = Colors.white,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: color.withValues(alpha: 0.35), width: 0.8),
        ),
        child: Icon(icon, color: color, size: 19),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: textColor,
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: const TextStyle(color: Colors.white54, fontSize: 11.5),
            )
          : null,
      onTap: onTap,
    );
  }
}

/// Modal picker letting the user browse App Galleries and Saved Bookmarks/Collections
/// to pick a profile picture for themselves or a group/deity.
class AppMediaPickerSheet extends ConsumerStatefulWidget {
  final AppMediaPickerTab initialTab;
  final String? initialGroupId;
  final String? initialGroupName;

  const AppMediaPickerSheet({
    super.key,
    this.initialTab = AppMediaPickerTab.gallery,
    this.initialGroupId,
    this.initialGroupName,
  });

  static Future<PickedAppMedia?> show(
    BuildContext context, {
    AppMediaPickerTab initialTab = AppMediaPickerTab.gallery,
    String? initialGroupId,
    String? initialGroupName,
  }) {
    return showModalBottomSheet<PickedAppMedia?>(
      context: context,
      backgroundColor: const Color(0xFF161426),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => AppMediaPickerSheet(
        initialTab: initialTab,
        initialGroupId: initialGroupId,
        initialGroupName: initialGroupName,
      ),
    );
  }

  @override
  ConsumerState<AppMediaPickerSheet> createState() =>
      _AppMediaPickerSheetState();
}

class _AppMediaPickerSheetState extends ConsumerState<AppMediaPickerSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchCtrl = TextEditingController();
  bool _cropBeforeSelecting = false;
  bool _isResolvingCrop = false;

  // Gallery state
  List<GroupModel> _groups = const [];
  String? _selectedGroupId;
  bool _loadingGroups = true;
  bool _loadingAllGallery = false;
  List<GroupGalleryImage> _allGalleryImages = const [];

  // Bookmarks state
  String? _selectedCollectionId;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab == AppMediaPickerTab.bookmarks ? 1 : 0,
    );
    _selectedGroupId = widget.initialGroupId;
    _initGallery();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _initGallery() async {
    try {
      final groups =
          await ref.read(groupControllerProvider).getAllGroupsForPicker();
      if (!mounted) return;
      setState(() {
        _groups = groups;
        _loadingGroups = false;
        if (_selectedGroupId != null &&
            !groups.any((g) => g.groupId == _selectedGroupId)) {
          _selectedGroupId = null;
        }
      });
      if (_selectedGroupId == null && groups.isNotEmpty) {
        await _loadAllGroupsGallery(groups);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingGroups = false);
    }
  }

  Future<void> _loadAllGroupsGallery(List<GroupModel> groups) async {
    if (_loadingAllGallery) return;
    setState(() => _loadingAllGallery = true);
    try {
      final images = await ref
          .read(groupGalleryControllerProvider)
          .getAllGalleryImagesForPicker(groups.map((g) => g.groupId).toList());
      if (mounted) {
        setState(() {
          _allGalleryImages = images;
          _loadingAllGallery = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingAllGallery = false);
    }
  }

  Future<void> _selectImageUrl(String url, {String? label}) async {
    if (_isResolvingCrop) return;
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty) return;

    if (!_cropBeforeSelecting) {
      Navigator.pop(
        context,
        PickedAppMedia(imageUrl: cleanUrl, label: label),
      );
      return;
    }

    setState(() => _isResolvingCrop = true);
    try {
      final file = await PhoneWallpaperService.instance.resolveImageFile(
        imageUrl: cleanUrl,
      );
      if (!mounted) return;
      if (file == null) {
        setState(() => _isResolvingCrop = false);
        AppSnackBar.error(context, 'Could not download photo to crop.');
        return;
      }
      final cropped = await cropImageToSquare(context, file);
      if (!mounted) return;
      setState(() => _isResolvingCrop = false);
      if (cropped != null) {
        Navigator.pop(
          context,
          PickedAppMedia(imageFile: cropped, imageUrl: cleanUrl, label: label),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isResolvingCrop = false);
        AppSnackBar.error(context, 'Failed to prepare photo: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.85;

    return SafeArea(
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Choose Profile Photo',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Crop',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Switch.adaptive(
                        value: _cropBeforeSelecting,
                        activeTrackColor: tabColor,
                        onChanged: _isResolvingCrop
                            ? null
                            : (val) =>
                                setState(() => _cropBeforeSelecting = val),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                controller: _searchCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 13.5),
                decoration: InputDecoration(
                  hintText: 'Filter by deity, group or caption...',
                  hintStyle: const TextStyle(color: Colors.white38),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: Colors.white54,
                    size: 19,
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white54,
                            size: 18,
                          ),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: const Color(0xFF0F0E17),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (val) => setState(() => _searchQuery = val.trim()),
              ),
            ),
            TabBar(
              controller: _tabController,
              indicatorColor: tabColor,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              tabs: const [
                Tab(text: 'App Gallery'),
                Tab(text: 'Bookmarks'),
              ],
            ),
            if (_isResolvingCrop) const LinearProgressIndicator(color: tabColor),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildGalleryTab(),
                  _buildBookmarksTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGalleryTab() {
    if (_loadingGroups) {
      return const Center(child: CircularProgressIndicator(color: tabColor));
    }

    final groupNameById = {
      for (final g in _groups) g.groupId: g.nameWithPosition,
    };

    return Column(
      children: [
        if (_groups.isNotEmpty)
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: const Text('All Groups'),
                    selected: _selectedGroupId == null,
                    selectedColor: tabColor,
                    backgroundColor: const Color(0xFF1F1B33),
                    labelStyle: TextStyle(
                      color:
                          _selectedGroupId == null ? Colors.black : Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    onSelected: (_) {
                      setState(() => _selectedGroupId = null);
                      if (_allGalleryImages.isEmpty) {
                        _loadAllGroupsGallery(_groups);
                      }
                    },
                  ),
                ),
                ..._groups.map((g) {
                  final selected = _selectedGroupId == g.groupId;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(
                        g.nameWithPosition.isNotEmpty
                            ? g.nameWithPosition
                            : g.name,
                      ),
                      selected: selected,
                      selectedColor: tabColor,
                      backgroundColor: const Color(0xFF1F1B33),
                      labelStyle: TextStyle(
                        color: selected ? Colors.black : Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      onSelected: (_) =>
                          setState(() => _selectedGroupId = g.groupId),
                    ),
                  );
                }),
              ],
            ),
          ),
        Expanded(
          child: _selectedGroupId != null
              ? StreamBuilder<List<GroupGalleryImage>>(
                  stream: ref
                      .read(groupGalleryControllerProvider)
                      .getGalleryStream(_selectedGroupId!),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(color: tabColor),
                      );
                    }
                    final items = (snap.data ?? const [])
                        .where((img) => !img.isVideo)
                        .toList();
                    return _buildGalleryGrid(items, groupNameById);
                  },
                )
              : (_loadingAllGallery
                  ? const Center(
                      child: CircularProgressIndicator(color: tabColor),
                    )
                  : _buildGalleryGrid(_allGalleryImages, groupNameById)),
        ),
      ],
    );
  }

  Widget _buildGalleryGrid(
    List<GroupGalleryImage> rawItems,
    Map<String, String> groupNameById,
  ) {
    final q = _searchQuery.toLowerCase();
    final items = rawItems.where((img) {
      if (q.isEmpty) return true;
      final gName = (groupNameById[img.groupId] ?? '').toLowerCase();
      final caption = (img.caption ?? '').toLowerCase();
      return gName.contains(q) || caption.contains(q);
    }).toList();

    if (items.isEmpty) {
      return const Center(
        child: Text(
          'No gallery photos found',
          style: TextStyle(color: Colors.white54, fontSize: 13.5),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(6),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: items.length,
      itemBuilder: (_, index) {
        final item = items[index];
        final label = (item.caption?.trim().isNotEmpty ?? false)
            ? item.caption!.trim()
            : (groupNameById[item.groupId] ?? '');
        return GestureDetector(
          onTap: () => _selectImageUrl(item.imageUrl, label: label),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: item.imageUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, __) =>
                      Container(color: const Color(0xFF1F1B33)),
                  errorWidget: (_, __, ___) => Container(
                    color: const Color(0xFF1F1B33),
                    child: const Icon(
                      Icons.broken_image_rounded,
                      color: Colors.white24,
                    ),
                  ),
                ),
              ),
              if (label.isNotEmpty)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                    decoration: const BoxDecoration(
                      borderRadius:
                          BorderRadius.vertical(bottom: Radius.circular(8)),
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Colors.black87, Colors.transparent],
                      ),
                    ),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBookmarksTab() {
    final bookmarkController = ref.read(bookmarkControllerProvider);
    final uid = safeCurrentUserId();

    return StreamBuilder<List<BookmarkModel>>(
      stream: bookmarkController.myBookmarks(),
      builder: (context, bmSnap) {
        if (bmSnap.connectionState == ConnectionState.waiting &&
            !bmSnap.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: tabColor),
          );
        }
        final allBookmarks = bmSnap.data ?? const <BookmarkModel>[];
        if (uid == null || uid.isEmpty) {
          return _buildBookmarksGrid(allBookmarks);
        }

        return StreamBuilder<List<BookmarkCollectionModel>>(
          stream: bookmarkController.collectionsForUser(uid),
          builder: (context, colSnap) {
            final collections =
                colSnap.data ?? const <BookmarkCollectionModel>[];
            BookmarkCollectionModel? activeCol;
            if (_selectedCollectionId != null) {
              for (final c in collections) {
                if (c.id == _selectedCollectionId) {
                  activeCol = c;
                  break;
                }
              }
            }
            final filtered = activeCol == null
                ? allBookmarks
                : allBookmarks
                    .where((b) => activeCol!.bookmarkIds.contains(b.bookmarkId))
                    .toList();

            return Column(
              children: [
                if (collections.isNotEmpty)
                  SizedBox(
                    height: 46,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: const Text('All Bookmarks'),
                            selected: _selectedCollectionId == null,
                            selectedColor: const Color(0xFFF59E0B),
                            backgroundColor: const Color(0xFF1F1B33),
                            labelStyle: TextStyle(
                              color: _selectedCollectionId == null
                                  ? Colors.black
                                  : Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                            onSelected: (_) =>
                                setState(() => _selectedCollectionId = null),
                          ),
                        ),
                        ...collections.map((c) {
                          final selected = _selectedCollectionId == c.id;
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text(c.name),
                              selected: selected,
                              selectedColor: const Color(0xFFF59E0B),
                              backgroundColor: const Color(0xFF1F1B33),
                              labelStyle: TextStyle(
                                color: selected ? Colors.black : Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                              onSelected: (_) =>
                                  setState(() => _selectedCollectionId = c.id),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                Expanded(child: _buildBookmarksGrid(filtered)),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildBookmarksGrid(List<BookmarkModel> rawItems) {
    final q = _searchQuery.toLowerCase();
    final items = rawItems.where((bm) {
      if (q.isEmpty) return true;
      return bm.groupName.toLowerCase().contains(q) ||
          bm.userName.toLowerCase().contains(q);
    }).toList();

    if (items.isEmpty) {
      return const Center(
        child: Text(
          'No bookmarked photos found',
          style: TextStyle(color: Colors.white54, fontSize: 13.5),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(6),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: items.length,
      itemBuilder: (_, index) {
        final bm = items[index];
        return GestureDetector(
          onTap: () => _selectImageUrl(bm.imageUrl, label: bm.groupName),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: bm.imageUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, __) =>
                      Container(color: const Color(0xFF1F1B33)),
                  errorWidget: (_, __, ___) => Container(
                    color: const Color(0xFF1F1B33),
                    child: const Icon(
                      Icons.broken_image_rounded,
                      color: Colors.white24,
                    ),
                  ),
                ),
              ),
              if (bm.groupName.isNotEmpty)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                    decoration: const BoxDecoration(
                      borderRadius:
                          BorderRadius.vertical(bottom: Radius.circular(8)),
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Colors.black87, Colors.transparent],
                      ),
                    ),
                    child: Text(
                      bm.groupName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
