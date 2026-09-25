import 'package:flutter/material.dart';

/// A reusable, smooth shimmer effect that sweeps across child skeleton shapes.
class ShimmerEffect extends StatefulWidget {
  final Widget child;
  final Color baseColor;
  final Color highlightColor;
  final Duration duration;

  const ShimmerEffect({
    super.key,
    required this.child,
    this.baseColor = const Color(0xFF161622),
    this.highlightColor = const Color(0xFF2A2638),
    this.duration = const Duration(milliseconds: 1400),
  });

  @override
  State<ShimmerEffect> createState() => _ShimmerEffectState();
}

class _ShimmerEffectState extends State<ShimmerEffect>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            final x = -1.5 + _controller.value * 3.0;
            return LinearGradient(
              begin: Alignment(x, -0.3),
              end: Alignment(x + 1.2, 0.3),
              colors: [
                widget.baseColor,
                widget.highlightColor,
                widget.baseColor,
              ],
              stops: const [0.0, 0.5, 1.0],
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// A modern skeleton loader representing chat contacts or groups list.
class ContactListSkeleton extends StatelessWidget {
  final int itemCount;
  final bool isGroup;

  const ContactListSkeleton({
    super.key,
    this.itemCount = 8,
    this.isGroup = false,
  });

  @override
  Widget build(BuildContext context) {
    return ShimmerEffect(
      child: ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: itemCount,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemBuilder: (context, index) {
          // Vary widths slightly for realism
          final nameWidths = [140.0, 170.0, 120.0, 190.0, 150.0, 130.0, 160.0, 180.0];
          final messageWidths = [220.0, 180.0, 240.0, 160.0, 200.0, 230.0, 170.0, 210.0];
          final nameW = nameWidths[index % nameWidths.length];
          final messageW = messageWidths[index % messageWidths.length];

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                // Avatar placeholder
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: isGroup
                        ? BorderRadius.circular(14)
                        : BorderRadius.circular(27),
                  ),
                ),
                const SizedBox(width: 14),
                // Name & last message
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: nameW,
                        height: 16,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: messageW,
                        height: 13,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Time & badge placeholder
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      width: 36,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (index % 3 == 0)
                      Container(
                        width: 18,
                        height: 18,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A modern skeleton loader for chat message screens (1-to-1 & group chats).
class ChatMessagesSkeleton extends StatelessWidget {
  final int bubbleCount;

  const ChatMessagesSkeleton({
    super.key,
    this.bubbleCount = 7,
  });

  @override
  Widget build(BuildContext context) {
    // Alternating realistic bubble structures (isMe, width, height, hasMedia)
    final bubbleConfigs = [
      {'isMe': false, 'w': 180.0, 'lines': 1, 'media': false},
      {'isMe': true, 'w': 220.0, 'lines': 2, 'media': false},
      {'isMe': false, 'w': 200.0, 'lines': 1, 'media': true},
      {'isMe': true, 'w': 140.0, 'lines': 1, 'media': false},
      {'isMe': false, 'w': 240.0, 'lines': 3, 'media': false},
      {'isMe': true, 'w': 190.0, 'lines': 2, 'media': false},
      {'isMe': false, 'w': 150.0, 'lines': 1, 'media': false},
    ];

    return ShimmerEffect(
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        itemCount: bubbleCount,
        reverse: true,
        itemBuilder: (context, index) {
          final config = bubbleConfigs[index % bubbleConfigs.length];
          final isMe = config['isMe'] as bool;
          final width = config['w'] as double;
          final lines = config['lines'] as int;
          final hasMedia = config['media'] as bool;

          return Align(
            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 6),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMe ? 16 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasMedia) ...[
                    Container(
                      width: width,
                      height: 120,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  for (int i = 0; i < lines; i++) ...[
                    Container(
                      width: i == lines - 1 && lines > 1
                          ? width * 0.6
                          : width,
                      height: 14,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(7),
                      ),
                    ),
                    if (i < lines - 1) const SizedBox(height: 6),
                  ],
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Container(
                      width: 32,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A horizontal skeleton loader for the stories/status row at the top of the chat screen.
class StatusRowSkeleton extends StatelessWidget {
  final int itemCount;

  const StatusRowSkeleton({
    super.key,
    this.itemCount = 5,
  });

  @override
  Widget build(BuildContext context) {
    return ShimmerEffect(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 108,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              itemCount: itemCount,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Story circle with ring effect
                      Container(
                        width: 62,
                        height: 62,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withOpacity(0.4),
                            width: 2.5,
                          ),
                        ),
                        child: Center(
                          child: Container(
                            width: 52,
                            height: 52,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      // Name pill
                      Container(
                        width: 48,
                        height: 10,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Divider(
            color: Colors.white.withOpacity(0.08),
            thickness: 1,
            indent: 14,
            endIndent: 14,
          ),
        ],
      ),
    );
  }
}

/// A skeleton loader for the status contacts list screen.
class StatusListSkeleton extends StatelessWidget {
  final int itemCount;

  const StatusListSkeleton({
    super.key,
    this.itemCount = 6,
  });

  @override
  Widget build(BuildContext context) {
    return ShimmerEffect(
      child: ListView.builder(
        itemCount: itemCount,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemBuilder: (context, index) {
          final nameWidths = [120.0, 150.0, 110.0, 160.0, 130.0, 140.0];
          final nameW = nameWidths[index % nameWidths.length];

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                // Avatar with story ring
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withOpacity(0.4),
                      width: 2.2,
                    ),
                  ),
                  child: Center(
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                // Title and subtitle pills
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: nameW,
                        height: 16,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 70,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
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
    );
  }
}

/// A skeleton loader for the Bookmark user list screen.
class BookmarkUserListSkeleton extends StatelessWidget {
  final int itemCount;

  const BookmarkUserListSkeleton({
    super.key,
    this.itemCount = 6,
  });

  @override
  Widget build(BuildContext context) {
    return ShimmerEffect(
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: itemCount,
        separatorBuilder: (_, __) => Divider(
          color: Colors.white.withOpacity(0.08),
          height: 1,
          indent: 72,
        ),
        itemBuilder: (context, index) {
          final nameWidths = [130.0, 160.0, 110.0, 150.0, 140.0, 120.0];
          final nameW = nameWidths[index % nameWidths.length];

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                // User Avatar placeholder
                Container(
                  width: 52,
                  height: 52,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 14),
                // Name & count pills
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: nameW,
                        height: 15,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(7),
                        ),
                      ),
                      const SizedBox(height: 7),
                      Container(
                        width: 75,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // 3 preview thumbnails
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(
                    3,
                    (thumbIndex) => Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A skeleton loader for the user's bookmarks photo grid (3 columns).
class BookmarkGridSkeleton extends StatelessWidget {
  final int itemCount;

  const BookmarkGridSkeleton({
    super.key,
    this.itemCount = 18,
  });

  @override
  Widget build(BuildContext context) {
    return ShimmerEffect(
      child: GridView.builder(
        padding: const EdgeInsets.all(3),
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 3,
          mainAxisSpacing: 3,
        ),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
          );
        },
      ),
    );
  }
}

/// A skeleton loader for the Recent Bookmarks section on the Dashboard.
class RecentBookmarksSkeleton extends StatelessWidget {
  final int itemCount;

  const RecentBookmarksSkeleton({
    super.key,
    this.itemCount = 4,
  });

  @override
  Widget build(BuildContext context) {
    return ShimmerEffect(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                // "RECENT BOOKMARKS" title placeholder
                Container(
                  width: 120,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const Spacer(),
                // "See all" placeholder
                Container(
                  width: 44,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 110,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: itemCount,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                return Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
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

/// A sleek shimmer skeleton for the chat AppBar (avatar + name + status).
class ChatAppBarSkeleton extends StatelessWidget {
  const ChatAppBarSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerEffect(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 110,
                height: 14,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: 48,
                height: 10,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A sleek shimmer skeleton for the Events Calendar Page.
/// Renders a full calendar grid skeleton, date summary bar, and event card placeholders.
class CalendarPageSkeleton extends StatelessWidget {
  const CalendarPageSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerEffect(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Calendar Card Container ───────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  // Month header row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Prev arrow
                      Container(
                        width: 32,
                        height: 32,
                        decoration: const BoxDecoration(
                          color: Colors.black26,
                          shape: BoxShape.circle,
                        ),
                      ),
                      // Month Title placeholder
                      Container(
                        width: 140,
                        height: 20,
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      // Next arrow & format pill
                      Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: const BoxDecoration(
                              color: Colors.black26,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 64,
                            height: 26,
                            decoration: BoxDecoration(
                              color: Colors.black26,
                              borderRadius: BorderRadius.circular(13),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Day of week labels row (7 columns)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: List.generate(
                      7,
                      (_) => Container(
                        width: 22,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Calendar day cells (5 rows x 7 cols)
                  for (int row = 0; row < 5; row++) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: List.generate(7, (col) {
                          final hasMarker = (row == 1 && col == 3) ||
                              (row == 2 && col == 5) ||
                              (row == 3 && col == 1);
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: (row == 2 && col == 2)
                                      ? Colors.black38 // Active selected cell
                                      : Colors.black12,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: hasMarker
                                      ? Colors.black26
                                      : Colors.transparent,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          );
                        }),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Selected Date Summary Bar ──────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 150,
                    height: 16,
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  Container(
                    width: 80,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // ── Event Cards List Shimmer ───────────────────────────────
            for (int i = 0; i < 2; i++) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Icon Box placeholder
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: Colors.black26,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Title and info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: i == 0 ? 160 : 130,
                                height: 16,
                                decoration: BoxDecoration(
                                  color: Colors.black26,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Container(
                                    width: 70,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      color: Colors.black26,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Container(
                                    width: 50,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      color: Colors.black26,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        // Action buttons placeholder
                        Row(
                          children: [
                            Container(
                              width: 26,
                              height: 26,
                              decoration: const BoxDecoration(
                                color: Colors.black26,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              width: 26,
                              height: 26,
                              decoration: const BoxDecoration(
                                color: Colors.black26,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Attribution placeholder
                    Container(
                      width: 110,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}


