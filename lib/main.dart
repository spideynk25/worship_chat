import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/utils/fcm_token_manager.dart';
import 'package:worship_chat/common/utils/firebase_notification_service.dart';
import 'package:worship_chat/common/utils/media_cache_service.dart';
import 'package:worship_chat/common/widgets/error_screen.dart';
import 'package:worship_chat/features/auth/screens/login_screen.dart';
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

  await Firebase.initializeApp();

  // Initialize Android notification channels early at boot
  await createDefaultNotificationChannels();

  // Background FCM
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Permissions
  await FirebaseMessaging.instance.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  // Local cache & storage
  await MediaCacheService().init();

  await Hive.initFlutter();
  Hive.registerAdapter(UserModelAdapter());
  Hive.registerAdapter(OneToOneMessageModelAdapter());
  Hive.registerAdapter(GroupChatMessageModelAdapter());
  Hive.registerAdapter(GroupGalleryImageAdapter());
  await Hive.openBox<UserModel>('userBox');
  await Hive.openBox('messages');
  await Hive.openBox('contacts_cache');
  await Hive.openBox('groups_cache');

  await FCMTokenManager.initializeFCM();

  runApp(const ProviderScope(child: MyApp()));
}

/// ------------------------------
/// FCM BACKGROUND HANDLER
/// ------------------------------
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

/// ------------------------------
/// APP
/// ------------------------------
class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FirebaseNotificationService(navigatorKey: navigatorKey).initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Worship Chat',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: ThemeData.dark().copyWith(
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
            shape: RoundedRectangleBorder(
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
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: dividerColor),
          ),
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: tabColor),
          ),
        ),
        dividerColor: dividerColor,
        popupMenuTheme: const PopupMenuThemeData(
          color: Color(0xFF1C1C28),
          textStyle: TextStyle(color: textColor),
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: Color(0xFF1C1C28),
          contentTextStyle: TextStyle(color: textColor),
        ),
      ),
      onGenerateRoute: (settings) => generateRoute(settings),
      home: const RootGate(),
    );
  }
}

/// ------------------------------
/// ROOT AUTH GATE (CRITICAL FIX)
/// ------------------------------
/// Uses imperative Navigator.pushReplacement so we never get a blank frame
/// from a setState-triggered rebuild racing with the animation controller.
class RootGate extends StatefulWidget {
  const RootGate({super.key});

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  @override
  void initState() {
    super.initState();
    _resolveAndNavigate();
  }

  Future<void> _resolveAndNavigate() async {
    // Keep the splash visible for at least 800 ms so the animation is seen
    // and we don't get a jarring instant replacement.
    final minSplashFuture = Future.delayed(const Duration(milliseconds: 800));

    Widget destination;
    Widget? directChatScreen;

    try {
      User? user = FirebaseAuth.instance.currentUser;

      if (user != null) {
        // Reload is CRITICAL for Android reliability
        await user.reload();
        user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          try {
            await FCMTokenManager.refreshAndSaveFCMToken();
          } catch (e) {
            debugPrint('Note: initial token refresh error: $e');
          }
        }

        if (user != null && user.emailVerified) {
          // Pre-warm Hive user cache & check cold-start notification in parallel
          final prewarmFuture = Future.any([
            _prewarmUserCache(user.uid),
            Future.delayed(const Duration(seconds: 3)),
          ]);

          final notificationFuture =
              FirebaseNotificationService.getInitialNotificationData();

          await Future.wait([prewarmFuture, notificationFuture]);

          final notifData = await notificationFuture;
          if (notifData != null) {
            directChatScreen =
                await FirebaseNotificationService.buildChatScreenFromNotificationData(
              notifData,
            );
          }

          destination = const HomeScreen();
        } else {
          destination = LoginScreen();
        }
      } else {
        destination = const LandingScreen();
      }
    } catch (e) {
      destination = ErrorScreen(error: e.toString());
    }

    // Ensure minimum splash duration before navigating
    await minSplashFuture;

    if (!mounted) return;

    if (directChatScreen != null) {
      FirebaseNotificationService.clearPendingNotification();
      FirebaseNotificationService.isAppReady = true;

      // 1. Mount HomeScreen underneath with zero transition so back navigation returns to HomeScreen
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const HomeScreen(),
          transitionDuration: Duration.zero,
        ),
      );

      // 2. Mount the chat screen directly on top with smooth fade transition
      Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => directChatScreen!,
          transitionsBuilder: (_, animation, __, child) => FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          ),
          transitionDuration: const Duration(milliseconds: 300),
        ),
      );
    } else {
      FirebaseNotificationService.isAppReady = true;

      // Use pushReplacement + fade so the SplashScreen is cleanly replaced.
      // This avoids the blank-screen race that setState rebuilds can cause.
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => destination,
          transitionsBuilder: (_, animation, __, child) => FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          ),
          transitionDuration: const Duration(milliseconds: 400),
        ),
      );

      // If a notification was tapped right as the app finished booting, dispatch it
      WidgetsBinding.instance.addPostFrameCallback((_) {
        FirebaseNotificationService.checkAndDispatchPendingNotification();
      });
    }
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
    // Always show SplashScreen — navigation is handled imperatively above.
    return const SplashScreen();
  }
}
