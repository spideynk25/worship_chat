import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/utils/app_capabilities.dart';
import 'package:worship_chat/common/utils/google_lens_service.dart';
import 'package:worship_chat/common/utils/utils.dart';
import 'package:worship_chat/features/bookmark/controller/bookmark_controller.dart';
import 'package:worship_chat/features/bookmark/screens/bookmark_screen.dart';
import 'package:worship_chat/features/bookmark/widgets/add_bookmarks_to_collection_sheet.dart';
import 'package:worship_chat/features/bookmark/widgets/save_to_collection_sheet.dart';
import 'package:worship_chat/features/chat/widgets/forward_message_sheet.dart';
import 'package:worship_chat/features/group/screens/slide_show_screen.dart';
import 'package:worship_chat/features/group/services/gallery_media_service.dart';
import 'package:worship_chat/models/bookmark_collection_model.dart';
import 'package:worship_chat/models/bookmark_model.dart';
import 'package:worship_chat/models/group_gallery_image.dart';

/// Screen displaying the bookmarks contained within a specific Collection / Folder.
class CollectionDetailScreen extends ConsumerStatefulWidget {
  final BookmarkCollectionModel collection;
  final String userId;
  final String currentUserId;
  final bool isOwner;

  const CollectionDetailScreen({
    super.key,
    required this.collection,
    required this.userId,
    required this.currentUserId,
    required this.isOwner,
  });

  @override
  ConsumerState<CollectionDetailScreen> createState() =>
      _CollectionDetailScreenState();
}

