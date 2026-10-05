import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/widgets/user_avatar.dart';
import 'package:worship_chat/features/auth/controller/auth_controller.dart';
import 'package:worship_chat/features/chat/controller/chat_controller.dart';
import 'package:worship_chat/features/group/controller/group_controller.dart';
import 'package:worship_chat/features/group/controller/group_gallery_controller.dart';
import 'package:worship_chat/models/chat_contact.dart';
import 'package:worship_chat/models/group.dart';
import 'package:worship_chat/models/user_model.dart';
import 'package:hive/hive.dart';

/// Extract clean media URL from fileMessageData (which may be plain URL or JSON wrapper).
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

  String get effectiveMediaUrl {
    final clean = _extractCleanMediaUrl(fileMessageData);
    if (clean.isNotEmpty) return clean;
    if ((isImage || isVideo || isGif || isDocument || isAudio) &&
        (text.startsWith('http://') || text.startsWith('https://'))) {
      return text;
    }
    return '';
  }

  String get previewTitle {
    if (text.isNotEmpty && (isText || text != fileMessageData)) {
      if (!isText &&
          (text.startsWith('http://') || text.startsWith('https://'))) {
        return isImage ? 'Photo' : isVideo ? 'Video' : 'Media';
      }
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

    final messenger = ScaffoldMessenger.of(context);

    try {
      final payload = widget.payload;
      final mediaUrl = payload.effectiveMediaUrl;
      final cleanText = payload.text;
      final effectiveFile = mediaUrl.isNotEmpty
          ? mediaUrl
          : (!payload.isText &&
                  (payload.text.startsWith('http://') ||
                      payload.text.startsWith('https://'))
              ? payload.text
              : null);

      UserModel? userData;
      try {
        userData = await ref.read(userDataAuthProvider.future);
      } catch (_) {}
      if (userData == null && Hive.isBoxOpen('userBox')) {
        userData = Hive.box<UserModel>('userBox').get('currentUser');
      }
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
              if (contact.uid.isEmpty) continue;
              await ref.read(chatControllerProvider).sendTextMessage(
                    context,
                    cleanText,
                    contact.uid,
                    payload.messageType,
                    effectiveFile,
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
              if (group.groupId.isEmpty) continue;
              await ref.read(groupControllerProvider).sendTextMessage(
                    context,
                    cleanText,
                    group.groupId,
                    payload.messageType,
                    effectiveFile,
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
              if (group.groupId.isEmpty) continue;
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

      if (!mounted) return;

      final successMsg =
          'Forwarded to $successCount destination${successCount > 1 ? 's' : ''}';
      final hasSuccess = successCount > 0;

      Navigator.pop(context);

      messenger.showSnackBar(
        SnackBar(
          elevation: 0,
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.transparent,
          duration: const Duration(milliseconds: 3200),
          padding: EdgeInsets.zero,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          content: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1A2D),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: hasSuccess
                    ? const Color(0xFF22C55E).withValues(alpha: 0.3)
                    : const Color(0xFFEF4444).withValues(alpha: 0.3),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black45,
                  blurRadius: 16,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(
                  hasSuccess
                      ? Icons.check_circle_rounded
                      : Icons.error_outline_rounded,
                  color: hasSuccess
                      ? const Color(0xFF22C55E)
                      : const Color(0xFFEF4444),
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    hasSuccess ? successMsg : 'Failed to forward message',
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
        ),
      );
    } catch (e) {
      log('❌ _executeForward error: $e');
      if (mounted) {
        setState(() => _isSending = false);
      }
      messenger.showSnackBar(
        SnackBar(
          elevation: 0,
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.transparent,
          duration: const Duration(milliseconds: 3200),
          padding: EdgeInsets.zero,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          content: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1A2D),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFFEF4444).withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  color: Color(0xFFEF4444),
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Error forwarding: $e',
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
        ),
      );
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
        decoration: BoxDecoration(
          color: const Color(0xFF13101E),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          border: Border.all(
            color: const Color(0x26FFFFFF),
            width: 1,
          ),
          boxShadow: const [
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
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
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
                  _ChatsTab(
                    searchQuery: _searchQuery,
                    selectedTargets: _selectedTargets,
                    onToggleTarget: _toggleTarget,
                  ),
                  _GroupsTab(
                    searchQuery: _searchQuery,
                    selectedTargets: _selectedTargets,
                    onToggleTarget: _toggleTarget,
                  ),
                  if (_hasGalleryTab)
                    _GalleriesTab(
                      payload: widget.payload,
                      searchQuery: _searchQuery,
                      selectedTargets: _selectedTargets,
                      onToggleTarget: _toggleTarget,
                    ),
                ],
              ),
            ),

            // ── Bottom Floating / Docked Send Bar ────────────────────────────
            if (_selectedTargets.isNotEmpty)
              _buildBottomSendBar()
            else
              SafeArea(
                top: false,
                child: const SizedBox.shrink(),
              ),
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
              child: Image.network(
                mediaUrl,
                width: 38,
                height: 38,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 38,
                  height: 38,
                  color: tabColor.withValues(alpha: 0.2),
                  child: const Icon(Icons.photo_rounded,
                      color: Colors.white, size: 20),
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
                    Expanded(
                      child: Text(
                        payload.isFromGallery
                            ? 'Forward from ${payload.sourceGroupName ?? 'Gallery'}'
                            : 'Forwarded message',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: tabColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
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

// ─────────────────────────────────────────────────────────────────────────────
// ── Chats Tab Component (Direct Conversations + All Contacts) ────────────────
// ─────────────────────────────────────────────────────────────────────────────

class _ChatsTab extends ConsumerStatefulWidget {
  final String searchQuery;
  final Set<ForwardTarget> selectedTargets;
  final ValueChanged<ForwardTarget> onToggleTarget;

  const _ChatsTab({
    required this.searchQuery,
    required this.selectedTargets,
    required this.onToggleTarget,
  });

  @override
  ConsumerState<_ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends ConsumerState<_ChatsTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<ChatContact> _recentChats = [];
  List<ChatContact> _allContacts = [];
  StreamSubscription<List<ChatContact>>? _recentSub;
  StreamSubscription<List<ChatContact>>? _allSub;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // 1. Instant 0ms load from Hive cache
    try {
      final cachedRecent = ref
          .read(chatControllerProvider)
          .getCachedContacts(isAllChats: false);
      final cachedAll = ref
          .read(chatControllerProvider)
          .getCachedContacts(isAllChats: true);

      _recentChats = cachedRecent;
      _allContacts = cachedAll;
      if (_recentChats.isNotEmpty || _allContacts.isNotEmpty) {
        _isLoading = false;
      }
    } catch (e) {
      log('Error reading cached contacts: $e');
    }

    // 2. Real-time updates from Firestore
    try {
      _recentSub = ref
          .read(chatControllerProvider)
          .chatContacts()
          .listen((chats) {
        if (mounted) {
          setState(() {
            _recentChats = chats;
            _isLoading = false;
          });
        }
      }, onError: (e) {
        log('Error in recent chats stream: $e');
        if (mounted) setState(() => _isLoading = false);
      });

      _allSub = ref
          .read(chatControllerProvider)
          .fetchAllContacts()
          .listen((all) {
        if (mounted) {
          setState(() {
            _allContacts = all;
            _isLoading = false;
          });
        }
      }, onError: (e) {
        log('Error in all contacts stream: $e');
        if (mounted) setState(() => _isLoading = false);
      });
    } catch (e) {
      log('Error setting up contact subscriptions: $e');
      _isLoading = false;
    }
  }

  @override
  void dispose() {
    _recentSub?.cancel();
    _allSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isLoading && _recentChats.isEmpty && _allContacts.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: tabColor, strokeWidth: 2),
      );
    }

    // Deduplicate by uid: recent chats take priority (they have lastMessage and proper profile)
    final Map<String, ChatContact> map = {};
    for (final c in _recentChats) {
      if (c.uid.isNotEmpty) map[c.uid] = c;
    }
    for (final c in _allContacts) {
      if (c.uid.isNotEmpty && !map.containsKey(c.uid)) {
        map[c.uid] = c;
      }
    }

    final contacts = map.values.toList();
    final query = widget.searchQuery.toLowerCase();
    final filtered = contacts.where((c) {
      if (query.isEmpty) return true;
      return c.name.toLowerCase().contains(query);
    }).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Text(
          widget.searchQuery.isEmpty
              ? 'No chats found'
              : 'No matches for "${widget.searchQuery}"',
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
        final isSelected = widget.selectedTargets.contains(target);

        final subtitle = (contact.lastMessage != null &&
                contact.lastMessage!.trim().isNotEmpty)
            ? contact.lastMessage!.trim()
            : 'Direct Chat';

        return _buildTargetTile(
          target: target,
          isSelected: isSelected,
          subtitle: subtitle,
          onTap: () => widget.onToggleTarget(target),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ── Group Categories & Helpers ───────────────────────────────────────────────
// ─────────────────────────────────────────────────────────────────────────────

enum GroupCategory { all, normal, queenPooja, queenRashmika }

GroupCategory _getGroupCategory(GroupModel group) {
  final q = group.queendom?.trim();
  if (q == 'Queen Pooja') {
    return GroupCategory.queenPooja;
  } else if (q == 'Queen Rashmika') {
    return GroupCategory.queenRashmika;
  }
  return GroupCategory.normal;
}

// ─────────────────────────────────────────────────────────────────────────────
// ── Groups Tab Component (Categorized: Normal, Queen Pooja, Queen Rashmika) ───
// ─────────────────────────────────────────────────────────────────────────────

class _GroupsTab extends ConsumerStatefulWidget {
  final String searchQuery;
  final Set<ForwardTarget> selectedTargets;
  final ValueChanged<ForwardTarget> onToggleTarget;

  const _GroupsTab({
    required this.searchQuery,
    required this.selectedTargets,
    required this.onToggleTarget,
  });

  @override
  ConsumerState<_GroupsTab> createState() => _GroupsTabState();
}

class _GroupsTabState extends ConsumerState<_GroupsTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<GroupModel> _groups = [];
  StreamSubscription<List<GroupModel>>? _groupSub;
  bool _isLoading = true;
  GroupCategory _selectedCategory = GroupCategory.all;

  @override
  void initState() {
    super.initState();
    // 1. Instant 0ms load from Hive cache
    try {
      final pooja =
          ref.read(groupControllerProvider).getCachedGroups('groups_pooja');
      final rashmika =
          ref.read(groupControllerProvider).getCachedGroups('groups_rashmika');
      final general =
          ref.read(groupControllerProvider).getCachedGroups('groups_none');
      final allCached =
          ref.read(groupControllerProvider).getCachedGroups('groups_all');

      final Map<String, GroupModel> mergedMap = {};
      for (final g in [...allCached, ...general, ...pooja, ...rashmika]) {
        if (g.groupId.isNotEmpty) mergedMap[g.groupId] = g;
      }
      if (mergedMap.isNotEmpty) {
        _groups = mergedMap.values.toList()
          ..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        _isLoading = false;
      }
    } catch (e) {
      log('Error reading cached groups: $e');
    }

    // 2. Real-time updates from Firestore
    try {
      _groupSub = ref
          .read(groupControllerProvider)
          .getAllUserGroups()
          .listen((groups) {
        if (mounted) {
          setState(() {
            _groups = groups;
            _isLoading = false;
          });
        }
      }, onError: (e) {
        log('Error in getAllUserGroups stream: $e');
        if (mounted) setState(() => _isLoading = false);
      });
    } catch (e) {
      log('Error setting up group subscription: $e');
      _isLoading = false;
    }
  }

  @override
  void dispose() {
    _groupSub?.cancel();
    super.dispose();
  }

  Widget _buildGroupTile(GroupModel group) {
    final target = ForwardTarget(
      id: group.groupId,
      name: group.name,
      avatarUrl: group.groupPic,
      type: ForwardTargetType.groupChat,
      data: group,
    );
    final isSelected = widget.selectedTargets.contains(target);
    final category = _getGroupCategory(group);

    final String subtitle;
    final Color? subtitleColor;
    switch (category) {
      case GroupCategory.queenPooja:
        subtitle = "Queen Pooja's Group • ${group.membersUid.length} members";
        subtitleColor = const Color(0xFFFFD700);
        break;
      case GroupCategory.queenRashmika:
        subtitle =
            "Queen Rashmika's Group • ${group.membersUid.length} members";
        subtitleColor = const Color(0xFFFF4081);
        break;
      case GroupCategory.normal:
      case GroupCategory.all:
        subtitle = "Normal Group • ${group.membersUid.length} members";
        subtitleColor = Colors.white54;
        break;
    }

    return _buildTargetTile(
      target: target,
      isSelected: isSelected,
      subtitle: subtitle,
      subtitleColor: subtitleColor,
      onTap: () => widget.onToggleTarget(target),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isLoading && _groups.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: tabColor, strokeWidth: 2),
      );
    }

    final query = widget.searchQuery.toLowerCase();
    final allMatching = _groups.where((g) {
      if (query.isEmpty) return true;
      return g.name.toLowerCase().contains(query);
    }).toList();

    // Segregate by category
    final normalGroups = allMatching
        .where((g) => _getGroupCategory(g) == GroupCategory.normal)
        .toList();
    final poojaGroups = allMatching
        .where((g) => _getGroupCategory(g) == GroupCategory.queenPooja)
        .toList();
    final rashmikaGroups = allMatching
        .where((g) => _getGroupCategory(g) == GroupCategory.queenRashmika)
        .toList();

    return Column(
      children: [
        // ── Category Filter Bar ─────────────────────────────────────────────
        _buildCategoryFilterBar(
          selectedCategory: _selectedCategory,
          onCategoryChanged: (cat) => setState(() => _selectedCategory = cat),
          totalCount: allMatching.length,
          normalCount: normalGroups.length,
          poojaCount: poojaGroups.length,
          rashmikaCount: rashmikaGroups.length,
        ),

        // ── Group List Content ──────────────────────────────────────────────
        Expanded(
          child: _buildGroupContent(
            allMatching: allMatching,
            normalGroups: normalGroups,
            poojaGroups: poojaGroups,
            rashmikaGroups: rashmikaGroups,
          ),
        ),
      ],
    );
  }

  Widget _buildGroupContent({
    required List<GroupModel> allMatching,
    required List<GroupModel> normalGroups,
    required List<GroupModel> poojaGroups,
    required List<GroupModel> rashmikaGroups,
  }) {
    if (allMatching.isEmpty) {
      return Center(
        child: Text(
          widget.searchQuery.isEmpty
              ? 'No groups found'
              : 'No matches for "${widget.searchQuery}"',
          style: const TextStyle(color: Colors.white38, fontSize: 13),
        ),
      );
    }

    switch (_selectedCategory) {
      case GroupCategory.normal:
        if (normalGroups.isEmpty) {
          return const Center(
            child: Text('No normal groups found',
                style: TextStyle(color: Colors.white38, fontSize: 13)),
          );
        }
        return ListView.builder(
          itemCount: normalGroups.length,
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemBuilder: (_, i) => _buildGroupTile(normalGroups[i]),
        );

      case GroupCategory.queenPooja:
        if (poojaGroups.isEmpty) {
          return const Center(
            child: Text("No Queen Pooja's groups found",
                style: TextStyle(color: Colors.white38, fontSize: 13)),
          );
        }
        return ListView.builder(
          itemCount: poojaGroups.length,
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemBuilder: (_, i) => _buildGroupTile(poojaGroups[i]),
        );

      case GroupCategory.queenRashmika:
        if (rashmikaGroups.isEmpty) {
          return const Center(
            child: Text("No Queen Rashmika's groups found",
                style: TextStyle(color: Colors.white38, fontSize: 13)),
          );
        }
        return ListView.builder(
          itemCount: rashmikaGroups.length,
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemBuilder: (_, i) => _buildGroupTile(rashmikaGroups[i]),
        );

      case GroupCategory.all:
        // Categorized view with section headers
        final List<Widget> items = [];

        if (poojaGroups.isNotEmpty) {
          items.add(_buildSectionHeader(
            title: "QUEEN POOJA'S GROUPS",
            color: const Color(0xFFFFD700),
            count: poojaGroups.length,
          ));
          for (final g in poojaGroups) {
            items.add(_buildGroupTile(g));
          }
        }

        if (rashmikaGroups.isNotEmpty) {
          items.add(_buildSectionHeader(
            title: "QUEEN RASHMIKA'S GROUPS",
            color: const Color(0xFFFF4081),
            count: rashmikaGroups.length,
          ));
          for (final g in rashmikaGroups) {
            items.add(_buildGroupTile(g));
          }
        }

        if (normalGroups.isNotEmpty) {
          items.add(_buildSectionHeader(
            title: "NORMAL GROUPS",
            color: const Color(0xFFC070D0),
            count: normalGroups.length,
          ));
          for (final g in normalGroups) {
            items.add(_buildGroupTile(g));
          }
        }

        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 4),
          children: items,
        );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ── Galleries Tab Component (Categorized Group Galleries) ────────────────────
// ─────────────────────────────────────────────────────────────────────────────

class _GalleriesTab extends ConsumerStatefulWidget {
  final ForwardMessagePayload payload;
  final String searchQuery;
  final Set<ForwardTarget> selectedTargets;
  final ValueChanged<ForwardTarget> onToggleTarget;

  const _GalleriesTab({
    required this.payload,
    required this.searchQuery,
    required this.selectedTargets,
    required this.onToggleTarget,
  });

  @override
  ConsumerState<_GalleriesTab> createState() => _GalleriesTabState();
}

class _GalleriesTabState extends ConsumerState<_GalleriesTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<GroupModel> _groups = [];
  StreamSubscription<List<GroupModel>>? _groupSub;
  bool _isLoading = true;
  GroupCategory _selectedCategory = GroupCategory.all;

  @override
  void initState() {
    super.initState();
    // 1. Instant 0ms load from Hive cache
    try {
      final pooja =
          ref.read(groupControllerProvider).getCachedGroups('groups_pooja');
      final rashmika =
          ref.read(groupControllerProvider).getCachedGroups('groups_rashmika');
      final general =
          ref.read(groupControllerProvider).getCachedGroups('groups_none');
      final allCached =
          ref.read(groupControllerProvider).getCachedGroups('groups_all');

      final Map<String, GroupModel> mergedMap = {};
      for (final g in [...allCached, ...general, ...pooja, ...rashmika]) {
        if (g.groupId.isNotEmpty) mergedMap[g.groupId] = g;
      }
      if (mergedMap.isNotEmpty) {
        _groups = mergedMap.values.toList()
          ..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        _isLoading = false;
      }
    } catch (e) {
      log('Error reading cached groups for gallery: $e');
    }

    // 2. Real-time updates from Firestore
    try {
      _groupSub = ref
          .read(groupControllerProvider)
          .getAllUserGroups()
          .listen((groups) {
        if (mounted) {
          setState(() {
            _groups = groups;
            _isLoading = false;
          });
        }
      }, onError: (e) {
        log('Error in galleries getAllUserGroups stream: $e');
        if (mounted) setState(() => _isLoading = false);
      });
    } catch (e) {
      log('Error setting up gallery group subscription: $e');
      _isLoading = false;
    }
  }

  @override
  void dispose() {
    _groupSub?.cancel();
    super.dispose();
  }

  Widget _buildGalleryTile(GroupModel group) {
    final target = ForwardTarget(
      id: group.groupId,
      name: '${group.name} Gallery',
      avatarUrl: group.groupPic,
      type: ForwardTargetType.groupGallery,
      data: group,
    );
    final isSelected = widget.selectedTargets.contains(target);
    final category = _getGroupCategory(group);
    final count = group.galleryCount;
    final countText = count > 0
        ? '$count ${count == 1 ? 'photo' : 'photos'}'
        : 'Add photo';

    final String subtitle;
    final Color? subtitleColor;
    switch (category) {
      case GroupCategory.queenPooja:
        subtitle = "Queen Pooja Gallery • $countText";
        subtitleColor = const Color(0xFFFFD700);
        break;
      case GroupCategory.queenRashmika:
        subtitle = "Queen Rashmika Gallery • $countText";
        subtitleColor = const Color(0xFFFF4081);
        break;
      case GroupCategory.normal:
      case GroupCategory.all:
        subtitle = "Group Gallery • $countText";
        subtitleColor = tabColor;
        break;
    }

    return _buildTargetTile(
      target: target,
      isSelected: isSelected,
      subtitle: subtitle,
      subtitleColor: subtitleColor,
      isGallery: true,
      onTap: () => widget.onToggleTarget(target),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isLoading && _groups.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: tabColor, strokeWidth: 2),
      );
    }

    final query = widget.searchQuery.toLowerCase();
    final allMatching = _groups.where((g) {
      if (widget.payload.isFromGallery &&
          widget.payload.sourceGroupId == g.groupId) {
        return false;
      }
      if (query.isEmpty) return true;
      return g.name.toLowerCase().contains(query);
    }).toList();

    // Segregate by category
    final normalGroups = allMatching
        .where((g) => _getGroupCategory(g) == GroupCategory.normal)
        .toList();
    final poojaGroups = allMatching
        .where((g) => _getGroupCategory(g) == GroupCategory.queenPooja)
        .toList();
    final rashmikaGroups = allMatching
        .where((g) => _getGroupCategory(g) == GroupCategory.queenRashmika)
        .toList();

    return Column(
      children: [
        // ── Category Filter Bar ─────────────────────────────────────────────
        _buildCategoryFilterBar(
          selectedCategory: _selectedCategory,
          onCategoryChanged: (cat) => setState(() => _selectedCategory = cat),
          totalCount: allMatching.length,
          normalCount: normalGroups.length,
          poojaCount: poojaGroups.length,
          rashmikaCount: rashmikaGroups.length,
          isGallery: true,
        ),

        // ── Gallery List Content ────────────────────────────────────────────
        Expanded(
          child: _buildGalleryContent(
            allMatching: allMatching,
            normalGroups: normalGroups,
            poojaGroups: poojaGroups,
            rashmikaGroups: rashmikaGroups,
          ),
        ),
      ],
    );
  }

  Widget _buildGalleryContent({
    required List<GroupModel> allMatching,
    required List<GroupModel> normalGroups,
    required List<GroupModel> poojaGroups,
    required List<GroupModel> rashmikaGroups,
  }) {
    if (allMatching.isEmpty) {
      return Center(
        child: Text(
          widget.searchQuery.isEmpty
              ? 'No group galleries found'
              : 'No matches for "${widget.searchQuery}"',
          style: const TextStyle(color: Colors.white38, fontSize: 13),
        ),
      );
    }

    switch (_selectedCategory) {
      case GroupCategory.normal:
        if (normalGroups.isEmpty) {
          return const Center(
            child: Text('No normal group galleries found',
                style: TextStyle(color: Colors.white38, fontSize: 13)),
          );
        }
        return ListView.builder(
          itemCount: normalGroups.length,
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemBuilder: (_, i) => _buildGalleryTile(normalGroups[i]),
        );

      case GroupCategory.queenPooja:
        if (poojaGroups.isEmpty) {
          return const Center(
            child: Text("No Queen Pooja galleries found",
                style: TextStyle(color: Colors.white38, fontSize: 13)),
          );
        }
        return ListView.builder(
          itemCount: poojaGroups.length,
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemBuilder: (_, i) => _buildGalleryTile(poojaGroups[i]),
        );

      case GroupCategory.queenRashmika:
        if (rashmikaGroups.isEmpty) {
          return const Center(
            child: Text("No Queen Rashmika galleries found",
                style: TextStyle(color: Colors.white38, fontSize: 13)),
          );
        }
        return ListView.builder(
          itemCount: rashmikaGroups.length,
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemBuilder: (_, i) => _buildGalleryTile(rashmikaGroups[i]),
        );

      case GroupCategory.all:
        // Categorized view with section headers
        final List<Widget> items = [];

        if (poojaGroups.isNotEmpty) {
          items.add(_buildSectionHeader(
            title: "QUEEN POOJA GALLERIES",
            color: const Color(0xFFFFD700),
            count: poojaGroups.length,
          ));
          for (final g in poojaGroups) {
            items.add(_buildGalleryTile(g));
          }
        }

        if (rashmikaGroups.isNotEmpty) {
          items.add(_buildSectionHeader(
            title: "QUEEN RASHMIKA GALLERIES",
            color: const Color(0xFFFF4081),
            count: rashmikaGroups.length,
          ));
          for (final g in rashmikaGroups) {
            items.add(_buildGalleryTile(g));
          }
        }

        if (normalGroups.isNotEmpty) {
          items.add(_buildSectionHeader(
            title: "NORMAL GROUP GALLERIES",
            color: const Color(0xFFC070D0),
            count: normalGroups.length,
          ));
          for (final g in normalGroups) {
            items.add(_buildGalleryTile(g));
          }
        }

        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 4),
          children: items,
        );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ── Category Filter Bar & Pill Component ─────────────────────────────────────
// ─────────────────────────────────────────────────────────────────────────────

Widget _buildCategoryFilterBar({
  required GroupCategory selectedCategory,
  required ValueChanged<GroupCategory> onCategoryChanged,
  required int totalCount,
  required int normalCount,
  required int poojaCount,
  required int rashmikaCount,
  bool isGallery = false,
}) {
  return Container(
    height: 40,
    margin: const EdgeInsets.only(bottom: 4),
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      children: [
        _buildFilterPill(
          label: 'All ($totalCount)',
          isSelected: selectedCategory == GroupCategory.all,
          onTap: () => onCategoryChanged(GroupCategory.all),
          accentColor: tabColor,
        ),
        const SizedBox(width: 8),
        _buildFilterPill(
          label: 'Normal ($normalCount)',
          isSelected: selectedCategory == GroupCategory.normal,
          onTap: () => onCategoryChanged(GroupCategory.normal),
          accentColor: const Color(0xFFC070D0),
        ),
        const SizedBox(width: 8),
        _buildFilterPill(
          label: "Queen Pooja ($poojaCount)",
          isSelected: selectedCategory == GroupCategory.queenPooja,
          onTap: () => onCategoryChanged(GroupCategory.queenPooja),
          accentColor: const Color(0xFFFFD700),
        ),
        const SizedBox(width: 8),
        _buildFilterPill(
          label: "Queen Rashmika ($rashmikaCount)",
          isSelected: selectedCategory == GroupCategory.queenRashmika,
          onTap: () => onCategoryChanged(GroupCategory.queenRashmika),
          accentColor: const Color(0xFFFF4081),
        ),
      ],
    ),
  );
}

