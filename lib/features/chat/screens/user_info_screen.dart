import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/widgets/loader.dart';
import 'package:worship_chat/common/widgets/user_avatar.dart';
import 'package:worship_chat/features/auth/controller/auth_controller.dart';
import 'package:worship_chat/features/chat/controller/chat_controller.dart';
import 'package:worship_chat/models/one_to_one_message_model.dart';
import 'package:worship_chat/models/user_model.dart';

class UserInfoScreen extends ConsumerStatefulWidget {
  final String userId;
  final String profilePic;
  final String name;

  const UserInfoScreen({
    super.key,
    required this.userId,
    required this.profilePic,
    required this.name,
  });

  @override
  ConsumerState<UserInfoScreen> createState() => _UserInfoScreenState();
}

class _UserInfoScreenState extends ConsumerState<UserInfoScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late final Future<List<OneToOneMessageModel>> _mediaFuture;
  late final Future<List<OneToOneMessageModel>> _linksFuture;

  static const _tabs = [
    (
      icon: Icons.image_outlined,
      activeIcon: Icons.image_rounded,
      label: 'Media',
    ),
    (icon: Icons.link_outlined, activeIcon: Icons.link_rounded, label: 'Links'),
    (
      icon: Icons.insert_drive_file_outlined,
      activeIcon: Icons.insert_drive_file_rounded,
      label: 'Docs',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _mediaFuture = ref
        .read(chatControllerProvider)
        .getSharedMedia(widget.userId);
    _linksFuture = ref
        .read(chatControllerProvider)
        .getSharedLinks(widget.userId);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        backgroundColor: backgroundColor,
        body: StreamBuilder<UserModel>(
          stream: ref.watch(authControllerProvider).userDataById(widget.userId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Loader();
            }
            final user = snapshot.data;

            return NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                SliverAppBar(
                  expandedHeight: 300,
                  pinned: true,
                  stretch: true,
                  backgroundColor: appBarColor,
                  elevation: 0,
                  leading: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      margin: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black38,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white12, width: 0.8),
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                  flexibleSpace: FlexibleSpaceBar(
                    stretchModes: const [
                      StretchMode.zoomBackground,
                      StretchMode.fadeTitle,
                    ],
                    background: _HeroHeader(
                      user: user,
                      profilePic: widget.profilePic,
                      name: widget.name,
                      userId: widget.userId,
                    ),
                  ),
                ),
                SliverToBoxAdapter(child: _buildInfoSection(user)),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _CustomTabBarDelegate(
                    controller: _tabController,
                    color: tabColor,
                    tabs: _tabs,
                  ),
                ),
              ],
              body: TabBarView(
                controller: _tabController,
                children: [
                  _MediaTab(mediaFuture: _mediaFuture),
                  _LinksTab(linksFuture: _linksFuture),
                  const _DocsTab(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildInfoSection(UserModel? user) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: _GlassCard(
        child: Column(
          children: [
            if (user?.userName != null && user!.userName!.isNotEmpty) ...[
              _DetailRow(
                icon: Icons.alternate_email_rounded,
                label: 'Username',
                value: '@${user.userName}',
              ),
              _Hairline(),
            ],
            if (user?.email != null && user!.email!.isNotEmpty) ...[
              _DetailRow(
                icon: Icons.mail_outline_rounded,
                label: 'Email',
                value: user.email??"N/A",
              ),
              _Hairline(),
            ],
            FutureBuilder<List<OneToOneMessageModel>>(
              future: _mediaFuture,
              builder: (context, snapshot) {
                return _DetailRow(
                  icon: Icons.perm_media_outlined,
                  label: 'Shared Media',
                  value: snapshot.connectionState == ConnectionState.waiting
                      ? 'Counting...'
                      : '${snapshot.data?.length ?? 0} files',
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ── Custom tab bar ────────────────────────────────────────────────────────────

class _CustomTabBar extends StatefulWidget {
  final TabController controller;
  final Color color;
  final List<({IconData icon, IconData activeIcon, String label})> tabs;

  const _CustomTabBar({
    required this.controller,
    required this.color,
    required this.tabs,
  });

  @override
  State<_CustomTabBar> createState() => _CustomTabBarState();
}

class _CustomTabBarState extends State<_CustomTabBar> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTabChanged);
  }

  void _onTabChanged() => setState(() {});

  @override
  void dispose() {
    widget.controller.removeListener(_onTabChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(widget.tabs.length, (i) {
        final isActive = widget.controller.index == i;
        final tab = widget.tabs[i];
        return Expanded(
          child: GestureDetector(
            onTap: () => widget.controller.animateTo(i),
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              height: 62,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 4),
                  Icon(
                    isActive ? tab.activeIcon : tab.icon,
                    size: 22,
                    color: isActive
                        ? widget.color
                        : Colors.white.withOpacity(0.35),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    tab.label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                      color: isActive
                          ? widget.color
                          : Colors.white.withOpacity(0.35),
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Dot indicator
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    width: isActive ? 5 : 0,
                    height: isActive ? 5 : 0,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.color,
                      boxShadow: isActive
                          ? [
                              BoxShadow(
                                color: widget.color.withOpacity(0.9),
                                blurRadius: 6,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}

// ── Tab bar sliver delegate ───────────────────────────────────────────────────

class _CustomTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabController controller;
  final Color color;
  final List<({IconData icon, IconData activeIcon, String label})> tabs;

  _CustomTabBarDelegate({
    required this.controller,
    required this.color,
    required this.tabs,
  });

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: backgroundColor,
      child: Column(
        children: [
          Expanded(
            child: _CustomTabBar(
              controller: controller,
              color: color,
              tabs: tabs,
            ),
          ),
          Container(height: 0.5, color: Colors.white.withOpacity(0.08)),
        ],
      ),
    );
  }

  @override
  double get maxExtent => 66;

  @override
  double get minExtent => 66;

  @override
  bool shouldRebuild(_CustomTabBarDelegate oldDelegate) => false;
}

// ── Hero header ───────────────────────────────────────────────────────────────

class _HeroHeader extends StatelessWidget {
  final UserModel? user;
  final String profilePic;
  final String name;
  final String userId;

  const _HeroHeader({
    required this.user,
    required this.profilePic,
    required this.name,
    required this.userId,
  });

  @override
  Widget build(BuildContext context) {
    final isOnline = user?.isOnline ?? false;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (profilePic.isNotEmpty)
          CachedNetworkImage(
            imageUrl: profilePic,
            fit: BoxFit.cover,
            color: Colors.black.withOpacity(0.55),
            colorBlendMode: BlendMode.darken,
          )
        else
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  appBarColor,
                  tabColor.withOpacity(0.4),
                  backgroundColor,
                ],
              ),
            ),
          ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: 120,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, backgroundColor],
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 24,
          left: 0,
          right: 0,
          child: Column(
            children: [
              GestureDetector(
                onTap: () {
                  if (profilePic.isNotEmpty) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => _FullScreenImage(
                          imageUrl: profilePic,
                          heroTag: 'profile_$userId',
                          label: name,
                        ),
                      ),
                    );
                  }
                },
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 108,
                      height: 108,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isOnline
                              ? Colors.greenAccent.withOpacity(0.7)
                              : Colors.white24,
                          width: 2.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: isOnline
                                ? Colors.greenAccent.withOpacity(0.25)
                                : Colors.black26,
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                    Hero(
                      tag: 'profile_$userId',
                      child: UserAvatar(
                        url: profilePic.isNotEmpty ? profilePic : null,
                        radius: 50,
                      ),
                    ),
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: tabColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: backgroundColor, width: 2),
                        ),
                        child: const Icon(
                          Icons.zoom_in_rounded,
                          color: Colors.white,
                          size: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                name,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 0.3,
                  shadows: [
                    Shadow(
                      color: Colors.black54,
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: isOnline
                      ? Colors.greenAccent.withOpacity(0.15)
                      : Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isOnline
                        ? Colors.greenAccent.withOpacity(0.5)
                        : Colors.white12,
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isOnline ? Colors.greenAccent : Colors.grey,
                        boxShadow: isOnline
                            ? [
                                BoxShadow(
                                  color: Colors.greenAccent.withOpacity(0.7),
                                  blurRadius: 6,
                                ),
                              ]
                            : null,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isOnline ? 'Online' : 'Offline',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isOnline ? Colors.greenAccent : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Glass card ────────────────────────────────────────────────────────────────

class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.08), width: 0.8),
      ),
      child: child,
    );
  }
}

// ── Hairline ──────────────────────────────────────────────────────────────────

class _Hairline extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 0.5,
      margin: const EdgeInsets.symmetric(vertical: 2),
      color: Colors.white.withOpacity(0.07),
    );
  }
}

// ── Detail row ────────────────────────────────────────────────────────────────

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: tabColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: tabColor, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withOpacity(0.4),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: Colors.white.withOpacity(0.2),
            size: 18,
          ),
        ],
      ),
    );
  }
}

