import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:swipe_to/swipe_to.dart';
import 'package:worship_chat/common/enums/message_status_enum.dart';
import 'package:worship_chat/common/utils/utils.dart';
import 'display_messages.dart';
import 'message_reaction_dialog.dart';

class MyMessageCard extends StatelessWidget {
  final String message;
  final String date;
  final String messageType;
  final String? fileMessageData;
  final VoidCallback onLeftSwipe;
  final String repliedText;
  final String username;
  final String repliedMessageType;
  final bool isSeen;
  final bool isDelivered;
  final bool isSending;
  final String? messageId;
  final String? currentUserId;
  final String? receiverId;
  final Map<String, String> reactions;
  final void Function(String emoji)? onReactionSelected;
  final VoidCallback? onForward;
  final VoidCallback? onDelete;

  const MyMessageCard({
    super.key,
    required this.message,
    required this.date,
    required this.messageType,
    this.fileMessageData,
    required this.onLeftSwipe,
    required this.repliedText,
    required this.username,
    required this.repliedMessageType,
    required this.isSeen,
    this.isDelivered = false,
    this.isSending = false,
    this.messageId,
    this.currentUserId,
    this.receiverId,
    this.reactions = const {},
    this.onReactionSelected,
    this.onForward,
    this.onDelete,
  });

  void _copyMessage(BuildContext context) {
    final textToCopy = messageType == 'text' ? message : fileMessageData ?? '';
    if (textToCopy.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: textToCopy));
      AppSnackBar.success(context, 'Message copied');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isReplying = repliedText.isNotEmpty;
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 600;

    final isMedia = messageType == 'image' ||
        messageType == 'video' ||
        messageType == 'gif';
    final hasCaption = isMedia &&
        message.isNotEmpty &&
        message != fileMessageData;
    final isPureMedia = isMedia && !hasCaption;
    final isPureGif = messageType == 'gif' && !hasCaption && !isReplying;

    // Compact single-line detection for short messages (like "hi", "ok", "yes")
    final isShortSingleLine = messageType == 'text' &&
        !isReplying &&
        !message.contains('\n') &&
        !message.contains('http://') &&
        !message.contains('https://') &&
        message.length <= 25;

    final deliveryStatus = MessageDeliveryStatus.fromFlags(
      isSeen: isSeen,
      isDelivered: isDelivered,
      isSending: isSending,
    );

    // Asymmetrical tail pointing towards user's avatar on the right
    const bubbleRadius = BorderRadius.only(
      topLeft: Radius.circular(18),
      topRight: Radius.circular(18),
      bottomLeft: Radius.circular(18),
      bottomRight: Radius.circular(4),
    );

