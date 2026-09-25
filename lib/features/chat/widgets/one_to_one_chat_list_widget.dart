import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/adapters.dart';
import 'package:intl/intl.dart';
import 'dart:developer';
import 'package:worship_chat/common/providers/message_reply_provider.dart';
import 'package:worship_chat/common/widgets/skeleton_loader.dart';
import 'package:worship_chat/common/widgets/user_avatar.dart';
import 'package:worship_chat/features/chat/controller/chat_controller.dart';
import 'package:worship_chat/features/chat/widgets/sender_message_card.dart';
import 'package:worship_chat/models/one_to_one_message_model.dart';
import 'package:worship_chat/features/chat/widgets/my_message_card.dart';
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

  // ── Scroll to Load (Pagination) ──────────────────────────────────────────
  static const int _pageSize = 30;
  int _visibleCount = _pageSize;
  bool _isLoadingMore = false;
  int _prevTotalMessages = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadInitialCachedMessages();
    _initializeUserProfile();
    _setupScrollListener();
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
          _displayMessages = cachedData.cast<OneToOneMessageModel>();
          _lastMessageId = _displayMessages.last.messageId;
          _prevTotalMessages = _displayMessages.length;
          log('⚡ Pre-seeded ${_displayMessages.length} messages from Hive in initState');
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

    return SizedBox.expand(
      child: StreamBuilder<List<OneToOneMessageModel>>(
        stream: ref
            .watch(chatControllerProvider)
            .chatStream(widget.receiverUserId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            if (_displayMessages.isNotEmpty) {
              return _buildMessageList(_displayMessages);
            }
            return const ChatMessagesSkeleton();
          }

          if (snapshot.hasError) {
            log('❌ Stream error: ${snapshot.error}');
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('Error: ${snapshot.error}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => setState(() {
                      _displayMessages = [];
                      _lastMessageId = null;
                      _visibleCount = _pageSize;
                    }),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            _displayMessages = [];
            _lastMessageId = null;
            _prevTotalMessages = 0;
            return const Center(
              child: Text('No messages yet. Start the conversation!'),
            );
          }

          final newMessages = snapshot.data!;
          final newLastMessageId = newMessages.isNotEmpty
              ? newMessages.last.messageId
              : null;

          final currentUserId = FirebaseAuth.instance.currentUser?.uid;
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

          final oldMessageCount = _displayMessages.length;
          final hasStatusChanges = _hasDeliveryOrSeenStatusChanged(newMessages);
          final hasNewMessage = newMessages.length > oldMessageCount ||
              (newMessages.isNotEmpty && newLastMessageId != _lastMessageId);
          final addedCount = newMessages.length - _prevTotalMessages;

          if (addedCount > 0 && _prevTotalMessages > 0) {
            _visibleCount += addedCount;
          } else if (_visibleCount == _pageSize ||
              _visibleCount > newMessages.length) {
            _visibleCount = _pageSize.clamp(0, newMessages.length);
          }

          _prevTotalMessages = newMessages.length;
          _lastMessageId = newLastMessageId;
          _displayMessages = newMessages;

          if (_isAtBottom && (hasNewMessage || hasStatusChanges)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _scrollToBottom();
            });
          }

          return _buildMessageList(_displayMessages);
        },
      ),
    );
  }

  bool _hasDeliveryOrSeenStatusChanged(List<OneToOneMessageModel> newMessages) {
    if (_displayMessages.length != newMessages.length) return true;
    for (int i = 0; i < newMessages.length; i++) {
      if (_displayMessages[i].messageId != newMessages[i].messageId ||
          _displayMessages[i].isSeen != newMessages[i].isSeen ||
          _displayMessages[i].isDelivered != newMessages[i].isDelivered ||
          _displayMessages[i].isSending != newMessages[i].isSending ||
          _displayMessages[i].text != newMessages[i].text) {
        return true;
      }
    }
    return false;
  }

  Widget _buildMessageList(List<OneToOneMessageModel> allMessages) {
    if (allMessages.isEmpty) {
      return const Center(
        child: Text('No messages yet. Start the conversation!'),
      );
    }

    final totalCount = allMessages.length;
    final effectiveCount = _visibleCount.clamp(0, totalCount);
    final startIndex =
        totalCount > effectiveCount ? totalCount - effectiveCount : 0;
    final visibleMessages = allMessages.sublist(startIndex);
    final hasMore = startIndex > 0;

    return NotificationListener<OverscrollIndicatorNotification>(
      onNotification: (notification) {
        notification.disallowIndicator();
        return true;
      },
      child: ListView.builder(
        controller: messageController,
        reverse: true,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: visibleMessages.length + (hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          // Top spinner for loading older messages in reverse list
          if (index == visibleMessages.length) {
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

          final reversedIndex = visibleMessages.length - 1 - index;
          final messageData = visibleMessages[reversedIndex];
          final currentUserId = FirebaseAuth.instance.currentUser?.uid;
          if (currentUserId == null) return const SizedBox.shrink();

          final isMyMessage = messageData.senderId == currentUserId;

          // Global index in allMessages to check date separator accurately across pages
          final globalIndex = startIndex + reversedIndex;
          final previousMessage = globalIndex > 0
              ? allMessages[globalIndex - 1]
              : null;
          final showDateSeparator = _shouldShowDateSeparator(
            messageData,
            previousMessage,
          );

          _markMessageAsSeen(messageData);

          return _MessageItemWidget(
            key: ValueKey(messageData.messageId),
            messageData: messageData,
            isMyMessage: isMyMessage,
            showDateSeparator: showDateSeparator,
            currentUserProfilePic: currentUserProfilePic,
            receiverProfilePic: widget.profilePic,
            onMessageSwipe: onMessageSwipe,
            getDateSeparatorText: _getDateSeparatorText,
          );
        },
      ),
    );
  }
}

