import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:swipe_to/swipe_to.dart';
import 'package:worship_chat/common/utils/utils.dart';
import 'display_messages.dart';
import 'message_reaction_dialog.dart';

class SenderMessageCard extends StatefulWidget {
  final String message;
  final String date;
  final String messageType;
  final String? fileMessageData;
  final VoidCallback onRightSwipe;
  final String repliedText;
  final String username;
  final String repliedMessageType;
  final String? messageId;
  final String? currentUserId;
  final String? receiverId;
  final String? senderProfilePic;
  final Map<String, String> reactions;
  final void Function(String emoji)? onReactionSelected;
  final VoidCallback? onForward;
  final bool isNewlyReceived;

  const SenderMessageCard({
    super.key,
    required this.message,
    required this.date,
    required this.messageType,
    this.fileMessageData,
    required this.onRightSwipe,
    required this.repliedText,
    required this.username,
    required this.repliedMessageType,
    this.messageId,
    this.currentUserId,
    this.receiverId,
    this.senderProfilePic,
    this.reactions = const {},
    this.onReactionSelected,
    this.onForward,
    this.isNewlyReceived = false,
  });

  @override
  State<SenderMessageCard> createState() => _SenderMessageCardState();
}

class _SenderMessageCardState extends State<SenderMessageCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entranceController;
  late final Animation<double> _entranceFadeAnimation;
  late final Animation<double> _entranceScaleAnimation;
  late final Animation<Offset> _entranceSlideAnimation;

  static final Set<String> _animatedMessageIds = <String>{};

  @override
  void initState() {
    super.initState();

    // ── Smooth Entrance Animation (Pop, Slide up & Fade) ─────────────
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );

    _entranceFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.0, 0.75, curve: Curves.easeOut),
      ),
    );

    _entranceScaleAnimation = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: Curves.easeOutBack,
      ),
    );

    _entranceSlideAnimation = Tween<Offset>(
      begin: const Offset(-0.04, 0.12),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: Curves.easeOutCubic,
      ),
    );

    final messageKey = widget.messageId;
    final alreadyAnimated =
        messageKey != null && _animatedMessageIds.contains(messageKey);
    final shouldAnimateEntrance = !alreadyAnimated && widget.isNewlyReceived;

    if (shouldAnimateEntrance) {
      if (messageKey != null) {
        _animatedMessageIds.add(messageKey);
        if (_animatedMessageIds.length > 500) {
          _animatedMessageIds.clear();
        }
      }
      _entranceController.forward(from: 0.0);
    } else {
      _entranceController.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant SenderMessageCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final messageKey = widget.messageId;
    final alreadyAnimated =
        messageKey != null && _animatedMessageIds.contains(messageKey);
    if (!alreadyAnimated &&
        widget.isNewlyReceived &&
        !_entranceController.isAnimating &&
        _entranceController.value < 1.0) {
      if (messageKey != null) {
        _animatedMessageIds.add(messageKey);
        if (_animatedMessageIds.length > 500) {
          _animatedMessageIds.clear();
        }
      }
      _entranceController.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  void _copyMessage(BuildContext context) {
    final textToCopy = widget.messageType == 'text'
        ? widget.message
        : widget.fileMessageData ?? '';
    if (textToCopy.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: textToCopy));
      AppSnackBar.success(context, 'Message copied');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isReplying = widget.repliedText.isNotEmpty;
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 600;

    final isMedia = widget.messageType == 'image' ||
        widget.messageType == 'video' ||
        widget.messageType == 'gif';
    final hasCaption = isMedia &&
        widget.message.isNotEmpty &&
        widget.message != widget.fileMessageData;
    final isPureMedia = isMedia && !hasCaption;
    final isPureGif = widget.messageType == 'gif' && !hasCaption && !isReplying;

    final double mediaWidth = isSmallScreen
        ? (screenWidth * 0.70).clamp(220.0, 275.0)
        : 295.0;
    final double mediaHeight = isSmallScreen ? 235.0 : 265.0;

    // Compact single-line detection for short messages (like "hi", "ok", "yes")
    final isShortSingleLine = widget.messageType == 'text' &&
        !isReplying &&
        !widget.message.contains('\n') &&
        !widget.message.contains('http://') &&
        !widget.message.contains('https://') &&
        widget.message.length <= 25;

    // Asymmetrical tail pointing towards sender's avatar on the left
    const bubbleRadius = BorderRadius.only(
      topLeft: Radius.circular(18),
      topRight: Radius.circular(18),
      bottomLeft: Radius.circular(4),
      bottomRight: Radius.circular(18),
    );

    return SwipeTo(
      iconSize: 0,
      swipeSensitivity: 8,
      onRightSwipe: (details) => widget.onRightSwipe(),
      child: Align(
        alignment: Alignment.bottomLeft,
        child: AnimatedBuilder(
          animation: _entranceController,
          builder: (context, child) {
            return SlideTransition(
              position: _entranceSlideAnimation,
              child: FadeTransition(
                opacity: _entranceFadeAnimation,
                child: Transform.scale(
                  scale: _entranceScaleAnimation.value,
                  alignment: Alignment.bottomLeft,
                  child: child,
                ),
              ),
            );
          },
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
                        currentUserId: widget.currentUserId,
                        reactions: widget.reactions,
                        onReactionSelected: (emoji) {
                          widget.onReactionSelected?.call(emoji);
                        },
                        onReply: widget.onRightSwipe,
                        onCopy: () => _copyMessage(context),
                        onForward: widget.onForward,
                        isMyMessage: false,
                      );
                    },
                    child: Container(
                      margin: EdgeInsets.only(
                        left: isSmallScreen ? 3 : 6,
                        right: isSmallScreen ? 3 : 6,
                        top: 2,
                        bottom: widget.reactions.isNotEmpty ? 13 : 2,
                      ),
                      decoration: isPureGif
                          ? null
                          : BoxDecoration(
                              borderRadius: bubbleRadius,
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFF262137), // Rich obsidian violet
                                  Color(0xFF1B1728), // Deep slate dusk
                                ],
                              ),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.08),
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
                            ? _buildPureMedia(
                                context,
                                isReplying,
                                bubbleRadius,
                                mediaWidth,
                                mediaHeight,
                              )
                            : isShortSingleLine
                                ? _buildShortSingleLine(context, isSmallScreen)
                                : _buildDynamicContent(
                                    context,
                                    isReplying,
                                    isMedia,
                                    isSmallScreen,
                                    hasCaption,
                                    bubbleRadius,
                                    mediaWidth,
                                    mediaHeight,
                                  ),
                      ),
                    ),
                  ),
                ),

                // ── Floating Reaction Badge Capsule ───────────────────────────
                if (widget.reactions.isNotEmpty)
                  Positioned(
                    bottom: 0,
                    right: 10,
                    child: MessageReactionsBadge(
                      reactions: widget.reactions,
                      currentUserId: widget.currentUserId,
                      isMe: false,
                      onTap: () {
                        showReactionDetailsSheet(
                          context: context,
                          reactions: widget.reactions,
                          currentUserId: widget.currentUserId,
                          onRemoveReaction: widget.onReactionSelected,
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Compact single-line bubble: text & timestamp side-by-side with dynamic snug fit
  Widget _buildShortSingleLine(BuildContext context, bool isSmallScreen) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 7, 10, 7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            widget.message,
            style: TextStyle(
              fontSize: isSmallScreen ? 14 : 15,
              color: Colors.white,
              height: 1.2,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            widget.date,
            style: TextStyle(
              fontSize: isSmallScreen ? 11 : 12,
              fontWeight: FontWeight.w400,
              color: Colors.white.withValues(alpha: 0.6),
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  /// Edge-to-edge media with a floating frosted pill for timestamp
  Widget _buildPureMedia(
    BuildContext context,
    bool isReplying,
    BorderRadius bubbleRadius,
    double mediaWidth,
    double mediaHeight,
  ) {
    final mediaContent = Stack(
      children: [
        DisplayMessages(
          key: ValueKey('dm_${widget.messageId}_${widget.messageType}'),
          message: widget.message,
          messageType: widget.messageType,
          fileMessageData: widget.fileMessageData,
          isPreviewable: true,
          useCachedMedia: true,
          isMe: false,
          messageId: widget.messageId,
          currentUserId: widget.currentUserId,
          receiverId: widget.receiverId,
          senderName: widget.username,
          senderProfilePic: widget.senderProfilePic,
          mediaWidth: mediaWidth,
          mediaHeight: mediaHeight,
          mediaBorderRadius: isReplying
              ? BorderRadius.only(
                  bottomLeft: bubbleRadius.bottomLeft,
                  bottomRight: bubbleRadius.bottomRight,
                )
              : bubbleRadius,
        ),
        // Floating frosted pill for timestamp
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
            child: Text(
              widget.date,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
          ),
        ),
      ],
    );

    if (!isReplying) {
      return SizedBox(
        width: mediaWidth,
        child: mediaContent,
      );
    }

    return SizedBox(
      width: mediaWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: _buildReplyHeader(context),
          ),
          mediaContent,
        ],
      ),
    );
  }

  /// Multi-line or captioned content that dynamically sizes to the message width
  Widget _buildDynamicContent(
    BuildContext context,
    bool isReplying,
    bool isMedia,
    bool isSmallScreen,
    bool hasCaption,
    BorderRadius bubbleRadius,
    double mediaWidth,
    double mediaHeight,
  ) {
    final isCustomBubble = widget.messageType == 'document' ||
        widget.messageType == 'location' ||
        widget.messageType == 'live_location';

    return SizedBox(
      width: isMedia ? mediaWidth : null,
      child: Padding(
        padding: (isMedia || isCustomBubble)
            ? EdgeInsets.zero
            : const EdgeInsets.fromLTRB(12, 8, 12, 6),
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
              key: ValueKey('dm_${widget.messageId}_${widget.messageType}'),
              message: widget.message,
              messageType: widget.messageType,
              fileMessageData: widget.fileMessageData,
              isPreviewable: true,
              useCachedMedia: true,
              isMe: false,
              messageId: widget.messageId,
              currentUserId: widget.currentUserId,
              receiverId: widget.receiverId,
              senderName: widget.username,
              senderProfilePic: widget.senderProfilePic,
              mediaWidth: isMedia ? mediaWidth : null,
              mediaHeight: isMedia ? mediaHeight : null,
              mediaBorderRadius: isMedia
                  ? BorderRadius.only(
                      topLeft: isReplying ? Radius.zero : bubbleRadius.topLeft,
                      topRight: isReplying ? Radius.zero : bubbleRadius.topRight,
                    )
                  : null,
            ),
            if (hasCaption)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 7, 10, 3),
                child: Text(
                  widget.message,
                  style: TextStyle(
                    fontSize: isSmallScreen ? 14 : 15,
                    color: Colors.white,
                  ),
                ),
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
                    widget.date,
                    style: TextStyle(
                      fontSize: isSmallScreen ? 11 : 12,
                      fontWeight: FontWeight.w400,
                      color: Colors.white.withValues(alpha: 0.6),
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

  /// Sleek glassy reply preview quote
  Widget _buildReplyHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(10),
        border: const Border(
          left: BorderSide(
            color: Color(0xFF8B7FF5), // Iris lavender accent
            width: 3.5,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.username,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: Color(0xFFA594F9),
            ),
          ),
          const SizedBox(height: 2),
          DisplayMessages(
            message: widget.repliedText,
            messageType: widget.repliedMessageType,
            fileMessageData: widget.repliedText,
            isPreviewable: false,
            useCachedMedia: true,
            mediaWidth: 46.0,
            mediaHeight: 46.0,
          ),
        ],
      ),
    );
  }
}