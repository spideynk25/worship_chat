import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:swipe_to/swipe_to.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/utils/google_lens_service.dart';
import 'package:worship_chat/common/utils/media_cache_service.dart';
import 'package:worship_chat/common/utils/utils.dart';
import 'package:worship_chat/common/widgets/skeleton_loader.dart';
import 'package:worship_chat/features/chat/widgets/display_messages.dart';
import 'package:worship_chat/features/chat/widgets/forward_message_sheet.dart';
import 'package:worship_chat/features/chat/widgets/message_reaction_dialog.dart';
import 'package:worship_chat/features/settings/providers/chat_bubble_settings_provider.dart';
import 'package:worship_chat/models/group_chat_message_model.dart';

/// A neutral, centered chat bubble for Roleplay Mode gallery photos.
/// Common to all participants — does NOT represent sender or receiver.
class RoleplayMessageCard extends StatefulWidget {
  final GroupChatMessageModel messageData;
  final bool isNewlySent;
  final VoidCallback onSwipe;
  final VoidCallback? onForward;
  final VoidCallback? onDelete;
  final VoidCallback? onPin;
  final bool isPinned;
  final void Function(String emoji)? onReactionSelected;
  final Color? accentColor;
  final String? queendom;

  const RoleplayMessageCard({
    super.key,
    required this.messageData,
    this.isNewlySent = false,
    required this.onSwipe,
    this.onForward,
    this.onDelete,
    this.onPin,
    this.isPinned = false,
    this.onReactionSelected,
    this.accentColor,
    this.queendom,
  });

  @override
  State<RoleplayMessageCard> createState() => _RoleplayMessageCardState();
}

