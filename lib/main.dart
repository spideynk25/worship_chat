import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/utils/app_capabilities.dart';
import 'package:worship_chat/firebase_options.dart';
import 'package:worship_chat/common/utils/fcm_token_manager.dart';
import 'package:worship_chat/common/utils/firebase_notification_service.dart';
import 'package:worship_chat/common/utils/location_service.dart';
import 'package:worship_chat/common/utils/media_cache_service.dart';
import 'package:worship_chat/common/utils/wish_reminder_service.dart';
import 'package:worship_chat/features/auth/screens/login_screen.dart';
import 'package:worship_chat/features/group/services/roleplay_service.dart';
import 'package:worship_chat/features/landing/screens/landing_screen.dart';
import 'package:worship_chat/features/home/screens/home_screen.dart';
import 'package:worship_chat/models/group_chat_message_model.dart';
import 'package:worship_chat/models/group_gallery_image.dart';
import 'package:worship_chat/models/one_to_one_message_model.dart';
import 'package:worship_chat/models/user_model.dart';
import 'package:worship_chat/router.dart';
import 'package:worship_chat/splash_screen.dart';

/// ------------------------------
/// MAIN
/// ------------------------------
/// Global navigator key — used by FirebaseNotificationService to navigate
/// when a notification is tapped from background/killed state.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Graceful dark-themed error widget fallback to prevent red screens of death
  ErrorWidget.builder = (FlutterErrorDetails details) {
    debugPrint(
      '⚠️ UI Error caught by ErrorWidget.builder: ${details.exception}',
    );
    return Material(
      color: Colors.transparent,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1B2E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: Colors.amber,
                size: 18,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Content temporarily unavailable',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  };

  await AppCapabilities.initialize();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  try {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  } catch (e) {
    debugPrint('⚠️ Could not set Firestore persistence: $e');
  }

  if (AppCapabilities.current.notificationsEnabled) {
    await createDefaultNotificationChannels();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } else {
    // Revoke any token from an older tablet installation without changing
    // the account's phone token in Firestore.
    await FCMTokenManager.disableForGalleryDevice();
  }

  // Local cache & storage
  await MediaCacheService().init();

  await Hive.initFlutter('worship_chat');
  Hive.registerAdapter(UserModelAdapter());
  Hive.registerAdapter(OneToOneMessageModelAdapter());
  Hive.registerAdapter(GroupChatMessageModelAdapter());
  Hive.registerAdapter(GroupGalleryImageAdapter());
  await _safeOpenHiveBox<UserModel>('userBox');
  if (AppCapabilities.current.chatEnabled) {
    await _safeOpenHiveBox('messages');
    await _safeOpenHiveBox('contacts_cache');
    await _safeOpenHiveBox('roleplay_settings');
    await _safeOpenHiveBox('displayImage');
    await _safeOpenHiveBox('status_cache');
    unawaited(LocationService.instance.resumeActiveLiveLocationTracking());
    unawaited(RoleplayService.instance.restoreActiveSessions());
  }
  await _safeOpenHiveBox('groups_cache');

  if (AppCapabilities.current.notificationsEnabled) {
    unawaited(FCMTokenManager.initializeFCM());
    if (AppCapabilities.current.chatEnabled) {
      WishReminderService.instance.start();
    }
  }

  // Check if launched directly from a notification on cold start
  Widget? initialChatScreen;
  if (AppCapabilities.current.notificationsEnabled &&
      AppCapabilities.current.chatEnabled) {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && user.emailVerified) {
        final notifData =
            await FirebaseNotificationService.getInitialNotificationData();
        if (notifData != null) {
          initialChatScreen =
              await FirebaseNotificationService.buildChatScreenFromNotificationData(
                notifData,
              );
          if (initialChatScreen != null) {
            FirebaseNotificationService.clearPendingNotification();
            FirebaseNotificationService.isAppReady = true;
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error resolving initial notification in main: $e');
    }
  }

  runApp(ProviderScope(child: MyApp(initialChatScreen: initialChatScreen)));
}

/// Safely opens a Hive box, handling potential lock contention on desktop/mobile
Future<Box<T>?> _safeOpenHiveBox<T>(String boxName) async {
  try {
    return await Hive.openBox<T>(boxName);
  } catch (e) {
    debugPrint('⚠️ Initial attempt to open Hive box "$boxName" failed: $e');
    try {
      await Future.delayed(const Duration(milliseconds: 300));
      return await Hive.openBox<T>(boxName);
    } catch (retryError) {
      debugPrint('⚠️ Retry opening Hive box "$boxName" failed: $retryError');
      return null;
    }
  }
}

/// ------------------------------
/// FCM BACKGROUND HANDLER
/// ------------------------------
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppCapabilities.initialize(background: true);
  if (!AppCapabilities.current.notificationsEnabled) return;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (_) {}
  await FirebaseNotificationService.ensureStaticInitialized();
  await FirebaseNotificationService.ensureHiveInitialized();
  await FirebaseNotificationService.showNotificationFromRemoteMessage(message);
}

/// ------------------------------
/// APP
/// ------------------------------
class MyApp extends ConsumerStatefulWidget {
  final Widget? initialChatScreen;
  const MyApp({super.key, this.initialChatScreen});

  static ThemeData get theme => ThemeData.dark().copyWith(
    scaffoldBackgroundColor: backgroundColor,
    appBarTheme: const AppBarTheme(
      backgroundColor: appBarColor,
      foregroundColor: textColor,
      elevation: 0,
      titleTextStyle: TextStyle(
        color: textColor,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
      iconTheme: IconThemeData(color: textColor),
    ),
    colorScheme: const ColorScheme.dark(
      primary: tabColor,
      secondary: accentOrange,
      surface: mobileChatBoxColor,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: textColor,
      primaryContainer: Color(0xFF3D0B21),
      onPrimaryContainer: tabColor,
      secondaryContainer: Color(0xFF3D2010),
      onSecondaryContainer: accentOrange,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: appBarColor,
      selectedItemColor: tabColor,
      unselectedItemColor: greyColor,
      elevation: 0,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: tabColor,
      foregroundColor: Colors.white,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: tabColor,
        foregroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: tabColor),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      hintStyle: TextStyle(color: greyColor),
      labelStyle: TextStyle(color: greyColor),
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
      errorBorder: InputBorder.none,
      focusedErrorBorder: InputBorder.none,
    ),
    dividerColor: dividerColor,
    popupMenuTheme: const PopupMenuThemeData(
      color: Color(0xFF1C1C28),
      textStyle: TextStyle(color: textColor),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: Colors.transparent,
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      contentTextStyle: TextStyle(color: textColor),
    ),
  );

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (AppCapabilities.current.notificationsEnabled) {
      FirebaseNotificationService(navigatorKey: navigatorKey).initialize();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (AppCapabilities.current.notificationsEnabled &&
          AppCapabilities.current.chatEnabled) {
        WishReminderService.instance.checkReminders();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WishReminderService.instance.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Worship Chat',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: MyApp.theme,
      onGenerateRoute: (settings) => generateRoute(settings),
      home: RootGate(initialChatScreen: widget.initialChatScreen),
    );
  }
}

/// ------------------------------
/// ROOT AUTH GATE (CRITICAL FIX)
/// ------------------------------
/// Uses imperative Navigator.pushReplacement so we never get a blank frame
/// from a setState-triggered rebuild racing with the animation controller.
class RootGate extends StatefulWidget {
  final Widget? initialChatScreen;
  const RootGate({super.key, this.initialChatScreen});

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  bool _hasNavigated = false;
  Timer? _watchdogTimer;
  Widget? _destinationScreen;

  @override
  void initState() {
    super.initState();
    // Safety watchdog: Guarantees the splash screen NEVER hangs or freezes.
    // If initialization does not finish within 5s, force navigation immediately!
    _watchdogTimer = Timer(const Duration(milliseconds: 5000), () {
      if (!_hasNavigated && mounted) {
        debugPrint('⏱️ Splash watchdog triggered: forcing safe navigation');
        _navigateToDestination(_computeSafeFallbackDestination());
      }
    });

    _resolveAndNavigate();
  }

  @override
  void dispose() {
    _watchdogTimer?.cancel();
    super.dispose();
  }

  Widget _computeSafeFallbackDestination() {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final cachedUser = Hive.isBoxOpen('userBox')
          ? Hive.box<UserModel>('userBox').get('currentUser')
          : null;
      if ((user != null && user.emailVerified) || cachedUser != null) {
        return const HomeScreen();
      }
      return AppCapabilities.current.chatEnabled
          ? const LandingScreen()
          : LoginScreen();
    } catch (_) {
      return LoginScreen();
    }
  }

  void _navigateToDestination(
    Widget target, {
    Duration duration = const Duration(milliseconds: 350),
  }) {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;
    _watchdogTimer?.cancel();
    FirebaseNotificationService.isAppReady = true;

    // Fail-safe 1: Set destination screen for widget-tree fallback
    if (mounted) {
      setState(() {
        _destinationScreen = target;
      });
    }

    // Fail-safe 2: Perform smooth fade transition via navigatorKey or context
    try {
      final nav = navigatorKey.currentState ?? Navigator.of(context);
      nav.pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => target,
          transitionsBuilder: (_, animation, __, child) => FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          ),
          transitionDuration: duration,
        ),
      );
    } catch (e) {
      debugPrint('⚠️ Push replacement error in RootGate: $e');
    }

    if (AppCapabilities.current.notificationsEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        FirebaseNotificationService.checkAndDispatchPendingNotification();
      });
    }
  }

  Future<void> _resolveAndNavigate() async {
    // Keep the splash visible for at least 750 ms so the animation is seen
    // and we don't get a jarring instant replacement.
    final minSplashFuture = Future.delayed(const Duration(milliseconds: 750));

    Widget destination;
    Widget? directChatScreen = widget.initialChatScreen;

    try {
      User? user;
      try {
        user = FirebaseAuth.instance.currentUser;
      } catch (authError) {
        debugPrint(
          '⚠️ Note: FirebaseAuth.currentUser error (e.g. macOS keychain access): $authError',
        );
        user = null;
      }

      final cachedUser = Hive.isBoxOpen('userBox')
          ? Hive.box<UserModel>('userBox').get('currentUser')
          : null;

      final bool isLocallyAuthenticated =
          (user != null && user.emailVerified) || cachedUser != null;

      if (isLocallyAuthenticated) {
        if (user != null) {
          try {
            // Quick 500ms timeout for online token refresh; if offline, proceed immediately with cached session
            await user.reload().timeout(
              const Duration(milliseconds: 500),
              onTimeout: () {
                debugPrint(
                  '⚠️ user.reload timed out; continuing with cached session',
                );
              },
            );
            user = FirebaseAuth.instance.currentUser;
          } catch (reloadError) {
            debugPrint('⚠️ Note: FirebaseAuth reload error: $reloadError');
          }
        }

        if (user != null && AppCapabilities.current.notificationsEnabled) {
          try {
            unawaited(FCMTokenManager.refreshAndSaveFCMToken());
          } catch (e) {
            debugPrint('Note: initial token refresh error: $e');
          }
        }

        final uid = user?.uid ?? cachedUser?.uid;
        if (uid != null && uid.isNotEmpty) {
          unawaited(_prewarmUserCache(uid));
        }

        if (AppCapabilities.current.notificationsEnabled) {
          try {
            final notifData =
                await FirebaseNotificationService.getInitialNotificationData()
                    .timeout(
                      const Duration(milliseconds: 400),
                      onTimeout: () => null,
                    );
            if (notifData != null) {
              directChatScreen =
                  await FirebaseNotificationService.buildChatScreenFromNotificationData(
                    notifData,
                  ).timeout(
                    const Duration(milliseconds: 400),
                    onTimeout: () => null,
                  );
            }
          } catch (e) {
            debugPrint('⚠️ notification resolving error: $e');
          }
        }

        destination = const HomeScreen();
      } else {
        destination = AppCapabilities.current.chatEnabled
            ? const LandingScreen()
            : const LoginScreen();
      }
    } catch (e) {
      debugPrint('⚠️ _resolveAndNavigate error: $e');
      destination = _computeSafeFallbackDestination();
    }

    // Check if a pending notification was received during initialization
    if (directChatScreen == null &&
        AppCapabilities.current.notificationsEnabled) {
      try {
        final pendingData =
            FirebaseNotificationService.getAndClearPendingNotificationData();
        if (pendingData != null) {
          directChatScreen =
              await FirebaseNotificationService.buildChatScreenFromNotificationData(
                pendingData,
              ).timeout(
                const Duration(milliseconds: 1000),
                onTimeout: () => null,
              );
        }
      } catch (e) {
        debugPrint('⚠️ pending notification check error: $e');
      }
    }

    if (!mounted || _hasNavigated) return;

    if (directChatScreen != null) {
      FirebaseNotificationService.clearPendingNotification();
      _navigateToDestination(
        const HomeScreen(),
        duration: const Duration(milliseconds: 150),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          final nav = navigatorKey.currentState;
          nav?.push(
            PageRouteBuilder(
              pageBuilder: (_, __, ___) => directChatScreen!,
              transitionsBuilder: (_, animation, __, child) => FadeTransition(
                opacity: CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOut,
                ),
                child: child,
              ),
              transitionDuration: const Duration(milliseconds: 150),
            ),
          );
        } catch (e) {
          debugPrint(
            '⚠️ Error pushing direct chat screen on top of HomeScreen: $e',
          );
        }
      });
      return;
    }

    // Ensure minimum splash duration ONLY for normal launcher launch
    await minSplashFuture;

    _navigateToDestination(destination);
  }

  Future<void> _prewarmUserCache(String uid) async {
    final userBox = Hive.box<UserModel>('userBox');
    try {
      final userData = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      if (userData.data() != null) {
        final model = UserModel.fromMap(userData.data()!);
        await userBox.put('currentUser', model);
        debugPrint(
          '✅ Pre-warmed user cache from Firestore: ${model.name}, pic: ${model.profilePic}',
        );
      }
    } catch (e) {
      debugPrint('⚠️ Could not pre-warm user cache: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_destinationScreen != null) {
      return _destinationScreen!;
    }
    return const SplashScreen();
  }
}
