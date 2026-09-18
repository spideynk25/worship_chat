import 'dart:io';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:share_handler/share_handler.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/screens/combined_contact_screen.dart';
import 'package:worship_chat/common/utils/share_intent_service.dart';
import 'package:worship_chat/common/utils/utils.dart';
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
  bool _initialShareProcessed = false;

  final List<Widget> _screens = const [
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

    // Delay so widget tree is fully ready before pushing routes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initShareHandler();
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
    // Cancel existing subscription before creating new one
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
    _shareSubscription?.cancel();
    _pageController.dispose();
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
    setState(() => _selectedIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _onPageChanged(int index) {
    setState(() => _selectedIndex = index);
  }

  // ── Badge count helpers ────────────────────────────────────────────────────

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

    return ValueListenableBuilder(
      valueListenable: Hive.box<UserModel>('userBox').listenable(),
      builder: (context, Box<UserModel> userBox, _) {
        final user = userBox.get('currentUser');

        return Scaffold(
          appBar: AppBar(
            toolbarHeight: 90,
            backgroundColor: appBarColor,
            elevation: 0,
            shadowColor: Colors.grey,
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
                      user?.name ?? 'User',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: Colors.pink,
                      ),
                    ),
                    Text(
                      user?.userName ?? 'User',
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
                icon: Hero(
                  tag: user?.uid ?? "profile_icon",
                  child: UserAvatar(url: user?.profilePic, radius: 25),
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
                    onTap: () => Future(
                      () => Navigator.pushNamed(
                        context,
                        CreateGroupScreen.routeName,
                      ),
                    ),
                  ),
                  PopupMenuItem(
                    child: const Text('Logout'),
                    onTap: () => Future(() async {
                      await FirebaseMessaging.instance.deleteToken();
                      Hive.box<UserModel>('userBox').delete('currentUser');
                      ref.read(authControllerProvider).logout(context);
                    }),
                  ),
                ],
              ),
            ],
          ),

          // ── PageView body ──────────────────────────────────────────────
          body: PageView(
            controller: _pageController,
            onPageChanged: _onPageChanged,
            children: _screens,
          ),

          // ── Bottom nav with badges ─────────────────────────────────────
          bottomNavigationBar: StreamBuilder<List<ChatContact>>(
            stream: ref.watch(chatControllerProvider).chatContacts(),
            builder: (context, chatSnapshot) {
              return StreamBuilder<List<Map<String, dynamic>>>(
                stream: ref
                    .watch(statusStreamProvider)
                    .when(
                      data: (data) => Stream.value(data),
                      loading: () => Stream.value(<Map<String, dynamic>>[]),
                      error: (_, __) => Stream.value(<Map<String, dynamic>>[]),
                    ),
                builder: (context, statusSnapshot) {
                  return StreamBuilder<List<GroupModel>>(
                    stream: ref.watch(groupControllerProvider).chatGroups(),
                    builder: (context, generalSnapshot) {
                      return StreamBuilder<List<GroupModel>>(
                        stream: ref
                            .watch(groupControllerProvider)
                            .getQueenPoojaStream(),
                        builder: (context, poojaSnapshot) {
                          return StreamBuilder<List<GroupModel>>(
                            stream: ref
                                .watch(groupControllerProvider)
                                .getQueenRashmikaStream(),
                            builder: (context, rashmikaSnapshot) {
                              final contacts = chatSnapshot.data ?? [];
                              final statuses = statusSnapshot.data ?? [];
                              final generalGroups = generalSnapshot.data ?? [];
                              final poojaGroups = poojaSnapshot.data ?? [];
                              final rashmikaGroups =
                                  rashmikaSnapshot.data ?? [];

                              final unreadChatsCount = _getUnreadChatsCount(
                                contacts,
                              );
                              final unseenStatusCount = _getUnseenStatusCount(
                                statuses,
                                currentUserUid,
                              );
                              final generalUnseenCount =
                                  _getUnseenCountForGeneralGroups(
                                    generalGroups,
                                  );
                              final poojaUnseenCount =
                                  _getUnseenCountForQueendom(
                                    poojaGroups,
                                    'Queen Pooja',
                                  );
                              final rashmikaUnseenCount =
                                  _getUnseenCountForQueendom(
                                    rashmikaGroups,
                                    'Queen Rashmika',
                                  );

                              final chatTabBadge =
                                  unreadChatsCount + unseenStatusCount;

                              return BottomNavigationBar(
                                currentIndex: _selectedIndex,
                                selectedItemColor: tabColor,
                                unselectedItemColor: Colors.grey,
                                onTap: _onItemTapped,
                                type: BottomNavigationBarType.fixed,
                                items: [
                                  const BottomNavigationBarItem(
                                    icon: Icon(Icons.home),
                                    label: '',
                                  ),
                                  BottomNavigationBarItem(
                                    icon: _buildBadgedIcon(
                                      icon: const Icon(Icons.chat_bubble),
                                      count: chatTabBadge,
                                    ),
                                    label: '',
                                  ),
                                  BottomNavigationBarItem(
                                    icon: _buildBadgedIcon(
                                      icon: const FaIcon(FontAwesomeIcons.crown),
                                      count: poojaUnseenCount,
                                    ),
                                    label: '',
                                  ),
                                  BottomNavigationBarItem(
                                    icon: _buildBadgedIcon(
                                      icon: const FaIcon(FontAwesomeIcons.crown),
                                      count: rashmikaUnseenCount,
                                    ),
                                    label: '',
                                  ),
                                  BottomNavigationBarItem(
                                    icon: _buildBadgedIcon(
                                      icon: const Icon(Icons.group),
                                      count: generalUnseenCount,
                                    ),
                                    label: '',
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
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
      },
    );
  }

  // ── Badged icon widget ─────────────────────────────────────────────────────

  Widget _buildBadgedIcon({required Widget icon, required int count}) {
    if (count == 0) return icon;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        Positioned(
          right: -6,
          top: -6,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
              border: Border.all(color: backgroundColor, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.red.withOpacity(0.5),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
            child: Center(
              child: Text(
                count > 99
                    ? '99+'
                    : count > 9
                    ? '9+'
                    : '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
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