class _RoleplayMessageCardState extends State<RoleplayMessageCard>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late final AnimationController _entranceController;
  late final Animation<double> _entranceFadeAnimation;
  late final Animation<double> _entranceScaleAnimation;

  /// Ensures each roleplay message only runs its entrance animation once
  /// and never flickers or re-animates on list shifts or subsequent messages.
  static final Set<String> _animatedMessageIds = <String>{};

  @override
  bool get wantKeepAlive => true;

  Color get _accent {
    if (widget.accentColor != null) return widget.accentColor!;
    final q = widget.queendom?.toLowerCase() ?? '';
    if (q.contains('pooja')) {
      return const Color(0xFFFFD700);
    } else if (q.contains('rashmika')) {
      return const Color(0xFFFF4081);
    }
    return tabColor;
  }

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _entranceFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.0, 0.8, curve: Curves.easeOut),
      ),
    );
    _entranceScaleAnimation = Tween<double>(begin: 0.90, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: Curves.easeOutBack,
      ),
    );

    if (widget.isNewlySent &&
        !_animatedMessageIds.contains(widget.messageData.messageId)) {
      _animatedMessageIds.add(widget.messageData.messageId);
      _entranceController.forward();
    } else {
      _entranceController.value = 1.0;
    }
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  void _openFullScreen(String imageUrl) {
    HapticFeedback.lightImpact();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MediaPreviewWidget(
          mediaType: 'image',
          mediaUrl: imageUrl,
        ),
      ),
    );
  }

  void _showContextMenu(BuildContext context, Offset globalPos, Size size) {
    HapticFeedback.mediumImpact();
    final rect = Rect.fromLTWH(
      globalPos.dx,
      globalPos.dy,
      size.width,
      size.height,
    );

    MessageReactionDialog.show(
      context: context,
      targetRect: rect,
      currentUserId: '',
      reactions: widget.messageData.reactions,
      onReactionSelected: (emoji) {
        widget.onReactionSelected?.call(emoji);
      },
      onReply: widget.onSwipe,
      onCopy: () {
        Clipboard.setData(ClipboardData(
          text: widget.messageData.fileMessageData ?? widget.messageData.text,
        ));
      },
      onForward: widget.onForward ??
          () {
            ForwardMessageSheet.show(
              context,
              ForwardMessagePayload(
                text: widget.messageData.text,
                messageType: 'image',
                fileMessageData: widget.messageData.fileMessageData,
                sourceGroupId: widget.messageData.groupId,
              ),
            );
          },
      onGoogleLens: () {
        final mediaUrl = widget.messageData.fileMessageData?.isNotEmpty == true
            ? widget.messageData.fileMessageData!
            : widget.messageData.text;
        GoogleLensService.search(
          context: context,
          imageUrl: mediaUrl,
        );
      },
      onPin: widget.messageData.isDeleted ? null : widget.onPin,
      isPinned: widget.isPinned,
      onDelete: widget.onDelete,
      isMyMessage: false,
    );
  }

  Widget _buildShimmerPlaceholder(Color accent) {
    return SizedBox(
      height: 220,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Base dark gradient with smooth, sweeping shimmer
          ShimmerEffect(
            baseColor: const Color(0xFF131122),
            highlightColor: accent.withValues(alpha: 0.20),
            duration: const Duration(milliseconds: 1400),
            child: Container(
              height: 220,
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFF161426),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF1E1A30),
                    accent.withValues(alpha: 0.10),
                    const Color(0xFF100E1C),
                  ],
                ),
              ),
            ),
          ),

          // Central glowing royal darshan emblem badge
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF1B172E),
                  border: Border.all(
                    color: accent.withValues(alpha: 0.5),
                    width: 1.4,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.28),
                      blurRadius: 18,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    size: 24,
                    color: accent,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: accent.withValues(alpha: 0.22),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.auto_awesome,
                      size: 11,
                      color: accent,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        'Loading Darshan Photo…',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          letterSpacing: 0.4,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Container(
      height: 140,
      color: const Color(0xFF141220),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.broken_image_rounded,
              color: Colors.white.withValues(alpha: 0.35),
              size: 32,
            ),
            const SizedBox(height: 6),
            Text(
              'Darshan photo unavailable',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImage(String url, double maxCardWidth) {
    if (url.startsWith('assets/')) {
      return Image.asset(
        url,
        width: maxCardWidth,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
      );
    }

    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      final clean = url.replaceFirst('file://', '');
      if (File(clean).existsSync()) {
        return Image.file(
          File(clean),
          width: maxCardWidth,
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
        );
      }
    }

    final optimizedUrl = getOptimizedRoleplayImageUrl(url);

    // Instant local memory or disk cache check
    final localPath = MediaCacheService().getCachedSync(optimizedUrl) ??
        MediaCacheService().getCachedSync(url);
    if (localPath != null && File(localPath).existsSync()) {
      return Image.file(
        File(localPath),
        width: maxCardWidth,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
      );
    }

    return CachedNetworkImage(
      key: ValueKey('cni_${widget.messageData.messageId}'),
      imageUrl: optimizedUrl,
      width: maxCardWidth,
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      fadeInDuration: const Duration(milliseconds: 200),
      fadeOutDuration: Duration.zero,
      memCacheWidth: 800,
      maxWidthDiskCache: 800,
      placeholder: (context, _) => _buildShimmerPlaceholder(_accent),
      errorWidget: (context, _, error) => _buildErrorWidget(),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 360;
    final cardWidth = isSmallScreen ? 230.0 : 260.0;
    final imageUrl =
        widget.messageData.fileMessageData ?? widget.messageData.text;
    final hasCaption = widget.messageData.text.isNotEmpty &&
        widget.messageData.text != widget.messageData.fileMessageData;
    final timeStr = DateFormat.jm().format(widget.messageData.timeSent);
    final accent = _accent;

    return FadeTransition(
      opacity: _entranceFadeAnimation,
      child: ScaleTransition(
        scale: _entranceScaleAnimation,
        child: SwipeTo(
          onRightSwipe: (_) => widget.onSwipe(),
          onLeftSwipe: (_) => widget.onSwipe(),
          child: Center(
            child: Container(
              margin: EdgeInsets.only(
                top: 6,
                bottom: widget.messageData.reactions.isNotEmpty ? 14 : 6,
                left: 12,
                right: 12,
              ),
              constraints: BoxConstraints(maxWidth: cardWidth),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Builder(
                    builder: (cardContext) {
                      return GestureDetector(
                        onLongPress: () {
                          final renderBox = cardContext.findRenderObject()
                              as RenderBox?;
                          final pos = renderBox != null
                              ? renderBox.localToGlobal(Offset.zero)
                              : Offset.zero;
                          final size = renderBox?.size ?? Size.zero;
                          _showContextMenu(context, pos, size);
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: accent.withValues(alpha: 0.18),
                                blurRadius: 12,
                                spreadRadius: 0.5,
                                offset: const Offset(0, 2),
                              ),
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.20),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Consumer(
                                builder: (context, ref, _) {
                                  final bubbleSettings = ref.watch(chatBubbleSettingsProvider);
                                  final roleplayColors = bubbleSettings.getRoleplayGradientColors(accent);
                                  final contrast = ChatBubbleSettings.contrastForBackground(
                                    Color.alphaBlend(
                                      Color.lerp(roleplayColors.first, roleplayColors.last, 0.5)!,
                                      Theme.of(context).scaffoldBackgroundColor,
                                    ),
                                  );

                                  return Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: roleplayColors,
                                        stops: const [0.0, 0.45, 1.0],
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: accent.withValues(
                                          alpha: bubbleSettings.computeAlpha(0.50, minAlpha: 0.20, maxAlpha: 0.80),
                                        ),
                                        width: 1.0,
                                      ),
                                    ),
                                    child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // ── Photo with tap-to-expand (No name on top) ──
                              if (imageUrl.isNotEmpty)
                                GestureDetector(
                                  onTap: () => _openFullScreen(imageUrl),
                                  child: Padding(
                                    padding: EdgeInsets.fromLTRB(
                                      5,
                                      5,
                                      5,
                                      hasCaption ? 2 : 5,
                                    ),
                                    child: Stack(
                                      children: [
                                        ConstrainedBox(
                                          constraints: BoxConstraints(
                                            minWidth: cardWidth,
                                            maxWidth: cardWidth,
                                            minHeight: 120,
                                            maxHeight: isSmallScreen ? 240 : 270,
                                          ),
                                          child: ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(13),
                                            child:
                                                _buildImage(imageUrl, cardWidth),
                                          ),
                                        ),
                                        // Subtle timestamp overlay on image when no caption
                                        if (!hasCaption)
                                          Positioned(
                                            bottom: 6,
                                            right: 6,
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.black
                                                    .withValues(alpha: 0.6),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.15),
                                                  width: 0.5,
                                                ),
                                              ),
                                              child: Text(
                                                timeStr,
                                                style: TextStyle(
                                                  fontSize: 9.5,
                                                  color: Colors.white
                                                      .withValues(alpha: 0.9),
                                                  fontWeight: FontWeight.w400,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),

                              // ── Optional Caption & Timestamp below Photo ──
                              if (hasCaption)
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(10, 4, 10, 8),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          widget.messageData.text,
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontStyle: FontStyle.italic,
                                            color: contrast.primaryTextColor,
                                          shadows: contrast.textShadows,
                                            height: 1.25,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      if (widget.isPinned)
                                        const MessagePinBadge(size: 10.5),
                                      Text(
                                        timeStr,
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          color: Colors.white
                                              .withValues(alpha: 0.55),
                                          fontWeight: FontWeight.w400,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                                ),
                              );
                            },
                          ),
                        ),
                        ),
                      );
                    },
                  ),

                  // ── Floating Reaction Badge ──────────────────────────────
                  if (widget.messageData.reactions.isNotEmpty)
                    Positioned(
                      bottom: -10,
                      left: 12,
                      child: MessageReactionsBadge(
                        reactions: widget.messageData.reactions,
                        currentUserId: '',
                        isMe: false,
                        onTap: () {
                          showReactionDetailsSheet(
                            context: context,
                            reactions: widget.messageData.reactions,
                            currentUserId: '',
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
      ),
    );
  }
}
