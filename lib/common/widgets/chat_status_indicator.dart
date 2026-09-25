import 'package:flutter/material.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/widgets/user_avatar.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// BOUNCING TYPING DOTS
/// Fluid 3-dot wave bounce animation (similar to iMessage / Telegram).
/// Uses a single AnimationController with staggered intervals for optimal performance.
/// ─────────────────────────────────────────────────────────────────────────────
class BouncingTypingDots extends StatefulWidget {
  final Color? color;
  final double dotSize;
  final double spacing;

  const BouncingTypingDots({
    super.key,
    this.color,
    this.dotSize = 4.5,
    this.spacing = 3.0,
  });

  @override
  State<BouncingTypingDots> createState() => _BouncingTypingDotsState();
}

class _BouncingTypingDotsState extends State<BouncingTypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _dot1;
  late final Animation<double> _dot2;
  late final Animation<double> _dot3;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();

    _dot1 = _buildDotAnimation(0.0, 0.55);
    _dot2 = _buildDotAnimation(0.2, 0.75);
    _dot3 = _buildDotAnimation(0.4, 0.95);
  }

  Animation<double> _buildDotAnimation(double start, double end) {
    return TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: -4.5)
            .chain(CurveTween(curve: Curves.easeOutQuad)),
        weight: 45,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: -4.5, end: 0.0)
            .chain(CurveTween(curve: Curves.easeInQuad)),
        weight: 45,
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(0.0),
        weight: 10,
      ),
    ]).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Interval(start, end, curve: Curves.linear),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeColor = widget.color ?? tabColor;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildDot(_dot1.value, activeColor),
            SizedBox(width: widget.spacing),
            _buildDot(_dot2.value, activeColor),
            SizedBox(width: widget.spacing),
            _buildDot(_dot3.value, activeColor),
          ],
        );
      },
    );
  }

  Widget _buildDot(double translateY, Color color) {
    final progress = (-translateY / 4.5).clamp(0.0, 1.0);
    final scale = 1.0 + (progress * 0.25);
    final opacity = (0.45 + (progress * 0.55)).clamp(0.0, 1.0);

    return Transform.translate(
      offset: Offset(0, translateY),
      child: Transform.scale(
        scale: scale,
        child: Container(
          width: widget.dotSize,
          height: widget.dotSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: opacity),
            boxShadow: progress > 0.4
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.5),
                      blurRadius: 3,
                    ),
                  ]
                : null,
          ),
        ),
      ),
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────────────
/// PULSING ONLINE DOT
/// A vibrant emerald green dot with a breathing outer glow ring.
/// ─────────────────────────────────────────────────────────────────────────────
class PulsingOnlineDot extends StatefulWidget {
  final double size;
  final Color color;

  const PulsingOnlineDot({
    super.key,
    this.size = 6.5,
    this.color = const Color(0xFF00E676),
  });

  @override
  State<PulsingOnlineDot> createState() => _PulsingOnlineDotState();
}

class _PulsingOnlineDotState extends State<PulsingOnlineDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    _scaleAnimation = Tween<double>(begin: 1.0, end: 2.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOutCubic),
    );

    _fadeAnimation = Tween<double>(begin: 0.6, end: 0.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size * 2,
      height: widget.size * 2,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, _) {
              return Transform.scale(
                scale: _scaleAnimation.value,
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color.withValues(alpha: _fadeAnimation.value),
                  ),
                ),
              );
            },
          ),
          Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color,
              boxShadow: [
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.8),
                  blurRadius: 5,
                  spreadRadius: 0.5,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────────────
/// APP BAR STATUS SUBTITLE (1-ON-1 CHAT)
/// Smoothly transitions between Typing, Online, and Offline states.
/// ─────────────────────────────────────────────────────────────────────────────
class AppBarStatusSubtitle extends StatelessWidget {
  final bool isTyping;
  final bool isOnline;
  final Color accentColor;

