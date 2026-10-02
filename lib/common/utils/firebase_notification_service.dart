import 'dart:convert';
import 'dart:developer';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:worship_chat/common/utils/active_chat_notifier.dart';
import 'package:worship_chat/common/utils/fcm_token_manager.dart';
import 'package:worship_chat/features/chat/screens/one_to_one_chat_screen.dart';
import 'package:worship_chat/features/group/screens/group_chat_screen.dart';
import 'package:worship_chat/models/chat_contact.dart';
import 'package:worship_chat/models/group.dart';
import 'package:worship_chat/models/group_chat_message_model.dart';
import 'package:worship_chat/models/one_to_one_message_model.dart';
import 'package:worship_chat/models/user_model.dart';

// ─── Background Notification Action Handler (top-level, required by Android) ─
@pragma('vm:entry-point')
void notificationActionBackgroundHandler(NotificationResponse response) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  await FirebaseNotificationService.ensureStaticInitialized();
  log('Background notification action: ${response.actionId}, payload: ${response.payload}');
  if (response.actionId == 'action_mark_read') {
    await FirebaseNotificationService.handleMarkAsReadAction(response);
  } else if (response.actionId == 'action_reply') {
    await FirebaseNotificationService.handleReplyAction(response);
  }
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
  await FirebaseNotificationService.ensureStaticInitialized();
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
  static bool _isStaticInitialized = false;

  /// Ensures FlutterLocalNotificationsPlugin is statically initialized with action callbacks and channels.
  /// Safe to call repeatedly across main isolate, background FCM isolate, and notification action isolate.
  static Future<void> ensureStaticInitialized({
    void Function(NotificationResponse)? onForegroundResponse,
  }) async {
    if (_isStaticInitialized && onForegroundResponse == null) return;
    try {
      const androidSettings =
          AndroidInitializationSettings('@mipmap/launcher_icon');
      const darwinSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
      );

      await _staticLocalNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: onForegroundResponse ??
            (response) {
              log('Foreground notification tapped: ${response.payload}');
              _instance?._onLocalNotificationTapped(response);
            },
        onDidReceiveBackgroundNotificationResponse:
            notificationActionBackgroundHandler,
      );

      final androidPlugin = _staticLocalNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(_highImportanceChannel);
      await androidPlugin?.createNotificationChannel(_legacyChannel);

      _isStaticInitialized = true;
      log('✅ FlutterLocalNotificationsPlugin statically initialized with channels');
    } catch (e) {
      log('⚠️ Error statically initializing notifications: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> _getPersistedNotificationMessages(
    String chatId,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList = prefs.getStringList('notif_msgs_$chatId');
      if (rawList != null && rawList.isNotEmpty) {
        return rawList
            .map((item) => Map<String, dynamic>.from(jsonDecode(item) as Map))
            .toList();
      }
      final oldLines = prefs.getStringList('notif_lines_$chatId') ?? [];
      return oldLines.map((line) => {
        'text': line,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'senderName': null,
        'senderKey': null,
      }).toList();
    } catch (e) {
      log('Error reading notification messages from prefs: $e');
      return [];
    }
  }

  static Future<void> _savePersistedNotificationMessages(
    String chatId,
    List<Map<String, dynamic>> messages,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = messages.map((m) => jsonEncode(m)).toList();
      await prefs.setStringList('notif_msgs_$chatId', jsonList);
    } catch (e) {
      log('Error saving notification messages to prefs: $e');
    }
  }

  static Future<void> _clearPersistedNotificationMessages(String chatId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('notif_msgs_$chatId');
      await prefs.remove('notif_lines_$chatId');
    } catch (e) {
      log('Error clearing notification messages in prefs: $e');
    }
  }

  /// Dismisses all notifications currently showing in the system notification shade/tray
  /// that correspond strictly to the given [chatId] (either senderUid for 1-on-1 or groupId for groups).
  /// Matches on tag, deterministic ID, and active notification properties.
  static Future<void> cancelNotificationsForChat(
    String chatId, {
    String? chatName,
  }) async {
    final cleanChatId = chatId.trim();
    if (cleanChatId.isEmpty) return;

    await _clearPersistedNotificationMessages(cleanChatId);

    try {
      await ensureStaticInitialized();
      final plugin = _staticLocalNotifications;
      final notifId = cleanChatId.hashCode.abs() % 2147483647;

      // 1. Cancel directly by deterministic ID with tag and without tag
      await plugin.cancel(notifId, tag: cleanChatId);
      await plugin.cancel(notifId);

      // 2. Query all currently active notifications in the Android notification shade
      // and dismiss strictly matching notifications for this specific chat.
      final activeList = await plugin.getActiveNotifications();
      for (final notif in activeList) {
        bool match = false;

        // Check exact tag match
        if (notif.tag != null) {
          final t = notif.tag!.trim().toLowerCase();
          if (t == cleanChatId.toLowerCase()) {
            match = true;
          }
        }

        // Check deterministic ID match
        if (!match && notif.id == notifId) {
          match = true;
        }

        if (match && notif.id != null) {
          log('🧹 Dismissed notification for chat $cleanChatId (id: ${notif.id}, tag: ${notif.tag})');
          if (notif.tag != null) {
            await plugin.cancel(notif.id!, tag: notif.tag);
          }
          await plugin.cancel(notif.id!);
        }
      }
    } catch (e) {
      log('⚠️ Error in cancelNotificationsForChat: $e');
    }
  }

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;

  // ── Public entry point ─────────────────────────────────────────────────────
  Future<void> initialize() async {
    _instance = this;

    // 1. Ensure static notification plugin and channels are ready
    await ensureStaticInitialized(
      onForegroundResponse: _onLocalNotificationTapped,
    );

    // 2. Request Android 13+ POST_NOTIFICATIONS runtime permission
    try {
      final androidPlugin = _staticLocalNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      final granted = await androidPlugin?.requestNotificationsPermission();
      log('Android 13+ POST_NOTIFICATIONS runtime permission granted: $granted');
    } catch (e) {
      log('Error requesting Android 13+ notification permission: $e');
    }

    // Cache current user info for background actions
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('cached_current_user_id', user.uid);
        if (user.displayName != null && user.displayName!.isNotEmpty) {
          await prefs.setString('cached_current_user_name', user.displayName!);
        }
        if (user.photoURL != null && user.photoURL!.isNotEmpty) {
          await prefs.setString('cached_current_user_pic', user.photoURL!);
        }
      }
    } catch (_) {}

    FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user != null) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('cached_current_user_id', user.uid);
          if (user.displayName != null && user.displayName!.isNotEmpty) {
            await prefs.setString('cached_current_user_name', user.displayName!);
          }
          if (user.photoURL != null && user.photoURL!.isNotEmpty) {
            await prefs.setString('cached_current_user_pic', user.photoURL!);
          }
        } catch (_) {}
      }
    });

    // Automatically dismiss notifications whenever any chat is entered
    ActiveChatNotifier.instance.onChatEntered = (chatId, chatName) {
      cancelNotificationsForChat(chatId, chatName: chatName);
    };

    // 3. Immediately listen for notification clicks when app is in BACKGROUND
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      log('onMessageOpenedApp tapped: ${message.data}');
      _navigateFromNotificationData(message.data);
    });

    // 4. Immediately listen for FOREGROUND messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // 5. Request permissions from FCM
    final settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    log('FCM permission: ${settings.authorizationStatus}');

    // 6. App was KILLED and launched by tapping a LOCAL notification
    if (!_initialNotificationHandled) {
      final launchDetails =
          await _staticLocalNotifications.getNotificationAppLaunchDetails();
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

  // ── Unified Notification Builder (used by BOTH foreground and background FCM) ───
  static Future<void> showNotificationFromRemoteMessage(
    RemoteMessage message,
  ) async {
    try {
      await ensureStaticInitialized();
      log('Processing remote notification message: ${message.messageId}, data: ${message.data}');

      final msgType = message.data['type']?.toString().trim();
      final senderUid = (message.data['senderUid'] ??
              message.data['uid'] ??
              message.data['senderId'])
          ?.toString()
          .trim();
      final groupId = (message.data['groupId'] ??
              (msgType == 'group' ? message.data['id'] : null))
          ?.toString()
          .trim();
      final chatId = (groupId != null && groupId.isNotEmpty)
          ? groupId
          : ((senderUid != null && senderUid.isNotEmpty)
              ? senderUid
              : (message.data['chatId']?.toString().trim() ?? 'general'));

      // 1. Suppress notification if user is currently inside this chat
      final activeChatId = ActiveChatNotifier.instance.activeChatUid;
      if (activeChatId != null &&
          (activeChatId == chatId ||
              (senderUid != null && activeChatId == senderUid) ||
              (groupId != null && activeChatId == groupId))) {
        log('🚫 Suppressing notification for currently opened chat: $activeChatId');
        return;
      }

      // 2. Extract title & body
      final rawTitle = message.notification?.title ??
          message.data['title'] ??
          message.data['groupName'] ??
          message.data['name'];
      final safeTitle = (rawTitle != null && rawTitle.toString().trim().isNotEmpty)
          ? rawTitle.toString().trim()
          : 'New Message';

      final rawBody = message.notification?.body ??
          message.data['body'] ??
          message.data['text'];
      final safeBody = (rawBody != null && rawBody.toString().trim().isNotEmpty)
          ? rawBody.toString().trim()
          : 'Tap to view message';

      if (safeTitle == 'New Message' &&
          (rawBody == null || rawBody.toString().trim().isEmpty)) {
        return;
      }

      final senderName = (message.data['name'] ?? '').toString().trim();
      final isGroup = (groupId != null && groupId.isNotEmpty);

      // 3. Append new message to existing conversation thread in SharedPreferences
      // Persisted so that messages from the same conversation tile append sequentially!
      final existingMessages = await _getPersistedNotificationMessages(chatId);
      final isDuplicate = existingMessages.isNotEmpty &&
          existingMessages.last['text'] == safeBody &&
          (existingMessages.last['senderKey'] == (senderUid ?? chatId)) &&
          (DateTime.now().millisecondsSinceEpoch -
                  ((existingMessages.last['timestamp'] as int?) ?? 0))
              .abs() < 2500;
      if (!isDuplicate) {
        existingMessages.add({
          'text': safeBody,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'senderName': senderName.isNotEmpty ? senderName : safeTitle,
          'senderKey': senderUid ?? chatId,
        });
      }
      List<Map<String, dynamic>> trimmedMessages = existingMessages;
      if (trimmedMessages.length > 15) {
        trimmedMessages = trimmedMessages.sublist(trimmedMessages.length - 15);
      }
      await _savePersistedNotificationMessages(chatId, trimmedMessages);

      final notifId = chatId.hashCode.abs() % 2147483647;

      final prefs = await SharedPreferences.getInstance();
      final currentUserId = FirebaseAuth.instance.currentUser?.uid ??
          prefs.getString('cached_current_user_id') ??
          'me';
      final currentUserName =
          prefs.getString('cached_current_user_name') ?? 'Me';

      final mePerson = Person(
        name: currentUserName,
        key: currentUserId,
      );

      final styleMessages = trimmedMessages.map((m) {
        final sName = m['senderName'] as String?;
        final sKey = m['senderKey'] as String?;
        final isMe = (sKey != null && sKey == currentUserId) || sName == 'Me';
        return Message(
          m['text'] as String? ?? '',
          DateTime.fromMillisecondsSinceEpoch(
            m['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
          ),
          isMe
              ? mePerson
              : Person(
                  name: (sName != null && sName.isNotEmpty) ? sName : safeTitle,
                  key: sKey ?? chatId,
                ),
        );
      }).toList();

      final messagingStyle = MessagingStyleInformation(
        mePerson,
        conversationTitle: isGroup ? safeTitle : null,
        groupConversation: isGroup,
        messages: styleMessages,
      );

      final actions = <AndroidNotificationAction>[
        const AndroidNotificationAction(
          'action_mark_read',
          'Mark as read',
          cancelNotification: true,
          showsUserInterface: false,
        ),
        const AndroidNotificationAction(
          'action_reply',
          'Reply',
          allowGeneratedReplies: true,
          cancelNotification: false,
          inputs: <AndroidNotificationActionInput>[
            AndroidNotificationActionInput(
              label: 'Type a reply...',
              allowFreeFormInput: true,
            ),
          ],
        ),
      ];

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
        styleInformation: messagingStyle,
        visibility: NotificationVisibility.public,
        category: AndroidNotificationCategory.message,
        actions: actions,
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: const DarwinNotificationDetails(presentSound: true),
      );

      // Encode the entire FCM data map as JSON so action and tap handlers can read it
      final payloadMap = Map<String, dynamic>.from(message.data);
      if (!payloadMap.containsKey('type') ||
          (payloadMap['type'] as String?)?.isEmpty == true) {
        payloadMap['type'] = groupId != null ? 'group' : 'chat';
      }
      payloadMap['chatId'] = chatId;
      if (groupId != null) payloadMap['groupId'] = groupId;
      if (senderUid != null) payloadMap['senderUid'] = senderUid;
      final payloadJson = jsonEncode(payloadMap);

      try {
        await _staticLocalNotifications.show(
          notifId,
          safeTitle,
          safeBody,
          details,
          payload: payloadJson,
        );
        log('✅ Notification posted (MessagingStyle) for $chatId (id: $notifId)');
      } catch (styleErr) {
        log('⚠️ MessagingStyle failed, falling back to BigTextStyle: $styleErr');
        final fallbackAndroidDetails = AndroidNotificationDetails(
          _highImportanceChannel.id,
          _highImportanceChannel.name,
          channelDescription: _highImportanceChannel.description,
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          icon: '@mipmap/launcher_icon',
          tag: chatId,
          styleInformation: BigTextStyleInformation(safeBody, contentTitle: safeTitle),
          visibility: NotificationVisibility.public,
          category: AndroidNotificationCategory.message,
          actions: actions,
        );
        await _staticLocalNotifications.show(
          notifId,
          safeTitle,
          safeBody,
          NotificationDetails(
            android: fallbackAndroidDetails,
            iOS: const DarwinNotificationDetails(presentSound: true),
          ),
          payload: payloadJson,
        );
        log('✅ Fallback notification posted for $chatId (id: $notifId)');
      }
    } catch (e) {
      log('❌ Error in showNotificationFromRemoteMessage: $e');
    }
  }

  // ── Foreground: display a local notification ───────────────────────────────
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    log('Foreground message: ${message.messageId}');
    await showNotificationFromRemoteMessage(message);
  }

  // ── Local notification response (tap or action button) ─────────────────────
  Future<void> _onLocalNotificationTapped(NotificationResponse response) async {
    log('Local notification action: ${response.actionId}, payload: ${response.payload}');

    if (response.actionId == 'action_mark_read') {
      await handleMarkAsReadAction(response);
      return;
    }

    if (response.actionId == 'action_reply') {
      await handleReplyAction(response);
      return;
    }

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

  // ── Notification Action: Mark as read ──────────────────────────────────────
  static Future<void> handleMarkAsReadAction(
    NotificationResponse response,
  ) async {
    try {
      await ensureStaticInitialized();
      if (response.payload == null || response.payload!.isEmpty) return;
      final data = Map<String, dynamic>.from(
        jsonDecode(response.payload!) as Map,
      );
      log('Mark as read requested from notification: $data');

      final prefs = await SharedPreferences.getInstance();
      var currentUserId = FirebaseAuth.instance.currentUser?.uid ??
          prefs.getString('cached_current_user_id');
      if (currentUserId == null) {
        for (int i = 0; i < 15; i++) {
          await Future.delayed(const Duration(milliseconds: 100));
          currentUserId = FirebaseAuth.instance.currentUser?.uid ??
              prefs.getString('cached_current_user_id');
          if (currentUserId != null) break;
        }
      }
      if (currentUserId == null) {
        log('⚠️ User not authenticated, cannot mark as read from notification');
        return;
      }

      String? type = data['type'] as String?;
      final senderUid = (data['senderUid'] ??
              data['uid'] ??
              data['senderId'])
          ?.toString()
          .trim();
      final groupId = (data['groupId'] ?? data['id'])?.toString().trim();

      if (type == null || type.isEmpty) {
        if (groupId != null && groupId.isNotEmpty) {
          type = 'group';
        } else if (senderUid != null && senderUid.isNotEmpty) {
          type = 'chat';
        }
      }

      final chatId = (groupId ?? senderUid) ?? '';
      if (chatId.isNotEmpty) {
        await cancelNotificationsForChat(chatId);
      }

      if (type == 'chat' && senderUid != null && senderUid.isNotEmpty) {
        // 1. Reset unseenCount on current user's contact doc
        try {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(currentUserId)
              .collection('chats')
              .doc(senderUid)
              .update({'unseenCount': false});
        } catch (e) {
          log('Note: could not update contact unseenCount: $e');
        }

        // 2. Mark unread messages as seen in both sender and receiver subcollections
        try {
          final unreadDocs = await FirebaseFirestore.instance
              .collection('users')
              .doc(currentUserId)
              .collection('chats')
              .doc(senderUid)
              .collection('messages')
              .where('isSeen', isEqualTo: false)
              .get();

          if (unreadDocs.docs.isNotEmpty) {
            final batch = FirebaseFirestore.instance.batch();
            int markedCount = 0;
            for (final doc in unreadDocs.docs) {
              final dData = doc.data();
              if (dData['receiverId'] != null && dData['receiverId'] != currentUserId) {
                continue;
              }
              markedCount++;
              batch.update(doc.reference, {'isSeen': true, 'isDelivered': true});

              final senderMsgRef = FirebaseFirestore.instance
                  .collection('users')
                  .doc(senderUid)
                  .collection('chats')
                  .doc(currentUserId)
                  .collection('messages')
                  .doc(doc.id);
              batch.update(senderMsgRef, {'isSeen': true, 'isDelivered': true});
            }
            if (markedCount > 0) {
              await batch.commit();
              log('✅ Marked $markedCount 1-to-1 messages as seen from notification');
            }
          }
        } catch (e) {
          log('❌ Error marking 1-to-1 messages seen: $e');
        }
      } else if (type == 'group' && groupId != null && groupId.isNotEmpty) {
        // 1. Reset group unseenMessages flag for current user
        try {
          await FirebaseFirestore.instance
              .collection('groups')
              .doc(groupId)
              .update({
            'unseenMessages.$currentUserId': false,
          });
        } catch (e) {
          log('Note: could not update group unseenMessages: $e');
        }

        // 2. Mark unread group messages as seen
        try {
          final unreadDocs = await FirebaseFirestore.instance
              .collection('groups')
              .doc(groupId)
              .collection('chats')
              .where('isSeen', isEqualTo: false)
              .get();

          if (unreadDocs.docs.isNotEmpty) {
            final batch = FirebaseFirestore.instance.batch();
            for (final doc in unreadDocs.docs) {
              batch.update(doc.reference, {'isSeen': true, 'isDelivered': true});
            }
            await batch.commit();
            log('✅ Marked ${unreadDocs.docs.length} group messages as seen from notification');
          }
        } catch (e) {
          log('❌ Error marking group messages seen: $e');
        }
      }
    } catch (e) {
      log('❌ Error in handleMarkAsReadAction: $e');
    }
  }

  // ── Notification Action: Reply ─────────────────────────────────────────────
  static Future<void> handleReplyAction(
    NotificationResponse response,
  ) async {
    try {
      await ensureStaticInitialized();
      final replyText = response.input?.trim();
      if (replyText == null || replyText.isEmpty) {
        log('⚠️ Empty reply input from notification, ignoring');
        return;
      }

      if (response.payload == null || response.payload!.isEmpty) return;
      final data = Map<String, dynamic>.from(
        jsonDecode(response.payload!) as Map,
      );
      log('Reply submitted from notification: "$replyText", data: $data');

      final prefs = await SharedPreferences.getInstance();
      var currentUserId = FirebaseAuth.instance.currentUser?.uid ??
          prefs.getString('cached_current_user_id');
      if (currentUserId == null) {
        for (int i = 0; i < 15; i++) {
          await Future.delayed(const Duration(milliseconds: 100));
          currentUserId = FirebaseAuth.instance.currentUser?.uid ??
              prefs.getString('cached_current_user_id');
          if (currentUserId != null) break;
        }
      }
      if (currentUserId == null) {
        log('⚠️ User not authenticated, cannot send reply from notification');
        return;
      }

      String? type = data['type'] as String?;
      final senderUid = (data['senderUid'] ??
              data['uid'] ??
              data['senderId'])
          ?.toString()
          .trim();
      final groupId = (data['groupId'] ?? data['id'])?.toString().trim();

      if (type == null || type.isEmpty) {
        if (groupId != null && groupId.isNotEmpty) {
          type = 'group';
        } else if (senderUid != null && senderUid.isNotEmpty) {
          type = 'chat';
        }
      }

      final chatId = (groupId ?? senderUid) ?? '';
      if (chatId.isNotEmpty) {
        await cancelNotificationsForChat(chatId);
      }

      // Fetch current user details
      UserModel? currentUser;
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUserId)
            .get();
        if (userDoc.exists && userDoc.data() != null) {
          currentUser = UserModel.fromMap(userDoc.data()!);
        }
      } catch (e) {
        log('Warning: could not fetch current user for reply: $e');
      }

      final cachedName = prefs.getString('cached_current_user_name');
      final cachedPic = prefs.getString('cached_current_user_pic');

      final senderName = currentUser?.name ?? currentUser?.userName ?? cachedName ?? 'User';
      final senderProfilePic = currentUser?.profilePic ?? cachedPic ?? '';
      final timeSent = DateTime.now();
      final messageId = const Uuid().v1();

      if (type == 'chat' && senderUid != null && senderUid.isNotEmpty) {
        // Fetch recipient's data for latest token and name
        UserModel? receiverUser;
        try {
          final rDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(senderUid)
              .get();
          if (rDoc.exists && rDoc.data() != null) {
            receiverUser = UserModel.fromMap(rDoc.data()!);
          }
        } catch (_) {}

        final receiverName =
            receiverUser?.name ?? (data['name'] as String?) ?? 'User';
        final receiverToken = receiverUser?.fcmToken ?? '';

        final message = OneToOneMessageModel(
          senderId: currentUserId,
          receiverId: senderUid,
          text: replyText,
          messageType: 'text',
          timeSent: timeSent,
          messageId: messageId,
          isSeen: false,
          isDelivered: false,
          isSending: false,
          fileMessageData: null,
          repliedMessage: '',
          repliedTo: '',
          repliedMessageType: 'text',
        );

        // Atomic message write to both users
        final batch = FirebaseFirestore.instance.batch();
        final receiverMessageRef = FirebaseFirestore.instance
            .collection('users')
            .doc(senderUid)
            .collection('chats')
            .doc(currentUserId)
            .collection('messages')
            .doc(messageId);
        final senderMessageRef = FirebaseFirestore.instance
            .collection('users')
            .doc(currentUserId)
            .collection('chats')
            .doc(senderUid)
            .collection('messages')
            .doc(messageId);

        batch.set(receiverMessageRef, message.toMap());
        batch.set(senderMessageRef, message.toMap());
        await batch.commit();

        // Update contacts
        String myToken = '';
        try {
          myToken = await FirebaseMessaging.instance.getToken() ?? '';
        } catch (_) {}
        final receiverContact = ChatContact(
          name: senderName,
          profilePic: senderProfilePic,
          uid: currentUserId,
          timeSent: timeSent,
          lastMessage: replyText,
          fcmToken: myToken,
          unseenCount: true,
          chatBackgroundUrl: '',
        );
        await FirebaseFirestore.instance
            .collection('users')
            .doc(senderUid)
            .collection('chats')
            .doc(currentUserId)
            .set(receiverContact.toMap(), SetOptions(merge: true));

        final senderContact = ChatContact(
          name: receiverName,
          profilePic: receiverUser?.profilePic,
          uid: senderUid,
          timeSent: timeSent,
          lastMessage: replyText,
          fcmToken: receiverToken,
          unseenCount: false,
          chatBackgroundUrl: '',
        );
        await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUserId)
            .collection('chats')
            .doc(senderUid)
            .set(senderContact.toMap(), SetOptions(merge: true));

        // Send FCM notification to recipient
        if (receiverToken.isNotEmpty) {
          await sendNotification(
            receiverToken,
            senderName,
            replyText,
            data: {
              'type': 'chat',
              'senderUid': currentUserId,
              'name': senderName,
              'profilePic': senderProfilePic,
              'tag': currentUserId,
            },
          );
        }
        log('✅ Direct notification reply sent for 1-to-1 chat');
      } else if (type == 'group' && groupId != null && groupId.isNotEmpty) {
        final groupDoc = await FirebaseFirestore.instance
            .collection('groups')
            .doc(groupId)
            .get();

        if (groupDoc.exists && groupDoc.data() != null) {
          final gData = groupDoc.data()!;
          final groupName = (gData['name'] ??
              data['groupName'] ??
              'Group Chat') as String;
          final membersUid = List<String>.from(gData['membersUid'] ?? []);
          final receiverIds =
              membersUid.where((m) => m != currentUserId).toList();

          final groupMessage = GroupChatMessageModel(
            senderId: currentUserId,
            receiverIds: receiverIds,
            groupId: groupId,
            text: replyText,
            messageType: 'text',
            timeSent: timeSent,
            messageId: messageId,
            isSeen: false,
            isDelivered: false,
            isSending: false,
            fileMessageData: null,
            repliedMessage: '',
            repliedTo: '',
            repliedMessageType: 'text',
          );

          await FirebaseFirestore.instance
              .collection('groups')
              .doc(groupId)
              .collection('chats')
              .doc(messageId)
              .set(groupMessage.toMap());

          Map<String, bool> unseenMessages = {};
          for (var uid in membersUid) {
            unseenMessages[uid] = (uid != currentUserId);
          }

          await FirebaseFirestore.instance
              .collection('groups')
              .doc(groupId)
              .update({
            'senderId': currentUserId,
            'lastMessage': replyText,
            'timeSent': DateTime.now().millisecondsSinceEpoch,
            'unseenMessages': unseenMessages,
          });

          final freshTokens =
              await FCMTokenManager.getGroupMemberTokens(groupId);
          if (freshTokens.isNotEmpty) {
            await sendMultipleNotification(
              freshTokens,
              groupName,
              '$senderName: $replyText',
              data: {
                'type': 'group',
                'groupId': groupId,
                'groupName': groupName,
                'tag': groupId,
                'name': senderName,
              },
            );
          }
          log('✅ Direct notification reply sent for group chat');
        }
      }
    } catch (e) {
      log('❌ Error in handleReplyAction: $e');
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
