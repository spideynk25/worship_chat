import 'dart:developer';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/utils/utils.dart';
import 'package:worship_chat/features/auth/controller/auth_controller.dart';
import 'package:worship_chat/features/status/controller/status_controller.dart';

class ConfirmStatusScreen extends ConsumerStatefulWidget {
  static const String routeName = '/confirm-status-screen';
  const ConfirmStatusScreen({super.key});

  @override
  ConsumerState<ConfirmStatusScreen> createState() =>
      _ConfirmStatusScreenState();
}

class _ConfirmStatusScreenState extends ConsumerState<ConfirmStatusScreen> {
  List<File> _files = [];
  int _currentIndex = 0;
  late final PageController _pageController;
  bool _isVideo = false;
  bool _argsLoaded = false;

  VideoPlayerController? _videoController;
  bool _videoReady = false;
  bool _muted = false;
  bool _isUploading = false;
  int _uploadProgressIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_argsLoaded) return;
    _argsLoaded = true;

    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    if (args == null) return;

    if (args['files'] is List<File>) {
      _files = List<File>.from(args['files'] as List<File>);
    } else if (args['files'] is List) {
      _files = (args['files'] as List).whereType<File>().toList();
    } else if (args['file'] is File) {
      _files = [args['file'] as File];
    }
    _isVideo = args['isVideo'] as bool? ?? false;

    if (_isVideo && _files.isNotEmpty) {
      _initVideo(_files.first);
    }
  }

  Future<void> _initVideo(File file) async {
    final controller = VideoPlayerController.file(file);
    _videoController = controller;
    await controller.initialize();
    if (!mounted) return;
    controller.setLooping(true);
    controller.setVolume(_muted ? 0 : 1);
    controller.play();
    setState(() => _videoReady = true);
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    _videoController?.setVolume(_muted ? 0 : 1);
  }

  Future<void> _pickMorePhotos() async {
    try {
      final pickedList = await ImagePicker().pickMultiImage(imageQuality: 90);
      if (pickedList.isNotEmpty && mounted) {
        setState(() {
          _files.addAll(pickedList.map((x) => File(x.path)));
        });
      }
    } catch (e) {
      log('Error picking more photos: $e');
    }
  }

  void _removePhoto(int index) {
    if (_files.length <= 1) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _files.removeAt(index);
      if (_currentIndex >= _files.length) {
        _currentIndex = _files.length - 1;
      }
    });
    if (_pageController.hasClients) {
      _pageController.jumpToPage(_currentIndex);
    }
  }

  Future<void> _upload() async {
    if (_files.isEmpty) return;
    setState(() {
      _isUploading = true;
      _uploadProgressIndex = 0;
    });
    _videoController?.pause();

    var userAsync = ref.read(userDataAuthProvider);
    if (userAsync.value == null) {
      for (int i = 0; i < 10; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        userAsync = ref.read(userDataAuthProvider);
        if (userAsync.value != null) break;
      }
    }

    final user = userAsync.value;
    if (user == null) {
      setState(() => _isUploading = false);
      _videoController?.play();
      if (mounted) {
        AppSnackBar.error(context, "Could not load user data. Try again.");
      }
      return;
    }

    await ref.read(statusControllerProvider).uploadMultipleStatuses(
          userName: user.name ?? '',
          profilePic: user.profilePic ?? '',
          email: user.email ?? '',
          statusFiles: _files,
          isVideo: _isVideo,
          context: context,
          onProgress: (current, total) {
            if (mounted) {
              setState(() {
                _uploadProgressIndex = current;
              });
            }
          },
        );

    if (mounted) {
      Navigator.pop(context);
      AppSnackBar.success(context, "Story shared successfully!");
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_files.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    final size = MediaQuery.of(context).size;
    final currentFile = _files[_currentIndex.clamp(0, _files.length - 1)];

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Full-screen blurred background ─────────────────────────
          if (!_isVideo)
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
              child: Image.file(
                currentFile,
                fit: BoxFit.cover,
                color: Colors.black.withValues(alpha: 0.35),
                colorBlendMode: BlendMode.darken,
              ),
            )
          else
            const ColoredBox(color: Colors.black),

          // ── Media preview centered ──────────────────────────────────
          Center(
            child: _isVideo
                ? _buildVideoPreview()
                : _buildMultiImagePreview(size),
          ),

          // ── Top gradient scrim ──────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 130,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.75),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // ── Header (Back button, counter badge, action icon) ─────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(left: 12, right: 12, top: 8),
              child: Row(
                children: [
                  _GlassIcon(
                    icon: Icons.arrow_back_ios_new_rounded,
                    onTap: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  if (!_isVideo && _files.length > 1)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Text(
                        '${_currentIndex + 1} / ${_files.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  const Spacer(),
                  if (_isVideo)
                    _GlassIcon(
                      icon: _muted
                          ? Icons.volume_off_rounded
                          : Icons.volume_up_rounded,
                      onTap: _toggleMute,
                    )
                  else if (_files.length > 1)
                    _GlassIcon(
                      icon: Icons.delete_outline_rounded,
                      onTap: () => _removePhoto(_currentIndex),
                    )
                  else
                    const SizedBox(width: 40),
                ],
              ),
            ),
          ),

          // ── Bottom gradient scrim ───────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: _files.length > 1 && !_isVideo ? 210 : 140,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.9),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // ── Horizontal thumbnail strip for multiple photos ──────────
          if (!_isVideo && _files.length > 1 && !_isUploading)
            Positioned(
              bottom: 84,
              left: 0,
              right: 0,
              height: 58,
              child: _buildThumbnailStrip(),
            ),

          // ── Bottom action buttons ───────────────────────────────────
          if (!_isUploading)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Row(
                    children: [
                      // Discard
                      ClipRRect(
                        borderRadius: BorderRadius.circular(50),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                          child: GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 22,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(50),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.2),
                                ),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.close_rounded,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    "Discard",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const Spacer(),
                      // Share button
                      GestureDetector(
                        onTap: _upload,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 26,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: tabColor,
                            borderRadius: BorderRadius.circular(50),
                            boxShadow: [
                              BoxShadow(
                                color: tabColor.withValues(alpha: 0.4),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.send_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _files.length > 1
                                    ? "Share (${_files.length}) to Story"
                                    : "Share to Story",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── Upload progress overlay ─────────────────────────────────
          if (_isUploading)
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: Container(
                color: Colors.black.withValues(alpha: 0.65),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                      const SizedBox(height: 18),
                      Text(
                        _files.length > 1
                            ? "Sharing ${_uploadProgressIndex + 1} of ${_files.length} to story..."
                            : (_isVideo
                                ? "Sharing video to story..."
                                : "Sharing to story..."),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Multi-image preview with PageView ───────────────────────────────────────

  Widget _buildMultiImagePreview(Size size) {
    if (_files.length == 1) {
      return SizedBox(
        width: size.width,
        height: size.height,
        child: Image.file(_files.first, fit: BoxFit.contain),
      );
    }

    return PageView.builder(
      controller: _pageController,
      itemCount: _files.length,
      onPageChanged: (idx) {
        setState(() => _currentIndex = idx);
      },
      itemBuilder: (context, index) {
        return SizedBox(
          width: size.width,
          height: size.height,
          child: Image.file(_files[index], fit: BoxFit.contain),
        );
      },
    );
  }

  // ── Horizontal thumbnail strip ─────────────────────────────────────────────

  Widget _buildThumbnailStrip() {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: _files.length + 1,
      separatorBuilder: (_, __) => const SizedBox(width: 8),
      itemBuilder: (context, i) {
        if (i == _files.length) {
          // Add more photos tile
          return GestureDetector(
            onTap: _pickMorePhotos,
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.25),
                ),
              ),
              child: const Icon(
                Icons.add_photo_alternate_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
          );
        }

        final isSelected = i == _currentIndex;
        return GestureDetector(
          onTap: () {
            setState(() => _currentIndex = i);
            if (_pageController.hasClients) {
              _pageController.jumpToPage(i);
            }
          },
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected ? tabColor : Colors.white.withValues(alpha: 0.25),
                width: isSelected ? 2.5 : 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                _files[i],
                fit: BoxFit.cover,
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Video preview ──────────────────────────────────────────────────────────

  Widget _buildVideoPreview() {
    if (!_videoReady || _videoController == null) {
      return const CircularProgressIndicator(
        color: Colors.white,
        strokeWidth: 2,
      );
    }
    return GestureDetector(
      onTap: () => setState(() {
        _videoController!.value.isPlaying
            ? _videoController!.pause()
            : _videoController!.play();
      }),
      child: AspectRatio(
        aspectRatio: _videoController!.value.aspectRatio,
        child: Stack(
          alignment: Alignment.center,
          children: [
            VideoPlayer(_videoController!),
            // Play/pause icon
            ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: _videoController!,
              builder: (_, value, __) => AnimatedOpacity(
                opacity: value.isPlaying ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 34,
                  ),
                ),
              ),
            ),
            // Duration chip
            Positioned(
              bottom: 10,
              right: 10,
              child: ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: _videoController!,
                builder: (_, value, __) => Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_fmt(value.position)} / ${_fmt(value.duration)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
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

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

// ── Glass icon button ───────────────────────────────────────────────────────

class _GlassIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _GlassIcon({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(50),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
        ),
      ),
    );
  }
}