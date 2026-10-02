import 'dart:io';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:share_handler/share_handler.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/screens/combined_contact_screen.dart';
import 'package:worship_chat/common/utils/fcm_token_manager.dart';
import 'package:worship_chat/common/utils/share_intent_service.dart';
import 'package:worship_chat/features/auth/controller/auth_controller.dart';
import 'package:worship_chat/features/chat/controller/chat_controller.dart';
import 'package:worship_chat/features/chat/widgets/all_user_screen.dart';
import 'package:worship_chat/features/dashboard/screens/dashboard_page.dart';
import 'package:worship_chat/features/group/controller/group_controller.dart';
import 'package:worship_chat/features/group/screens/create_group_screen.dart';
import 'package:worship_chat/features/group/screens/group_list_screen.dart';
import 'package:worship_chat/features/group/screens/queen_pooja_queendom_screen.dart';
import 'package:worship_chat/features/group/screens/queen_rashmika_queendom_screen.dart';
import 'package:worship_chat/features/home/screens/profile_screen.dart';
import 'package:worship_chat/features/home/widgets/dynamic_text_widget.dart';
import 'package:worship_chat/features/share/screens/share_upload_screen.dart';
import 'package:worship_chat/features/status/controller/status_controller.dart';
import 'package:worship_chat/models/chat_contact.dart';
import 'package:worship_chat/models/group.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:worship_chat/models/user_model.dart';
import 'package:worship_chat/common/widgets/user_avatar.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  int _selectedIndex = 0;
  late final PageController _pageController;
  StreamSubscription? _shareSubscription;
  StreamSubscription<DocumentSnapshot>? _userSubscription;
  bool _initialShareProcessed = false;

  static const List<Widget> _screens = [
    DashboardPage(),
    CombinedContactsScreen(isAllChats: false),
    QueenPoojaQueenScreen(),
    QueenRashmikaQueenScreen(),
    GroupListScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pageController = PageController(initialPage: _selectedIndex);

    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isNotEmpty) {
      _userSubscription = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots()
          .listen((snapshot) {
        if (snapshot.exists && snapshot.data() != null) {
          final user = UserModel.fromMap(snapshot.data() as Map<String, dynamic>);
          Hive.box<UserModel>('userBox').put('currentUser', user);
        }
      }, onError: (err) {
        debugPrint('⚠️ HomeScreen user listener error: $err');
      });
    }

    // Delay so widget tree is fully ready before pushing routes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initShareHandler();
      FCMTokenManager.refreshAndSaveFCMToken();
      ref.read(authControllerProvider).getUsetData();
    });
  }

  Future<void> _initShareHandler() async {
    final handler = ShareHandlerPlatform.instance;

    // ── Handle initial share (app launched via share) ─────────────────
    if (!_initialShareProcessed) {
      _initialShareProcessed = true;
      try {
        final initial = await handler.getInitialSharedMedia();
        if (initial != null && mounted) {
          final files = extractImageFiles(initial);
          if (files.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _openShareUpload(files);
            });
          }
        }
      } catch (_) {
        // No initial share intent — safe to ignore
      }
    }

    // ── Handle share while app is already open ────────────────────────
    await _shareSubscription?.cancel();
    _shareSubscription = handler.sharedMediaStream.listen((SharedMedia media) {
      final files = extractImageFiles(media);
      if (files.isNotEmpty && mounted) {
        _openShareUpload(files);
      }
    });
  }

  void _openShareUpload(List<File> files) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ShareUploadScreen(files: files)),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _shareSubscription?.cancel();
    _userSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.resumed:
        ref.read(authControllerProvider).setUserState(true);
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        ref.read(authControllerProvider).setUserState(false);
        break;
    }
  }

  void _onItemTapped(int index) {
    if (_selectedIndex == index) return;
    HapticFeedback.selectionClick();
    final prevIndex = _selectedIndex;
    setState(() {
      _selectedIndex = index;
    });
    if (_pageController.hasClients) {
      final diff = (prevIndex - index).abs();
      if (diff <= 1) {
        _pageController.animateToPage(
          index,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
      } else {
        _pageController.jumpToPage(index);
      }
    }
  }

  void _onPageChanged(int index) {
    if (_selectedIndex != index) {
      HapticFeedback.selectionClick();
      setState(() {
        _selectedIndex = index;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserUid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(90),
        child: ValueListenableBuilder<Box<UserModel>>(
          valueListenable: Hive.box<UserModel>('userBox').listenable(),
          builder: (context, Box<UserModel> userBox, _) {
            final user = userBox.get('currentUser');
            final authUser = FirebaseAuth.instance.currentUser;

            final displayName = (user?.name != null && user!.name!.trim().isNotEmpty)
                ? user.name!.trim()
                : (authUser?.displayName != null && authUser!.displayName!.trim().isNotEmpty)
                    ? authUser.displayName!.trim()
                    : 'User';

            final displayUserName = (user?.userName != null && user!.userName!.trim().isNotEmpty)
                ? user.userName!.trim()
                : (authUser?.displayName != null && authUser!.displayName!.trim().isNotEmpty)
                    ? authUser.displayName!.trim()
                    : 'User';

            final rawPic = (user?.profilePic != null && user!.profilePic!.trim().isNotEmpty)
                ? user.profilePic!.trim()
                : (authUser?.photoURL != null && authUser!.photoURL!.trim().isNotEmpty)
                    ? authUser.photoURL!.trim()
                    : null;

            final displayPic = UserAvatar.sanitizeUrl(rawPic);

            return AppBar(
              toolbarHeight: 90,
              backgroundColor: appBarColor,
              elevation: 0,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Text(
                    'Worship Chat',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  DynamicTextWidget(),
                ],
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 2),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        displayName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: tabColor,
                        ),
                      ),
                      Text(
                        displayUserName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w400,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton(
                  position: PopupMenuPosition.under,
                  padding: EdgeInsets.zero,
                  iconSize: 50,
                  icon: Hero(
                    tag: user?.uid ?? (currentUserUid.isNotEmpty ? currentUserUid : "profile_icon"),
                    child: UserAvatar(url: displayPic, radius: 24),
                  ),
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      child: const Text('Profile'),
                      onTap: () => Navigator.push(
                        context,
                        PageRouteBuilder(
                          pageBuilder: (context, animation, secondaryAnimation) =>
                              const ProfileScreen(),
                          transitionsBuilder:
                              (context, animation, secondaryAnimation, child) {
                                return FadeTransition(
                                  opacity: animation,
                                  child: child,
                                );
                              },
                        ),
                      ),
                    ),
                    PopupMenuItem(
                      child: const Text('Create Group'),
                      onTap: () => Future.microtask(() {
                        if (mounted) {
                          Navigator.pushNamed(
                            this.context,
                            CreateGroupScreen.routeName,
                          );
                        }
                      }),
                    ),
                    PopupMenuItem(
                      child: const Text('Logout'),
                      onTap: () => Future.microtask(() async {
                        await FirebaseMessaging.instance.deleteToken();
                        Hive.box<UserModel>('userBox').delete('currentUser');
                        if (mounted) {
                          ref.read(authControllerProvider).logout(this.context);
                        }
                      }),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),

      // ── Swipeable PageView with KeepAlive for smooth swiping & state persistence ──
      body: PageView.builder(
        controller: _pageController,
        onPageChanged: _onPageChanged,
        physics: const BouncingScrollPhysics(),
        itemCount: _screens.length,
        itemBuilder: (context, index) {
          return _KeepAlivePage(child: _screens[index]);
        },
      ),

      // ── Dedicated, isolated bottom nav with badges ───────────────────────
      bottomNavigationBar: _HomeScreenBottomNavBar(
        selectedIndex: _selectedIndex,
        onItemTapped: _onItemTapped,
      ),

      floatingActionButton: _selectedIndex == 1
          ? FloatingActionButton(
              onPressed: () {
                Navigator.pushNamed(context, AllUserScreen.routeName);
              },
              backgroundColor: tabColor,
              child: const Icon(Icons.comment, color: Colors.white),
            )
          : null,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Keep-Alive Wrapper to preserve state & prevent rebuilds during swiping
// ─────────────────────────────────────────────────────────────────────────────

class _KeepAlivePage extends StatefulWidget {
  final Widget child;
  const _KeepAlivePage({required this.child});

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dedicated Bottom Navigation Bar Widget
// Maintains its own cached stream subscriptions so tab switching is instantaneous
// ─────────────────────────────────────────────────────────────────────────────

class _HomeScreenBottomNavBar extends ConsumerStatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemTapped;

  const _HomeScreenBottomNavBar({
    required this.selectedIndex,
    required this.onItemTapped,
  });

  @override
  ConsumerState<_HomeScreenBottomNavBar> createState() =>
      _HomeScreenBottomNavBarState();
}

class _HomeScreenBottomNavBarState
    extends ConsumerState<_HomeScreenBottomNavBar> {
  late final Stream<List<ChatContact>> _chatContactsStream;
  late final Stream<List<GroupModel>> _generalGroupsStream;
  late final Stream<List<GroupModel>> _poojaGroupsStream;
  late final Stream<List<GroupModel>> _rashmikaGroupsStream;

  @override
  void initState() {
    super.initState();
    _chatContactsStream = ref.read(chatControllerProvider).chatContacts();
    _generalGroupsStream = ref.read(groupControllerProvider).chatGroups();
    _poojaGroupsStream = ref.read(groupControllerProvider).getQueenPoojaStream();
    _rashmikaGroupsStream =
        ref.read(groupControllerProvider).getQueenRashmikaStream();
  }

  int _getUnreadChatsCount(List<ChatContact> contacts) {
    return contacts
        .where((c) => c.unseenCount != null && c.unseenCount != false)
        .length;
  }

  int _getUnseenStatusCount(
    List<Map<String, dynamic>> statuses,
    String currentUserUid,
  ) {
    final Map<String, List<Map<String, dynamic>>> byUser = {};
    for (final s in statuses) {
      final uid = s['uid'] as String;
      if (uid == currentUserUid) continue;
      byUser.putIfAbsent(uid, () => []).add(s);
    }

    int count = 0;
    for (final userStatuses in byUser.values) {
      final hasUnseen = userStatuses.any((s) {
        final seenBy = Map<String, dynamic>.from(s['seenBy'] as Map? ?? {});
        return !seenBy.containsKey(currentUserUid);
      });
      if (hasUnseen) count++;
    }
    return count;
  }

  int _getUnseenCountForQueendom(List<GroupModel> groups, String queendom) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return 0;
    return groups
        .where(
          (g) => g.queendom == queendom && g.hasUnseenForUser(currentUserId),
        )
        .length;
  }

  int _getUnseenCountForGeneralGroups(List<GroupModel> groups) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return 0;
    return groups
        .where((g) => g.queendom == 'None' && g.hasUnseenForUser(currentUserId))
        .length;
  }

  @override
  Widget build(BuildContext context) {
    final currentUserUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final statuses = ref.watch(statusStreamProvider).valueOrNull ?? const [];

    return StreamBuilder<List<ChatContact>>(
      stream: _chatContactsStream,
      builder: (context, chatSnapshot) {
        return StreamBuilder<List<GroupModel>>(
          stream: _generalGroupsStream,
          builder: (context, generalSnapshot) {
            return StreamBuilder<List<GroupModel>>(
              stream: _poojaGroupsStream,
              builder: (context, poojaSnapshot) {
                return StreamBuilder<List<GroupModel>>(
                  stream: _rashmikaGroupsStream,
                  builder: (context, rashmikaSnapshot) {
                    final contacts = chatSnapshot.data ?? const [];
                    final generalGroups = generalSnapshot.data ?? const [];
                    final poojaGroups = poojaSnapshot.data ?? const [];
                    final rashmikaGroups = rashmikaSnapshot.data ?? const [];

                    final unreadChatsCount = _getUnreadChatsCount(contacts);
                    final unseenStatusCount =
                        _getUnseenStatusCount(statuses, currentUserUid);
                    final generalUnseenCount =
                        _getUnseenCountForGeneralGroups(generalGroups);
                    final poojaUnseenCount =
                        _getUnseenCountForQueendom(poojaGroups, 'Queen Pooja');
                    final rashmikaUnseenCount =
                        _getUnseenCountForQueendom(rashmikaGroups, 'Queen Rashmika');

                    final chatTabBadge = unreadChatsCount + unseenStatusCount;

                    return _buildModernBottomNavBar(
                      chatTabBadge: chatTabBadge,
                      poojaUnseenCount: poojaUnseenCount,
                      rashmikaUnseenCount: rashmikaUnseenCount,
                      generalUnseenCount: generalUnseenCount,
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildModernBottomNavBar({
    required int chatTabBadge,
    required int poojaUnseenCount,
    required int rashmikaUnseenCount,
    required int generalUnseenCount,
  }) {
    final navItems = [
      _NavBarItemConfig(
        iconBuilder: (isSelected) => Icon(
          Icons.grid_view_rounded,
          size: isSelected ? 21 : 22,
          color: isSelected ? tabColor : Colors.white.withValues(alpha: 0.45),
        ),
        label: 'Home',
        badgeCount: 0,
      ),
      _NavBarItemConfig(
        iconBuilder: (isSelected) => Icon(
          Icons.chat_bubble_rounded,
          size: isSelected ? 21 : 22,
          color: isSelected ? tabColor : Colors.white.withValues(alpha: 0.45),
        ),
        label: 'Chats',
        badgeCount: chatTabBadge,
      ),
      _NavBarItemConfig(
        iconBuilder: (isSelected) => FaIcon(
          FontAwesomeIcons.crown,
          size: isSelected ? 18 : 19,
          color: isSelected ? tabColor : Colors.white.withValues(alpha: 0.45),
        ),
        label: 'Pooja',
        badgeCount: poojaUnseenCount,
      ),
      _NavBarItemConfig(
        iconBuilder: (isSelected) => FaIcon(
          FontAwesomeIcons.crown,
          size: isSelected ? 18 : 19,
          color: isSelected ? tabColor : Colors.white.withValues(alpha: 0.45),
        ),
        label: 'Rashmika',
        badgeCount: rashmikaUnseenCount,
      ),
      _NavBarItemConfig(
        iconBuilder: (isSelected) => Icon(
          Icons.groups_rounded,
          size: isSelected ? 21 : 22,
          color: isSelected ? tabColor : Colors.white.withValues(alpha: 0.45),
        ),
        label: 'Groups',
        badgeCount: generalUnseenCount,
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF14131B),
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1.0,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(22),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(navItems.length, (index) {
              final item = navItems[index];
              final isSelected = widget.selectedIndex == index;

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.lightImpact();
                  widget.onItemTapped(index);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeInOutCubic,
                  padding: isSelected
                      ? const EdgeInsets.symmetric(horizontal: 14, vertical: 8)
                      : const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: isSelected
                      ? BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              tabColor.withValues(alpha: 0.22),
                              accentOrange.withValues(alpha: 0.12),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: tabColor.withValues(alpha: 0.45),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: tabColor.withValues(alpha: 0.18),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        )
                      : const BoxDecoration(
                          color: Colors.transparent,
                        ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildNavIcon(item: item, isSelected: isSelected),
                      ClipRect(
                        child: AnimatedSize(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOutCubic,
                          child: isSelected
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const SizedBox(width: 7),
                                    Text(
                                      item.label,
                                      maxLines: 1,
                                      style: const TextStyle(
                                        color: tabColor,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                  ],
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildNavIcon({
    required _NavBarItemConfig item,
    required bool isSelected,
  }) {
    final iconWidget = item.iconBuilder(isSelected);

    if (item.badgeCount <= 0) {
      return iconWidget;
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        iconWidget,
        Positioned(
          right: -7,
          top: -6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1.5),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [tabColor, accentOrange],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF14131B), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: tabColor.withValues(alpha: 0.45),
                  blurRadius: 5,
                  offset: const Offset(0, 1.5),
                ),
              ],
            ),
            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
            child: Center(
              child: Text(
                item.badgeCount > 99
                    ? '99+'
                    : item.badgeCount > 9
                        ? '9+'
                        : '${item.badgeCount}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NavBarItemConfig {
  final Widget Function(bool isSelected) iconBuilder;
  final String label;
  final int badgeCount;

  const _NavBarItemConfig({
    required this.iconBuilder,
    required this.label,
    required this.badgeCount,
  });
}
