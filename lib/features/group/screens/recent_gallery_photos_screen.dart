import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gallery_saver_plus/gallery_saver.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/utils/google_lens_service.dart';
import 'package:worship_chat/common/utils/utils.dart';
import 'package:worship_chat/common/widgets/photo_text_remover_sheet.dart';
import 'package:worship_chat/common/widgets/set_as_profile_pic_sheet.dart';
import 'package:worship_chat/common/widgets/wallpaper_widget_sheet.dart';
import 'package:worship_chat/features/auth/controller/auth_controller.dart';
import 'package:worship_chat/features/bookmark/controller/bookmark_controller.dart';
import 'package:worship_chat/features/bookmark/widgets/save_to_collection_sheet.dart';
import 'package:worship_chat/features/chat/widgets/forward_message_sheet.dart';
import 'package:worship_chat/features/group/controller/group_gallery_controller.dart';
import 'package:worship_chat/features/group/screens/group_gallery_screen.dart';
import 'package:worship_chat/features/group/screens/slide_show_screen.dart';
import 'package:worship_chat/features/group/utils/multi_gallery_shuffler_helper.dart';
import 'package:worship_chat/features/settings/models/queendom_customization_model.dart';
import 'package:worship_chat/features/settings/providers/queendom_customization_provider.dart';
import 'package:worship_chat/models/group.dart';
import 'package:worship_chat/models/group_gallery_image.dart';

/// Formats a gallery upload timestamp cleanly for recent strips and grids.
String formatRecentGalleryTimeAgo(DateTime dt, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final diff = reference.difference(dt);
  if (diff.isNegative || diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays == 1) return 'Yesterday';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  if (dt.year == reference.year) {
    return DateFormat('MMM d').format(dt);
  }
  return DateFormat('MMM d, yy').format(dt);
}

/// Resolves a group's accent color from its Queendom category/position customization.
Color resolveGroupAccentColor(
  GroupModel? group,
  QueendomCustomizationState? customization,
) {
  if (group == null) return tabColor;
  if (group.isFuckToySubGroup) {
    return const Color(0xFFE040FB);
  }
  final fallback = group.queendom == 'Queen Rashmika'
      ? const Color(0xFFFF4081)
      : const Color(0xFFFFD700);

  if (customization == null) return fallback;

  final position = group.position;
  if (position != null && position.isNotEmpty && position != 'None') {
    for (final cat in customization.allCategories) {
      if (cat.position.toLowerCase() == position.toLowerCase()) {
        return cat.color;
      }
    }
  }

  return fallback;
}

/// Full-screen browser showing recently added photos across all user groups,
/// filterable by group and launchable straight into Photo Viewer, Slideshow, or
/// the originating Group Gallery.
class RecentGalleryPhotosScreen extends ConsumerStatefulWidget {
  final List<GroupGalleryImage> initialImages;
  final List<GroupModel> groups;
  final bool initialPhotosOnly;
  final bool autoRefreshOnOpen;

  const RecentGalleryPhotosScreen({
    super.key,
    required this.initialImages,
    required this.groups,
    this.initialPhotosOnly = true,
    this.autoRefreshOnOpen = true,
  });

  @override
  ConsumerState<RecentGalleryPhotosScreen> createState() =>
      _RecentGalleryPhotosScreenState();
}

