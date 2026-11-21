import 'dart:io';
import 'package:any_link_preview/any_link_preview.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:worship_chat/common/utils/background_task_service.dart';
import 'package:worship_chat/common/utils/google_lens_service.dart';
import 'package:worship_chat/common/utils/media_cache_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_view/photo_view.dart';
import 'dart:developer';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/utils/utils.dart';
import 'package:worship_chat/features/settings/providers/chat_bubble_settings_provider.dart';
import 'document_message_widget.dart';
import 'location_message_widget.dart';
import 'forward_message_sheet.dart';

// Enhanced MediaPreviewWidget with download and fullscreen
class MediaPreviewWidget extends StatefulWidget {
  final String mediaType;
  final String mediaUrl;
  final bool showAppBar;

  const MediaPreviewWidget({
    super.key,
    required this.mediaType,
    required this.mediaUrl,
    this.showAppBar = true,
  });

  @override
  State<MediaPreviewWidget> createState() => _MediaPreviewWidgetState();
}

class _MediaPreviewWidgetState extends State<MediaPreviewWidget> {
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;
  bool _isMuted = false;
  bool _showControls = true;
  String? _errorMessage;
  String? _localMediaPath;
  bool _isLoading = true;
  bool _isDownloading = false;
  bool _isFullscreen = false;

  @override
  void initState() {
    super.initState();
    _loadMedia();
  }

