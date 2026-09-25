import 'dart:convert';
import 'dart:developer';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:worship_chat/common/utils/active_chat_notifier.dart';
import 'package:worship_chat/features/chat/screens/one_to_one_chat_screen.dart';
import 'package:worship_chat/features/group/screens/group_chat_screen.dart';
import 'package:worship_chat/models/group.dart';
import 'package:worship_chat/models/user_model.dart';

// ─── Background handler (top-level, required by FCM) ─────────────────────────
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  log("Handling a background message: ${message.messageId}");
}

// ─── Android notification channels ───────────────────────────────────────────
const AndroidNotificationChannel _highImportanceChannel =
    AndroidNotificationChannel(
  'high_importance_channel',
  'High Importance Notifications',
  description: 'This channel is used for important chat notifications.',
  importance: Importance.max,
  playSound: true,
  enableVibration: true,
);

const AndroidNotificationChannel _legacyChannel = AndroidNotificationChannel(
  'worship_chat_channel',
  'Worship Chat Messages',
  description: 'Chat message notifications for Worship Chat',
  importance: Importance.max,
  playSound: true,
  enableVibration: true,
);

/// Creates and registers notification channels with Android system NotificationManager early at boot
Future<void> createDefaultNotificationChannels() async {
  try {
    final localNotifications = FlutterLocalNotificationsPlugin();
    const androidSettings =
        AndroidInitializationSettings('@mipmap/launcher_icon');
    const darwinSettings = DarwinInitializationSettings();
    await localNotifications.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
      ),
    );

    final androidPlugin = localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_highImportanceChannel);
    await androidPlugin?.createNotificationChannel(_legacyChannel);
    log('✅ Default Android notification channels initialized');
  } catch (e) {
    log('⚠️ Error creating default notification channels: $e');
  }
}

// ─── Service ──────────────────────────────────────────────────────────────────
class FirebaseNotificationService {
  final GlobalKey<NavigatorState> navigatorKey;

  FirebaseNotificationService({required this.navigatorKey}) {
    _instance = this;
  }

  static FirebaseNotificationService? _instance;
  static Map<String, dynamic>? _pendingNotificationData;
  static bool isAppReady = false;
  static bool _initialNotificationHandled = false;

  /// Clears any pending cold-start notification so it is not processed twice.
  static void clearPendingNotification() {
    _pendingNotificationData = null;
    _initialNotificationHandled = true;
  }

  /// Called after RootGate finishes its splash animation and mounts HomeScreen.
  /// Dispatches any pending cold-start notification navigation cleanly on top of HomeScreen.
  static Future<void> checkAndDispatchPendingNotification() async {
    isAppReady = true;
    if (!_initialNotificationHandled && _pendingNotificationData != null) {
      final data = _pendingNotificationData!;
      _pendingNotificationData = null;
      _initialNotificationHandled = true;
      log('🚀 Dispatching pending notification after app ready: $data');
      await _instance?._navigateFromNotificationData(data);
    }
  }

  /// Retrieves cold-start notification data immediately at app launch (if any).
  static Future<Map<String, dynamic>?> getInitialNotificationData() async {
    if (_initialNotificationHandled) {
      return null;
    }
    if (_pendingNotificationData != null) {
      return _pendingNotificationData;
    }

    try {
      final launchDetails =
          await _staticLocalNotifications.getNotificationAppLaunchDetails();
      if (launchDetails?.didNotificationLaunchApp ?? false) {
        final response = launchDetails?.notificationResponse;
        if (response != null &&
            response.payload != null &&
            response.payload!.isNotEmpty) {
          final data = Map<String, dynamic>.from(
            jsonDecode(response.payload!) as Map,
          );
          _pendingNotificationData = data;
          return data;
        }
      }
    } catch (e) {
      log('Launch local notification check error: $e');
    }

    try {
      final initialMessage =
          await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null && initialMessage.data.isNotEmpty) {
        _pendingNotificationData = initialMessage.data;
        return initialMessage.data;
      }
    } catch (e) {
      log('Launch FCM message check error: $e');
    }

