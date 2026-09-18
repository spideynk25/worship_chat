import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/widgets/loader.dart';
import 'package:worship_chat/features/group/controller/group_controller.dart';
import 'package:worship_chat/models/group.dart';
import 'package:worship_chat/models/group_chat_message_model.dart';

class GroupInfoScreen extends ConsumerStatefulWidget {
  final String groupId;
  final String groupPic;
  final String name;
  final String? wish;
  final String? queendom;
  final Color? color;

  const GroupInfoScreen({
    super.key,
    required this.groupId,
    required this.groupPic,
    required this.name,
    required this.wish,
    required this.queendom,
    required this.color,
  });

  @override
  ConsumerState<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends ConsumerState<GroupInfoScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late final Future<List<GroupChatMessageModel>> _mediaFuture;
  late final Future<List<GroupChatMessageModel>> _linksFuture;

  static const _tabs = [
    (
      icon: Icons.image_outlined,
      activeIcon: Icons.image_rounded,
      label: 'Media',
    ),
    (icon: Icons.link_outlined, activeIcon: Icons.link_rounded, label: 'Links'),
    (
      icon: Icons.group_outlined,
      activeIcon: Icons.group_rounded,
      label: 'Members',
    ),
  ];

  Color get _accentColor {
    if (widget.color == null) return tabColor;
    final hsl = HSLColor.fromColor(widget.color!);
    if (hsl.lightness < 0.25) {
      return hsl.withLightness(0.55).withSaturation(0.7).toColor();
    }
    return widget.color!;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _mediaFuture = ref
        .read(groupControllerProvider)
        .getSharedGroupMedia(widget.groupId);
    _linksFuture = ref
        .read(groupControllerProvider)
        .getSharedGroupLinks(widget.groupId);
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
        body: StreamBuilder<GroupModel>(
          stream: FirebaseFirestore.instance
              .collection('groups')
              .doc(widget.groupId)
              .snapshots()
              .map((doc) => GroupModel.fromMap(doc.data()!)),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Loader();
            }
            final group = snapshot.data;

            return NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                SliverAppBar(
                  expandedHeight: 320,
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
                    background: _GroupHeroHeader(
                      group: group,
                      groupPic: widget.groupPic,
                      name: widget.name,
                      groupId: widget.groupId,
                      accentColor: _accentColor,
                    ),
                  ),
                ),
                SliverToBoxAdapter(child: _buildInfoCards(group)),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _CustomTabBarDelegate(
                    controller: _tabController,
                    color: _accentColor,
                    tabs: _tabs,
                  ),
                ),
              ],
              body: TabBarView(
                controller: _tabController,
                children: [
                  _MediaTab(
                    mediaFuture: _mediaFuture,
                    accentColor: _accentColor,
                  ),
                  _LinksTab(
                    linksFuture: _linksFuture,
                    accentColor: _accentColor,
                  ),
                  _MembersTab(
                    membersUid: group?.membersUid ?? [],
                    accentColor: _accentColor,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildInfoCards(GroupModel? group) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: _GlassCard(
        accentColor: _accentColor,
        child: Column(
          children: [
            if (group?.queendom != null &&
                group!.queendom!.isNotEmpty &&
                group.queendom != 'None') ...[
              _DetailRow(
                icon: Icons.auto_awesome,
                label: 'Queendom',
                value: group.queendom!,
                accentColor: _accentColor,
              ),
              _Hairline(),
            ],
            if (group?.family != null &&
                group!.family!.isNotEmpty &&
                group.family != 'None') ...[
              _DetailRow(
                icon: Icons.diversity_3_outlined,
                label: 'Family',
                value: '${group.family} Family',
                accentColor: _accentColor,
              ),
              _Hairline(),
            ],
            if (group?.position != null &&
                group!.position!.isNotEmpty &&
                group.position != 'None') ...[
              _DetailRow(
                icon: Icons.workspace_premium_outlined,
                label: 'Position',
                value: group.position!,
                accentColor: _accentColor,
              ),
              _Hairline(),
            ],
            if (widget.wish != null && widget.wish!.isNotEmpty) ...[
              _DetailRow(
                icon: Icons.favorite_border_rounded,
                label: 'Wish',
                value: widget.wish!,
                accentColor: _accentColor,
              ),
              _Hairline(),
            ],
            FutureBuilder<List<GroupChatMessageModel>>(
              future: _mediaFuture,
              builder: (context, snapshot) {
                return _DetailRow(
                  icon: Icons.perm_media_outlined,
                  label: 'Shared Media',
                  value: snapshot.connectionState == ConnectionState.waiting
                      ? 'Counting...'
                      : '${snapshot.data?.length ?? 0} files',
                  accentColor: _accentColor,
                );
              },
            ),
            _Hairline(),
            _DetailRow(
              icon: Icons.group_outlined,
              label: 'Members',
              value: '${group?.membersUid.length ?? 0} members',
              accentColor: _accentColor,
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

// ── Group hero header ─────────────────────────────────────────────────────────

class _GroupHeroHeader extends StatelessWidget {
  final GroupModel? group;
  final String groupPic;
  final String name;
  final String groupId;
  final Color accentColor;

  const _GroupHeroHeader({
    required this.group,
    required this.groupPic,
    required this.name,
    required this.groupId,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (groupPic.isNotEmpty)
          CachedNetworkImage(
            imageUrl: groupPic,
            fit: BoxFit.cover,
            color: Colors.black.withOpacity(0.6),
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
                  accentColor.withOpacity(0.4),
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
                  if (groupPic.isNotEmpty) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => _FullScreenImage(
                          imageUrl: groupPic,
                          heroTag: 'group_$groupId',
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
                          color: accentColor.withOpacity(0.7),
                          width: 2.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: accentColor.withOpacity(0.3),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                    Hero(
                      tag: 'group_$groupId',
                      child: CircleAvatar(
                        radius: 50,
                        backgroundImage: groupPic.isNotEmpty
                            ? NetworkImage(groupPic)
                            : null,
                        backgroundColor: Colors.grey[800],
                        child: groupPic.isEmpty
                            ? const Icon(
                                Icons.group,
                                color: Colors.white,
                                size: 40,
                              )
                            : null,
                      ),
                    ),
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: accentColor,
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
                textAlign: TextAlign.center,
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
                  color: accentColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: accentColor.withOpacity(0.5),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.group, color: accentColor, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      '${group?.membersUid.length ?? 0} members',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: accentColor,
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
  final Color accentColor;
  const _GlassCard({required this.child, required this.accentColor});

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
  final Color accentColor;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.accentColor,
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
              color: accentColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: accentColor, size: 18),
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
  final Future<List<GroupChatMessageModel>> mediaFuture;
  final Color accentColor;
  const _MediaTab({required this.mediaFuture, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<GroupChatMessageModel>>(
      future: mediaFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator(color: accentColor));
        }
        final media = snapshot.data ?? [];
        if (media.isEmpty) {
          return _EmptyState(
            icon: Icons.photo_library_outlined,
            message: 'No shared media yet',
            accentColor: accentColor,
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
                  builder: (_) => _MediaPageViewer(
                    messages: media,
                    initialIndex: index,
                    accentColor: accentColor,
                  ),
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
  final GroupChatMessageModel message;
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
  final List<GroupChatMessageModel> messages;
  final int initialIndex;
  final Color accentColor;
  const _MediaPageViewer({
    required this.messages,
    required this.initialIndex,
    required this.accentColor,
  });

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
                        placeholder: (_, __) => Center(
                          child: CircularProgressIndicator(
                            color: widget.accentColor,
                          ),
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
                        color: _currentIndex == i
                            ? widget.accentColor
                            : Colors.grey[700],
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
  final Future<List<GroupChatMessageModel>> linksFuture;
  final Color accentColor;
  const _LinksTab({required this.linksFuture, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<GroupChatMessageModel>>(
      future: linksFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator(color: accentColor));
        }
        final links = snapshot.data ?? [];
        if (links.isEmpty) {
          return _EmptyState(
            icon: Icons.link_outlined,
            message: 'No shared links yet',
            accentColor: accentColor,
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
                      color: accentColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.link_rounded,
                      color: accentColor,
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

// ── Members tab ───────────────────────────────────────────────────────────────

class _MembersTab extends StatelessWidget {
  final List<dynamic> membersUid;
  final Color accentColor;
  const _MembersTab({required this.membersUid, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    if (membersUid.isEmpty) {
      return _EmptyState(
        icon: Icons.group_outlined,
        message: 'No members found',
        accentColor: accentColor,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: membersUid.length,
      separatorBuilder: (_, __) =>
          Container(height: 0.5, color: Colors.white.withOpacity(0.06)),
      itemBuilder: (context, index) {
        final uid = membersUid[index];
        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance.collection('users').doc(uid).get(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    CircleAvatar(radius: 22, backgroundColor: Colors.grey[800]),
                    const SizedBox(width: 12),
                    Container(
                      width: 120,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.grey[800],
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ],
                ),
              );
            }
            final data = snapshot.data!.data() as Map<String, dynamic>?;
            if (data == null) return const SizedBox.shrink();

            final name = data['name'] ?? 'Unknown';
            final userName = data['userName'] ?? '';
            final profilePic = data['profilePic'] ?? '';
            final isOnline = data['isOnline'] ?? false;

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
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundImage: profilePic.isNotEmpty
                            ? NetworkImage(profilePic)
                            : null,
                        backgroundColor: Colors.grey[800],
                        child: profilePic.isEmpty
                            ? const Icon(
                                Icons.person,
                                color: Colors.white54,
                                size: 22,
                              )
                            : null,
                      ),
                      if (isOnline)
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: Colors.greenAccent,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: backgroundColor,
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (userName.isNotEmpty)
                          Text(
                            '@$userName',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withOpacity(0.4),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isOnline ? Colors.greenAccent : Colors.grey,
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

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color accentColor;
  const _EmptyState({
    required this.icon,
    required this.message,
    required this.accentColor,
  });

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
