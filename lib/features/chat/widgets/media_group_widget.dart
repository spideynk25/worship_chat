import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/utils/media_cache_service.dart';
import 'package:worship_chat/common/utils/utils.dart';
import 'package:worship_chat/features/chat/widgets/display_messages.dart';

/// Extract the media URL from fileMessageData (plain URL or JSON wrapper).
String extractMediaUrl(String? fileMessageData) {
  if (fileMessageData == null || fileMessageData.isEmpty) return '';
  try {
    final map = jsonDecode(fileMessageData);
    if (map is Map && map.containsKey('url')) return map['url']?.toString() ?? '';
  } catch (_) {}
  return fileMessageData;
}

/// Extract the groupId from fileMessageData JSON.
String? extractGroupId(String? fileMessageData) {
  if (fileMessageData == null || fileMessageData.isEmpty) return null;
  try {
    final map = jsonDecode(fileMessageData);
    if (map is Map && map.containsKey('groupId')) return map['groupId']?.toString();
  } catch (_) {}
  return null;
}

/// Represents one media item in a group.
class MediaGroupItem {
  final String url;
  final String type;
  const MediaGroupItem({required this.url, required this.type});
}

/// WhatsApp-style Grid Collage of grouped media messages.
class MediaGroupWidget extends StatelessWidget {
  final List<MediaGroupItem> items;
  final double maxWidth;
  final bool isMe;
  final String date;
  final Widget statusWidget;
  final String? caption;

  const MediaGroupWidget({
    super.key,
    required this.items,
    required this.maxWidth,
    required this.isMe,
    required this.date,
    required this.statusWidget,
    this.caption,
  });

