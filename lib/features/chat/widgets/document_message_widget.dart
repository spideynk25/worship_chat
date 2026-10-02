import 'dart:developer';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/utils/media_cache_service.dart';
import 'package:worship_chat/common/utils/utils.dart';

class DocumentMessageWidget extends StatefulWidget {
  final String fileName;
  final String? fileUrl;
  final bool isMe;
  final bool isSending;

  const DocumentMessageWidget({
    super.key,
    required this.fileName,
    required this.fileUrl,
    required this.isMe,
    this.isSending = false,
  });

  @override
  State<DocumentMessageWidget> createState() => _DocumentMessageWidgetState();
}

class _DocumentMessageWidgetState extends State<DocumentMessageWidget> {
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String? _localPath;
  int? _fileSizeBytes;

  @override
  void initState() {
    super.initState();
    _checkLocalFileSync();
    _checkLocalFile();
  }

  @override
  void didUpdateWidget(covariant DocumentMessageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fileUrl != widget.fileUrl) {
      _checkLocalFileSync();
      _checkLocalFile();
    }
  }

  void _checkLocalFileSync() {
    final url = widget.fileUrl;
    if (url == null || url.isEmpty) return;

    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      final f = File(url);
      if (f.existsSync()) {
        _localPath = url;
        _fileSizeBytes = f.lengthSync();
        return;
      }
    }

    final cached = MediaCacheService().getCachedSync(url);
    if (cached != null) {
      final f = File(cached);
      if (f.existsSync()) {
        _localPath = cached;
        _fileSizeBytes = f.lengthSync();
        return;
      }
    }
  }

  Future<void> _checkLocalFile() async {
    final url = widget.fileUrl;
    if (url == null || url.isEmpty) return;

    // Check if it's already a local file path
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      final f = File(url);
      if (await f.exists()) {
        final length = await f.length();
        if (mounted) {
          setState(() {
            _localPath = url;
            _fileSizeBytes = length;
          });
        }
        return;
      }
    }

    // Check MediaCacheService
    final cached = MediaCacheService().getCachedSync(url);
    if (cached != null) {
      final f = File(cached);
      if (await f.exists()) {
        final length = await f.length();
        if (mounted) {
          setState(() {
            _localPath = cached;
            _fileSizeBytes = length;
          });
        }
        return;
      }
    }

    final resolved = await MediaCacheService().getMediaPath(url);
    if (resolved != null && mounted) {
      final f = File(resolved);
      if (await f.exists()) {
        final length = await f.length();
        setState(() {
          _localPath = resolved;
          _fileSizeBytes = length;
        });
      }
    }
  }

  String _getFileExtension() {
    final name = widget.fileName;
    if (name.contains('.')) {
      return name.split('.').last.toUpperCase();
    }
    final url = widget.fileUrl ?? '';
    if (url.contains('.')) {
      return url.split('.').last.split('?').first.toUpperCase();
    }
    return 'FILE';
  }

  Color _getExtensionColor(String ext) {
    switch (ext.toLowerCase()) {
      case 'pdf':
        return const Color(0xFFE53935);
      case 'mp3':
      case 'wav':
      case 'm4a':
      case 'aac':
      case 'ogg':
        return const Color(0xFFFFB300);
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
        return const Color(0xFF8E24AA);
      case 'apk':
        return const Color(0xFF43A047);
      case 'doc':
      case 'docx':
        return const Color(0xFF1E88E5);
      case 'xls':
      case 'xlsx':
        return const Color(0xFF2E7D32);
      case 'ppt':
      case 'pptx':
        return const Color(0xFFFB8C00);
      case 'txt':
        return const Color(0xFF78909C);
      default:
        return const Color(0xFF5C6BC0);
    }
  }

  IconData _getExtensionIcon(String ext) {
    switch (ext.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'mp3':
      case 'wav':
      case 'm4a':
      case 'aac':
      case 'ogg':
        return Icons.audio_file_rounded;
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
        return Icons.folder_zip_rounded;
      case 'apk':
        return Icons.android_rounded;
      case 'doc':
      case 'docx':
        return Icons.description_rounded;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _handleTap() async {
    HapticFeedback.lightImpact();

    // 1. If already on disk, open directly
    if (_localPath != null && await File(_localPath!).exists()) {
      try {
        final result = await OpenFilex.open(_localPath!);
        log('OpenFilex result: ${result.message} (${result.type})');
        if (result.type != ResultType.done && mounted) {
          AppSnackBar.error(context, 'Could not open file: ${result.message}');
        }
      } catch (e) {
        log('Error opening file: $e');
      }
      return;
    }

    final url = widget.fileUrl;
    if (url == null || url.isEmpty) {
      AppSnackBar.warning(context, 'File is still uploading or unavailable');
      return;
    }

    // 2. Download from remote URL
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
    });

    try {
      final ext = _getFileExtension().toLowerCase();
      final dir = await getApplicationDocumentsDirectory();
      final cleanName = widget.fileName.replaceAll(RegExp(r'[^\w\.\-]'), '_');
      final targetPath = '${dir.path}/$cleanName';

      final dio = Dio();
      await dio.download(
        url,
        targetPath,
        onReceiveProgress: (received, total) {
          if (total > 0 && mounted) {
            setState(() {
              _downloadProgress = received / total;
            });
          }
        },
      );

      final downloaded = File(targetPath);
      if (await downloaded.exists()) {
        final size = await downloaded.length();
        MediaCacheService().registerLocalMapping(url, targetPath);
        if (mounted) {
          setState(() {
            _localPath = targetPath;
            _fileSizeBytes = size;
            _isDownloading = false;
          });
        }

        final result = await OpenFilex.open(targetPath);
        log('Downloaded and opened file: ${result.message}');
      }
    } catch (e) {
      log('Error downloading document: $e');
      if (mounted) {
        setState(() => _isDownloading = false);
        AppSnackBar.error(context, 'Failed to download file: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ext = _getFileExtension();
    final badgeColor = _getExtensionColor(ext);
    final iconData = _getExtensionIcon(ext);
    final isDownloaded = _localPath != null;

    final displayName = widget.fileName.trim().isNotEmpty
        ? widget.fileName.trim()
        : 'Document.$ext';

    return InkWell(
      onTap: widget.isSending ? null : _handleTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        constraints: const BoxConstraints(minWidth: 220, maxWidth: 280),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.1),
            width: 0.8,
          ),
        ),
        child: Row(
          children: [
            // Left: File icon with extension badge
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 44,
                  height: 48,
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: badgeColor.withValues(alpha: 0.5),
                      width: 1,
                    ),
                  ),
                  child: Center(
                    child: Icon(iconData, color: badgeColor, size: 24),
                  ),
                ),
                Positioned(
                  bottom: -3,
                  right: -3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: badgeColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      ext.length > 4 ? ext.substring(0, 4) : ext,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),

            // Center: File Name & Size
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (_fileSizeBytes != null) ...[
                        Text(
                          _formatFileSize(_fileSizeBytes!),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '•',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4),
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        ext,
                        style: TextStyle(
                          color: badgeColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Right: Download / Open state action button
            if (widget.isSending)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white70,
                ),
              )
            else if (_isDownloading)
              SizedBox(
                width: 28,
                height: 28,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: _downloadProgress > 0 ? _downloadProgress : null,
                      strokeWidth: 2.5,
                      color: tabColor,
                    ),
                    const Icon(Icons.downloading_rounded, size: 14, color: Colors.white),
                  ],
                ),
              )
            else if (isDownloaded)
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.open_in_new_rounded,
                  size: 16,
                  color: Colors.white,
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                  border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
                ),
                child: Icon(
                  Icons.arrow_downward_rounded,
                  size: 16,
                  color: badgeColor,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
