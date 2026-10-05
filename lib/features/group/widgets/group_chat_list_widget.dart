import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'dart:developer';
import 'package:worship_chat/common/providers/message_reply_provider.dart';
import 'package:worship_chat/common/widgets/skeleton_loader.dart';
import 'package:worship_chat/features/chat/widgets/sender_message_card.dart';
import 'package:worship_chat/features/group/controller/group_controller.dart';
import 'package:worship_chat/models/group_chat_message_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/widgets/user_avatar.dart';
import 'package:worship_chat/features/chat/widgets/forward_message_sheet.dart';
import 'package:worship_chat/features/chat/widgets/my_message_card.dart';
import 'package:worship_chat/models/user_model.dart';

final _groupUserProvider =
    FutureProvider.family<UserModel?, String>((ref, userId) async {
  if (userId.isEmpty) return null;

  if (userId == FirebaseAuth.instance.currentUser?.uid) {
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
  String _currentUserProfilePic = "";
  List<GroupChatMessageModel> _displayMessages = [];
  late Stream<List<GroupChatMessageModel>> _groupChatStream;

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
    _initializeUserProfile();
    _groupChatStream =
        ref.read(groupControllerProvider).getGroupChat(widget.groupId);
    _loadInitialCachedMessages();
    _setupScrollListener();
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
      _groupChatStream =
          ref.read(groupControllerProvider).getGroupChat(widget.groupId);
      _hasRecordedInitialIds = false;
      _initialMessageIds.clear();
      _newlyArrivedIds.clear();
      _loadInitialCachedMessages();
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
          !mapEquals(_displayMessages[i].reactions, newMessages[i].reactions)) {
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
        stream: _groupChatStream,
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
                  Text('Error: ${snapshot.error}',
                      style: const TextStyle(color: Colors.white70)),
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
            if (_displayMessages.isNotEmpty) {
              return _buildMessageList(_displayMessages);
            }
            _lastMessageId = null;
            _prevTotalMessages = 0;
            return _buildEmptyState();
          }

          final newMessages = snapshot.data!;
          final newLastMessageId = newMessages.isNotEmpty
              ? newMessages.last.messageId
              : null;

          final currentUserId = FirebaseAuth.instance.currentUser?.uid;
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

          final hasStatusChanges = _hasDeliveryOrSeenStatusChanged(newMessages);
          final isNewData =
              newLastMessageId != _lastMessageId || hasStatusChanges;

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

          if (isNewData) {
            log('📨 Messages updated: ${newMessages.length} total');
            final oldMessageCount = _displayMessages.length;
            final hasNewMessage = newMessages.length > oldMessageCount;
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
          }

          return _buildMessageList(_displayMessages);
        },
      ),
    );
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

          final reactionsKey = messageData.reactions.entries
              .map((e) => '${e.key}:${e.value}')
              .join('_');

          final isNewlyArrived = _newlyArrivedIds.contains(messageData.messageId) ||
              ((index < 3) &&
                  (DateTime.now()
                          .difference(messageData.timeSent)
                          .inSeconds
                          .abs() <
                      25));

          return _GroupMessageItemWidget(
            key: ValueKey(
              '${messageData.messageId}_$reactionsKey',
            ),
            messageData: messageData,
            isNewlySent: isNewlyArrived,
            currentUserId: currentUserId,
            currentUserProfilePic: _currentUserProfilePic,
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

class _GroupMessageItemWidget extends ConsumerWidget {
  final GroupChatMessageModel messageData;
  final bool isNewlySent;
  final String currentUserId;
  final String currentUserProfilePic;
  final bool isMyMessage;
  final bool showDateSeparator;
  final Function(String, bool, String, String) onMessageSwipe;
  final String Function(DateTime) getDateSeparatorText;

  const _GroupMessageItemWidget({
    super.key,
    required this.messageData,
    this.isNewlySent = false,
    required this.currentUserId,
    required this.currentUserProfilePic,
    required this.isMyMessage,
    required this.showDateSeparator,
    required this.onMessageSwipe,
    required this.getDateSeparatorText,
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
    final timeSent = DateFormat.jm().format(messageData.timeSent);
    final seen = messageData.isSeen;
    final delivered = messageData.isDelivered;
    final sending = messageData.isSending;
    final reactionsKey = messageData.reactions.entries
        .map((e) => '${e.key}:${e.value}')
        .join('_');

    final senderUserAsync = isMyMessage
        ? null
        : ref.watch(_groupUserProvider(messageData.senderId));
    final senderPic = senderUserAsync?.value?.profilePic;
    final myPic = currentUserProfilePic.isNotEmpty
        ? currentUserProfilePic
        : ref.watch(_groupUserProvider(currentUserId)).value?.profilePic;

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
                      isNewlySent: sending || isNewlySent,
                      messageId: messageData.messageId,
                      currentUserId: currentUserId,
                      reactions: messageData.reactions,
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
                            fileMessageData: messageData.fileMessageData,
                            sourceGroupId: messageData.groupId,
                          ),
                        );
                      },
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
                      isNewlyReceived: isNewlySent,
                      messageId: messageData.messageId,
                      currentUserId: currentUserId,
                      senderProfilePic: senderPic,
                      reactions: messageData.reactions,
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
                            fileMessageData: messageData.fileMessageData,
                            sourceGroupId: messageData.groupId,
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
}
