import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:math' as math;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worship_chat/common/utils/firebase_notification_service.dart';
import 'package:worship_chat/common/enums/message_status_enum.dart';
import 'package:worship_chat/common/providers/message_reply_provider.dart';
import 'package:worship_chat/common/providers/message_edit_provider.dart';
import 'package:worship_chat/common/widgets/skeleton_loader.dart';
import 'package:worship_chat/features/auth/controller/auth_controller.dart';
import 'package:worship_chat/features/chat/widgets/chat_power_ups.dart';
import 'package:worship_chat/features/chat/widgets/delete_message_dialog.dart';
import 'package:worship_chat/features/chat/widgets/media_group_widget.dart';
import 'package:worship_chat/features/chat/widgets/sender_message_card.dart';
import 'package:worship_chat/features/group/controller/group_controller.dart';
import 'package:worship_chat/models/group_chat_message_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/widgets/user_avatar.dart';
import 'package:worship_chat/features/chat/widgets/forward_message_sheet.dart';
import 'package:worship_chat/features/chat/widgets/my_message_card.dart';
import 'package:worship_chat/features/group/widgets/roleplay_message_card.dart';
import 'package:worship_chat/models/user_model.dart';

final _groupUserProvider =
    FutureProvider.family<UserModel?, String>((ref, userId) async {
  if (userId.isEmpty) return null;

  String? currentAuthId;
  try {
    currentAuthId = FirebaseAuth.instance.currentUser?.uid;
  } catch (_) {}
  if (currentAuthId != null && userId == currentAuthId) {
    if (Hive.isBoxOpen('userBox')) {
      final currentUser = Hive.box<UserModel>('userBox').get('currentUser');
      if (currentUser != null) return currentUser;
    }
  }

  if (Hive.isBoxOpen('userBox')) {
    final cached = Hive.box<UserModel>('userBox').get(userId);
    if (cached != null) return cached;
  }

  try {
    final doc =
        await FirebaseFirestore.instance.collection('users').doc(userId).get();
    if (doc.exists && doc.data() != null) {
      final user = UserModel.fromMap(doc.data()!);
      if (Hive.isBoxOpen('userBox')) {
        Hive.box<UserModel>('userBox').put(userId, user);
      }
      return user;
    }
  } catch (e) {
    debugPrint('Error fetching user for group avatar: $e');
  }
  return null;
});

class GroupChatListWidget extends ConsumerStatefulWidget {
  final String groupId;
  final Color? accentColor;
  final String? queendom;
  final ChatPowerUpController? powerUpController;

  const GroupChatListWidget({
    super.key,
    required this.groupId,
    this.accentColor,
    this.queendom,
    this.powerUpController,
  });

  @override
  ConsumerState<GroupChatListWidget> createState() =>
      _GroupChatListWidgetState();
}

