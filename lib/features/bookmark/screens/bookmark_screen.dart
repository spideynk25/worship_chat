import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/utils/app_capabilities.dart';
import 'package:worship_chat/common/utils/google_lens_service.dart';
import 'package:worship_chat/common/utils/utils.dart';
import 'package:worship_chat/features/group/services/gallery_media_service.dart';
import 'package:worship_chat/features/group/widgets/gallery_navigation_controls.dart';
import 'package:worship_chat/common/widgets/photo_text_remover_sheet.dart';
import 'package:worship_chat/common/widgets/set_as_profile_pic_sheet.dart';
import 'package:worship_chat/common/widgets/skeleton_loader.dart';
import 'package:worship_chat/common/widgets/user_avatar.dart';
import 'package:worship_chat/common/widgets/wallpaper_widget_sheet.dart';
import 'package:worship_chat/features/bookmark/controller/bookmark_controller.dart';
import 'package:worship_chat/features/chat/widgets/forward_message_sheet.dart';
import 'package:worship_chat/features/group/screens/slide_show_screen.dart';
import 'package:worship_chat/features/bookmark/screens/collection_detail_screen.dart';
import 'package:worship_chat/features/bookmark/widgets/bookmark_collection_card.dart';
import 'package:worship_chat/features/bookmark/widgets/save_to_collection_sheet.dart';
import 'package:worship_chat/models/bookmark_collection_model.dart';
import 'package:worship_chat/models/bookmark_model.dart';
import 'package:worship_chat/models/group_gallery_image.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BookmarkScreen — user list
// ─────────────────────────────────────────────────────────────────────────────

