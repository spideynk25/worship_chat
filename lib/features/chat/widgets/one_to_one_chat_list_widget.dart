import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/adapters.dart';
import 'package:intl/intl.dart';
import 'dart:developer';
import 'package:worship_chat/common/enums/message_status_enum.dart';
import 'package:worship_chat/common/providers/message_reply_provider.dart';
import 'package:worship_chat/common/widgets/skeleton_loader.dart';
import 'package:worship_chat/common/widgets/user_avatar.dart';
import 'package:worship_chat/features/chat/controller/chat_controller.dart';
import 'package:worship_chat/features/chat/widgets/media_group_widget.dart';
import 'package:worship_chat/features/chat/widgets/sender_message_card.dart';
import 'package:worship_chat/models/one_to_one_message_model.dart';
import 'package:worship_chat/features/chat/widgets/my_message_card.dart';
import 'package:worship_chat/features/chat/widgets/forward_message_sheet.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/models/user_model.dart';

class OneToOneChatListWidget extends ConsumerStatefulWidget {
  final String receiverUserId;
  final String profilePic;

  const OneToOneChatListWidget({
    super.key,
    required this.receiverUserId,
    required this.profilePic,
  });

  @override
  ConsumerState<OneToOneChatListWidget> createState() =>
      _OneToOneChatListWidgetState();
}

