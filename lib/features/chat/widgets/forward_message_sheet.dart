import 'dart:convert';
import 'dart:developer';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/utils/utils.dart';
import 'package:worship_chat/common/widgets/user_avatar.dart';
import 'package:worship_chat/features/auth/controller/auth_controller.dart';
import 'package:worship_chat/features/chat/controller/chat_controller.dart';
import 'package:worship_chat/features/group/controller/group_controller.dart';
import 'package:worship_chat/features/group/controller/group_gallery_controller.dart';
import 'package:worship_chat/models/chat_contact.dart';
import 'package:worship_chat/models/group.dart';

/// Extract clean media URL from fileMessageData (which may be plain URL or JSON).
String _extractCleanMediaUrl(String? raw) {
  if (raw == null || raw.isEmpty) return '';
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map && decoded.containsKey('url')) {
      return decoded['url']?.toString() ?? '';
    }
  } catch (_) {}
  return raw;
}

/// Represents the message payload to be forwarded.
class ForwardMessagePayload {
  final String text;
  final String messageType;
  final String? fileMessageData;
  final String? caption;
  final bool isFromGallery;
  final String? sourceGroupId;
  final String? sourceGroupName;

  const ForwardMessagePayload({
    required this.text,
    required this.messageType,
    this.fileMessageData,
    this.caption,
    this.isFromGallery = false,
    this.sourceGroupId,
    this.sourceGroupName,
  });

  bool get isImage => messageType == 'image';
  bool get isVideo => messageType == 'video';
  bool get isGif => messageType == 'gif';
  bool get isAudio => messageType == 'audio';
  bool get isDocument => messageType == 'document';
  bool get isLocation =>
      messageType == 'location' || messageType == 'live_location';
  bool get isText => messageType == 'text';

  String get effectiveMediaUrl => _extractCleanMediaUrl(fileMessageData);

  String get previewTitle {
    if (text.isNotEmpty && (isText || text != fileMessageData)) {
      return text;
    }
    switch (messageType) {
      case 'image':
        return 'Photo';
      case 'video':
        return 'Video';
      case 'gif':
        return 'GIF';
      case 'audio':
        return 'Voice Message';
      case 'document':
        return 'Document';
      case 'location':
      case 'live_location':
        return 'Location';
      default:
        return 'Message';
    }
  }

  IconData get icon {
    switch (messageType) {
      case 'image':
        return Icons.photo_rounded;
      case 'video':
        return Icons.videocam_rounded;
      case 'gif':
        return Icons.gif_box_rounded;
      case 'audio':
        return Icons.mic_rounded;
      case 'document':
        return Icons.description_rounded;
      case 'location':
      case 'live_location':
        return Icons.location_on_rounded;
      default:
        return Icons.chat_bubble_outline_rounded;
    }
  }
}

enum ForwardTargetType { directChat, groupChat, groupGallery }

class ForwardTarget {
  final String id;
  final String name;
  final String? avatarUrl;
  final ForwardTargetType type;
  final dynamic data;

  const ForwardTarget({
    required this.id,
    required this.name,
    this.avatarUrl,
    required this.type,
    required this.data,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ForwardTarget && id == other.id && type == other.type;

  @override
  int get hashCode => Object.hash(id, type);
}

class ForwardMessageSheet extends ConsumerStatefulWidget {
  final ForwardMessagePayload payload;

  const ForwardMessageSheet({super.key, required this.payload});

  static Future<void> show(
    BuildContext context,
    ForwardMessagePayload payload,
  ) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      builder: (ctx) => ForwardMessageSheet(payload: payload),
    );
  }

  @override
  ConsumerState<ForwardMessageSheet> createState() =>
      _ForwardMessageSheetState();
}

