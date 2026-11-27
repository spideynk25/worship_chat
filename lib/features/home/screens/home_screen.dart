import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
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
import 'package:worship_chat/common/utils/app_capabilities.dart';
import 'package:worship_chat/common/utils/app_update_service.dart';
import 'package:worship_chat/common/utils/fcm_token_manager.dart';
import 'package:worship_chat/common/utils/firebase_notification_service.dart';
import 'package:worship_chat/common/utils/share_intent_service.dart';
import 'package:worship_chat/common/utils/utils.dart';
import 'package:worship_chat/common/widgets/skeleton_loader.dart';
import 'package:worship_chat/common/widgets/user_avatar.dart';
import 'package:worship_chat/features/auth/controller/auth_controller.dart';
import 'package:worship_chat/features/bookmark/screens/bookmark_screen.dart';
import 'package:worship_chat/features/chat/controller/chat_controller.dart';
import 'package:worship_chat/features/chat/widgets/all_user_screen.dart';
import 'package:worship_chat/features/dashboard/screens/dashboard_page.dart';
import 'package:worship_chat/features/group/controller/group_controller.dart';
import 'package:worship_chat/features/group/screens/create_group_screen.dart';
import 'package:worship_chat/features/group/screens/folder_gallery_screen.dart';
import 'package:worship_chat/features/group/screens/queen_pooja_queendom_screen.dart';
import 'package:worship_chat/features/group/screens/queen_rashmika_queendom_screen.dart';
import 'package:worship_chat/features/home/screens/photo_count_screen.dart';
import 'package:worship_chat/features/home/screens/profile_screen.dart';
import 'package:worship_chat/features/settings/screens/settings_screen.dart';
import 'package:worship_chat/features/home/widgets/dynamic_text_widget.dart';
import 'package:worship_chat/features/home/widgets/home_birthday_deities_app_bar_bottom.dart';
import 'package:worship_chat/features/dashboard/repositories/event_repository.dart';
import 'package:worship_chat/features/dashboard/widgets/today_birthdays_slideshow_widget.dart';
import 'package:worship_chat/features/share/screens/share_upload_screen.dart';
import 'package:worship_chat/features/status/controller/status_controller.dart';
import 'package:worship_chat/models/chat_contact.dart';
import 'package:worship_chat/models/event.dart';
import 'package:worship_chat/models/group.dart';
import 'package:worship_chat/models/user_model.dart';

class HomeScreen extends ConsumerStatefulWidget {
  final int? initialIndex;
  const HomeScreen({super.key, this.initialIndex});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  late int _selectedIndex;
  late final PageController _pageController;
  StreamSubscription? _shareSubscription;
  StreamSubscription<DocumentSnapshot>? _userSubscription;
  Stream<List<Event>>? _eventsStream;
  bool _initialShareProcessed = false;
  bool _isShareScreenOpen = false;

  static const List<Widget> _phoneScreens = [
    DashboardPage(),
    CombinedContactsScreen(isAllChats: false),
    QueenPoojaQueenScreen(),
    QueenRashmikaQueenScreen(),
  ];

  static const List<Widget> _galleryDeviceScreens = [
    DashboardPage(),
    QueenPoojaQueenScreen(),
    QueenRashmikaQueenScreen(),
  ];

  List<Widget> get _screens => AppCapabilities.current.chatEnabled
      ? _phoneScreens
      : _galleryDeviceScreens;

  String _safeGetCurrentUserUid() {
    return safeCurrentUserId() ?? '';
  }

