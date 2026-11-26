import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:swipe_to/swipe_to.dart';
import 'package:worship_chat/common/utils/google_lens_service.dart';
import 'package:worship_chat/common/utils/utils.dart';
import 'package:worship_chat/common/utils/wish_helper.dart';
import 'package:worship_chat/features/settings/providers/chat_bubble_settings_provider.dart';
import 'display_messages.dart';
import 'message_reaction_dialog.dart';
import 'wish_bubble_content_widget.dart';

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
  final VoidCallback? onDelete;
  final VoidCallback? onPin;
  final VoidCallback? onReplyTap;
  final bool isNewlyReceived;
  final bool isEdited;
  final bool isDeleted;
  final bool isPinned;

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
    this.onDelete,
    this.onPin,
    this.onReplyTap,
    this.isNewlyReceived = false,
    this.isEdited = false,
    this.isDeleted = false,
    this.isPinned = false,
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
    final isPureMedia = !widget.isDeleted && isMedia && !hasCaption;
    final isPureGif = !widget.isDeleted && widget.messageType == 'gif' && !hasCaption && !isReplying;

    final double mediaWidth = isSmallScreen
        ? (screenWidth * 0.70).clamp(220.0, 275.0)
        : 295.0;
    final double mediaHeight = isSmallScreen ? 235.0 : 265.0;

    final isWish = !widget.isDeleted && WishHelper.isWish(
      messageType: widget.messageType,
      text: widget.message,
    );

    // Compact single-line detection for short messages (like "hi", "ok", "yes")
    final isShortSingleLine = !widget.isDeleted &&
        widget.messageType == 'text' &&
        !isWish &&
        !isReplying &&
        !widget.message.contains('\n') &&
        !widget.message.contains('http://') &&
        !widget.message.contains('https://') &&
        widget.message.length <= 25;

    final bubbleRadius = isWish
        ? WishHelper.getBubbleRadius(isMe: false, isSmallScreen: isSmallScreen)
        : const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(18),
          );

    return SwipeTo(
      iconSize: 0,
      swipeSensitivity: 8,
      onRightSwipe: widget.isDeleted ? null : (details) => widget.onRightSwipe(),
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
                        onReply: widget.isDeleted ? null : widget.onRightSwipe,
                        onCopy: widget.isDeleted ? null : () => _copyMessage(context),
                        onForward: widget.isDeleted ? null : widget.onForward,
                        onGoogleLens: (widget.isDeleted || widget.messageType != 'image')
                            ? null
                            : () {
                                final mediaUrl = widget.fileMessageData?.isNotEmpty == true
                                    ? widget.fileMessageData!
                                    : widget.message;
                                GoogleLensService.search(
                                  context: context,
                                  imageUrl: mediaUrl,
                                );
                              },
                        onPin: widget.isDeleted ? null : widget.onPin,
                        isPinned: widget.isPinned,
                        onDelete: widget.onDelete,
                        isMyMessage: false,
                        isDeleted: widget.isDeleted,
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
                              boxShadow: isWish
                                  ? WishHelper.getBubbleShadow(
                                      text: widget.message,
                                    )
                                  : [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.14),
                                        blurRadius: 10,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                            ),
                      child: ClipRRect(
                        borderRadius: isPureGif
                            ? BorderRadius.circular(16)
                            : bubbleRadius,
                        child: isPureGif
                            ? (widget.isDeleted
                                ? _buildDeletedMessage(context, isSmallScreen)
                                : isWish
                                    ? _buildWishMessage(
                                        context,
                                        isReplying,
                                        isSmallScreen,
                                      )
                                    : isPureMedia
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
                                              ))
                            : Consumer(
                                  builder: (context, ref, _) {
                                    final bubbleSettings = ref.watch(chatBubbleSettingsProvider);
                                    final gradientColors = bubbleSettings.getBubbleGradientColors(isMe: false);
                                    final borderColor = bubbleSettings.getBubbleBorderColor(isMe: false);
                                    final contrast = bubbleSettings.getTextContrast(
                                      isMe: false,
                                      backdropColor: Theme.of(context).scaffoldBackgroundColor,
                                    );

                                    return Container(
                                      decoration: isWish
                                          ? BoxDecoration(
                                              borderRadius: bubbleRadius,
                                              gradient: WishHelper.getBubbleGradient(
                                                isMe: false,
                                                text: widget.message,
                                              ),
                                              border: WishHelper.getBubbleBorder(
                                                text: widget.message,
                                              ),
                                            )
                                          : BoxDecoration(
                                              borderRadius: bubbleRadius,
                                              gradient: LinearGradient(
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                                colors: gradientColors,
                                                stops: const [0.0, 0.45, 1.0],
                                              ),
                                              border: Border.all(
                                                color: borderColor,
                                                width: 1.0,
                                              ),
                                            ),
                                      child: widget.isDeleted
                                          ? _buildDeletedMessage(context, isSmallScreen, contrast)
                                          : isWish
                                              ? _buildWishMessage(
                                                  context,
                                                  isReplying,
                                                  isSmallScreen,
                                                )
                                              : isPureMedia
                                                  ? _buildPureMedia(
                                                      context,
                                                      isReplying,
                                                      bubbleRadius,
                                                      mediaWidth,
                                                      mediaHeight,
                                                    )
                                                  : isShortSingleLine
                                                      ? _buildShortSingleLine(context, isSmallScreen, contrast)
                                                      : _buildDynamicContent(
                                                          context,
                                                          isReplying,
                                                          isMedia,
                                                          isSmallScreen,
                                                          hasCaption,
                                                          bubbleRadius,
                                                          mediaWidth,
                                                          mediaHeight,
                                                          contrast,
                                                        ),
                                    );
                                  },
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

  /// Ornate royal proclamation wish bubble
  Widget _buildWishMessage(
    BuildContext context,
    bool isReplying,
    bool isSmallScreen,
  ) {
    final wishWidget = WishBubbleContentWidget(
      text: widget.message,
      date: widget.date,
      isMe: false,
      senderName: widget.username,
      isSmallScreen: isSmallScreen,
    );

    if (!isReplying) {
      return wishWidget;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 2),
          child: _buildReplyHeader(context),
        ),
        wishWidget,
      ],
    );
  }

  /// Deleted message bubble matching WhatsApp / Telegram
  Widget _buildDeletedMessage(
    BuildContext context,
    bool isSmallScreen, [
    BubbleTextContrast? contrast,
  ]) {
    final effectiveContrast = contrast ??
        ChatBubbleSettings.contrastForBackground(const Color(0xFF15141F));
    const displayText = 'This message was deleted';
    final deletedColor = effectiveContrast.isLightBackground
        ? const Color(0xFF6E6A7C)
        : const Color(0xFFA09EB0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            Icons.block_flipped,
            size: isSmallScreen ? 14 : 16,
            color: deletedColor,
          ),
          const SizedBox(width: 6),
          Text(
            displayText,
            style: TextStyle(
              fontSize: isSmallScreen ? 13.5 : 14.5,
              fontStyle: FontStyle.italic,
              color: deletedColor,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            widget.date,
            style: TextStyle(
              fontSize: isSmallScreen ? 10.5 : 11.5,
              color: effectiveContrast.secondaryTextColor.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  /// Compact single-line bubble: text & timestamp side-by-side with dynamic snug fit
  Widget _buildShortSingleLine(
    BuildContext context,
    bool isSmallScreen, [
    BubbleTextContrast? contrast,
  ]) {
    final effectiveContrast = contrast ??
        ChatBubbleSettings.contrastForBackground(const Color(0xFF15141F));

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
              color: effectiveContrast.primaryTextColor,
              height: 1.2,
              shadows: effectiveContrast.textShadows,
            ),
          ),
          const SizedBox(width: 8),
          if (widget.isPinned)
            MessagePinBadge(size: isSmallScreen ? 10.5 : 11.5),
          if (widget.isEdited) ...[
            Text(
              'edited',
              style: TextStyle(
                fontSize: isSmallScreen ? 10 : 11,
                fontStyle: FontStyle.italic,
                color: effectiveContrast.secondaryTextColor.withValues(alpha: 0.8),
                height: 1.2,
                shadows: effectiveContrast.textShadows,
              ),
            ),
            const SizedBox(width: 4),
          ],
          Text(
            widget.date,
            style: TextStyle(
              fontSize: isSmallScreen ? 11 : 12,
              fontWeight: FontWeight.w400,
              color: effectiveContrast.secondaryTextColor,
              height: 1.2,
              shadows: effectiveContrast.textShadows,
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
          mediaHeight: widget.messageType == 'image' ? null : mediaHeight,
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
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.isPinned) const MessagePinBadge(size: 10.5),
                if (widget.isEdited) ...[
                  Text(
                    'edited',
                    style: TextStyle(
                      fontSize: 10,
                      fontStyle: FontStyle.italic,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                Text(
                  widget.date,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
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
    bool isReplying,
    bool isMedia,
    bool isSmallScreen,
    bool hasCaption,
    BorderRadius bubbleRadius,
    double mediaWidth,
    double mediaHeight, [
    BubbleTextContrast? contrast,
  ]) {
    final effectiveContrast = contrast ??
        ChatBubbleSettings.contrastForBackground(const Color(0xFF15141F));
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
              textColor: effectiveContrast.primaryTextColor,
              mediaWidth: isMedia ? mediaWidth : null,
              mediaHeight: widget.messageType == 'image'
                  ? null
                  : (isMedia ? mediaHeight : null),
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
                    color: effectiveContrast.primaryTextColor,
                    shadows: effectiveContrast.textShadows,
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
                  if (widget.isPinned)
                    MessagePinBadge(size: isSmallScreen ? 10.5 : 11.5),
                  if (widget.isEdited) ...[
                    Text(
                      'edited',
                      style: TextStyle(
                        fontSize: isSmallScreen ? 10 : 11,
                        fontStyle: FontStyle.italic,
                        color: effectiveContrast.secondaryTextColor.withValues(alpha: 0.8),
                        shadows: effectiveContrast.textShadows,
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    widget.date,
                    style: TextStyle(
                      fontSize: isSmallScreen ? 11 : 12,
                      fontWeight: FontWeight.w400,
                      color: effectiveContrast.secondaryTextColor,
                      shadows: effectiveContrast.textShadows,
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
  Widget _buildReplyHeader(BuildContext context, [BubbleTextContrast? contrast]) {
    final effectiveContrast = contrast ??
        ChatBubbleSettings.contrastForBackground(const Color(0xFF15141F));
    final isStoryReply = widget.repliedMessageType == 'story';
    return GestureDetector(
      onTap: widget.onReplyTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: effectiveContrast.isLightBackground
              ? Colors.black.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(10),
          border: Border(
            left: BorderSide(
              color: widget.repliedMessageType == 'wish'
                  ? const Color(0xFFFFD700)
                  : isStoryReply
                  ? const Color(0xFFFF2D55)
                  : (effectiveContrast.isLightBackground
                      ? const Color(0xFF6B186B)
                      : const Color(0xFF8B7FF5)), // Iris lavender accent
              width: 3.5,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isStoryReply) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF2D55), Color(0xFFFF7A00)],
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.history_toggle_off, color: Colors.white, size: 10),
                        SizedBox(width: 3),
                        Text(
                          'Story',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                Text(
                  widget.username.isNotEmpty ? widget.username : (isStoryReply ? 'Story' : ''),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: widget.repliedMessageType == 'wish'
                        ? const Color(0xFFFFD700)
                        : (effectiveContrast.isLightBackground
                            ? const Color(0xFF5A189A)
                            : const Color(0xFFB1A9FF)),
                  ),
                ),
              ],
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
              textColor: effectiveContrast.primaryTextColor,
            ),
          ],
        ),
      ),
    );
  }
}