  void _openFullscreen(BuildContext context, int initialIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _GroupMediaViewer(
          items: items,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  Widget _buildTile(
    BuildContext context,
    int index, {
    String? overlayText,
  }) {
    if (index >= items.length) return const SizedBox.shrink();
    final item = items[index];

    return GestureDetector(
      key: ValueKey('tile_${item.url}_$index'),
      onTap: () => _openFullscreen(context, index),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _MediaThumb(
            key: ValueKey('thumb_${item.url}_$index'),
            url: item.url,
            type: item.type,
          ),
          if (overlayText != null)
            Container(
              color: Colors.black.withValues(alpha: 0.6),
              alignment: Alignment.center,
              child: Text(
                overlayText,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGrid(BuildContext context, double width, double height) {
    const double gap = 2.0;
    final count = items.length;

    if (count == 1) {
      return SizedBox(
        width: width,
        height: width * 0.76,
        child: _buildTile(context, 0),
      );
    }

    if (count == 2) {
      return SizedBox(
        width: width,
        height: width * 0.72,
        child: Row(
          children: [
            Expanded(child: _buildTile(context, 0)),
            const SizedBox(width: gap),
            Expanded(child: _buildTile(context, 1)),
          ],
        ),
      );
    }

    if (count == 3) {
      // WhatsApp 3-item collage: 1 large left, 2 stacked right
      return SizedBox(
        width: width,
        height: height,
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: _buildTile(context, 0),
            ),
            const SizedBox(width: gap),
            Expanded(
              flex: 2,
              child: Column(
                children: [
                  Expanded(child: _buildTile(context, 1)),
                  const SizedBox(height: gap),
                  Expanded(child: _buildTile(context, 2)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (count == 4) {
      // WhatsApp 4-item 2x2 grid
      return SizedBox(
        width: width,
        height: height,
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _buildTile(context, 0)),
                  const SizedBox(width: gap),
                  Expanded(child: _buildTile(context, 1)),
                ],
              ),
            ),
            const SizedBox(height: gap),
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _buildTile(context, 2)),
                  const SizedBox(width: gap),
                  Expanded(child: _buildTile(context, 3)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // 5+ items: 2x2 grid where 4th tile shows +N count
    return SizedBox(
      width: width,
      height: height,
      child: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(child: _buildTile(context, 0)),
                const SizedBox(width: gap),
                Expanded(child: _buildTile(context, 1)),
              ],
            ),
          ),
          const SizedBox(height: gap),
          Expanded(
            child: Row(
              children: [
                Expanded(child: _buildTile(context, 2)),
                const SizedBox(width: gap),
                Expanded(
                  child: _buildTile(
                    context,
                    3,
                    overlayText: '+${count - 3}',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = maxWidth.clamp(210.0, 275.0);
    final height = width * 0.88;
    final hasCaption = caption != null && caption!.trim().isNotEmpty;

    final grid = _buildGrid(context, width, height);

    final timestampPill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.15),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            date,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 4),
          statusWidget,
        ],
      ),
    );

    if (!hasCaption) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: width,
          child: Stack(
            children: [
              grid,
              Positioned(
                bottom: 6,
                right: 6,
                child: timestampPill,
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: isMe ? const Color(0xFF24223A) : const Color(0xFF1B192A),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            child: grid,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    caption!.trim(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14.5,
                      height: 1.25,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      date,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(width: 4),
                    statusWidget,
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MediaThumb extends StatefulWidget {
  final String url;
  final String type;
  const _MediaThumb({super.key, required this.url, required this.type});

  @override
  State<_MediaThumb> createState() => _MediaThumbState();
}

class _MediaThumbState extends State<_MediaThumb> {
  String? _localPath;

  @override
  void initState() {
    super.initState();
    _checkLocalSync();
  }

  @override
  void didUpdateWidget(covariant _MediaThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _checkLocalSync();
    }
  }

  void _checkLocalSync() {
    final url = widget.url;
    if (url.isEmpty) return;

    // Check plain local path or file://
    if (url.startsWith('/') ||
        url.startsWith('file://') ||
        (!url.startsWith('http://') && !url.startsWith('https://'))) {
      final clean = url.startsWith('file://') ? url.substring(7) : url;
      final f = File(clean);
      if (f.existsSync() && f.lengthSync() > 0) {
        _localPath = clean;
        return;
      }
    }

    // Check MediaCacheService sync cache (mapped local files or cached downloads)
    final syncCached = MediaCacheService().getCachedSync(url);
    if (syncCached != null &&
        File(syncCached).existsSync() &&
        File(syncCached).lengthSync() > 0) {
      _localPath = syncCached;
      return;
    }

    // If it's a video and we don't have local cache yet, resolve in background
    if (widget.type == 'video') {
      _resolveVideoAsync();
    }
  }

  Future<void> _resolveVideoAsync() async {
    try {
      final path = await MediaCacheService().getMediaPath(widget.url);
      if (path != null && mounted && File(path).existsSync()) {
        setState(() => _localPath = path);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (widget.type == 'video') {
      return Container(
        color: const Color(0xFF1A1A2E),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (_localPath != null)
              Image.file(
                File(_localPath!),
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => _errWidget(),
              )
            else
              const Icon(Icons.movie_outlined, color: Colors.white12, size: 48),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
            ),
          ],
        ),
      );
    }

    if (_localPath != null) {
      return Image.file(
        File(_localPath!),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _errWidget(),
      );
    }

    return CachedNetworkImage(
      imageUrl: widget.url,
      fit: BoxFit.cover,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      placeholder: (_, __) => Container(color: const Color(0xFF1A1A2E)),
      errorWidget: (_, __, ___) => _errWidget(),
    );
  }

  Widget _errWidget() => Container(
    color: const Color(0xFF1A1A2E),
    child: const Icon(Icons.broken_image_outlined, color: Colors.white38, size: 36),
  );
}

class _GroupMediaViewer extends StatefulWidget {
  final List<MediaGroupItem> items;
  final int initialIndex;
  const _GroupMediaViewer({required this.items, required this.initialIndex});

  @override
  State<_GroupMediaViewer> createState() => _GroupMediaViewerState();
}

class _GroupMediaViewerState extends State<_GroupMediaViewer> {
  late int _current;
  late PageController _controller;
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _downloadCurrent() async {
    final item = widget.items[_current];
    setState(() => _isDownloading = true);
    try {
      final localPath = await MediaCacheService().getMediaPath(item.url);
      if (localPath == null) {
        if (mounted) AppSnackBar.error(context, 'Media file not ready for download');
        return;
      }

      Directory? directory;
      String displayPath = 'Downloads/WorshipChat';

      if (Platform.isAndroid) {
        directory = Directory('/storage/emulated/0/Download/WorshipChat');
      } else {
        directory = await getApplicationDocumentsDirectory();
        displayPath = directory.path;
      }

      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final ext = item.type == 'video' ? 'mp4' : 'jpg';
      final savePath = '${directory.path}/WorshipChat_$timestamp.$ext';
      await File(localPath).copy(savePath);

      if (mounted) {
        AppSnackBar.success(context, 'Saved to $displayPath');
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.error(context, 'Failed to save: $e');
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.items.length;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Close',
        ),
        title: Text(
          '${_current + 1} / $count',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        actions: [
          if (_isDownloading)
            const Padding(
              padding: EdgeInsets.all(14.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.download_rounded, color: Colors.white),
              tooltip: 'Save to Gallery',
              onPressed: _downloadCurrent,
            ),
        ],
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: count,
        onPageChanged: (page) => setState(() => _current = page),
        itemBuilder: (context, index) {
          final item = widget.items[index];
          return MediaPreviewWidget(
            mediaType: item.type,
            mediaUrl: item.url,
            showAppBar: false, // Prevents duplicate AppBar & second close button!
          );
        },
      ),
    );
  }
}