import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:gallery_saver_plus/gallery_saver.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_view/photo_view.dart';
import 'package:worship_chat/models/group_gallery_image.dart';

class SlideshowScreen extends StatefulWidget {
  final List<GroupGalleryImage> images;
  final int initialIndex;
  final Color accentColor;
  final String groupName;

  const SlideshowScreen({
    super.key,
    required this.images,
    required this.initialIndex,
    required this.accentColor,
    required this.groupName,
  });

  @override
  State<SlideshowScreen> createState() => _SlideshowScreenState();
}

class _SlideshowScreenState extends State<SlideshowScreen>
    with SingleTickerProviderStateMixin {
  late PageController _pageCtrl;
  late List<GroupGalleryImage> _playlist; // shuffled or original order
  late int _currentIndex;

  bool _isPlaying = true;
  bool _isDownloading = false;
  int _intervalSeconds = 3;

  late AnimationController _progressCtrl;
  late Animation<double> _progressAnim;

  bool _overlayOn = true;
  Timer? _overlayHideTimer;

  @override
  void initState() {
    super.initState();
    _playlist = List.of(widget.images);
    _currentIndex = widget.initialIndex;
    _pageCtrl = PageController(initialPage: widget.initialIndex);

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
    final next = (_currentIndex + 1) % _playlist.length;
    _pageCtrl.animateToPage(
      next,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOut,
    );
    if (_isPlaying) _startSlideshow();
  }

  void _previous() {
    final prev = (_currentIndex - 1 + _playlist.length) % _playlist.length;
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

  // ── Download ──────────────────────────────────────────────────────────────

  Future<void> _downloadCurrent() async {
    if (_isDownloading) return;
    setState(() => _isDownloading = true);

    try {
      final img = _playlist[_currentIndex];
      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/${img.imageId}.jpg';

      await Dio().download(img.imageUrl, filePath);
      final saved = await GallerySaver.saveImage(
        filePath,
        albumName: 'Worship Chat', 
        toDcim: false,
      );
      await File(filePath).delete();

      if (mounted) {
        _snack(
          saved == true
              ? '✅ Saved to Worship Chat album'
              : '⚠️ Could not save image',
          saved == true ? widget.accentColor : Colors.redAccent,
        );
      }
    } catch (e) {
      if (mounted) _snack('⚠️ Download failed', Colors.redAccent);
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _showOverlay,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Photo pager
            PageView.builder(
              controller: _pageCtrl,
              itemCount: _playlist.length,
              onPageChanged: (i) {
                setState(() => _currentIndex = i);
                if (_isPlaying) _startSlideshow();
              },
              itemBuilder: (ctx, i) => PhotoView(
                imageProvider: CachedNetworkImageProvider(
                  _playlist[i].imageUrl,
                ),
                backgroundDecoration: const BoxDecoration(color: Colors.black),
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 2,
              ),
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
    );
  }

  Widget _buildTopBar() {
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
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Slideshow',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  widget.groupName,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
            actions: [
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
                    : const Icon(Icons.download_rounded, color: Colors.white),
                tooltip: 'Save photo',
                onPressed: _isDownloading ? null : _downloadCurrent,
              ),
              // Speed menu
              _SpeedMenu(current: _intervalSeconds, onSelect: _setSpeed),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    return Positioned(
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
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _DotIndicator(
                  count: _playlist.length,
                  current: _currentIndex,
                  accentColor: widget.accentColor,
                ),
                const SizedBox(height: 12),

                // Progress bar
                AnimatedBuilder(
                  animation: _progressAnim,
                  builder: (_, __) => ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: _progressAnim.value,
                      backgroundColor: Colors.white.withOpacity(0.2),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        widget.accentColor,
                      ),
                      minHeight: 3,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Controls row
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${_currentIndex + 1} / ${_playlist.length}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(
                        Icons.skip_previous,
                        color: Colors.white,
                        size: 28,
                      ),
                      onPressed: _previous,
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _togglePlay,
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: widget.accentColor,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _isPlaying ? Icons.pause : Icons.play_arrow,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(
                        Icons.skip_next,
                        color: Colors.white,
                        size: 28,
                      ),
                      onPressed: _advance,
                    ),
                    const Spacer(),
                    Text(
                      '${_intervalSeconds}s',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
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
      itemBuilder: (_) => [2, 3, 5, 8, 10].map((s) {
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
            color: isActive ? accentColor : Colors.white.withOpacity(0.4),
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }
}
