import 'dart:developer';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gallery_saver_plus/gallery_saver.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/widgets/loader.dart';
import 'package:worship_chat/features/auth/controller/auth_controller.dart';
import 'package:worship_chat/features/bookmark/controller/bookmark_controller.dart';
import 'package:worship_chat/features/group/controller/group_gallery_controller.dart';
import 'package:worship_chat/features/group/screens/slide_show_screen.dart';
import 'package:worship_chat/models/group_gallery_image.dart';

// ─────────────────────────────────────────────────────────────────────────────
// GroupGalleryScreen
// ─────────────────────────────────────────────────────────────────────────────

class GroupGalleryScreen extends ConsumerStatefulWidget {
  final String groupId;
  final String groupName;
  final Color accentColor;

  const GroupGalleryScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.accentColor,
  });

  @override
  ConsumerState<GroupGalleryScreen> createState() => _GroupGalleryScreenState();
}

class _GroupGalleryScreenState extends ConsumerState<GroupGalleryScreen>
    with SingleTickerProviderStateMixin {
  final ValueNotifier<bool> _isUploadingNotifier = ValueNotifier(false);
  final ValueNotifier<int> _uploadedCountNotifier = ValueNotifier(0);
  final ValueNotifier<int> _totalToUploadNotifier = ValueNotifier(0);

  List<GroupGalleryImage>? _shuffledImages;
  bool _isShuffled = false;

  late final AnimationController _fabAnimController;
  late final Animation<double> _fabScaleAnim;

  Color get _accent {
    final hsl = HSLColor.fromColor(widget.accentColor);
    return hsl.lightness < 0.25
        ? hsl.withLightness(0.55).withSaturation(0.7).toColor()
        : widget.accentColor;
  }

  @override
  void initState() {
    super.initState();
    _fabAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _fabScaleAnim = CurvedAnimation(
      parent: _fabAnimController,
      curve: Curves.elasticOut,
    );
    _fabAnimController.forward();
  }

  @override
  void dispose() {
    _fabAnimController.dispose();
    _isUploadingNotifier.dispose();
    _uploadedCountNotifier.dispose();
    _totalToUploadNotifier.dispose();
    super.dispose();
  }

  // ── Shuffle ───────────────────────────────────────────────────────────────

  void _shuffleImages(List<GroupGalleryImage> original) {
    final shuffled = List.of(original)..shuffle();
    setState(() {
      _shuffledImages = shuffled;
      _isShuffled = true;
    });
  }

  void _restoreOrder() {
    setState(() {
      _shuffledImages = null;
      _isShuffled = false;
    });
  }

  // ── Upload ────────────────────────────────────────────────────────────────

  Future<void> _pickImages() async {
    try {
      final picked = await ImagePicker().pickMultiImage(imageQuality: 85);
      if (picked.isEmpty) return;
      final files = picked.map((x) => File(x.path)).toList();
      _showUploadSheet(files);
    } catch (e) {
      log('image picker error: $e');
      _snack('Could not open gallery.');
    }
  }

  void _showUploadSheet(List<File> files) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _UploadSheet(
        files: files,
        accentColor: _accent,
        onConfirm: () => _startUpload(files),
        onCancel: () {},
      ),
    );
  }

  Future<void> _startUpload(List<File> files) async {
    if (files.isEmpty) return;
    final userData = await ref.read(userDataAuthProvider.future);
    if (userData == null) return;

    _isUploadingNotifier.value = true;
    _uploadedCountNotifier.value = 0;
    _totalToUploadNotifier.value = files.length;

    final count = await ref
        .read(groupGalleryControllerProvider)
        .uploadImages(
          groupId: widget.groupId,
          imageFiles: files,
          uploaderName: userData.name ?? 'Unknown',
          caption: null,
          onProgress: (uploaded, total) {
            _uploadedCountNotifier.value = uploaded;
          },
        );

    if (mounted) {
      _isUploadingNotifier.value = false;
      _snack(count > 0 ? '✅ $count images uploaded!' : '⚠️ Upload failed.');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

    return StreamBuilder<List<GroupGalleryImage>>(
      stream: ref
          .watch(groupGalleryControllerProvider)
          .getGalleryStream(widget.groupId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return Scaffold(
            backgroundColor: backgroundColor,
            appBar: _buildAppBar([]),
            body: const Loader(),
          );
        }

        final originalImages = snapshot.data ?? [];
        final displayImages = _isShuffled && _shuffledImages != null
            ? _shuffledImages!
            : originalImages;

        return Scaffold(
          backgroundColor: backgroundColor,
          appBar: _buildAppBar(originalImages),
          floatingActionButton: ScaleTransition(
            scale: _fabScaleAnim,
            child: ValueListenableBuilder<bool>(
              valueListenable: _isUploadingNotifier,
              builder: (context, isUploading, _) {
                return ValueListenableBuilder<int>(
                  valueListenable: _uploadedCountNotifier,
                  builder: (context, uploaded, _) {
                    return ValueListenableBuilder<int>(
                      valueListenable: _totalToUploadNotifier,
                      builder: (context, total, _) {
                        return FloatingActionButton.extended(
                          onPressed: isUploading ? null : _pickImages,
                          backgroundColor: _accent,
                          icon: isUploading
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    value: total > 0 ? uploaded / total : null,
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.add_photo_alternate_outlined),
                          label: Text(
                            isUploading ? '$uploaded / $total' : 'Add Photos',
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
          body: _GalleryGrid(
            images: displayImages,
            groupId: widget.groupId,
            groupName: widget.groupName,
            accentColor: _accent,
            currentUserId: currentUserId,
            onDelete: (id) => ref
                .read(groupGalleryControllerProvider)
                .deleteImage(widget.groupId, id),
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(List<GroupGalleryImage> images) {
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
          Text(
            'Gallery',
            style: TextStyle(
              color: _accent,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          Text(
            widget.groupName,
            style: TextStyle(color: Colors.grey[400], fontSize: 12),
          ),
        ],
      ),
      actions: [
        // ── Shuffle controls ───────────────────────────────
        if (images.isNotEmpty) ...[
          if (_isShuffled) ...[
            IconButton(
              icon: Icon(Icons.shuffle_rounded, color: _accent),
              tooltip: 'Shuffle again',
              onPressed: () => _shuffleImages(images),
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
              tooltip: 'Shuffle',
              onPressed: () => _shuffleImages(images),
            ),
        ],

        // ── Upload progress ────────────────────────────────
        ValueListenableBuilder<bool>(
          valueListenable: _isUploadingNotifier,
          builder: (context, isUploading, _) {
            if (!isUploading) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: ValueListenableBuilder<int>(
                  valueListenable: _uploadedCountNotifier,
                  builder: (context, uploaded, _) {
                    return ValueListenableBuilder<int>(
                      valueListenable: _totalToUploadNotifier,
                      builder: (context, total, _) {
                        return SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            value: total > 0 ? uploaded / total : null,
                            color: _accent,
                            strokeWidth: 2.5,
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Fullscreen viewer
// ─────────────────────────────────────────────────────────────────────────────

class _FullscreenViewer extends ConsumerStatefulWidget {
  final List<GroupGalleryImage> images;
  final int initialIndex;
  final Color accentColor;
  final String currentUserId;
  final String groupName;
  final String groupId;
  final Future<void> Function(String imageId) onDelete;

  const _FullscreenViewer({
    required this.images,
    required this.initialIndex,
    required this.accentColor,
    required this.currentUserId,
    required this.groupName,
    required this.groupId,
    required this.onDelete,
  });

  @override
  ConsumerState<_FullscreenViewer> createState() => _FullscreenViewerState();
}

class _FullscreenViewerState extends ConsumerState<_FullscreenViewer> {
  late PageController _pageCtrl;
  late int _index;
  bool _overlayOn = true;
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _pageCtrl = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  // ── Download ──────────────────────────────────────────────────────────────

  Future<void> _downloadCurrent() async {
    if (_isDownloading) return;
    setState(() => _isDownloading = true);

    try {
      final img = widget.images[_index];
      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/${img.imageId}.jpg';

      await Dio().download(img.imageUrl, filePath);
      final saved = await GallerySaver.saveImage(
        filePath,
        albumName: 'Worship Chat', // ← custom album, not DCIM
        toDcim: false,
      );
      await File(filePath).delete();

      if (mounted) {
        _snack(
          saved == true ? '✅ Saved to Worship Chat album' : '⚠️ Could not save',
          saved == true ? Colors.green[700]! : Colors.redAccent,
        );
      }
    } catch (_) {
      if (mounted) _snack('⚠️ Download failed', Colors.redAccent);
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  // ── Bookmark ──────────────────────────────────────────────────────────────

  Future<void> _toggleBookmark() async {
    final userData = await ref.read(userDataAuthProvider.future);
    if (userData == null) return;
    final img = widget.images[_index];
    await ref
        .read(bookmarkControllerProvider)
        .toggleBookmark(
          imageUrl: img.imageUrl,
          groupId: widget.groupId,
          groupName: widget.groupName,
          userName: userData.name ?? 'Unknown',
          userProfilePic: userData.profilePic ?? '',
        );
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (widget.images.isEmpty) {
      return const Scaffold(backgroundColor: Colors.black);
    }

    final img = widget.images[_index];

    // Watch bookmark state reactively
    final isBookmarked = ref
        .watch(bookmarkControllerProvider)
        .isBookmarked(img.imageUrl);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Photo gallery ──────────────────────────────────────────────
          PhotoViewGallery.builder(
            pageController: _pageCtrl,
            itemCount: widget.images.length,
            onPageChanged: (i) => setState(() => _index = i),
            scrollPhysics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            backgroundDecoration: const BoxDecoration(color: Colors.black),
            builder: (context, i) => PhotoViewGalleryPageOptions(
              imageProvider: CachedNetworkImageProvider(
                widget.images[i].imageUrl,
              ),
              minScale: PhotoViewComputedScale.contained,
              maxScale: PhotoViewComputedScale.covered * 4,
              onTapUp: (_, __, ___) => setState(() => _overlayOn = !_overlayOn),
              heroAttributes: PhotoViewHeroAttributes(
                tag: 'gallery_${widget.images[i].imageId}',
              ),
            ),
            loadingBuilder: (context, event) =>
                const Center(child: CircularProgressIndicator()),
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
                        child: AppBar(
                          backgroundColor: Colors.transparent,
                          elevation: 0,
                          leading: IconButton(
                            icon: const Icon(
                              Icons.arrow_back_ios_new_rounded,
                              color: Colors.white,
                            ),
                            onPressed: () => Navigator.pop(context),
                          ),
                          title: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Gallery',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                widget.groupName,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                          actions: [
                            // ── Bookmark ───────────────────────────
                            StreamBuilder<bool>(
                              stream: isBookmarked,
                              builder: (context, snap) {
                                final bookmarked = snap.data ?? false;
                                return IconButton(
                                  icon: Icon(
                                    bookmarked
                                        ? Icons.bookmark
                                        : Icons.bookmark_outline,
                                    color: bookmarked
                                        ? Colors.amber
                                        : Colors.white,
                                  ),
                                  tooltip: bookmarked
                                      ? 'Remove bookmark'
                                      : 'Bookmark',
                                  onPressed: _toggleBookmark,
                                );
                              },
                            ),

                            // ── Download ───────────────────────────
                            IconButton(
                              icon: _isDownloading
                                  ? SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: widget.accentColor,
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
                                    images: widget.images,
                                    initialIndex: _index,
                                    accentColor: widget.accentColor,
                                    groupName: widget.groupName,
                                  ),
                                ),
                              ),
                            ),

                            // ── Delete ─────────────────────────────
                            IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Colors.redAccent,
                              ),
                              onPressed: () async {
                                final ok = await _confirmDelete();
                                if (ok == true) {
                                  await widget.onDelete(img.imageId);
                                  if (mounted) Navigator.pop(context);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Bottom counter
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
                          padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
                          child: Text(
                            '${_index + 1} / ${widget.images.length}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
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
        ],
      ),
    );
  }

  Future<bool?> _confirmDelete() {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          'Delete Photo?',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Upload Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _UploadSheet extends StatelessWidget {
  final List<File> files;
  final Color accentColor;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const _UploadSheet({
    required this.files,
    required this.accentColor,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[700],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Icon(Icons.photo_library_outlined, color: accentColor),
                  const SizedBox(width: 10),
                  Text(
                    'Upload ${files.length} image${files.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 90,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: files.length,
                itemBuilder: (context, index) {
                  return Container(
                    width: 80,
                    height: 80,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: accentColor.withOpacity(0.4),
                        width: 1.5,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: Image.file(files[index], fit: BoxFit.cover),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        onCancel();
                      },
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.grey[700]!),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        onConfirm();
                      },
                      icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                      label: Text(
                        'Upload ${files.length} Photo${files.length == 1 ? '' : 's'}',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty state
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyGallery extends StatelessWidget {
  final Color accentColor;
  final VoidCallback onUpload;
  const _EmptyGallery({required this.accentColor, required this.onUpload});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.photo_library_outlined,
            size: 52,
            color: accentColor.withOpacity(0.6),
          ),
          const SizedBox(height: 20),
          const Text(
            'No photos yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 28),
          ElevatedButton(
            onPressed: onUpload,
            style: ElevatedButton.styleFrom(backgroundColor: accentColor),
            child: const Text('Add Photos'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Gallery Grid
// ─────────────────────────────────────────────────────────────────────────────

class _GalleryGrid extends StatelessWidget {
  final List<GroupGalleryImage> images;
  final String groupId;
  final String groupName;
  final Color accentColor;
  final String currentUserId;
  final Future<void> Function(String imageId) onDelete;

  const _GalleryGrid({
    required this.images,
    required this.groupId,
    required this.groupName,
    required this.accentColor,
    required this.currentUserId,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) {
      return _EmptyGallery(accentColor: accentColor, onUpload: () {});
    }

    return GridView.builder(
      padding: const EdgeInsets.all(3),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 3,
        mainAxisSpacing: 3,
      ),
      itemCount: images.length,
      itemBuilder: (context, index) {
        final img = images[index];
        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => _FullscreenViewer(
                images: images,
                initialIndex: index,
                accentColor: accentColor,
                currentUserId: currentUserId,
                groupName: groupName,
                groupId: groupId,
                onDelete: onDelete,
              ),
            ),
          ),
          onLongPress: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SlideshowScreen(
                images: images,
                initialIndex: index,
                accentColor: accentColor,
                groupName: groupName,
              ),
            ),
          ),
          child: Hero(
            tag: 'gallery_${img.imageId}',
            child: CachedNetworkImage(
              imageUrl: img.imageUrl,
              fit: BoxFit.cover,
            ),
          ),
        );
      },
    );
  }
}