// ── Media tab ─────────────────────────────────────────────────────────────────

class _MediaTab extends StatelessWidget {
  final Future<List<OneToOneMessageModel>> mediaFuture;
  const _MediaTab({required this.mediaFuture});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<OneToOneMessageModel>>(
      future: mediaFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: tabColor),
          );
        }
        final media = snapshot.data ?? [];
        if (media.isEmpty) {
          return const _EmptyState(
            icon: Icons.photo_library_outlined,
            message: 'No shared media yet',
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.all(2),
          cacheExtent: 500,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 2,
            mainAxisSpacing: 2,
          ),
          itemCount: media.length,
          itemBuilder: (context, index) {
            return GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      _MediaPageViewer(messages: media, initialIndex: index),
                ),
              ),
              child: _MediaThumbnail(message: media[index]),
            );
          },
        );
      },
    );
  }
}

// ── Media thumbnail ───────────────────────────────────────────────────────────

class _MediaThumbnail extends StatelessWidget {
  final OneToOneMessageModel message;
  const _MediaThumbnail({required this.message});

  @override
  Widget build(BuildContext context) {
    final url = message.fileMessageData ?? '';
    return Container(
      color: Colors.grey[900],
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (url.isNotEmpty)
            CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(
                color: Colors.grey[850],
                child: const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: tabColor,
                      strokeWidth: 2,
                    ),
                  ),
                ),
              ),
              errorWidget: (_, __, ___) => const Center(
                child: Icon(Icons.broken_image, color: Colors.grey),
              ),
            ),
          if (message.messageType == 'video')
            Container(
              color: Colors.black45,
              child: const Center(
                child: Icon(
                  Icons.play_circle_fill,
                  color: Colors.white70,
                  size: 30,
                ),
              ),
            ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 3),
              color: Colors.black54,
              child: Text(
                DateFormat('MMM d').format(message.timeSent),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 9),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Media page viewer ─────────────────────────────────────────────────────────

