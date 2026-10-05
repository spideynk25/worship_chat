import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:worship_chat/colors.dart';

/// Quick emojis for the floating reaction bar (WhatsApp / Telegram style)
const List<String> kQuickReactionEmojis = [
  '👍',
  '❤️',
  '😂',
  '😮',
  '😢',
  '🙏',
];

/// Expanded emoji palette when tapping '+'
const List<String> kExtendedReactionEmojis = [
  '🔥',
  '🎉',
  '👏',
  '💯',
  '✨',
  '💔',
  '🙌',
  '🤝',
  '😍',
  '🥰',
  '🤔',
  '👀',
  '😎',
  '🥳',
  '🤩',
  '💪',
  '🕊️',
  '✝️',
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
    VoidCallback? onDelete,
    bool isMyMessage = false,
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
            onDelete: onDelete,
            isMyMessage: isMyMessage,
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
  final VoidCallback? onDelete;
  final bool isMyMessage;
  final Animation<double> animation;

  const _ReactionOverlay({
    required this.targetRect,
    required this.currentUserId,
    required this.reactions,
    required this.onReactionSelected,
    this.onReply,
    this.onCopy,
    this.onForward,
    this.onDelete,
    required this.isMyMessage,
    required this.animation,
  });

  @override
  State<_ReactionOverlay> createState() => _ReactionOverlayState();
}

class _ReactionOverlayState extends State<_ReactionOverlay> {
  bool _showExtended = false;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final topPadding = MediaQuery.of(context).padding.top;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    // Check if the message is close to top or bottom
    final bool showAbove = widget.targetRect.top > 120;

    // Calculate vertical position for the reaction bar
    double barTop;
    if (showAbove) {
      barTop = widget.targetRect.top - 102;
      if (barTop < topPadding + 10) barTop = topPadding + 10;
    } else {
      barTop = widget.targetRect.bottom + 10;
      if (barTop > screenSize.height - bottomPadding - 120) {
        barTop = screenSize.height - bottomPadding - 120;
      }
    }

    // Horizontal alignment following message bubble
    double? barLeft;
    double? barRight;
    if (widget.isMyMessage) {
      barRight = 16.0;
    } else {
      barLeft = 16.0;
    }

    final myCurrentEmoji = widget.currentUserId != null
        ? widget.reactions[widget.currentUserId]
        : null;

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

        // Floating Reaction Bar + Action Menu
        Positioned(
          top: barTop,
          left: barLeft,
          right: barRight,
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
              child: Column(
                crossAxisAlignment: widget.isMyMessage
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Quick Emojis Pill Bar ─────────────────────────────────
                  ClipRRect(
                    borderRadius: BorderRadius.circular(32),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xE61B182B),
                          borderRadius: BorderRadius.circular(32),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.14),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.45),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ...kQuickReactionEmojis.map((emoji) {
                              final isSelected = myCurrentEmoji == emoji;
                              return _EmojiButton(
                                emoji: emoji,
                                isSelected: isSelected,
                                onTap: () {
                                  Navigator.of(context).pop();
                                  widget.onReactionSelected(emoji);
                                },
                              );
                            }),
                            // Expand '+' button
                            GestureDetector(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() {
                                  _showExtended = !_showExtended;
                                });
                              },
                              child: Container(
                                width: 36,
                                height: 36,
                                margin: const EdgeInsets.symmetric(horizontal: 2),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _showExtended
                                      ? tabColor.withValues(alpha: 0.3)
                                      : Colors.white.withValues(alpha: 0.08),
                                ),
                                child: Icon(
                                  _showExtended
                                      ? Icons.close_rounded
                                      : Icons.add_rounded,
                                  size: 18,
                                  color: _showExtended ? tabColor : Colors.white70,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // ── Extended Emoji Palette Grid (If expanded) ─────────────
                  if (_showExtended) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                        child: Container(
                          width: 280,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xF21B182B),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.12),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.4),
                                blurRadius: 20,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.center,
                            children: kExtendedReactionEmojis.map((emoji) {
                              final isSelected = myCurrentEmoji == emoji;
                              return _EmojiButton(
                                emoji: emoji,
                                isSelected: isSelected,
                                onTap: () {
                                  Navigator.of(context).pop();
                                  widget.onReactionSelected(emoji);
                                },
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                  ],

                  // ── Message Actions (Reply, Copy, Delete) ─────────────────
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xE61B182B),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.10),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.35),
                              blurRadius: 14,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.onReply != null)
                              _ActionButton(
                                icon: Icons.reply_rounded,
                                label: 'Reply',
                                onTap: () {
                                  Navigator.of(context).pop();
                                  widget.onReply!();
                                },
                              ),
                            if (widget.onCopy != null)
                              _ActionButton(
                                icon: Icons.copy_rounded,
                                label: 'Copy',
                                onTap: () {
                                  Navigator.of(context).pop();
                                  widget.onCopy!();
                                },
                              ),
                            if (widget.onForward != null)
                              _ActionButton(
                                icon: Icons.forward_rounded,
                                label: 'Forward',
                                onTap: () {
                                  Navigator.of(context).pop();
                                  widget.onForward!();
                                },
                              ),
                            if (widget.isMyMessage && widget.onDelete != null)
                              _ActionButton(
                                icon: Icons.delete_outline_rounded,
                                label: 'Delete',
                                color: Colors.redAccent,
                                onTap: () {
                                  Navigator.of(context).pop();
                                  widget.onDelete!();
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
}

class _EmojiButton extends StatefulWidget {
  final String emoji;
  final bool isSelected;
  final VoidCallback onTap;

  const _EmojiButton({
    required this.emoji,
    required this.isSelected,
    required this.onTap,
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
          width: 38,
          height: 38,
          margin: const EdgeInsets.symmetric(horizontal: 2),
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
            style: const TextStyle(fontSize: 22),
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = Colors.white70,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
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