    return _pendingNotificationData;
  }

  /// Directly builds the target chat widget (OneToOneChatScreen or GroupChatScreen)
  /// from notification data payload, fetching Firestore metadata with a fast fallback.
  static Future<Widget?> buildChatScreenFromNotificationData(
    Map<String, dynamic> data,
  ) async {
    String? type = data['type'] as String?;
    if (type == null || type.isEmpty) {
      if (data.containsKey('groupId') || data.containsKey('groupName')) {
        type = 'group';
      } else if (data.containsKey('senderUid') ||
          data.containsKey('uid') ||
          data.containsKey('senderId')) {
        type = 'chat';
      }
    }

    log('Building chat screen from notification data — type: $type, data: $data');

    if (type == 'chat') {
      final senderUid = (data['senderUid'] ??
          data['uid'] ??
          data['senderId']) as String?;
      if (senderUid == null || senderUid.isEmpty) {
        log('senderUid missing in chat notification data');
        return null;
      }

      String name = data['name'] as String? ?? '';
      String? profilePic = data['profilePic'] as String?;
      String fcmToken = '';

      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(senderUid)
            .get()
            .timeout(const Duration(milliseconds: 1200));

        if (doc.exists && doc.data() != null) {
          final user = UserModel.fromMap(doc.data()!);
          if (user.name != null && user.name!.isNotEmpty) {
            name = user.name!;
          }
          if (user.profilePic != null && user.profilePic!.isNotEmpty) {
            profilePic = user.profilePic;
          }
          fcmToken = user.fcmToken ?? '';
        }
      } catch (e) {
        log('Note: fallback to notification payload for user info: $e');
      }

      if (name.isEmpty) {
        name = 'Chat';
      }

      return OneToOneChatScreen(
        name: name,
        uid: senderUid,
        fcmToken: fcmToken,
        profilePic: profilePic,
        unseenCount: false,
        chatBackgroundUrl: null,
      );
    } else if (type == 'group') {
      final groupId = (data['groupId'] ?? data['id']) as String?;
      if (groupId == null || groupId.isEmpty) {
        log('groupId missing in group notification data');
        return null;
      }

      GroupModel? group;
      try {
        final doc = await FirebaseFirestore.instance
            .collection('groups')
            .doc(groupId)
            .get()
            .timeout(const Duration(milliseconds: 1200));

        if (doc.exists && doc.data() != null) {
          group = GroupModel.fromMap(doc.data()!);
        }
      } catch (e) {
        log('Note: fallback to notification payload for group info: $e');
      }

      final groupName = data['groupName'] as String? ??
          data['name'] as String? ??
          group?.name ??
          'Group Chat';

      final resolvedGroup = group ??
          GroupModel(
            senderId: '',
            name: groupName,
            groupId: groupId,
            lastMessage: '',
            groupPic: '',
            membersUid: [],
            timeSent: DateTime.now(),
            fcmTokens: [],
            unseenMessages: {},
            chatBackgroundUrl: null,
            wish: null,
            queendom: null,
          );

      return GroupChatScreen(
        name: resolvedGroup.name,
        groupId: resolvedGroup.groupId,
        fcmToken: List<String>.from(resolvedGroup.fcmTokens),
        membersUid: List<String>.from(resolvedGroup.membersUid),
        chatBackgroundUrl: resolvedGroup.chatBackgroundUrl,
        groupPic: resolvedGroup.groupPic,
        wish: resolvedGroup.wish,
        queendom: resolvedGroup.queendom,
        color: null,
        type: resolvedGroup.queendom == 'Queen Pooja'
            ? 'queenPooja'
            : resolvedGroup.queendom == 'Queen Rashmika'
                ? 'queenRashmika'
                : 'group',
      );
    }

    return null;
  }

  static final FlutterLocalNotificationsPlugin _staticLocalNotifications =
      FlutterLocalNotificationsPlugin();

  /// Dismisses all notifications currently showing in the system notification shade/tray
  /// that correspond to the given [chatId] (either senderUid for 1-on-1 or groupId for groups).
  /// Matches on tag, deterministic ID, payload data, and optional [chatName].
  static Future<void> cancelNotificationsForChat(
    String chatId, {
    String? chatName,
  }) async {
    final cleanChatId = chatId.trim();
    if (cleanChatId.isEmpty) return;

    try {
      final plugin =
          _instance?._localNotifications ?? _staticLocalNotifications;
      final notifId = cleanChatId.hashCode.abs() % 2147483647;

      // 1. Cancel directly by deterministic ID with tag and without tag
      await plugin.cancel(notifId, tag: cleanChatId);
      await plugin.cancel(notifId);

      // 2. Query all currently active notifications in the Android notification shade
      final activeList = await plugin.getActiveNotifications();
      final cleanName = chatName?.trim().toLowerCase();

      for (final notif in activeList) {
        bool match = false;

        // Check tag
        if (notif.tag == cleanChatId) {
          match = true;
        }

        // Check notification ID
        if (!match && notif.id == notifId) {
          match = true;
        }

        // Check payload
        if (!match && notif.payload != null && notif.payload!.isNotEmpty) {
          try {
            final data = jsonDecode(notif.payload!);
            if (data is Map) {
              final sUid = (data['senderUid'] ??
                      data['uid'] ??
                      data['senderId'])
                  ?.toString();
              final gId = (data['groupId'] ?? data['id'])?.toString();
              if (sUid == cleanChatId || gId == cleanChatId) {
                match = true;
              }
            }
          } catch (_) {}
        }

        // Check title matching chatName (for notifications posted by FCM in background)
        if (!match && cleanName != null && cleanName.isNotEmpty) {
          final notifTitle = notif.title?.trim().toLowerCase();
          if (notifTitle != null &&
              (notifTitle == cleanName || notifTitle.contains(cleanName))) {
            match = true;
          }
        }

        if (match && notif.id != null) {
          log('🧹 Dismissed notification for chat $cleanChatId (id: ${notif.id}, tag: ${notif.tag}, title: ${notif.title})');
          await plugin.cancel(notif.id!, tag: notif.tag);
        }
      }
    } catch (e) {
      log('⚠️ Error in cancelNotificationsForChat: $e');
    }
  }

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  // ── Public entry point ─────────────────────────────────────────────────────
  Future<void> initialize() async {
    _instance = this;

    // Automatically dismiss notifications whenever any chat is entered
    ActiveChatNotifier.instance.onChatEntered = (chatId, chatName) {
      cancelNotificationsForChat(chatId, chatName: chatName);
    };

    // 1. Immediately listen for notification clicks when app is in BACKGROUND
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      log('onMessageOpenedApp tapped: ${message.data}');
      _navigateFromNotificationData(message.data);
    });

    // 2. Immediately listen for FOREGROUND messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // 3. Request permissions
    final settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    log('FCM permission: ${settings.authorizationStatus}');

    // 4. Create Android channels (registers with system NotificationManager)
    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_highImportanceChannel);
    await androidPlugin?.createNotificationChannel(_legacyChannel);

    // 5. Init local notifications with tap callback
    const androidSettings =
        AndroidInitializationSettings('@mipmap/launcher_icon');
    const darwinSettings = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onLocalNotificationTapped,
    );

    // 6. App was KILLED and launched by tapping a LOCAL notification
    if (!_initialNotificationHandled) {
      final launchDetails =
          await _localNotifications.getNotificationAppLaunchDetails();
      if (launchDetails?.didNotificationLaunchApp ?? false) {
        final response = launchDetails?.notificationResponse;
        if (response != null &&
            response.payload != null &&
            response.payload!.isNotEmpty) {
          log('App launched from local notification tap: ${response.payload}');
          _onLocalNotificationTapped(response);
        }
      }

      // 7. App was KILLED and user tapped the FCM notification
      final initialMessage = await _firebaseMessaging.getInitialMessage();
      if (initialMessage != null) {
        log('getInitialMessage: ${initialMessage.data}');
        _navigateFromNotificationData(initialMessage.data);
      }
    }
  }

  // ── Foreground: display a local notification ───────────────────────────────
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    log('Foreground message: ${message.messageId}');

    // Suppress notification if the user is currently viewing this exact chat!
    final senderUid = message.data['senderUid'] ??
        message.data['uid'] ??
        message.data['senderId'];
    final groupId = message.data['groupId'] ?? message.data['id'];
    final activeChatId = ActiveChatNotifier.instance.activeChatUid;

    if (activeChatId != null) {
      if ((senderUid != null && activeChatId == senderUid) ||
          (groupId != null && activeChatId == groupId)) {
        log('🚫 Suppressing foreground notification for currently opened chat: $activeChatId');
        return;
      }
    }

    // Support both notification block and data-only FCM messages
    final title = message.notification?.title ??
        message.data['title'] ??
        message.data['name'] ??
        'New Message';
    final body = message.notification?.body ??
        message.data['body'] ??
        message.data['text'] ??
        '';

    if (title.toString().trim().isEmpty && body.toString().trim().isEmpty) {
      return;
    }
    final chatId = (groupId ?? senderUid)?.toString().trim();
    final notifId = chatId != null && chatId.isNotEmpty
        ? (chatId.hashCode.abs() % 2147483647)
        : message.hashCode;

    final androidDetails = AndroidNotificationDetails(
      _highImportanceChannel.id,
      _highImportanceChannel.name,
      channelDescription: _highImportanceChannel.description,
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      icon: '@mipmap/launcher_icon',
      tag: chatId,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: const DarwinNotificationDetails(presentSound: true),
    );

    // Encode the entire FCM data map as JSON so the tap handler can read it
    final payloadJson = jsonEncode(message.data);

    await _localNotifications.show(
      notifId,
      title.toString(),
      body.toString(),
      details,
      payload: payloadJson,
    );
  }

  // ── Local notification tapped ──────────────────────────────────────────────
  void _onLocalNotificationTapped(NotificationResponse response) {
    log('Local notification tapped, payload: ${response.payload}');
    if (response.payload == null || response.payload!.isEmpty) return;
    try {
      final data = Map<String, dynamic>.from(
        jsonDecode(response.payload!) as Map,
      );
      _navigateFromNotificationData(data);
    } catch (e) {
      log('Error parsing notification payload: $e');
    }
  }

  // ── Helper: Wait for Navigator to be mounted and ready ─────────────────────
  Future<NavigatorState?> _waitForNavigator() async {
    for (int i = 0; i < 50; i++) {
      final state = navigatorKey.currentState;
      if (state != null && state.mounted) {
        return state;
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }
    return navigatorKey.currentState;
  }

  // ── Helper: Wait for user authentication to resolve on cold start ──────────
  Future<bool> _ensureAuthenticated() async {
    if (FirebaseAuth.instance.currentUser != null) return true;
    for (int i = 0; i < 30; i++) {
      if (FirebaseAuth.instance.currentUser != null) return true;
      await Future.delayed(const Duration(milliseconds: 100));
    }
    return FirebaseAuth.instance.currentUser != null;
  }

  // ── Core navigation dispatcher ─────────────────────────────────────────────
  Future<void> _navigateFromNotificationData(
    Map<String, dynamic> data,
  ) async {
    // If the app is still at the splash screen / RootGate, queue and wait until HomeScreen mounts
    if (!isAppReady) {
      log('⏳ App is still initializing (RootGate), queueing pending notification: $data');
      _pendingNotificationData = data;
      return;
    }

    String? type = data['type'] as String?;
    if (type == null || type.isEmpty) {
      if (data.containsKey('groupId') || data.containsKey('groupName')) {
        type = 'group';
      } else if (data.containsKey('senderUid') ||
          data.containsKey('uid') ||
          data.containsKey('senderId')) {
        type = 'chat';
      }
    }

    log('Navigating from notification — resolved type: $type, data: $data');

    if (type == 'chat') {
      await _navigateToOneToOneChat(data);
    } else if (type == 'group') {
      await _navigateToGroupChat(data);
    } else {
      log('Unknown or missing notification type: $type');
    }
  }

  // ── Navigate to a 1-to-1 chat screen ──────────────────────────────────────
  Future<void> _navigateToOneToOneChat(Map<String, dynamic> data) async {
    final isAuthed = await _ensureAuthenticated();
    if (!isAuthed) {
      log('Cannot navigate to 1-to-1 chat: user not authenticated');
      return;
    }

    final nav = await _waitForNavigator();
    if (nav == null) {
      log('Cannot navigate to 1-to-1 chat: NavigatorState unavailable');
      return;
    }

    final chatScreen = await buildChatScreenFromNotificationData(data);
    if (chatScreen == null) return;

    try {
      nav.push(
        MaterialPageRoute(
          builder: (_) => chatScreen,
        ),
      );
    } catch (e) {
      log('Error pushing 1-to-1 chat route: $e');
    }
  }

  // ── Navigate to a group chat screen ──────────────────────────────────────
  Future<void> _navigateToGroupChat(Map<String, dynamic> data) async {
    final isAuthed = await _ensureAuthenticated();
    if (!isAuthed) {
      log('Cannot navigate to group chat: user not authenticated');
      return;
    }

    final nav = await _waitForNavigator();
    if (nav == null) {
      log('Cannot navigate to group chat: NavigatorState unavailable');
      return;
    }

    final groupScreen = await buildChatScreenFromNotificationData(data);
    if (groupScreen == null) return;

    try {
      nav.push(
        MaterialPageRoute(
          builder: (_) => groupScreen,
        ),
      );
    } catch (e) {
      log('Error navigating to group chat: $e');
    }
  }
}