class _CollectionDetailScreenState
    extends ConsumerState<CollectionDetailScreen> {
  late BookmarkCollectionModel _collection;
  List<BookmarkModel>? _shuffledBookmarks;
  bool _isShuffled = false;

  @override
  void initState() {
    super.initState();
    _collection = widget.collection;
  }

  void _shuffleImages(List<BookmarkModel> original) {
    final shuffled = List.of(original)..shuffle();
    setState(() {
      _shuffledBookmarks = shuffled;
      _isShuffled = true;
    });
  }

  void _restoreOrder() {
    setState(() {
      _shuffledBookmarks = null;
      _isShuffled = false;
    });
  }

  List<GroupGalleryImage> _toGalleryImages(List<BookmarkModel> bookmarks) {
    return bookmarks
        .map(
          (bm) => GroupGalleryImage(
            imageId: bm.bookmarkId,
            groupId: bm.groupId,
            imageUrl: bm.imageUrl,
            uploadedBy: bm.userId,
            uploadedByName: bm.userName,
            uploadedAt: bm.bookmarkedAt,
            caption: null,
          ),
        )
        .toList();
  }

  Future<void> _savePhoto(BookmarkModel bm) async {
    try {
      final media = GalleryMediaService();
      final result = await media.saveImage(
        imageUrl: bm.imageUrl,
        imageId: bm.bookmarkId,
      );
      if (mounted && result != GallerySaveResult.cancelled) {
        AppSnackBar.show(
          context,
          message: result == GallerySaveResult.saved
              ? (media.isDesktop
                    ? '✅ Saved photo in high quality'
                    : '✅ Saved in high quality to Worship Chat album')
              : '⚠️ Could not save',
        );
      }
    } catch (_) {
      if (mounted) {
        AppSnackBar.show(context, message: '⚠️ Download failed');
      }
    }
  }

  void _showRenameDialog() {
    final ctrl = TextEditingController(text: _collection.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1A2D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Rename Collection',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Collection name',
            hintStyle: TextStyle(color: Colors.white38),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: tabColor, width: 2),
            ),
          ),
          onSubmitted: (val) {
            Navigator.pop(ctx);
            _performRename(val);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white60),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: tabColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _performRename(ctrl.text);
            },
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _performRename(String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty || trimmed == _collection.name) return;
    final ok = await ref
        .read(bookmarkControllerProvider)
        .updateCollectionName(collectionId: _collection.id, newName: trimmed);
    if (ok && mounted) {
      setState(() {
        _collection = _collection.copyWith(name: trimmed);
      });
      AppSnackBar.show(context, message: 'Collection renamed');
    }
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1A2D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Collection?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to delete "${_collection.name}"? The bookmarked photos will remain in All Bookmarks.',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white60),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (ok == true) {
      await ref
          .read(bookmarkControllerProvider)
          .deleteCollection(_collection.id);
      if (mounted) {
        Navigator.pop(context);
        AppSnackBar.show(context, message: 'Collection deleted');
      }
    }
  }

  void _showBookmarkOptions({
    required BookmarkModel bm,
    required List<BookmarkModel> bookmarks,
    required int index,
  }) {
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
            if (widget.isOwner)
              ListTile(
                leading: const Icon(
                  Icons.folder_off_rounded,
                  color: accentOrange,
                ),
                title: const Text(
                  'Remove from this collection',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  'Keeps photo in All Bookmarks',
                  style: TextStyle(color: Colors.grey[400], fontSize: 11),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  await ref
                      .read(bookmarkControllerProvider)
                      .removeBookmarkFromCollection(
                        collectionId: _collection.id,
                        bookmarkId: bm.bookmarkId,
                      );
                  if (mounted) {
                    AppSnackBar.show(
                      context,
                      message: 'Removed from "${_collection.name}"',
                    );
                  }
                },
              ),
            if (widget.isOwner)
              ListTile(
                leading: const Icon(
                  Icons.folder_copy_outlined,
                  color: tabColor,
                ),
                title: const Text(
                  'Manage Collections',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Organize into other folders',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  SaveToCollectionSheet.show(
                    context: context,
                    bookmarkId: bm.bookmarkId,
                    imageUrl: bm.imageUrl,
                    userId: widget.userId,
                  );
                },
              ),
            if (AppCapabilities.current.chatEnabled)
              ListTile(
                leading: const Icon(Icons.forward_rounded, color: tabColor),
                title: const Text(
                  'Forward Photo',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  ForwardMessageSheet.show(
                    context,
                    ForwardMessagePayload(
                      text: '',
                      messageType: 'image',
                      fileMessageData: bm.imageUrl,
                      isFromGallery: true,
                      sourceGroupId: bm.groupId,
                      sourceGroupName: bm.groupName.isNotEmpty
                          ? bm.groupName
                          : _collection.name,
                    ),
                  );
                },
              ),
            ListTile(
              leading: const Icon(Icons.slideshow_rounded, color: tabColor),
              title: const Text(
                'Start Slideshow',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SlideshowScreen(
                      images: _toGalleryImages(bookmarks),
                      initialIndex: index,
                      accentColor: tabColor,
                      groupName: _collection.name,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const GoogleLensIcon(size: 22),
              title: const Text(
                'Search with Google Lens',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: const Text(
                'Find source, products & visual matches',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(ctx);
                GoogleLensService.search(
                  context: context,
                  imageUrl: bm.imageUrl,
                );
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.download_rounded,
                color: Colors.white70,
              ),
              title: const Text(
                'Save Photo',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _savePhoto(bm);
              },
            ),
            if (widget.isOwner)
              ListTile(
                leading: const Icon(
                  Icons.bookmark_remove,
                  color: Colors.redAccent,
                ),
                title: const Text(
                  'Remove Bookmark Entirely',
                  style: TextStyle(color: Colors.redAccent),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      backgroundColor: Colors.grey[900],
                      title: const Text(
                        'Remove Bookmark Completely?',
                        style: TextStyle(color: Colors.white),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text(
                            'Remove',
                            style: TextStyle(color: Colors.redAccent),
                          ),
                        ),
                      ],
                    ),
                  );

                  if (ok == true) {
                    await ref
                        .read(bookmarkControllerProvider)
                        .toggleBookmark(
                          imageUrl: bm.imageUrl,
                          groupId: bm.groupId,
                          groupName: bm.groupName,
                          userName: bm.userName,
                          userProfilePic: bm.userProfilePic,
                        );
                    if (mounted) {
                      AppSnackBar.show(context, message: 'Bookmark removed');
                    }
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<BookmarkCollectionModel>>(
      stream: ref
          .watch(bookmarkControllerProvider)
          .collectionsForUser(widget.userId),
      builder: (context, colSnap) {
        // Find live collection if available
        final cols = colSnap.data ?? [];
        final liveCol = cols.firstWhere(
          (c) => c.id == _collection.id,
          orElse: () => _collection,
        );
        _collection = liveCol;

        return StreamBuilder<List<BookmarkModel>>(
          stream: ref
              .watch(bookmarkControllerProvider)
              .bookmarksForUser(widget.userId),
          builder: (context, bmSnap) {
            final allBookmarks = bmSnap.data ?? [];
            final collectionBookmarks = allBookmarks
                .where((bm) => _collection.containsBookmark(bm.bookmarkId))
                .toList();

            final displayList = _isShuffled && _shuffledBookmarks != null
                ? _shuffledBookmarks!
                : collectionBookmarks;

            return Scaffold(
              backgroundColor: backgroundColor,
              appBar: AppBar(
                backgroundColor: appBarColor,
                elevation: 0,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                  onPressed: () => Navigator.pop(context),
                ),
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _collection.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${collectionBookmarks.length} photo${collectionBookmarks.length == 1 ? '' : 's'}',
                      style: TextStyle(color: Colors.grey[400], fontSize: 11),
                    ),
                  ],
                ),
                actions: [
                  // Shuffle / Restore
                  if (collectionBookmarks.isNotEmpty) ...[
                    if (_isShuffled) ...[
                      IconButton(
                        icon: const Icon(
                          Icons.shuffle_rounded,
                          color: tabColor,
                        ),
                        tooltip: 'Shuffle again',
                        onPressed: () => _shuffleImages(collectionBookmarks),
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
                        icon: const Icon(
                          Icons.shuffle_rounded,
                          color: Colors.white54,
                        ),
                        tooltip: 'Shuffle',
                        onPressed: () => _shuffleImages(collectionBookmarks),
                      ),

                    // Slideshow
                    IconButton(
                      icon: const Icon(
                        Icons.slideshow_rounded,
                        color: Colors.white,
                      ),
                      tooltip: 'Slideshow',
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SlideshowScreen(
                            images: _toGalleryImages(displayList),
                            initialIndex: 0,
                            accentColor: tabColor,
                            groupName: _collection.name,
                          ),
                        ),
                      ),
                    ),
                  ],

                  // Add Photos
                  if (widget.isOwner)
                    IconButton(
                      icon: const Icon(
                        Icons.add_photo_alternate_outlined,
                        color: tabColor,
                      ),
                      tooltip: 'Add photos',
                      onPressed: () => AddBookmarksToCollectionSheet.show(
                        context: context,
                        collection: _collection,
                        allBookmarks: allBookmarks,
                      ),
                    ),

                  // Menu
                  if (widget.isOwner)
                    PopupMenuButton<String>(
                      icon: const Icon(
                        Icons.more_vert_rounded,
                        color: Colors.white,
                      ),
                      color: const Color(0xFF242036),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      onSelected: (val) {
                        if (val == 'rename') _showRenameDialog();
                        if (val == 'delete') _confirmDelete();
                      },
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(
                          value: 'rename',
                          child: Row(
                            children: [
                              Icon(
                                Icons.edit_rounded,
                                color: Colors.white,
                                size: 16,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Edit Name',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(
                                Icons.delete_outline_rounded,
                                color: Colors.redAccent,
                                size: 16,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Delete Collection',
                                style: TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              body: SafeArea(
                top: false,
                child: collectionBookmarks.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: tabColor.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.folder_open_rounded,
                                  size: 38,
                                  color: tabColor,
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'This collection is empty',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Add bookmarked photos into "${_collection.name}" to organize them.',
                                style: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 13,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              if (widget.isOwner &&
                                  allBookmarks.isNotEmpty) ...[
                                const SizedBox(height: 20),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: tabColor,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.add_photo_alternate_rounded,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                  label: const Text(
                                    'Add Photos',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  onPressed: () =>
                                      AddBookmarksToCollectionSheet.show(
                                        context: context,
                                        collection: _collection,
                                        allBookmarks: allBookmarks,
                                      ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(3),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount:
                              (MediaQuery.sizeOf(context).width / 200)
                                  .floor()
                                  .clamp(3, 12),
                          crossAxisSpacing: 3,
                          mainAxisSpacing: 3,
                        ),
                        itemCount: displayList.length,
                        itemBuilder: (context, index) {
                          final bm = displayList[index];
                          return GestureDetector(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => BookmarkFullscreenViewer(
                                  bookmarks: displayList,
                                  initialIndex: index,
                                  currentUserId: widget.currentUserId,
                                  isOwner: widget.isOwner,
                                  onRemove: widget.isOwner
                                      ? (bm) async {
                                          await ref
                                              .read(bookmarkControllerProvider)
                                              .removeBookmarkFromCollection(
                                                collectionId: _collection.id,
                                                bookmarkId: bm.bookmarkId,
                                              );
                                        }
                                      : null,
                                ),
                              ),
                            ),
                            onLongPress: () => _showBookmarkOptions(
                              bm: bm,
                              bookmarks: displayList,
                              index: index,
                            ),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                CachedNetworkImage(
                                  imageUrl: bm.imageUrl,
                                  fit: BoxFit.cover,
                                ),
                                const Positioned(
                                  top: 4,
                                  right: 4,
                                  child: Icon(
                                    Icons.bookmark,
                                    color: Colors.amber,
                                    size: 16,
                                    shadows: [
                                      Shadow(
                                        color: Colors.black54,
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            );
          },
        );
      },
    );
  }
}