class _GroupChatListWidgetState extends ConsumerState<GroupChatListWidget>
    with AutomaticKeepAliveClientMixin {
  final ScrollController messageController = ScrollController();
  final ChatScrollToBottomController _scrollBottomController =
      ChatScrollToBottomController();
  final Set<String> _processedMessages = {};
  bool _isAtBottom = true;
  String? _lastMessageId;
  String _currentUserProfilePic = "";
  List<GroupChatMessageModel> _displayMessages = [];
  StreamSubscription<List<GroupChatMessageModel>>? _chatSubscription;
  bool _isInitialLoad = true;

  // ── Scroll to Load (Pagination) ──────────────────────────────────────────
  static const int _pageSize = 45;
  int _visibleCount = _pageSize;
  int _prevTotalMessages = 0;
  bool _isLoadingMore = false;
  final Set<String> _initialMessageIds = <String>{};
  final Set<String> _newlyArrivedIds = <String>{};
  bool _hasRecordedInitialIds = false;
  final Map<String, GlobalKey> _messageKeys = {};
  String? _highlightedMessageId;
  Timer? _highlightTimer;
  int _jumpGeneration = 0;

  GlobalKey _getMessageKey(String messageId) {
    return _messageKeys.putIfAbsent(messageId, () => GlobalKey());
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.powerUpController?.attachJumpHandler(_scrollToAndHighlightMessage);
    _initializeUserProfile();
    _loadInitialCachedMessages();
    _setupScrollListener();
    _subscribeToStream();
  }

  void _pushPowerUpMessages() {
    final controller = widget.powerUpController;
    if (controller == null) return;
    final uid = _resolveCurrentUserId() ?? '';
    Box<UserModel>? userBox;
    try {
      if (Hive.isBoxOpen('userBox')) {
        userBox = Hive.box<UserModel>('userBox');
      }
    } catch (_) {}

    final summaries = _displayMessages.map((m) {
      String? senderName;
      if (m.senderId.isNotEmpty &&
          m.senderId != uid &&
          m.senderId != 'roleplay') {
        senderName = userBox?.get(m.senderId)?.name;
      }
      return ChatMessageSummary.fromGroup(
        m,
        currentUserId: uid,
        senderName: senderName,
      );
    }).toList(growable: false);

    controller.updateMessages(summaries);
  }

  void _subscribeToStream() {
    _chatSubscription?.cancel();
    final stream =
        ref.read(groupControllerProvider).getGroupChat(widget.groupId);
    _chatSubscription = stream.listen(
      _onNewMessages,
      onError: (e) {
        log('❌ Group chat stream error: $e');
        if (mounted && _isInitialLoad) {
          setState(() => _isInitialLoad = false);
        }
      },
    );
  }

  void _initializeUserProfile() {
    try {
      if (Hive.isBoxOpen('userBox')) {
        final userBox = Hive.box<UserModel>('userBox');
        final user = userBox.get('currentUser');
        _currentUserProfilePic = user?.profilePic ?? "";
      }
    } catch (e) {
      log('Error loading user profile: $e');
    }
  }

  @override
  void didUpdateWidget(covariant GroupChatListWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.powerUpController != widget.powerUpController) {
      oldWidget.powerUpController
          ?.detachJumpHandler(_scrollToAndHighlightMessage);
      widget.powerUpController?.attachJumpHandler(_scrollToAndHighlightMessage);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _pushPowerUpMessages();
      });
    }
    if (oldWidget.groupId != widget.groupId) {
      _jumpGeneration++;
      _highlightTimer?.cancel();
      _highlightedMessageId = null;
      _displayMessages = [];
      _isInitialLoad = true;
      _visibleCount = _pageSize;
      _prevTotalMessages = 0;
      _lastMessageId = null;
      _isLoadingMore = false;
      _hasRecordedInitialIds = false;
      _initialMessageIds.clear();
      _newlyArrivedIds.clear();
      _messageKeys.clear();
      _scrollBottomController.reset();
      _loadInitialCachedMessages();
      _subscribeToStream();
    }
  }

  void _loadInitialCachedMessages() {
    try {
      final currentUserId = _resolveCurrentUserId();
      final localKey = widget.groupId;
      if (Hive.isBoxOpen('messages')) {
        final box = Hive.box('messages');
        final cachedData = box.get(localKey, defaultValue: []);
        if (cachedData is List && cachedData.isNotEmpty) {
          final List<GroupChatMessageModel> parsed = [];
          bool hasUnseenIncoming = false;
          for (final item in cachedData) {
            GroupChatMessageModel? m;
            if (item is GroupChatMessageModel) {
              m = item;
            } else if (item is Map) {
              try {
                m = GroupChatMessageModel.fromMap(
                    Map<String, dynamic>.from(item));
              } catch (_) {}
            }
            if (m != null) {
              // Optimistically mark incoming unseen messages as seen immediately on chat open
              if (currentUserId != null && m.senderId != currentUserId && (!m.isSeen || !m.isDelivered)) {
                hasUnseenIncoming = true;
                m = m.copyWith(isSeen: true, isDelivered: true);
              }
              parsed.add(m);
            }
          }
          if (parsed.isNotEmpty) {
            _displayMessages = parsed;
            _lastMessageId = _displayMessages.last.messageId;
            _prevTotalMessages = _displayMessages.length;
            _initialMessageIds.addAll(parsed.map((m) => m.messageId));
            _hasRecordedInitialIds = true;
            _isInitialLoad = false;
            log('⚡ Pre-seeded ${_displayMessages.length} group messages from Hive in initState');
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _pushPowerUpMessages();
            });

            if (hasUnseenIncoming) {
              box.put(localKey, parsed).catchError((e) {
                log('Note: Error saving optimistically seen group messages to Hive: $e');
              });
            }
          }
        }
      }

      // Merge any pending background notification replies from SharedPreferences
      SharedPreferences.getInstance().then((prefs) {
        final pending =
            FirebaseNotificationService.getPendingBackgroundRepliesForChat<
                GroupChatMessageModel>(
          chatId: localKey,
          isGroup: true,
          prefs: prefs,
        );
        if (pending.isNotEmpty && mounted) {
          bool anyAdded = false;
          for (final m in pending) {
            if (!_displayMessages.any((x) => x.messageId == m.messageId)) {
              _displayMessages.add(m);
              anyAdded = true;
            }
          }
          if (anyAdded) {
            _displayMessages.sort((a, b) => a.timeSent.compareTo(b.timeSent));
            _lastMessageId = _displayMessages.last.messageId;
            _prevTotalMessages = _displayMessages.length;
            _initialMessageIds.addAll(_displayMessages.map((m) => m.messageId));
            setState(() {
              _isInitialLoad = false;
            });
            _pushPowerUpMessages();
            FirebaseNotificationService.syncPendingBackgroundRepliesToHive(
                specificChatId: localKey);
          }
        }
      });
    } catch (e) {
      log('Error pre-seeding cached group messages: $e');
    }
  }

  void _setupScrollListener() {
    messageController.addListener(() {
      if (!messageController.hasClients) return;
      final position = messageController.position;
      final atBottom = position.pixels <= 10.0;
      if (atBottom != _isAtBottom) {
        _isAtBottom = atBottom;
      }
      _scrollBottomController.handleScroll(position);

      // Check if user is scrolling up towards older messages (near top in reverse list)
      if (position.pixels >= position.maxScrollExtent - 250 &&
          _visibleCount < _displayMessages.length) {
        _loadMoreMessages();
      }
    });
  }

  void _loadMoreMessages() {
    if (_isLoadingMore || _visibleCount >= _displayMessages.length) return;
    _isLoadingMore = true;
    setState(() {
      _visibleCount =
          (_visibleCount + _pageSize).clamp(0, _displayMessages.length);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _isLoadingMore = false;
    });
  }

  @override
  void dispose() {
    _jumpGeneration++;
    widget.powerUpController?.detachJumpHandler(_scrollToAndHighlightMessage);
    _scrollBottomController.dispose();
    _chatSubscription?.cancel();
    _highlightTimer?.cancel();
    messageController.dispose();
    super.dispose();
  }

  void onMessageSwipe(
    String message,
    bool isMe,
    String messageType,
    String fileMessageData,
  ) {
    final effectiveMessage = (messageType == 'text' || messageType == 'wish')
        ? message
        : (message.isNotEmpty && fileMessageData.isEmpty
            ? message
            : fileMessageData);
    ref.read(messageReplyProvider.notifier).state = MessageReply(
      message: effectiveMessage,
      isMe: isMe,
      messageType: messageType,
      fileMessageData: fileMessageData,
    );
  }

  void _navigateToRepliedMessage(GroupChatMessageModel sourceMessage) {
    final repliedText = sourceMessage.repliedMessage.trim();
    final repliedType = sourceMessage.repliedMessageType;
    if (repliedText.isEmpty && repliedType.isEmpty) return;

    final sourceIdx = _displayMessages.indexWhere(
      (m) => m.messageId == sourceMessage.messageId,
    );

    int targetIdx = -1;
    final searchLimit = sourceIdx > 0 ? sourceIdx : _displayMessages.length;

    // Search backwards from the replying message
    for (int i = searchLimit - 1; i >= 0; i--) {
      final m = _displayMessages[i];
      final textMatch = (m.text.isNotEmpty && m.text == repliedText) ||
          (m.fileMessageData != null && m.fileMessageData == repliedText) ||
          (m.text.isNotEmpty &&
              (m.text.startsWith(repliedText) ||
                  repliedText.startsWith(m.text)));

      if (textMatch) {
        targetIdx = i;
        break;
      }
    }

    // Fallback search across all messages if not found before source
    if (targetIdx == -1) {
      for (int i = _displayMessages.length - 1; i >= 0; i--) {
        if (i == sourceIdx) continue;
        final m = _displayMessages[i];
        if ((m.text.isNotEmpty && m.text == repliedText) ||
            (m.fileMessageData != null && m.fileMessageData == repliedText)) {
          targetIdx = i;
          break;
        }
      }
    }

    if (targetIdx == -1) {
      log('⚠️ Target replied message not found in history');
      return;
    }

    final targetMessage = _displayMessages[targetIdx];

    // Check pagination: if target is older than visible window, expand _visibleCount
    final totalCount = _displayMessages.length;
    final effectiveCount = _visibleCount.clamp(0, totalCount);
    final startIndex =
        totalCount > effectiveCount ? totalCount - effectiveCount : 0;

    if (targetIdx < startIndex) {
      final neededCount =
          (totalCount - targetIdx + 15).clamp(_pageSize, totalCount);
      setState(() {
        _visibleCount = math.max(_visibleCount, neededCount);
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToAndHighlightMessage(targetMessage.messageId);
    });
  }

  void _scrollToAndHighlightMessage(String targetMessageId) {
    _runConvergentJump(targetMessageId, ++_jumpGeneration);
  }

  void _runConvergentJump(String targetMessageId, int generation) {
    if (!mounted || generation != _jumpGeneration) return;

    final totalCount = _displayMessages.length;
    final targetIdx =
        _displayMessages.indexWhere((m) => m.messageId == targetMessageId);
    if (targetIdx < 0) return;

    final currentStart =
        totalCount > _visibleCount ? totalCount - _visibleCount : 0;
    if (targetIdx < currentStart) {
      final neededCount =
          (totalCount - targetIdx + 15).clamp(_pageSize, totalCount);
      setState(() {
        _visibleCount = math.max(_visibleCount, neededCount);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _runConvergentJump(targetMessageId, generation);
      });
      return;
    }

    List<_GroupChatRow> computeVisibleRows() {
      final total = _displayMessages.length;
      final eff = _visibleCount.clamp(0, total);
      final start = total > eff ? total - eff : 0;
      final visible = _displayMessages.sublist(start);
      final uid = _resolveCurrentUserId();
      return _buildRows(visible, _displayMessages, start, uid);
    }

    ChatListJumpHelper.convergeToMessage(
      generation: generation,
      currentGeneration: () => _jumpGeneration,
      isMounted: () => mounted,
      scrollController: messageController,
      targetMessageId: targetMessageId,
      keyForPrimaryId: _getMessageKey,
      onHighlight: _triggerMessageHighlight,
      lookupTargetRow: () {
        final rows = computeVisibleRows();
        for (int i = 0; i < rows.length; i++) {
          if (rows[i].messages.any((m) => m.messageId == targetMessageId)) {
            return ChatRowLookup(
              rowCount: rows.length,
              targetRowIndex: i,
              primaryMessageId: rows[i].messages.first.messageId,
            );
          }
        }
        return null;
      },
      orderedPrimaryIds: () {
        final rows = computeVisibleRows();
        return rows
            .map((r) => r.messages.first.messageId)
            .toList(growable: false);
      },
    );
  }

  void _triggerMessageHighlight(String targetMessageId) {
    _highlightTimer?.cancel();
    setState(() {
      _highlightedMessageId = targetMessageId;
    });
    _highlightTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted && _highlightedMessageId == targetMessageId) {
        setState(() {
          _highlightedMessageId = null;
        });
      }
    });
  }

  String? _resolveCurrentUserId() {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null && uid.isNotEmpty) return uid;
    } catch (_) {}
    return ref.watch(userDataAuthProvider).value?.uid;
  }

  void _markMessageAsSeen(GroupChatMessageModel message) {
    final currentUserId = _resolveCurrentUserId();

    if (currentUserId != null &&
        message.senderId != currentUserId &&
        !message.isSeen &&
        !_processedMessages.contains(message.messageId)) {
      _processedMessages.add(message.messageId);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref
              .read(groupControllerProvider)
              .setChatMessageSeen(context, widget.groupId, message.messageId);
        }
      });
    }
  }

  void _scrollToBottom() {
    if (!messageController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (messageController.hasClients && mounted) {
        messageController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _getDateSeparatorText(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDate = DateTime(date.year, date.month, date.day);

    if (messageDate == today) return 'Today';
    if (messageDate == yesterday) return 'Yesterday';
    if (now.difference(messageDate).inDays < 7) {
      return DateFormat('EEEE').format(date);
    }
    if (date.year == now.year) return DateFormat('MMMM d').format(date);
    return DateFormat('MMMM d, y').format(date);
  }

  bool _shouldShowDateSeparator(
    GroupChatMessageModel currentMessage,
    GroupChatMessageModel? previousMessage,
  ) {
    if (previousMessage == null) return true;
    final currentDate = DateTime(
      currentMessage.timeSent.year,
      currentMessage.timeSent.month,
      currentMessage.timeSent.day,
    );
    final previousDate = DateTime(
      previousMessage.timeSent.year,
      previousMessage.timeSent.month,
      previousMessage.timeSent.day,
    );
    return currentDate != previousDate;
  }

  // ✅ Check if delivery, sending, seen, text, fileMessageData, or reactions changed on any message
  bool _hasDeliveryOrSeenStatusChanged(List<GroupChatMessageModel> newMessages) {
    if (_displayMessages.length != newMessages.length) return true;
    for (int i = 0; i < newMessages.length; i++) {
      final oldMsg = _displayMessages[i];
      final newMsg = newMessages[i];
      if (oldMsg.messageId != newMsg.messageId ||
          oldMsg.messageType != newMsg.messageType ||
          oldMsg.text != newMsg.text ||
          oldMsg.fileMessageData != newMsg.fileMessageData ||
          oldMsg.isEdited != newMsg.isEdited ||
          oldMsg.isDeleted != newMsg.isDeleted ||
          oldMsg.isPinned != newMsg.isPinned ||
          oldMsg.pinnedAt != newMsg.pinnedAt ||
          oldMsg.pinnedBy != newMsg.pinnedBy ||
          !mapEquals(oldMsg.reactions, newMsg.reactions)) {
        return true;
      }
      if (oldMsg.isSeen != newMsg.isSeen ||
          oldMsg.isDelivered != newMsg.isDelivered ||
          oldMsg.isSending != newMsg.isSending) {
        return true;
      }
    }
    return false;
  }

  void _onNewMessages(List<GroupChatMessageModel> newMessages) {
    if (!mounted) return;

    final currentUserId = _resolveCurrentUserId();
    if (currentUserId != null) {
      final hasUnseenIncoming = newMessages.any(
        (m) => m.senderId != currentUserId && !m.isSeen,
      );
      if (hasUnseenIncoming) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref
                .read(groupControllerProvider)
                .markGroupAsSeen(widget.groupId);
          }
        });
      }
    }

    // Skip redundant rebuild if incoming messages have no visual changes
    if (_displayMessages.isNotEmpty && !_hasDeliveryOrSeenStatusChanged(newMessages)) {
      _displayMessages = newMessages; // Silently update backing models
      _isInitialLoad = false;
      _pushPowerUpMessages();
      return;
    }

    final newLastMessageId =
        newMessages.isNotEmpty ? newMessages.last.messageId : null;
    final oldMessageCount = _displayMessages.length;
    final hasNewMessage = newMessages.length > oldMessageCount ||
        (newMessages.isNotEmpty && newLastMessageId != _lastMessageId);
    final hasStatusChanges = _hasDeliveryOrSeenStatusChanged(newMessages);
    final addedCount = newMessages.length - _prevTotalMessages;

    int newTailCount = 0;
    if (_hasRecordedInitialIds && _lastMessageId != null && newMessages.isNotEmpty) {
      final oldLastIdxInNew =
          newMessages.lastIndexWhere((m) => m.messageId == _lastMessageId);
      if (oldLastIdxInNew >= 0) {
        newTailCount = newMessages.length - 1 - oldLastIdxInNew;
      } else if (addedCount > 0 && _prevTotalMessages >= _pageSize) {
        newTailCount = addedCount;
      }
    }

    if (!_hasRecordedInitialIds) {
      _initialMessageIds.addAll(newMessages.map((m) => m.messageId));
      _hasRecordedInitialIds = true;
    } else {
      for (final m in newMessages) {
        if (!_initialMessageIds.contains(m.messageId)) {
          _newlyArrivedIds.add(m.messageId);
          _initialMessageIds.add(m.messageId);
        }
      }
    }

    setState(() {
      if (newTailCount > 0 && _prevTotalMessages > 0) {
        _visibleCount = math.max(_pageSize, _visibleCount + newTailCount);
      } else if (_visibleCount < _pageSize) {
        _visibleCount = _pageSize;
      }

      _prevTotalMessages = newMessages.length;
      _lastMessageId = newLastMessageId;
      _displayMessages = newMessages;
      _isInitialLoad = false;
    });
    _pushPowerUpMessages();

    if (_isAtBottom && (hasNewMessage || hasStatusChanges)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToBottom();
      });
    } else if (!_isAtBottom && hasNewMessage) {
      _scrollBottomController.notifyIncomingMessages(
        newTailCount > 0 ? newTailCount : 1,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // Show skeleton only on the very first load before any data arrives.
    if (_isInitialLoad && _displayMessages.isEmpty) {
      return const ChatMessagesSkeleton();
    }

    if (_displayMessages.isEmpty) {
      return _buildEmptyState();
    }

    return _buildMessageList(_displayMessages);
  }

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    tabColor.withValues(alpha: 0.6),
                    Colors.purpleAccent.withValues(alpha: 0.4),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: tabColor.withValues(alpha: 0.25),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(
                Icons.groups_rounded,
                size: 48,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'No messages yet',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Start the conversation with your group members! 💬',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.65),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageList(List<GroupChatMessageModel> allMessages) {
    if (allMessages.isEmpty) {
      return _buildEmptyState();
    }

    final totalCount = allMessages.length;
    final effectiveCount = _visibleCount.clamp(0, totalCount);
    final startIndex =
        totalCount > effectiveCount ? totalCount - effectiveCount : 0;
    final visibleMessages = allMessages.sublist(startIndex);
    final hasMore = startIndex > 0;
    final currentUserId = _resolveCurrentUserId();

    final List<_GroupChatRow> rows = _buildRows(
      visibleMessages,
      allMessages,
      startIndex,
      currentUserId,
    );

    ChatPaginationHelper.scheduleUnderfilledCheck(
      scrollController: messageController,
      hasMore: hasMore,
      isLoadingMore: _isLoadingMore,
      onLoadMore: () {
        if (mounted) _loadMoreMessages();
      },
    );

    return Stack(
      children: [
        NotificationListener<OverscrollIndicatorNotification>(
          onNotification: (notification) {
            notification.disallowIndicator();
            return true;
          },
          child: ListView.builder(
            controller: messageController,
            reverse: true,
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: rows.length + (hasMore ? 1 : 0),
            findChildIndexCallback: (Key key) {
              if (key is ValueKey<String>) {
                final keyVal = key.value;
                for (int i = 0; i < rows.length; i++) {
                  final revIndex = rows.length - 1 - i;
                  if (rows[revIndex].messages.any((m) => keyVal.startsWith('group_item_${m.messageId}'))) {
                    return i;
                  }
                }
              }
              return null;
            },
            itemBuilder: (context, index) {
              // Top spinner for loading older messages in reverse list
              if (index == rows.length) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: tabColor,
                      ),
                    ),
                  ),
                );
              }

              final reversedIndex = rows.length - 1 - index;
              final row = rows[reversedIndex];

              if (currentUserId == null) return const SizedBox.shrink();

              for (final m in row.messages) {
                _markMessageAsSeen(m);
              }

              final rowReactionsKey = row.messages
                  .map((m) =>
                      '${m.isPinned}:${m.reactions.entries.map((e) => '${e.key}:${e.value}').join(',')}')
                  .join(';');

              final isNewlyArrived = row.messages.any((m) => _newlyArrivedIds.remove(m.messageId)) ||
                  (index == 0 &&
                      (DateTime.now()
                              .difference(row.messages.last.timeSent)
                              .inSeconds
                              .abs() <
                          5));

              final primaryMsgId = row.messages.first.messageId;
              for (final m in row.messages) {
                _messageKeys[m.messageId] = _getMessageKey(primaryMsgId);
              }

              final isHighlighted = _highlightedMessageId != null &&
                  row.messages.any((m) => m.messageId == _highlightedMessageId);

              // RepaintBoundary isolates each row's raster cache so that when
              // a new message arrives, only the new/changed rows repaint —
              // video and link preview rows are NOT repainted at all.
              final rowWidget = RepaintBoundary(
                key: ValueKey('group_item_$primaryMsgId'),
                child: _GroupMessageItemWidget(
                  key: ValueKey(
                    '${row.key}_$rowReactionsKey',
                  ),
                  row: row,
                  isNewlySent: isNewlyArrived,
                  currentUserId: currentUserId,
                  currentUserProfilePic: _currentUserProfilePic,
                  isMyMessage: row.isMyMessage,
                  showDateSeparator: row.showDateSeparator,
                  onMessageSwipe: onMessageSwipe,
                  getDateSeparatorText: _getDateSeparatorText,
                  accentColor: widget.accentColor,
                  queendom: widget.queendom,
                  onReplyTap: () => _navigateToRepliedMessage(row.messages.first),
                ),
              );

              if (isHighlighted) {
                return KeyedSubtree(
                  key: _getMessageKey(primaryMsgId),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: const Color(0xFFFFD700).withValues(alpha: 0.25),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFFD700).withValues(alpha: 0.40),
                          blurRadius: 18,
                          spreadRadius: 3,
                        ),
                      ],
                    ),
                    child: rowWidget,
                  ),
                );
              }

              return KeyedSubtree(
                key: _getMessageKey(primaryMsgId),
                child: rowWidget,
              );
            },
          ),
        ),
        ChatScrollToBottomButton(
          controller: _scrollBottomController,
          scrollController: messageController,
          accentColor: widget.accentColor ?? tabColor,
        ),
      ],
    );
  }

  /// Build a flat list of _GroupChatRow objects, merging consecutive messages that
  /// share the same senderId + mediaGroupId into a single row.
  List<_GroupChatRow> _buildRows(
    List<GroupChatMessageModel> visibleMessages,
    List<GroupChatMessageModel> allMessages,
    int startIndex,
    String? currentUserId,
  ) {
    final rows = <_GroupChatRow>[];

    for (int i = 0; i < visibleMessages.length; i++) {
      final msg = visibleMessages[i];
      final globalIndex = startIndex + i;
      final prevMsg = globalIndex > 0 ? allMessages[globalIndex - 1] : null;
      final showDateSep = _shouldShowDateSeparator(msg, prevMsg);
      final isMyMessage = msg.senderId == currentUserId;
      final mediaGroupId = _getGroupMediaId(msg.fileMessageData);
      final isMedia = msg.messageType == 'image' || msg.messageType == 'video';

      if (isMedia && mediaGroupId != null && mediaGroupId.isNotEmpty && !showDateSep) {
        // Check if the last row has the same groupId from the same sender
        if (rows.isNotEmpty &&
            rows.last.groupId == mediaGroupId &&
            rows.last.isMyMessage == isMyMessage) {
          rows.last.messages.add(msg);
          continue;
        }
      }

      rows.add(_GroupChatRow(
        messages: [msg],
        isMyMessage: isMyMessage,
        groupId: mediaGroupId,
        showDateSeparator: showDateSep,
      ));
    }

    return rows;
  }
}