class _MessageItemWidget extends StatelessWidget {
  final OneToOneMessageModel messageData;
  final bool isMyMessage;
  final bool showDateSeparator;
  final String currentUserProfilePic;
  final String receiverProfilePic;
  final Function(String, bool, String, String) onMessageSwipe;
  final String Function(DateTime) getDateSeparatorText;

  const _MessageItemWidget({
    super.key,
    required this.messageData,
    required this.isMyMessage,
    required this.showDateSeparator,
    required this.currentUserProfilePic,
    required this.receiverProfilePic,
    required this.onMessageSwipe,
    required this.getDateSeparatorText,
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

    final pic = profilePic ?? "";
    return Padding(
      padding: padding,
      child: UserAvatar(
        url: pic.isNotEmpty ? pic : null,
        radius: 17.5,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final timeSent = DateFormat.jm().format(messageData.timeSent);
    final seen = messageData.isSeen;
    final delivered = messageData.isDelivered;
    final sending = messageData.isSending;

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
                        'my_${messageData.messageId}_${sending}_${delivered}_$seen',
                      ),
                      message: messageData.text,
                      date: timeSent,
                      messageType: messageData.messageType,
                      fileMessageData: messageData.fileMessageData,
                      repliedText: messageData.repliedMessage,
                      username: messageData.repliedTo,
                      repliedMessageType: messageData.repliedMessageType,
                      onLeftSwipe: () => onMessageSwipe(
                        messageData.text,
                        true,
                        messageData.messageType,
                        messageData.fileMessageData ?? "",
                      ),
                      isSeen: seen,
                      isDelivered: delivered,
                      isSending: sending,
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
                      key: ValueKey('sender_${messageData.messageId}'),
                      message: messageData.text,
                      date: timeSent,
                      messageType: messageData.messageType,
                      fileMessageData: messageData.fileMessageData,
                      repliedText: messageData.repliedMessage,
                      username: messageData.repliedTo,
                      repliedMessageType: messageData.repliedMessageType,
                      onRightSwipe: () => onMessageSwipe(
                        messageData.text,
                        false,
                        messageData.messageType,
                        messageData.fileMessageData ?? "",
                      ),
                    ),
                  ),
                ],
              ),
      ],
    );
  }
}