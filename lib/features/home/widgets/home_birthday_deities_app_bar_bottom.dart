import 'dart:io';
import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/utils/utils.dart';
import 'package:worship_chat/features/dashboard/widgets/today_birthdays_slideshow_widget.dart';
import 'package:worship_chat/features/group/screens/group_chat_screen.dart';
import 'package:worship_chat/features/group/screens/slide_show_screen.dart';
import 'package:worship_chat/models/event.dart';
import 'package:worship_chat/models/group_gallery_image.dart';

/// A celebratory bottom bar for the Home AppBar that prominently displays
/// the name, profile picture, and royal celebration styling of today's birthday deities.
class HomeBirthdayDeitiesAppBarBottom extends StatelessWidget
    implements PreferredSizeWidget {
  final List<Event> celebrants;
  final ValueChanged<Event>? onCelebrantTapped;

  const HomeBirthdayDeitiesAppBarBottom({
    super.key,
    required this.celebrants,
    this.onCelebrantTapped,
  });

  @override
  Size get preferredSize => const Size.fromHeight(48.0);

  static String? resolveCelebrantPic(Event event) {
    if (event.connectedGroupPic != null &&
        event.connectedGroupPic!.trim().isNotEmpty) {
      return event.connectedGroupPic!.trim();
    }
    final fallbacks = TodayBirthdaysSlideshowWidget.buildFallbackPhotos(event);
    if (fallbacks.isNotEmpty) {
      return fallbacks.first;
    }
    return null;
  }

  static ImageProvider? getImageProvider(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return CachedNetworkImageProvider(path);
    }
    if (path.startsWith('assets/')) {
      return AssetImage(path);
    }
    return FileImage(File(path));
  }

  static void showAllCelebrantsSheet(
    BuildContext context,
    List<Event> celebrants,
  ) {
    if (celebrants.isEmpty) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          decoration: BoxDecoration(
            color: const Color(0xFF151320),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            border: Border(
              top: BorderSide(
                color: const Color(0xFFD2B46E).withValues(alpha: 0.28),
                width: 1.0,
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  "Today's Birthdays (${celebrants.length})",
                  style: const TextStyle(
                    color: Color(0xFFF3F0FA),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(ctx).size.height * 0.55,
                  ),
                  child: Material(
                    type: MaterialType.transparency,
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const BouncingScrollPhysics(),
                      itemCount: celebrants.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: Colors.white.withValues(alpha: 0.06),
                      ),
                      itemBuilder: (_, index) {
                        final celebrant = celebrants[index];
                        final cleanName =
                            TodayBirthdaysSlideshowWidget.extractCelebrantName(
                          celebrant.title,
                          connectedGroupName: celebrant.connectedGroupName,
                          connectedGroupId: celebrant.connectedGroupId,
                        );

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(vertical: 4),
                          leading: AnimatedBirthdayDeityAvatar(
                            celebrant: celebrant,
                            radius: 22,
                            phaseOffset: index * 0.21,
                            showCakeBadge: false,
                          ),
                          title: Text(
                            cleanName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFF3F0FA),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          trailing: IconButton(
                            tooltip: 'Watch Slideshow',
                            icon: const Icon(
                              Icons.play_circle_outline_rounded,
                              color: Color(0xFFD2B46E),
                              size: 22,
                            ),
                            onPressed: () {
                              Navigator.pop(ctx);
                              openSlideshow(context, celebrant);
                            },
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            showCelebrationSheet(context, celebrant);
                          },
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static void showCelebrationSheet(BuildContext context, Event celebrant) {
    final cleanName = TodayBirthdaysSlideshowWidget.extractCelebrantName(
      celebrant.title,
      connectedGroupName: celebrant.connectedGroupName,
      connectedGroupId: celebrant.connectedGroupId,
    );
    final pic = resolveCelebrantPic(celebrant);
    final imageProvider = getImageProvider(pic);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          decoration: BoxDecoration(
            color: const Color(0xFF161224),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(
              color: const Color(0xFFFFD700).withValues(alpha: 0.35),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.7),
                blurRadius: 24,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle indicator
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),

                // Celebrant Avatar with Golden Aura
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFFFD700),
                      width: 2.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFFD700).withValues(alpha: 0.45),
                        blurRadius: 18,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: CircleAvatar(
                    radius: 36,
                    backgroundColor: const Color(0xFF261D36),
                    backgroundImage: imageProvider,
                    child: imageProvider == null
                        ? const Icon(Icons.person, color: Colors.white, size: 36)
                        : null,
                  ),
                ),
                const SizedBox(height: 12),

                // Deity Name
                Text(
                  cleanName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFFE082),
                    letterSpacing: 0.3,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '🎂 Divine Royal Birthday Celebration ✨',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),

                // Action 1: Watch Birthday Slideshow
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFD700),
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.play_circle_fill_rounded, size: 22),
                    label: const Text(
                      'Watch Birthday Slideshow',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3,
                      ),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      openSlideshow(context, celebrant);
                    },
                  ),
                ),

                // Action 2: Open Royal Sanctum & Chat (if linked group exists)
                if (celebrant.connectedGroupId != null &&
                    celebrant.connectedGroupId!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFFFE082),
                        side: BorderSide(
                          color: const Color(0xFFFFD700).withValues(alpha: 0.6),
                          width: 1.2,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.chat_bubble_outline_rounded, size: 20),
                      label: const Text(
                        'Enter Royal Sanctum & Chat',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        openGroupChat(context, celebrant);
                      },
                    ),
                  ),
                ],

                // Action 3: Copy Royal Birthday Wish
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white70,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text(
                      'Copy Royal Birthday Wish',
                      style: TextStyle(fontSize: 13),
                    ),
                    onPressed: () {
                      final wish = 'Happy Birthday, $cleanName! 🎂✨ Long may you reign in divine splendor!';
                      Clipboard.setData(ClipboardData(text: wish));
                      Navigator.pop(ctx);
                      AppSnackBar.success(
                        context,
                        'Birthday wish for $cleanName copied to clipboard! 🎂✨',
                        customIcon: Icons.cake_rounded,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Future<void> openSlideshow(BuildContext context, Event celebrant) async {
    final cleanName = TodayBirthdaysSlideshowWidget.extractCelebrantName(
      celebrant.title,
      connectedGroupName: celebrant.connectedGroupName,
      connectedGroupId: celebrant.connectedGroupId,
    );

    List<GroupGalleryImage> galleryImages = [];
    final groupId = celebrant.connectedGroupId;
    if (groupId != null && groupId.isNotEmpty) {
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('groups')
            .doc(groupId)
            .collection('gallery')
            .orderBy('uploadedAt', descending: true)
            .limit(60)
            .get();

        galleryImages = snapshot.docs
            .map((doc) => GroupGalleryImage.fromMap({
                  ...doc.data(),
                  'imageId': doc.id,
                }))
            .where((img) => img.imageUrl.isNotEmpty)
            .toList();
      } catch (_) {}
    }

    if (galleryImages.isEmpty) {
      final fallbacks = TodayBirthdaysSlideshowWidget.buildFallbackPhotos(celebrant);
      galleryImages = fallbacks.asMap().entries.map((entry) {
        return GroupGalleryImage(
          imageId: 'bday_${celebrant.id}_${entry.key}',
          groupId: celebrant.connectedGroupId ?? 'general',
          imageUrl: entry.value,
          uploadedBy: 'Birthday Celebration',
          uploadedByName: cleanName,
          uploadedAt: DateTime.now(),
        );
      }).toList();
    }

    if (context.mounted && galleryImages.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SlideshowScreen(
            images: galleryImages,
            initialIndex: 0,
            accentColor: const Color(0xFFFFD700),
            groupName: cleanName,
          ),
        ),
      );
    }
  }

  static void openGroupChat(BuildContext context, Event celebrant) {
    if (celebrant.connectedGroupId == null) return;
    final resolvedName = TodayBirthdaysSlideshowWidget.resolveConnectedGroupName(
      connectedGroupName: celebrant.connectedGroupName,
      connectedGroupId: celebrant.connectedGroupId,
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupChatScreen(
          name: resolvedName ??
              TodayBirthdaysSlideshowWidget.extractCelebrantName(
                celebrant.title,
                connectedGroupName: celebrant.connectedGroupName,
                connectedGroupId: celebrant.connectedGroupId,
              ),
          groupId: celebrant.connectedGroupId!,
          fcmToken: const [],
          membersUid: const [],
          chatBackgroundUrl: null,
          groupPic: celebrant.connectedGroupPic,
          wish: null,
          queendom: celebrant.connectedQueendom,
          color: null,
          type: 'group',
        ),
      ),
    );
  }

  Widget _buildCelebrantAvatar(Event celebrant, {double radius = 15}) {
    final pic = resolveCelebrantPic(celebrant);
    final imageProvider = getImageProvider(pic);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: const Color(0xFFFFD700),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFFD700).withValues(alpha: 0.45),
                blurRadius: 6,
                spreadRadius: 0.5,
              ),
            ],
          ),
          child: CircleAvatar(
            radius: radius,
            backgroundColor: const Color(0xFF261D36),
            backgroundImage: imageProvider,
            child: imageProvider == null
                ? Icon(Icons.person, color: Colors.white, size: radius * 1.2)
                : null,
          ),
        ),
        Positioned(
          bottom: -2,
          right: -3,
          child: Container(
            padding: const EdgeInsets.all(1),
            decoration: BoxDecoration(
              color: const Color(0xFF1B1428),
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFFFFD700).withValues(alpha: 0.7),
                width: 0.8,
              ),
            ),
            child: const Text('🎂', style: TextStyle(fontSize: 9)),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (celebrants.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      height: 48,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Color(0xFF231808),
            Color(0xFF171224),
            Color(0xFF231808),
          ],
        ),
        border: Border(
          top: BorderSide(
            color: const Color(0xFFFFD700).withValues(alpha: 0.35),
            width: 0.8,
          ),
          bottom: BorderSide(
            color: const Color(0xFFFFD700).withValues(alpha: 0.22),
            width: 0.6,
          ),
        ),
      ),
      child: celebrants.length == 1
          ? _buildSingleCelebrantRow(context, celebrants.first)
          : _buildMultipleCelebrantsList(context),
    );
  }

  Widget _buildSingleCelebrantRow(BuildContext context, Event celebrant) {
    final cleanName = TodayBirthdaysSlideshowWidget.extractCelebrantName(
      celebrant.title,
      connectedGroupName: celebrant.connectedGroupName,
      connectedGroupId: celebrant.connectedGroupId,
    );

    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        if (onCelebrantTapped != null) {
          onCelebrantTapped!(celebrant);
        } else {
          showCelebrationSheet(context, celebrant);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            _buildCelebrantAvatar(celebrant, radius: 14),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          cleanName,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFFFE082),
                            letterSpacing: 0.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Text('✨', style: TextStyle(fontSize: 10)),
                    ],
                  ),
                  const SizedBox(height: 1),
                  const Text(
                    "Today's Royal Birthday Celebration 🎂",
                    style: TextStyle(
                      fontSize: 9.5,
                      color: Colors.white70,
                      fontStyle: FontStyle.italic,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
              decoration: BoxDecoration(
                color: const Color(0xFFFFD700).withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFFFD700).withValues(alpha: 0.6),
                  width: 0.8,
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Celebrate',
                    style: TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.2,
                    ),
                  ),
                  SizedBox(width: 2),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 13,
                    color: Color(0xFFFFD700),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMultipleCelebrantsList(BuildContext context) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: celebrants.length,
      separatorBuilder: (_, __) => const SizedBox(width: 10),
      itemBuilder: (context, index) {
        final celebrant = celebrants[index];
        final cleanName = TodayBirthdaysSlideshowWidget.extractCelebrantName(
          celebrant.title,
          connectedGroupName: celebrant.connectedGroupName,
          connectedGroupId: celebrant.connectedGroupId,
        );

        return InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            HapticFeedback.lightImpact();
            if (onCelebrantTapped != null) {
              onCelebrantTapped!(celebrant);
            } else {
              showCelebrationSheet(context, celebrant);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFFFFD700).withValues(alpha: 0.45),
                width: 0.8,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildCelebrantAvatar(celebrant, radius: 12),
                const SizedBox(width: 7),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      cleanName,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFFFE082),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Text(
                      "🎂 Birthday ✨",
                      style: TextStyle(
                        fontSize: 8.5,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Circular birthday deity portrait wrapped in a rotating gold-rose halo,
/// soft breathing radiance, diagonal prism shimmer, and twinkling star sparkles.
class AnimatedBirthdayDeityAvatar extends StatefulWidget {
  final Event celebrant;
  final double radius;
  final double phaseOffset;
  final bool showCakeBadge;
  final VoidCallback? onTap;

  const AnimatedBirthdayDeityAvatar({
    super.key,
    required this.celebrant,
    this.radius = 15.0,
    this.phaseOffset = 0.0,
    this.showCakeBadge = true,
    this.onTap,
  });

  @override
  State<AnimatedBirthdayDeityAvatar> createState() =>
      _AnimatedBirthdayDeityAvatarState();
}

class _AnimatedBirthdayDeityAvatarState
    extends State<AnimatedBirthdayDeityAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _controller.value = 0.25;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pic =
        HomeBirthdayDeitiesAppBarBottom.resolveCelebrantPic(widget.celebrant);
    final imageProvider =
        HomeBirthdayDeitiesAppBarBottom.getImageProvider(pic);
    final cleanName = TodayBirthdaysSlideshowWidget.extractCelebrantName(
      widget.celebrant.title,
      connectedGroupName: widget.celebrant.connectedGroupName,
      connectedGroupId: widget.celebrant.connectedGroupId,
    );

    final avatarDiameter = widget.radius * 2;
    final ringStroke = (widget.radius * 0.075).clamp(1.4, 2.2);
    final bezelGap = (widget.radius * 0.045).clamp(0.8, 1.3);
    final outerSize = avatarDiameter + (ringStroke + bezelGap) * 2;

    final avatarChild = SizedBox(
      width: avatarDiameter,
      height: avatarDiameter,
      child: CircleAvatar(
        radius: widget.radius,
        backgroundColor: const Color(0xFF201C2E),
        backgroundImage: imageProvider,
        child: imageProvider == null
            ? Icon(
                Icons.person,
                color: Colors.white70,
                size: widget.radius,
              )
            : null,
      ),
    );

    Widget content = RepaintBoundary(
      child: SizedBox(
        width: outerSize,
        height: outerSize,
        child: AnimatedBuilder(
          animation: _controller,
          child: avatarChild,
          builder: (context, cachedAvatar) {
            final t = (_controller.value + widget.phaseOffset) % 1.0;
            final angle = t * 2 * math.pi;
            final pulse = 0.5 + 0.5 * math.sin(angle);
            final sweepActive = t <= 0.36;
            final sweepProgress = sweepActive ? (t / 0.36) : -1.0;

            return Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                // Subtle soft halo without heavy multi-pass Gaussian blur per frame
                Container(
                  width: outerSize,
                  height: outerSize,
                  padding: EdgeInsets.all(ringStroke),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: SweepGradient(
                      colors: const [
                        Color(0xFFFFD700),
                        Color(0xFFFF7EB3),
                        Color(0xFFFFB26B),
                        Color(0xFFFFF1B8),
                        Color(0xFFFFD700),
                      ],
                      transform: GradientRotation(angle),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFFD700).withValues(
                          alpha: 0.20 + 0.14 * pulse,
                        ),
                        blurRadius: 4.0,
                      ),
                    ],
                  ),
                child: Container(
                  padding: EdgeInsets.all(bezelGap),
                  decoration: const BoxDecoration(
                    color: appBarColor,
                    shape: BoxShape.circle,
                  ),
                  child: ClipOval(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        cachedAvatar!,
                        if (sweepActive)
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment(
                                  -2.2 + sweepProgress * 4.4,
                                  -0.9,
                                ),
                                end: Alignment(
                                  -1.0 + sweepProgress * 4.4,
                                  0.9,
                                ),
                                colors: [
                                  Colors.transparent,
                                  Colors.white.withValues(alpha: 0.34),
                                  Colors.transparent,
                                ],
                                stops: const [0.0, 0.5, 1.0],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              // Twinkling 4-point star sparkles on upper rim
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _BirthdaySparklePainter(t: t),
                  ),
                ),
              ),
                if (widget.showCakeBadge)
                  Positioned(
                    bottom: -1,
                    right: -1,
                    child: Container(
                      padding: const EdgeInsets.all(0.8),
                      decoration: BoxDecoration(
                        color: appBarColor,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFFFFD700).withValues(alpha: 0.65),
                          width: 0.7,
                        ),
                      ),
                      child: Text(
                        '🎂',
                        style: TextStyle(
                          fontSize: (widget.radius * 0.44).clamp(7.5, 13.0),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );

    if (widget.onTap != null) {
      content = Tooltip(
        message: cleanName,
        child: GestureDetector(
          onTap: widget.onTap,
          child: content,
        ),
      );
    }

    return content;
  }
}

class _BirthdaySparklePainter extends CustomPainter {
  final double t;

  const _BirthdaySparklePainter({required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final angle1 = t * 2 * math.pi;
    final star1Alpha = (0.35 + 0.65 * (0.5 + 0.5 * math.sin(angle1))).clamp(0.0, 1.0);
    final star2Alpha =
        (0.25 + 0.75 * (0.5 + 0.5 * math.cos(angle1 * 1.5))).clamp(0.0, 1.0);

    _drawFourPointStar(
      canvas,
      Offset(size.width * 0.14, size.height * 0.14),
      size.width * 0.065 + size.width * 0.03 * star1Alpha,
      const Color(0xFFFFF4C2).withValues(alpha: star1Alpha),
    );
    _drawFourPointStar(
      canvas,
      Offset(size.width * 0.87, size.height * 0.15),
      size.width * 0.055 + size.width * 0.025 * star2Alpha,
      const Color(0xFFFFA9CF).withValues(alpha: star2Alpha),
    );
  }

  void _drawFourPointStar(
    Canvas canvas,
    Offset center,
    double outerR,
    Color color,
  ) {
    final innerR = outerR * 0.32;
    final path = Path();
    for (int i = 0; i < 8; i++) {
      final r = i.isEven ? outerR : innerR;
      final theta = (i * math.pi / 4) - math.pi / 2;
      final point = Offset(
        center.dx + r * math.cos(theta),
        center.dy + r * math.sin(theta),
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BirthdaySparklePainter oldDelegate) {
    return oldDelegate.t != t;
  }
}