String? _getGroupMediaId(String? fileMessageData) {
  if (fileMessageData == null) return null;
  try {
    final map = jsonDecode(fileMessageData);
    if (map is Map && map.containsKey('groupId')) {
      return map['groupId']?.toString();
    }
  } catch (_) {}
  return null;
}

String _extractGroupFileUrl(String? fileMessageData) {
  if (fileMessageData == null || fileMessageData.isEmpty) return '';
  try {
    final map = jsonDecode(fileMessageData);
    if (map is Map && map.containsKey('url')) {
      return map['url']?.toString() ?? '';
    }
  } catch (_) {}
  return fileMessageData;
}

/// A logical chat row in group chat – may contain 1 message or several grouped media messages.
class _GroupChatRow {
  final List<GroupChatMessageModel> messages;
  final bool isMyMessage;
  final String? groupId;
  bool showDateSeparator;

  _GroupChatRow({
    required this.messages,
    required this.isMyMessage,
    required this.groupId,
    required this.showDateSeparator,
  });

  String get key {
    if (messages.length == 1) return messages.first.messageId;
    return '${groupId ?? messages.first.messageId}_${messages.length}';
  }
}

class _GroupMessageItemWidget extends ConsumerWidget {
  final _GroupChatRow row;
  final bool isNewlySent;
  final String currentUserId;
  final String currentUserProfilePic;
  final bool isMyMessage;
  final bool showDateSeparator;
  final Function(String, bool, String, String) onMessageSwipe;
  final String Function(DateTime) getDateSeparatorText;
  final Color? accentColor;
  final String? queendom;
  final VoidCallback? onReplyTap;

