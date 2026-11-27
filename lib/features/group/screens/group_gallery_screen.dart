import 'dart:developer';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gallery_saver_plus/gallery_saver.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:video_player/video_player.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/utils/google_lens_service.dart';
import 'package:worship_chat/common/utils/utils.dart';
import 'package:worship_chat/common/widgets/loader.dart';
import 'package:worship_chat/common/widgets/photo_text_remover_sheet.dart';
import 'package:worship_chat/common/widgets/set_as_profile_pic_sheet.dart';
import 'package:worship_chat/common/widgets/wallpaper_widget_sheet.dart';
import 'package:worship_chat/features/auth/controller/auth_controller.dart';
import 'package:worship_chat/features/bookmark/controller/bookmark_controller.dart';
import 'package:worship_chat/features/bookmark/widgets/save_to_collection_sheet.dart';
import 'package:worship_chat/features/group/controller/group_gallery_controller.dart';
import 'package:worship_chat/features/group/screens/duplicate_finder_screen.dart';
import 'package:worship_chat/features/group/screens/slide_show_screen.dart';
import 'package:worship_chat/features/group/services/duplicate_detection_service.dart';
import 'package:worship_chat/features/chat/widgets/forward_message_sheet.dart';
import 'package:worship_chat/features/group/services/gallery_media_service.dart';
import 'package:worship_chat/features/group/widgets/multi_gallery_shuffle_sheet.dart';
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
    with TickerProviderStateMixin {
  final ValueNotifier<bool> _isUploadingNotifier = ValueNotifier(false);
  final ValueNotifier<int> _uploadedCountNotifier = ValueNotifier(0);
  final ValueNotifier<int> _totalToUploadNotifier = ValueNotifier(0);

  List<GroupGalleryImage>? _shuffledImages;
  List<GroupGalleryImage> _currentGalleryImages = [];
  bool _isShuffled = false;

  late TabController _tabController;
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
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
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
    _tabController.dispose();
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
      final picked = await ImagePicker().pickMultiImage();
      if (picked.isEmpty) return;
      var files = picked.map((x) => File(x.path)).toList();

      // Pre-upload Smart Duplicate Check
      if (_currentGalleryImages.isNotEmpty) {
        final duplicateFiles = <File>[];
        for (final file in files) {
          final dup = await DuplicateDetectionService.findDuplicateForLocalFile(
            file: file,
            existingImages: _currentGalleryImages,
          );
          if (dup != null) {
            duplicateFiles.add(file);
          }
        }

        if (duplicateFiles.isNotEmpty && mounted) {
          final skipDuplicates = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF1B1827),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: _accent.withValues(alpha: 0.3)),
              ),
              title: const Row(
                children: [
                  Icon(Icons.copy_rounded, color: Colors.orangeAccent, size: 20),
                  SizedBox(width: 8),
                  Text('Duplicate Photos Detected', style: TextStyle(fontSize: 16)),
                ],
              ),
              content: Text(
                '${duplicateFiles.length} of the ${files.length} selected photos appear to already exist in this gallery.\n\nWould you like to skip uploading them?',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Upload All', style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Skip Duplicates'),
                ),
              ],
            ),
          );

          if (skipDuplicates == true) {
            files = files.where((f) => !duplicateFiles.contains(f)).toList();
            if (files.isEmpty) {
              _snack('All selected photos were duplicates and skipped.');
              return;
            }
          }
        }
      }

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

  Future<void> _pickVideos() async {
    try {
      final files = await GalleryMediaService().pickVideos();
      if (files.isEmpty) return;
      _showVideoUploadSheet(files);
    } catch (e) {
      log('video picker error: $e');
      _snack('Could not open video picker.');
    }
  }

  void _showVideoUploadSheet(List<File> files) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _UploadSheet(
        files: files,
        accentColor: _accent,
        isVideo: true,
        onConfirm: () => _startVideoUpload(files),
        onCancel: () {},
      ),
    );
  }

  Future<void> _startVideoUpload(List<File> files) async {
    if (files.isEmpty) return;
    final userData = await ref.read(userDataAuthProvider.future);
    if (userData == null) return;

    _isUploadingNotifier.value = true;
    _uploadedCountNotifier.value = 0;
    _totalToUploadNotifier.value = files.length;

    final count = await ref
        .read(groupGalleryControllerProvider)
        .uploadVideos(
          groupId: widget.groupId,
          videoFiles: files,
          uploaderName: userData.name ?? 'Unknown',
          caption: null,
          onProgress: (uploaded, total) {
            _uploadedCountNotifier.value = uploaded;
          },
        );

    if (mounted) {
      _isUploadingNotifier.value = false;
      _snack(count > 0 ? '✅ $count videos uploaded!' : '⚠️ Video upload failed.');
    }
  }

  bool _isDownloadingZip = false;

  void _startSlideshow(List<GroupGalleryImage> images) {
    final photos = images.where((m) => m.isImage).toList();
    final activeImages = _isShuffled && _shuffledImages != null
        ? _shuffledImages!.where((m) => m.isImage).toList()
        : photos;
    if (activeImages.isEmpty) {
      _snack('No photos available for slideshow');
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SlideshowScreen(
          images: activeImages,
          initialIndex: 0,
          accentColor: _accent,
          groupName: widget.groupName,
        ),
      ),
    );
  }

  void _showDownloadZipDialog(List<GroupGalleryImage> images) {
    if (images.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Download Gallery',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Download all ${images.length} photos from ${widget.groupName} as a ZIP archive?',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 8),
            const Text(
              'Includes original high-quality photos',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _downloadAllAsZip(images);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Download ZIP'),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadAllAsZip(List<GroupGalleryImage> images) async {
    if (_isDownloadingZip || images.isEmpty) return;
    setState(() => _isDownloadingZip = true);
    _snack('📦 Downloading ${images.length} photos as ZIP...');

    try {
      final result = await GalleryMediaService().downloadGalleryAsZip(
        groupName: widget.groupName,
        images: images,
      );

      if (!mounted) return;
      if (result.status == GalleryZipStatus.saved) {
        _snack('✅ ZIP saved to ${result.displayLocation ?? "Downloads"}!');
      } else if (result.status == GalleryZipStatus.cancelled) {
        _snack('ZIP download cancelled');
      } else {
        _snack('⚠️ ${result.errorMessage ?? "Failed to download ZIP"}');
      }
    } catch (e) {
      log('Error downloading ZIP: $e');
      if (mounted) _snack('⚠️ ZIP download error: $e');
    } finally {
      if (mounted) setState(() => _isDownloadingZip = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    AppSnackBar.show(context, message: msg);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    String currentUserId = '';
    try {
      currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    } catch (_) {}

    return StreamBuilder<List<GroupGalleryImage>>(
      stream: ref
          .watch(groupGalleryControllerProvider)
          .getGalleryStream(widget.groupId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return Scaffold(
            backgroundColor: backgroundColor,
            appBar: _buildAppBar([], [], []),
            body: const Loader(),
          );
        }

        final originalImages = snapshot.data ?? [];
        _currentGalleryImages = originalImages;
        final photos = originalImages.where((m) => m.isImage).toList();
        final videos = originalImages.where((m) => m.isVideo).toList();

        final displayPhotos = _isShuffled && _shuffledImages != null
            ? _shuffledImages!.where((m) => m.isImage).toList()
            : photos;
        final displayVideos = _isShuffled && _shuffledImages != null
            ? _shuffledImages!.where((m) => m.isVideo).toList()
            : videos;

        final isVideoTab = _tabController.index == 1;

        return Scaffold(
          backgroundColor: backgroundColor,
          appBar: _buildAppBar(originalImages, photos, videos),
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
                          onPressed: isUploading
                              ? null
                              : (isVideoTab ? _pickVideos : _pickImages),
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
                              : Icon(isVideoTab
                                  ? Icons.videocam_rounded
                                  : Icons.add_photo_alternate_outlined),
                          label: Text(
                            isUploading
                                ? '$uploaded / $total'
                                : (isVideoTab ? 'Add Videos' : 'Add Photos'),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              _GalleryGrid(
                images: displayPhotos,
                isVideo: false,
                groupId: widget.groupId,
                groupName: widget.groupName,
                accentColor: _accent,
                currentUserId: currentUserId,
                onUpload: _pickImages,
                onDelete: (id) => ref
                    .read(groupGalleryControllerProvider)
                    .deleteImage(widget.groupId, id),
              ),
              _GalleryGrid(
                images: displayVideos,
                isVideo: true,
                groupId: widget.groupId,
                groupName: widget.groupName,
                accentColor: _accent,
                currentUserId: currentUserId,
                onUpload: _pickVideos,
                onDelete: (id) => ref
                    .read(groupGalleryControllerProvider)
                    .deleteImage(widget.groupId, id),
              ),
            ],
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(
    List<GroupGalleryImage> images,
    List<GroupGalleryImage> photos,
    List<GroupGalleryImage> videos,
  ) {
    final hasMedia = images.isNotEmpty;
    return AppBar(
      backgroundColor: appBarColor,
      elevation: 0,
      titleSpacing: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
        onPressed: () => Navigator.pop(context),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  'Gallery',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _accent,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
              if (images.isNotEmpty) ...[
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
                    '${images.length}',
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
            widget.groupName,
            style: TextStyle(color: Colors.grey[400], fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      actions: [
        // ── Upload progress ────────────────────────────────
        ValueListenableBuilder<bool>(
          valueListenable: _isUploadingNotifier,
          builder: (context, isUploading, _) {
            if (!isUploading) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Center(
                child: ValueListenableBuilder<int>(
                  valueListenable: _uploadedCountNotifier,
                  builder: (context, uploaded, _) {
                    return ValueListenableBuilder<int>(
                      valueListenable: _totalToUploadNotifier,
                      builder: (context, total, _) {
                        return SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            value: total > 0 ? uploaded / total : null,
                            color: _accent,
                            strokeWidth: 2,
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
      bottom: PreferredSize(
        preferredSize: Size.fromHeight(hasMedia ? 94.0 : 46.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasMedia) _buildActionBar(images),
            TabBar(
              controller: _tabController,
              indicatorColor: _accent,
              indicatorWeight: 3,
              labelColor: _accent,
              unselectedLabelColor: Colors.grey[400],
              dividerColor: Colors.transparent,
              tabs: [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Photos'),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: _tabController.index == 0
                              ? _accent.withValues(alpha: 0.2)
                              : Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${photos.length}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Videos'),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: _tabController.index == 1
                              ? _accent.withValues(alpha: 0.2)
                              : Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${videos.length}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionBar(List<GroupGalleryImage> images) {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // ── Shuffle ─────────────────────────
          _buildActionIconButton(
            icon: Icon(
              Icons.shuffle_rounded,
              color: _isShuffled ? _accent : Colors.white70,
              size: 19,
            ),
            tooltip: _isShuffled
                ? 'Shuffle again (multi-shuffle)'
                : 'Shuffle',
            isActive: _isShuffled,
            onPressed: () {
              HapticFeedback.lightImpact();
              _shuffleImages(images);
            },
          ),

          if (_isShuffled) ...[
            const SizedBox(width: 14),
            _buildActionIconButton(
              icon: const Icon(
                Icons.format_list_numbered_rounded,
                color: Colors.white70,
                size: 19,
              ),
              tooltip: 'Restore order',
              onPressed: _restoreOrder,
            ),
          ],

          const SizedBox(width: 14),

          // ── Multi-Gallery Shuffle ─────────────────────
          _buildActionIconButton(
            icon: const Icon(
              Icons.auto_awesome_motion_rounded,
              color: Colors.white70,
              size: 19,
            ),
            tooltip: 'Multi-Gallery Shuffle',
            onPressed: () => MultiGalleryShuffleSheet.show(
              context,
              initialGroupId: widget.groupId,
              accentColor: _accent,
            ),
          ),

          const SizedBox(width: 14),

          // ── Slideshow ─────────────────────────────────
          _buildActionIconButton(
            icon: const Icon(
              Icons.slideshow_rounded,
              color: Colors.white70,
              size: 20,
            ),
            tooltip: 'Slideshow',
            onPressed: () => _startSlideshow(images),
          ),

          const SizedBox(width: 14),

          // ── Download all as ZIP ─────────────────────────
          _buildActionIconButton(
            icon: _isDownloadingZip
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      color: _accent,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(
                    Icons.download_rounded,
                    color: Colors.white70,
                    size: 19,
                  ),
            tooltip: 'Download all as ZIP',
            onPressed: _isDownloadingZip
                ? null
                : () => _showDownloadZipDialog(images),
          ),

          const SizedBox(width: 14),

          // ── Smart Duplicate Finder ────────────────────────
          _buildActionIconButton(
            icon: const Icon(
              Icons.copy_rounded,
              color: Colors.white70,
              size: 19,
            ),
            tooltip: 'Smart Duplicate Finder',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DuplicateFinderScreen(
                    initialImages: images,
                    groupId: widget.groupId,
                    groupName: widget.groupName,
                    accentColor: _accent,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildActionIconButton({
    required Widget icon,
    required String tooltip,
    required VoidCallback? onPressed,
    bool isActive = false,
  }) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: isActive
            ? _accent.withValues(alpha: 0.22)
            : Colors.white.withValues(alpha: 0.06),
        shape: BoxShape.circle,
        border: Border.all(
          color: isActive
              ? _accent.withValues(alpha: 0.6)
              : Colors.white.withValues(alpha: 0.12),
          width: 1,
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: _accent.withValues(alpha: 0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 1),
                ),
              ]
            : null,
      ),
      child: IconButton(
        icon: icon,
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
        onPressed: onPressed,
      ),
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
      final originalUrl = getOriginalHighQualityImageUrl(img.imageUrl);
      final ext = getImageExtensionFromUrl(originalUrl);
      final dir = await getTemporaryDirectory();
      final filePath =
          '${dir.path}/${img.imageId}_${DateTime.now().millisecondsSinceEpoch}.$ext';

      final dio = Dio();
      await dio.download(
        originalUrl,
        filePath,
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
        ),
      );
      final saved = await GallerySaver.saveImage(
        filePath,
        albumName: 'Worship Chat', // ← custom album, not DCIM
        toDcim: false,
      );
      final tempFile = File(filePath);
      if (await tempFile.exists()) {
        await tempFile.delete();
      }

      if (mounted) {
        _snack(
          saved == true
              ? '✅ Saved in high quality to Worship Chat album'
              : '⚠️ Could not save',
          saved == true ? Colors.green[700]! : Colors.redAccent,
        );
      }
    } catch (e) {
      log('Download error: $e');
      if (mounted) _snack('⚠️ Download failed: $e', Colors.redAccent);
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  // ── Bookmark & Collection ──────────────────────────────────────────────────

  Future<void> _openSaveToCollection({String? bookmarkId}) async {
    final userData = await ref.read(userDataAuthProvider.future);
    if (!mounted) return;
    final uid = userData?.uid ?? widget.currentUserId;
    if (uid.isEmpty) return;
    final img = widget.images[_index];

    String? bId = bookmarkId;
    bId ??= await ref.read(bookmarkControllerProvider).ensureBookmarked(
          imageUrl: img.imageUrl,
          groupId: widget.groupId,
          groupName: widget.groupName,
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

  Future<void> _handleBookmarkPress(bool isCurrentlyBookmarked) async {
    if (isCurrentlyBookmarked) {
      _showBookmarkActionSheet();
    } else {
      await _toggleBookmark();
    }
  }

  Future<void> _toggleBookmark() async {
    final userData = await ref.read(userDataAuthProvider.future);
    if (userData == null) return;
    final img = widget.images[_index];
    final result = await ref
        .read(bookmarkControllerProvider)
        .toggleBookmarkWithResult(
          imageUrl: img.imageUrl,
          groupId: widget.groupId,
          groupName: widget.groupName,
          userName: userData.name ?? 'Unknown',
          userProfilePic: userData.profilePic ?? '',
        );

    if (!mounted) return;

    if (result.isBookmarked && result.bookmarkId != null) {
      // Auto-open SaveToCollectionSheet to give the user immediate choice of collection
      _openSaveToCollection(bookmarkId: result.bookmarkId);
      AppSnackBar.show(
        context,
        message: 'Saved to bookmarks',
        type: SnackBarType.success,
        actionLabel: 'Collections',
        onAction: () => _openSaveToCollection(bookmarkId: result.bookmarkId),
      );
    } else {
      AppSnackBar.show(
        context,
        message: 'Bookmark removed',
        type: SnackBarType.info,
      );
    }
  }

  void _showBookmarkActionSheet() {
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
              leading:
                  const Icon(Icons.folder_special_rounded, color: tabColor),
              title: const Text('Save to Collection',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
              subtitle: const Text('Choose or change collection folder',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              onTap: () {
                Navigator.pop(ctx);
                _openSaveToCollection();
              },
            ),
            ListTile(
              leading: const Icon(Icons.bookmark_remove_rounded,
                  color: Colors.redAccent),
              title: const Text('Remove Bookmark',
                  style: TextStyle(color: Colors.redAccent)),
              subtitle: const Text('Delete from all bookmarks and collections',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              onTap: () {
                Navigator.pop(ctx);
                _toggleBookmark();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _snack(String msg, [Color? color]) {
    if (!mounted) return;
    AppSnackBar.show(context, message: msg);
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
                getOriginalHighQualityImageUrl(widget.images[i].imageUrl),
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
                                          '${_index + 1} of ${widget.images.length}',
                                          style: const TextStyle(
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
                                  horizontal: 8, vertical: 2),
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
                                  // ── Bookmark & Collection ─────────────
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
                                          tooltip: bookmarked
                                              ? 'Bookmark options / Collections'
                                              : 'Bookmark & Save to collection',
                                          onPressed: () =>
                                              _handleBookmarkPress(bookmarked),
                                        ),
                                      );
                                    },
                                  ),

                                  // ── Download ───────────────────────────
                                  IconButton(
                                    icon: _isDownloading
                                        ? SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: widget.accentColor,
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

                                  // ── Forward ────────────────────────────
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
                                          messageType: 'image',
                                          fileMessageData: img.imageUrl,
                                          caption: img.caption,
                                          isFromGallery: true,
                                          sourceGroupId: widget.groupId,
                                          sourceGroupName: widget.groupName,
                                        ),
                                      );
                                    },
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

                                  // ── Google Lens ────────────────────────
                                  if (!img.isVideo)
                                    IconButton(
                                      icon: const GoogleLensIcon(),
                                      tooltip: 'Search with Google Lens',
                                      onPressed: () => GoogleLensService.search(
                                        context: context,
                                        imageUrl: img.imageUrl,
                                      ),
                                    ),

                                  // ── Remove Text ────────────────────────
                                  if (!img.isVideo)
                                    IconButton(
                                      icon: const Icon(
                                        Icons.text_fields_rounded,
                                        color: Color(0xFF00E5FF),
                                      ),
                                      tooltip: 'Remove Text',
                                      onPressed: () =>
                                          PhotoTextRemoverSheet.open(
                                        context,
                                        origin:
                                            PhotoTextRemoverOrigin.groupGallery,
                                        imageUrl: img.imageUrl,
                                        groupId: widget.groupId,
                                        groupName: widget.groupName,
                                        sourceImageId: img.imageId,
                                        title: (img.caption?.trim().isNotEmpty ??
                                                false)
                                            ? img.caption!.trim()
                                            : widget.groupName,
                                      ),
                                    ),

                                  // ── Wallpaper & Home Widget ─────────────
                                  if (!img.isVideo)
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
                                        title: (img.caption?.trim().isNotEmpty ??
                                                false)
                                            ? img.caption!.trim()
                                            : widget.groupName,
                                        subtitle: 'Queendom Gallery',
                                      ),
                                    ),

                                  // ── Set as Profile Pic ─────────────────
                                  if (!img.isVideo)
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
                                        sourceGroupId: widget.groupId,
                                        sourceGroupName: widget.groupName,
                                        title: (img.caption?.trim().isNotEmpty ??
                                                false)
                                            ? img.caption!.trim()
                                            : widget.groupName,
                                      ),
                                    ),

                                  // ── Delete ─────────────────────────────
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.redAccent,
                                    ),
                                    tooltip: 'Delete photo',
                                    onPressed: () async {
                                      final ok = await _confirmDelete();
                                      if (ok == true) {
                                        await widget.onDelete(img.imageId);
                                        if (context.mounted) Navigator.pop(context);
                                      }
                                    },
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

                  // ── Bottom Counter ───────────────────────────────────────
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
                              fontSize: 14,
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
  final bool isVideo;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const _UploadSheet({
    required this.files,
    required this.accentColor,
    this.isVideo = false,
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
                  Icon(
                    isVideo
                        ? Icons.videocam_rounded
                        : Icons.photo_library_outlined,
                    color: accentColor,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    isVideo
                        ? 'Upload ${files.length} video${files.length == 1 ? '' : 's'}'
                        : 'Upload ${files.length} photo${files.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: accentColor.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isVideo ? Icons.videocam_rounded : Icons.hd_outlined,
                          size: 14,
                          color: accentColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isVideo ? 'Video HD' : 'Original HD',
                          style: TextStyle(
                            color: accentColor,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
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
                        color: accentColor.withValues(alpha: 0.4),
                        width: 1.5,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: isVideo
                          ? Container(
                              color: Colors.black54,
                              child: const Center(
                                child: Icon(
                                  Icons.videocam_rounded,
                                  color: Colors.white70,
                                  size: 32,
                                ),
                              ),
                            )
                          : Image.file(files[index], fit: BoxFit.cover),
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
                        isVideo
                            ? 'Upload ${files.length} Video${files.length == 1 ? '' : 's'}'
                            : 'Upload ${files.length} Photo${files.length == 1 ? '' : 's'}',
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
  final bool isVideo;
  final VoidCallback onUpload;

  const _EmptyGallery({
    required this.accentColor,
    this.isVideo = false,
    required this.onUpload,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isVideo
                ? Icons.videocam_outlined
                : Icons.photo_library_outlined,
            size: 52,
            color: accentColor.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 20),
          Text(
            isVideo ? 'No videos yet' : 'No photos yet',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 28),
          ElevatedButton(
            onPressed: onUpload,
            style: ElevatedButton.styleFrom(backgroundColor: accentColor),
            child: Text(isVideo ? 'Add Videos' : 'Add Photos'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Gallery Grid
// ─────────────────────────────────────────────────────────────────────────────

class _GalleryGrid extends ConsumerWidget {
  final List<GroupGalleryImage> images;
  final bool isVideo;
  final String groupId;
  final String groupName;
  final Color accentColor;
  final String currentUserId;
  final VoidCallback onUpload;
  final Future<void> Function(String imageId) onDelete;

  const _GalleryGrid({
    required this.images,
    this.isVideo = false,
    required this.groupId,
    required this.groupName,
    required this.accentColor,
    required this.currentUserId,
    required this.onUpload,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (images.isEmpty) {
      return _EmptyGallery(
        accentColor: accentColor,
        isVideo: isVideo,
        onUpload: onUpload,
      );
    }

    return CustomScrollView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.paddingOf(context).bottom + 80,
          ),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 0,
              mainAxisSpacing: 0,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final img = images[index];
                return GestureDetector(
                  onTap: () {
                    if (img.isVideo) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => _FullscreenVideoViewer(
                            video: img,
                            accentColor: accentColor,
                            currentUserId: currentUserId,
                            groupName: groupName,
                            groupId: groupId,
                            onDelete: onDelete,
                          ),
                        ),
                      );
                    } else {
                      Navigator.push(
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
                      );
                    }
                  },
                  onLongPress: () {
                    showModalBottomSheet(
                      context: context,
                      backgroundColor: const Color(0xFF1B1728),
                      isScrollControlled: true,
                      shape: const RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.vertical(top: Radius.circular(20)),
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
                            ListTile(
                              leading: const Icon(Icons.forward_rounded,
                                  color: tabColor),
                              title: const Text('Forward Photo',
                                  style: TextStyle(color: Colors.white)),
                              subtitle: const Text(
                                  'Send to chat or another gallery',
                                  style: TextStyle(
                                      color: Colors.white54, fontSize: 12)),
                              onTap: () {
                                Navigator.pop(ctx);
                                ForwardMessageSheet.show(
                                  context,
                                  ForwardMessagePayload(
                                    text: img.caption ?? '',
                                    messageType:
                                        img.isVideo ? 'video' : 'image',
                                    fileMessageData: img.imageUrl,
                                    caption: img.caption,
                                    isFromGallery: true,
                                    sourceGroupId: groupId,
                                    sourceGroupName: groupName,
                                  ),
                                );
                              },
                            ),
                            if (!img.isVideo)
                              ListTile(
                                leading: const Icon(Icons.bookmark_add_rounded,
                                    color: Colors.amber),
                                title: const Text('Save to Collection',
                                    style: TextStyle(color: Colors.white)),
                                subtitle: const Text(
                                    'Bookmark and organize into collections',
                                    style: TextStyle(
                                        color: Colors.white54, fontSize: 12)),
                                onTap: () async {
                                  Navigator.pop(ctx);
                                  final userData = await ref
                                      .read(userDataAuthProvider.future);
                                  final bId = await ref
                                      .read(bookmarkControllerProvider)
                                      .ensureBookmarked(
                                        imageUrl: img.imageUrl,
                                        groupId: groupId,
                                        groupName: groupName,
                                        userName: userData?.name ?? 'Unknown',
                                        userProfilePic:
                                            userData?.profilePic ?? '',
                                      );
                                  if (bId != null && context.mounted) {
                                    SaveToCollectionSheet.show(
                                      context: context,
                                      bookmarkId: bId,
                                      imageUrl: img.imageUrl,
                                      userId: currentUserId,
                                    );
                                  }
                                },
                              ),
                            if (!img.isVideo)
                              ListTile(
                                leading: Icon(Icons.slideshow_rounded,
                                    color: accentColor),
                                title: const Text('Start Slideshow',
                                    style: TextStyle(color: Colors.white)),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => SlideshowScreen(
                                        images: images,
                                        initialIndex: index,
                                        accentColor: accentColor,
                                        groupName: groupName,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            if (!img.isVideo)
                              ListTile(
                                leading: const GoogleLensIcon(size: 22),
                                title: const Text('Search with Google Lens',
                                    style: TextStyle(color: Colors.white)),
                                subtitle: const Text(
                                    'Find visual matches with Google Lens',
                                    style: TextStyle(
                                        color: Colors.white54, fontSize: 12)),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  GoogleLensService.search(
                                    context: context,
                                    imageUrl: img.imageUrl,
                                  );
                                },
                              ),
                            if (!img.isVideo)
                              ListTile(
                                leading: const Icon(
                                  Icons.text_fields_rounded,
                                  color: Color(0xFF00E5FF),
                                ),
                                title: const Text('Remove Text',
                                    style: TextStyle(color: Colors.white)),
                                subtitle: const Text(
                                    'Erase captions, watermarks & overlaid text',
                                    style: TextStyle(
                                        color: Colors.white54, fontSize: 12)),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  PhotoTextRemoverSheet.open(
                                    context,
                                    origin:
                                        PhotoTextRemoverOrigin.groupGallery,
                                    imageUrl: img.imageUrl,
                                    groupId: groupId,
                                    groupName: groupName,
                                    sourceImageId: img.imageId,
                                    title:
                                        (img.caption?.trim().isNotEmpty ?? false)
                                            ? img.caption!.trim()
                                            : groupName,
                                  );
                                },
                              ),
                            if (!img.isVideo)
                              ListTile(
                                leading: const Icon(
                                  Icons.wallpaper_rounded,
                                  color: Color(0xFFFFD700),
                                ),
                                title: const Text('Wallpaper & Home Widget',
                                    style: TextStyle(color: Colors.white)),
                                subtitle: const Text(
                                    'Set phone wallpaper or pin to widget',
                                    style: TextStyle(
                                        color: Colors.white54, fontSize: 12)),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  WallpaperAndWidgetSheet.show(
                                    context,
                                    photoId: 'gal_${img.imageId}',
                                    imageUrl: img.imageUrl,
                                    title:
                                        (img.caption?.trim().isNotEmpty ?? false)
                                            ? img.caption!.trim()
                                            : groupName,
                                    subtitle: 'Queendom Gallery',
                                  );
                                },
                              ),
                            if (!img.isVideo)
                              ListTile(
                                leading: const Icon(
                                  Icons.account_circle_outlined,
                                  color: tabColor,
                                ),
                                title: const Text('Set as Profile Pic',
                                    style: TextStyle(color: Colors.white)),
                                subtitle: const Text(
                                    'Use for your profile or any group',
                                    style: TextStyle(
                                        color: Colors.white54, fontSize: 12)),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  SetAsProfilePicSheet.show(
                                    context,
                                    imageUrl: img.imageUrl,
                                    sourceGroupId: groupId,
                                    sourceGroupName: groupName,
                                    title:
                                        (img.caption?.trim().isNotEmpty ?? false)
                                            ? img.caption!.trim()
                                            : groupName,
                                  );
                                },
                              ),
                          ],
                          ),
                        ),
                      ),
                    );
                  },
                  child: Hero(
                    tag: 'gallery_${img.imageId}',
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CachedNetworkImage(
                          imageUrl: img.imageUrl,
                          fit: BoxFit.cover,
                          errorWidget: (context, url, error) => Container(
                            color: Colors.grey[900],
                            child: Center(
                              child: Icon(
                                img.isVideo
                                    ? Icons.videocam_rounded
                                    : Icons.broken_image_rounded,
                                color: Colors.white24,
                              ),
                            ),
                          ),
                        ),
                        if (img.isVideo) ...[
                          Positioned(
                            top: 6,
                            left: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.75),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.videocam_rounded,
                                      size: 12, color: Colors.white),
                                  SizedBox(width: 4),
                                  Text(
                                    'VIDEO',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Center(
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.5),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 26,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
              childCount: images.length,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24.0),
            child: Center(
              child: Text(
                isVideo
                    ? '${images.length} ${images.length == 1 ? 'Video' : 'Videos'}'
                    : '${images.length} ${images.length == 1 ? 'Photo' : 'Photos'}',
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
        const SliverToBoxAdapter(
          child: SizedBox(height: 70),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Fullscreen Video Viewer
// ─────────────────────────────────────────────────────────────────────────────

class _FullscreenVideoViewer extends StatefulWidget {
  final GroupGalleryImage video;
  final Color accentColor;
  final String currentUserId;
  final String groupName;
  final String groupId;
  final Future<void> Function(String imageId) onDelete;

  const _FullscreenVideoViewer({
    required this.video,
    required this.accentColor,
    required this.currentUserId,
    required this.groupName,
    required this.groupId,
    required this.onDelete,
  });

  @override
  State<_FullscreenVideoViewer> createState() => _FullscreenVideoViewerState();
}

class _FullscreenVideoViewerState extends State<_FullscreenVideoViewer> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _overlayOn = true;
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    _controller =
        VideoPlayerController.networkUrl(Uri.parse(widget.video.imageUrl))
          ..initialize().then((_) {
            if (mounted) {
              setState(() {
                _isInitialized = true;
                _controller.play();
                _isPlaying = true;
              });
            }
          }).catchError((e) {
            log('Error initializing video: $e');
          });

    _controller.addListener(() {
      if (mounted) {
        final isPlaying = _controller.value.isPlaying;
        if (isPlaying != _isPlaying) {
          setState(() => _isPlaying = isPlaying);
        }
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _togglePlay() {
    if (!_isInitialized) return;
    setState(() {
      if (_controller.value.isPlaying) {
        _controller.pause();
        _isPlaying = false;
      } else {
        _controller.play();
        _isPlaying = true;
      }
    });
  }

  Future<void> _downloadVideo() async {
    if (_isDownloading) return;
    setState(() => _isDownloading = true);
    AppSnackBar.show(context, message: '📥 Downloading video...');
    try {
      final dir = await getTemporaryDirectory();
      final ext = widget.video.imageUrl.split('?').first.split('.').last;
      final fileExt = ext.isNotEmpty && ext.length <= 4 ? ext : 'mp4';
      final path =
          '${dir.path}/gallery_video_${widget.video.imageId}.$fileExt';
      await Dio().download(widget.video.imageUrl, path);
      final saved = await GallerySaver.saveVideo(path);
      if (mounted) {
        AppSnackBar.show(
          context,
          message: saved == true
              ? '✅ Video saved to gallery!'
              : '⚠️ Failed to save video.',
        );
      }
    } catch (e) {
      log('Video download error: $e');
      if (mounted) {
        AppSnackBar.show(context, message: '⚠️ Could not download video.');
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  Future<bool?> _confirmDelete() {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          'Delete Video?',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _overlayOn = !_overlayOn),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Center(
              child: _isInitialized
                  ? AspectRatio(
                      aspectRatio: _controller.value.aspectRatio,
                      child: VideoPlayer(_controller),
                    )
                  : const CircularProgressIndicator(color: Colors.white),
            ),
            if (_isInitialized)
              GestureDetector(
                onTap: _togglePlay,
                child: AnimatedOpacity(
                  opacity: _overlayOn || !_isPlaying ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 48,
                    ),
                  ),
                ),
              ),

            // Top overlay bar
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AnimatedOpacity(
                opacity: _overlayOn ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
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
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.arrow_back_ios_new_rounded,
                                    color: Colors.white, size: 20),
                                onPressed: () => Navigator.pop(context),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      widget.video.uploadedByName,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      widget.groupName,
                                      style: const TextStyle(
                                          color: Colors.white60, fontSize: 11),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 2),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                IconButton(
                                  icon: _isDownloading
                                      ? SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: widget.accentColor),
                                        )
                                      : const Icon(Icons.download_rounded,
                                          color: Colors.white),
                                  tooltip: 'Download video',
                                  onPressed:
                                      _isDownloading ? null : _downloadVideo,
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      color: Colors.redAccent),
                                  tooltip: 'Delete video',
                                  onPressed: () async {
                                    final ok = await _confirmDelete();
                                    if (ok == true) {
                                      await widget.onDelete(widget.video.imageId);
                                      if (context.mounted) {
                                        Navigator.pop(context);
                                      }
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
