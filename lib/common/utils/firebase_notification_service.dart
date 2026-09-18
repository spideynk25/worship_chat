import 'dart:convert';
import 'dart:developer';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:worship_chat/features/chat/screens/one_to_one_chat_screen.dart';
import 'package:worship_chat/features/group/screens/group_chat_screen.dart';
import 'package:worship_chat/models/group.dart';
import 'package:worship_chat/models/user_model.dart';

// ─── Background handler (top-level, required by FCM) ─────────────────────────
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  log("Handling a background message: ${message.messageId}");
}

// ─── Android notification channel ────────────────────────────────────────────
const AndroidNotificationChannel _channel = AndroidNotificationChannel(
  'worship_chat_channel',      // id
  'Worship Chat Messages',     // name
  description: 'Chat message notifications for Worship Chat',
  importance: Importance.max,
  playSound: true,
);

// ─── Service ──────────────────────────────────────────────────────────────────
class FirebaseNotificationService {
  final GlobalKey<NavigatorState> navigatorKey;

  FirebaseNotificationService({required this.navigatorKey});

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  // ── Public entry point ─────────────────────────────────────────────────────
  Future<void> initialize() async {
    // 1. Request permissions
    final settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    log('FCM permission: ${settings.authorizationStatus}');

    // 2. Create Android channel (no-op on iOS)
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    // 3. Init local notifications with tap callback
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onLocalNotificationTapped,
    );

    // 4. Register background message handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 5. Foreground messages → show a local notification
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // 6. App was BACKGROUNDED and user tapped the notification
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      log('onMessageOpenedApp: ${message.data}');
      _navigateFromNotificationData(message.data);
    });

    // 7. App was KILLED and user tapped the notification
    final initialMessage = await _firebaseMessaging.getInitialMessage();
    if (initialMessage != null) {
      log('getInitialMessage: ${initialMessage.data}');
      // Delay until first frame is fully rendered
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navigateFromNotificationData(initialMessage.data);
      });
    }
  }

  // ── Foreground: display a local notification ───────────────────────────────
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    log('Foreground message: ${message.messageId}');
    if (message.notification == null) return;

    final androidDetails = AndroidNotificationDetails(
      _channel.id,
      _channel.name,
      channelDescription: _channel.description,
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      icon: '@mipmap/ic_launcher',
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: const DarwinNotificationDetails(presentSound: true),
    );

    // Encode the entire FCM data map as JSON so the tap handler can read it
    final payloadJson = jsonEncode(message.data);

    await _localNotifications.show(
      message.hashCode,
      message.notification!.title,
      message.notification!.body,
      details,
      payload: payloadJson,
    );
  }

  // ── Local notification tapped (foreground) ────────────────────────────────
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

  // ── Core navigation dispatcher ─────────────────────────────────────────────
  Future<void> _navigateFromNotificationData(
    Map<String, dynamic> data,
  ) async {
    final type = data['type'] as String?;
    log('Navigating from notification — type: $type, data: $data');

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
    final senderUid = data['senderUid'] as String?;
    if (senderUid == null || senderUid.isEmpty) {
      log('senderUid missing in chat notification data');
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(senderUid)
          .get();

      if (!doc.exists || doc.data() == null) {
        log('Sender user not found: $senderUid');
        return;
      }

      final user = UserModel.fromMap(doc.data()!);

      navigatorKey.currentState?.pushNamed(
        OneToOneChatScreen.routeName,
        arguments: {
          'name': user.name ?? data['name'] ?? '',
          'uid': senderUid,
          'fcmToken': user.fcmToken ?? '',
          'profilePic': user.profilePic,
          'unseenCount': true,
          'chatBackgroundUrl': null,
        },
      );
    } catch (e) {
      log('Error navigating to 1-to-1 chat: $e');
    }
  }

  // ── Navigate to a group chat screen ──────────────────────────────────────
  Future<void> _navigateToGroupChat(Map<String, dynamic> data) async {
    final groupId = data['groupId'] as String?;
    if (groupId == null || groupId.isEmpty) {
      log('groupId missing in group notification data');
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId)
          .get();

      if (!doc.exists || doc.data() == null) {
        log('Group not found: $groupId');
        return;
      }

      final group = GroupModel.fromMap(doc.data()!);

      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => GroupChatScreen(
            name: group.name,
            groupId: group.groupId,
            fcmToken: List<String>.from(group.fcmTokens),
            membersUid: List<String>.from(group.membersUid),
            chatBackgroundUrl: group.chatBackgroundUrl,
            groupPic: group.groupPic,
            wish: group.wish,
            queendom: group.queendom,
            color: null,
            type: 'group',
          ),
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
    log("Sending single notification to: ${token.substring(0, 20)}...");
    final dio = Dio();
    final response = await dio.post(
      "https://worshipchatnotification.vercel.app/send-single",
      options: Options(headers: {'Content-Type': 'application/json'}),
      data: {
        'title': title,
        'body': body,
        'token': token,
        if (data != null) 'data': data,
      },
    );

    if (response.statusCode == 200) {
      log('✅ Single notification sent successfully');
    }
  } catch (e) {
    log("Error sending single notification: $e");
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
    log("Sending multiple notifications to ${tokens.length} tokens");
    final dio = Dio();
    final response = await dio.post(
      "https://worshipchatnotification.vercel.app/send-multiple",
      options: Options(headers: {'Content-Type': 'application/json'}),
      data: {
        'title': title,
        'body': body,
        'tokens': tokens,
        if (data != null) 'data': data,
      },
    );

    if (response.statusCode == 200) {
      log('✅ Multiple notifications sent successfully');
    }
  } catch (e) {
    log("Error sending multiple notifications: $e");
  }
}