class _RecentGalleryPhotosScreenState
    extends ConsumerState<RecentGalleryPhotosScreen> {
  late List<GroupGalleryImage> _images;
  late bool _photosOnly;
  String? _selectedGroupId;
  bool _isRefreshing = false;

  Map<String, GroupModel> get _groupsById => {
        for (final g in widget.groups)
          if (g.groupId.isNotEmpty) g.groupId: g,
      };

  List<GroupGalleryImage> get _filteredImages {
    if (_selectedGroupId == null) return _images;
    return _images.where((e) => e.groupId == _selectedGroupId).toList();
  }

  @override
  void initState() {
    super.initState();
    _images = List<GroupGalleryImage>.of(widget.initialImages);
    _photosOnly = widget.initialPhotosOnly;
    if (widget.autoRefreshOnOpen && widget.groups.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    }
  }

  Future<void> _refresh() async {
    if (_isRefreshing || widget.groups.isEmpty) return;
    setState(() => _isRefreshing = true);
    try {
      final fetched = await ref
          .read(groupGalleryControllerProvider)
          .getRecentGalleryPhotos(
            groups: widget.groups,
            limit: 60,
            limitPerGroup: 12,
            maxGroupsToQuery: 24,
            photosOnly: _photosOnly,
            saveCache: _photosOnly,
          );
      if (mounted) {
        setState(() {
          _images = fetched;
          if (_selectedGroupId != null &&
              !_images.any((img) => img.groupId == _selectedGroupId)) {
            _selectedGroupId = null;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  void _openSlideshow() {
    final active = _filteredImages.where((e) => !e.isVideo).toList();
    if (active.isEmpty) {
      AppSnackBar.show(
        context,
        message: 'No recent photos available for slideshow',
        type: SnackBarType.info,
      );
      return;
    }

    final groupNamesMap = <String, String>{};
    for (final img in active) {
      final g = _groupsById[img.groupId];
      if (g != null) {
        groupNamesMap[g.groupId] = g.nameWithPosition;
      }
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SlideshowScreen(
          images: active,
          initialIndex: 0,
          accentColor: tabColor,
          groupName: 'Recent Gallery (${active.length} Photos)',
          mode: MultiGalleryMode.alternate,
          groupNamesMap: groupNamesMap,
        ),
      ),
    );
  }

  void _openViewer(int index) {
    final list = _filteredImages;
    if (list.isEmpty || index < 0 || index >= list.length) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RecentPhotoViewerScreen(
          images: list,
          initialIndex: index,
          groupsById: _groupsById,
        ),
      ),
    );
  }

  void _openGroupGallery(GroupModel group) {
    final customization = ref.read(queendomCustomizationProvider);
    final accent = resolveGroupAccentColor(group, customization);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupGalleryScreen(
          groupId: group.groupId,
          groupName: group.nameWithPosition,
          accentColor: accent,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = _filteredImages;
    final groupsMap = _groupsById;
    final customization = ref.watch(queendomCustomizationProvider);

    // Order group filter chips by the most recent photo appearance.
    final orderedGroupIds = <String>[];
    final seenGroups = <String>{};
    for (final img in _images) {
      if (img.groupId.isNotEmpty && seenGroups.add(img.groupId)) {
        orderedGroupIds.add(img.groupId);
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0E0D15),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161426),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
            size: 18,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Recently Added Photos',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              '${active.length} ${active.length == 1 ? 'item' : 'items'} across ${orderedGroupIds.length} ${orderedGroupIds.length == 1 ? 'group' : 'groups'}',
              style: TextStyle(color: Colors.grey[400], fontSize: 11.5),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _photosOnly ? 'Photos only (tap for all media)' : 'All media',
            icon: Icon(
              _photosOnly
                  ? Icons.photo_library_outlined
                  : Icons.perm_media_rounded,
              color: _photosOnly ? Colors.white70 : tabColor,
              size: 21,
            ),
            onPressed: () {
              HapticFeedback.selectionClick();
              setState(() => _photosOnly = !_photosOnly);
              _refresh();
            },
          ),
          IconButton(
            tooltip: 'Start Slideshow',
            icon: const Icon(
              Icons.slideshow_rounded,
              color: Colors.white,
              size: 22,
            ),
            onPressed: _openSlideshow,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isRefreshing)
            const LinearProgressIndicator(
              minHeight: 2,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation<Color>(tabColor),
            ),

          if (orderedGroupIds.length > 1)
            Container(
              height: 46,
              color: const Color(0xFF161426),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                itemCount: 1 + orderedGroupIds.length,
                itemBuilder: (context, idx) {
                  if (idx == 0) {
                    final selected = _selectedGroupId == null;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text('All (${_images.length})'),
                        selected: selected,
                        backgroundColor: const Color(0xFF211E33),
                        selectedColor: tabColor.withValues(alpha: 0.24),
                        side: BorderSide(
                          color: selected
                              ? tabColor.withValues(alpha: 0.6)
                              : Colors.white12,
                        ),
                        labelStyle: TextStyle(
                          color: selected ? tabColor : Colors.white70,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                        onSelected: (_) =>
                            setState(() => _selectedGroupId = null),
                      ),
                    );
                  }

                  final gid = orderedGroupIds[idx - 1];
                  final group = groupsMap[gid];
                  final count = _images.where((e) => e.groupId == gid).length;
                  final selected = _selectedGroupId == gid;
                  final accent = resolveGroupAccentColor(group, customization);
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(
                        '${(group != null && group.nameWithPosition.isNotEmpty) ? group.nameWithPosition : (group?.name ?? 'Group')} ($count)',
                      ),
                      selected: selected,
                      backgroundColor: const Color(0xFF211E33),
                      selectedColor: accent.withValues(alpha: 0.24),
                      side: BorderSide(
                        color: selected
                            ? accent.withValues(alpha: 0.65)
                            : Colors.white12,
                      ),
                      labelStyle: TextStyle(
                        color: selected ? accent : Colors.white70,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                      onSelected: (_) =>
                          setState(() => _selectedGroupId = gid),
                    ),
                  );
                },
              ),
            ),

          Expanded(
            child: RefreshIndicator(
              color: tabColor,
              backgroundColor: const Color(0xFF1A1829),
              onRefresh: _refresh,
              child: active.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.sizeOf(context).height * 0.55,
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.photo_library_outlined,
                                  color: Colors.grey[600],
                                  size: 48,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _isRefreshing
                                      ? 'Loading recent gallery photos...'
                                      : 'No recently added photos found',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Pull down to refresh across your group galleries',
                                  style: TextStyle(
                                    color: Colors.grey[500],
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : GridView.builder(
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      padding: const EdgeInsets.fromLTRB(10, 10, 10, 24),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 6,
                        mainAxisSpacing: 6,
                        childAspectRatio: 0.85,
                      ),
                      itemCount: active.length,
                      itemBuilder: (context, index) {
                        final img = active[index];
                        final group = groupsMap[img.groupId];
                        final accent =
                            resolveGroupAccentColor(group, customization);
                        final thumbUrl = img.isVideo
                            ? img.imageUrl
                            : getOptimizedRoleplayImageUrl(
                                img.imageUrl,
                                width: 420,
                              );

                        return GestureDetector(
                          onTap: () => _openViewer(index),
                          onLongPress: group != null
                              ? () {
                                  HapticFeedback.mediumImpact();
                                  _openGroupGallery(group);
                                }
                              : null,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: accent.withValues(alpha: 0.25),
                                width: 0.8,
                              ),
                              color: const Color(0xFF1A1926),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(11),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Hero(
                                    tag: 'recent_gallery_${img.imageId}',
                                    child: CachedNetworkImage(
                                      imageUrl: thumbUrl,
                                      fit: BoxFit.cover,
                                      placeholder: (_, __) => Container(
                                        color: const Color(0xFF1C1B29),
                                        child: Center(
                                          child: Icon(
                                            Icons.image_outlined,
                                            color: Colors.grey[700],
                                            size: 22,
                                          ),
                                        ),
                                      ),
                                      errorWidget: (_, __, ___) => Container(
                                        color: const Color(0xFF1C1B29),
                                        child: Icon(
                                          img.isVideo
                                              ? Icons.videocam_rounded
                                              : Icons.broken_image_outlined,
                                          color: Colors.white38,
                                        ),
                                      ),
                                    ),
                                  ),
                                  // Top-left relative time badge
                                  Positioned(
                                    top: 5,
                                    left: 5,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5.5,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(
                                          alpha: 0.65,
                                        ),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        formatRecentGalleryTimeAgo(
                                          img.uploadedAt,
                                        ),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (img.isVideo)
                                    const Positioned(
                                      top: 5,
                                      right: 5,
                                      child: CircleAvatar(
                                        radius: 10,
                                        backgroundColor: Colors.black54,
                                        child: Icon(
                                          Icons.play_arrow_rounded,
                                          color: Colors.white,
                                          size: 14,
                                        ),
                                      ),
                                    ),
                                  if (group != null &&
                                      group.groupPic.trim().isNotEmpty)
                                    Positioned(
                                      bottom: 5,
                                      right: 5,
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () => _openGroupGallery(group),
                                        child: Container(
                                          width: 20,
                                          height: 20,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: accent,
                                              width: 1.1,
                                            ),
                                            boxShadow: const [
                                              BoxShadow(
                                                color: Colors.black54,
                                                blurRadius: 4,
                                              ),
                                            ],
                                          ),
                                          child: ClipOval(
                                            child: CachedNetworkImage(
                                              imageUrl: group.groupPic,
                                              fit: BoxFit.cover,
                                              errorWidget: (_, __, ___) =>
                                                  Container(
                                                color: accent.withValues(
                                                  alpha: 0.3,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Swipeable full-screen photo viewer tailored for recent cross-group gallery items.
class RecentPhotoViewerScreen extends ConsumerStatefulWidget {
  final List<GroupGalleryImage> images;
  final int initialIndex;
  final Map<String, GroupModel> groupsById;

  const RecentPhotoViewerScreen({
    super.key,
    required this.images,
    required this.initialIndex,
    required this.groupsById,
  });

  @override
  ConsumerState<RecentPhotoViewerScreen> createState() =>
      _RecentPhotoViewerScreenState();
}

class _RecentPhotoViewerScreenState
    extends ConsumerState<RecentPhotoViewerScreen> {
  late final PageController _pageCtrl;
  late int _index;
  bool _overlayOn = true;
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    final safeInitial = widget.images.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, widget.images.length - 1);
    _index = safeInitial;
    _pageCtrl = PageController(initialPage: safeInitial);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  GroupGalleryImage get _currentImage => widget.images[_index];

  GroupModel? get _currentGroup => widget.groupsById[_currentImage.groupId];

  String get _currentGroupName =>
      _currentGroup?.nameWithPosition ?? 'Group Gallery';

  Future<void> _downloadCurrent() async {
    if (_isDownloading || _currentImage.isVideo) return;
    setState(() => _isDownloading = true);
    try {
      final img = _currentImage;
      final originalUrl = getOriginalHighQualityImageUrl(img.imageUrl);
      final ext = getImageExtensionFromUrl(originalUrl);
      final dir = await getTemporaryDirectory();
      final filePath =
          '${dir.path}/${img.imageId}_${DateTime.now().millisecondsSinceEpoch}.$ext';

      await Dio().download(
        originalUrl,
        filePath,
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
        ),
      );

      final saved = await GallerySaver.saveImage(
        filePath,
        albumName: 'Worship Chat',
        toDcim: false,
      );

      final tempFile = File(filePath);
      if (await tempFile.exists()) {
        await tempFile.delete();
      }

      if (mounted) {
        AppSnackBar.show(
          context,
          message: saved == true
              ? 'Saved in high quality to Worship Chat album'
              : 'Could not save photo',
          type: saved == true ? SnackBarType.success : SnackBarType.error,
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.show(
          context,
          message: 'Download failed: $e',
          type: SnackBarType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  Future<void> _openSaveToCollection({String? bookmarkId}) async {
    final userData = await ref.read(userDataAuthProvider.future);
    if (!mounted) return;
    final uid =
        userData?.uid ?? FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return;

    final img = _currentImage;
    String? bId = bookmarkId;
    bId ??= await ref.read(bookmarkControllerProvider).ensureBookmarked(
          imageUrl: img.imageUrl,
          groupId: img.groupId,
          groupName: _currentGroupName,
          userName: userData?.name ?? 'Unknown',
          userProfilePic: userData?.profilePic ?? '',
        );

    if (bId != null && mounted) {
      await SaveToCollectionSheet.show(
        context: context,
        bookmarkId: bId,
        imageUrl: img.imageUrl,
        userId: uid,
      );
    }
  }

  Future<void> _toggleBookmark() async {
    final userData = await ref.read(userDataAuthProvider.future);
    if (userData == null || !mounted) return;
    final img = _currentImage;
    final result = await ref
        .read(bookmarkControllerProvider)
        .toggleBookmarkWithResult(
          imageUrl: img.imageUrl,
          groupId: img.groupId,
          groupName: _currentGroupName,
          userName: userData.name ?? 'Unknown',
          userProfilePic: userData.profilePic ?? '',
        );

    if (!mounted) return;
    if (result.isBookmarked && result.bookmarkId != null) {
      await _openSaveToCollection(bookmarkId: result.bookmarkId);
    } else {
      AppSnackBar.show(
        context,
        message: 'Bookmark removed',
        type: SnackBarType.info,
      );
    }
  }

  void _openOriginGallery() {
    final img = _currentImage;
    final group = _currentGroup;
    final customization = ref.read(queendomCustomizationProvider);
    final accent = resolveGroupAccentColor(group, customization);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupGalleryScreen(
          groupId: img.groupId,
          groupName: group?.nameWithPosition ?? 'Group Gallery',
          accentColor: accent,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.images.isEmpty) {
      return const Scaffold(backgroundColor: Colors.black);
    }

    final img = _currentImage;
    final customization = ref.watch(queendomCustomizationProvider);
    final accent = resolveGroupAccentColor(_currentGroup, customization);
    final isBookmarked =
        ref.watch(bookmarkControllerProvider).isBookmarked(img.imageUrl);

    final photoOnlyImages = widget.images.where((e) => !e.isVideo).toList();
    final groupNamesMap = <String, String>{
      for (final entry in widget.groupsById.entries)
        entry.key: entry.value.nameWithPosition,
    };

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          PhotoViewGallery.builder(
            pageController: _pageCtrl,
            itemCount: widget.images.length,
            onPageChanged: (i) => setState(() => _index = i),
            scrollPhysics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            backgroundDecoration: const BoxDecoration(color: Colors.black),
            builder: (context, i) {
              final item = widget.images[i];
              if (item.isVideo) {
                return PhotoViewGalleryPageOptions.customChild(
                  onTapUp: (_, __, ___) =>
                      setState(() => _overlayOn = !_overlayOn),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.play_circle_filled_rounded,
                          color: Colors.white70,
                          size: 64,
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Video Item',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: _openOriginGallery,
                          icon: const Icon(Icons.photo_library_rounded, size: 17),
                          label: const Text('Play in Group Gallery'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return PhotoViewGalleryPageOptions(
                imageProvider: CachedNetworkImageProvider(
                  getOriginalHighQualityImageUrl(item.imageUrl),
                ),
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 4,
                onTapUp: (_, __, ___) =>
                    setState(() => _overlayOn = !_overlayOn),
                heroAttributes: PhotoViewHeroAttributes(
                  tag: 'recent_gallery_${item.imageId}',
                ),
              );
            },
            loadingBuilder: (context, event) => Center(
              child: CircularProgressIndicator(color: accent),
            ),
          ),

          IgnorePointer(
            ignoring: !_overlayOn,
            child: AnimatedOpacity(
              opacity: _overlayOn ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 180),
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
                                horizontal: 8,
                                vertical: 4,
                              ),
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
                                          _currentGroupName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        Text(
                                          '${img.uploadedByName.isNotEmpty ? img.uploadedByName : 'Gallery'} • ${formatRecentGalleryTimeAgo(img.uploadedAt)}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 11.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (img.groupId.isNotEmpty)
                                    TextButton.icon(
                                      onPressed: _openOriginGallery,
                                      style: TextButton.styleFrom(
                                        foregroundColor: accent,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        backgroundColor:
                                            accent.withValues(alpha: 0.14),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(18),
                                          side: BorderSide(
                                            color: accent.withValues(alpha: 0.4),
                                          ),
                                        ),
                                      ),
                                      icon: const Icon(
                                        Icons.photo_library_rounded,
                                        size: 14,
                                      ),
                                      label: const Text(
                                        'Gallery',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    minWidth:
                                        MediaQuery.sizeOf(context).width - 16,
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceEvenly,
                                    children: [
                                      StreamBuilder<bool>(
                                        stream: isBookmarked,
                                        builder: (context, snap) {
                                          final bookmarked = snap.data ?? false;
                                          return GestureDetector(
                                            onLongPress: () =>
                                                _openSaveToCollection(),
                                            child: IconButton(
                                              icon: Icon(
                                                bookmarked
                                                    ? Icons.bookmark
                                                    : Icons.bookmark_outline,
                                                color: bookmarked
                                                    ? Colors.amber
                                                    : Colors.white,
                                              ),
                                              tooltip: 'Bookmark & Collections',
                                              onPressed: _toggleBookmark,
                                            ),
                                          );
                                        },
                                      ),
                                      if (!img.isVideo)
                                        IconButton(
                                          icon: _isDownloading
                                              ? SizedBox(
                                                  width: 20,
                                                  height: 20,
                                                  child:
                                                      CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    color: accent,
                                                  ),
                                                )
                                              : const Icon(
                                                  Icons.download_rounded,
                                                  color: Colors.white,
                                                ),
                                          tooltip: 'Save photo (HD)',
                                          onPressed: _isDownloading
                                              ? null
                                              : _downloadCurrent,
                                        ),
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
                                              text: img.caption ?? '',
                                              messageType: img.isVideo
                                                  ? 'video'
                                                  : 'image',
                                              fileMessageData: img.imageUrl,
                                              caption: img.caption,
                                              isFromGallery: true,
                                              sourceGroupId: img.groupId,
                                              sourceGroupName:
                                                  _currentGroupName,
                                            ),
                                          );
                                        },
                                      ),
                                      if (photoOnlyImages.isNotEmpty)
                                        IconButton(
                                          icon: const Icon(
                                            Icons.slideshow_rounded,
                                            color: Colors.white,
                                          ),
                                          tooltip: 'Slideshow',
                                          onPressed: () {
                                            final startIdx = photoOnlyImages
                                                .indexWhere(
                                                  (e) =>
                                                      e.imageId == img.imageId,
                                                );
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => SlideshowScreen(
                                                  images: photoOnlyImages,
                                                  initialIndex: startIdx >= 0
                                                      ? startIdx
                                                      : 0,
                                                  accentColor: accent,
                                                  groupName:
                                                      'Recent Gallery (${photoOnlyImages.length})',
                                                  mode: MultiGalleryMode
                                                      .alternate,
                                                  groupNamesMap: groupNamesMap,
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      if (!img.isVideo) ...[
                                        IconButton(
                                          icon: const GoogleLensIcon(),
                                          tooltip: 'Search with Google Lens',
                                          onPressed: () =>
                                              GoogleLensService.search(
                                            context: context,
                                            imageUrl: img.imageUrl,
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.text_fields_rounded,
                                            color: Color(0xFF00E5FF),
                                          ),
                                          tooltip: 'Remove Text',
                                          onPressed: () =>
                                              PhotoTextRemoverSheet.open(
                                            context,
                                            origin: PhotoTextRemoverOrigin
                                                .groupGallery,
                                            imageUrl: img.imageUrl,
                                            groupId: img.groupId,
                                            groupName: _currentGroupName,
                                            sourceImageId: img.imageId,
                                            title: (img.caption
                                                        ?.trim()
                                                        .isNotEmpty ??
                                                    false)
                                                ? img.caption!.trim()
                                                : _currentGroupName,
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.wallpaper_rounded,
                                            color: Colors.white,
                                          ),
                                          tooltip: 'Wallpaper & Home Widget',
                                          onPressed: () =>
                                              WallpaperAndWidgetSheet.show(
                                            context,
                                            photoId: 'gal_${img.imageId}',
                                            imageUrl: img.imageUrl,
                                            title: (img.caption
                                                        ?.trim()
                                                        .isNotEmpty ??
                                                    false)
                                                ? img.caption!.trim()
                                                : _currentGroupName,
                                            subtitle: 'Recent Gallery',
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.account_circle_outlined,
                                            color: Colors.white,
                                          ),
                                          tooltip: 'Set as Profile Pic',
                                          onPressed: () =>
                                              SetAsProfilePicSheet.show(
                                            context,
                                            imageUrl: img.imageUrl,
                                            sourceGroupId: img.groupId,
                                            sourceGroupName: _currentGroupName,
                                            title: (img.caption
                                                        ?.trim()
                                                        .isNotEmpty ??
                                                    false)
                                                ? img.caption!.trim()
                                                : _currentGroupName,
                                          ),
                                        ),
                                      ],
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
                          padding: const EdgeInsets.fromLTRB(20, 32, 20, 18),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (img.caption != null &&
                                  img.caption!.trim().isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Text(
                                    img.caption!.trim(),
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              Text(
                                '${_index + 1} / ${widget.images.length}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13.5,
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
