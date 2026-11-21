import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:worship_chat/common/enums/message_status_enum.dart';
import 'package:worship_chat/common/providers/message_reply_provider.dart';
import 'package:worship_chat/common/providers/message_edit_provider.dart';
import 'package:worship_chat/common/widgets/skeleton_loader.dart';
import 'package:worship_chat/features/auth/controller/auth_controller.dart';
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

  const GroupChatListWidget({
    super.key,
    required this.groupId,
    this.accentColor,
    this.queendom,
  });

  @override
  ConsumerState<GroupChatListWidget> createState() =>
      _GroupChatListWidgetState();
}

class _GroupChatListWidgetState extends ConsumerState<GroupChatListWidget>
    with AutomaticKeepAliveClientMixin {
  final ScrollController messageController = ScrollController();
  final Set<String> _processedMessages = {};
  bool _isAtBottom = true;
  String? _lastMessageId;
  String _currentUserProfilePic = "";
  List<GroupChatMessageModel> _displayMessages = [];
  StreamSubscription<List<GroupChatMessageModel>>? _chatSubscription;
  bool _isInitialLoad = true;

  // ── Scroll to Load (Pagination) ──────────────────────────────────────────
  static const int _pageSize = 30;
  int _visibleCount = _pageSize;
  bool _isLoadingMore = false;
  int _prevTotalMessages = 0;
  final Set<String> _initialMessageIds = <String>{};
  final Set<String> _newlyArrivedIds = <String>{};
  bool _hasRecordedInitialIds = false;
  final Map<String, GlobalKey> _messageKeys = {};
  String? _highlightedMessageId;
  Timer? _highlightTimer;

  GlobalKey _getMessageKey(String messageId) {
    return _messageKeys.putIfAbsent(messageId, () => GlobalKey());
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initializeUserProfile();
    _loadInitialCachedMessages();
    _setupScrollListener();
    _subscribeToStream();
  }

  void _subscribeToStream() {
    _chatSubscription?.cancel();
    final stream =
        ref.read(groupControllerProvider).getGroupChat(widget.groupId);
    _chatSubscription = stream.listen(
      _onNewMessages,
      onError: (e) => log('❌ Group chat stream error: $e'),
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
    if (oldWidget.groupId != widget.groupId) {
      _hasRecordedInitialIds = false;
      _initialMessageIds.clear();
      _newlyArrivedIds.clear();
      _loadInitialCachedMessages();
      _subscribeToStream();
    }
  }

  void _loadInitialCachedMessages() {
    try {
      final localKey = widget.groupId;
      if (Hive.isBoxOpen('messages')) {
        final box = Hive.box('messages');
        final cachedData = box.get(localKey, defaultValue: []);
        if (cachedData is List && cachedData.isNotEmpty) {
          final List<GroupChatMessageModel> parsed = [];
          for (final item in cachedData) {
            if (item is GroupChatMessageModel) {
              parsed.add(item);
            } else if (item is Map) {
              try {
                parsed.add(GroupChatMessageModel.fromMap(
                    Map<String, dynamic>.from(item)));
              } catch (_) {}
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
          }
        }
      }
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
        setState(() => _isAtBottom = atBottom);
      }

      // Check if user is scrolling up towards older messages (near top in reverse list)
      if (position.pixels >= position.maxScrollExtent - 250 &&
          !_isLoadingMore &&
          _visibleCount < _displayMessages.length) {
        _loadMoreMessages();
      }
    });
  }

  void _loadMoreMessages() {
    if (_isLoadingMore || _visibleCount >= _displayMessages.length) return;
    setState(() {
      _isLoadingMore = true;
    });

    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) {
        setState(() {
          _visibleCount =
              (_visibleCount + _pageSize).clamp(0, _displayMessages.length);
          _isLoadingMore = false;
        });
      }
    });
  }

  @override
  void dispose() {
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
      final neededCount = totalCount - targetIdx + 10;
      setState(() {
        _visibleCount = neededCount;
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToAndHighlightMessage(targetMessage.messageId);
    });
  }

  void _scrollToAndHighlightMessage(String targetMessageId) {
    if (!mounted) return;

    final key = _messageKeys[targetMessageId];
    final context = key?.currentContext;

    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOutCubic,
        alignment: 0.5,
      ).then((_) {
        _triggerMessageHighlight(targetMessageId);
      });
    } else {
      final totalCount = _displayMessages.length;
      final effectiveCount = _visibleCount.clamp(0, totalCount);
      final startIndex =
          totalCount > effectiveCount ? totalCount - effectiveCount : 0;
      final targetIdx =
          _displayMessages.indexWhere((m) => m.messageId == targetMessageId);

      if (targetIdx >= 0 && messageController.hasClients) {
        final visibleIdx = targetIdx - startIndex;
        final itemIndex =
            (effectiveCount - 1 - visibleIdx).clamp(0, effectiveCount - 1);
        final maxExtent = messageController.position.maxScrollExtent;
        final estimatedOffset =
            ((itemIndex / (effectiveCount > 0 ? effectiveCount : 1)) *
                    maxExtent)
                .clamp(0.0, maxExtent);

        messageController.jumpTo(estimatedOffset);

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final retryCtx = _messageKeys[targetMessageId]?.currentContext;
          if (retryCtx != null) {
            Scrollable.ensureVisible(
              retryCtx,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeInOutCubic,
              alignment: 0.5,
            ).then((_) {
              _triggerMessageHighlight(targetMessageId);
            });
          } else {
            _triggerMessageHighlight(targetMessageId);
          }
        });
      }
    }
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
      if (_displayMessages[i].messageId != newMessages[i].messageId ||
          _displayMessages[i].isSeen != newMessages[i].isSeen ||
          _displayMessages[i].isDelivered != newMessages[i].isDelivered ||
          _displayMessages[i].isSending != newMessages[i].isSending ||
          _displayMessages[i].text != newMessages[i].text ||
          _displayMessages[i].fileMessageData != newMessages[i].fileMessageData ||
          _displayMessages[i].isEdited != newMessages[i].isEdited ||
          _displayMessages[i].isDeleted != newMessages[i].isDeleted ||
          !mapEquals(_displayMessages[i].reactions, newMessages[i].reactions)) {
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

    // Skip redundant rebuild if incoming messages are identical to what's already showing
    if (_displayMessages.isNotEmpty && !_hasDeliveryOrSeenStatusChanged(newMessages)) {
      _isInitialLoad = false;
      return;
    }

    final newLastMessageId =
        newMessages.isNotEmpty ? newMessages.last.messageId : null;
    final oldMessageCount = _displayMessages.length;
    final hasNewMessage = newMessages.length > oldMessageCount ||
        (newMessages.isNotEmpty && newLastMessageId != _lastMessageId);
    final hasStatusChanges = _hasDeliveryOrSeenStatusChanged(newMessages);
    final addedCount = newMessages.length - _prevTotalMessages;

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
      if (addedCount > 0 && _prevTotalMessages > 0) {
        _visibleCount += addedCount;
      } else if (_visibleCount == _pageSize ||
          _visibleCount > newMessages.length) {
        _visibleCount = _pageSize.clamp(0, newMessages.length);
      }

      _prevTotalMessages = newMessages.length;
      _lastMessageId = newLastMessageId;
      _displayMessages = newMessages;
      _isInitialLoad = false;
    });

    if (_isAtBottom && (hasNewMessage || hasStatusChanges)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToBottom();
      });
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

    return NotificationListener<OverscrollIndicatorNotification>(
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
              .map((m) => m.reactions.entries
                  .map((e) => '${e.key}:${e.value}')
                  .join(','))
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
          return KeyedSubtree(
            key: _getMessageKey(primaryMsgId),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: isHighlighted
                    ? const Color(0xFFFFD700).withValues(alpha: 0.25)
                    : Colors.transparent,
                boxShadow: isHighlighted
                    ? [
                        BoxShadow(
                          color:
                              const Color(0xFFFFD700).withValues(alpha: 0.40),
                          blurRadius: 18,
                          spreadRadius: 3,
                        ),
                      ]
                    : null,
              ),
              child: RepaintBoundary(
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
              ),
            ),
          );
        },
      ),
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
            key: ValueKey('roleplay_${firstMsg.messageId}_$reactionsKey'),
            messageData: firstMsg,
            isNewlySent: isNewlySent,
            accentColor: accentColor,
            queendom: queendom,
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
                        'my_${messageData.messageId}_$reactionsKey',
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
                        'sender_${messageData.messageId}_$reactionsKey',
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