class BookmarkScreen extends ConsumerWidget {
  static const routeName = '/bookmarks';
  const BookmarkScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: appBarColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Bookmarks',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: SafeArea(
        top: false,
        child: StreamBuilder<List<BookmarkModel>>(
          stream: ref.watch(bookmarkControllerProvider).allBookmarks(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const BookmarkUserListSkeleton();
            }

            final all = snapshot.data ?? [];

            if (all.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.bookmark_outline,
                      size: 52,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No bookmarks yet',
                      style: TextStyle(color: Colors.grey[400], fontSize: 15),
                    ),
                  ],
                ),
              );
            }

            // Group by userId, current user always first
            final Map<String, _UserBookmarkSummary> byUser = {};
            for (final bm in all) {
              if (!byUser.containsKey(bm.userId)) {
                byUser[bm.userId] = _UserBookmarkSummary(
                  userId: bm.userId,
                  userName: bm.userName,
                  userProfilePic: bm.userProfilePic,
                  bookmarks: [],
                );
              }
              byUser[bm.userId]!.bookmarks.add(bm);
            }

            final users = byUser.values.toList()
              ..sort((a, b) {
                if (a.userId == currentUserId) return -1;
                if (b.userId == currentUserId) return 1;
                return a.userName.compareTo(b.userName);
              });

            return ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: users.length,
              separatorBuilder: (_, __) =>
                  Divider(color: Colors.grey[800], height: 1, indent: 72),
              itemBuilder: (context, index) {
                final u = users[index];
                return _BookmarkUserTile(
                  summary: u,
                  currentUserId: currentUserId,
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _BookmarkUserTile extends StatelessWidget {
  final _UserBookmarkSummary summary;
  final String currentUserId;

  const _BookmarkUserTile({required this.summary, required this.currentUserId});

  @override
  Widget build(BuildContext context) {
    final isMe = summary.userId == currentUserId;
    final previews = summary.bookmarks.take(3).toList();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(summary.userId)
          .snapshots(),
      builder: (context, snapshot) {
        final userData = snapshot.data?.data();
        final liveProfilePic = userData?['profilePic'] as String?;
        final liveName = userData?['name'] as String?;

        final effectiveProfilePic =
            (liveProfilePic != null && liveProfilePic.isNotEmpty)
            ? liveProfilePic
            : summary.userProfilePic;
        final effectiveName = (liveName != null && liveName.isNotEmpty)
            ? liveName
            : summary.userName;

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          leading: Stack(
            children: [
              UserAvatar(url: effectiveProfilePic, radius: 26),
              if (isMe)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: tabColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: backgroundColor, width: 1.5),
                    ),
                    child: const Icon(
                      Icons.person,
                      size: 10,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
          title: Text(
            isMe ? '$effectiveName (You)' : effectiveName,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          subtitle: Text(
            '${summary.bookmarks.length} bookmark${summary.bookmarks.length == 1 ? '' : 's'}',
            style: TextStyle(color: Colors.grey[500], fontSize: 12),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...previews.map(
                (bm) => Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: CachedNetworkImage(
                      imageUrl: bm.imageUrl,
                      width: 36,
                      height: 36,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
              if (summary.bookmarks.length > 3)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.grey[800],
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Center(
                      child: Text(
                        '+${summary.bookmarks.length - 3}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
            ],
          ),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => _UserBookmarksScreen(
                userId: summary.userId,
                userName: isMe ? '$effectiveName (You)' : effectiveName,
                userProfilePic: effectiveProfilePic,
                currentUserId: currentUserId,
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// User bookmark summary (local)
// ─────────────────────────────────────────────────────────────────────────────

class _UserBookmarkSummary {
  final String userId;
  final String userName;
  final String userProfilePic;
  final List<BookmarkModel> bookmarks;

  _UserBookmarkSummary({
    required this.userId,
    required this.userName,
    required this.userProfilePic,
    required this.bookmarks,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Individual user's bookmarks screen — grid with fullscreen + slideshow
// ─────────────────────────────────────────────────────────────────────────────

class _UserBookmarksScreen extends ConsumerStatefulWidget {
  final String userId;
  final String userName;
  final String userProfilePic;
  final String currentUserId;

  const _UserBookmarksScreen({
    required this.userId,
    required this.userName,
    required this.userProfilePic,
    required this.currentUserId,
  });

  @override
  ConsumerState<_UserBookmarksScreen> createState() =>
      _UserBookmarksScreenState();
}

class _UserBookmarksScreenState extends ConsumerState<_UserBookmarksScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  List<BookmarkModel>? _shuffledBookmarks;
  bool _isShuffled = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  void _showCreateCollectionDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1A2D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'New Collection',
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
            _createCollection(val);
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
              _createCollection(ctrl.text);
            },
            child: const Text('Create', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _createCollection(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final col = await ref
        .read(bookmarkControllerProvider)
        .createCollection(name: trimmed);
    if (mounted && col != null) {
      AppSnackBar.show(context, message: 'Collection "${col.name}" created');
    }
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

  // Convert BookmarkModel list to GroupGalleryImage list for slideshow
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

  void _showBookmarkOptions({
    required BookmarkModel bm,
    required List<BookmarkModel> bookmarks,
    required int index,
    required bool isMe,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1B1728),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
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
            if (AppCapabilities.current.chatEnabled)
              ListTile(
                leading: const Icon(Icons.forward_rounded, color: tabColor),
                title: const Text(
                  'Forward Photo',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Send to chat or another gallery',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
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
                          : 'Bookmarks',
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
                      groupName: '${widget.userName}\'s Bookmarks',
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
                  origin: PhotoTextRemoverOrigin.bookmarks,
                  imageUrl: bm.imageUrl,
                  groupId: bm.groupId,
                  groupName: bm.groupName,
                  sourceBookmarkId: bm.bookmarkId,
                  isOwner: isMe,
                  title: bm.groupName.isNotEmpty
                      ? bm.groupName
                      : widget.userName,
                );
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.wallpaper_rounded,
                color: Color(0xFFFFD700),
              ),
              title: const Text(
                'Wallpaper & Home Widget',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: const Text(
                'Set phone wallpaper or pin to widget',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(ctx);
                WallpaperAndWidgetSheet.show(
                  context,
                  photoId: 'bm_${bm.bookmarkId}',
                  imageUrl: bm.imageUrl,
                  title: bm.groupName.isNotEmpty
                      ? bm.groupName
                      : widget.userName,
                  subtitle: 'Saved Bookmark',
                );
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.account_circle_outlined,
                color: tabColor,
              ),
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
                  imageUrl: bm.imageUrl,
                  sourceGroupId: bm.groupId,
                  sourceGroupName: bm.groupName,
                  title: bm.groupName.isNotEmpty
                      ? bm.groupName
                      : widget.userName,
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
            if (isMe)
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
                  'Organize into folders',
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
            if (isMe)
              ListTile(
                leading: const Icon(
                  Icons.bookmark_remove,
                  color: Colors.redAccent,
                ),
                title: const Text(
                  'Remove Bookmark',
                  style: TextStyle(color: Colors.redAccent),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      backgroundColor: Colors.grey[900],
                      title: const Text(
                        'Remove Bookmark?',
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMe = widget.userId == widget.currentUserId;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: appBarColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(widget.userId)
              .snapshots(),
          builder: (context, snapshot) {
            final data = snapshot.data?.data();
            final pic = (data?['profilePic'] as String?)?.isNotEmpty == true
                ? data!['profilePic'] as String
                : widget.userProfilePic;
            final name = (data?['name'] as String?)?.isNotEmpty == true
                ? (isMe ? '${data!['name']} (You)' : data!['name'] as String)
                : widget.userName;

            return Row(
              children: [
                UserAvatar(url: pic, radius: 16),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            );
          },
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Colors.white.withValues(alpha: 0.08),
                  width: 1,
                ),
              ),
            ),
            child: TabBar(
              controller: _tabCtrl,
              indicatorColor: tabColor,
              indicatorWeight: 2.5,
              labelColor: tabColor,
              unselectedLabelColor: Colors.grey[400],
              labelStyle: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
              tabs: const [
                Tab(
                  icon: Icon(Icons.folder_copy_rounded, size: 18),
                  text: 'Collections',
                ),
                Tab(
                  icon: Icon(Icons.grid_view_rounded, size: 18),
                  text: 'All Bookmarks',
                ),
              ],
            ),
          ),
        ),
        actions: [
          if (isMe)
            IconButton(
              icon: const Icon(
                Icons.create_new_folder_outlined,
                color: tabColor,
              ),
              tooltip: 'New Collection',
              onPressed: _showCreateCollectionDialog,
            ),
          StreamBuilder<List<BookmarkModel>>(
            stream: ref
                .watch(bookmarkControllerProvider)
                .bookmarksForUser(widget.userId),
            builder: (context, snapshot) {
              final bookmarks = snapshot.data ?? [];
              if (bookmarks.isEmpty) return const SizedBox.shrink();
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isShuffled) ...[
                    IconButton(
                      icon: const Icon(Icons.shuffle_rounded, color: tabColor),
                      tooltip: 'Shuffle again',
                      onPressed: () => _shuffleImages(bookmarks),
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
                      onPressed: () => _shuffleImages(bookmarks),
                    ),
                ],
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: TabBarView(
          controller: _tabCtrl,
          children: [
            // ── TAB 1: INSTAGRAM STYLE COLLECTIONS ──
            _buildCollectionsTab(isMe),

            // ── TAB 2: ALL BOOKMARKS GRID ──
            _buildAllBookmarksTab(isMe),
          ],
        ),
      ),
    );
  }

  Widget _buildCollectionsTab(bool isMe) {
    return StreamBuilder<List<BookmarkModel>>(
      stream: ref
          .watch(bookmarkControllerProvider)
          .bookmarksForUser(widget.userId),
      builder: (context, bmSnap) {
        return StreamBuilder<List<BookmarkCollectionModel>>(
          stream: ref
              .watch(bookmarkControllerProvider)
              .collectionsForUser(widget.userId),
          builder: (context, colSnap) {
            if (bmSnap.connectionState == ConnectionState.waiting &&
                colSnap.connectionState == ConnectionState.waiting) {
              return const BookmarkGridSkeleton();
            }

            final allBookmarks = bmSnap.data ?? [];
            final collections = colSnap.data ?? [];

            if (allBookmarks.isEmpty && collections.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.bookmark_outline,
                      size: 52,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No bookmarks yet',
                      style: TextStyle(color: Colors.grey[400], fontSize: 15),
                    ),
                  ],
                ),
              );
            }

            final totalCards = 1 + collections.length + (isMe ? 1 : 0);

            return GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: (MediaQuery.sizeOf(context).width / 180)
                    .floor()
                    .clamp(2, 6),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.78,
              ),
              itemCount: totalCards,
              itemBuilder: (context, index) {
                // First Card: All Bookmarks
                if (index == 0) {
                  return BookmarkCollectionCard(
                    title: 'All Bookmarks',
                    count: allBookmarks.length,
                    previewImageUrls: allBookmarks
                        .take(4)
                        .map((b) => b.imageUrl)
                        .toList(),
                    isAllBookmarks: true,
                    canManage: false,
                    onTap: () => _tabCtrl.animateTo(1),
                  );
                }

                // Collections Cards
                final colIndex = index - 1;
                if (colIndex < collections.length) {
                  final col = collections[colIndex];
                  final matching = allBookmarks
                      .where((b) => col.containsBookmark(b.bookmarkId))
                      .toList();
                  final previews = matching.isNotEmpty
                      ? matching.map((b) => b.imageUrl).toList()
                      : (col.coverImageUrl != null
                            ? [col.coverImageUrl!]
                            : <String>[]);

                  return BookmarkCollectionCard(
                    collection: col,
                    title: col.name,
                    count: matching.length,
                    previewImageUrls: previews,
                    isAllBookmarks: false,
                    canManage: isMe,
                    onRename: () => _showRenameDialog(col),
                    onDelete: () => _confirmDeleteCollection(col),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CollectionDetailScreen(
                          collection: col,
                          userId: widget.userId,
                          currentUserId: widget.currentUserId,
                          isOwner: isMe,
                        ),
                      ),
                    ),
                  );
                }

                // New Collection Tile (Instagram Style)
                return GestureDetector(
                  onTap: _showCreateCollectionDialog,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B1728),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: tabColor.withValues(alpha: 0.35),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: tabColor.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.add_rounded,
                            color: tabColor,
                            size: 28,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'New Collection',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Create folder',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  void _showRenameDialog(BookmarkCollectionModel col) {
    final ctrl = TextEditingController(text: col.name);
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
            _performRename(col, val);
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
              _performRename(col, ctrl.text);
            },
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _performRename(
    BookmarkCollectionModel col,
    String newName,
  ) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty || trimmed == col.name) return;
    final ok = await ref
        .read(bookmarkControllerProvider)
        .updateCollectionName(collectionId: col.id, newName: trimmed);
    if (ok && mounted) {
      AppSnackBar.show(context, message: 'Collection renamed');
    }
  }

  Future<void> _confirmDeleteCollection(BookmarkCollectionModel col) async {
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
          'Are you sure you want to delete "${col.name}"? The bookmarked photos will remain in All Bookmarks.',
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
      await ref.read(bookmarkControllerProvider).deleteCollection(col.id);
      if (mounted) {
        AppSnackBar.show(context, message: 'Collection deleted');
      }
    }
  }

  Widget _buildAllBookmarksTab(bool isMe) {
    return StreamBuilder<List<BookmarkModel>>(
      stream: ref
          .watch(bookmarkControllerProvider)
          .bookmarksForUser(widget.userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const BookmarkGridSkeleton();
        }

        final original = snapshot.data ?? [];
        final bookmarks = _isShuffled && _shuffledBookmarks != null
            ? _shuffledBookmarks!
            : original;

        if (bookmarks.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.bookmark_outline, size: 52, color: Colors.grey[600]),
                const SizedBox(height: 16),
                Text(
                  'No bookmarks yet',
                  style: TextStyle(color: Colors.grey[400], fontSize: 15),
                ),
              ],
            ),
          );
        }

        return GridView.builder(
          padding: const EdgeInsets.all(3),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: (MediaQuery.sizeOf(context).width / 200)
                .floor()
                .clamp(3, 12),
            crossAxisSpacing: 3,
            mainAxisSpacing: 3,
          ),
          itemCount: bookmarks.length,
          itemBuilder: (context, index) {
            final bm = bookmarks[index];
            return GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => BookmarkFullscreenViewer(
                    bookmarks: bookmarks,
                    initialIndex: index,
                    currentUserId: widget.currentUserId,
                    isOwner: isMe,
                    onRemove: isMe
                        ? (bm) async {
                            await ref
                                .read(bookmarkControllerProvider)
                                .toggleBookmark(
                                  imageUrl: bm.imageUrl,
                                  groupId: bm.groupId,
                                  groupName: bm.groupName,
                                  userName: bm.userName,
                                  userProfilePic: bm.userProfilePic,
                                );
                          }
                        : null,
                  ),
                ),
              ),
              onLongPress: () => _showBookmarkOptions(
                bm: bm,
                bookmarks: bookmarks,
                index: index,
                isMe: isMe,
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(imageUrl: bm.imageUrl, fit: BoxFit.cover),
                  const Positioned(
                    top: 4,
                    right: 4,
                    child: Icon(
                      Icons.bookmark,
                      color: Colors.amber,
                      size: 16,
                      shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Fullscreen viewer for bookmarks
// ─────────────────────────────────────────────────────────────────────────────

class BookmarkFullscreenViewer extends ConsumerStatefulWidget {
  final List<BookmarkModel> bookmarks;
  final int initialIndex;
  final String currentUserId;
  final bool isOwner;
  final String? sourceCollectionId;
  final Future<void> Function(BookmarkModel bm)? onRemove;

  const BookmarkFullscreenViewer({
    super.key,
    required this.bookmarks,
    required this.initialIndex,
    required this.currentUserId,
    required this.isOwner,
    this.sourceCollectionId,
    required this.onRemove,
  });

  @override
  ConsumerState<BookmarkFullscreenViewer> createState() =>
      BookmarkFullscreenViewerState();
}

class BookmarkFullscreenViewerState
    extends ConsumerState<BookmarkFullscreenViewer> {
  late PageController _pageCtrl;
  late int _index;
  late List<BookmarkModel> _bookmarks;
  bool _overlayOn = true;
  bool _isDownloading = false;

  // Convert BookmarkModel list to GroupGalleryImage list for slideshow
  List<GroupGalleryImage> get _asGalleryImages => _bookmarks
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

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _bookmarks = List<BookmarkModel>.from(widget.bookmarks);
    _pageCtrl = PageController(initialPage: widget.initialIndex);
  }

  @override
  void didUpdateWidget(covariant BookmarkFullscreenViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bookmarks != widget.bookmarks) {
      _bookmarks = List<BookmarkModel>.from(widget.bookmarks);
      if (_index >= _bookmarks.length && _bookmarks.isNotEmpty) {
        _index = _bookmarks.length - 1;
      }
    }
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<void> _downloadCurrent() async {
    if (_isDownloading) return;
    setState(() => _isDownloading = true);

    try {
      final bm = _bookmarks[_index];
      final media = GalleryMediaService();
      final result = await media.saveImage(
        imageUrl: bm.imageUrl,
        imageId: bm.bookmarkId,
      );
      if (mounted && result != GallerySaveResult.cancelled) {
        _snack(
          result == GallerySaveResult.saved
              ? (media.isDesktop
                    ? '✅ Saved photo in high quality'
                    : '✅ Saved in high quality to Worship Chat album')
              : '⚠️ Could not save',
        );
      }
    } catch (_) {
      if (mounted) _snack('⚠️ Download failed', Colors.redAccent);
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  void _snack(String msg, [Color? color]) {
    if (!mounted) return;
    AppSnackBar.show(context, message: msg);
  }

  void _forwardCurrent() {
    if (!AppCapabilities.current.chatEnabled) return;
    final bm = _bookmarks[_index];
    ForwardMessageSheet.show(
      context,
      ForwardMessagePayload(
        text: '',
        messageType: 'image',
        fileMessageData: bm.imageUrl,
        isFromGallery: true,
        sourceGroupId: bm.groupId,
        sourceGroupName: bm.groupName.isNotEmpty ? bm.groupName : 'Bookmarks',
      ),
    );
  }

  Future<void> _confirmRemove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          'Remove Bookmark?',
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

    if (ok == true && widget.onRemove != null) {
      await widget.onRemove!(_bookmarks[_index]);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_bookmarks.isEmpty) {
      return const Scaffold(backgroundColor: Colors.black);
    }

    final bm = _bookmarks[_index];

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Photo gallery ──────────────────────────────────────────────
          PhotoViewGallery.builder(
            pageController: _pageCtrl,
            itemCount: _bookmarks.length,
            onPageChanged: (i) => setState(() => _index = i),
            scrollPhysics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            backgroundDecoration: const BoxDecoration(color: Colors.black),
            builder: (context, i) => PhotoViewGalleryPageOptions(
              imageProvider: CachedNetworkImageProvider(
                getOriginalHighQualityImageUrl(_bookmarks[i].imageUrl),
              ),
              minScale: PhotoViewComputedScale.contained,
              maxScale: PhotoViewComputedScale.covered * 4,
              onTapUp: (_, __, ___) => setState(() => _overlayOn = !_overlayOn),
              heroAttributes: PhotoViewHeroAttributes(
                tag: 'bookmark_${_bookmarks[i].bookmarkId}',
              ),
            ),
            loadingBuilder: (context, event) =>
                const Center(child: CircularProgressIndicator()),
          ),

          GalleryNavigationControls(
            controller: _pageCtrl,
            currentIndex: _index,
            imageCount: _bookmarks.length,
          ),

          // ── Overlay ────────────────────────────────────────────────────
          IgnorePointer(
            ignoring: !_overlayOn,
            child: AnimatedOpacity(
              opacity: _overlayOn ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Stack(
                children: [
                  // Top bar
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
                                        const Text(
                                          'Bookmark',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          bm.groupName,
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
                                horizontal: 16,
                                vertical: 2,
                              ),
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
                                  // ── Download ───────────────────────────
                                  IconButton(
                                    icon: _isDownloading
                                        ? SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: tabColor,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.download_rounded,
                                            color: Colors.white,
                                          ),
                                    tooltip: 'Save photo',
                                    onPressed: _isDownloading
                                        ? null
                                        : _downloadCurrent,
                                  ),

                                  // ── Forward ────────────────────────────
                                  if (AppCapabilities.current.chatEnabled)
                                    IconButton(
                                      icon: const Icon(
                                        Icons.forward_rounded,
                                        color: Colors.white,
                                      ),
                                      tooltip: 'Forward photo',
                                      onPressed: _forwardCurrent,
                                    ),

                                  // ── Slideshow ──────────────────────────
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
                                          images: _asGalleryImages,
                                          initialIndex: _index,
                                          accentColor: tabColor,
                                          groupName: bm.groupName,
                                        ),
                                      ),
                                    ),
                                  ),

                                  // ── Google Lens ────────────────────────
                                  IconButton(
                                    icon: const GoogleLensIcon(),
                                    tooltip: 'Search with Google Lens',
                                    onPressed: () => GoogleLensService.search(
                                      context: context,
                                      imageUrl: bm.imageUrl,
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
                                      origin: widget.sourceCollectionId != null
                                          ? PhotoTextRemoverOrigin
                                              .bookmarkCollection
                                          : PhotoTextRemoverOrigin.bookmarks,
                                      imageUrl: bm.imageUrl,
                                      groupId: bm.groupId,
                                      groupName: bm.groupName,
                                      sourceBookmarkId: bm.bookmarkId,
                                      sourceCollectionId:
                                          widget.sourceCollectionId,
                                      isOwner: widget.isOwner,
                                      title: bm.groupName.isNotEmpty
                                          ? bm.groupName
                                          : 'Saved Bookmark',
                                      onRemoteImageUpdated: (newUrl) {
                                        if (!mounted) return;
                                        setState(() {
                                          _bookmarks[_index] = BookmarkModel(
                                            bookmarkId: bm.bookmarkId,
                                            userId: bm.userId,
                                            userName: bm.userName,
                                            userProfilePic: bm.userProfilePic,
                                            imageUrl: newUrl,
                                            groupId: bm.groupId,
                                            groupName: bm.groupName,
                                            bookmarkedAt: DateTime.now(),
                                          );
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
                                      photoId: 'bm_${bm.bookmarkId}',
                                      imageUrl: bm.imageUrl,
                                      title: bm.groupName.isNotEmpty
                                          ? bm.groupName
                                          : 'Saved Bookmark',
                                      subtitle: 'Worship Chat Bookmarks',
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
                                      imageUrl: bm.imageUrl,
                                      sourceGroupId: bm.groupId,
                                      sourceGroupName: bm.groupName,
                                      title: bm.groupName.isNotEmpty
                                          ? bm.groupName
                                          : 'Saved Bookmark',
                                    ),
                                  ),

                                  // ── Save to Collection (own only) ──────
                                  if (widget.isOwner)
                                    IconButton(
                                      icon: const Icon(
                                        Icons.folder_copy_outlined,
                                        color: Colors.white,
                                      ),
                                      tooltip: 'Save to collection',
                                      onPressed: () {
                                        SaveToCollectionSheet.show(
                                          context: context,
                                          bookmarkId: bm.bookmarkId,
                                          imageUrl: bm.imageUrl,
                                          userId: widget.currentUserId,
                                        );
                                      },
                                    ),

                                  // ── Remove bookmark (own only) ─────────
                                  if (widget.isOwner)
                                    IconButton(
                                      icon: const Icon(
                                        Icons.bookmark_remove,
                                        color: Colors.redAccent,
                                      ),
                                      tooltip: 'Remove bookmark',
                                      onPressed: _confirmRemove,
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

                  // ── Bottom Info + Counter ────────────────────────────────
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
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Uploader info
                              StreamBuilder<
                                DocumentSnapshot<Map<String, dynamic>>
                              >(
                                stream: Firebase.apps.isNotEmpty
                                    ? FirebaseFirestore.instance
                                        .collection('users')
                                        .doc(bm.userId)
                                        .snapshots()
                                    : const Stream.empty(),
                                builder: (context, snapshot) {
                                  final data = snapshot.data?.data();
                                  final pic =
                                      (data?['profilePic'] as String?)
                                              ?.isNotEmpty ==
                                          true
                                      ? data!['profilePic'] as String
                                      : bm.userProfilePic;
                                  final name =
                                      (data?['name'] as String?)?.isNotEmpty ==
                                          true
                                      ? (bm.userId == widget.currentUserId
                                            ? 'You'
                                            : data!['name'] as String)
                                      : (bm.userId == widget.currentUserId
                                            ? 'You'
                                            : bm.userName);

                                  return Row(
                                    children: [
                                      UserAvatar(url: pic, radius: 14),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              name,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            Text(
                                              DateFormat(
                                                'd MMM yyyy',
                                              ).format(bm.bookmarkedAt),
                                              style: const TextStyle(
                                                color: Colors.white54,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        '${_index + 1} / ${widget.bookmarks.length}',
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  );
                                },
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
