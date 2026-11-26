import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/utils/home_widget_service.dart';
import 'package:worship_chat/common/utils/phone_wallpaper_service.dart';
import 'package:worship_chat/common/utils/utils.dart';
import 'package:worship_chat/features/settings/screens/home_widget_settings_screen.dart';

/// Shared bottom sheet for applying any photo as Phone Wallpaper or pinning
/// it to the Android Home Screen Photo Widget.
class WallpaperAndWidgetSheet extends StatefulWidget {
  final String photoId;
  final String? imageUrl;
  final String? localPath;
  final String title;
  final String subtitle;

  const WallpaperAndWidgetSheet({
    super.key,
    required this.photoId,
    this.imageUrl,
    this.localPath,
    this.title = '',
    this.subtitle = '',
  });

  static Future<void> show(
    BuildContext context, {
    required String photoId,
    String? imageUrl,
    String? localPath,
    String title = '',
    String subtitle = '',
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF161426),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => WallpaperAndWidgetSheet(
        photoId: photoId,
        imageUrl: imageUrl,
        localPath: localPath,
        title: title,
        subtitle: subtitle,
      ),
    );
  }

  @override
  State<WallpaperAndWidgetSheet> createState() =>
      _WallpaperAndWidgetSheetState();
}

class _WallpaperAndWidgetSheetState extends State<WallpaperAndWidgetSheet> {
  bool _cropBeforeSetting = false;
  bool _isBusy = false;
  String? _busyMessage;

  Future<void> _applyWallpaper(WallpaperTarget target) async {
    if (_isBusy) return;
    setState(() {
      _isBusy = true;
      _busyMessage = 'Applying to ${target.label}...';
    });

    final result = await PhoneWallpaperService.instance.applyWallpaper(
      context: context,
      imageUrl: widget.imageUrl,
      localPath: widget.localPath,
      target: target,
      cropFirst: _cropBeforeSetting,
    );

    if (!mounted) return;
    setState(() {
      _isBusy = false;
      _busyMessage = null;
    });

    if (result.cancelled) return;
    if (result.success) {
      Navigator.pop(context);
      AppSnackBar.success(context, result.message, title: 'Wallpaper Updated');
    } else {
      AppSnackBar.error(context, result.message);
    }
  }

  Future<void> _pinToHomeWidget() async {
    if (_isBusy) return;
    setState(() {
      _isBusy = true;
      _busyMessage = 'Preparing photo for Home Widget...';
    });

    final ok = await HomeWidgetService.instance.pinSinglePhoto(
      HomeWidgetPhotoInput(
        id: widget.photoId,
        imageUrl: widget.imageUrl,
        localPath: widget.localPath,
        title: widget.title,
        subtitle: widget.subtitle,
      ),
    );

    if (!mounted) return;

    if (!ok) {
      setState(() {
        _isBusy = false;
        _busyMessage = null;
      });
      AppSnackBar.error(context, 'Could not cache photo for Home Widget.');
      return;
    }

    final nativeStatus = await HomeWidgetService.instance.getNativeStatus();
    if (!mounted) return;

    setState(() {
      _isBusy = false;
      _busyMessage = null;
    });

    Navigator.pop(context);
    if (nativeStatus.installedCount == 0 && nativeStatus.canPin) {
      final pinned = await HomeWidgetService.instance.requestPinWidget();
      if (mounted) {
        AppSnackBar.success(
          context,
          pinned
              ? 'Photo pinned! Confirm adding the widget to your home screen.'
              : 'Photo set on Home Widget. Long-press your home screen to add the widget.',
          title: 'Home Widget Ready',
        );
      }
    } else {
      AppSnackBar.success(
        context,
        nativeStatus.installedCount > 0
            ? 'Home Screen Widget updated!'
            : 'Saved to Home Widget. Long-press Home Screen → Widgets → Worship Chat to place it.',
        title: 'Home Widget Ready',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cleanLocal = widget.localPath?.trim().replaceFirst('file://', '');
    final hasLocalFile =
        cleanLocal != null && cleanLocal.isNotEmpty && File(cleanLocal).existsSync();
    final cleanUrl = widget.imageUrl?.trim() ?? '';

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: hasLocalFile
                        ? Image.file(File(cleanLocal), fit: BoxFit.cover)
                        : (cleanUrl.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: cleanUrl,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) =>
                                      Container(color: const Color(0xFF242038)),
                                )
                              : Container(color: const Color(0xFF242038))),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Wallpaper & Home Widget',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.title.isNotEmpty
                            ? widget.title
                            : 'Personalize your phone screen',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_isBusy) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F0E17),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: tabColor.withValues(alpha: 0.35),
                    width: 0.9,
                  ),
                ),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: tabColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _busyMessage ?? 'Processing...',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.crop_rounded,
                      color: Color(0xFFFFD700),
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Crop to Screen Before Applying',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'Adjust framing to match your display ratio',
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _cropBeforeSetting,
                      activeTrackColor: tabColor.withValues(alpha: 0.55),
                      activeThumbColor: tabColor,
                      onChanged: (v) => setState(() => _cropBeforeSetting = v),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _buildGroupLabel('SET AS PHONE WALLPAPER'),
              const SizedBox(height: 8),
              _buildCard([
                _buildActionRow(
                  icon: Icons.home_rounded,
                  color: const Color(0xFF38BDF8),
                  title: 'Home Screen Wallpaper',
                  onTap: () => _applyWallpaper(WallpaperTarget.home),
                ),
                _divider(),
                _buildActionRow(
                  icon: Icons.lock_rounded,
                  color: const Color(0xFFA78BFA),
                  title: 'Lock Screen Wallpaper',
                  onTap: () => _applyWallpaper(WallpaperTarget.lock),
                ),
                _divider(),
                _buildActionRow(
                  icon: Icons.wallpaper_rounded,
                  color: tabColor,
                  title: 'Both Home & Lock Screens',
                  onTap: () => _applyWallpaper(WallpaperTarget.both),
                ),
              ]),
              const SizedBox(height: 16),
              _buildGroupLabel('HOME SCREEN PHOTO WIDGET'),
              const SizedBox(height: 8),
              _buildCard([
                _buildActionRow(
                  icon: Icons.widgets_rounded,
                  color: const Color(0xFFFFD700),
                  title: 'Pin Photo to Home Widget',
                  subtitle: 'Show this photo on your Android home screen',
                  onTap: _pinToHomeWidget,
                ),
                _divider(),
                _buildActionRow(
                  icon: Icons.tune_rounded,
                  color: const Color(0xFF00E676),
                  title: 'Widget Settings & Collection Sync',
                  subtitle: 'Rotation timer, captions & playlist manager',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const HomeWidgetSettingsScreen(),
                      ),
                    );
                  },
                ),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGroupLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.grey[400],
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.9,
        ),
      ),
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F0E17),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 0.8,
        ),
      ),
      child: Column(children: children),
    );
  }

  Widget _divider() => Divider(
        height: 1,
        indent: 54,
        endIndent: 12,
        color: Colors.white.withValues(alpha: 0.06),
      );

  Widget _buildActionRow({
    required IconData icon,
    required Color color,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: color.withValues(alpha: 0.35),
                  width: 0.8,
                ),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null && subtitle.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      style: TextStyle(color: Colors.grey[400], fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              color: Colors.white30,
              size: 13,
            ),
          ],
        ),
      ),
    );
  }
}