  User? _safeGetCurrentUser() {
    try {
      return FirebaseAuth.instance.currentUser;
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final count = _screens.length;
    final defaultIndex = AppCapabilities.current.chatEnabled ? 1 : 0;
    _selectedIndex = (widget.initialIndex ?? defaultIndex).clamp(0, count - 1);
    _pageController = PageController(initialPage: _selectedIndex);
    _eventsStream = ref.read(eventRepositoryProvider).eventsStream();

    if (AppCapabilities.current.chatEnabled) {
      final uid = _safeGetCurrentUserUid();
      if (uid.isNotEmpty) {
        try {
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
        } catch (_) {}
      }
    }

    // Delay so widget tree is fully ready before pushing routes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (AppCapabilities.current.chatEnabled) {
        _initShareHandler();
      }
      if (AppCapabilities.current.notificationsEnabled) {
        FCMTokenManager.refreshAndSaveFCMToken();
      }
      if (AppCapabilities.current.chatEnabled) {
        FirebaseNotificationService.syncPendingBackgroundRepliesToHive();
        try {
          ref.read(authControllerProvider).getUsetData();
          ref.read(authControllerProvider).setUserState(true);
        } catch (_) {}
      }
      if (mounted) {
        AppUpdateService.instance.setNativeUpdateTapHandler(() {
          if (mounted) {
            AppUpdateService.instance.openAvailableUpdateDialog(context);
          }
        });
        FirebaseNotificationService.pendingUpdateNotificationNotifier
            .addListener(_onPendingUpdateNotification);
        _onPendingUpdateNotification();
        AppUpdateService.instance.consumePendingNativeUpdateLaunch().then((launched) {
          if (launched && mounted) {
            AppUpdateService.instance.openAvailableUpdateDialog(context);
          } else if (mounted) {
            AppUpdateService.instance.checkForUpdateIfAvailable(context);
          }
        });
      }
    });
  }

  void _onPendingUpdateNotification() {
    final pending =
        FirebaseNotificationService.pendingUpdateNotificationNotifier.value;
    if (pending == null || !mounted) return;
    FirebaseNotificationService.pendingUpdateNotificationNotifier.value = null;
    AppUpdateService.instance.openAvailableUpdateDialog(context);
  }

  Future<void> _initShareHandler() async {
    final handler = ShareHandlerPlatform.instance;

    // ── Handle initial share (app launched via share) ─────────────────
    if (!_initialShareProcessed) {
      _initialShareProcessed = true;
      try {
        final initial = await handler.getInitialSharedMedia();
        if (initial != null && mounted) {
          final payload = extractSharedPayload(initial);
          if (payload.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _openShareUpload(payload);
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
      final payload = extractSharedPayload(media);
      if (payload.isNotEmpty && mounted) {
        _openShareUpload(payload);
      }
    });
  }

  void _openShareUpload(SharedPayload payload) {
    if (_isShareScreenOpen || !mounted) return;
    _isShareScreenOpen = true;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ShareUploadScreen(payload: payload)),
    ).then((_) {
      _isShareScreenOpen = false;
    });
  }

  @override
  void dispose() {
    FirebaseNotificationService.pendingUpdateNotificationNotifier
        .removeListener(_onPendingUpdateNotification);
    AppUpdateService.instance.setNativeUpdateTapHandler(null);
    if (AppCapabilities.current.chatEnabled) {
      try {
        ref.read(authControllerProvider).setUserState(false);
      } catch (_) {}
    }
    _pageController.dispose();
    _shareSubscription?.cancel();
    _userSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      AppUpdateService.instance.consumePendingNativeUpdateLaunch().then((launched) {
        if (launched && mounted) {
          AppUpdateService.instance.openAvailableUpdateDialog(context);
        } else if (mounted) {
          AppUpdateService.instance.checkForUpdateOnResume(context);
        }
      });
    }
    if (!AppCapabilities.current.chatEnabled) return;
    switch (state) {
      case AppLifecycleState.resumed:
        ref.read(authControllerProvider).setUserState(true);
        FirebaseNotificationService.syncPendingBackgroundRepliesToHive();
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
    setState(() {
      _selectedIndex = index;
    });
    if (_pageController.hasClients) {
      _pageController.jumpToPage(index);
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
    final currentUserUid = _safeGetCurrentUserUid();
    final isWide = MediaQuery.of(context).size.width >= 720;
    final isChatEnabled = AppCapabilities.current.chatEnabled;
    final screens = _screens;

    return StreamBuilder<List<Event>>(
      stream: _eventsStream ?? ref.watch(eventRepositoryProvider).eventsStream(),
      builder: (context, eventSnapshot) {
        final allEvents = eventSnapshot.data ?? const [];
        final now = DateTime.now();
        final todayBirthdays = allEvents
            .where((e) =>
                TodayBirthdaysSlideshowWidget.isToday(e, now) &&
                TodayBirthdaysSlideshowWidget.isBirthday(e))
            .toList();
        const headerHeight = 92.0;
        return Scaffold(
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(headerHeight),
            child: Hive.isBoxOpen('userBox')
                ? ValueListenableBuilder<Box<UserModel>>(
                    valueListenable: Hive.box<UserModel>('userBox').listenable(),
                    builder: (context, Box<UserModel> userBox, _) {
                      return _buildAppBar(
                        userBox.get('currentUser'),
                        currentUserUid,
                        isChatEnabled,
                        todayBirthdays: todayBirthdays,
                      );
                    },
                  )
                : _buildAppBar(
                    null,
                    currentUserUid,
                    isChatEnabled,
                    todayBirthdays: todayBirthdays,
                  ),
          ),
          body: isWide
              ? Row(
                  children: [
                    _HomeScreenNavHost(
                      selectedIndex: _selectedIndex,
                      onItemTapped: _onItemTapped,
                      isWide: true,
                    ),
                    VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                    Expanded(
                      child: PageView.builder(
                        controller: _pageController,
                        onPageChanged: _onPageChanged,
                        physics: AppCapabilities.current.isDesktop
                            ? const NeverScrollableScrollPhysics()
                            : const BouncingScrollPhysics(),
                        itemCount: screens.length,
                        itemBuilder: (context, index) {
                          return _KeepAlivePage(child: screens[index]);
                        },
                      ),
                    ),
                  ],
                )
              : PageView.builder(
                  controller: _pageController,
                  onPageChanged: _onPageChanged,
                  physics: const BouncingScrollPhysics(),
                  itemCount: screens.length,
                  itemBuilder: (context, index) {
                    return _KeepAlivePage(child: screens[index]);
                  },
                ),
          bottomNavigationBar: isWide
              ? null
              : _HomeScreenNavHost(
                  selectedIndex: _selectedIndex,
                  onItemTapped: _onItemTapped,
                  isWide: false,
                ),
          floatingActionButton: (isChatEnabled && _selectedIndex == 1)
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

  Widget _buildDeityBirthdayStrip(
    BuildContext context,
    List<Event> todayBirthdays,
  ) {
    final hasMany = todayBirthdays.length > 3;

    return SizedBox(
      height: 53,
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              clipBehavior: Clip.none,
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < todayBirthdays.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: AnimatedBirthdayDeityAvatar(
                        celebrant: todayBirthdays[i],
                        radius: 23,
                        phaseOffset: i * 0.23,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          HomeBirthdayDeitiesAppBarBottom.openSlideshow(
                            context,
                            todayBirthdays[i],
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (hasMany) ...[
            const SizedBox(width: 4),
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                HapticFeedback.selectionClick();
                HomeBirthdayDeitiesAppBarBottom.showAllCelebrantsSheet(
                  context,
                  todayBirthdays,
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.cake_outlined,
                      size: 13,
                      color: Color(0xFFD2B46E),
                    ),
                    const SizedBox(width: 2.5),
                    Text(
                      '${todayBirthdays.length}',
                      style: const TextStyle(
                        color: Color(0xFFE7D6AD),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 15,
                      color: Color(0xFFD2B46E),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
    UserModel? user,
    String currentUserUid,
    bool isChatEnabled, {
    List<Event> todayBirthdays = const [],
  }) {
    final authUser = _safeGetCurrentUser();

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

    final birthdayWishes = <String>[];
    if (todayBirthdays.isNotEmpty) {
      final seenNames = <String>{};
      for (final event in todayBirthdays) {
        final name = TodayBirthdaysSlideshowWidget.extractCelebrantName(
          event.title,
          connectedGroupName: event.connectedGroupName,
        );
        if (name.isNotEmpty && seenNames.add(name.toLowerCase())) {
          birthdayWishes.add('Happy Birthday $name');
        }
      }
    }

    const headerHeight = 92.0;

    return AppBar(
      automaticallyImplyLeading: false,
      centerTitle: false,
      titleSpacing: 16,
      toolbarHeight: headerHeight,
      backgroundColor: appBarColor,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: todayBirthdays.isNotEmpty
                    ? _buildDeityBirthdayStrip(context, todayBirthdays)
                    : Text(
                        isChatEnabled ? 'Worship Chat' : 'Worship Gallery',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFF6F4FC),
                          fontSize: 20.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.4,
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              if (!isChatEnabled)
                IconButton(
                  tooltip: 'Bookmarks',
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.only(right: 4),
                  constraints: const BoxConstraints(
                    minWidth: 34,
                    minHeight: 34,
                  ),
                  icon: const Icon(
                    Icons.bookmark_outline_rounded,
                    color: Colors.white70,
                    size: 20,
                  ),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const BookmarkScreen()),
                  ),
                ),
              _buildProfileMenuButton(
                displayName: displayName,
                displayUserName: displayUserName,
                displayPic: displayPic,
                user: user,
                currentUserUid: currentUserUid,
                isChatEnabled: isChatEnabled,
              ),
            ],
          ),
          const SizedBox(height: 2),
          Align(
            alignment: Alignment.centerLeft,
            child: ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (bounds) => const LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Color(0xFFFF7EB3),
                  Color(0xFFFFB26B),
                  Color(0xFFFFDC88),
                ],
              ).createShader(
                Rect.fromLTWH(
                  0,
                  0,
                  bounds.width > 0 ? bounds.width : 1,
                  bounds.height > 0 ? bounds.height : 1,
                ),
              ),
              child: DynamicTextWidget(
                maxLines: 1,
                overrideTexts: birthdayWishes,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileMenuButton({
    required String displayName,
    required String displayUserName,
    required String? displayPic,
    required UserModel? user,
    required String currentUserUid,
    required bool isChatEnabled,
  }) {
    return PopupMenuButton<String>(
      position: PopupMenuPosition.under,
      padding: EdgeInsets.zero,
      elevation: 16,
      shadowColor: Colors.black.withValues(alpha: 0.7),
      color: const Color(0xFF161426),
      surfaceTintColor: Colors.transparent,
      offset: const Offset(0, 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: Colors.white.withValues(alpha: 0.12),
          width: 1.0,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 108),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    color: Color(0xFFFF82B2),
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 1.5),
                ShimmerEffect(
                  baseColor: const Color(0xFFD2B46E),
                  highlightColor: const Color(0xFFF7EBD0),
                  duration: const Duration(seconds: 10),
                  activeFraction: 0.14,
                  child: Text(
                    displayUserName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                      fontSize: 11,
                      letterSpacing: 0.2,
                      height: 1.15,
                      shadows: [
                        Shadow(
                          color: Color(0x33D2B46E),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 9),
          ValueListenableBuilder<UpdateCheckOutcome?>(
            valueListenable:
                AppUpdateService.instance.availableOutcomeNotifier,
            builder: (context, pendingUpdate, child) {
              final hasUpdate =
                  pendingUpdate?.status == UpdateCheckStatus.updateAvailable &&
                  pendingUpdate?.updateInfo != null;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  child!,
                  if (hasUpdate)
                    Positioned(
                      top: -2,
                      right: -2,
                      child: Container(
                        constraints: const BoxConstraints(
                          minWidth: 18,
                          minHeight: 18,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [tabColor, accentOrange],
                          ),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF0F0E17),
                            width: 1.8,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: tabColor.withValues(alpha: 0.65),
                              blurRadius: 6,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: const Text(
                          '1',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            height: 1.0,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
            child: Hero(
              tag: user?.uid ??
                  (currentUserUid.isNotEmpty
                      ? currentUserUid
                      : 'profile_icon'),
              child: UserAvatar(url: displayPic, radius: 25),
            ),
          ),
        ],
      ),
      itemBuilder: (context) {
            final pendingUpdate =
                AppUpdateService.instance.availableOutcomeNotifier.value;
            final updateInfo =
                pendingUpdate?.status == UpdateCheckStatus.updateAvailable
                    ? pendingUpdate?.updateInfo
                    : null;

            return [
              if (updateInfo != null) ...[
                _buildMenuActionItem(
                  icon: Icons.system_update_rounded,
                  color: const Color(0xFF00E676),
                  title: 'Update',
                  textColor: const Color(0xFF69F0AE),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E676).withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFF00E676).withValues(alpha: 0.45),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      'v${updateInfo.latestVersionName}',
                      style: const TextStyle(
                        color: Color(0xFF69F0AE),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  onTap: () => Future.microtask(() {
                    if (mounted) {
                      AppUpdateService.instance.openAvailableUpdateDialog(
                        this.context,
                      );
                    }
                  }),
                ),
                _buildMenuDivider(),
              ],
            _buildMenuActionItem(
              icon: Icons.person_rounded,
              color: const Color(0xFF8B5CF6),
              title: 'Profile',
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
            if (isChatEnabled)
              _buildMenuActionItem(
                icon: Icons.group_add_rounded,
                color: const Color(0xFF00E676),
                title: 'Create Group',
                onTap: () => Future.microtask(() {
                  if (mounted) {
                    Navigator.pushNamed(
                      this.context,
                      CreateGroupScreen.routeName,
                    );
                  }
                }),
              ),
            _buildMenuActionItem(
              icon: Icons.bookmark_rounded,
              color: const Color(0xFFFFD700),
              title: 'Bookmarks',
              onTap: () => Future.microtask(() {
                if (mounted) {
                  Navigator.push(
                    this.context,
                    MaterialPageRoute(builder: (_) => const BookmarkScreen()),
                  );
                }
              }),
            ),
            _buildMenuActionItem(
              icon: Icons.folder_open_rounded,
              color: const Color(0xFF64B5F6),
              title: 'Folder',
              onTap: () => Future.microtask(() {
                if (mounted) {
                  FolderGalleryScreen.showPickerOptions(this.context);
                }
              }),
            ),
            _buildMenuActionItem(
              icon: Icons.collections_rounded,
              color: const Color(0xFFFFD700),
              title: 'Photo Counts',
              onTap: () => Future.microtask(() {
                if (mounted) {
                  Navigator.push(
                    this.context,
                    MaterialPageRoute(
                      builder: (_) => const PhotoCountScreen(),
                    ),
                  );
                }
              }),
            ),
            _buildMenuActionItem(
              icon: Icons.settings_rounded,
              color: const Color(0xFF00D2D3),
              title: 'Settings',
              onTap: () => Future.microtask(() {
                if (mounted) {
                  Navigator.push(
                    this.context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                }
              }),
            ),
            _buildMenuDivider(),
            _buildMenuActionItem(
              icon: Icons.logout_rounded,
              color: const Color(0xFFFF5252),
              title: 'Logout',
              textColor: const Color(0xFFFF6B6B),
              onTap: () => Future.microtask(() async {
                if (AppCapabilities.current.notificationsEnabled) {
                  try {
                    await FirebaseMessaging.instance.deleteToken();
                  } catch (_) {}
                }
                if (Hive.isBoxOpen('userBox')) {
                  await Hive.box<UserModel>('userBox').delete('currentUser');
                }
                if (mounted) {
                  try {
                    ref.read(authControllerProvider).logout(this.context);
                  } catch (_) {}
                }
              }),
            ),
            ];
          },
    );
  }

  PopupMenuItem<String> _buildMenuActionItem({
    required IconData icon,
    required Color color,
    required String title,
    Color? textColor,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    return PopupMenuItem<String>(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: color.withValues(alpha: 0.35),
                width: 0.8,
              ),
            ),
            child: Icon(icon, size: 15, color: color),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: textColor ?? Colors.white,
                letterSpacing: 0.2,
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing,
          ],
        ],
      ),
    );
  }

  PopupMenuEntry<String> _buildMenuDivider() {
    return PopupMenuItem<String>(
      enabled: false,
      height: 8,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Divider(
        color: Colors.white.withValues(alpha: 0.10),
        height: 1,
        thickness: 0.8,
      ),
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
// Navigation Host Widget (Adaptive: Side Navigation Rail on wide, Bottom Bar on compact)
// ─────────────────────────────────────────────────────────────────────────────

class _HomeScreenNavHost extends ConsumerStatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemTapped;
  final bool isWide;

  const _HomeScreenNavHost({
    required this.selectedIndex,
    required this.onItemTapped,
    required this.isWide,
  });

  @override
  ConsumerState<_HomeScreenNavHost> createState() => _HomeScreenNavHostState();
}

class _HomeScreenNavHostState extends ConsumerState<_HomeScreenNavHost> {
  Stream<List<ChatContact>>? _chatContactsStream;
  Stream<List<GroupModel>>? _poojaGroupsStream;
  Stream<List<GroupModel>>? _rashmikaGroupsStream;

  @override
  void initState() {
    super.initState();
    if (AppCapabilities.current.chatEnabled) {
      _chatContactsStream = ref.read(chatControllerProvider).chatContacts();
      _poojaGroupsStream = ref.read(groupControllerProvider).getQueenPoojaStream();
      _rashmikaGroupsStream =
          ref.read(groupControllerProvider).getQueenRashmikaStream();
    }
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

  @override
  Widget build(BuildContext context) {
    if (!AppCapabilities.current.chatEnabled) {
      final navItems = [
        _NavBarItemConfig(
          iconBuilder: (isSelected) => Icon(
            Icons.grid_view_rounded,
            size: 26,
            color: isSelected ? tabColor : Colors.white.withValues(alpha: 0.55),
          ),
          label: 'Home',
          badgeCount: 0,
        ),
        _NavBarItemConfig(
          iconBuilder: (isSelected) => _buildQueendomNavIcon(
            isSelected: isSelected,
            activeAsset: 'assets/images/queen_pooja_nav_active.jpg',
            inactiveAsset: 'assets/images/queen_pooja_nav_inactive.jpg',
          ),
          label: 'Pooja',
          badgeCount: 0,
        ),
        _NavBarItemConfig(
          iconBuilder: (isSelected) => _buildQueendomNavIcon(
            isSelected: isSelected,
            activeAsset: 'assets/images/queen_rashmika_nav_active.jpg',
            inactiveAsset: 'assets/images/queen_rashmika_nav_inactive.jpg',
          ),
          label: 'Rashmika',
          badgeCount: 0,
        ),
      ];

      return widget.isWide
          ? _HomeScreenSideNavRail(
              selectedIndex: widget.selectedIndex,
              onItemTapped: widget.onItemTapped,
              navItems: navItems,
            )
          : _buildModernBottomNavBar(navItems: navItems);
    }

    final currentUserUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final statuses = ref.watch(statusStreamProvider).valueOrNull ?? const [];

    return StreamBuilder<List<ChatContact>>(
      stream: _chatContactsStream ?? Stream.value(const []),
      builder: (context, chatSnapshot) {
        return StreamBuilder<List<GroupModel>>(
          stream: _poojaGroupsStream ?? const Stream.empty(),
          builder: (context, poojaSnapshot) {
            return StreamBuilder<List<GroupModel>>(
              stream: _rashmikaGroupsStream ?? const Stream.empty(),
              builder: (context, rashmikaSnapshot) {
                final contacts = chatSnapshot.data ?? const [];
                final poojaGroups = poojaSnapshot.data ?? const [];
                final rashmikaGroups = rashmikaSnapshot.data ?? const [];

                final unreadChatsCount = _getUnreadChatsCount(contacts);
                final unseenStatusCount =
                    _getUnseenStatusCount(statuses, currentUserUid);
                final poojaUnseenCount =
                    _getUnseenCountForQueendom(poojaGroups, 'Queen Pooja');
                final rashmikaUnseenCount =
                    _getUnseenCountForQueendom(rashmikaGroups, 'Queen Rashmika');

                final chatTabBadge = unreadChatsCount + unseenStatusCount;

                final navItems = [
                  _NavBarItemConfig(
                    iconBuilder: (isSelected) => Icon(
                      Icons.grid_view_rounded,
                      size: 26,
                      color: isSelected
                          ? tabColor
                          : Colors.white.withValues(alpha: 0.55),
                    ),
                    label: 'Home',
                    badgeCount: 0,
                  ),
                  _NavBarItemConfig(
                    iconBuilder: (isSelected) => Icon(
                      isSelected
                          ? Icons.chat_bubble_rounded
                          : Icons.chat_bubble_outline_rounded,
                      size: 26,
                      color: isSelected
                          ? tabColor
                          : Colors.white.withValues(alpha: 0.55),
                    ),
                    label: 'Chats',
                    badgeCount: chatTabBadge,
                  ),
                  _NavBarItemConfig(
                    iconBuilder: (isSelected) => _buildQueendomNavIcon(
                      isSelected: isSelected,
                      activeAsset: 'assets/images/queen_pooja_nav_active.jpg',
                      inactiveAsset: 'assets/images/queen_pooja_nav_inactive.jpg',
                    ),
                    label: 'Pooja',
                    badgeCount: poojaUnseenCount,
                  ),
                  _NavBarItemConfig(
                    iconBuilder: (isSelected) => _buildQueendomNavIcon(
                      isSelected: isSelected,
                      activeAsset: 'assets/images/queen_rashmika_nav_active.jpg',
                      inactiveAsset: 'assets/images/queen_rashmika_nav_inactive.jpg',
                    ),
                    label: 'Rashmika',
                    badgeCount: rashmikaUnseenCount,
                  ),
                ];

                return widget.isWide
                    ? _HomeScreenSideNavRail(
                        selectedIndex: widget.selectedIndex,
                        onItemTapped: widget.onItemTapped,
                        navItems: navItems,
                      )
                    : _buildModernBottomNavBar(navItems: navItems);
              },
            );
          },
        );
      },
    );
  }

  Widget _buildModernBottomNavBar({required List<_NavBarItemConfig> navItems}) {
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
        child: SizedBox(
          height: 60,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
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
                  child: Semantics(
                    label: item.label,
                    button: true,
                    selected: isSelected,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeInOutCubic,
                      height: 44,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                      ),
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
                              borderRadius: BorderRadius.circular(18),
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
                          : BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              color: Colors.transparent,
                            ),
                      child: _buildNavIcon(item: item, isSelected: isSelected),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }

  static Widget _buildQueendomNavIcon({
    required bool isSelected,
    required String activeAsset,
    required String inactiveAsset,
  }) {
    final asset = isSelected ? activeAsset : inactiveAsset;
    const size = 34.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isSelected ? tabColor : Colors.white.withValues(alpha: 0.55),
          width: isSelected ? 2.0 : 1.4,
        ),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: tabColor.withValues(alpha: 0.5),
                  blurRadius: 8,
                  spreadRadius: 1.5,
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
      ),
      child: ClipOval(
        child: Opacity(
          opacity: isSelected ? 1.0 : 0.88,
          child: Image.asset(
            asset,
            width: size,
            height: size,
            fit: BoxFit.cover,
            alignment: const Alignment(0, -0.35),
            filterQuality: FilterQuality.medium,
          ),
        ),
      ),
    );
  }

  static Widget _buildNavIcon({
    required _NavBarItemConfig item,
    required bool isSelected,
  }) {
    final iconWidget = item.iconBuilder(isSelected);

    if (item.badgeCount <= 0) {
      return iconWidget;
    }

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        iconWidget,
        Positioned(
          right: -3,
          bottom: -2,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 3.5, vertical: 0.5),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [tabColor, accentOrange],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF14131B), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: tabColor.withValues(alpha: 0.45),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            constraints: const BoxConstraints(minWidth: 13, minHeight: 13),
            child: Center(
              child: Text(
                item.badgeCount > 99
                    ? '99+'
                    : item.badgeCount > 9
                        ? '9+'
                        : '${item.badgeCount}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8.0,
                  fontWeight: FontWeight.w800,
                  height: 1.0,
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

// ─────────────────────────────────────────────────────────────────────────────
// Royal Side Navigation Rail (Desktop & Wide Tablet Screens)
// ─────────────────────────────────────────────────────────────────────────────

class _HomeScreenSideNavRail extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemTapped;
  final List<_NavBarItemConfig> navItems;

  const _HomeScreenSideNavRail({
    required this.selectedIndex,
    required this.onItemTapped,
    required this.navItems,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      decoration: BoxDecoration(
        color: const Color(0xFF14131B),
        border: Border(
          right: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1.0,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(4, 0),
          ),
        ],
      ),
      child: SafeArea(
        right: false,
        child: Column(
          children: [
            const SizedBox(height: 12),
            // Royal Crest badge at top of rail
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [tabColor, accentOrange],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: tabColor.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Center(
                child: FaIcon(
                  FontAwesomeIcons.crown,
                  size: 20,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.separated(
                itemCount: navItems.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                itemBuilder: (context, index) {
                  final item = navItems[index];
                  final isSelected = selectedIndex == index;

                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      onItemTapped(index);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeInOutCubic,
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 4,
                      ),
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
                          : BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              color: Colors.transparent,
                            ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildRailNavIcon(item: item, isSelected: isSelected),
                          const SizedBox(height: 5),
                          Text(
                            item.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isSelected
                                  ? tabColor
                                  : Colors.white.withValues(alpha: 0.6),
                              fontSize: 11,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _buildRailNavIcon({
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
          right: -3,
          bottom: -2,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 3.5, vertical: 0.5),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [tabColor, accentOrange],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF14131B), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: tabColor.withValues(alpha: 0.45),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            constraints: const BoxConstraints(minWidth: 13, minHeight: 13),
            child: Center(
              child: Text(
                item.badgeCount > 99
                    ? '99+'
                    : item.badgeCount > 9
                        ? '9+'
                        : '${item.badgeCount}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8.0,
                  fontWeight: FontWeight.w800,
                  height: 1.0,
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
