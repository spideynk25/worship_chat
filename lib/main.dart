import 'dart:async';
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
      ),
      onGenerateRoute: (settings) => generateRoute(settings),
      home: const RootGate(),
    );
  }
}

/// ------------------------------
/// ROOT AUTH GATE (CRITICAL FIX)
/// ------------------------------
class RootGate extends StatefulWidget {
  const RootGate({super.key});

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  User? _user;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _resolveAuth();
  }

  Future<void> _resolveAuth() async {
    try {
      User? user = FirebaseAuth.instance.currentUser;

      if (user != null) {
        // Reload is CRITICAL for Android reliability
        await user.reload();
        user = FirebaseAuth.instance.currentUser;
      }

      _user = user;
    } catch (e, st) {
      _error = e;
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SplashScreen();
    }

    if (_error != null) {
      return ErrorScreen(error: _error.toString());
    }

    if (_user == null) {
      return const LandingScreen();
    }

    if (!_user!.emailVerified) {
      return LoginScreen();
    }

    return const HomeScreen();
  }
}
