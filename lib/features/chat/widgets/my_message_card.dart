import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:swipe_to/swipe_to.dart';
import 'package:worship_chat/common/enums/message_status_enum.dart';
import 'package:worship_chat/common/utils/utils.dart';
import 'display_messages.dart';
import 'message_reaction_dialog.dart';

class MyMessageCard extends StatefulWidget {
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
    this.isNewlySent = false,
    this.messageId,
    this.currentUserId,
    this.receiverId,
    this.reactions = const {},
    this.onReactionSelected,
    this.onForward,
    this.onDelete,
  });

  final bool isNewlySent;

  @override
  State<MyMessageCard> createState() => _MyMessageCardState();
}

class _MyMessageCardState extends State<MyMessageCard>
    with TickerProviderStateMixin {
  late final AnimationController _entranceController;
  late final Animation<double> _entranceFadeAnimation;
  late final Animation<double> _entranceScaleAnimation;
  late final Animation<Offset> _entranceSlideAnimation;

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  late final AnimationController _settleController;
  late final Animation<double> _settleScaleAnimation;

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
      begin: const Offset(0.04, 0.12),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: Curves.easeOutCubic,
      ),
    );

    // ── "While Sending" Breathing Pulse (Border shimmer & soft aura) ─
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _pulseAnimation = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOutSine,
    );

    // ── "Sent!" Micro-pop Confirmation ──────────────────────────────
    _settleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );

    _settleScaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.03)
            .chain(CurveTween(curve: Curves.easeOutQuad)),
        weight: 45,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.03, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInQuad)),
        weight: 55,
      ),
    ]).animate(_settleController);

    final messageKey = widget.messageId;
    final alreadyAnimated =
        messageKey != null && _animatedMessageIds.contains(messageKey);
    final shouldAnimateEntrance =
        !alreadyAnimated && (widget.isSending || widget.isNewlySent);

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

    if (widget.isSending) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant MyMessageCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isSending && !widget.isSending) {
      // Transitioned from in-flight to delivered: stop pulse and play settle micro-pop
      _pulseController.stop();
      _pulseController.reset();
      _settleController.forward(from: 0.0);
    } else if (!oldWidget.isSending && widget.isSending) {
      // Transitioned back to sending (e.g. retry)
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _pulseController.dispose();
    _settleController.dispose();
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

    final deliveryStatus = MessageDeliveryStatus.fromFlags(
      isSeen: widget.isSeen,
      isDelivered: widget.isDelivered,
      isSending: widget.isSending,
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
      onLeftSwipe: (details) => widget.onLeftSwipe(),
      child: Align(
        alignment: Alignment.bottomRight,
        child: AnimatedBuilder(
          animation: Listenable.merge([
            _entranceController,
            _settleController,
          ]),
          builder: (context, child) {
            final entranceScale = _entranceScaleAnimation.value;
            final settleScale = _settleController.isAnimating
                ? _settleScaleAnimation.value
                : 1.0;
            final combinedScale = entranceScale * settleScale;

            return SlideTransition(
              position: _entranceSlideAnimation,
              child: FadeTransition(
                opacity: _entranceFadeAnimation,
                child: Transform.scale(
                  scale: combinedScale,
                  alignment: Alignment.bottomRight,
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
                        onReply: widget.onLeftSwipe,
                        onCopy: () => _copyMessage(context),
                        onForward: widget.onForward,
                        onDelete: widget.onDelete,
                        isMyMessage: true,
                      );
                    },
                    child: AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, child) {
                        final isSending = widget.isSending;
                        final pulse = isSending ? _pulseAnimation.value : 0.0;

                        return Container(
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
                                  gradient: isSending
                                      ? LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [
                                            Color.lerp(
                                              const Color(0xFF6E1C4B),
                                              const Color(0xFF8B2360),
                                              pulse * 0.45,
                                            )!,
                                            Color.lerp(
                                              const Color(0xFF4E1135),
                                              const Color(0xFF631644),
                                              pulse * 0.45,
                                            )!,
                                          ],
                                        )
                                      : const LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [
                                            Color(0xFF6E1C4B), // Rich luxury wine
                                            Color(0xFF4E1135), // Deep velvety burgundy
                                          ],
                                        ),
                                  border: Border.all(
                                    color: isSending
                                        ? Color.lerp(
                                            Colors.white.withValues(alpha: 0.16),
                                            const Color(0xFFFF6DA4)
                                                .withValues(alpha: 0.50),
                                            pulse,
                                          )!
                                        : Colors.white.withValues(alpha: 0.12),
                                    width: isSending ? (0.8 + 0.35 * pulse) : 0.8,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: isSending
                                          ? Color.lerp(
                                              const Color(0xFF6E1C4B)
                                                  .withValues(alpha: 0.28),
                                              const Color(0xFF9E2A6C)
                                                  .withValues(alpha: 0.52),
                                              pulse,
                                            )!
                                          : Colors.black.withValues(alpha: 0.25),
                                      blurRadius: isSending
                                          ? (8.0 + 5.0 * pulse)
                                          : 8.0,
                                      spreadRadius: isSending
                                          ? (0.2 + 0.5 * pulse)
                                          : 0.0,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                          child: ClipRRect(
                            borderRadius: isPureGif
                                ? BorderRadius.circular(16)
                                : bubbleRadius,
                            child: Opacity(
                              opacity: isSending
                                  ? (0.92 + 0.08 * (1.0 - pulse * 0.3))
                                  : 1.0,
                              child: child,
                            ),
                          ),
                        );
                      },
                      child: isPureMedia
                          ? _buildPureMedia(
                              context,
                              deliveryStatus,
                              isReplying,
                              bubbleRadius,
                              mediaWidth,
                              mediaHeight,
                            )
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
                                  hasCaption,
                                  bubbleRadius,
                                  mediaWidth,
                                  mediaHeight,
                                ),
                    ),
                  ),
                ),

                // ── Floating Reaction Badge Capsule ───────────────────────────
                if (widget.reactions.isNotEmpty)
                  Positioned(
                    bottom: 0,
                    left: 10,
                    child: MessageReactionsBadge(
                      reactions: widget.reactions,
                      currentUserId: widget.currentUserId,
                      isMe: true,
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
            widget.message,
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
                widget.date,
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
          isMe: true,
          isSending: widget.isSending,
          messageId: widget.messageId,
          currentUserId: widget.currentUserId,
          receiverId: widget.receiverId,
          senderName: 'You',
          mediaWidth: mediaWidth,
          mediaHeight: mediaHeight,
          mediaBorderRadius: isReplying
              ? BorderRadius.only(
                  bottomLeft: bubbleRadius.bottomLeft,
                  bottomRight: bubbleRadius.bottomRight,
                )
              : bubbleRadius,
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
                  widget.date,
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
    MessageDeliveryStatus deliveryStatus,
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
              isMe: true,
              isSending: widget.isSending,
              messageId: widget.messageId,
              currentUserId: widget.currentUserId,
              receiverId: widget.receiverId,
              senderName: 'You',
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
            widget.username,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: Color(0xFFFF85A1),
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