  const _GroupMessageItemWidget({
    super.key,
    required this.row,
    this.isNewlySent = false,
    required this.currentUserId,
    required this.currentUserProfilePic,
    required this.isMyMessage,
    required this.showDateSeparator,
    required this.onMessageSwipe,
    required this.getDateSeparatorText,
    this.accentColor,
    this.queendom,
    this.onReplyTap,
  });

  Widget _buildProfileAvatar(String? profilePic, bool isCurrentUser) {
    final padding = isCurrentUser
        ? const EdgeInsets.only(left: 2.0, right: 6.0, bottom: 2.0)
        : const EdgeInsets.only(left: 6.0, right: 2.0, bottom: 2.0);
    final pic = profilePic ?? '';
    return Padding(
      padding: padding,
      child: UserAvatar(url: pic.isNotEmpty ? pic : null, radius: 17.5),
    );
  }

  Widget _buildDateSeparator(DateTime date) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          getDateSeparatorText(date),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final firstMsg = row.messages.first;
    final lastMsg = row.messages.last;
    final timeSent = DateFormat.jm().format(lastMsg.timeSent);
    final seen = lastMsg.isSeen;
    final delivered = lastMsg.isDelivered;
    final sending = lastMsg.isSending;

    final isRoleplay = firstMsg.messageType == 'roleplay' ||
        firstMsg.senderId == 'roleplay';

