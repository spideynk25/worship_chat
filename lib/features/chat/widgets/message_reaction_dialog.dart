import 'dart:math' as math;
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/utils/google_lens_service.dart';
import 'package:worship_chat/features/chat/widgets/emoji_reaction_picker_sheet.dart';

/// Quick emojis for the floating reaction bar (WhatsApp style)
const List<String> kQuickReactionEmojis = [
  '👍',
  '❤️',
  '😂',
  '😮',
  '😢',
  '🙏',
];

// ─────────────────────────────────────────────────────────────────────────────
// MessageReactionDialog
// ─────────────────────────────────────────────────────────────────────────────

class MessageReactionDialog {
  MessageReactionDialog._();

  /// Displays the floating WhatsApp-style reaction bar and message actions popup
  static Future<void> show({
    required BuildContext context,
    required Rect targetRect,
    required String? currentUserId,
    required Map<String, String> reactions,
    required void Function(String emoji) onReactionSelected,
    VoidCallback? onReply,
    VoidCallback? onCopy,
    VoidCallback? onForward,
    VoidCallback? onGoogleLens,
    VoidCallback? onPin,
    bool isPinned = false,
    VoidCallback? onEdit,
    VoidCallback? onDelete,
    bool isMyMessage = false,
    bool isDeleted = false,
  }) async {
    HapticFeedback.mediumImpact();

    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black.withValues(alpha: 0.45),
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (ctx, anim, _) {
          return _ReactionOverlay(
            targetRect: targetRect,
            currentUserId: currentUserId,
            reactions: reactions,
            onReactionSelected: onReactionSelected,
            onReply: onReply,
            onCopy: onCopy,
            onForward: onForward,
            onGoogleLens: onGoogleLens,
            onPin: onPin,
            isPinned: isPinned,
            onEdit: onEdit,
            onDelete: onDelete,
            isMyMessage: isMyMessage,
            isDeleted: isDeleted,
            animation: anim,
          );
        },
      ),
    );
  }
}

class _ReactionOverlay extends StatefulWidget {
  final Rect targetRect;
  final String? currentUserId;
  final Map<String, String> reactions;
  final void Function(String emoji) onReactionSelected;
  final VoidCallback? onReply;
  final VoidCallback? onCopy;
  final VoidCallback? onForward;
  final VoidCallback? onGoogleLens;
  final VoidCallback? onPin;
  final bool isPinned;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final bool isMyMessage;
  final bool isDeleted;
  final Animation<double> animation;

  const _ReactionOverlay({
    required this.targetRect,
    required this.currentUserId,
    required this.reactions,
    required this.onReactionSelected,
    this.onReply,
    this.onCopy,
    this.onForward,
    this.onGoogleLens,
    this.onPin,
    this.isPinned = false,
    this.onEdit,
    this.onDelete,
    required this.isMyMessage,
    this.isDeleted = false,
    required this.animation,
  });

  @override
  State<_ReactionOverlay> createState() => _ReactionOverlayState();
}

class _ReactionOverlayState extends State<_ReactionOverlay> {
  void _invokeAction(VoidCallback callback) {
    Navigator.of(context).pop();
    callback();
  }

  void _selectEmoji(String emoji) {
    ReactionEmojiCatalog.recordRecent(emoji);
    Navigator.of(context).pop();
    widget.onReactionSelected(emoji);
  }

