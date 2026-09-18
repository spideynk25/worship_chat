import 'dart:convert';
import 'dart:io';
import 'package:any_link_preview/any_link_preview.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:worship_chat/common/utils/gif_viewer.dart';
import 'package:worship_chat/common/utils/media_cache_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_view/photo_view.dart';
import 'dart:developer';

// Enhanced MediaPreviewWidget with download and fullscreen
class MediaPreviewWidget extends StatefulWidget {
  final String mediaType;
  final String mediaUrl;

  const MediaPreviewWidget({
    super.key,
    required this.mediaType,
    required this.mediaUrl,
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
      final localPath = await MediaCacheService().getMediaPath(widget.mediaUrl);

      if (localPath == null) {
        setState(() {
          _errorMessage = 'Failed to load media';
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _localMediaPath = localPath;
        _isLoading = false;
      });

      if (widget.mediaType == 'video') {
        _videoController = VideoPlayerController.file(File(localPath))
          ..initialize()
              .then((_) {
                if (mounted) {
                  setState(() {
                    _isVideoInitialized = true;
                    _isMuted = false;
                    _videoController!.setVolume(1.0);
                    _videoController!.play();
                  });
                  Future.delayed(const Duration(seconds: 3), () {
                    if (mounted) setState(() => _showControls = false);
                  });
                }
              })
              .catchError((error) {
                if (mounted) {
                  setState(() {
                    _errorMessage = 'Failed to load video: $error';
                  });
                  log('Video error: $error');
                }
              });
      }
    } catch (e) {
      log('Error loading media: $e');
      setState(() {
        _errorMessage = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _exitFullscreen();
    super.dispose();
  }

  Future<void> _downloadMedia() async {
    if (_localMediaPath == null) return;

    setState(() => _isDownloading = true);

    try {
      // Request storage permission for Android
      if (Platform.isAndroid) {
        var status = await Permission.storage.request();

        // For Android 11+ (API 30+), try photos permission
        if (!status.isGranted) {
          if (widget.mediaType == 'image') {
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
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Storage permission denied')),
            );
          }
          setState(() => _isDownloading = false);
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
      final extension = widget.mediaType == 'video' ? 'mp4' : 'jpg';
      final fileName = 'WorshipChat_$timestamp.$extension';
      final filePath = '${directory.path}/$fileName';

      // Copy file to destination
      final sourceFile = File(_localMediaPath!);
      await sourceFile.copy(filePath);

      log('Media saved to: $filePath');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved to $displayPath'),
            duration: const Duration(seconds: 3),
            action: SnackBarAction(label: 'OK', onPressed: () {}),
          ),
        );
      }
    } catch (e) {
      log('Download error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      setState(() => _isDownloading = false);
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
    if (_videoController != null) {
      setState(() {
        if (_videoController!.value.isPlaying) {
          _videoController!.pause();
        } else {
          _videoController!.play();
        }
        _showControls = true;
      });
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
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
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
      appBar: _isFullscreen
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
                else
                  IconButton(
                    icon: const Icon(Icons.download, color: Colors.white),
                    onPressed: _downloadMedia,
                    tooltip: 'Download',
                  ),
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
            : widget.mediaType == 'image' && _localMediaPath != null
            ? PhotoView(
                imageProvider: FileImage(File(_localMediaPath!)),
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 3,
                initialScale: PhotoViewComputedScale.contained,
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
                        child: VideoPlayer(_videoController!),
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
                                Colors.black.withOpacity(0.8),
                                Colors.transparent,
                              ],
                            ),
                          ),
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
                                    overlayShape: const RoundSliderOverlayShape(
                                      overlayRadius: 12,
                                    ),
                                    activeTrackColor: Colors.pink,
                                    inactiveTrackColor: Colors.white30,
                                    thumbColor: Colors.white,
                                    overlayColor: Colors.pink.withOpacity(0.2),
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
  final bool showLinkPreview; // NEW: Option to show link previews

  const DisplayMessages({
    super.key,
    required this.message,
    required this.messageType,
    this.fileMessageData,
    this.isPreviewable = true,
    this.useCachedMedia = true,
    this.showLinkPreview = true, // Default to true
  });

  @override
  State<DisplayMessages> createState() => _DisplayMessagesState();
}

class _DisplayMessagesState extends State<DisplayMessages> {
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

    // Extract URLs from message for link preview
    if (widget.messageType == 'text' && widget.showLinkPreview) {
      _extractedUrls = _extractUrls(widget.message);
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
    setState(() => _isLoadingMedia = true);

    try {
      final localPath = await MediaCacheService().getMediaPath(
        widget.fileMessageData!,
      );

      if (localPath == null) {
        setState(() {
          _errorMessage = 'Failed to load video';
          _isLoadingMedia = false;
        });
        return;
      }

      setState(() => _localMediaPath = localPath);

      _videoController = VideoPlayerController.file(File(localPath))
        ..initialize()
            .then((_) {
              if (mounted) {
                setState(() {
                  _isVideoInitialized = true;
                  _isLoadingMedia = false;
                  _isMuted = true;
                  _videoController!.setVolume(0.0);
                  _videoController!.play();
                  _videoController!.setLooping(true);
                });
                Future.delayed(const Duration(seconds: 3), () {
                  if (mounted) setState(() => _showControls = false);
                });
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
    } catch (e) {
      log('Error loading cached video: $e');
      setState(() {
        _errorMessage = 'Error: $e';
        _isLoadingMedia = false;
      });
    }
  }

  void _initializeNetworkVideo() {
    if (Uri.tryParse(widget.fileMessageData!)?.isAbsolute ?? false) {
      _videoController = VideoPlayerController.network(widget.fileMessageData!)
        ..initialize()
            .then((_) {
              if (mounted) {
                setState(() {
                  _isVideoInitialized = true;
                  _isMuted = true;
                  _videoController!.setVolume(0.0);
                  _videoController!.play();
                  _videoController!.setLooping(true);
                });
                Future.delayed(const Duration(seconds: 3), () {
                  if (mounted) setState(() => _showControls = false);
                });
              }
            })
            .catchError((error) {
              if (mounted) {
                setState(() {
                  _errorMessage = 'Failed to load video: $error';
                });
                log('Video error: $error');
              }
            });
    } else {
      setState(() {
        _errorMessage = 'Invalid video URL';
      });
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  void _openPreview(BuildContext context) {
    if (!widget.isPreviewable ||
        widget.fileMessageData == null ||
        widget.fileMessageData!.isEmpty) {
      return;
    }
    if (widget.messageType != 'image' && widget.messageType != 'video') {
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
    ).then((_) {
      if (_videoController != null && _isVideoInitialized) {
        _videoController!.play();
      }
    });
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
    if (_videoController != null) {
      setState(() {
        if (_videoController!.value.isPlaying) {
          _videoController!.pause();
        } else {
          _videoController!.play();
        }
        _showControls = true;
      });
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Cannot open this link: $cleanUrl'),
              duration: const Duration(seconds: 3),
            ),
          );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open link: $cleanUrl'),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () => _launchURL(url),
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      log('Error launching URL: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open link: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Widget _buildTextWithLinks(
    String text,
    BuildContext context,
    bool isSmallScreen,
  ) {
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
          color: Theme.of(context).colorScheme.onSurface,
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
              color: Theme.of(context).colorScheme.onSurface,
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
            color: Colors.blue,
            decoration: TextDecoration.underline,
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
            color: Theme.of(context).colorScheme.onSurface,
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
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Storage permission denied')),
            );
          }
          setState(() => _isDownloading = false);
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved to $displayPath'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      log('Download error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Download failed: $e')));
      }
    } finally {
      setState(() => _isDownloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 600;

    Widget content;
    switch (widget.messageType) {
      case 'text':
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTextWithLinks(widget.message, context, isSmallScreen),
            // Add link previews if URLs are found
            if (widget.showLinkPreview && _extractedUrls.isNotEmpty)
              ..._extractedUrls
                  .map(
                    (url) => Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: AnyLinkPreview(
                        link: url,
                        displayDirection: UIDirection.uiDirectionVertical,
                        showMultimedia: true,
                        bodyMaxLines: 3,
                        bodyTextOverflow: TextOverflow.ellipsis,
                        titleStyle: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.bold,
                          fontSize: isSmallScreen ? 14 : 16,
                        ),
                        bodyStyle: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: isSmallScreen ? 12 : 14,
                        ),
                        errorBody: 'Failed to load preview',
                        errorTitle: 'Error',
                        errorWidget: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceVariant,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Theme.of(
                                context,
                              ).colorScheme.outline.withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.link,
                                color: Theme.of(context).colorScheme.primary,
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  url,
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    decoration: TextDecoration.underline,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        errorImage:
                            'https://via.placeholder.com/400x200?text=No+Preview',
                        cache: const Duration(hours: 1),
                        backgroundColor: Theme.of(context).colorScheme.surface,
                        borderRadius: 8,
                        removeElevation: false,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                        onTap: () => _launchURL(url),
                        placeholderWidget: Container(
                          height: 150,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceVariant,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Center(
                            child: CircularProgressIndicator(),
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
          ],
        );
        break;

      case 'image':
        content =
            widget.fileMessageData != null && widget.fileMessageData!.isNotEmpty
            ? widget.useCachedMedia
                  ? _CachedImageWidget(
                      imageUrl: widget.fileMessageData!,
                      screenWidth: screenWidth,
                    )
                  : CachedNetworkImage(
                      imageUrl: widget.fileMessageData!,
                      fit: BoxFit.contain,
                      maxWidthDiskCache: (screenWidth * 0.8).toInt(),
                      placeholder: (context, url) =>
                          const Center(child: CircularProgressIndicator()),
                      errorWidget: (context, url, error) => Container(
                        constraints: BoxConstraints(
                          maxWidth: screenWidth * 0.8,
                        ),
                        color: Theme.of(context).colorScheme.surfaceVariant,
                        child: const Center(
                          child: Icon(Icons.error, color: Colors.red),
                        ),
                      ),
                    )
            : Container(
                constraints: BoxConstraints(maxWidth: screenWidth * 0.8),
                color: Theme.of(context).colorScheme.surfaceVariant,
                child: const Center(child: Text('Image not available')),
              );
        break;

      case 'video':
        content = _isLoadingMedia
            ? Container(
                constraints: BoxConstraints(maxWidth: screenWidth * 0.8),
                color: Theme.of(context).colorScheme.surfaceVariant,
                child: const Center(child: CircularProgressIndicator()),
              )
            : _errorMessage != null
            ? Container(
                constraints: BoxConstraints(maxWidth: screenWidth * 0.8),
                color: Theme.of(context).colorScheme.surfaceVariant,
                child: Center(
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              )
            : widget.fileMessageData != null &&
                  _isVideoInitialized &&
                  _videoController != null
            ? VisibilityDetector(
                key: Key(widget.fileMessageData!),
                onVisibilityChanged: (info) {
                  if (_videoController != null) {
                    if (info.visibleFraction > 0.5) {
                      _videoController!.play();
                    } else {
                      _videoController!.pause();
                    }
                  }
                },
                child: GestureDetector(
                  onTap: _toggleControls,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      AspectRatio(
                        aspectRatio: _videoController!.value.aspectRatio,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: VideoPlayer(_videoController!),
                        ),
                      ),
                      // Play/Pause button
                      Align(
                        alignment: Alignment.center,
                        child: AnimatedOpacity(
                          opacity:
                              _showControls ||
                                  !_videoController!.value.isPlaying
                              ? 0.8
                              : 0.0,
                          duration: const Duration(milliseconds: 300),
                          child: IconButton(
                            icon: Icon(
                              _videoController!.value.isPlaying
                                  ? Icons.pause_circle_filled
                                  : Icons.play_circle_filled,
                              color: Colors.white,
                              size: isSmallScreen ? 50 : 60,
                            ),
                            onPressed: _togglePlayPause,
                          ),
                        ),
                      ),
                      // Top right controls (Download & Fullscreen)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: AnimatedOpacity(
                          opacity: _showControls ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 300),
                          child: Row(
                            children: [
                              // Download button
                              if (_isDownloading)
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              else
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: IconButton(
                                    icon: const Icon(
                                      Icons.download,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                    onPressed: _downloadVideo,
                                    padding: const EdgeInsets.all(8),
                                    constraints: const BoxConstraints(),
                                  ),
                                ),
                              const SizedBox(width: 4),
                              // Fullscreen button
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: IconButton(
                                  icon: const Icon(
                                    Icons.fullscreen,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  onPressed: () => _openPreview(context),
                                  padding: const EdgeInsets.all(8),
                                  constraints: const BoxConstraints(),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Bottom controls bar
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
                                  Colors.black.withOpacity(0.7),
                                  Colors.transparent,
                                ],
                              ),
                            ),
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
                                    size: isSmallScreen ? 20 : 24,
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
                                      activeTrackColor: Colors.pink,
                                      inactiveTrackColor: Colors.white30,
                                      thumbColor: Colors.white,
                                      overlayColor: Colors.pink.withOpacity(
                                        0.2,
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
                                  padding: const EdgeInsets.only(right: 8),
                                  child: Text(
                                    '${_formatDuration(_videoController!.value.position)} / ${_formatDuration(_videoController!.value.duration)}',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: isSmallScreen ? 10 : 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : Container(
                constraints: BoxConstraints(maxWidth: screenWidth * 0.8),
                color: Theme.of(context).colorScheme.surfaceVariant,
                child: const Center(child: CircularProgressIndicator()),
              );
        break;

      case 'gif':
        log(
          'Rendering GIF with data: ${Uint8List.fromList(utf8.encode(widget.fileMessageData!))}',
        );
        content =
            widget.fileMessageData != null && widget.fileMessageData!.isNotEmpty
            ? Image.memory(
                Uint8List.fromList(utf8.encode(widget.fileMessageData!)),
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  log('GIF error: $error');
                  return Container(
                    constraints: BoxConstraints(maxWidth: screenWidth * 0.8),
                    color: Theme.of(context).colorScheme.surfaceVariant,
                    child: const Center(
                      child: Icon(Icons.error, color: Colors.red),
                    ),
                  );
                },
              )
            : Container(
                constraints: BoxConstraints(maxWidth: screenWidth * 0.8),
                color: Theme.of(context).colorScheme.surfaceVariant,
                child: const Center(child: Text('GIF not available')),
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
            (widget.messageType == 'image' || widget.messageType == 'video') &&
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

// Helper widget for cached images
class _CachedImageWidget extends StatefulWidget {
  final String imageUrl;
  final double screenWidth;

  const _CachedImageWidget({required this.imageUrl, required this.screenWidth});

  @override
  State<_CachedImageWidget> createState() => _CachedImageWidgetState();
}

class _CachedImageWidgetState extends State<_CachedImageWidget> {
  String? _localPath;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    try {
      final path = await MediaCacheService().getMediaPath(widget.imageUrl);
      if (mounted) {
        setState(() {
          _localPath = path;
          _isLoading = false;
          _hasError = path == null;
        });
      }
    } catch (e) {
      log('Error loading cached image: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        constraints: BoxConstraints(maxWidth: widget.screenWidth * 0.8),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_hasError || _localPath == null) {
      return Container(
        constraints: BoxConstraints(maxWidth: widget.screenWidth * 0.8),
        color: Theme.of(context).colorScheme.surfaceVariant,
        child: const Center(child: Icon(Icons.error, color: Colors.red)),
      );
    }

    return Image.file(
      File(_localPath!),
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          constraints: BoxConstraints(maxWidth: widget.screenWidth * 0.8),
          color: Theme.of(context).colorScheme.surfaceVariant,
          child: const Center(child: Icon(Icons.error, color: Colors.red)),
        );
      },
    );
  }
}
