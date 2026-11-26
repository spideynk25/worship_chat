import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/utils/phone_wallpaper_service.dart';
import 'package:worship_chat/common/utils/utils.dart';
import 'package:worship_chat/common/widgets/square_image_crop_screen.dart';
import 'package:worship_chat/common/widgets/user_avatar.dart';
import 'package:worship_chat/features/auth/controller/auth_controller.dart';
import 'package:worship_chat/features/group/controller/group_controller.dart';
import 'package:worship_chat/models/group.dart';
import 'package:worship_chat/models/user_model.dart';

/// Shared bottom sheet for applying any Gallery or Bookmark photo directly as
/// the current user's profile picture or any Queendom Group / Deity's picture.
class SetAsProfilePicSheet extends ConsumerStatefulWidget {
  final String? imageUrl;
  final String? localPath;
  final String? sourceGroupId;
  final String? sourceGroupName;
  final String title;

  const SetAsProfilePicSheet({
    super.key,
    this.imageUrl,
    this.localPath,
    this.sourceGroupId,
    this.sourceGroupName,
    this.title = '',
  });

  static Future<void> show(
    BuildContext context, {
    String? imageUrl,
    String? localPath,
    String? sourceGroupId,
    String? sourceGroupName,
    String title = '',
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF161426),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => SetAsProfilePicSheet(
        imageUrl: imageUrl,
        localPath: localPath,
        sourceGroupId: sourceGroupId,
        sourceGroupName: sourceGroupName,
        title: title,
      ),
    );
  }

  @override
  ConsumerState<SetAsProfilePicSheet> createState() =>
      _SetAsProfilePicSheetState();
}