  Future<void> _openFullEmojiPicker(String? currentEmoji) async {
    HapticFeedback.selectionClick();
    final picked = await EmojiReactionPickerSheet.show(
      context,
      selectedEmoji: currentEmoji,
    );
    if (picked != null && mounted) {
      Navigator.of(context).pop();
      widget.onReactionSelected(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screenSize = media.size;
    final padding = media.padding;

    final double toolbarHeight = screenSize.height < 420 ? 56.0 : 76.0;
    final double topBarHeight = padding.top + toolbarHeight;

    final double horizontalMargin = screenSize.width < 360 ? 8.0 : 12.0;
    final double leftInset = padding.left + horizontalMargin;
    final double rightInset = padding.right + horizontalMargin;
    final double topInset = topBarHeight + 8.0;
    final double bottomInset = padding.bottom + 10.0;

    final double availableWidth = math.max(
      140.0,
      screenSize.width - leftInset - rightInset,
    );
    final bool isCompactEmojis = availableWidth < 330;
    final bool isTabletOrWide = screenSize.width > 520;

    final localTargetRect = widget.targetRect.translate(-leftInset, -topInset);

    final myCurrentEmoji = widget.currentUserId != null
        ? widget.reactions[widget.currentUserId]
        : null;
    final List<String> quickEmojis =
        (myCurrentEmoji != null &&
                myCurrentEmoji.isNotEmpty &&
                !kQuickReactionEmojis.contains(myCurrentEmoji))
            ? [...kQuickReactionEmojis.take(5), myCurrentEmoji]
            : kQuickReactionEmojis;

    final actions = <_AppBarActionItem>[
      if (!widget.isDeleted && widget.onReply != null)
        _AppBarActionItem(
          icon: Icons.reply_rounded,
          label: 'Reply',
          onTap: () => _invokeAction(widget.onReply!),
        ),
      if (!widget.isDeleted && widget.onPin != null)
        _AppBarActionItem(
          icon: widget.isPinned
              ? Icons.push_pin_rounded
              : Icons.push_pin_outlined,
          label: widget.isPinned ? 'Unpin' : 'Pin',
          color: widget.isPinned ? const Color(0xFFFFD700) : Colors.white,
          onTap: () => _invokeAction(widget.onPin!),
        ),
      if (widget.onDelete != null)
        _AppBarActionItem(
          icon: Icons.delete_outline_rounded,
          label: 'Delete',
          color: Colors.redAccent,
          onTap: () => _invokeAction(widget.onDelete!),
        ),
      if (!widget.isDeleted && widget.onForward != null)
        _AppBarActionItem(
          icon: Icons.forward_rounded,
          label: 'Forward',
          onTap: () => _invokeAction(widget.onForward!),
        ),
      if (!widget.isDeleted && widget.onCopy != null)
        _AppBarActionItem(
          icon: Icons.copy_rounded,
          label: 'Copy',
          onTap: () => _invokeAction(widget.onCopy!),
        ),
      if (!widget.isDeleted && widget.isMyMessage && widget.onEdit != null)
        _AppBarActionItem(
          icon: Icons.edit_outlined,
          label: 'Edit',
          color: tabColor,
          onTap: () => _invokeAction(widget.onEdit!),
        ),
      if (!widget.isDeleted && widget.onGoogleLens != null)
        _AppBarActionItem(
          customIcon: const GoogleLensIcon(size: 20),
          icon: Icons.image_search_rounded,
          label: 'Lens',
          onTap: () => _invokeAction(widget.onGoogleLens!),
        ),
    ];

    final double emojiButtonSize = isCompactEmojis ? 33.0 : 38.0;
    final double emojiFontSize = isCompactEmojis ? 19.0 : 22.0;
    final double emojiMargin = isCompactEmojis ? 1.5 : 2.0;
    final double expandButtonSize = isCompactEmojis ? 32.0 : 36.0;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // Dismiss backdrop
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
              child: const SizedBox.expand(),
            ),
          ),

          // Subtle row highlight strip below top AppBar
          Positioned(
            top: topBarHeight,
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: ClipRect(
                child: Stack(
                  children: [
                    Positioned(
                      top: widget.targetRect.top - topBarHeight - 4,
                      left: 0,
                      right: 0,
                      height: widget.targetRect.height + 8,
                      child: Container(
                        decoration: BoxDecoration(
                          color: tabColor.withValues(alpha: 0.12),
                          border: Border.symmetric(
                            horizontal: BorderSide(
                              color: tabColor.withValues(alpha: 0.25),
                              width: 0.6,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Bounded Floating Emoji Reaction Bar (above or below pressed bubble)
          if (!widget.isDeleted)
            Positioned(
              top: topInset,
              bottom: bottomInset,
              left: leftInset,
              right: rightInset,
              child: CustomSingleChildLayout(
                delegate: _ReactionOverlayLayoutDelegate(
                  localTargetRect: localTargetRect,
                  isMyMessage: widget.isMyMessage,
                  isTabletOrWide: isTabletOrWide,
                ),
                child: FadeTransition(
                  opacity: CurvedAnimation(
                    parent: widget.animation,
                    curve: Curves.easeOut,
                  ),
                  child: ScaleTransition(
                    scale: CurvedAnimation(
                      parent: widget.animation,
                      curve: Curves.elasticOut,
                      reverseCurve: Curves.easeIn,
                    ),
                    alignment: widget.isMyMessage
                        ? Alignment.topRight
                        : Alignment.topLeft,
                    child: SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: widget.isMyMessage
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // ── Quick Emojis Pill Bar ─────────────────────────
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: availableWidth,
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(32),
                              child: BackdropFilter(
                                filter:
                                    ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: isCompactEmojis ? 6 : 8,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xE61B182B),
                                    borderRadius: BorderRadius.circular(32),
                                    border: Border.all(
                                      color:
                                          Colors.white.withValues(alpha: 0.14),
                                      width: 1.2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color:
                                            Colors.black.withValues(alpha: 0.45),
                                        blurRadius: 20,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        ...quickEmojis.map((emoji) {
                                          final isSelected =
                                              myCurrentEmoji == emoji;
                                          return _EmojiButton(
                                            emoji: emoji,
                                            isSelected: isSelected,
                                            size: emojiButtonSize,
                                            fontSize: emojiFontSize,
                                            horizontalMargin: emojiMargin,
                                            onTap: () => _selectEmoji(emoji),
                                          );
                                        }),
                                        // Full emoji picker '+' button
                                        Tooltip(
                                          message: 'More emojis',
                                          child: GestureDetector(
                                            onTap: () => _openFullEmojiPicker(
                                              myCurrentEmoji,
                                            ),
                                            child: Container(
                                              width: expandButtonSize,
                                              height: expandButtonSize,
                                              margin: EdgeInsets.symmetric(
                                                horizontal: emojiMargin,
                                              ),
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: Colors.white.withValues(
                                                  alpha: 0.08,
                                                ),
                                              ),
                                              child: const Icon(
                                                Icons.add_rounded,
                                                size: 18,
                                                color: Colors.white70,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // WhatsApp-Style Top Contextual Action AppBar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: topBarHeight,
            child: FadeTransition(
              opacity: CurvedAnimation(
                parent: widget.animation,
                curve: Curves.easeOut,
              ),
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, -0.25),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(
                    parent: widget.animation,
                    curve: Curves.easeOutCubic,
                  ),
                ),
                child: _ContextualActionAppBar(
                  topPadding: padding.top,
                  leftPadding: padding.left,
                  rightPadding: padding.right,
                  screenWidth: screenSize.width,
                  actions: actions,
                  onClose: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReactionOverlayLayoutDelegate extends SingleChildLayoutDelegate {
  final Rect localTargetRect;
  final bool isMyMessage;
  final bool isTabletOrWide;

  const _ReactionOverlayLayoutDelegate({
    required this.localTargetRect,
    required this.isMyMessage,
    required this.isTabletOrWide,
  });

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints(
      maxWidth: constraints.maxWidth,
      maxHeight: constraints.maxHeight,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final maxX = math.max(0.0, size.width - childSize.width);
    final maxY = math.max(0.0, size.height - childSize.height);

    final double rawX = isTabletOrWide
        ? (isMyMessage
            ? localTargetRect.right - childSize.width
            : localTargetRect.left)
        : (isMyMessage ? maxX : 0.0);
    final double x = rawX.clamp(0.0, maxX);

    const double gap = 10.0;
    final double anchorTop = localTargetRect.top.clamp(0.0, size.height);
    final double anchorBottom = localTargetRect.bottom.clamp(0.0, size.height);
    final double spaceAbove = anchorTop - gap;
    final double spaceBelow = size.height - anchorBottom - gap;

    double y;
    if (spaceAbove >= childSize.height) {
      y = anchorTop - gap - childSize.height;
    } else if (spaceBelow >= childSize.height) {
      y = anchorBottom + gap;
    } else if (spaceAbove >= spaceBelow) {
      y = anchorTop - gap - childSize.height;
    } else {
      y = anchorBottom + gap;
    }
    y = y.clamp(0.0, maxY);

    return Offset(x, y);
  }

  @override
  bool shouldRelayout(covariant _ReactionOverlayLayoutDelegate oldDelegate) {
    return oldDelegate.localTargetRect != localTargetRect ||
        oldDelegate.isMyMessage != isMyMessage ||
        oldDelegate.isTabletOrWide != isTabletOrWide;
  }
}

class _EmojiButton extends StatefulWidget {
  final String emoji;
  final bool isSelected;
  final VoidCallback onTap;
  final double size;
  final double fontSize;
  final double horizontalMargin;

  const _EmojiButton({
    required this.emoji,
    required this.isSelected,
    required this.onTap,
    this.size = 38.0,
    this.fontSize = 22.0,
    this.horizontalMargin = 2.0,
  });

  @override
  State<_EmojiButton> createState() => _EmojiButtonState();
}

class _EmojiButtonState extends State<_EmojiButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 1.35).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutBack),
    );
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _animCtrl.forward(),
      onTapCancel: () => _animCtrl.reverse(),
      onTap: () {
        HapticFeedback.lightImpact();
        widget.onTap();
      },
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Container(
          width: widget.size,
          height: widget.size,
          margin: EdgeInsets.symmetric(horizontal: widget.horizontalMargin),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.isSelected
                ? tabColor.withValues(alpha: 0.28)
                : Colors.transparent,
            border: widget.isSelected
                ? Border.all(color: tabColor, width: 1.5)
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            widget.emoji,
            style: TextStyle(fontSize: widget.fontSize),
          ),
        ),
      ),
    );
  }
}

class _AppBarActionItem {
  final IconData icon;
  final Widget? customIcon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  const _AppBarActionItem({
    required this.icon,
    this.customIcon,
    required this.label,
    required this.onTap,
    this.color = Colors.white,
  });
}

class _ContextualActionAppBar extends StatelessWidget {
  final double topPadding;
  final double leftPadding;
  final double rightPadding;
  final double screenWidth;
  final List<_AppBarActionItem> actions;
  final VoidCallback onClose;

  const _ContextualActionAppBar({
    required this.topPadding,
    required this.leftPadding,
    required this.rightPadding,
    required this.screenWidth,
    required this.actions,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final double usableWidth =
        math.max(200.0, screenWidth - leftPadding - rightPadding);
    const double leftLeadWidth = 88.0;
    const double iconSlotWidth = 40.0;
    const double overflowBtnWidth = 38.0;

    final double actionBudget = math.max(0.0, usableWidth - leftLeadWidth);
    final bool allFitInline = actions.length * iconSlotWidth <= actionBudget;

    late final List<_AppBarActionItem> inlineActions;
    late final List<_AppBarActionItem> overflowActions;

    if (allFitInline) {
      inlineActions = actions;
      overflowActions = const [];
    } else {
      final int maxInline = math.max(
        1,
        ((actionBudget - overflowBtnWidth) / iconSlotWidth).floor(),
      );
      inlineActions = actions.take(maxInline).toList();
      overflowActions = actions.skip(maxInline).toList();
    }

    return Container(
      padding: EdgeInsets.only(
        top: topPadding,
        left: leftPadding + 4,
        right: rightPadding + 4,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF161426),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.12),
            width: 0.8,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(
              Icons.arrow_back_rounded,
              color: Colors.white,
              size: 23,
            ),
            tooltip: 'Close',
            onPressed: onClose,
          ),
          const SizedBox(width: 2),
          const Text(
            '1',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          ...inlineActions.map((action) {
            return IconButton(
              icon: action.customIcon ??
                  Icon(action.icon, color: action.color, size: 22),
              tooltip: action.label,
              constraints: const BoxConstraints(
                minWidth: 38,
                minHeight: 42,
              ),
              padding: EdgeInsets.zero,
              onPressed: () {
                HapticFeedback.selectionClick();
                action.onTap();
              },
            );
          }),
          if (overflowActions.isNotEmpty)
            PopupMenuButton<int>(
              icon: const Icon(
                Icons.more_vert_rounded,
                color: Colors.white,
                size: 22,
              ),
              tooltip: 'More actions',
              color: const Color(0xFF1D1A2F),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: Colors.white.withValues(alpha: 0.12),
                  width: 0.8,
                ),
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: 36,
                minHeight: 42,
              ),
              onSelected: (idx) {
                HapticFeedback.selectionClick();
                overflowActions[idx].onTap();
              },
              itemBuilder: (_) => List.generate(
                overflowActions.length,
                (idx) {
                  final action = overflowActions[idx];
                  return PopupMenuItem<int>(
                    value: idx,
                    height: 42,
                    child: Row(
                      children: [
                        action.customIcon ??
                            Icon(action.icon, color: action.color, size: 19),
                        const SizedBox(width: 12),
                        Text(
                          action.label,
                          style: TextStyle(
                            color: action.color,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MessageReactionsBadge
// ─────────────────────────────────────────────────────────────────────────────

/// Floating capsule badge placed on the bottom edge of a message bubble
class MessageReactionsBadge extends StatelessWidget {
  final Map<String, String> reactions;
  final String? currentUserId;
  final VoidCallback? onTap;
  final bool isMe;

  const MessageReactionsBadge({
    super.key,
    required this.reactions,
    required this.currentUserId,
    this.onTap,
    this.isMe = false,
  });

  @override
  Widget build(BuildContext context) {
    if (reactions.isEmpty) return const SizedBox.shrink();

    // Group emoji counts: {'❤️': 2, '👍': 1}
    final Map<String, int> counts = {};
    for (final emoji in reactions.values) {
      counts[emoji] = (counts[emoji] ?? 0) + 1;
    }

    final sortedEntries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Show up to 3 distinct emojis
    final topEmojis = sortedEntries.take(3).map((e) => e.key).toList();
    final totalCount = reactions.length;

    final hasMyReaction = currentUserId != null &&
        reactions.containsKey(currentUserId);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1B2E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasMyReaction
                ? tabColor.withValues(alpha: 0.6)
                : Colors.white.withValues(alpha: 0.12),
            width: hasMyReaction ? 1.2 : 0.8,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              topEmojis.join(''),
              style: const TextStyle(fontSize: 13),
            ),
            if (totalCount > 1) ...[
              const SizedBox(width: 4),
              Text(
                '$totalCount',
                style: TextStyle(
                  color: hasMyReaction ? tabColor : Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reaction Details Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────

void showReactionDetailsSheet({
  required BuildContext context,
  required Map<String, String> reactions,
  required String? currentUserId,
  void Function(String emoji)? onRemoveReaction,
}) {
  HapticFeedback.lightImpact();

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) {
      return _ReactionDetailsSheet(
        reactions: reactions,
        currentUserId: currentUserId,
        onRemoveReaction: onRemoveReaction,
      );
    },
  );
}

class _ReactionDetailsSheet extends StatefulWidget {
  final Map<String, String> reactions;
  final String? currentUserId;
  final void Function(String emoji)? onRemoveReaction;

  const _ReactionDetailsSheet({
    required this.reactions,
    required this.currentUserId,
    this.onRemoveReaction,
  });

  @override
  State<_ReactionDetailsSheet> createState() => _ReactionDetailsSheetState();
}

class _ReactionDetailsSheetState extends State<_ReactionDetailsSheet> {
  String? _selectedFilter; // null means 'All'

  @override
  Widget build(BuildContext context) {
    final Map<String, int> emojiCounts = {};
    for (final emoji in widget.reactions.values) {
      emojiCounts[emoji] = (emojiCounts[emoji] ?? 0) + 1;
    }

    final filteredEntries = widget.reactions.entries.where((entry) {
      if (_selectedFilter == null) return true;
      return entry.value == _selectedFilter;
    }).toList();

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.55,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF161424),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
          const SizedBox(height: 10),
          // Drag handle
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Header Tabs: All + Each Emoji
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _FilterChip(
                    label: 'All ${widget.reactions.length}',
                    isSelected: _selectedFilter == null,
                    onTap: () => setState(() => _selectedFilter = null),
                  ),
                  const SizedBox(width: 8),
                  ...emojiCounts.entries.map((entry) {
                    final isSel = _selectedFilter == entry.key;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _FilterChip(
                        label: '${entry.key} ${entry.value}',
                        isSelected: isSel,
                        onTap: () => setState(() => _selectedFilter = entry.key),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),

          const Divider(color: Colors.white10, height: 20),

          // List of reacted users
          Expanded(
            child: ListView.builder(
              itemCount: filteredEntries.length,
              itemBuilder: (ctx, idx) {
                final entry = filteredEntries[idx];
                final userId = entry.key;
                final emoji = entry.value;
                final isMe = userId == widget.currentUserId;

                return _ReactionUserTile(
                  userId: userId,
                  emoji: emoji,
                  isMe: isMe,
                  onRemove: isMe && widget.onRemoveReaction != null
                      ? () {
                          Navigator.of(context).pop();
                          widget.onRemoveReaction!(emoji);
                        }
                      : null,
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? tabColor.withValues(alpha: 0.25)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? tabColor : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? tabColor : Colors.white70,
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _ReactionUserTile extends StatelessWidget {
  final String userId;
  final String emoji;
  final bool isMe;
  final VoidCallback? onRemove;

  const _ReactionUserTile({
    required this.userId,
    required this.emoji,
    required this.isMe,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    if (isMe) {
      return ListTile(
        leading: Stack(
          alignment: Alignment.bottomRight,
          children: [
            const CircleAvatar(
              radius: 19,
              backgroundColor: tabColor,
              child: Icon(Icons.person, color: Colors.white, size: 20),
            ),
            Text(emoji, style: const TextStyle(fontSize: 14)),
          ],
        ),
        title: const Text(
          'You',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 14.5,
          ),
        ),
        subtitle: onRemove != null
            ? const Text(
                'Tap to remove',
                style: TextStyle(color: Colors.white54, fontSize: 11.5),
              )
            : null,
        onTap: onRemove,
      );
    }

    // Lookup user from Firestore
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.collection('users').doc(userId).get(),
      builder: (ctx, snap) {
        final data = snap.data?.data();
        final name = data?['name']?.toString() ?? 'Worship User';
        final profilePic = data?['profilePic']?.toString();

        return ListTile(
          leading: Stack(
            alignment: Alignment.bottomRight,
            children: [
              CircleAvatar(
                radius: 19,
                backgroundColor: messageColor,
                backgroundImage: (profilePic != null && profilePic.isNotEmpty)
                    ? NetworkImage(profilePic)
                    : null,
                child: (profilePic == null || profilePic.isEmpty)
                    ? const Icon(Icons.person, color: Colors.white70, size: 20)
                    : null,
              ),
              Text(emoji, style: const TextStyle(fontSize: 14)),
            ],
          ),
          title: Text(
            name,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 14.5,
            ),
          ),
        );
      },
    );
  }
}

/// Compact royal-gold pin indicator rendered next to timestamps on pinned bubbles.
class MessagePinBadge extends StatelessWidget {
  final double size;

  const MessagePinBadge({super.key, this.size = 11.0});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Icon(
        Icons.push_pin_rounded,
        size: size,
        color: const Color(0xFFFFD700),
      ),
    );
  }
}