    return SwipeTo(
      iconSize: 0,
      swipeSensitivity: 8,
      onLeftSwipe: (details) => onLeftSwipe(),
      child: Align(
        alignment: Alignment.bottomRight,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: screenWidth * 0.75),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Builder(
                builder: (bubbleContext) => GestureDetector(
                  onLongPress: () {
                    final renderBox =
                        bubbleContext.findRenderObject() as RenderBox?;
                    if (renderBox == null) return;
                    final offset = renderBox.localToGlobal(Offset.zero);
                    final size = renderBox.size;
                    final rect = Rect.fromLTWH(
                      offset.dx,
                      offset.dy,
                      size.width,
                      size.height,
                    );

                    MessageReactionDialog.show(
                      context: context,
                      targetRect: rect,
                      currentUserId: currentUserId,
                      reactions: reactions,
                      onReactionSelected: (emoji) {
                        onReactionSelected?.call(emoji);
                      },
                      onReply: onLeftSwipe,
                      onCopy: () => _copyMessage(context),
                      onForward: onForward,
                      onDelete: onDelete,
                      isMyMessage: true,
                    );
                  },
                  child: Container(
                    margin: EdgeInsets.only(
                      left: isSmallScreen ? 3 : 6,
                      right: isSmallScreen ? 3 : 6,
                      top: 2,
                      bottom: reactions.isNotEmpty ? 13 : 2,
                    ),
                    decoration: isPureGif
                        ? null
                        : BoxDecoration(
                            borderRadius: bubbleRadius,
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(0xFF6E1C4B), // Rich luxury wine
                                Color(0xFF4E1135), // Deep velvety burgundy
                              ],
                            ),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.12),
                              width: 0.8,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.25),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                    child: ClipRRect(
                      borderRadius: isPureGif
                          ? BorderRadius.circular(16)
                          : bubbleRadius,
                      child: isPureMedia
                          ? _buildPureMedia(context, deliveryStatus, isReplying)
                          : isShortSingleLine
                              ? _buildShortSingleLine(
                                  context,
                                  deliveryStatus,
                                  isSmallScreen,
                                )
                              : _buildDynamicContent(
                                  context,
                                  deliveryStatus,
                                  isReplying,
                                  isMedia,
                                  isSmallScreen,
                                ),
                    ),
                  ),
                ),
              ),

              // ── Floating Reaction Badge Capsule ───────────────────────────
              if (reactions.isNotEmpty)
                Positioned(
                  bottom: 0,
                  left: 10,
                  child: MessageReactionsBadge(
                    reactions: reactions,
                    currentUserId: currentUserId,
                    isMe: true,
                    onTap: () {
                      showReactionDetailsSheet(
                        context: context,
                        reactions: reactions,
                        currentUserId: currentUserId,
                        onRemoveReaction: onReactionSelected,
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Compact single-line bubble: text & timestamp side-by-side with dynamic snug fit
  Widget _buildShortSingleLine(
    BuildContext context,
    MessageDeliveryStatus deliveryStatus,
    bool isSmallScreen,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 7, 10, 7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            message,
            style: TextStyle(
              fontSize: isSmallScreen ? 14 : 15,
              color: Colors.white,
              height: 1.2,
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                date,
                style: TextStyle(
                  fontSize: isSmallScreen ? 11 : 12,
                  fontWeight: FontWeight.w400,
                  color: Colors.white.withValues(alpha: 0.65),
                  height: 1.2,
                ),
              ),
              const SizedBox(width: 4),
              MessageStatusIcon(
                status: deliveryStatus,
                size: isSmallScreen ? 14 : 15,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Edge-to-edge media with a floating frosted pill for timestamp & delivery ticks
  Widget _buildPureMedia(
    BuildContext context,
    MessageDeliveryStatus deliveryStatus,
    bool isReplying,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isReplying)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: _buildReplyHeader(context),
          ),
        Stack(
          children: [
            DisplayMessages(
              key: ValueKey('dm_${messageId}_$messageType'),
              message: message,
              messageType: messageType,
              fileMessageData: fileMessageData,
              isPreviewable: true,
              useCachedMedia: true,
              isMe: true,
              isSending: isSending,
              messageId: messageId,
              currentUserId: currentUserId,
              receiverId: receiverId,
              senderName: 'You',
            ),
            // Floating frosted pill for timestamp & status
            Positioned(
              bottom: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.15),
                    width: 0.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      date,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                    const SizedBox(width: 4),
                    MessageStatusIcon(status: deliveryStatus, size: 14),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Multi-line or captioned content that dynamically sizes to the message width
  Widget _buildDynamicContent(
    BuildContext context,
    MessageDeliveryStatus deliveryStatus,
    bool isReplying,
    bool isMedia,
    bool isSmallScreen,
  ) {
    final isCustomBubble = messageType == 'document' ||
        messageType == 'location' ||
        messageType == 'live_location';

    return Padding(
      padding: (isMedia || isCustomBubble)
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(12, 8, 12, 6),
      // NOTE: IntrinsicWidth was removed here — it's incompatible with
      // LayoutBuilder widgets (e.g. AnyLinkPreview) and caused a render crash.
      // The parent ConstrainedBox(maxWidth: 0.75) already limits bubble width.
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isReplying)
            Padding(
              padding: (isMedia || isCustomBubble)
                  ? const EdgeInsets.fromLTRB(8, 8, 8, 4)
                  : const EdgeInsets.only(bottom: 6),
              child: _buildReplyHeader(context),
            ),
          DisplayMessages(
            key: ValueKey('dm_${messageId}_$messageType'),
            message: message,
            messageType: messageType,
            fileMessageData: fileMessageData,
            isPreviewable: true,
            isMe: true,
            isSending: isSending,
            messageId: messageId,
            currentUserId: currentUserId,
            receiverId: receiverId,
            senderName: 'You',
          ),
          // Dynamic bottom row without Spacer to hug message bounds
          Padding(
            padding: (isMedia || isCustomBubble)
                ? const EdgeInsets.fromLTRB(10, 4, 10, 6)
                : const EdgeInsets.only(top: 3),
            child: Row(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(width: 14), // Minimum separation
                Text(
                  date,
                  style: TextStyle(
                    fontSize: isSmallScreen ? 11 : 12,
                    fontWeight: FontWeight.w400,
                    color: Colors.white.withValues(alpha: 0.65),
                  ),
                ),
                const SizedBox(width: 4),
                MessageStatusIcon(
                  status: deliveryStatus,
                  size: isSmallScreen ? 14 : 15,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Sleek glassy reply preview quote
  Widget _buildReplyHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(10),
        border: const Border(
          left: BorderSide(
            color: Color(0xFFFF6584), // Premium coral pink accent
            width: 3.5,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            username,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: Color(0xFFFF85A1),
            ),
          ),
          const SizedBox(height: 2),
          DisplayMessages(
            message: repliedText,
            messageType: repliedMessageType,
            fileMessageData: repliedText,
            isPreviewable: false,
            useCachedMedia: true,
          ),
        ],
      ),
    );
  }
}