// ─── Standalone helpers (called from repositories) ────────────────────────────

/// Send a single-recipient FCM notification with an optional data payload.
/// The [data] map is forwarded as FCM's data field (all values must be strings).
Future<void> sendNotification(
  String token,
  String title,
  String body, {
  Map<String, String>? data,
}) async {
  try {
    final cleanToken = token.trim();
    if (cleanToken.isEmpty) {
      log("⚠️ sendNotification: token is empty, skipping");
      return;
    }

    final safeTitle = title.trim().isNotEmpty ? title.trim() : 'New Message';
    final safeBody = body.trim().isNotEmpty ? body.trim() : 'Tap to open';

    final preview = cleanToken.length > 20 ? cleanToken.substring(0, 20) : cleanToken;
    log("Sending single notification to: $preview...");

    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        sendTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ),
    );
    final tag = (data?['tag'] ?? data?['senderUid'] ?? data?['groupId'])?.toString().trim();

    final response = await dio.post(
      "https://worshipchatnotification.vercel.app/send-single",
      options: Options(headers: {'Content-Type': 'application/json'}),
      data: {
        'title': safeTitle,
        'body': safeBody,
        'token': cleanToken,
        if (tag != null && tag.isNotEmpty) 'tag': tag,
        if (data != null) 'data': data,
      },
    );

    if (response.statusCode == 200) {
      log('✅ Single notification sent successfully');
    } else {
      log('⚠️ Notification server returned status ${response.statusCode}: ${response.data}');
    }
  } on DioException catch (e) {
    log("❌ Dio error sending single notification: status=${e.response?.statusCode}, data=${e.response?.data}, message=${e.message}");
  } catch (e) {
    log("❌ Error sending single notification: $e");
  }
}

