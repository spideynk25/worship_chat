import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'dart:developer';
import 'package:worship_chat/common/providers/message_reply_provider.dart';
import 'package:worship_chat/common/widgets/loader.dart';
import 'package:worship_chat/features/chat/widgets/sender_message_card.dart';
import 'package:worship_chat/features/group/controller/group_controller.dart';
import 'package:worship_chat/models/group_chat_message_model.dart';
import 'package:worship_chat/features/chat/widgets/my_message_card.dart';

class GroupChatListWidget extends ConsumerStatefulWidget {
  final String groupId;

  const GroupChatListWidget({super.key, required this.groupId});

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
  List<GroupChatMessageModel> _displayMessages = [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _setupScrollListener();
  }

  void _setupScrollListener() {
    messageController.addListener(() {
      if (!messageController.hasClients) return;
      final position = messageController.position.pixels;
      final atBottom = position <= 10.0;
      if (atBottom != _isAtBottom) {
        setState(() => _isAtBottom = atBottom);
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

  // ✅ Direct call without microtask, guarded with mounted
  void _markMessageAsSeen(GroupChatMessageModel message) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    if (currentUserId != null &&
        message.senderId != currentUserId &&
        !message.isSeen &&
        !_processedMessages.contains(message.messageId)) {
      _processedMessages.add(message.messageId);

      if (mounted) {
        ref
            .read(groupControllerProvider)
            .setChatMessageSeen(context, widget.groupId, message.messageId);
      }
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

  // ✅ Check if seen status changed on any message
  bool _hasSeenStatusChanged(List<GroupChatMessageModel> newMessages) {
    if (_displayMessages.length != newMessages.length) return false;
    for (int i = 0; i < _displayMessages.length; i++) {
      if (_displayMessages[i].messageId == newMessages[i].messageId &&
          _displayMessages[i].isSeen != newMessages[i].isSeen) {
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return SizedBox.expand(
      child: StreamBuilder<List<GroupChatMessageModel>>(
        stream: ref.watch(groupControllerProvider).getGroupChat(widget.groupId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            if (_displayMessages.isNotEmpty) {
              return _buildMessageList(_displayMessages);
            }
            return const Loader();
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
            return const Center(
              child: Text('No messages yet. Start the conversation!'),
            );
          }

          final newMessages = snapshot.data!;
          final newLastMessageId = newMessages.isNotEmpty
              ? newMessages.last.messageId
              : null;

          final hasSeenChanges = _hasSeenStatusChanged(newMessages);
          final isNewData =
              newLastMessageId != _lastMessageId || hasSeenChanges;

          if (isNewData) {
            log('📨 Messages updated: ${newMessages.length} total');
            final hasNewMessage = newMessages.length > _displayMessages.length;
            _lastMessageId = newLastMessageId;
            _displayMessages = newMessages;

            if (_isAtBottom && hasNewMessage) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _scrollToBottom();
              });
            }
          }

          return _buildMessageList(_displayMessages);
        },
      ),
    );
  }

  Widget _buildMessageList(List<GroupChatMessageModel> messages) {
    if (messages.isEmpty) {
      return const Center(
        child: Text('No messages yet. Start the conversation!'),
      );
    }

    return NotificationListener<OverscrollIndicatorNotification>(
      onNotification: (notification) {
        notification.disallowIndicator();
        return true;
      },
      child: ListView.builder(
        controller: messageController,
        reverse: true,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: messages.length,
        itemBuilder: (context, index) {
          final reversedIndex = messages.length - 1 - index;
          final messageData = messages[reversedIndex];
          final currentUserId = FirebaseAuth.instance.currentUser?.uid;

          if (currentUserId == null) return const SizedBox.shrink();

          final isMyMessage = messageData.senderId == currentUserId;
          final previousMessage = reversedIndex > 0
              ? messages[reversedIndex - 1]
              : null;
          final showDateSeparator = _shouldShowDateSeparator(
            messageData,
            previousMessage,
          );

          _markMessageAsSeen(messageData);

          return _GroupMessageItemWidget(
            // ✅ Include isSeen in key so widget rebuilds on seen change
            key: ValueKey('${messageData.messageId}_${messageData.isSeen}'),
            messageData: messageData,
            isMyMessage: isMyMessage,
            showDateSeparator: showDateSeparator,
            onMessageSwipe: onMessageSwipe,
            getDateSeparatorText: _getDateSeparatorText,
          );
        },
      ),
    );
  }
}

class _GroupMessageItemWidget extends StatelessWidget {
  final GroupChatMessageModel messageData;
  final bool isMyMessage;
  final bool showDateSeparator;
  final Function(String, bool, String, String) onMessageSwipe;
  final String Function(DateTime) getDateSeparatorText;

  const _GroupMessageItemWidget({
    super.key,
    required this.messageData,
    required this.isMyMessage,
    required this.showDateSeparator,
    required this.onMessageSwipe,
    required this.getDateSeparatorText,
  });

  Widget _buildDateSeparator(DateTime date) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.5),
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
  Widget build(BuildContext context) {
    final timeSent = DateFormat.jm().format(messageData.timeSent);

    return Column(
      children: [
        if (showDateSeparator) _buildDateSeparator(messageData.timeSent),
        isMyMessage
            ? MyMessageCard(
                key: ValueKey('my_${messageData.messageId}'),
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
                isSeen: messageData.isSeen,
              )
            : SenderMessageCard(
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
      ],
    );
  }
}
