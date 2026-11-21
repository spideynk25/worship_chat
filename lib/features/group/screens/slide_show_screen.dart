import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';
import 'package:worship_chat/common/utils/google_lens_service.dart';
import 'package:worship_chat/common/utils/utils.dart';
import 'package:worship_chat/features/group/services/gallery_media_service.dart';
import 'package:worship_chat/features/group/utils/multi_gallery_shuffler_helper.dart';
import 'package:worship_chat/models/group_gallery_image.dart';

enum TwoPhotosLayout {
  stacked,
  sideBySide,
}

class SlideshowScreen extends StatefulWidget {
  final List<GroupGalleryImage> images;
  final int initialIndex;
  final Color accentColor;
  final String groupName;
  final MultiGalleryMode mode;
  final List<MultiGallerySlideSet>? slideSets;
  final Map<String, String>? groupNamesMap;

  const SlideshowScreen({
    super.key,
    required this.images,
    required this.initialIndex,
    required this.accentColor,
    required this.groupName,
    this.mode = MultiGalleryMode.alternate,
    this.slideSets,
    this.groupNamesMap,
  });

  @override
  State<SlideshowScreen> createState() => _SlideshowScreenState();
}

class _SlideshowScreenState extends State<SlideshowScreen>
    with SingleTickerProviderStateMixin {
  late PageController _pageCtrl;
  late List<GroupGalleryImage> _playlist; // shuffled or original order
  late List<MultiGallerySlideSet> _slideSets;
  late MultiGalleryMode _mode;
  late int _currentIndex;

  GroupGalleryImage? _maximizedPhoto;
  bool _wasPlayingBeforeMaximize = false;

  bool _isPlaying = true;
  bool _isDownloading = false;
  int _intervalSeconds = 10;
  TwoPhotosLayout _twoPhotosLayout = TwoPhotosLayout.stacked;

  late AnimationController _progressCtrl;
  late Animation<double> _progressAnim;

  bool _overlayOn = true;
  Timer? _overlayHideTimer;

  int get _totalCount {
    if (_mode == MultiGalleryMode.sameSlide && _slideSets.isNotEmpty) {
      return _slideSets.length;
    }
    return _playlist.length;
  }

  @override
  void initState() {
    super.initState();
    _mode = widget.mode;
    _playlist = List.of(widget.images);
    _slideSets = widget.slideSets != null
        ? List<MultiGallerySlideSet>.of(widget.slideSets!)
        : const [];

    final total = _totalCount;
    _currentIndex = total > 0 ? widget.initialIndex.clamp(0, total - 1) : 0;
    _pageCtrl = PageController(initialPage: _currentIndex);

    _progressCtrl =
        AnimationController(
          vsync: this,
          duration: Duration(seconds: _intervalSeconds),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed && _isPlaying) {
            _advance();
          }
        });

    _progressAnim = Tween(begin: 0.0, end: 1.0).animate(_progressCtrl);
    _startSlideshow();
    _scheduleOverlayHide();
  }

  @override
  void dispose() {
    _overlayHideTimer?.cancel();
    _progressCtrl.dispose();
    _pageCtrl.dispose();
    super.dispose();
  }

  // ── Playback ──────────────────────────────────────────────────────────────

  void _startSlideshow() {
    _progressCtrl.duration = Duration(seconds: _intervalSeconds);
    _progressCtrl.forward(from: 0.0);
  }

  void _advance() {
    final total = _totalCount;
    if (total == 0) return;
    final next = (_currentIndex + 1) % total;
    _pageCtrl.animateToPage(
      next,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOut,
    );
    if (_isPlaying) _startSlideshow();
  }

  void _previous() {
    final total = _totalCount;
    if (total == 0) return;
    final prev = (_currentIndex - 1 + total) % total;
    _pageCtrl.animateToPage(
      prev,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
    if (_isPlaying) _startSlideshow();
  }

  void _togglePlay() {
    setState(() => _isPlaying = !_isPlaying);
    if (_isPlaying) {
      _startSlideshow();
    } else {
      _progressCtrl.stop();
    }
    _showOverlay();
  }

  void _setSpeed(int seconds) {
    setState(() => _intervalSeconds = seconds);
    if (_isPlaying) _startSlideshow();
  }

  void _toggleMode() {
    if (widget.slideSets == null || widget.slideSets!.isEmpty) return;
    setState(() {
      _mode = _mode == MultiGalleryMode.alternate
          ? MultiGalleryMode.sameSlide
          : MultiGalleryMode.alternate;
      _currentIndex = 0;
    });
    _pageCtrl.jumpToPage(0);
    if (_isPlaying) _startSlideshow();
    _snack(
      _mode == MultiGalleryMode.sameSlide
          ? '👥 Switched to Same Slide Mode (All galleries synced)'
          : '🔀 Switched to Alternate Images Mode',
    );
  }

  // ── Maximize & Minimize (Pause & Auto-Resume) ─────────────────────────────

  void _maximizePhoto(GroupGalleryImage photo) {
    _wasPlayingBeforeMaximize = _isPlaying;
    if (_isPlaying) {
      _progressCtrl.stop();
      setState(() {
        _isPlaying = false;
        _maximizedPhoto = photo;
      });
    } else {
      setState(() {
        _maximizedPhoto = photo;
      });
    }
  }

  void _minimizePhoto() {
    setState(() {
      _maximizedPhoto = null;
    });
    _showOverlay();
    // Automatically resume slideshow if it was playing before maximize!
    if (_wasPlayingBeforeMaximize) {
      setState(() => _isPlaying = true);
      _startSlideshow();
    }
  }



  // ── Download ──────────────────────────────────────────────────────────────

  Future<void> _downloadCurrent() async {
    if (_isDownloading) return;
    setState(() => _isDownloading = true);

    try {
      final List<GroupGalleryImage> photosToSave;
      if (_mode == MultiGalleryMode.sameSlide && _slideSets.isNotEmpty) {
        photosToSave = _slideSets[_currentIndex].photos;
      } else if (_playlist.isNotEmpty) {
        photosToSave = [_playlist[_currentIndex]];
      } else {
        photosToSave = const [];
      }

      if (photosToSave.isEmpty) return;

      final media = GalleryMediaService();
      int savedCount = 0;
      for (final img in photosToSave) {
        final isNetwork = img.imageUrl.startsWith('http://') ||
            img.imageUrl.startsWith('https://');
        if (!isNetwork) {
          continue;
        }
        final result = await media.saveImage(
          imageUrl: img.imageUrl,
          imageId: img.imageId,
        );
        if (result == GallerySaveResult.saved) {
          savedCount++;
        }
      }

      if (mounted) {
        if (savedCount > 0) {
          _snack(
            savedCount == 1
                ? (media.isDesktop
                    ? '✅ Saved photo in high quality'
                    : '✅ Saved in high quality to Worship Chat album')
                : '✅ Saved $savedCount slide photos in high quality',
          );
        } else {
          _snack('Photo is already stored on your device.');
        }
      }
    } catch (e) {
      if (mounted) _snack('⚠️ Download failed', Colors.redAccent);
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  void _snack(String msg, [Color? color]) {
    AppSnackBar.show(context, message: msg);
  }

  // ── Overlay ───────────────────────────────────────────────────────────────

  void _showOverlay() {
    setState(() => _overlayOn = true);
    _overlayHideTimer?.cancel();
    _scheduleOverlayHide();
  }

  void _scheduleOverlayHide() {
    _overlayHideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _isPlaying) setState(() => _overlayOn = false);
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _maximizedPhoto == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_maximizedPhoto != null) {
          _minimizePhoto();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: _maximizedPhoto != null
            ? _buildMaximizedView(_maximizedPhoto!)
            : GestureDetector(
                onTap: _showOverlay,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Photo pager
                    PageView.builder(
                      controller: _pageCtrl,
                      itemCount: _totalCount,
                      onPageChanged: (i) {
                        setState(() => _currentIndex = i);
                        if (_isPlaying) _startSlideshow();
                      },
                      itemBuilder: (ctx, i) {
                        if (_mode == MultiGalleryMode.sameSlide && _slideSets.isNotEmpty) {
                          return SafeArea(
                            top: true,
                            bottom: false,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(10, 88, 10, 84),
                              child: _buildSameSlideContent(_slideSets[i]),
                            ),
                          );
                        }

                        if (_playlist.isEmpty) {
                          return const Center(
                            child: Text('No photos', style: TextStyle(color: Colors.white54)),
                          );
                        }

                        final imgUrl = _playlist[i].imageUrl;
                        final bool isNetwork = imgUrl.startsWith('http://') ||
                            imgUrl.startsWith('https://');
                        final ImageProvider provider = isNetwork
                            ? CachedNetworkImageProvider(
                                getOriginalHighQualityImageUrl(imgUrl),
                              )
                            : FileImage(File(imgUrl)) as ImageProvider;

                        return PhotoView(
                          imageProvider: provider,
                          backgroundDecoration:
                              const BoxDecoration(color: Colors.black),
                          minScale: PhotoViewComputedScale.contained,
                          maxScale: PhotoViewComputedScale.covered * 2,
                        );
                      },
                    ),

                    // Overlay
                    IgnorePointer(
                      ignoring: !_overlayOn,
                      child: AnimatedOpacity(
                        opacity: _overlayOn ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 300),
                        child: Stack(
                          children: [_buildTopBar(), _buildBottomControls()],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  /// Builds a synchronized slide displaying full uncropped photos from every selected gallery.
  Widget _buildSameSlideContent(MultiGallerySlideSet slide) {
    final photos = slide.photos;
    if (photos.isEmpty) {
      return const Center(
        child: Text('Empty slide', style: TextStyle(color: Colors.white54)),
      );
    }

    if (photos.length == 1) {
      return _buildSlidePhotoTile(photos[0]);
    }

    // 2 galleries: Toggleable between Stacked (Top & Bottom, default) and Side-by-Side (Columns)
    if (photos.length == 2) {
      if (_twoPhotosLayout == TwoPhotosLayout.stacked) {
        return Column(
          children: [
            Expanded(child: _buildSlidePhotoTile(photos[0])),
            const SizedBox(height: 10),
            Expanded(child: _buildSlidePhotoTile(photos[1])),
          ],
        );
      } else {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _buildSlidePhotoTile(photos[0])),
            const SizedBox(width: 10),
            Expanded(child: _buildSlidePhotoTile(photos[1])),
          ],
        );
      }
    }

    // 3 galleries: Balanced Editorial Collage (1 Top Hero + 2 Bottom Split)
    // Rotates the Top Hero position per slide so each gallery takes turns as the main feature!
    if (photos.length == 3) {
      final heroIndex = slide.slideIndex % 3;
      final heroPhoto = photos[heroIndex];
      final subPhoto1 = photos[(heroIndex + 1) % 3];
      final subPhoto2 = photos[(heroIndex + 2) % 3];

      return Column(
        children: [
          Expanded(
            flex: 11,
            child: _buildSlidePhotoTile(heroPhoto),
          ),
          const SizedBox(height: 10),
          Expanded(
            flex: 9,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _buildSlidePhotoTile(subPhoto1)),
                const SizedBox(width: 10),
                Expanded(child: _buildSlidePhotoTile(subPhoto2)),
              ],
            ),
          ),
        ],
      );
    }

    // 4 galleries: 2x2 grid
    if (photos.length == 4) {
      return Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(child: _buildSlidePhotoTile(photos[0])),
                const SizedBox(width: 10),
                Expanded(child: _buildSlidePhotoTile(photos[1])),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Row(
              children: [
                Expanded(child: _buildSlidePhotoTile(photos[2])),
                const SizedBox(width: 10),
                Expanded(child: _buildSlidePhotoTile(photos[3])),
              ],
            ),
          ),
        ],
      );
    }

    // 5+ photos: responsive grid
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: photos.length <= 6 ? 2 : 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.85,
      ),
      itemCount: photos.length,
      itemBuilder: (ctx, idx) => _buildSlidePhotoTile(photos[idx]),
    );
  }

  Widget _buildSlidePhotoTile(GroupGalleryImage photo) {
    final groupName = widget.groupNamesMap?[photo.groupId] ?? '';
    final isNetwork = photo.imageUrl.startsWith('http://') ||
        photo.imageUrl.startsWith('https://');

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('slide_photo_${photo.imageId}'),
          onTap: _showOverlay,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0F0B18),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.14),
                width: 1.2,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black54,
                  blurRadius: 16,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 1. Ambient Blurred Backdrop:
                // Matches photo colors, scaled up with blur and dark cinematic vignette
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(19),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ImageFiltered(
                          imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                          child: Transform.scale(
                            scale: 1.2,
                            child: isNetwork
                                ? CachedNetworkImage(
                                    imageUrl: getOriginalHighQualityImageUrl(photo.imageUrl),
                                    fit: BoxFit.cover,
                                    alignment: Alignment.center,
                                  )
                                : Image.file(
                                    File(photo.imageUrl),
                                    fit: BoxFit.cover,
                                    alignment: Alignment.center,
                                  ),
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.45),
                                Colors.black.withValues(alpha: 0.25),
                                Colors.black.withValues(alpha: 0.65),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 2. Crisp, Uncropped Main Photo (BoxFit.contain preserves 100% of subject)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: isNetwork
                          ? CachedNetworkImage(
                              imageUrl: getOriginalHighQualityImageUrl(photo.imageUrl),
                              fit: BoxFit.contain,
                              alignment: Alignment.center,
                              placeholder: (_, __) => const Center(
                                child: SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white24,
                                  ),
                                ),
                              ),
                              errorWidget: (_, __, ___) => const Center(
                                child: Icon(Icons.broken_image, color: Colors.white38),
                              ),
                            )
                          : Image.file(
                              File(photo.imageUrl),
                              fit: BoxFit.contain,
                              alignment: Alignment.center,
                            ),
                    ),
                  ),
                ),

                // 3. Floating group badge in top-left
                if (groupName.isNotEmpty)
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4.5),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: widget.accentColor.withValues(alpha: 0.65),
                          width: 1.0,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black45,
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6.5,
                            height: 6.5,
                            decoration: BoxDecoration(
                              color: widget.accentColor,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: widget.accentColor.withValues(alpha: 0.6),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 160),
                            child: Text(
                              groupName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // 4. Sleek Maximize Icon Button in bottom-right (Icon only, no text)
                Positioned(
                  bottom: 10,
                  right: 10,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      key: ValueKey('maximize_btn_${photo.imageId}'),
                      onTap: () => _maximizePhoto(photo),
                      borderRadius: BorderRadius.circular(20),
                      child: Tooltip(
                        message: 'Maximize photo',
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.72),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.35),
                              width: 1.0,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black45,
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.open_in_full_rounded,
                              size: 16,
                              color: Colors.white,
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
      ),
    );
  }

  Widget _buildMaximizedView(GroupGalleryImage photo) {
    final groupName = widget.groupNamesMap?[photo.groupId] ?? '';
    final isNetwork = photo.imageUrl.startsWith('http://') ||
        photo.imageUrl.startsWith('https://');
    final ImageProvider provider = isNetwork
        ? CachedNetworkImageProvider(
            getOriginalHighQualityImageUrl(photo.imageUrl),
          )
        : FileImage(File(photo.imageUrl)) as ImageProvider;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Fullscreen Photo with Pinch-To-Zoom & Pan
        PhotoView(
          imageProvider: provider,
          backgroundDecoration: const BoxDecoration(color: Colors.black),
          minScale: PhotoViewComputedScale.contained,
          maxScale: PhotoViewComputedScale.covered * 3.5,
        ),

        // Top Controls Bar with Minimize button
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
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    // Minimize icon button (resumes slideshow automatically, icon only, no text)
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        key: const ValueKey('minimize_photo_btn'),
                        onTap: _minimizePhoto,
                        borderRadius: BorderRadius.circular(20),
                        child: Tooltip(
                          message: 'Minimize photo',
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: widget.accentColor.withValues(alpha: 0.85),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: widget.accentColor
                                      .withValues(alpha: 0.45),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.close_fullscreen_rounded,
                                size: 18,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (groupName.isNotEmpty) ...[
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2),
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            groupName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    // Paused indicator badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.pause_circle_rounded,
                              size: 14, color: Colors.amber),
                          SizedBox(width: 4),
                          Text(
                            'Paused',
                            style: TextStyle(
                              color: Colors.amber,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      icon: const GoogleLensIcon(),
                      tooltip: 'Search with Google Lens',
                      onPressed: () => GoogleLensService.search(
                        context: context,
                        imageUrl: isNetwork ? photo.imageUrl : null,
                        localPath: isNetwork ? null : photo.imageUrl,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.download_rounded,
                          color: Colors.white),
                      tooltip: 'Save Photo',
                      onPressed: () async {
                        if (isNetwork) {
                          final media = GalleryMediaService();
                          await media.saveImage(
                            imageUrl: photo.imageUrl,
                            imageId: photo.imageId,
                          );
                          if (mounted) {
                            AppSnackBar.show(context,
                                message: '✅ Saved photo in high quality');
                          }
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTopBar() {
    final hasSlideSets = widget.slideSets != null && widget.slideSets!.isNotEmpty;
    final String titleText;
    final String subtitleText;

    if (_mode == MultiGalleryMode.sameSlide && _slideSets.isNotEmpty) {
      titleText = 'Slide ${_currentIndex + 1} of ${_slideSets.length} • Same Slide';
      final count = _slideSets[_currentIndex].photos.length;
      subtitleText = '$count Galleries synced together';
    } else {
      titleText = _playlist.isNotEmpty
          ? 'Slideshow (${_currentIndex + 1}/${_playlist.length})'
          : 'Slideshow';
      subtitleText = widget.groupName;
    }

    return Positioned(
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
              // ── Top Row: Close button + Full-width Title & Subtitle ────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            titleText,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            subtitleText,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ── Action Controls Row (Down the title) ───────────────
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Mode Toggle (Alternate vs Same Slide)
                    if (hasSlideSets)
                      Tooltip(
                        message: _mode == MultiGalleryMode.sameSlide
                            ? 'Switch to Alternate Images Mode'
                            : 'Switch to Same Slide Mode',
                        child: InkWell(
                          key: const ValueKey('same_slide_toggle_btn'),
                          onTap: _toggleMode,
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _mode == MultiGalleryMode.sameSlide
                                  ? widget.accentColor.withValues(alpha: 0.25)
                                  : Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: _mode == MultiGalleryMode.sameSlide
                                    ? widget.accentColor
                                    : Colors.white30,
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _mode == MultiGalleryMode.sameSlide
                                      ? Icons.view_carousel_rounded
                                      : Icons.splitscreen_rounded,
                                  size: 14,
                                  color: _mode == MultiGalleryMode.sameSlide
                                      ? widget.accentColor
                                      : Colors.white,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _mode == MultiGalleryMode.sameSlide
                                      ? 'Alternate'
                                      : 'Same Slide',
                                  style: TextStyle(
                                    color: _mode == MultiGalleryMode.sameSlide
                                        ? widget.accentColor
                                        : Colors.white,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                    // 2-Photo Layout Switcher (Stacked vs Side-by-Side)
                    if (_mode == MultiGalleryMode.sameSlide &&
                        _slideSets.isNotEmpty &&
                        _currentIndex < _slideSets.length &&
                        _slideSets[_currentIndex].photos.length == 2)
                      IconButton(
                        key: const ValueKey('two_photos_layout_toggle_btn'),
                        icon: Icon(
                          _twoPhotosLayout == TwoPhotosLayout.stacked
                              ? Icons.view_column_rounded
                              : Icons.view_agenda_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                        tooltip: _twoPhotosLayout == TwoPhotosLayout.stacked
                            ? 'Switch to Side-by-Side'
                            : 'Switch to Stacked (Top & Bottom)',
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          setState(() {
                            _twoPhotosLayout =
                                _twoPhotosLayout == TwoPhotosLayout.stacked
                                    ? TwoPhotosLayout.sideBySide
                                    : TwoPhotosLayout.stacked;
                          });
                        },
                      ),

                    // Download photo
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
                          : const Icon(Icons.download_rounded,
                              color: Colors.white),
                      tooltip: 'Save photo',
                      onPressed: _isDownloading ? null : _downloadCurrent,
                    ),

                    // Speed menu
                    _SpeedMenu(
                        current: _intervalSeconds, onSelect: _setSpeed),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    final total = _totalCount;
    final isSameSlide = _mode == MultiGalleryMode.sameSlide;

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withValues(alpha: isSameSlide ? 0.8 : 0.9),
              Colors.black.withValues(alpha: isSameSlide ? 0.3 : 0.45),
              Colors.transparent,
            ],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, isSameSlide ? 10 : 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _DotIndicator(
                  count: total,
                  current: _currentIndex,
                  accentColor: widget.accentColor,
                ),
                const SizedBox(height: 6),

                // Progress bar
                AnimatedBuilder(
                  animation: _progressAnim,
                  builder: (_, __) => ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: _progressAnim.value,
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        widget.accentColor,
                      ),
                      minHeight: 2.5,
                    ),
                  ),
                ),
                const SizedBox(height: 6),

                // Controls row
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      total > 0 ? '${_currentIndex + 1} / $total' : '0 / 0',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(
                        Icons.skip_previous,
                        color: Colors.white,
                        size: 26,
                      ),
                      onPressed: _previous,
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: _togglePlay,
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: widget.accentColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: widget.accentColor.withValues(alpha: 0.4),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(
                          _isPlaying ? Icons.pause : Icons.play_arrow,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(
                        Icons.skip_next,
                        color: Colors.white,
                        size: 26,
                      ),
                      onPressed: _advance,
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_intervalSeconds}s',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Fullscreen Lightbox Viewer with Pinch-To-Zoom & Save
// ─────────────────────────────────────────────────────────────────────────────

class PhotoLightboxViewer extends StatelessWidget {
  final GroupGalleryImage photo;
  final String groupName;
  final Color accentColor;

  const PhotoLightboxViewer({
    super.key,
    required this.photo,
    required this.groupName,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final isNetwork = photo.imageUrl.startsWith('http://') ||
        photo.imageUrl.startsWith('https://');
    final ImageProvider provider = isNetwork
        ? CachedNetworkImageProvider(
            getOriginalHighQualityImageUrl(photo.imageUrl),
          )
        : FileImage(File(photo.imageUrl)) as ImageProvider;

    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.96),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Zoomable Photo (Pinch to zoom, pan)
          PhotoView(
            imageProvider: provider,
            backgroundDecoration:
                const BoxDecoration(color: Colors.transparent),
            minScale: PhotoViewComputedScale.contained,
            maxScale: PhotoViewComputedScale.covered * 3.5,
          ),

          // Top Header Bar
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
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close_rounded,
                            color: Colors.white, size: 26),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 4),
                      if (groupName.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4.5),
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: accentColor.withValues(alpha: 0.6),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: accentColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 220),
                                child: Text(
                                  groupName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const Spacer(),
                      IconButton(
                        icon: const GoogleLensIcon(),
                        tooltip: 'Search with Google Lens',
                        onPressed: () => GoogleLensService.search(
                          context: context,
                          imageUrl: isNetwork ? photo.imageUrl : null,
                          localPath: isNetwork ? null : photo.imageUrl,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.download_rounded,
                            color: Colors.white),
                        tooltip: 'Save Photo',
                        onPressed: () async {
                          if (isNetwork) {
                            final media = GalleryMediaService();
                            await media.saveImage(
                              imageUrl: photo.imageUrl,
                              imageId: photo.imageId,
                            );
                            if (context.mounted) {
                              AppSnackBar.show(context,
                                  message: '✅ Saved photo in high quality');
                            }
                          }
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Speed menu
// ─────────────────────────────────────────────────────────────────────────────

class _SpeedMenu extends StatelessWidget {
  final int current;
  final ValueChanged<int> onSelect;
  const _SpeedMenu({required this.current, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      icon: const Icon(Icons.speed, color: Colors.white),
      color: Colors.grey[900],
      tooltip: 'Slideshow speed',
      onSelected: onSelect,
      itemBuilder: (_) => [3, 5, 8, 10, 15].map((s) {
        return PopupMenuItem<int>(
          value: s,
          child: Row(
            children: [
              if (s == current)
                const Icon(Icons.check, size: 16, color: Colors.white)
              else
                const SizedBox(width: 16),
              const SizedBox(width: 8),
              Text(
                '${s}s per photo',
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dot indicator
// ─────────────────────────────────────────────────────────────────────────────

class _DotIndicator extends StatelessWidget {
  final int count;
  final int current;
  final Color accentColor;
  const _DotIndicator({
    required this.count,
    required this.current,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    if (count <= 1) return const SizedBox.shrink();
    const maxDots = 7;
    final visible = count.clamp(1, maxDots);
    final start = (current - maxDots ~/ 2).clamp(0, count - visible);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(visible, (i) {
        final isActive = (start + i) == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: isActive ? 16 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: isActive ? accentColor : Colors.white.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }
}