class _OneToOneChatListWidgetState extends ConsumerState<OneToOneChatListWidget>
    with AutomaticKeepAliveClientMixin {
  final ScrollController messageController = ScrollController();
  final Set<String> _processedMessages = {};
  bool _isAtBottom = true;
  String? _lastMessageId;
  List<OneToOneMessageModel> _displayMessages = [];
  String currentUserProfilePic = "";
  StreamSubscription<List<OneToOneMessageModel>>? _chatSubscription;
  // Loading state shown only before the first data arrives
  bool _isInitialLoad = true;

  // ── Scroll to Load (Pagination) ──────────────────────────────────────────
  static const int _pageSize = 30;
  int _visibleCount = _pageSize;
  bool _isLoadingMore = false;
  int _prevTotalMessages = 0;
  final Set<String> _initialMessageIds = <String>{};
  final Set<String> _newlyArrivedIds = <String>{};
  bool _hasRecordedInitialIds = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadInitialCachedMessages();
    _initializeUserProfile();
    _setupScrollListener();
    _subscribeToStream();
  }

  void _subscribeToStream() {
    _chatSubscription?.cancel();
    final stream =
        ref.read(chatControllerProvider).chatStream(widget.receiverUserId);
    _chatSubscription = stream.listen(
      _onNewMessages,
      onError: (e) => log('❌ Chat stream error: $e'),
    );
  }

  void _onNewMessages(List<OneToOneMessageModel> newMessages) {
    if (!mounted) return;

    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    // Mark unseen messages
    if (currentUserId != null) {
      final hasUnseenIncoming = newMessages.any(
        (m) => m.receiverId == currentUserId && !m.isSeen,
      );
      if (hasUnseenIncoming) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref
                .read(chatControllerProvider)
                .markChatAsSeen(widget.receiverUserId);
          }
        });
      }
    }

    final newLastMessageId =
        newMessages.isNotEmpty ? newMessages.last.messageId : null;
    final oldMessageCount = _displayMessages.length;
    final hasNewMessage = newMessages.length > oldMessageCount ||
        (newMessages.isNotEmpty && newLastMessageId != _lastMessageId);
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

    if (_isAtBottom && hasNewMessage) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToBottom();
      });
    }
  }

  @override
  void didUpdateWidget(covariant OneToOneChatListWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.receiverUserId != widget.receiverUserId) {
      _displayMessages = [];
      _isInitialLoad = true;
      _hasRecordedInitialIds = false;
      _initialMessageIds.clear();
      _newlyArrivedIds.clear();
      _loadInitialCachedMessages();
      _subscribeToStream();
    }
  }

  void _loadInitialCachedMessages() {
    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId == null) return;
      final localKey = '${currentUserId}_${widget.receiverUserId}';
      if (Hive.isBoxOpen('messages')) {
        final box = Hive.box('messages');
        final cachedData = box.get(localKey, defaultValue: []);
        if (cachedData is List && cachedData.isNotEmpty) {
          final List<OneToOneMessageModel> parsed = [];
          for (final item in cachedData) {
            if (item is OneToOneMessageModel) {
              parsed.add(item);
            } else if (item is Map) {
              try {
                parsed.add(OneToOneMessageModel.fromMap(
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
            log('⚡ Pre-seeded ${_displayMessages.length} messages from Hive in initState');
          }
        }
      }
    } catch (e) {
      log('Error pre-seeding cached messages: $e');
    }
  }

  void _initializeUserProfile() {
    try {
      final userBox = Hive.box<UserModel>('userBox');
      final user = userBox.get('currentUser');
      currentUserProfilePic = user?.profilePic ?? "";
    } catch (e) {
      log('Error loading user profile: $e');
    }
  }

  void _setupScrollListener() {
    messageController.addListener(() {
      if (!messageController.hasClients) return;
      final position = messageController.position;
      final atBottom = position.pixels <= 10.0;
      if (atBottom != _isAtBottom) {
        _isAtBottom = atBottom; // not used in build() — no setState needed
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
    messageController.dispose();
    super.dispose();
  }

  void onMessageSwipe(
    String message,
    bool isMe,
    String messageType,
    String fileMessageData,
  ) {
    ref.read(messageReplyProvider.notifier).state = MessageReply(
      message: messageType == 'text' ? message : fileMessageData,
      isMe: isMe,
      messageType: messageType,
      fileMessageData: fileMessageData,
    );
  }

  void _markMessageAsSeen(OneToOneMessageModel message) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;

    if (!message.isSeen &&
        message.receiverId == currentUserId &&
        !_processedMessages.contains(message.messageId)) {
      _processedMessages.add(message.messageId);

      if (mounted) {
        ref
            .read(chatControllerProvider)
            .setChatMessageSeen(
              context,
              widget.receiverUserId,
              message.messageId,
            );
      }
    }
  }

  void _optimisticToggleReaction(String messageId, String emoji) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;
    setState(() {
      final idx = _displayMessages.indexWhere((m) => m.messageId == messageId);
      if (idx >= 0) {
        final old = _displayMessages[idx];
        final updated = Map<String, String>.from(old.reactions);
        if (updated[currentUserId] == emoji) {
          updated.remove(currentUserId);
        } else {
          updated[currentUserId] = emoji;
        }
        _displayMessages[idx] = old.copyWith(reactions: updated);
      }
    });
  }

  void _scrollToBottom() {
    if (!messageController.hasClients) return;
    log('Scrolling to bottom');
    messageController.jumpTo(0);
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
    OneToOneMessageModel currentMessage,
    OneToOneMessageModel? previousMessage,
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

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // Show skeleton only on the very first load before any data arrives.
    // After that, _displayMessages is updated via setState from the stream
    // subscription — no StreamBuilder means the ListView is never recreated.
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
              padding: const EdgeInsets.all(4),
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
              child: UserAvatar(
                url: widget.profilePic.isNotEmpty ? widget.profilePic : null,
                radius: 44,
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
              'Send a message to start the conversation! 👋',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.65),
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.1),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 13,
                    color: tabColor.withValues(alpha: 0.9),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'End-to-end encrypted',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageList(List<OneToOneMessageModel> allMessages) {
    if (allMessages.isEmpty) {
      return _buildEmptyState();
    }

    final totalCount = allMessages.length;
    final effectiveCount = _visibleCount.clamp(0, totalCount);
    final startIndex =
        totalCount > effectiveCount ? totalCount - effectiveCount : 0;
    final visibleMessages = allMessages.sublist(startIndex);
    final hasMore = startIndex > 0;
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    // ── Group consecutive same-groupId messages into logical rows ─────────────
    final List<_ChatRow> rows = _buildRows(
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
        itemBuilder: (context, index) {
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

          for (final m in row.messages) {
            _markMessageAsSeen(m);
          }

          final rowReactionsKey = row.messages
              .map((m) => m.reactions.entries
                  .map((e) => '${e.key}:${e.value}')
                  .join(','))
              .join(';');

          // RepaintBoundary isolates each row's raster cache so that when
          // a new message arrives, only the new/changed rows repaint —
          // image and video rows are NOT repainted at all.
          final isNewlyArrived = _newlyArrivedIds.contains(row.messages.last.messageId) ||
              ((index < 3) &&
                  (DateTime.now()
                          .difference(row.messages.last.timeSent)
                          .inSeconds
                          .abs() <
                      25));

          return RepaintBoundary(
            child: _ChatRowWidget(
              key: ValueKey('${row.key}_$rowReactionsKey'),
              row: row,
              isNewlySent: isNewlyArrived,
              currentUserProfilePic: currentUserProfilePic,
              receiverProfilePic: widget.profilePic,
              receiverUserId: widget.receiverUserId,
              currentUserId: currentUserId ?? '',
              onMessageSwipe: onMessageSwipe,
              getDateSeparatorText: _getDateSeparatorText,
              onReactionToggle: _optimisticToggleReaction,
            ),
          );
        },
      ),
    );
  }

  /// Build a flat list of _ChatRow objects, merging consecutive messages that
  /// share the same senderId + groupId into a single row.
  List<_ChatRow> _buildRows(
    List<OneToOneMessageModel> visibleMessages,
    List<OneToOneMessageModel> allMessages,
    int startIndex,
    String? currentUserId,
  ) {
    final rows = <_ChatRow>[];

    for (int i = 0; i < visibleMessages.length; i++) {
      final msg = visibleMessages[i];
      final globalIndex = startIndex + i;
      final prevMsg = globalIndex > 0 ? allMessages[globalIndex - 1] : null;
      final showDateSep = _shouldShowDateSeparator(msg, prevMsg);
      final isMyMessage = msg.senderId == currentUserId;
      final groupId = _getGroupId(msg.fileMessageData);
      final isMedia = msg.messageType == 'image' || msg.messageType == 'video';

      if (isMedia && groupId != null && groupId.isNotEmpty && !showDateSep) {
        // Check if the last row has the same groupId from the same sender
        if (rows.isNotEmpty &&
            rows.last.groupId == groupId &&
            rows.last.isMyMessage == isMyMessage) {
          rows.last.messages.add(msg);
          continue;
        }
      }

      rows.add(_ChatRow(
        messages: [msg],
        isMyMessage: isMyMessage,
        groupId: groupId,
        showDateSeparator: showDateSep,
      ));
    }

    return rows;
  }

  String? _getGroupId(String? fileMessageData) {
    if (fileMessageData == null) return null;
    try {
      final map = jsonDecode(fileMessageData);
      if (map is Map && map.containsKey('groupId')) {
        return map['groupId']?.toString();
      }
    } catch (_) {}
    return null;
  }
}

/// A logical chat row – may contain 1 message or several grouped media messages.
class _ChatRow {
  final List<OneToOneMessageModel> messages;
  final bool isMyMessage;
  final String? groupId;
  bool showDateSeparator;

  _ChatRow({
    required this.messages,
    required this.isMyMessage,
    required this.groupId,
    required this.showDateSeparator,
  });

  String get key {
    if (messages.length == 1) return messages.first.messageId;
    return 'group_${groupId ?? messages.first.messageId}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ChatRowWidget – renders one logical row (normal msg OR media group)
// ─────────────────────────────────────────────────────────────────────────────
class _ChatRowWidget extends ConsumerWidget {
  final _ChatRow row;
  final bool isNewlySent;
  final String currentUserProfilePic;
  final String receiverProfilePic;
  final String receiverUserId;
  final String currentUserId;
  final Function(String, bool, String, String) onMessageSwipe;
  final String Function(DateTime) getDateSeparatorText;
  final void Function(String messageId, String emoji)? onReactionToggle;

  const _ChatRowWidget({
    super.key,
    required this.row,
    this.isNewlySent = false,
    required this.currentUserProfilePic,
    required this.receiverProfilePic,
    required this.receiverUserId,
    required this.currentUserId,
    required this.onMessageSwipe,
    required this.getDateSeparatorText,
    this.onReactionToggle,
  });

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final firstMsg = row.messages.first;
    final lastMsg = row.messages.last;
    final timeSent = DateFormat.jm().format(lastMsg.timeSent);
    final seen = lastMsg.isSeen;
    final delivered = lastMsg.isDelivered;
    final sending = lastMsg.isSending;

    // ── Is this a grouped media row? ─────────────────────────────────────────
    final isGroup = row.messages.length > 1 &&
        row.groupId != null &&
        (firstMsg.messageType == 'image' || firstMsg.messageType == 'video');

    if (isGroup) {
      // Build MediaGroupItems (extract URL from each message's fileMessageData)
      final items = row.messages.map((m) {
        final url = _extractUrl(m.fileMessageData);
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
          if (row.showDateSeparator)
            _buildDateSeparator(firstMsg.timeSent),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: row.isMyMessage
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      groupWidget,
                      _buildProfileAvatar(currentUserProfilePic, true),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _buildProfileAvatar(receiverProfilePic, false),
                      groupWidget,
                    ],
                  ),
          ),
        ],
      );
    }

    // ── Single message row (original behaviour) ───────────────────────────────
    final messageData = firstMsg;
    final isMyMessage = row.isMyMessage;
    final reactionsKey = messageData.reactions.entries
        .map((e) => '${e.key}:${e.value}')
        .join('_');

    return Column(
      children: [
        if (row.showDateSeparator) _buildDateSeparator(messageData.timeSent),
        isMyMessage
            ? Row(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(
                    child: MyMessageCard(
                      key: ValueKey('my_${messageData.messageId}_$reactionsKey'),
                      message: messageData.text,
                      date: timeSent,
                      messageType: messageData.messageType,
                      fileMessageData: _extractUrl(messageData.fileMessageData),
                      repliedText: messageData.repliedMessage,
                      username: messageData.repliedTo,
                      repliedMessageType: messageData.repliedMessageType,
                      onLeftSwipe: () => onMessageSwipe(
                        messageData.text,
                        true,
                        messageData.messageType,
                        messageData.fileMessageData ?? '',
                      ),
                      isSeen: seen,
                      isDelivered: delivered,
                      isSending: sending,
                      isNewlySent: sending || isNewlySent,
                      messageId: messageData.messageId,
                      currentUserId: currentUserId,
                      receiverId: receiverUserId,
                      reactions: messageData.reactions,
                      onReactionSelected: (emoji) {
                        onReactionToggle?.call(messageData.messageId, emoji);
                        ref.read(chatControllerProvider).toggleReaction(
                          messageId: messageData.messageId,
                          receiverUserId: receiverUserId,
                          emoji: emoji,
                        );
                      },
                      onForward: () {
                        ForwardMessageSheet.show(
                          context,
                          ForwardMessagePayload(
                            text: messageData.text,
                            messageType: messageData.messageType,
                            fileMessageData: messageData.fileMessageData,
                          ),
                        );
                      },
                    ),
                  ),
                  _buildProfileAvatar(currentUserProfilePic, true),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _buildProfileAvatar(receiverProfilePic, false),
                  Flexible(
                    child: SenderMessageCard(
                      key: ValueKey('sender_${messageData.messageId}_$reactionsKey'),
                      message: messageData.text,
                      date: timeSent,
                      messageType: messageData.messageType,
                      fileMessageData: _extractUrl(messageData.fileMessageData),
                      repliedText: messageData.repliedMessage,
                      username: messageData.repliedTo,
                      repliedMessageType: messageData.repliedMessageType,
                      onRightSwipe: () => onMessageSwipe(
                        messageData.text,
                        false,
                        messageData.messageType,
                        messageData.fileMessageData ?? '',
                      ),
                      isNewlyReceived: isNewlySent,
                      messageId: messageData.messageId,
                      currentUserId: currentUserId,
                      receiverId: receiverUserId,
                      senderProfilePic: receiverProfilePic,
                      reactions: messageData.reactions,
                      onReactionSelected: (emoji) {
                        onReactionToggle?.call(messageData.messageId, emoji);
                        ref.read(chatControllerProvider).toggleReaction(
                          messageId: messageData.messageId,
                          receiverUserId: receiverUserId,
                          emoji: emoji,
                        );
                      },
                      onForward: () {
                        ForwardMessageSheet.show(
                          context,
                          ForwardMessagePayload(
                            text: messageData.text,
                            messageType: messageData.messageType,
                            fileMessageData: messageData.fileMessageData,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
      ],
    );
  }

  /// Extract the actual URL from fileMessageData (plain URL or JSON wrapper).
  String _extractUrl(String? fileMessageData) {
    if (fileMessageData == null || fileMessageData.isEmpty) return '';
    try {
      final map = jsonDecode(fileMessageData);
      if (map is Map && map.containsKey('url')) {
        return map['url']?.toString() ?? '';
      }
    } catch (_) {}
    return fileMessageData;
  }
}