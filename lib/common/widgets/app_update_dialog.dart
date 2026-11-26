import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/utils/app_update_service.dart';

enum _UpdateDialogPhase {
  prompt,
  downloading,
  readyToInstall,
  error,
}

/// Royal-themed in-app update dialog handling release notes, progress download,
/// permission prompts, and APK installation.
class AppUpdateDialog extends StatefulWidget {
  final AppUpdateService service;
  final InstalledAppVersion installed;
  final AppUpdateInfo updateInfo;

  const AppUpdateDialog({
    super.key,
    required this.service,
    required this.installed,
    required this.updateInfo,
  });

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  _UpdateDialogPhase _phase = _UpdateDialogPhase.prompt;
  double _progress = 0.0;
  int _receivedBytes = 0;
  int _totalBytes = 0;
  CancelToken? _cancelToken;
  File? _downloadedApk;
  String? _statusMessage;

  bool get _isForced =>
      widget.updateInfo.isForcedFor(widget.installed.versionCode);

  @override
  void dispose() {
    _cancelToken?.cancel('dialog_disposed');
    super.dispose();
  }

  String _formatMb(int bytes) {
    if (bytes <= 0) return '0.0 MB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _startDownloadAndInstall() async {
    _cancelToken?.cancel('restarted');
    final token = CancelToken();

    setState(() {
      _cancelToken = token;
      _phase = _UpdateDialogPhase.downloading;
      _progress = 0.0;
      _receivedBytes = 0;
      _totalBytes = 0;
      _statusMessage = null;
    });

    try {
      final apk = await widget.service.downloadApk(
        widget.updateInfo,
        cancelToken: token,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _receivedBytes = received;
            _totalBytes = total;
            _progress = total > 0 ? (received / total).clamp(0.0, 1.0) : 0.0;
          });
        },
      );

      if (!mounted) return;
      _downloadedApk = apk;

      setState(() {
        _phase = _UpdateDialogPhase.readyToInstall;
        _statusMessage = 'Launching Android installer...';
      });

      await _triggerInstall();
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        if (mounted) {
          setState(() {
            _phase = _UpdateDialogPhase.prompt;
            _statusMessage = null;
          });
        }
        return;
      }
      if (mounted) {
        setState(() {
          _phase = _UpdateDialogPhase.error;
          _statusMessage = e.message ?? 'Download failed. Please try again.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _phase = _UpdateDialogPhase.error;
          _statusMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _triggerInstall() async {
    final apk = _downloadedApk;
    if (apk == null) return;

    final res = await widget.service.installApk(apk);
    if (!mounted) return;

    if (res.launched) {
      if (!_isForced) {
        Navigator.of(context).pop();
      } else {
        setState(() {
          _statusMessage =
              'Follow the Android installer prompt to finish updating.';
        });
      }
    } else {
      setState(() {
        _phase = _UpdateDialogPhase.readyToInstall;
        _statusMessage = res.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isForced && _phase != _UpdateDialogPhase.downloading,
      child: AlertDialog(
        backgroundColor: const Color(0xFF161426),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: tabColor.withValues(alpha: 0.35),
            width: 1.2,
          ),
        ),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [tabColor, accentOrange],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.system_update_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isForced ? 'Required Update' : 'Update Available',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'v${widget.installed.versionName}  →  v${widget.updateInfo.latestVersionName} (Build ${widget.updateInfo.latestVersionCode})',
                    style: TextStyle(
                      color: const Color(0xFFFFD700).withValues(alpha: 0.9),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: _buildBody(),
        actions: _buildActions(),
      ),
    );
  }

  Widget _buildBody() {
    switch (_phase) {
      case _UpdateDialogPhase.prompt:
        final notes = widget.updateInfo.releaseNotes;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isForced
                  ? 'A new version of Worship Chat is required to continue.'
                  : 'A newer version of Worship Chat is ready to install.',
              style: const TextStyle(color: Colors.white70, fontSize: 13.5),
            ),
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 160),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    notes,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ],
          ],
        );

      case _UpdateDialogPhase.downloading:
        final pct = (_progress * 100).toStringAsFixed(0);
        final sizeText = _totalBytes > 0
            ? '${_formatMb(_receivedBytes)} / ${_formatMb(_totalBytes)}'
            : _formatMb(_receivedBytes);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Downloading update APK...',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                Text(
                  _totalBytes > 0 ? '$pct%' : '...',
                  style: const TextStyle(
                    color: tabColor,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: _totalBytes > 0 ? _progress : null,
                minHeight: 7,
                backgroundColor: Colors.white12,
                color: tabColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              sizeText,
              style: const TextStyle(color: Colors.white54, fontSize: 11.5),
            ),
          ],
        );

      case _UpdateDialogPhase.readyToInstall:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'APK Downloaded & Verified',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            if (_statusMessage != null && _statusMessage!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _statusMessage!,
                style: const TextStyle(color: Colors.white70, fontSize: 12.5),
              ),
            ],
          ],
        );

      case _UpdateDialogPhase.error:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 18),
                SizedBox(width: 8),
                Text(
                  'Update Download Failed',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _statusMessage ?? 'Unable to download the APK.',
              style: const TextStyle(color: Colors.white70, fontSize: 12.5),
            ),
          ],
        );
    }
  }

  List<Widget> _buildActions() {
    switch (_phase) {
      case _UpdateDialogPhase.prompt:
        return [
          if (!_isForced)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Later',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: tabColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: _startDownloadAndInstall,
            child: const Text(
              'Update Now',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ];

      case _UpdateDialogPhase.downloading:
        if (_isForced) return const [];
        return [
          TextButton(
            onPressed: () => _cancelToken?.cancel('user_cancelled'),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ];

      case _UpdateDialogPhase.readyToInstall:
        return [
          if (!_isForced)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Later',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: tabColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: _triggerInstall,
            child: const Text(
              'Install Now',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ];

      case _UpdateDialogPhase.error:
        return [
          if (!_isForced)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Close',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: tabColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: _startDownloadAndInstall,
            child: const Text(
              'Retry',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ];
    }
  }
}
