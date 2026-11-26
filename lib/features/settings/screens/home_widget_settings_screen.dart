import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/utils/home_widget_service.dart';
import 'package:worship_chat/common/utils/utils.dart';
import 'package:worship_chat/features/bookmark/controller/bookmark_controller.dart';
import 'package:worship_chat/features/group/controller/group_gallery_controller.dart';
import 'package:worship_chat/features/home/screens/gallery_home_screen.dart';
import 'package:worship_chat/features/settings/screens/settings_screen.dart';
import 'package:worship_chat/models/bookmark_collection_model.dart';
import 'package:worship_chat/models/group.dart';

/// Configures the Android Home Screen Photo Widget: live preview, pin-to-home
/// button, Bookmark Collection / Group Gallery sync, and rotation interval.
class HomeWidgetSettingsScreen extends ConsumerStatefulWidget {
  static const String routeName = '/home-widget-settings';

  const HomeWidgetSettingsScreen({super.key});

  @override
  ConsumerState<HomeWidgetSettingsScreen> createState() =>
      _HomeWidgetSettingsScreenState();
}

class _HomeWidgetSettingsScreenState
    extends ConsumerState<HomeWidgetSettingsScreen> {
  HomeWidgetNativeStatus _nativeStatus = const HomeWidgetNativeStatus();
  bool _isSyncing = false;
  String? _syncStatusText;

  static const _intervalOptions = <(int minutes, String label)>[
    (0, 'Manual Only'),
    (30, 'Every 30m'),
    (60, 'Every 1h'),
    (360, 'Every 6h'),
    (1440, 'Daily'),
  ];

  @override
  void initState() {
    super.initState();
    _refreshState();
  }

  Future<void> _refreshState() async {
    await HomeWidgetService.instance.loadConfig();
    final status = await HomeWidgetService.instance.getNativeStatus();
    if (mounted) {
      setState(() => _nativeStatus = status);
    }
  }

  Future<void> _pinToHomeScreen() async {
    if (!HomeWidgetService.instance.isSupportedPlatform) {
      AppSnackBar.info(
        context,
        'Home screen photo widgets are available on Android devices.',
      );
      return;
    }
    final sent = await HomeWidgetService.instance.requestPinWidget();
    if (!mounted) return;
    if (sent) {
      AppSnackBar.success(
        context,
        'Follow your launcher prompt to place the Worship Chat widget.',
        title: 'Widget Pin Requested',
      );
      await _refreshState();
    } else {
      AppSnackBar.info(
        context,
        'Long-press your home screen → Widgets → Worship Chat Photo to add it.',
      );
    }
  }

  Future<void> _pickCollectionToSync() async {
    final uid = safeCurrentUserId() ?? '';
    if (uid.isEmpty || Firebase.apps.isEmpty) {
      AppSnackBar.warning(context, 'Sign in to sync a bookmark collection.');
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF161426),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
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
                  'Sync Bookmark Collection',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: StreamBuilder<List<BookmarkCollectionModel>>(
                    stream: ref
                        .read(bookmarkControllerProvider)
                        .collectionsForUser(uid),
                    builder: (_, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                            child: CircularProgressIndicator(color: tabColor),
                          ),
                        );
                      }
                      final collections = (snap.data ?? [])
                          .where((c) => c.bookmarkIds.isNotEmpty)
                          .toList();
                      if (collections.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Text(
                            'No bookmark collections with photos found yet.',
                            style: TextStyle(color: Colors.grey[400]),
                          ),
                        );
                      }
                      return ListView.separated(
                        shrinkWrap: true,
                        itemCount: collections.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          color: Colors.white.withValues(alpha: 0.06),
                        ),
                        itemBuilder: (_, idx) {
                          final col = collections[idx];
                          return ListTile(
                            leading: const Icon(
                              Icons.collections_bookmark_rounded,
                              color: Color(0xFFFFD700),
                            ),
                            title: Text(
                              col.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              '${col.bookmarkIds.length} photos',
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 12,
                              ),
                            ),
                            onTap: () {
                              Navigator.pop(sheetCtx);
                              _syncCollection(uid, col);
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _syncCollection(String uid, BookmarkCollectionModel col) async {
    setState(() {
      _isSyncing = true;
      _syncStatusText = 'Caching photos from "${col.name}"...';
    });

    try {
      final allBookmarks = await ref
          .read(bookmarkControllerProvider)
          .bookmarksForUser(uid)
          .first;
      final items = allBookmarks
          .where((bm) => col.containsBookmark(bm.bookmarkId))
          .map(
            (bm) => HomeWidgetPhotoInput(
              id: bm.bookmarkId,
              imageUrl: bm.imageUrl,
              title: bm.groupName.isNotEmpty ? bm.groupName : col.name,
              subtitle: col.name,
            ),
          )
          .toList();

      final count = await HomeWidgetService.instance.syncPlaylist(
        items: items,
        sourceLabel: col.name,
      );
      if (!mounted) return;
      if (count > 0) {
        AppSnackBar.success(
          context,
          'Synced $count photo${count == 1 ? '' : 's'} from "${col.name}".',
        );
      } else {
        AppSnackBar.warning(
          context,
          'Could not cache any photos from "${col.name}".',
        );
      }
    } catch (e) {
      if (mounted) AppSnackBar.error(context, 'Sync failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
          _syncStatusText = null;
        });
      }
    }
  }

  Future<void> _pickGroupGalleryToSync() async {
    if (Firebase.apps.isEmpty) {
      AppSnackBar.warning(context, 'Connect to load group galleries.');
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF161426),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
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
                  'Sync from Queendom / Group Gallery',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: StreamBuilder<List<GroupModel>>(
                    stream: ref.read(galleryGroupsProvider.future).asStream(),
                    builder: (_, snap) {
                      final groups = snap.data ?? const <GroupModel>[];
                      if (snap.connectionState == ConnectionState.waiting &&
                          groups.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                            child: CircularProgressIndicator(color: tabColor),
                          ),
                        );
                      }
                      if (groups.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Text(
                            'No galleries found.',
                            style: TextStyle(color: Colors.grey[400]),
                          ),
                        );
                      }
                      return ListView.separated(
                        shrinkWrap: true,
                        itemCount: groups.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          color: Colors.white.withValues(alpha: 0.06),
                        ),
                        itemBuilder: (_, idx) {
                          final grp = groups[idx];
                          return ListTile(
                            leading: const Icon(
                              Icons.photo_library_rounded,
                              color: tabColor,
                            ),
                            title: Text(
                              grp.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            onTap: () {
                              Navigator.pop(sheetCtx);
                              _syncGroupGallery(grp);
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _syncGroupGallery(GroupModel group) async {
    setState(() {
      _isSyncing = true;
      _syncStatusText = 'Caching latest photos from "${group.name}"...';
    });

    try {
      final images = await ref
          .read(groupGalleryControllerProvider)
          .getMultiGalleryImages([group.groupId]);
      final photoInputs = images
          .where((img) => !img.isVideo && img.imageUrl.trim().isNotEmpty)
          .map(
            (img) => HomeWidgetPhotoInput(
              id: img.imageId,
              imageUrl: img.imageUrl,
              title: group.name,
              subtitle: img.caption?.trim().isNotEmpty == true
                  ? img.caption!.trim()
                  : 'Gallery',
            ),
          )
          .toList();

      final count = await HomeWidgetService.instance.syncPlaylist(
        items: photoInputs,
        sourceLabel: group.name,
      );
      if (!mounted) return;
      if (count > 0) {
        AppSnackBar.success(
          context,
          'Synced $count photo${count == 1 ? '' : 's'} from "${group.name}".',
        );
      } else {
        AppSnackBar.warning(
          context,
          'No downloadable photos found in "${group.name}".',
        );
      }
    } catch (e) {
      if (mounted) AppSnackBar.error(context, 'Sync failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
          _syncStatusText = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0E17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161426),
        elevation: 0,
        title: const Text(
          'Home Screen Widget',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ValueListenableBuilder<HomeWidgetConfig>(
        valueListenable: HomeWidgetService.instance.configNotifier,
        builder: (context, config, _) {
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildPreviewCard(config),
                  const SizedBox(height: 16),
                  _buildPinBanner(),
                  if (_isSyncing) ...[
                    const SizedBox(height: 14),
                    SettingsScreen.buildCard([
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: tabColor,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _syncStatusText ?? 'Syncing widget photos...',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ]),
                  ],
                  const SizedBox(height: 22),
                  SettingsScreen.buildSectionTitle('SYNC SOURCE'),
                  const SizedBox(height: 10),
                  SettingsScreen.buildCard([
                    SettingsScreen.buildRow(
                      icon: Icons.collections_bookmark_rounded,
                      iconColor: const Color(0xFFFFD700),
                      title: 'Sync Bookmark Collection',
                      subtitle:
                          'Rotate photos from any saved Bookmark collection',
                      onTap: _isSyncing ? null : _pickCollectionToSync,
                    ),
                    Divider(
                      height: 1,
                      indent: 62,
                      endIndent: 14,
                      color: Colors.white.withValues(alpha: 0.07),
                    ),
                    SettingsScreen.buildRow(
                      icon: Icons.photo_library_rounded,
                      iconColor: tabColor,
                      title: 'Sync Group Gallery',
                      subtitle:
                          'Use the latest 24 photos from any Queendom gallery',
                      onTap: _isSyncing ? null : _pickGroupGalleryToSync,
                    ),
                  ]),
                  const SizedBox(height: 22),
                  SettingsScreen.buildSectionTitle('WIDGET PREFERENCES'),
                  const SizedBox(height: 10),
                  SettingsScreen.buildCard([
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Auto-Rotation Interval',
                            style: TextStyle(
                              color: Colors.grey[300],
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _intervalOptions.map((opt) {
                              final selected =
                                  config.intervalMinutes == opt.$1;
                              return ChoiceChip(
                                label: Text(opt.$2),
                                selected: selected,
                                showCheckmark: false,
                                selectedColor:
                                    tabColor.withValues(alpha: 0.25),
                                backgroundColor: const Color(0xFF0F0E17),
                                side: BorderSide(
                                  color: selected
                                      ? tabColor
                                      : Colors.white.withValues(alpha: 0.12),
                                ),
                                labelStyle: TextStyle(
                                  color: selected ? Colors.white : Colors.grey[400],
                                  fontSize: 12,
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                                onSelected: (_) => HomeWidgetService.instance
                                    .updatePreferences(intervalMinutes: opt.$1),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                    Divider(
                      height: 1,
                      indent: 14,
                      endIndent: 14,
                      color: Colors.white.withValues(alpha: 0.07),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Show Photo Caption',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  'Display label and photo counter on widget',
                                  style: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: config.showTitle,
                            activeTrackColor: tabColor.withValues(alpha: 0.55),
                            activeThumbColor: tabColor,
                            onChanged: (v) => HomeWidgetService.instance
                                .updatePreferences(showTitle: v),
                          ),
                        ],
                      ),
                    ),
                  ]),
                  if (config.photos.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        SettingsScreen.buildSectionTitle(
                          'WIDGET PLAYLIST (${config.photos.length})',
                        ),
                        TextButton(
                          onPressed: () => HomeWidgetService.instance.clearAll(),
                          child: const Text(
                            'Clear All',
                            style: TextStyle(
                              color: Colors.redAccent,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _buildPlaylistGrid(config),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPreviewCard(HomeWidgetConfig config) {
    final activePhoto = config.photos.isEmpty
        ? null
        : config.photos[config.currentIndex.clamp(0, config.photos.length - 1)];
    final hasFile =
        activePhoto != null && File(activePhoto.localPath).existsSync();

    return Center(
      child: Container(
        width: 188,
        height: 236,
        decoration: BoxDecoration(
          color: const Color(0xFF161426),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: tabColor.withValues(alpha: 0.4),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: tabColor.withValues(alpha: 0.16),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasFile)
              Image.file(File(activePhoto.localPath), fit: BoxFit.cover)
            else
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.widgets_rounded,
                      color: tabColor.withValues(alpha: 0.8),
                      size: 38,
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'No Photos Pinned',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Sync a collection below or pin from any photo viewer',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            if (activePhoto != null &&
                (config.showTitle || config.photos.length > 1))
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 22, 10, 10),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Color(0xBB0F0E17),
                        Color(0xEE0F0E17),
                      ],
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: config.showTitle
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    activePhoto.title.isNotEmpty
                                        ? activePhoto.title
                                        : config.sourceLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (config.photos.length > 1)
                                    Text(
                                      '${config.currentIndex + 1} / ${config.photos.length}',
                                      style: const TextStyle(
                                        color: Color(0xFFFFD700),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                ],
                              )
                            : const SizedBox.shrink(),
                      ),
                      if (config.photos.length > 1)
                        GestureDetector(
                          onTap: () => HomeWidgetService.instance.nextPhoto(),
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: const Color(0x90161426),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0x90FFD700),
                              ),
                            ),
                            child: const Icon(
                              Icons.refresh_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPinBanner() {
    final placedCount = _nativeStatus.installedCount;
    return SettingsScreen.buildCard([
      Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  placedCount > 0
                      ? Icons.check_circle_rounded
                      : Icons.add_to_home_screen_rounded,
                  color: placedCount > 0 ? const Color(0xFF00E676) : tabColor,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    placedCount > 0
                        ? '$placedCount active widget${placedCount == 1 ? '' : 's'} on your Home Screen'
                        : 'Place this photo widget on your Android Home Screen',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: tabColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _pinToHomeScreen,
              icon: const Icon(Icons.add_to_home_screen_rounded, size: 18),
              label: const Text(
                'Add Widget to Home Screen',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    ]);
  }

  Widget _buildPlaylistGrid(HomeWidgetConfig config) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.8,
      ),
      itemCount: config.photos.length,
      itemBuilder: (_, idx) {
        final photo = config.photos[idx];
        final isActive = idx == config.currentIndex;
        final exists = File(photo.localPath).existsSync();
        return GestureDetector(
          onTap: () => HomeWidgetService.instance.selectIndex(idx),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isActive ? const Color(0xFFFFD700) : Colors.white12,
                width: isActive ? 2.0 : 0.8,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (exists)
                  Image.file(File(photo.localPath), fit: BoxFit.cover)
                else
                  Container(color: const Color(0xFF161426)),
                Positioned(
                  top: 4,
                  right: 4,
                  child: GestureDetector(
                    onTap: () => HomeWidgetService.instance.removePhoto(photo.id),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                  ),
                ),
                if (isActive)
                  Positioned(
                    bottom: 4,
                    left: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xCC000000),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Showing',
                        style: TextStyle(
                          color: Color(0xFFFFD700),
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
