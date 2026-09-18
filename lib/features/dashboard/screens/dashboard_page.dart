import 'dart:developer';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/features/bookmark/controller/bookmark_controller.dart';
import 'package:worship_chat/features/bookmark/screens/bookmark_screen.dart';
import 'package:worship_chat/features/dashboard/screens/event_calender_page.dart';
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
      await precacheImage(const AssetImage('assets/images/img1.png'), context);
      await precacheImage(const AssetImage('assets/images/img2.png'), context);
      await precacheImage(const AssetImage('assets/images/img3.png'), context);
      await precacheImage(const AssetImage('assets/images/bg1.png'), context);
      await precacheImage(const AssetImage('assets/images/bg2.png'), context);
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
          // ── Banner: img1 full width with portrait cutouts overlaid ───
          _BannerSection(imageLoadFailed: _imageLoadFailed),

          // ── Quick stats ───────────────────────────────────────────────
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _QuickStats(currentUserId: currentUserId),
          ),

          // ── Quick actions ─────────────────────────────────────────────
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: const _QuickActions(),
          ),

          // ── Recent bookmarks ──────────────────────────────────────────
          const SizedBox(height: 20),
          _RecentBookmarks(currentUserId: currentUserId),

          const SizedBox(height: 30),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Banner Section
// img1 as full-width banner, img2 + img3 side by side below on bg2
// ─────────────────────────────────────────────────────────────────────────────

class _BannerSection extends StatelessWidget {
  final bool imageLoadFailed;
  const _BannerSection({required this.imageLoadFailed});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── img1: full width photo banner ──────────────────────────────
        SizedBox(
          width: double.infinity,
          height: 200,
          child: imageLoadFailed
              ? Container(color: Colors.grey[900])
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(
                      'assets/images/img1.png',
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.high,
                      errorBuilder: (_, __, ___) =>
                          Container(color: Colors.grey[900]),
                    ),
                    // Bottom fade so it blends into the portrait section
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      height: 60,
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),

        // ── Portrait section: bg2 with img2 & img3 side by side ────────
        Container(
          width: double.infinity,
          height: 260,
          decoration: BoxDecoration(
            image: imageLoadFailed
                ? null
                : const DecorationImage(
                    image: AssetImage('assets/images/bg2.png'),
                    fit: BoxFit.cover,
                  ),
            color: imageLoadFailed ? Colors.black : null,
          ),
          child: imageLoadFailed
              ? const SizedBox.shrink()
              : Row(
                  children: [
                    // img3 — left portrait
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Image.asset(
                          'assets/images/img3.png',
                          height: 250,
                          fit: BoxFit.fitHeight,
                          filterQuality: FilterQuality.high,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      ),
                    ),
                    // img2 — right portrait
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Image.asset(
                          'assets/images/img2.png',
                          height: 250,
                          fit: BoxFit.fitHeight,
                          filterQuality: FilterQuality.high,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quick Stats
// ─────────────────────────────────────────────────────────────────────────────

class _QuickStats extends ConsumerWidget {
  final String currentUserId;
  const _QuickStats({required this.currentUserId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<List<BookmarkModel>>(
      stream: ref.watch(bookmarkControllerProvider).myBookmarks(),
      builder: (context, bookmarkSnap) {
        final bookmarkCount = bookmarkSnap.data?.length ?? 0;

        return Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.bookmark_rounded,
                iconColor: Colors.amber,
                label: 'Bookmarks',
                value: '$bookmarkCount',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const BookmarkScreen()),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                icon: Icons.task_alt_rounded,
                iconColor: Colors.deepOrange,
                label: 'Tasks',
                value: 'Open',
                onTap: () => Navigator.pushNamed(context, TodoPage.routeName),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                icon: Icons.calendar_today_rounded,
                iconColor: Colors.blueAccent,
                label: 'Calendar',
                value: 'Open',
                onTap: () =>
                    Navigator.pushNamed(context, EventsCalendarPage.routeName),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final VoidCallback onTap;

  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey[800]!),
        ),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(color: Colors.grey[500], fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quick Actions
// ─────────────────────────────────────────────────────────────────────────────

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'QUICK ACTIONS',
          style: TextStyle(
            color: Colors.grey[500],
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _ActionTile(
                icon: Icons.task_alt_rounded,
                label: 'Tasks',
                subtitle: 'Manage your to-dos',
                color: Colors.deepOrange,
                onTap: () => Navigator.pushNamed(context, TodoPage.routeName),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActionTile(
                icon: Icons.calendar_today_rounded,
                label: 'Calendar',
                subtitle: 'Events & schedule',
                color: Colors.blueAccent,
                onTap: () =>
                    Navigator.pushNamed(context, EventsCalendarPage.routeName),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _ActionTileWide(
          icon: Icons.bookmark_rounded,
          label: 'Bookmarks',
          subtitle: 'View saved photos from galleries',
          color: Colors.amber,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const BookmarkScreen()),
          ),
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 14),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: TextStyle(color: Colors.grey[500], fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionTileWide extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ActionTileWide({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(color: Colors.grey[500], fontSize: 11),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: Colors.grey[600],
              size: 20,
            ),
          ],
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
                        color: Colors.pink[300],
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
