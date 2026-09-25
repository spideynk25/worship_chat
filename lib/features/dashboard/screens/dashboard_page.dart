import 'dart:developer';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/widgets/skeleton_loader.dart';
import 'package:worship_chat/features/bookmark/controller/bookmark_controller.dart';
import 'package:worship_chat/features/bookmark/screens/bookmark_screen.dart';
import 'package:worship_chat/features/dashboard/screens/event_calender_page.dart';
import 'package:worship_chat/features/dashboard/widgets/event_shortcuts_widget.dart';
import 'package:worship_chat/features/dashboard/widgets/group_shortcuts_grid.dart';
import 'package:worship_chat/features/dashboard/widgets/todo_page.dart';
import 'package:worship_chat/models/bookmark_model.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
  bool _imagesPreloaded = false;
  bool _imageLoadFailed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_imagesPreloaded) {
      _preloadImages();
      _imagesPreloaded = true;
    }
  }

  Future<void> _preloadImages() async {
    try {
      if (!mounted) return;
      await precacheImage(const AssetImage('assets/images/img1.png'), context);
      if (!mounted) return;
      await precacheImage(const AssetImage('assets/images/img2.png'), context);
      if (!mounted) return;
      await precacheImage(const AssetImage('assets/images/img3.png'), context);
    } catch (e) {
      log('❌ Error preloading images: $e');
      if (mounted) setState(() => _imageLoadFailed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Banner: hero + stickers + action pills overlaid ──────────
          _BannerSection(
            imageLoadFailed: _imageLoadFailed,
            currentUserId: currentUserId,
          ),

          // ── Group Shortcuts ───────────────────────────────────────────
          const SizedBox(height: 24),
          GroupShortcutsGrid(currentUserId: currentUserId),

          // ── Birthday & Event Shortcuts ────────────────────────────────
          const SizedBox(height: 24),
          const EventShortcutsWidget(),

          // ── Recent bookmarks ──────────────────────────────────────────
          const SizedBox(height: 24),
          _RecentBookmarks(currentUserId: currentUserId),

          const SizedBox(height: 36),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Banner Section
// img1 hero + sticker portraits + glassmorphism action pills at bottom
// ─────────────────────────────────────────────────────────────────────────────

class _BannerSection extends ConsumerWidget {
  final bool imageLoadFailed;
  final String currentUserId;
  const _BannerSection({
    required this.imageLoadFailed,
    required this.currentUserId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (imageLoadFailed) {
      return Container(height: 280, color: Colors.grey[900]);
    }

    final bookmarkCount = ref
        .watch(bookmarkControllerProvider)
        .myBookmarks()
        .map((list) => list.length)
        .handleError((_) {});

    const double bannerHeight = 250.0;

    return SizedBox(
      width: double.infinity,
      height: bannerHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
                Image.asset(
                  'assets/images/img1.png',
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (_, __, ___) =>
                      Container(color: Colors.grey[900]),
                ),

                // Dark gradient — bottom 1/2 dims for pill readability
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  height: bannerHeight * 0.55,
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Color(0xCC000000),
                          Colors.black,
                        ],
                        stops: [0.0, 0.7, 1.0],
                      ),
                    ),
                  ),
                ),

                // Side vignette
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.black.withValues(alpha: 0.3),
                          Colors.transparent,
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.3),
                        ],
                        stops: const [0.0, 0.18, 0.82, 1.0],
                      ),
                    ),
                  ),
                ),

                // ── Action pills overlay — bottom of img1 ───────────────
                Positioned(
                  bottom: 16,
                  left: 16,
                  right: 16,
                  child: StreamBuilder<int>(
                    stream: bookmarkCount,
                    initialData: 0,
                    builder: (context, snap) {
                      final count = snap.data ?? 0;
                      return Row(
                        children: [
                          // Bookmark pill
                          _ActionPill(
                            icon: Icons.bookmark_rounded,
                            iconColor: Colors.amber,
                            label: 'Bookmarks',
                            badge: count > 0 ? '$count' : null,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const BookmarkScreen(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          // Tasks pill
                          _ActionPill(
                            icon: Icons.task_alt_rounded,
                            iconColor: accentOrange,
                            label: 'Tasks',
                            onTap: () => Navigator.pushNamed(
                              context,
                              TodoPage.routeName,
                            ),
                          ),
                          const SizedBox(width: 10),
                          // Calendar pill
                          _ActionPill(
                            icon: Icons.calendar_today_rounded,
                            iconColor: tabColor,
                            label: 'Calendar',
                            onTap: () => Navigator.pushNamed(
                              context,
                              EventsCalendarPage.routeName,
                            ),
                          ),
                        ],
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
// Glassmorphism Action Pill — used inside the banner overlay
// ─────────────────────────────────────────────────────────────────────────────

class _ActionPill extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String? badge;
  final VoidCallback onTap;

  const _ActionPill({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: iconColor, size: 16),
                  ),
                  if (badge != null)
                    Positioned(
                      top: -5,
                      right: -6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: iconColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          badge!,
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                  overflow: TextOverflow.ellipsis,
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
// Recent Bookmarks
// ─────────────────────────────────────────────────────────────────────────────

class _RecentBookmarks extends ConsumerWidget {
  final String currentUserId;
  const _RecentBookmarks({required this.currentUserId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<List<BookmarkModel>>(
      stream: ref.watch(bookmarkControllerProvider).myBookmarks(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const RecentBookmarksSkeleton();
        }
        final bookmarks = snapshot.data ?? [];
        if (bookmarks.isEmpty) return const SizedBox.shrink();

        final recent = bookmarks.take(6).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    'RECENT BOOKMARKS',
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const BookmarkScreen()),
                    ),
                    child: Text(
                      'See all',
                      style: TextStyle(
                        color: tabColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
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
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: recent.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final bm = recent[index];
                  return GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const BookmarkScreen()),
                    ),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: CachedNetworkImage(
                            imageUrl: bm.imageUrl,
                            width: 110,
                            height: 110,
                            fit: BoxFit.cover,
                          ),
                        ),
                        // Group name chip at bottom
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.transparent, Colors.black87],
                              ),
                              borderRadius: BorderRadius.vertical(
                                bottom: Radius.circular(12),
                              ),
                            ),
                            child: Text(
                              bm.groupName,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 9,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        // Bookmark icon
                        const Positioned(
                          top: 4,
                          right: 4,
                          child: Icon(
                            Icons.bookmark,
                            color: Colors.amber,
                            size: 14,
                            shadows: [
                              Shadow(color: Colors.black54, blurRadius: 4),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