/// Send a multi-recipient FCM notification with an optional data payload.
Future<void> sendMultipleNotification(
  List<String> tokens,
  String title,
  String body, {
  Map<String, String>? data,
}) async {
  try {
    final uniqueTokens = tokens
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toSet()
        .toList();
    if (uniqueTokens.isEmpty) {
      log("⚠️ sendMultipleNotification: tokens list is empty, skipping request");
      return;
    }

    final safeTitle = title.trim().isNotEmpty ? title.trim() : 'New Message';
    final safeBody = body.trim().isNotEmpty ? body.trim() : 'Tap to open';

    log("Sending multiple notifications to ${uniqueTokens.length} tokens");
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        sendTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ),
    );
    final tag = (data?['tag'] ?? data?['groupId'] ?? data?['senderUid'])?.toString().trim();

    final response = await dio.post(
      "https://worshipchatnotification.vercel.app/send-multiple",
      options: Options(headers: {'Content-Type': 'application/json'}),
      data: {
        'title': safeTitle,
        'body': safeBody,
        'tokens': uniqueTokens,
        if (tag != null && tag.isNotEmpty) 'tag': tag,
        if (data != null) 'data': data,
      },
    );

    log('✅ Multiple notifications response (${response.statusCode}): ${response.data}');
  } on DioException catch (e) {
    log("❌ Dio error sending multiple notifications: status=${e.response?.statusCode}, data=${e.response?.data}, message=${e.message}");
  } catch (e) {
    log("❌ Error sending multiple notifications: $e");
  }
}