class _MediaPageViewer extends StatefulWidget {
  final List<OneToOneMessageModel> messages;
  final int initialIndex;
  const _MediaPageViewer({required this.messages, required this.initialIndex});

  @override
  State<_MediaPageViewer> createState() => _MediaPageViewerState();
}

class _MediaPageViewerState extends State<_MediaPageViewer> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final msg = widget.messages[_currentIndex];
    return SafeArea(
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.white),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                DateFormat('MMM d, y').format(msg.timeSent),
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
              Text(
                DateFormat('hh:mm a').format(msg.timeSent),
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_currentIndex + 1} / ${widget.messages.length}',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              ),
            ),
          ],
        ),
        body: PageView.builder(
          controller: _pageController,
          itemCount: widget.messages.length,
          onPageChanged: (i) => setState(() => _currentIndex = i),
          itemBuilder: (context, index) {
            final url = widget.messages[index].fileMessageData ?? '';
            return InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Center(
                child: url.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: url,
                        fit: BoxFit.contain,
                        placeholder: (_, __) => const Center(
                          child: CircularProgressIndicator(color: tabColor),
                        ),
                        errorWidget: (_, __, ___) => const Icon(
                          Icons.broken_image,
                          color: Colors.grey,
                          size: 64,
                        ),
                      )
                    : const Icon(
                        Icons.broken_image,
                        color: Colors.grey,
                        size: 64,
                      ),
              ),
            );
          },
        ),
        bottomNavigationBar: widget.messages.length > 1
            ? Container(
                color: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    widget.messages.length.clamp(0, 20),
                    (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: _currentIndex == i ? 20 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        color: _currentIndex == i ? tabColor : Colors.grey[700],
                      ),
                    ),
                  ),
                ),
              )
            : null,
      ),
    );
  }
}

// ── Links tab ─────────────────────────────────────────────────────────────────

class _LinksTab extends StatelessWidget {
  final Future<List<OneToOneMessageModel>> linksFuture;
  const _LinksTab({required this.linksFuture});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<OneToOneMessageModel>>(
      future: linksFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: tabColor),
          );
        }
        final links = snapshot.data ?? [];
        if (links.isEmpty) {
          return const _EmptyState(
            icon: Icons.link_outlined,
            message: 'No shared links yet',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: links.length,
          separatorBuilder: (_, __) =>
              Container(height: 0.5, color: Colors.white.withOpacity(0.06)),
          itemBuilder: (context, index) {
            final msg = links[index];
            return Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withOpacity(0.07),
                  width: 0.8,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: tabColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.link_rounded,
                      color: tabColor,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          msg.text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.lightBlue,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          DateFormat('MMM d, y').format(msg.timeSent),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withOpacity(0.35),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ── Docs tab ──────────────────────────────────────────────────────────────────

class _DocsTab extends StatelessWidget {
  const _DocsTab();

  @override
  Widget build(BuildContext context) {
    return const _EmptyState(
      icon: Icons.insert_drive_file_outlined,
      message: 'No shared documents yet',
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withOpacity(0.08),
                width: 0.8,
              ),
            ),
            child: Icon(icon, size: 40, color: Colors.grey[600]),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(fontSize: 15, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}

// ── Full screen image ─────────────────────────────────────────────────────────

class _FullScreenImage extends StatelessWidget {
  final String imageUrl;
  final String heroTag;
  final String label;
  const _FullScreenImage({
    required this.imageUrl,
    required this.heroTag,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 15),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: Hero(
          tag: heroTag,
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 4.0,
            child: CachedNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.contain,
              placeholder: (_, __) => const Center(
                child: CircularProgressIndicator(color: tabColor),
              ),
              errorWidget: (_, __, ___) =>
                  const Icon(Icons.broken_image, color: Colors.grey, size: 64),
            ),
          ),
        ),
      ),
    );
  }
}
