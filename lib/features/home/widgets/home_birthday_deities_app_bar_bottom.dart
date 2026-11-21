import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  static void showCelebrationSheet(BuildContext context, Event celebrant) {
    final cleanName = TodayBirthdaysSlideshowWidget.extractCelebrantName(
      celebrant.title,
      connectedGroupName: celebrant.connectedGroupName,
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
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupChatScreen(
          name: celebrant.connectedGroupName ??
              TodayBirthdaysSlideshowWidget.extractCelebrantName(
                celebrant.title,
                connectedGroupName: celebrant.connectedGroupName,
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