class _SetAsProfilePicSheetState extends ConsumerState<SetAsProfilePicSheet> {
  final TextEditingController _searchController = TextEditingController();
  bool _cropFirst = false;
  bool _isBusy = false;
  String? _busyMessage;
  bool _loadingGroups = true;
  bool _showGroupPicker = false;
  String _searchQuery = '';
  List<GroupModel> _groups = const [];

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadGroups() async {
    try {
      final groups =
          await ref.read(groupControllerProvider).getAllGroupsForPicker();
      if (mounted) {
        setState(() {
          _groups = groups;
          _loadingGroups = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadingGroups = false);
      }
    }
  }

  String _groupTypeFor(GroupModel group) {
    if (group.queendom == 'Queen Pooja') return 'queenPooja';
    if (group.queendom == 'Queen Rashmika') return 'queenRashmika';
    return 'others';
  }

  /// Resolves either an uploadable [File] (if local file or cropped) or an
  /// existing [String] URL (for instant direct update without re-uploading).
  Future<({File? file, String? url, bool cancelled})> _prepareMediaPayload() async {
    final cleanLocal = widget.localPath?.trim().replaceFirst('file://', '');
    final localFile =
        (cleanLocal != null && cleanLocal.isNotEmpty && File(cleanLocal).existsSync())
            ? File(cleanLocal)
            : null;
    final cleanUrl = widget.imageUrl?.trim();

    if (!_cropFirst) {
      if (cleanUrl != null && cleanUrl.isNotEmpty) {
        return (file: null, url: cleanUrl, cancelled: false);
      }
      return (file: localFile, url: null, cancelled: false);
    }

    File? sourceFile = localFile;
    if (sourceFile == null && cleanUrl != null && cleanUrl.isNotEmpty) {
      if (mounted) {
        setState(() => _busyMessage = 'Preparing photo for crop...');
      }
      sourceFile = await PhoneWallpaperService.instance.resolveImageFile(
        imageUrl: cleanUrl,
      );
    }

    if (sourceFile == null || !mounted) {
      return (file: null, url: null, cancelled: false);
    }

    final cropped = await cropImageToSquare(context, sourceFile);
    if (cropped == null) {
      return (file: null, url: null, cancelled: true);
    }
    return (file: cropped, url: null, cancelled: false);
  }

  Future<void> _applyToMyProfile() async {
    if (_isBusy) return;
    setState(() {
      _isBusy = true;
      _busyMessage = 'Updating your profile picture...';
    });

    try {
      final payload = await _prepareMediaPayload();
      if (!mounted) return;
      if (payload.cancelled) {
        setState(() {
          _isBusy = false;
          _busyMessage = null;
        });
        return;
      }
      if (payload.file == null && payload.url == null) {
        setState(() {
          _isBusy = false;
          _busyMessage = null;
        });
        AppSnackBar.error(context, 'Could not load photo for profile picture.');
        return;
      }

      if (payload.file != null) {
        setState(() => _busyMessage = 'Uploading your new profile picture...');
      }

      final ok = await ref
          .read(authControllerProvider)
          .updateCurrentUserProfilePic(
            context: context,
            imageFile: payload.file,
            imageUrl: payload.url,
          );
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _busyMessage = null;
      });
      if (ok) {
        Navigator.pop(context);
        AppSnackBar.success(
          context,
          'Your profile picture has been updated!',
          title: 'Profile Pic Updated',
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _busyMessage = null;
      });
      AppSnackBar.error(context, 'Failed to update profile picture: $e');
    }
  }

  Future<void> _applyToGroup({
    required String groupId,
    required String groupName,
    String groupType = 'group',
  }) async {
    if (_isBusy) return;
    setState(() {
      _isBusy = true;
      _busyMessage = 'Updating $groupName picture...';
    });

    try {
      final payload = await _prepareMediaPayload();
      if (!mounted) return;
      if (payload.cancelled) {
        setState(() {
          _isBusy = false;
          _busyMessage = null;
        });
        return;
      }
      if (payload.file == null && payload.url == null) {
        setState(() {
          _isBusy = false;
          _busyMessage = null;
        });
        AppSnackBar.error(context, 'Could not load photo for $groupName.');
        return;
      }

      if (payload.file != null) {
        setState(() => _busyMessage = 'Uploading $groupName picture...');
      }

      final ok = await ref.read(groupControllerProvider).updateGroupProfilePic(
            groupId: groupId,
            imageFile: payload.file,
            imageUrl: payload.url,
            type: groupType,
          );
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _busyMessage = null;
      });
      if (ok) {
        Navigator.pop(context);
        AppSnackBar.success(
          context,
          '$groupName profile picture updated!',
          title: 'Group Pic Updated',
        );
      } else {
        AppSnackBar.error(context, 'Failed to update $groupName profile pic.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _busyMessage = null;
      });
      AppSnackBar.error(context, 'Failed to update $groupName: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cleanLocal = widget.localPath?.trim().replaceFirst('file://', '');
    final hasLocalFile =
        cleanLocal != null && cleanLocal.isNotEmpty && File(cleanLocal).existsSync();
    final cleanUrl = widget.imageUrl?.trim() ?? '';

    UserModel? currentUser;
    if (Hive.isBoxOpen('userBox')) {
      currentUser = Hive.box<UserModel>('userBox').get('currentUser');
    }
    currentUser ??= ref.watch(userDataAuthProvider).valueOrNull;

    final sourceGroupId = widget.sourceGroupId?.trim() ?? '';
    final hasSourceGroup =
        sourceGroupId.isNotEmpty && sourceGroupId != 'local';
    GroupModel? sourceGroup;
    if (hasSourceGroup) {
      for (final g in _groups) {
        if (g.groupId == sourceGroupId) {
          sourceGroup = g;
          break;
        }
      }
    }
    final sourceGroupDisplayName = sourceGroup?.nameWithPosition.isNotEmpty == true
        ? sourceGroup!.nameWithPosition
        : (widget.sourceGroupName?.trim().isNotEmpty == true
            ? widget.sourceGroupName!.trim()
            : 'Source Group');

    final filteredGroups = _groups.where((g) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return g.nameWithPosition.toLowerCase().contains(q) ||
          (g.queendom ?? '').toLowerCase().contains(q) ||
          (g.family ?? '').toLowerCase().contains(q) ||
          (g.parentGroupName ?? '').toLowerCase().contains(q);
    }).toList();

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
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
                                      errorWidget: (_, __, ___) => Container(
                                        color: const Color(0xFF242038),
                                      ),
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
                            'Set as Profile Pic',
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
                                : 'Apply directly to your profile or a group',
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
                  const SizedBox(height: 14),
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
                            _busyMessage ?? 'Updating...',
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
                ],
                const SizedBox(height: 14),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1F1B33),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.crop_rounded, color: tabColor, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Crop to Square First',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              _cropFirst
                                  ? 'Frame square crop before saving'
                                  : 'Instant apply without re-uploading',
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch.adaptive(
                        value: _cropFirst,
                        activeTrackColor: tabColor,
                        onChanged: _isBusy
                            ? null
                            : (val) => setState(() => _cropFirst = val),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _TargetTile(
                  leading: UserAvatar(
                    url: currentUser?.profilePic,
                    radius: 21,
                  ),
                  title: 'My Profile Pic',
                  subtitle: currentUser?.name?.trim().isNotEmpty == true
                      ? 'Update ${currentUser!.name}\'s avatar'
                      : 'Set as your personal profile picture',
                  accentColor: tabColor,
                  onTap: _isBusy ? null : _applyToMyProfile,
                ),
                if (hasSourceGroup) ...[
                  const SizedBox(height: 8),
                  _TargetTile(
                    leading: UserAvatar(
                      url: sourceGroup?.groupPic,
                      radius: 21,
                    ),
                    title: 'Update "$sourceGroupDisplayName"',
                    subtitle: 'Quickly set as this deity / group\'s profile pic',
                    accentColor: accentOrange,
                    onTap: _isBusy
                        ? null
                        : () => _applyToGroup(
                              groupId: sourceGroupId,
                              groupName: sourceGroupDisplayName,
                              groupType: sourceGroup != null
                                  ? _groupTypeFor(sourceGroup)
                                  : 'group',
                            ),
                  ),
                ],
                const SizedBox(height: 8),
                _TargetTile(
                  leading: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD700).withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.groups_rounded,
                      color: Color(0xFFFFD700),
                      size: 22,
                    ),
                  ),
                  title: 'Choose Any Group / Deity',
                  subtitle: _loadingGroups
                      ? 'Loading groups...'
                      : 'Pick from ${_groups.length} groups & sub-groups',
                  accentColor: const Color(0xFFFFD700),
                  trailing: Icon(
                    _showGroupPicker
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: Colors.white60,
                  ),
                  onTap: _isBusy
                      ? null
                      : () =>
                          setState(() => _showGroupPicker = !_showGroupPicker),
                ),
                if (_showGroupPicker) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white, fontSize: 13.5),
                    decoration: InputDecoration(
                      hintText: 'Search deity or group...',
                      hintStyle: const TextStyle(color: Colors.white38),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: Colors.white54,
                        size: 20,
                      ),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(
                                Icons.close_rounded,
                                color: Colors.white54,
                                size: 18,
                              ),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: const Color(0xFF0F0E17),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (val) =>
                        setState(() => _searchQuery = val.trim()),
                  ),
                  const SizedBox(height: 8),
                  if (_loadingGroups)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: tabColor,
                        ),
                      ),
                    )
                  else if (filteredGroups.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 18),
                      child: Center(
                        child: Text(
                          'No matching groups found',
                          style: TextStyle(color: Colors.white54, fontSize: 13),
                        ),
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 260),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: filteredGroups.length,
                        separatorBuilder: (_, __) => const Divider(
                          height: 1,
                          color: Colors.white10,
                        ),
                        itemBuilder: (_, i) {
                          final g = filteredGroups[i];
                          final subtitleParts = <String>[
                            if (g.queendom != null &&
                                g.queendom != 'None' &&
                                g.queendom!.isNotEmpty)
                              g.queendom!,
                            if (g.isSubGroup &&
                                (g.parentGroupName?.isNotEmpty ?? false))
                              'Sub-group of ${g.parentGroupName}'
                            else if ((g.family?.isNotEmpty ?? false) &&
                                g.family != 'None')
                              g.family!,
                          ];
                          return ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            leading: UserAvatar(url: g.groupPic, radius: 18),
                            title: Text(
                              g.nameWithPosition,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: subtitleParts.isNotEmpty
                                ? Text(
                                    subtitleParts.join(' • '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 11.5,
                                    ),
                                  )
                                : null,
                            trailing: const Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 13,
                              color: Colors.white38,
                            ),
                            onTap: _isBusy
                                ? null
                                : () => _applyToGroup(
                                      groupId: g.groupId,
                                      groupName: g.nameWithPosition,
                                      groupType: _groupTypeFor(g),
                                    ),
                          );
                        },
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

class _TargetTile extends StatelessWidget {
  final Widget leading;
  final String title;
  final String subtitle;
  final Color accentColor;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _TargetTile({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1F1B33),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: accentColor.withValues(alpha: 0.28),
            ),
          ),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              trailing ??
                  Icon(
                    Icons.chevron_right_rounded,
                    color: accentColor,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