    if (isRoleplay) {
      final reactionsKey = firstMsg.reactions.entries
          .map((e) => '${e.key}:${e.value}')
          .join('_');
      return Column(
        children: [
          if (showDateSeparator) _buildDateSeparator(firstMsg.timeSent),
          RoleplayMessageCard(
            key: ValueKey(
              'roleplay_${firstMsg.messageId}_${firstMsg.isPinned}_$reactionsKey',
            ),
            messageData: firstMsg,
            isNewlySent: isNewlySent,
            isPinned: firstMsg.isPinned,
            accentColor: accentColor,
            queendom: queendom,
            onPin: () {
              ref.read(groupControllerProvider).togglePinGroupMessage(
                    groupId: firstMsg.groupId,
                    messageId: firstMsg.messageId,
                    pin: !firstMsg.isPinned,
                  );
            },
            onSwipe: () => onMessageSwipe(
              firstMsg.text.isNotEmpty ? firstMsg.text : 'Roleplay photo',
              false,
              'image',
              firstMsg.fileMessageData ?? '',
            ),
            onForward: () {
              ForwardMessageSheet.show(
                context,
                ForwardMessagePayload(
                  text: firstMsg.text,
                  messageType: 'image',
                  fileMessageData: firstMsg.fileMessageData,
                  sourceGroupId: firstMsg.groupId,
                ),
              );
            },
            onDelete: () {
              DeleteMessageDialog.show(
                context: context,
                isMyMessage: false,
                isDeleted: firstMsg.isDeleted,
                onDeleteForMe: () {
                  ref.read(groupControllerProvider).deleteGroupMessageForMe(
                        groupId: firstMsg.groupId,
                        messageId: firstMsg.messageId,
                      );
                },
              );
            },
            onReactionSelected: (emoji) {
              ref.read(groupControllerProvider).toggleGroupReaction(
                    groupId: firstMsg.groupId,
                    messageId: firstMsg.messageId,
                    emoji: emoji,
                  );
            },
          ),
        ],
      );
    }