  Future<void> _loadMedia() async {
    try {
      // Synchronously check if local file is already available
      final syncLocal = MediaCacheService().getCachedSync(widget.mediaUrl);
      if (syncLocal != null && File(syncLocal).existsSync()) {
        _localMediaPath = syncLocal;
      } else if (!widget.mediaUrl.startsWith('http://') &&
          !widget.mediaUrl.startsWith('https://')) {
        final clean = widget.mediaUrl.replaceFirst('file://', '');
        if (File(clean).existsSync()) {
          _localMediaPath = clean;
        }
      }

      if (widget.mediaType == 'video') {
        VideoPlayerController? controller;
        if (_localMediaPath != null && File(_localMediaPath!).existsSync()) {
          controller = VideoPlayerController.file(File(_localMediaPath!));
        } else if (widget.mediaUrl.startsWith('http://') ||
            widget.mediaUrl.startsWith('https://')) {
          controller = VideoPlayerController.networkUrl(
            Uri.parse(widget.mediaUrl),
          );
          _prefetchLocalMedia();
        } else {
          final clean = widget.mediaUrl.replaceFirst('file://', '');
          if (File(clean).existsSync()) {
            _localMediaPath = clean;
            controller = VideoPlayerController.file(File(clean));
          } else if (Uri.tryParse(widget.mediaUrl)?.isAbsolute ?? false) {
            controller = VideoPlayerController.networkUrl(
              Uri.parse(widget.mediaUrl),
            );
          }
        }

        if (controller != null) {
          try {
            await controller.initialize();
            if (!mounted) {
              controller.dispose();
              return;
            }
            setState(() {
              _videoController = controller;
              _isVideoInitialized = true;
              _isLoading = false;
              _isMuted = false;
              _videoController!.setVolume(1.0);
              _videoController!.play();
            });
            Future.delayed(const Duration(seconds: 3), () {
              if (mounted) setState(() => _showControls = false);
            });
          } catch (error) {
            // If file playback failed and URL is remote, try networkUrl
            if (_localMediaPath != null &&
                (widget.mediaUrl.startsWith('http://') ||
                    widget.mediaUrl.startsWith('https://'))) {
              try {
                controller.dispose();
                final netController = VideoPlayerController.networkUrl(
                  Uri.parse(widget.mediaUrl),
                );
                await netController.initialize();
                if (!mounted) {
                  netController.dispose();
                  return;
                }
                setState(() {
                  _videoController = netController;
                  _isVideoInitialized = true;
                  _isLoading = false;
                  _isMuted = false;
                  _videoController!.setVolume(1.0);
                  _videoController!.play();
                });
                Future.delayed(const Duration(seconds: 3), () {
                  if (mounted) setState(() => _showControls = false);
                });
                return;
              } catch (_) {}
            }
            if (mounted) {
              setState(() {
                _errorMessage = 'Failed to load video: $error';
                _isLoading = false;
              });
            }
          }
        } else {
          if (mounted) {
            setState(() {
              _errorMessage = 'Video file unavailable';
              _isLoading = false;
            });
          }
        }
      } else {
        // Image or GIF
        setState(() => _isLoading = false);
        _prefetchLocalMedia();
      }
    } catch (e) {
      log('Error loading media: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Error: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _prefetchLocalMedia() {
    if (_localMediaPath != null) return;
    MediaCacheService()
        .getMediaPath(widget.mediaUrl)
        .then((path) {
          if (mounted && path != null && File(path).existsSync()) {
            setState(() => _localMediaPath = path);
          }
        })
        .catchError((_) {});
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _exitFullscreen();
    super.dispose();
  }

  Future<void> _downloadMedia() async {
    setState(() => _isDownloading = true);

    try {
      await BackgroundTaskService.instance.runWithBackgroundTask(
        title: 'Downloading ${widget.mediaType}',
        initialMessage: 'Saving media to device...',
        successMessage: 'Saved to Downloads',
        task: (_) async {
          String? localPath = _localMediaPath;
          if (localPath == null || !File(localPath).existsSync()) {
            localPath = await MediaCacheService().getMediaPath(widget.mediaUrl);
            if (localPath != null && mounted) {
              setState(() => _localMediaPath = localPath);
            }
          }

          if (localPath == null || !File(localPath).existsSync()) {
            if (mounted) {
              AppSnackBar.error(context, 'Media unavailable for download');
            }
            return;
          }

          // Request storage permission for Android
          if (Platform.isAndroid) {
            var status = await Permission.storage.request();

            // For Android 11+ (API 30+), try photos permission
            if (!status.isGranted) {
              if (widget.mediaType == 'image' || widget.mediaType == 'gif') {
                status = await Permission.photos.request();
              } else {
                status = await Permission.videos.request();
              }
            }

            // For Android 11+ (API 30+), request manage external storage
            if (!status.isGranted) {
              status = await Permission.manageExternalStorage.request();
            }

            if (!status.isGranted) {
              if (mounted) {
                AppSnackBar.warning(context, 'Storage permission denied');
              }
              return;
            }
          }

          // Get appropriate directory based on platform
          Directory? directory;
          String displayPath;

          if (Platform.isAndroid) {
            // Try to get external storage directory
            final externalDir = await getExternalStorageDirectory();
            if (externalDir != null) {
              // Navigate to public Downloads folder
              final downloadPath = '/storage/emulated/0/Download/WorshipChat';
              directory = Directory(downloadPath);
              displayPath = 'Downloads/WorshipChat';
            } else {
              // Fallback to app directory
              directory = await getApplicationDocumentsDirectory();
              displayPath = directory.path;
            }
          } else if (Platform.isIOS) {
            // For iOS, save to app documents directory
            directory = await getApplicationDocumentsDirectory();
            displayPath = 'App Documents';
          } else {
            // For other platforms
            directory =
                await getDownloadsDirectory() ??
                await getApplicationDocumentsDirectory();
            displayPath = directory.path;
          }

          // Create directory if it doesn't exist
          if (!await directory.exists()) {
            await directory.create(recursive: true);
          }

          // Create unique filename with proper extension
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final extension = widget.mediaType == 'video'
              ? 'mp4'
              : widget.mediaType == 'gif'
              ? 'gif'
              : 'jpg';
          final fileName = 'WorshipChat_$timestamp.$extension';
          final filePath = '${directory.path}/$fileName';

          // Copy file to destination
          final sourceFile = File(localPath);
          await sourceFile.copy(filePath);

          log('Media saved to: $filePath');

          if (mounted) {
            AppSnackBar.success(context, 'Saved to $displayPath');
          }
        },
      );
    } catch (e) {
      log('Download error: $e');
      if (mounted) {
        AppSnackBar.error(context, 'Download failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }

  void _toggleMute() {
    if (_videoController != null) {
      setState(() {
        _isMuted = !_isMuted;
        _videoController!.setVolume(_isMuted ? 0 : 1);
        _showControls = true;
      });
    }
  }

  void _togglePlayPause() {
    if (_videoController != null && _videoController!.value.isInitialized) {
      final val = _videoController!.value;
      if (val.position >= val.duration && val.duration.inMilliseconds > 0) {
        _videoController!.seekTo(Duration.zero).then((_) {
          _videoController!.play();
          if (mounted) setState(() => _showControls = true);
        });
        return;
      }
      setState(() {
        if (val.isPlaying) {
          _videoController!.pause();
        } else {
          _videoController!.play();
        }
        _showControls = true;
      });
      if (_videoController!.value.isPlaying) {
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted && _videoController?.value.isPlaying == true) {
            setState(() => _showControls = false);
          }
        });
      }
    }
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
      if (_showControls) {
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted && _videoController?.value.isPlaying == true) {
            setState(() => _showControls = false);
          }
        });
      }
    });
  }

  Future<void> _toggleFullscreen() async {
    if (_isFullscreen) {
      await _exitFullscreen();
    } else {
      await _enterFullscreen();
    }
  }

  Future<void> _enterFullscreen() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    final aspectRatio = _videoController?.value.aspectRatio ?? 1.0;
    if (aspectRatio > 1.1) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
    setState(() => _isFullscreen = true);
  }

  Future<void> _exitFullscreen() async {
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    setState(() => _isFullscreen = false);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 600;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: (_isFullscreen || !widget.showAppBar)
          ? null
          : AppBar(
              backgroundColor: Colors.black,
              leading: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
              actions: [
                if (_isDownloading)
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    ),
                  )
                else ...[
                  if (widget.mediaType == 'image')
                    IconButton(
                      icon: const GoogleLensIcon(size: 22),
                      tooltip: 'Search with Google Lens',
                      onPressed: () => GoogleLensService.search(
                        context: context,
                        imageUrl: widget.mediaUrl,
                        localPath: _localMediaPath,
                      ),
                    ),
                  IconButton(
                    icon: const Icon(Icons.download, color: Colors.white),
                    onPressed: _downloadMedia,
                    tooltip: 'Download',
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.forward_rounded,
                      color: Colors.white,
                    ),
                    onPressed: () {
                      ForwardMessageSheet.show(
                        context,
                        ForwardMessagePayload(
                          text: '',
                          messageType: widget.mediaType,
                          fileMessageData: widget.mediaUrl,
                        ),
                      );
                    },
                    tooltip: 'Forward',
                  ),
                ],
              ],
            ),
      body: Center(
        child: _isLoading
            ? const CircularProgressIndicator(color: Colors.white)
            : _errorMessage != null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, color: Colors.red, size: 50),
                  const SizedBox(height: 16),
                  Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                ],
              )
            : (widget.mediaType == 'image' || widget.mediaType == 'gif')
            ? PhotoView(
                imageProvider:
                    (_localMediaPath != null &&
                        File(_localMediaPath!).existsSync())
                    ? FileImage(File(_localMediaPath!))
                    : (widget.mediaUrl.startsWith('http://') ||
                          widget.mediaUrl.startsWith('https://'))
                    ? CachedNetworkImageProvider(widget.mediaUrl)
                    : FileImage(
                            File(widget.mediaUrl.replaceFirst('file://', '')),
                          )
                          as ImageProvider,
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 4,
                initialScale: PhotoViewComputedScale.contained,
                basePosition: Alignment.center,
                loadingBuilder: (context, event) => const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
                errorBuilder: (context, error, stackTrace) => Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.broken_image_rounded,
                      color: Colors.white60,
                      size: 54,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Failed to display full image',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
                backgroundDecoration: const BoxDecoration(color: Colors.black),
              )
            : _isVideoInitialized && _videoController != null
            ? GestureDetector(
                onTap: _toggleControls,
                child: Stack(
                  children: [
                    Center(
                      child: AspectRatio(
                        aspectRatio: _videoController!.value.aspectRatio,
                        child: RepaintBoundary(
                          child: VideoPlayer(_videoController!),
                        ),
                      ),
                    ),
                    // Play/Pause button
                    Align(
                      alignment: Alignment.center,
                      child: AnimatedOpacity(
                        opacity:
                            _showControls || !_videoController!.value.isPlaying
                            ? 0.8
                            : 0.0,
                        duration: const Duration(milliseconds: 300),
                        child: IconButton(
                          icon: Icon(
                            _videoController!.value.isPlaying
                                ? Icons.pause_circle_filled
                                : Icons.play_circle_filled,
                            color: Colors.white,
                            size: isSmallScreen ? 60 : 80,
                          ),
                          onPressed: _togglePlayPause,
                        ),
                      ),
                    ),
                    // Top controls
                    if (_isFullscreen)
                      Positioned(
                        top: 16,
                        left: 16,
                        child: AnimatedOpacity(
                          opacity: _showControls ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 300),
                          child: IconButton(
                            icon: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 28,
                            ),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ),
                      ),
                    // Bottom controls
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: AnimatedOpacity(
                        opacity: _showControls ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 300),
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.8),
                                Colors.transparent,
                              ],
                            ),
                          ),
                          child: SafeArea(
                            top: false,
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: isSmallScreen ? 8 : 12,
                                vertical: isSmallScreen ? 4 : 6,
                              ),
                              child: Row(
                                children: [
                                  IconButton(
                                    icon: Icon(
                                      _isMuted
                                          ? Icons.volume_off_rounded
                                          : Icons.volume_up_rounded,
                                      color: Colors.white,
                                      size: isSmallScreen ? 24 : 28,
                                    ),
                                    onPressed: _toggleMute,
                                  ),
                                  Expanded(
                                    child: SliderTheme(
                                      data: SliderTheme.of(context).copyWith(
                                        trackHeight: 2,
                                        thumbShape: const RoundSliderThumbShape(
                                          enabledThumbRadius: 6,
                                        ),
                                        overlayShape:
                                            const RoundSliderOverlayShape(
                                              overlayRadius: 12,
                                            ),
                                        activeTrackColor: tabColor,
                                        inactiveTrackColor: Colors.white30,
                                        thumbColor: Colors.white,
                                        overlayColor: tabColor.withValues(
                                          alpha: 0.2,
                                        ),
                                      ),
                                      child: Slider(
                                        value: _videoController!
                                            .value
                                            .position
                                            .inSeconds
                                            .toDouble(),
                                        max: _videoController!
                                            .value
                                            .duration
                                            .inSeconds
                                            .toDouble(),
                                        onChanged: (value) {
                                          setState(() {
                                            _videoController!.seekTo(
                                              Duration(seconds: value.toInt()),
                                            );
                                            _showControls = true;
                                          });
                                        },
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    child: Text(
                                      '${_formatDuration(_videoController!.value.position)} / ${_formatDuration(_videoController!.value.duration)}',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: isSmallScreen ? 10 : 12,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      _isFullscreen
                                          ? Icons.fullscreen_exit
                                          : Icons.fullscreen,
                                      color: Colors.white,
                                      size: isSmallScreen ? 24 : 28,
                                    ),
                                    onPressed: _toggleFullscreen,
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
              )
            : const CircularProgressIndicator(color: Colors.white),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class DisplayMessages extends StatefulWidget {
  final String message;
  final String messageType;
  final String? fileMessageData;
  final bool isPreviewable;
  final bool useCachedMedia;
  final bool showLinkPreview; // Option to show link previews
  final bool isMe;
  final bool isSending;
  final String? messageId;
  final String? currentUserId;
  final String? receiverId;
  final String? senderName;
  final String? senderProfilePic;
  final double? mediaWidth;
  final double? mediaHeight;
  final BorderRadius? mediaBorderRadius;
  final Color? textColor;

  const DisplayMessages({
    super.key,
    required this.message,
    required this.messageType,
    this.fileMessageData,
    this.isPreviewable = true,
    this.useCachedMedia = true,
    this.showLinkPreview = true, // Default to true
    this.isMe = false,
    this.isSending = false,
    this.messageId,
    this.currentUserId,
    this.receiverId,
    this.senderName,
    this.senderProfilePic,
    this.mediaWidth,
    this.mediaHeight,
    this.mediaBorderRadius,
    this.textColor,
  });

  @override
  State<DisplayMessages> createState() => _DisplayMessagesState();
}

// -----------------------------------------------------------------------------
// ChatLinkPreviewWidget: High-performance link preview with in-memory caching
// and zero-layout-shift design to eliminate flickering on message list updates.
// -----------------------------------------------------------------------------
class ChatLinkPreviewWidget extends StatefulWidget {
  final String url;
  final bool isSmallScreen;
  final VoidCallback? onTap;

  const ChatLinkPreviewWidget({
    super.key,
    required this.url,
    this.isSmallScreen = false,
    this.onTap,
  });

  // Global static cache persists metadata across widget rebuilds and ListView scroll cycles
  static final Map<String, Metadata> _metadataCache = {};
  static final Set<String> _failedUrls = {};
  static final Map<String, Future<Metadata?>> _inFlightRequests = {};

  static String normalizeUrl(String rawUrl) {
    String clean = rawUrl.trim();
    if (!clean.startsWith('http://') && !clean.startsWith('https://')) {
      clean = 'https://$clean';
    }
    return clean;
  }

  static void prefetch(String rawUrl) {
    final url = normalizeUrl(rawUrl);
    if (_metadataCache.containsKey(url) ||
        _failedUrls.contains(url) ||
        _inFlightRequests.containsKey(url)) {
      return;
    }
    _inFlightRequests[url] =
        AnyLinkPreview.getMetadata(link: url, cache: const Duration(days: 7))
            .then((metadata) {
              if (metadata != null && metadata.hasData) {
                _metadataCache[url] = metadata;
              } else {
                _failedUrls.add(url);
              }
              _inFlightRequests.remove(url);
              return metadata;
            })
            .catchError((_) {
              _failedUrls.add(url);
              _inFlightRequests.remove(url);
              return null;
            });
  }

  @override
  State<ChatLinkPreviewWidget> createState() => _ChatLinkPreviewWidgetState();
}

class _ChatLinkPreviewWidgetState extends State<ChatLinkPreviewWidget>
    with AutomaticKeepAliveClientMixin {
  Metadata? _metadata;
  bool _isLoading = false;
  bool _isFailed = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadMetadata();
  }

  @override
  void didUpdateWidget(covariant ChatLinkPreviewWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _loadMetadata();
    }
  }

  void _loadMetadata() {
    final url = ChatLinkPreviewWidget.normalizeUrl(widget.url);

    // 1. Instant cache hit: render immediately with zero latency and no flash!
    if (ChatLinkPreviewWidget._metadataCache.containsKey(url)) {
      _metadata = ChatLinkPreviewWidget._metadataCache[url];
      _isLoading = false;
      _isFailed = false;
      return;
    }

    // 2. Previously failed
    if (ChatLinkPreviewWidget._failedUrls.contains(url)) {
      _metadata = null;
      _isLoading = false;
      _isFailed = true;
      return;
    }

    // 3. Needs network fetch
    _isLoading = true;
    _isFailed = false;

    final future = ChatLinkPreviewWidget._inFlightRequests[url] ??=
        AnyLinkPreview.getMetadata(link: url, cache: const Duration(days: 7))
            .then((metadata) {
              if (metadata != null && metadata.hasData) {
                ChatLinkPreviewWidget._metadataCache[url] = metadata;
              } else {
                ChatLinkPreviewWidget._failedUrls.add(url);
              }
              ChatLinkPreviewWidget._inFlightRequests.remove(url);
              return metadata;
            })
            .catchError((_) {
              ChatLinkPreviewWidget._failedUrls.add(url);
              ChatLinkPreviewWidget._inFlightRequests.remove(url);
              return null;
            });

    future.then((meta) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        if (meta != null && meta.hasData) {
          _metadata = meta;
          _isFailed = false;
        } else {
          _metadata = null;
          _isFailed = true;
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_metadata != null && _metadata!.hasData) {
      return _buildRichPreviewCard(context, _metadata!);
    }

    return _buildCompactLinkTile(context);
  }

  Widget _buildRichPreviewCard(BuildContext context, Metadata meta) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final title = (meta.title ?? '').trim();
    final desc = (meta.desc ?? '').trim();
    final rawImage = meta.image?.trim();
    final hasValidImage =
        rawImage != null &&
        rawImage.isNotEmpty &&
        !rawImage.contains('via.placeholder') &&
        (rawImage.startsWith('http://') || rawImage.startsWith('https://'));

    final host =
        Uri.tryParse(ChatLinkPreviewWidget.normalizeUrl(widget.url))?.host ??
        '';
    final siteName = (meta.siteName ?? '').trim();
    final displaySource = siteName.isNotEmpty
        ? siteName
        : (host.isNotEmpty ? host.replaceFirst(RegExp(r'^www\.'), '') : '');

    return RepaintBoundary(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: isDark
                  ? theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.6,
                    )
                  : theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: theme.colorScheme.outline.withValues(
                  alpha: isDark ? 0.25 : 0.15,
                ),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasValidImage)
                  CachedNetworkImage(
                    imageUrl: rawImage,
                    height: 140,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    fadeInDuration: Duration.zero,
                    fadeOutDuration: Duration.zero,
                    placeholder: (context, _) => Container(
                      height: 140,
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.4),
                    ),
                    errorWidget: (context, _, __) => const SizedBox.shrink(),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (displaySource.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.link_rounded,
                                size: 13,
                                color: theme.colorScheme.primary.withValues(
                                  alpha: 0.8,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  displaySource,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.primary.withValues(
                                      alpha: 0.85,
                                    ),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (title.isNotEmpty)
                        Text(
                          title,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: widget.isSmallScreen ? 13 : 14,
                            color: theme.colorScheme.onSurface,
                            height: 1.25,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (desc.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          desc,
                          style: TextStyle(
                            fontSize: widget.isSmallScreen ? 11 : 12,
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.2,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactLinkTile(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return RepaintBoundary(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: isDark
                  ? theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    )
                  : theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: theme.colorScheme.outline.withValues(
                  alpha: isDark ? 0.25 : 0.15,
                ),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isFailed ? Icons.link_off_rounded : Icons.link_rounded,
                  color: _isFailed
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.colorScheme.primary,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.url,
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontSize: widget.isSmallScreen ? 12 : 13,
                      decoration: TextDecoration.underline,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_isLoading) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        theme.colorScheme.primary.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DisplayMessagesState extends State<DisplayMessages>
    with AutomaticKeepAliveClientMixin {
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;
  bool _isMuted = true;
  bool _showControls = true;
  String? _errorMessage;
  String? _localMediaPath;
  bool _isLoadingMedia = false;
  List<String> _extractedUrls = [];
  bool _isDownloading = false;

  @override
  bool get wantKeepAlive =>
      widget.messageType == 'video' ||
      (widget.messageType == 'text' && _extractedUrls.isNotEmpty);

  @override
  void initState() {
    super.initState();
    if (widget.useCachedMedia &&
        widget.messageType == 'video' &&
        widget.fileMessageData != null) {
      _loadAndInitializeVideo();
    } else if (!widget.useCachedMedia &&
        widget.messageType == 'video' &&
        widget.fileMessageData != null) {
      _initializeNetworkVideo();
    }

    // Extract URLs from message for link preview and prefetch
    if (widget.messageType == 'text' && widget.showLinkPreview) {
      _extractedUrls = _extractUrls(widget.message);
      for (final url in _extractedUrls) {
        ChatLinkPreviewWidget.prefetch(url);
      }
    }
  }

  @override
  void didUpdateWidget(covariant DisplayMessages oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.messageType == 'text' &&
        widget.showLinkPreview &&
        oldWidget.message != widget.message) {
      _extractedUrls = _extractUrls(widget.message);
      for (final url in _extractedUrls) {
        ChatLinkPreviewWidget.prefetch(url);
      }
    }

    if (widget.messageType == 'video') {
      if (_videoController != null && _isVideoInitialized) {
        if (widget.messageId != null &&
            oldWidget.messageId == widget.messageId) {
          return;
        }
        final oldCached = oldWidget.fileMessageData != null
            ? MediaCacheService().getCachedSync(oldWidget.fileMessageData!)
            : null;
        final newCached = widget.fileMessageData != null
            ? MediaCacheService().getCachedSync(widget.fileMessageData!)
            : null;
        if (oldCached != null && newCached != null && oldCached == newCached) {
          return;
        }
      }
      if (oldWidget.fileMessageData != widget.fileMessageData) {
        if (widget.useCachedMedia && widget.fileMessageData != null) {
          _loadAndInitializeVideo();
        } else if (!widget.useCachedMedia && widget.fileMessageData != null) {
          _initializeNetworkVideo();
        }
      }
    }
  }

  List<String> _extractUrls(String text) {
    final urlPattern = RegExp(
      r'(?:(?:https?|ftp):\/\/)?(?:www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b(?:[-a-zA-Z0-9()@:%_\+.~#?&\/=]*)',
      caseSensitive: false,
    );

    final matches = urlPattern.allMatches(text);
    return matches.map((match) {
      String url = match.group(0)!;
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        url = 'https://$url';
      }
      return url;
    }).toList();
  }

  Future<void> _loadAndInitializeVideo() async {
    if (!_isVideoInitialized) {
      setState(() => _isLoadingMedia = true);
    }

    try {
      final syncPath = MediaCacheService().getCachedSync(
        widget.fileMessageData!,
      );
      final localPath =
          syncPath ??
          await MediaCacheService().getMediaPath(widget.fileMessageData!);

      if (!mounted) return;

      if (localPath == null) {
        setState(() {
          _errorMessage = 'Failed to load video';
          _isLoadingMedia = false;
        });
        return;
      }

      if (_localMediaPath == localPath &&
          _videoController != null &&
          _isVideoInitialized) {
        return;
      }

      setState(() => _localMediaPath = localPath);

      final oldController = _videoController;
      oldController?.removeListener(_onVideoUpdate);
      final newController = VideoPlayerController.file(File(localPath));

      await newController.initialize();
      if (!mounted) {
        newController.dispose();
        return;
      }

      newController.addListener(_onVideoUpdate);

      setState(() {
        _videoController = newController;
        _isVideoInitialized = true;
        _isLoadingMedia = false;
        _isMuted = false;
        _videoController!.setVolume(1.0);
        _videoController!.pause();
        _videoController!.setLooping(false);
        _showControls = true;
      });

      oldController?.dispose();
    } catch (e) {
      log('Error loading cached video: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Error: $e';
          _isLoadingMedia = false;
        });
      }
    }
  }

  void _initializeNetworkVideo() {
    if (Uri.tryParse(widget.fileMessageData!)?.isAbsolute ?? false) {
      final oldController = _videoController;
      oldController?.removeListener(_onVideoUpdate);
      final newController = VideoPlayerController.networkUrl(
        Uri.parse(widget.fileMessageData!),
      );

      newController
          .initialize()
          .then((_) {
            if (mounted) {
              newController.addListener(_onVideoUpdate);
              setState(() {
                _videoController = newController;
                _isVideoInitialized = true;
                _isLoadingMedia = false;
                _isMuted = false;
                _videoController!.setVolume(1.0);
                _videoController!.pause();
                _videoController!.setLooping(false);
                _showControls = true;
              });
              oldController?.dispose();
            } else {
              newController.dispose();
            }
          })
          .catchError((error) {
            if (mounted) {
              setState(() {
                _errorMessage = 'Failed to load video: $error';
                _isLoadingMedia = false;
              });
              log('Video error: $error');
            }
          });
    } else {
      setState(() {
        _errorMessage = 'Invalid video URL';
        _isLoadingMedia = false;
      });
    }
  }

  void _onVideoUpdate() {
    if (mounted && _videoController != null) {
      if (_videoController!.value.isInitialized &&
          _videoController!.value.position >=
              _videoController!.value.duration &&
          !_videoController!.value.isPlaying) {
        if (!_showControls) {
          setState(() => _showControls = true);
        }
      }
      setState(() {});
    }
  }

  @override
  void dispose() {
    _videoController?.removeListener(_onVideoUpdate);
    _videoController?.dispose();
    super.dispose();
  }

  void _openPreview(BuildContext context) {
    if (!widget.isPreviewable ||
        widget.fileMessageData == null ||
        widget.fileMessageData!.isEmpty) {
      return;
    }
    if (widget.messageType != 'image' &&
        widget.messageType != 'video' &&
        widget.messageType != 'gif') {
      return;
    }

    _videoController?.pause();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MediaPreviewWidget(
          mediaType: widget.messageType,
          mediaUrl: widget.fileMessageData!,
        ),
      ),
    );
  }

  void _toggleMute() {
    if (_videoController != null) {
      setState(() {
        _isMuted = !_isMuted;
        _videoController!.setVolume(_isMuted ? 0 : 1);
        _showControls = true;
      });
    }
  }

  void _togglePlayPause() {
    if (_videoController != null && _videoController!.value.isInitialized) {
      setState(() {
        if (_videoController!.value.isPlaying) {
          _videoController!.pause();
          _showControls = true;
        } else {
          if (_videoController!.value.position >=
              _videoController!.value.duration) {
            _videoController!.seekTo(Duration.zero);
          }
          _videoController!.play();
          _showControls = true;
        }
      });
      if (_videoController!.value.isPlaying) {
        Future.delayed(const Duration(milliseconds: 2500), () {
          if (mounted &&
              _videoController != null &&
              _videoController!.value.isPlaying) {
            setState(() => _showControls = false);
          }
        });
      }
    }
  }

  Future<void> _launchURL(String url) async {
    try {
      String cleanUrl = url.trim();

      if (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://')) {
        cleanUrl = 'https://$cleanUrl';
      }

      log('Attempting to open URL: $cleanUrl');

      final uri = Uri.parse(cleanUrl);

      bool canLaunch = await canLaunchUrl(uri);
      log('Can launch URL: $canLaunch');

      if (!canLaunch) {
        if (mounted) {
          AppSnackBar.error(context, 'Cannot open this link: $cleanUrl');
        }
        return;
      }

      bool launched = false;

      try {
        launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
        log('External app launch: $launched');
      } catch (e) {
        log('External app launch failed: $e');
      }

      if (!launched) {
        try {
          launched = await launchUrl(uri, mode: LaunchMode.platformDefault);
          log('Platform default launch: $launched');
        } catch (e) {
          log('Platform default launch failed: $e');
        }
      }

      if (!launched && mounted) {
        AppSnackBar.error(
          context,
          'Could not open link: $cleanUrl',
          actionLabel: 'Retry',
          onAction: () => _launchURL(url),
        );
      }
    } catch (e) {
      log('Error launching URL: $e');
      if (mounted) {
        AppSnackBar.error(context, 'Failed to open link: $e');
      }
    }
  }

  Widget _buildTextWithLinks(
    String text,
    BuildContext context,
    bool isSmallScreen,
  ) {
    final contrast = widget.textColor != null
        ? (widget.textColor!.computeLuminance() < 0.45
              ? ChatBubbleSettings.contrastForBackground(
                  const Color(0xFFF0F0F0),
                )
              : ChatBubbleSettings.contrastForBackground(
                  const Color(0xFF15141F),
                ))
        : ChatBubbleSettings.contrastForBackground(const Color(0xFF15141F));

    final effectiveTextColor = widget.textColor ?? contrast.primaryTextColor;
    final isDarkText = effectiveTextColor.computeLuminance() < 0.45;
    final linkColor = isDarkText ? contrast.linkColor : tabColor;
    final textShadows = contrast.textShadows;

    final urlPattern = RegExp(
      r'(?:(?:https?|ftp):\/\/)?(?:www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b(?:[-a-zA-Z0-9()@:%_\+.~#?&\/=]*)',
      caseSensitive: false,
    );

    final matches = urlPattern.allMatches(text);

    if (matches.isEmpty) {
      return Text(
        text,
        style: TextStyle(
          fontSize: isSmallScreen ? 14 : 16,
          color: effectiveTextColor,
          shadows: textShadows,
        ),
      );
    }

    final spans = <TextSpan>[];
    int currentPosition = 0;

    for (final match in matches) {
      if (match.start > currentPosition) {
        spans.add(
          TextSpan(
            text: text.substring(currentPosition, match.start),
            style: TextStyle(
              fontSize: isSmallScreen ? 14 : 16,
              color: effectiveTextColor,
              shadows: textShadows,
            ),
          ),
        );
      }

      final url = match.group(0)!;
      spans.add(
        TextSpan(
          text: url,
          style: TextStyle(
            fontSize: isSmallScreen ? 14 : 16,
            color: linkColor,
            decoration: TextDecoration.underline,
            shadows: textShadows,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () {
              log('Link tapped: $url');
              _launchURL(url);
            },
        ),
      );

      currentPosition = match.end;
    }

    if (currentPosition < text.length) {
      spans.add(
        TextSpan(
          text: text.substring(currentPosition),
          style: TextStyle(
            fontSize: isSmallScreen ? 14 : 16,
            color: effectiveTextColor,
            shadows: textShadows,
          ),
        ),
      );
    }

    return RichText(text: TextSpan(children: spans));
  }

  Future<void> _downloadVideo() async {
    if (_localMediaPath == null) return;

    setState(() => _isDownloading = true);

    try {
      await BackgroundTaskService.instance.runWithBackgroundTask(
        title: 'Downloading Video',
        initialMessage: 'Saving video to device...',
        successMessage: 'Saved to Downloads',
        task: (_) async {
          if (Platform.isAndroid) {
            var status = await Permission.storage.request();

            if (!status.isGranted) {
              status = await Permission.videos.request();
            }

            if (!status.isGranted) {
              status = await Permission.manageExternalStorage.request();
            }

            if (!status.isGranted) {
              if (mounted) {
                AppSnackBar.warning(context, 'Storage permission denied');
              }
              return;
            }
          }

          Directory? directory;
          String displayPath;

          if (Platform.isAndroid) {
            final externalDir = await getExternalStorageDirectory();
            if (externalDir != null) {
              final downloadPath = '/storage/emulated/0/Download/WorshipChat';
              directory = Directory(downloadPath);
              displayPath = 'Downloads/WorshipChat';
            } else {
              directory = await getApplicationDocumentsDirectory();
              displayPath = directory.path;
            }
          } else if (Platform.isIOS) {
            directory = await getApplicationDocumentsDirectory();
            displayPath = 'App Documents';
          } else {
            directory =
                await getDownloadsDirectory() ??
                await getApplicationDocumentsDirectory();
            displayPath = directory.path;
          }

          if (!await directory.exists()) {
            await directory.create(recursive: true);
          }

          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final fileName = 'WorshipChat_$timestamp.mp4';
          final filePath = '${directory.path}/$fileName';

          final sourceFile = File(_localMediaPath!);
          await sourceFile.copy(filePath);

          log('Video saved to: $filePath');

          if (mounted) {
            AppSnackBar.success(context, 'Saved to $displayPath');
          }
        },
      );
    } catch (e) {
      log('Video download error: $e');
      if (mounted) {
        AppSnackBar.error(context, 'Download failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 600;

    final double defaultMediaWidth = isSmallScreen
        ? (screenWidth * 0.70).clamp(220.0, 275.0)
        : 295.0;
    final double defaultMediaHeight = isSmallScreen ? 235.0 : 265.0;

    final double effectiveMediaWidth =
        widget.mediaWidth ?? (widget.isPreviewable ? defaultMediaWidth : 48.0);
    final double effectiveMediaHeight =
        widget.mediaHeight ??
        (widget.isPreviewable ? defaultMediaHeight : 48.0);
    final BorderRadius effectiveRadius =
        widget.mediaBorderRadius ??
        BorderRadius.circular(widget.isPreviewable ? 14.0 : 8.0);

    Widget content;
    switch (widget.messageType) {
      case 'text':
        content = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTextWithLinks(widget.message, context, isSmallScreen),
            // Add link previews if URLs are found
            if (widget.showLinkPreview && _extractedUrls.isNotEmpty)
              ..._extractedUrls.map(
                (url) => Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: ChatLinkPreviewWidget(
                    key: ValueKey('chat_link_preview_$url'),
                    url: url,
                    isSmallScreen: isSmallScreen,
                    onTap: () => _launchURL(url),
                  ),
                ),
              ),
          ],
        );
        break;

      case 'image':
        final hasExplicitHeight =
            widget.mediaHeight != null || !widget.isPreviewable;
        content =
            widget.fileMessageData != null && widget.fileMessageData!.isNotEmpty
            ? (hasExplicitHeight
                  ? SizedBox(
                      width: effectiveMediaWidth,
                      height: effectiveMediaHeight,
                      child: ClipRRect(
                        borderRadius: effectiveRadius,
                        child: widget.useCachedMedia
                            ? _CachedImageWidget(
                                key: ValueKey(
                                  'cached_img_${widget.messageId ?? widget.fileMessageData}',
                                ),
                                imageUrl: widget.fileMessageData!,
                                screenWidth: screenWidth,
                                width: effectiveMediaWidth,
                                height: effectiveMediaHeight,
                                fit: BoxFit.cover,
                                alignment: Alignment.topCenter,
                              )
                            : CachedNetworkImage(
                                key: ValueKey(
                                  'cni_${widget.messageId ?? widget.fileMessageData}',
                                ),
                                imageUrl: widget.fileMessageData!,
                                width: effectiveMediaWidth,
                                height: effectiveMediaHeight,
                                fit: BoxFit.cover,
                                alignment: Alignment.topCenter,
                                maxWidthDiskCache: (effectiveMediaWidth * 2)
                                    .toInt(),
                                maxHeightDiskCache: (effectiveMediaHeight * 2)
                                    .toInt(),
                                fadeInDuration: Duration.zero,
                                fadeOutDuration: Duration.zero,
                                placeholder: (context, url) => Container(
                                  width: effectiveMediaWidth,
                                  height: effectiveMediaHeight,
                                  color: Colors.white.withValues(alpha: 0.06),
                                ),
                                errorWidget: (context, url, error) => Container(
                                  width: effectiveMediaWidth,
                                  height: effectiveMediaHeight,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest
                                      .withValues(alpha: 0.4),
                                  child: Center(
                                    child: Icon(
                                      Icons.broken_image_outlined,
                                      color: Colors.grey[400],
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                      ),
                    )
                  : ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: effectiveMediaWidth,
                        maxWidth: effectiveMediaWidth,
                        minHeight: 150.0,
                        maxHeight: (effectiveMediaWidth * 1.5).clamp(
                          360.0,
                          440.0,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: effectiveRadius,
                        child: widget.useCachedMedia
                            ? _CachedImageWidget(
                                key: ValueKey(
                                  'cached_img_${widget.messageId ?? widget.fileMessageData}',
                                ),
                                imageUrl: widget.fileMessageData!,
                                screenWidth: screenWidth,
                                width: effectiveMediaWidth,
                                height: null,
                                fit: BoxFit.cover,
                                alignment: Alignment.topCenter,
                              )
                            : CachedNetworkImage(
                                key: ValueKey(
                                  'cni_${widget.messageId ?? widget.fileMessageData}',
                                ),
                                imageUrl: widget.fileMessageData!,
                                width: effectiveMediaWidth,
                                fit: BoxFit.cover,
                                alignment: Alignment.topCenter,
                                maxWidthDiskCache: (effectiveMediaWidth * 2)
                                    .toInt(),
                                fadeInDuration: Duration.zero,
                                fadeOutDuration: Duration.zero,
                                placeholder: (context, url) => Container(
                                  width: effectiveMediaWidth,
                                  height: 240,
                                  color: Colors.white.withValues(alpha: 0.06),
                                  child: const Center(
                                    child: SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ),
                                ),
                                errorWidget: (context, url, error) => Container(
                                  width: effectiveMediaWidth,
                                  height: 160,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest
                                      .withValues(alpha: 0.4),
                                  child: Center(
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.broken_image_outlined,
                                          color: Colors.grey[400],
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Image unavailable',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[300],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                      ),
                    ))
            : Container(
                width: effectiveMediaWidth,
                height: effectiveMediaHeight,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: effectiveRadius,
                ),
                child: const Center(child: Text('Image not available')),
              );
        break;

      case 'video':
        if (!widget.isPreviewable) {
          content = SizedBox(
            width: effectiveMediaWidth,
            height: effectiveMediaHeight,
            child: ClipRRect(
              borderRadius: effectiveRadius,
              child: Container(
                color: Colors.black45,
                child: const Center(
                  child: Icon(
                    Icons.videocam_rounded,
                    color: Colors.white70,
                    size: 22,
                  ),
                ),
              ),
            ),
          );
          break;
        }

        content = _isLoadingMedia
            ? Container(
                width: effectiveMediaWidth,
                height: effectiveMediaHeight,
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: effectiveRadius,
                ),
                child: const Center(
                  child: SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                      color: Colors.white70,
                      strokeWidth: 2,
                    ),
                  ),
                ),
              )
            : _errorMessage != null
            ? Container(
                width: effectiveMediaWidth,
                height: effectiveMediaHeight,
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: effectiveRadius,
                ),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          color: Colors.redAccent,
                          size: 26,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _errorMessage!,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : widget.fileMessageData != null &&
                  _isVideoInitialized &&
                  _videoController != null
            ? VisibilityDetector(
                key: ValueKey(
                  'vd_${widget.messageId ?? widget.fileMessageData!}',
                ),
                onVisibilityChanged: (info) {
                  if (_videoController != null &&
                      _videoController!.value.isInitialized) {
                    final isPlaying = _videoController!.value.isPlaying;
                    if (info.visibleFraction <= 0.05 && isPlaying) {
                      _videoController!.pause();
                      if (mounted) setState(() => _showControls = true);
                    }
                  }
                },
                child: SizedBox(
                  width: effectiveMediaWidth,
                  height: effectiveMediaHeight,
                  child: ClipRRect(
                    borderRadius: effectiveRadius,
                    child: Stack(
                      fit: StackFit.expand,
                      alignment: Alignment.center,
                      children: [
                        // Video fitted with cover
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            if (_videoController != null &&
                                _videoController!.value.isInitialized) {
                              if (_videoController!.value.isPlaying) {
                                setState(() => _showControls = !_showControls);
                              } else {
                                _togglePlayPause();
                              }
                            }
                          },
                          child: FittedBox(
                            fit: BoxFit.cover,
                            clipBehavior: Clip.hardEdge,
                            child: RepaintBoundary(
                              child: SizedBox(
                                width:
                                    (_videoController!.value.isInitialized &&
                                        _videoController!.value.size.width > 0)
                                    ? _videoController!.value.size.width
                                    : 16,
                                height:
                                    (_videoController!.value.isInitialized &&
                                        _videoController!.value.size.height > 0)
                                    ? _videoController!.value.size.height
                                    : 9,
                                child: VideoPlayer(_videoController!),
                              ),
                            ),
                          ),
                        ),
                        // Top gradient overlay for controls readability
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          height: 48,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withValues(alpha: 0.55),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Bottom gradient overlay for duration and volume
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          height: 48,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [
                                  Colors.black.withValues(alpha: 0.65),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Center Play/Pause button
                        Align(
                          alignment: Alignment.center,
                          child: GestureDetector(
                            onTap: _togglePlayPause,
                            child: AnimatedOpacity(
                              opacity:
                                  _showControls ||
                                      !_videoController!.value.isPlaying
                                  ? 1.0
                                  : 0.0,
                              duration: const Duration(milliseconds: 250),
                              child: Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.60),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.35),
                                    width: 1.2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.4,
                                      ),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Icon(
                                    _videoController!.value.isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 32,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Top-right controls (Download & Fullscreen)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_isDownloading)
                                Container(
                                  padding: const EdgeInsets.all(5),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.55),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              else
                                GestureDetector(
                                  onTap: _downloadVideo,
                                  child: Container(
                                    padding: const EdgeInsets.all(5),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(
                                        alpha: 0.55,
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.download_rounded,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                  ),
                                ),
                              const SizedBox(width: 5),
                              GestureDetector(
                                onTap: () => _openPreview(context),
                                child: Container(
                                  padding: const EdgeInsets.all(5),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.55),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.fullscreen_rounded,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Bottom-left controls (Mute & Duration)
                        Positioned(
                          bottom: 7,
                          left: 7,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onTap: _toggleMute,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.55),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    _isMuted
                                        ? Icons.volume_off_rounded
                                        : Icons.volume_up_rounded,
                                    color: Colors.white,
                                    size: 14,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 5),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2.5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.55),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  _formatDuration(
                                    _videoController!.value.isPlaying
                                        ? _videoController!.value.position
                                        : _videoController!.value.duration,
                                  ),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : Container(
                width: effectiveMediaWidth,
                height: effectiveMediaHeight,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: effectiveRadius,
                ),
                child: const Center(child: CircularProgressIndicator()),
              );
        break;

      case 'gif':
        final gifData = widget.fileMessageData;
        final hasGif = gifData != null && gifData.isNotEmpty;
        content = hasGif
            ? SizedBox(
                width: effectiveMediaWidth,
                height: effectiveMediaHeight,
                child: ClipRRect(
                  borderRadius: effectiveRadius,
                  child: widget.useCachedMedia
                      ? _CachedImageWidget(
                          key: ValueKey(
                            'cached_gif_${widget.messageId ?? gifData}',
                          ),
                          imageUrl: gifData,
                          screenWidth: screenWidth,
                          width: effectiveMediaWidth,
                          height: effectiveMediaHeight,
                          fit: BoxFit.cover,
                        )
                      : (gifData.startsWith('http://') ||
                            gifData.startsWith('https://'))
                      ? CachedNetworkImage(
                          key: ValueKey(
                            'cni_gif_${widget.messageId ?? gifData}',
                          ),
                          imageUrl: gifData,
                          width: effectiveMediaWidth,
                          height: effectiveMediaHeight,
                          fit: BoxFit.cover,
                          maxWidthDiskCache: (effectiveMediaWidth * 2).toInt(),
                          maxHeightDiskCache: (effectiveMediaHeight * 2)
                              .toInt(),
                          fadeInDuration: Duration.zero,
                          fadeOutDuration: Duration.zero,
                          placeholder: (context, url) => Container(
                            width: effectiveMediaWidth,
                            height: effectiveMediaHeight,
                            color: Colors.white.withValues(alpha: 0.06),
                          ),
                          errorWidget: (context, url, error) => Container(
                            width: effectiveMediaWidth,
                            height: effectiveMediaHeight,
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withValues(alpha: 0.4),
                            child: Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.broken_image_outlined,
                                    color: Colors.grey[400],
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'GIF unavailable',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[300],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      : Image.file(
                          File(gifData),
                          width: effectiveMediaWidth,
                          height: effectiveMediaHeight,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(
                                width: effectiveMediaWidth,
                                height: effectiveMediaHeight,
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest
                                    .withValues(alpha: 0.4),
                                child: Center(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.broken_image_outlined,
                                        color: Colors.grey[400],
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'GIF unavailable',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[300],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                        ),
                ),
              )
            : Container(
                width: effectiveMediaWidth,
                height: effectiveMediaHeight,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: effectiveRadius,
                ),
                child: const Center(child: Text('GIF not available')),
              );
        break;

      case 'document':
        content = DocumentMessageWidget(
          key: ValueKey(
            'doc_${widget.messageId ?? widget.fileMessageData ?? widget.message}',
          ),
          fileName: widget.message.isNotEmpty ? widget.message : 'Document',
          fileUrl: widget.fileMessageData,
          isMe: widget.isMe,
          isSending: widget.isSending,
        );
        break;

      case 'location':
      case 'live_location':
        content = LocationMessageWidget(
          key: ValueKey('loc_${widget.messageId ?? widget.fileMessageData}'),
          messageType: widget.messageType,
          locationData: widget.fileMessageData,
          isMe: widget.isMe,
          messageId: widget.messageId,
          currentUserId: widget.currentUserId,
          receiverId: widget.receiverId,
          senderName: widget.senderName,
          senderProfilePic: widget.senderProfilePic,
        );
        break;

      case 'wish':
        content = Text(
          widget.message,
          style: TextStyle(
            fontSize: isSmallScreen ? 14 : 16,
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          maxLines: widget.isPreviewable ? null : 2,
          overflow: widget.isPreviewable ? null : TextOverflow.ellipsis,
        );
        break;

      default:
        content = Text(
          'Unsupported message type',
          style: TextStyle(
            fontSize: isSmallScreen ? 14 : 16,
            color: Theme.of(context).colorScheme.error,
          ),
        );
    }

    return widget.isPreviewable &&
            (widget.messageType == 'image' ||
                widget.messageType == 'video' ||
                widget.messageType == 'gif') &&
            widget.fileMessageData != null &&
            widget.fileMessageData!.isNotEmpty
        ? GestureDetector(onTap: () => _openPreview(context), child: content)
        : content;
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

// Helper widget for cached images with automatic network fallback and zero flicker
class _CachedImageWidget extends StatefulWidget {
  final String imageUrl;
  final double screenWidth;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Alignment alignment;

  const _CachedImageWidget({
    super.key,
    required this.imageUrl,
    required this.screenWidth,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.topCenter,
  });

  @override
  State<_CachedImageWidget> createState() => _CachedImageWidgetState();
}

class _CachedImageWidgetState extends State<_CachedImageWidget> {
  String? _localPath;

  @override
  void initState() {
    super.initState();
    _checkLocalSync();
  }

  @override
  void didUpdateWidget(covariant _CachedImageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _checkLocalSync();
    }
  }

  void _checkLocalSync() {
    final url = widget.imageUrl;
    if (url.isEmpty) return;

    // 1. Direct local file path or file:// URI
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      final clean = url.startsWith('file://') ? url.substring(7) : url;
      final f = File(clean);
      if (f.existsSync() && f.lengthSync() > 0) {
        _localPath = clean;
        return;
      }
    }

    // 2. Synchronous cache check (e.g. optimistic mapping from freshly uploaded file)
    final fastSync = MediaCacheService().getCachedSync(url);
    if (fastSync != null) {
      final f = File(fastSync);
      if (f.existsSync() && f.lengthSync() > 0) {
        _localPath = fastSync;
        return;
      }
    }
  }

  Widget _buildRetryWidget(BuildContext context) {
    return Container(
      width: widget.width,
      height: widget.height,
      constraints: widget.width == null
          ? BoxConstraints(maxWidth: widget.screenWidth * 0.8, minHeight: 90)
          : null,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: InkWell(
        onTap: () {
          _checkLocalSync();
          setState(() {});
        },
        borderRadius: BorderRadius.circular(8),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.refresh_rounded,
                size: 24,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 6),
              Text(
                'Tap to retry image',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNetworkImage(BuildContext context) {
    if (widget.imageUrl.startsWith('http://') ||
        widget.imageUrl.startsWith('https://')) {
      return CachedNetworkImage(
        imageUrl: widget.imageUrl,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        alignment: widget.alignment,
        maxWidthDiskCache: widget.width != null
            ? (widget.width! * 2).toInt()
            : (widget.screenWidth * 0.8).toInt(),
        maxHeightDiskCache: widget.height != null
            ? (widget.height! * 2).toInt()
            : null,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        placeholder: (context, url) => Container(
          width: widget.width,
          height: widget.height ?? 240,
          constraints: widget.width == null
              ? BoxConstraints(
                  maxWidth: widget.screenWidth * 0.8,
                  minHeight: 120,
                )
              : null,
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
          child: const Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
        errorWidget: (context, url, error) => _buildRetryWidget(context),
      );
    }
    return _buildRetryWidget(context);
  }

  @override
  Widget build(BuildContext context) {
    if (_localPath != null) {
      final localFile = File(_localPath!);
      if (localFile.existsSync() && localFile.lengthSync() > 0) {
        return Image.file(
          localFile,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          alignment: widget.alignment,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) {
            return _buildNetworkImage(context);
          },
        );
      }
    }

    return _buildNetworkImage(context);
  }
}