  const AppBarStatusSubtitle({
    super.key,
    required this.isTyping,
    required this.isOnline,
    this.accentColor = tabColor,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.0, 0.25),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: _buildCurrentState(),
    );
  }

  Widget _buildCurrentState() {
    if (isTyping) {
      return Row(
        key: const ValueKey('typing_state'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'typing',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: accentColor,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(width: 5),
          BouncingTypingDots(
            color: accentColor,
            dotSize: 4.0,
            spacing: 2.5,
          ),
        ],
      );
    }

    if (isOnline) {
      return Row(
        key: const ValueKey('online_state'),
        mainAxisSize: MainAxisSize.min,
        children: [
          const PulsingOnlineDot(size: 6.0),
          const SizedBox(width: 5),
          const Text(
            'Online',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF00E676),
              letterSpacing: 0.2,
            ),
          ),
        ],
      );
    }

    return Row(
      key: const ValueKey('offline_state'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 5.5,
          height: 5.5,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white38,
          ),
        ),
        const SizedBox(width: 5),
        const Text(
          'Offline',
          style: TextStyle(
            fontSize: 12.0,
            fontWeight: FontWeight.normal,
            color: Colors.white54,
            letterSpacing: 0.1,
          ),
        ),
      ],
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────────────
/// GROUP APP BAR STATUS SUBTITLE
/// Shows animated typing indicator or member count for groups.
/// ─────────────────────────────────────────────────────────────────────────────
class GroupAppBarStatusSubtitle extends StatelessWidget {
  final Map<String, String> typingUsers;
  final int memberCount;
  final Color accentColor;

  const GroupAppBarStatusSubtitle({
    super.key,
    required this.typingUsers,
    required this.memberCount,
    this.accentColor = tabColor,
  });

  String _formatTypingUsers(Map<String, String> users) {
    if (users.isEmpty) return '';
    final names = users.values.toList();
    if (names.length == 1) {
      return '${names[0]} is typing';
    } else if (names.length == 2) {
      return '${names[0]} & ${names[1]} are typing';
    } else {
      return '${names[0]} & ${names.length - 1} others typing';
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasTyping = typingUsers.isNotEmpty;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.0, 0.25),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: hasTyping
          ? Row(
              key: ValueKey('group_typing_${typingUsers.keys.join(',')}'),
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    _formatTypingUsers(typingUsers),
                    style: TextStyle(
                      fontSize: 12.0,
                      fontWeight: FontWeight.w600,
                      color: accentColor,
                      letterSpacing: 0.1,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 5),
                BouncingTypingDots(
                  color: accentColor,
                  dotSize: 3.8,
                  spacing: 2.2,
                ),
              ],
            )
          : Row(
              key: const ValueKey('group_members_state'),
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.people_alt_outlined,
                  size: 13,
                  color: Colors.white54,
                ),
                const SizedBox(width: 4),
                Text(
                  '$memberCount members',
                  style: const TextStyle(
                    fontSize: 12.0,
                    fontWeight: FontWeight.normal,
                    color: Colors.white54,
                    letterSpacing: 0.1,
                  ),
                ),
              ],
            ),
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────────────
/// IN-CHAT FLOATING TYPING BUBBLE
/// A floating bubble right above the message input field that slides in
/// when someone is typing, giving users immediate feedback at the bottom of the chat.
/// ─────────────────────────────────────────────────────────────────────────────
class InChatTypingBubble extends StatelessWidget {
  final bool isTyping;
  final String? userName;
  final String? profilePic;
  final Color accentColor;

  const InChatTypingBubble({
    super.key,
    required this.isTyping,
    this.userName,
    this.profilePic,
    this.accentColor = tabColor,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedCrossFade(
      duration: const Duration(milliseconds: 250),
      firstCurve: Curves.easeOutCubic,
      secondCurve: Curves.easeInCubic,
      crossFadeState:
          isTyping ? CrossFadeState.showFirst : CrossFadeState.showSecond,
      firstChild: Padding(
        padding: const EdgeInsets.only(left: 14, bottom: 6, right: 14),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFF1E212B).withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: accentColor.withValues(alpha: 0.35),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (profilePic != null && profilePic!.isNotEmpty) ...[
                  UserAvatar(url: profilePic, radius: 9),
                  const SizedBox(width: 7),
                ],
                if (userName != null && userName!.isNotEmpty) ...[
                  Text(
                    userName!,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: accentColor,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'is typing',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(width: 6),
                ] else ...[
                  Text(
                    'typing',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: accentColor,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                BouncingTypingDots(
                  color: accentColor,
                  dotSize: 4.2,
                  spacing: 2.5,
                ),
              ],
            ),
          ),
        ),
      ),
      secondChild: const SizedBox.shrink(),
    );
  }
}