    final senderUserAsync = isMyMessage
        ? null
        : ref.watch(_groupUserProvider(firstMsg.senderId));
    final senderPic = senderUserAsync?.value?.profilePic;
    final myPic = currentUserProfilePic.isNotEmpty
        ? currentUserProfilePic
        : ref.watch(_groupUserProvider(currentUserId)).value?.profilePic;

    // ── Is this a grouped media row? ─────────────────────────────────────────
    final isGroup = row.messages.length > 1 &&
        row.groupId != null &&
        (firstMsg.messageType == 'image' || firstMsg.messageType == 'video');

    if (isGroup) {
      final items = row.messages.map((m) {
        final url = _extractGroupFileUrl(m.fileMessageData);
        return MediaGroupItem(url: url, type: m.messageType);
      }).toList();

      final deliveryStatus = MessageDeliveryStatus.fromFlags(
        isSeen: seen,
        isDelivered: delivered,
        isSending: sending,
      );

      final screenWidth = MediaQuery.of(context).size.width;
      final maxW = screenWidth * 0.7;

      final groupWidget = MediaGroupWidget(
        key: ValueKey('group_${row.key}'),
        items: items,
        maxWidth: maxW,
        isMe: row.isMyMessage,
        date: timeSent,
        statusWidget: MessageStatusIcon(status: deliveryStatus, size: 14),
        caption: firstMsg.text,
      );

      return Column(
        children: [
          if (showDateSeparator)
            _buildDateSeparator(firstMsg.timeSent),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: row.isMyMessage
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      groupWidget,
                      _buildProfileAvatar(myPic, true),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _buildProfileAvatar(senderPic, false),
                      groupWidget,
                    ],
                  ),
          ),
        ],
      );
    }

    // ── Single message row (original behaviour) ───────────────────────────────
    final messageData = firstMsg;
    final reactionsKey = messageData.reactions.entries
        .map((e) => '${e.key}:${e.value}')
        .join('_');
    final extractedFileUrl = _extractGroupFileUrl(messageData.fileMessageData);

    return Column(
      children: [
        if (showDateSeparator) _buildDateSeparator(messageData.timeSent),
        isMyMessage
            ? Row(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(
                    child: MyMessageCard(
                      key: ValueKey(
                        'my_${messageData.messageId}_${messageData.isSending}_${messageData.isDelivered}_${messageData.isSeen}_${messageData.isPinned}_$reactionsKey',
                      ),
                      message: messageData.text,
                      date: timeSent,
                      messageType: messageData.messageType,
                      fileMessageData: extractedFileUrl,
                      repliedText: messageData.repliedMessage,
                      username: messageData.repliedTo,
                      repliedMessageType: messageData.repliedMessageType,
                      onLeftSwipe: () => onMessageSwipe(
                        messageData.text,
                        true,
                        messageData.messageType,
                        extractedFileUrl,
                      ),
                      isSeen: seen,
                      isDelivered: delivered,
                      isSending: sending,
                      isNewlySent: sending || isNewlySent,
                      messageId: messageData.messageId,
                      currentUserId: currentUserId,
                      reactions: messageData.reactions,
                      isEdited: messageData.isEdited,
                      isDeleted: messageData.isDeleted,
                      isPinned: messageData.isPinned,
                      onPin: () {
                        ref.read(groupControllerProvider).togglePinGroupMessage(
                              groupId: messageData.groupId,
                              messageId: messageData.messageId,
                              pin: !messageData.isPinned,
                            );
                      },
                      onEdit: (messageData.isDeleted || messageData.messageType != 'text')
                          ? null
                          : () {
                              ref.read(messageEditProvider.notifier).state =
                                  MessageEdit(
                                messageId: messageData.messageId,
                                text: messageData.text,
                                chatType: 'group',
                                groupId: messageData.groupId,
                              );
                            },
                      onDelete: () {
                        DeleteMessageDialog.show(
                          context: context,
                          isMyMessage: true,
                          isDeleted: messageData.isDeleted,
                          onDeleteForMe: () {
                            ref
                                .read(groupControllerProvider)
                                .deleteGroupMessageForMe(
                                  groupId: messageData.groupId,
                                  messageId: messageData.messageId,
                                );
                          },
                          onDeleteForEveryone: messageData.isDeleted
                              ? null
                              : () {
                                  ref
                                      .read(groupControllerProvider)
                                      .deleteGroupMessageForEveryone(
                                        groupId: messageData.groupId,
                                        messageId: messageData.messageId,
                                      );
                                },
                        );
                      },
                      onReactionSelected: (emoji) {
                        ref.read(groupControllerProvider).toggleGroupReaction(
                              groupId: messageData.groupId,
                              messageId: messageData.messageId,
                              emoji: emoji,
                            );
                      },
                      onForward: () {
                        ForwardMessageSheet.show(
                          context,
                          ForwardMessagePayload(
                            text: messageData.text,
                            messageType: messageData.messageType,
                            fileMessageData: extractedFileUrl,
                            sourceGroupId: messageData.groupId,
                          ),
                        );
                      },
                      onReplyTap: onReplyTap,
                    ),
                  ),
                  _buildProfileAvatar(myPic, true),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _buildProfileAvatar(senderPic, false),
                  Flexible(
                    child: SenderMessageCard(
                      key: ValueKey(
                        'sender_${messageData.messageId}_${messageData.isPinned}_$reactionsKey',
                      ),
                      message: messageData.text,
                      date: timeSent,
                      messageType: messageData.messageType,
                      fileMessageData: extractedFileUrl,
                      repliedText: messageData.repliedMessage,
                      username: messageData.repliedTo,
                      repliedMessageType: messageData.repliedMessageType,
                      onRightSwipe: () => onMessageSwipe(
                        messageData.text,
                        false,
                        messageData.messageType,
                        extractedFileUrl,
                      ),
                      isNewlyReceived: isNewlySent,
                      messageId: messageData.messageId,
                      currentUserId: currentUserId,
                      senderProfilePic: senderPic,
                      reactions: messageData.reactions,
                      isEdited: messageData.isEdited,
                      isDeleted: messageData.isDeleted,
                      isPinned: messageData.isPinned,
                      onPin: () {
                        ref.read(groupControllerProvider).togglePinGroupMessage(
                              groupId: messageData.groupId,
                              messageId: messageData.messageId,
                              pin: !messageData.isPinned,
                            );
                      },
                      onDelete: () {
                        DeleteMessageDialog.show(
                          context: context,
                          isMyMessage: false,
                          isDeleted: messageData.isDeleted,
                          onDeleteForMe: () {
                            ref
                                .read(groupControllerProvider)
                                .deleteGroupMessageForMe(
                                  groupId: messageData.groupId,
                                  messageId: messageData.messageId,
                                );
                          },
                        );
                      },
                      onReactionSelected: (emoji) {
                        ref.read(groupControllerProvider).toggleGroupReaction(
                              groupId: messageData.groupId,
                              messageId: messageData.messageId,
                              emoji: emoji,
                            );
                      },
                      onForward: () {
                        ForwardMessageSheet.show(
                          context,
                          ForwardMessagePayload(
                            text: messageData.text,
                            messageType: messageData.messageType,
                            fileMessageData: extractedFileUrl,
                            sourceGroupId: messageData.groupId,
                          ),
                        );
                      },
                      onReplyTap: onReplyTap,
                    ),
                  ),
                ],
              ),
      ],
    );
  }
}