class _ForwardMessageSheetState extends ConsumerState<ForwardMessageSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final Set<ForwardTarget> _selectedTargets = {};
  String _searchQuery = '';
  bool _isSending = false;

  bool get _hasGalleryTab => widget.payload.isImage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _hasGalleryTab ? 3 : 2,
      vsync: this,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _toggleTarget(ForwardTarget target) {
    setState(() {
      if (_selectedTargets.contains(target)) {
        _selectedTargets.remove(target);
      } else {
        _selectedTargets.add(target);
      }
    });
  }

  Future<void> _executeForward() async {
    if (_selectedTargets.isEmpty || _isSending) return;

    setState(() => _isSending = true);

    try {
      final payload = widget.payload;
      final mediaUrl = payload.effectiveMediaUrl;
      final cleanText = payload.text;

      final userData = await ref.read(userDataAuthProvider.future);
      final uploaderName =
          userData?.name ??
          userData?.userName ??
          FirebaseAuth.instance.currentUser?.displayName ??
          'User';

      int successCount = 0;

      for (final target in _selectedTargets) {
        if (!mounted) break;
        try {
          switch (target.type) {
            case ForwardTargetType.directChat:
              final contact = target.data as ChatContact;
              await ref.read(chatControllerProvider).sendTextMessage(
                    context,
                    cleanText,
                    contact.uid,
                    payload.messageType,
                    mediaUrl.isNotEmpty ? mediaUrl : null,
                    contact.fcmToken ?? '',
                    true,
                    contact.chatBackgroundUrl,
                    "chat",
                    clearReply: true,
                  );
              successCount++;
              break;

            case ForwardTargetType.groupChat:
              final group = target.data as GroupModel;
              await ref.read(groupControllerProvider).sendTextMessage(
                    context,
                    cleanText,
                    group.groupId,
                    payload.messageType,
                    mediaUrl.isNotEmpty ? mediaUrl : null,
                    group.fcmTokens,
                    group.membersUid,
                    group.name,
                    "group",
                    clearReply: true,
                  );
              successCount++;
              break;

            case ForwardTargetType.groupGallery:
              final group = target.data as GroupModel;
              final imageToSave =
                  mediaUrl.isNotEmpty ? mediaUrl : payload.text;
              if (imageToSave.isNotEmpty) {
                final ok = await ref
                    .read(groupGalleryControllerProvider)
                    .addGalleryImageFromUrl(
                      groupId: group.groupId,
                      imageUrl: imageToSave,
                      uploaderName: uploaderName,
                      caption: payload.caption ??
                          (cleanText.isNotEmpty && cleanText != imageToSave
                              ? cleanText
                              : null),
                    );
                if (ok) successCount++;
              }
              break;
          }
        } catch (e) {
          log('❌ Error forwarding to ${target.name}: $e');
        }
      }

      if (mounted) {
        Navigator.pop(context);
        if (successCount > 0) {
          AppSnackBar.success(
            context,
            'Forwarded to $successCount destination${successCount > 1 ? 's' : ''}',
          );
        } else {
          AppSnackBar.error(context, 'Failed to forward message');
        }
      }
    } catch (e) {
      log('❌ _executeForward error: $e');
      if (mounted) {
        setState(() => _isSending = false);
        AppSnackBar.error(context, 'Error forwarding: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;
    final maxSheetHeight = screenHeight * 0.88;

    return AnimatedPadding(
      padding: EdgeInsets.only(bottom: keyboardHeight),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      child: Container(
        height: maxSheetHeight,
        decoration: const BoxDecoration(
          color: Color(0xFF13101E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          border: Border(
            top: BorderSide(color: Color(0x33FFFFFF), width: 1),
            left: BorderSide(color: Color(0x1AFFFFFF), width: 0.5),
            right: BorderSide(color: Color(0x1AFFFFFF), width: 0.5),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black87,
              blurRadius: 30,
              offset: Offset(0, -6),
            ),
          ],
        ),
        child: Column(
          children: [
            // ── Drag Handle ─────────────────────────────────────────────────
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 38,
              height: 4.5,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(3),
              ),
            ),

            // ── Header: Title & Close ────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              child: Row(
                children: [
                  const Text(
                    'Forward to...',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white70, size: 22),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // ── Forwarded Message Preview Card ───────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildMessagePreviewBanner(),
            ),

            const SizedBox(height: 10),

            // ── Search Bar ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1A2D),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) => setState(() => _searchQuery = val.trim()),
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search chats, groups, galleries...',
                    hintStyle:
                        const TextStyle(color: Colors.white38, fontSize: 13.5),
                    prefixIcon: const Icon(Icons.search_rounded,
                        color: Colors.white54, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? GestureDetector(
                            onTap: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                            child: const Icon(Icons.cancel_rounded,
                                color: Colors.white38, size: 18),
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // ── Tab Bar ─────────────────────────────────────────────────────
            Container(
              height: 38,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF1B1728),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF8B255F), Color(0xFF5D1240)],
                  ),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white54,
                labelStyle:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                dividerColor: Colors.transparent,
                tabs: [
                  const Tab(text: 'Chats'),
                  const Tab(text: 'Groups'),
                  if (_hasGalleryTab) const Tab(text: 'Galleries'),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // ── Tab Views ───────────────────────────────────────────────────
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildDirectChatsTab(),
                  _buildGroupsTab(),
                  if (_hasGalleryTab) _buildGroupGalleriesTab(),
                ],
              ),
            ),

            // ── Bottom Floating / Docked Send Bar ────────────────────────────
            if (_selectedTargets.isNotEmpty) _buildBottomSendBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildMessagePreviewBanner() {
    final payload = widget.payload;
    final mediaUrl = payload.effectiveMediaUrl;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1628),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          // Media Thumbnail or Icon
          if (payload.isImage && mediaUrl.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: mediaUrl,
                width: 38,
                height: 38,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  width: 38,
                  height: 38,
                  color: Colors.white10,
                  child: const Icon(Icons.image, color: Colors.white38, size: 20),
                ),
                errorWidget: (_, __, ___) => Container(
                  width: 38,
                  height: 38,
                  color: Colors.white10,
                  child: const Icon(Icons.broken_image,
                      color: Colors.white38, size: 20),
                ),
              ),
            )
          else
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: tabColor.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(payload.icon, color: Colors.white, size: 20),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.forward_rounded,
                        color: tabColor, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      payload.isFromGallery
                          ? 'Forward from ${payload.sourceGroupName ?? 'Gallery'}'
                          : 'Forwarded message',
                      style: const TextStyle(
                        color: tabColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  payload.previewTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDirectChatsTab() {
    return StreamBuilder<List<ChatContact>>(
      stream: ref.watch(chatControllerProvider).fetchAllContacts(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: tabColor, strokeWidth: 2),
          );
        }

        final contacts = snapshot.data ?? [];
        final filtered = contacts.where((c) {
          if (_searchQuery.isEmpty) return true;
          return c.name.toLowerCase().contains(_searchQuery.toLowerCase());
        }).toList();

        if (filtered.isEmpty) {
          return Center(
            child: Text(
              _searchQuery.isEmpty ? 'No chats found' : 'No matches for "$_searchQuery"',
              style: const TextStyle(color: Colors.white38, fontSize: 13),
            ),
          );
        }

        return ListView.builder(
          itemCount: filtered.length,
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemBuilder: (context, index) {
            final contact = filtered[index];
            final target = ForwardTarget(
              id: contact.uid,
              name: contact.name,
              avatarUrl: contact.profilePic,
              type: ForwardTargetType.directChat,
              data: contact,
            );
            final isSelected = _selectedTargets.contains(target);

            return _buildTargetTile(
              target: target,
              isSelected: isSelected,
              subtitle: 'Direct Chat',
            );
          },
        );
      },
    );
  }

  Widget _buildGroupsTab() {
    return StreamBuilder<List<GroupModel>>(
      stream: ref.watch(groupControllerProvider).getAllUserGroups(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: tabColor, strokeWidth: 2),
          );
        }

        final groups = snapshot.data ?? [];
        final filtered = groups.where((g) {
          if (_searchQuery.isEmpty) return true;
          return g.name.toLowerCase().contains(_searchQuery.toLowerCase());
        }).toList();

        if (filtered.isEmpty) {
          return Center(
            child: Text(
              _searchQuery.isEmpty ? 'No groups found' : 'No matches for "$_searchQuery"',
              style: const TextStyle(color: Colors.white38, fontSize: 13),
            ),
          );
        }

        return ListView.builder(
          itemCount: filtered.length,
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemBuilder: (context, index) {
            final group = filtered[index];
            final target = ForwardTarget(
              id: group.groupId,
              name: group.name,
              avatarUrl: group.groupPic,
              type: ForwardTargetType.groupChat,
              data: group,
            );
            final isSelected = _selectedTargets.contains(target);

            return _buildTargetTile(
              target: target,
              isSelected: isSelected,
              subtitle: '${group.membersUid.length} members',
            );
          },
        );
      },
    );
  }

  Widget _buildGroupGalleriesTab() {
    return StreamBuilder<List<GroupModel>>(
      stream: ref.watch(groupControllerProvider).getAllUserGroups(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: tabColor, strokeWidth: 2),
          );
        }

        final groups = snapshot.data ?? [];
        // Optional: filter out source group if from gallery to prevent self-forwarding
        final filtered = groups.where((g) {
          if (widget.payload.isFromGallery &&
              widget.payload.sourceGroupId == g.groupId) {
            return false;
          }
          if (_searchQuery.isEmpty) return true;
          return g.name.toLowerCase().contains(_searchQuery.toLowerCase());
        }).toList();

        if (filtered.isEmpty) {
          return Center(
            child: Text(
              _searchQuery.isEmpty
                  ? 'No group galleries found'
                  : 'No matches for "$_searchQuery"',
              style: const TextStyle(color: Colors.white38, fontSize: 13),
            ),
          );
        }

        return ListView.builder(
          itemCount: filtered.length,
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemBuilder: (context, index) {
            final group = filtered[index];
            final target = ForwardTarget(
              id: group.groupId,
              name: '${group.name} Gallery',
              avatarUrl: group.groupPic,
              type: ForwardTargetType.groupGallery,
              data: group,
            );
            final isSelected = _selectedTargets.contains(target);

            return _buildTargetTile(
              target: target,
              isSelected: isSelected,
              subtitle: 'Add photo directly to group gallery',
              isGallery: true,
            );
          },
        );
      },
    );
  }

  Widget _buildTargetTile({
    required ForwardTarget target,
    required bool isSelected,
    required String subtitle,
    bool isGallery = false,
  }) {
    return InkWell(
      onTap: () => _toggleTarget(target),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            // Avatar
            Stack(
              clipBehavior: Clip.none,
              children: [
                UserAvatar(
                  url: target.avatarUrl,
                  radius: 22,
                ),
                if (isGallery)
                  Positioned(
                    bottom: -2,
                    right: -2,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Color(0xFF6E1C4B),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.collections_rounded,
                        color: Colors.white,
                        size: 11,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),

            // Name & subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    target.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14.5,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isGallery ? tabColor : Colors.white38,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            // Selection Circle Indicator
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: isSelected
                    ? const LinearGradient(
                        colors: [Color(0xFF8B255F), Color(0xFFD83B92)],
                      )
                    : null,
                border: Border.all(
                  color: isSelected ? Colors.transparent : Colors.white38,
                  width: 1.6,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check, color: Colors.white, size: 16)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomSendBar() {
    final count = _selectedTargets.length;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1B172A),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Selected avatar stack / text summary
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$count selected',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    _selectedTargets.map((t) => t.name).join(', '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 12),

            // Forward Send Button
            ElevatedButton(
              onPressed: _isSending ? null : _executeForward,
              style: ElevatedButton.styleFrom(
                backgroundColor: tabColor,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
                elevation: 4,
              ),
              child: _isSending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Forward ($count)',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.send_rounded, size: 16),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
