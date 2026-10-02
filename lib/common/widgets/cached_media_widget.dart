import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'dart:developer';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:worship_chat/common/utils/media_cache_service.dart';

class CachedImageWidget extends StatefulWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;

  const CachedImageWidget({
    Key? key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
  }) : super(key: key);

  @override
  State<CachedImageWidget> createState() => _CachedImageWidgetState();
}

class _CachedImageWidgetState extends State<CachedImageWidget> {
  String? _localPath;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    final fastSync = MediaCacheService().getCachedSync(widget.imageUrl);
    if (fastSync != null && File(fastSync).existsSync() && File(fastSync).lengthSync() > 0) {
      _localPath = fastSync;
      _isLoading = false;
      _hasError = false;
    } else {
      _loadMedia();
    }
  }

  Future<void> _loadMedia() async {
    try {
      final path = await MediaCacheService().getMediaPath(widget.imageUrl);
      if (mounted) {
        final isValid = path != null && File(path).existsSync() && File(path).lengthSync() > 0;
        setState(() {
          _localPath = isValid ? path : null;
          _isLoading = false;
          _hasError = !isValid;
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

  Widget _buildNetworkFallback() {
    if (widget.imageUrl.startsWith('http://') ||
        widget.imageUrl.startsWith('https://')) {
      return CachedNetworkImage(
        imageUrl: widget.imageUrl,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        placeholder: (context, url) =>
            widget.placeholder ??
            Container(
              width: widget.width,
              height: widget.height,
              color: Colors.grey[900],
              child: const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        errorWidget: (context, url, error) =>
            widget.errorWidget ??
            Container(
              width: widget.width,
              height: widget.height,
              color: Colors.grey[900],
              child: const Center(
                child: Icon(Icons.broken_image_outlined, color: Colors.grey, size: 24),
              ),
            ),
      );
    }

    return widget.errorWidget ??
        Container(
          width: widget.width,
          height: widget.height,
          color: Colors.grey[900],
          child: const Center(
            child: Icon(Icons.broken_image_outlined, color: Colors.grey, size: 24),
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return widget.placeholder ??
          Container(
            width: widget.width,
            height: widget.height,
            color: Colors.grey[900],
            child: const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
    }

    if (_hasError || _localPath == null) {
      return _buildNetworkFallback();
    }

    final file = File(_localPath!);
    if (!file.existsSync() || file.lengthSync() == 0) {
      return _buildNetworkFallback();
    }

    return Image.file(
      file,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      errorBuilder: (context, error, stackTrace) => _buildNetworkFallback(),
    );
  }
}

class CachedVideoWidget extends StatefulWidget {
  final String videoUrl;
  final double? width;
  final double? height;

  const CachedVideoWidget({
    Key? key,
    required this.videoUrl,
    this.width,
    this.height,
  }) : super(key: key);

  @override
  State<CachedVideoWidget> createState() => _CachedVideoWidgetState();
}

class _CachedVideoWidgetState extends State<CachedVideoWidget> {
  VideoPlayerController? _controller;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadVideo();
  }

  Future<void> _loadVideo() async {
    try {
      final path = await MediaCacheService().getMediaPath(widget.videoUrl);
      if (path == null) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _hasError = true;
          });
        }
        return;
      }

      _controller = VideoPlayerController.file(File(path));
      await _controller!.initialize();
      
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      log('Error loading cached video: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        width: widget.width,
        height: widget.height,
        color: Colors.black26,
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_hasError || _controller == null) {
      return Container(
        width: widget.width,
        height: widget.height,
        color: Colors.black26,
        child: const Icon(Icons.error, color: Colors.white),
      );
    }

    return GestureDetector(
      onTap: () {
        setState(() {
          if (_controller!.value.isPlaying) {
            _controller!.pause();
          } else {
            _controller!.play();
          }
        });
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          AspectRatio(
            aspectRatio: _controller!.value.aspectRatio,
            child: VideoPlayer(_controller!),
          ),
          if (!_controller!.value.isPlaying)
            const Icon(
              Icons.play_circle_outline,
              size: 60,
              color: Colors.white,
            ),
        ],
      ),
    );
  }
}