Widget _buildFilterPill({
  required String label,
  IconData? icon,
  required bool isSelected,
  required VoidCallback onTap,
  required Color accentColor,
}) {
  return GestureDetector(
    onTap: () {
      HapticFeedback.selectionClick();
      onTap();
    },
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isSelected
            ? accentColor.withValues(alpha: 0.2)
            : const Color(0xFF1B172A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSelected
              ? accentColor.withValues(alpha: 0.8)
              : Colors.white.withValues(alpha: 0.1),
          width: isSelected ? 1.4 : 1.0,
        ),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: accentColor.withValues(alpha: 0.25),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon,
                size: 13, color: isSelected ? accentColor : Colors.white60),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.white70,
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _buildSectionHeader({
  required String title,
  IconData? icon,
  required Color color,
  required int count,
}) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.3,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// ── Shared Target Tile ───────────────────────────────────────────────────────
// ─────────────────────────────────────────────────────────────────────────────

Widget _buildTargetTile({
  required ForwardTarget target,
  required bool isSelected,
  required String subtitle,
  required VoidCallback onTap,
  bool isGallery = false,
  Color? subtitleColor,
}) {
  return InkWell(
    onTap: onTap,
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
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: subtitleColor ??
                        (isGallery ? tabColor : Colors.white38),
                    fontSize: 12,
                    fontWeight: subtitleColor != null
                        ? FontWeight.w500
                        : FontWeight.normal,
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
