import 'dart:convert';
import 'dart:developer';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:worship_chat/common/utils/active_chat_notifier.dart';
import 'package:worship_chat/common/utils/app_capabilities.dart';
import 'package:worship_chat/common/utils/fcm_token_manager.dart';
import 'package:worship_chat/common/utils/notification_media_helper.dart';
import 'package:worship_chat/common/utils/wish_helper.dart';
import 'package:worship_chat/features/chat/screens/one_to_one_chat_screen.dart';
import 'package:worship_chat/features/group/screens/group_chat_screen.dart';
import 'package:worship_chat/features/status/screens/view_status_screen.dart';
import 'package:worship_chat/features/status/repository/status_repository.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:worship_chat/features/chat/repositories/chat_repository.dart';
import 'package:worship_chat/features/group/repository/group_repository.dart';
import 'package:worship_chat/models/chat_contact.dart';
import 'package:worship_chat/models/group.dart';
import 'package:worship_chat/models/group_chat_message_model.dart';
import 'package:worship_chat/models/group_gallery_image.dart';
import 'package:worship_chat/models/one_to_one_message_model.dart';
import 'package:worship_chat/models/user_model.dart';
import 'package:worship_chat/firebase_options.dart';

// ─── Background Notification Action Handler (top-level, required by Android) ─
@pragma('vm:entry-point')
void notificationActionBackgroundHandler(NotificationResponse response) async {
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
  log('Background notification action: ${response.actionId}, payload: ${response.payload}');
  if (response.actionId == 'action_mark_read') {
    await FirebaseNotificationService.handleMarkAsReadAction(response);
  } else if (response.actionId == 'action_reply') {
    await FirebaseNotificationService.handleReplyAction(response);
  } else if (response.actionId == 'action_wish_celebrate') {
    await FirebaseNotificationService.handleCelebrateAction(response);
  }
}

const AndroidNotificationChannel backgroundTransfersChannel =
    AndroidNotificationChannel(
  'background_transfers_channel',
  'Background Transfers',
  description:
      'Ongoing notifications for background media uploads, downloads, and messages.',
  importance: Importance.low,
  playSound: false,
  enableVibration: false,
  showBadge: false,
);

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

const AndroidNotificationChannel _wishNotificationChannel =
    AndroidNotificationChannel(
  'royal_wishes_celebration_channel',
  'Royal Wishes & Celebrations',
  description:
      'Celebratory birthday proclamations, royal wishes, and divine sanctum devotions.',
  importance: Importance.max,
  playSound: true,
  enableVibration: true,
  enableLights: true,
  ledColor: Color(0xFFFFD700),
);

const AndroidNotificationChannel _legacyChannel = AndroidNotificationChannel(
  'worship_chat_channel',
  'Worship Chat Messages',
  description: 'Chat message notifications for Worship Chat',
  importance: Importance.max,
  playSound: true,
  enableVibration: true,
);

const AndroidNotificationChannel _appUpdatesChannel = AndroidNotificationChannel(
  'app_updates_channel',
  'App Updates',
  description: 'Notifications when a new Worship Chat APK update is available.',
  importance: Importance.high,
  playSound: true,
  enableVibration: true,
  enableLights: true,
  ledColor: Color(0xFF00E676),
);

/// Creates and registers notification channels with Android system NotificationManager early at boot
Future<void> createDefaultNotificationChannels() async {
  if (!AppCapabilities.current.notificationsEnabled) return;
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

  /// Returns whether there is a pending notification awaiting navigation.
  static bool get hasPendingNotification =>
      !_initialNotificationHandled && _pendingNotificationData != null;

  /// Retrieves and clears any pending notification data synchronously.
  static Map<String, dynamic>? getAndClearPendingNotificationData() {
    if (_initialNotificationHandled || _pendingNotificationData == null) {
      return null;
    }
    final data = _pendingNotificationData;
    _pendingNotificationData = null;
    _initialNotificationHandled = true;
    return data;
  }

  /// Called after RootGate finishes its splash animation and mounts HomeScreen.
  /// Dispatches any pending cold-start notification navigation cleanly on top of HomeScreen.
  static Future<void> checkAndDispatchPendingNotification() async {
    if (!AppCapabilities.current.notificationsEnabled) {
      clearPendingNotification();
      return;
    }
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
    if (!AppCapabilities.current.notificationsEnabled) return null;
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
          if (data['type'] == 'app_update') {
            pendingUpdateNotificationNotifier.value = data;
            _pendingNotificationData = null;
            _initialNotificationHandled = true;
            return null;
          }
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
        if (initialMessage.data['type'] == 'app_update') {
          pendingUpdateNotificationNotifier.value =
              Map<String, dynamic>.from(initialMessage.data);
          _pendingNotificationData = null;
          _initialNotificationHandled = true;
          return null;
        }
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
    if (!AppCapabilities.current.chatEnabled) return null;
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
      String fcmToken = data['fcmToken'] as String? ?? '';

      // Check local Hive cache for instantaneous (0ms) contact resolution
      if (name.isEmpty || profilePic == null || profilePic.isEmpty) {
        try {
          if (Hive.isBoxOpen('chatContactsBox')) {
            final box = Hive.box<ChatContact>('chatContactsBox');
            final cached = box.get(senderUid);
            if (cached != null) {
              if (name.isEmpty && cached.name.isNotEmpty) {
                name = cached.name;
              }
              if ((profilePic == null || profilePic.isEmpty) &&
                  cached.profilePic != null &&
                  cached.profilePic!.isNotEmpty) {
                profilePic = cached.profilePic;
              }
            }
          }
        } catch (_) {}
      }

      // Fallback to cached user box if needed
      if (name.isEmpty) {
        try {
          if (Hive.isBoxOpen('userBox')) {
            final box = Hive.box<UserModel>('userBox');
            final cached = box.get(senderUid);
            if (cached != null &&
                cached.name != null &&
                cached.name!.isNotEmpty) {
              name = cached.name!;
              if (profilePic == null || profilePic.isEmpty) {
                profilePic = cached.profilePic;
              }
            }
          }
        } catch (_) {}
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
        if (Hive.isBoxOpen('groupsBox')) {
          final box = Hive.box<GroupModel>('groupsBox');
          group = box.get(groupId);
        }
      } catch (_) {}

      final groupName = data['groupName'] as String? ??
          data['name'] as String? ??
          group?.nameWithPosition ??
          group?.name ??
          'Group Chat';

      final resolvedGroup = group ??
          GroupModel(
            senderId: '',
            name: groupName,
            groupId: groupId,
            lastMessage: '',
            groupPic: (data['groupPic'] as String?) ?? '',
            membersUid: [],
            timeSent: DateTime.now(),
            fcmTokens: [],
            unseenMessages: {},
            chatBackgroundUrl: null,
            wish: null,
            queendom: data['queendom'] as String?,
          );

      return GroupChatScreen(
        name: resolvedGroup.nameWithPosition,
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
    if (!AppCapabilities.current.notificationsEnabled) return;
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
      await androidPlugin?.createNotificationChannel(_wishNotificationChannel);
      await androidPlugin?.createNotificationChannel(backgroundTransfersChannel);
      await androidPlugin?.createNotificationChannel(_appUpdatesChannel);

      _isStaticInitialized = true;
      log('✅ FlutterLocalNotificationsPlugin statically initialized with channels');
    } catch (e) {
      log('⚠️ Error statically initializing notifications: $e');
    }
  }

  static FlutterLocalNotificationsPlugin get localNotifications =>
      _staticLocalNotifications;

  static const int appUpdateNotificationId = 900100;

  /// Notifies the active UI whenever the user taps an app update notification.
  static final ValueNotifier<Map<String, dynamic>?>
      pendingUpdateNotificationNotifier =
      ValueNotifier<Map<String, dynamic>?>(null);

  /// Shows a system push notification when a newer Worship Chat APK is available.
  static Future<void> showAppUpdateNotification({
    required String versionName,
    required int versionCode,
    String? releaseNotes,
    bool forceUpdate = false,
  }) async {
    if (!AppCapabilities.current.notificationsEnabled) return;
    await ensureStaticInitialized();

    final cleanVersion =
        versionName.trim().replaceFirst(RegExp(r'^v', caseSensitive: false), '');
    final title = forceUpdate
        ? '⚡ Required Update: Worship Chat v$cleanVersion'
        : '✨ Worship Chat v$cleanVersion Available';

    String body = 'Tap to download and install Build $versionCode.';
    if (releaseNotes != null && releaseNotes.trim().isNotEmpty) {
      final condensed = releaseNotes
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .take(2)
          .join(' • ');
      if (condensed.isNotEmpty) {
        body = condensed.length > 140
            ? '${condensed.substring(0, 137)}...'
            : condensed;
      }
    }

    final androidDetails = AndroidNotificationDetails(
      _appUpdatesChannel.id,
      _appUpdatesChannel.name,
      channelDescription: _appUpdatesChannel.description,
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      enableLights: true,
      ledColor: const Color(0xFF00E676),
      color: const Color(0xFFD4AF37),
      icon: '@mipmap/launcher_icon',
      tag: 'app_update',
      styleInformation: BigTextStyleInformation(body, contentTitle: title),
    );

    const darwinDetails = DarwinNotificationDetails(
      presentSound: true,
      presentBadge: true,
      presentAlert: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
    );

    final payload = jsonEncode({
      'type': 'app_update',
      'versionName': cleanVersion,
      'versionCode': versionCode.toString(),
      'forceUpdate': forceUpdate.toString(),
      if (releaseNotes != null && releaseNotes.trim().isNotEmpty)
        'releaseNotes': releaseNotes.trim(),
    });

    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final androidPlugin = _staticLocalNotifications
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        if (androidPlugin != null) {
          await androidPlugin.show(
            appUpdateNotificationId,
            title,
            body,
            notificationDetails: androidDetails,
            payload: payload,
          );
          log('✨ Posted app update notification for v$cleanVersion+$versionCode');
          return;
        }
      }
      await _staticLocalNotifications.show(
        appUpdateNotificationId,
        title,
        body,
        details,
        payload: payload,
      );
      log('✨ Posted app update notification for v$cleanVersion+$versionCode');
    } catch (e) {
      log('❌ Error posting app update notification: $e');
    }
  }

  /// Dismisses any visible app update notification (e.g. after updating or opening dialog).
  static Future<void> cancelAppUpdateNotification() async {
    if (!AppCapabilities.current.notificationsEnabled) return;
    try {
      await ensureStaticInitialized();
      if (defaultTargetPlatform == TargetPlatform.android) {
        final androidPlugin = _staticLocalNotifications
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        if (androidPlugin != null) {
          await androidPlugin.cancel(appUpdateNotificationId, tag: 'app_update');
          await androidPlugin.cancel(appUpdateNotificationId);
          return;
        }
      }
      await _staticLocalNotifications.cancel(appUpdateNotificationId);
    } catch (e) {
      log('⚠️ Error canceling app update notification: $e');
    }
  }

  /// Displays an alert notification specifically for wish reminders.
  /// Uses royal_wishes_celebration_channel with golden led and high importance.
  static Future<void> showWishReminderNotification({
    required int id,
    required String title,
    required String body,
    required String payload,
  }) async {
    if (!AppCapabilities.current.notificationsEnabled) return;
    await ensureStaticInitialized();

    const androidDetails = AndroidNotificationDetails(
      'royal_wishes_celebration_channel',
      'Royal Wishes & Celebrations',
      channelDescription:
          'Celebratory birthday proclamations, royal wishes, and divine sanctum devotions.',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      enableLights: true,
      ledColor: Color(0xFFFFD700),
      color: Color(0xFFD4AF37),
      icon: '@mipmap/launcher_icon',
      styleInformation: BigTextStyleInformation(''),
    );

    const darwinDetails = DarwinNotificationDetails(
      presentSound: true,
      presentBadge: true,
      presentAlert: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
    );

    try {
      await _staticLocalNotifications.show(
        id,
        title,
        body,
        details,
        payload: payload,
      );
      log('👑 Wish reminder notification posted (id: $id, title: $title)');
    } catch (e) {
      log('❌ Error posting wish reminder notification: $e');
    }
  }

  static bool _hiveInitialized = false;

  /// Ensures Hive is initialized and all models are registered in the current isolate.
  /// Safe to call repeatedly across main isolate, background FCM isolate, and notification action isolate.
  static Future<void> ensureHiveInitialized() async {
    if (_hiveInitialized) return;
    try {
      try {
        await Hive.initFlutter('worship_chat');
      } catch (_) {}
      if (!Hive.isAdapterRegistered(0)) {
        Hive.registerAdapter(UserModelAdapter());
      }
      if (!Hive.isAdapterRegistered(1)) {
        Hive.registerAdapter(OneToOneMessageModelAdapter());
      }
      if (!Hive.isAdapterRegistered(2)) {
        Hive.registerAdapter(GroupChatMessageModelAdapter());
      }
      if (!Hive.isAdapterRegistered(10)) {
        Hive.registerAdapter(GroupGalleryImageAdapter());
      }
      _hiveInitialized = true;
      log('✅ Hive initialized and adapters registered in isolate');
    } catch (e) {
      log('Note: ensureHiveInitialized: $e');
    }
  }

  static Future<Box?> _safeOpenBox(String boxName) async {
    try {
      if (Hive.isBoxOpen(boxName)) {
        return Hive.box(boxName);
      }
      return await Hive.openBox(boxName);
    } catch (e) {
      log('⚠️ Initial attempt to open box "$boxName" failed: $e, retrying...');
      try {
        await Future.delayed(const Duration(milliseconds: 200));
        if (Hive.isBoxOpen(boxName)) {
          return Hive.box(boxName);
        }
        return await Hive.openBox(boxName);
      } catch (retryErr) {
        log('❌ Failed to open box "$boxName": $retryErr');
        return null;
      }
    }
  }

  /// Ingests incoming FCM message payload directly into Hive cache.
  /// Enables instantaneous (0ms) message display when opening chat.
  static Future<void> ingestNotificationMessageIntoHive(RemoteMessage message) async {
    final data = Map<String, dynamic>.from(message.data);
    if ((data['text'] == null || data['text'].toString().trim().isEmpty) &&
        message.notification?.body != null) {
      data['text'] = message.notification!.body;
    }
    if ((data['name'] == null || data['name'].toString().trim().isEmpty) &&
        message.notification?.title != null) {
      data['name'] = message.notification!.title;
    }
    await ingestNotificationDataIntoHive(data);
  }

  /// Ingests notification data map into Hive box 'messages' and updates 'contacts_cache'.
  static Future<void> ingestNotificationDataIntoHive(Map<String, dynamic> data) async {
    try {
      await ensureHiveInitialized();
      final messagesBox = await _safeOpenBox('messages');
      if (messagesBox == null) {
        log('⚠️ [Hive Ingest] Could not open "messages" box');
        return;
      }

      String? type = data['type']?.toString().trim();
      final senderUid = (data['senderUid'] ?? data['uid'] ?? data['senderId'])?.toString().trim();
      final groupId = (data['groupId'] ?? (type == 'group' ? data['id'] : null))?.toString().trim();

      if (type == null || type.isEmpty) {
        if (groupId != null && groupId.isNotEmpty) {
          type = 'group';
        } else if (senderUid != null && senderUid.isNotEmpty) {
          type = 'chat';
        }
      }

      final prefs = await SharedPreferences.getInstance();
      String? currentUserId;
      try {
        currentUserId = FirebaseAuth.instance.currentUser?.uid;
      } catch (_) {}
      currentUserId ??= prefs.getString('cached_current_user_id') ??
          (type == 'chat' ? data['receiverId']?.toString().trim() : null);

      if (currentUserId == null || currentUserId.isEmpty) {
        log('⚠️ [Hive Ingest] Cannot determine current user ID, skipping ingestion');
        return;
      }

      if (type == 'chat' && senderUid != null && senderUid.isNotEmpty) {
        if (senderUid == currentUserId) return;

        final localKey = '${currentUserId}_$senderUid';
        final cachedData = messagesBox.get(localKey, defaultValue: []);
        final List<OneToOneMessageModel> messages = [];
        if (cachedData is List) {
          for (final item in cachedData) {
            if (item is OneToOneMessageModel) {
              messages.add(item);
            } else if (item is Map) {
              try {
                messages.add(OneToOneMessageModel.fromMap(Map<String, dynamic>.from(item)));
              } catch (_) {}
            }
          }
        }

        final rawMessageId =
            (data['messageId'] ?? data['id'])?.toString().trim();

        DateTime timeSent = DateTime.now();
        if (data['timeSent'] != null) {
          timeSent =
              DateTime.tryParse(data['timeSent'].toString()) ?? DateTime.now();
        }

        final rawText = (data['text'] ?? data['body'] ?? '').toString();
        final rawMsgType = (data['messageType'] ?? 'text').toString();
        final fileData = data['fileMessageData']?.toString();

        // Always update contacts cache so chatlist tile updates immediately
        await _updateContactsCacheForOneToOne(
          currentUserId: currentUserId,
          senderUid: senderUid,
          name: (data['name'] ?? data['senderName'] ?? '').toString(),
          profilePic: data['profilePic']?.toString(),
          lastMessage:
              rawText.isNotEmpty ? rawText : (fileData != null ? 'Media' : ''),
          timeSent: timeSent,
        );

        // DO NOT inject phantom message into Hive if messageId is missing.
        // Inventing random UUIDs causes duplicate messages when Firestore syncs.
        if (rawMessageId == null || rawMessageId.isEmpty) {
          log('ℹ️ [Hive Ingest] Skipping message injection: messageId is empty');
          return;
        }

        // DO NOT inject media notification as raw text cards (e.g. '📷 Photo' / '🎥 Video')
        final isMediaWithoutData =
            (rawMsgType == 'image' || rawMsgType == 'video') &&
                (fileData == null || fileData.isEmpty);
        if (isMediaWithoutData) {
          log('ℹ️ [Hive Ingest] Skipping media message without fileMessageData');
          return;
        }

        if (messages.any((m) => m.messageId == rawMessageId)) {
          log('ℹ️ [Hive Ingest] Message $rawMessageId already in local cache for $localKey');
          return;
        }

        final newMsg = OneToOneMessageModel(
          senderId: senderUid,
          receiverId: currentUserId,
          text: rawText,
          messageType: rawMsgType,
          timeSent: timeSent,
          messageId: rawMessageId,
          isSeen: false,
          isDelivered: true,
          isSending: false,
          fileMessageData: fileData,
          repliedMessage: (data['repliedMessage'] ?? '').toString(),
          repliedTo: (data['repliedTo'] ?? '').toString(),
          repliedMessageType: (data['repliedMessageType'] ?? 'text').toString(),
        );

        messages.add(newMsg);
        messages.sort((a, b) => a.timeSent.compareTo(b.timeSent));
        await messagesBox.put(localKey, messages);
        log('⚡ [Hive Ingest] Stored new 1-to-1 message $rawMessageId in Hive key $localKey');

        ChatRepository.notifyChatListeners(localKey, messages);

        // Acknowledge delivery to Firestore immediately so sender sees double grey ticks
        try {
          FirebaseFirestore.instance
              .collection('users')
              .doc(senderUid)
              .collection('chats')
              .doc(currentUserId)
              .collection('messages')
              .doc(rawMessageId)
              .update({'isDelivered': true}).catchError((_) {});
          FirebaseFirestore.instance
              .collection('users')
              .doc(currentUserId)
              .collection('chats')
              .doc(senderUid)
              .collection('messages')
              .doc(rawMessageId)
              .update({'isDelivered': true}).catchError((_) {});
        } catch (_) {}
      } else if (type == 'group' && groupId != null && groupId.isNotEmpty) {
        final localKey = groupId;
        final cachedData = messagesBox.get(localKey, defaultValue: []);
        final List<GroupChatMessageModel> messages = [];
        if (cachedData is List) {
          for (final item in cachedData) {
            if (item is GroupChatMessageModel) {
              messages.add(item);
            } else if (item is Map) {
              try {
                messages.add(GroupChatMessageModel.fromMap(
                    Map<String, dynamic>.from(item)));
              } catch (_) {}
            }
          }
        }

        final rawMessageId =
            (data['messageId'] ?? data['id'])?.toString().trim();
        if (rawMessageId == null || rawMessageId.isEmpty) {
          log('ℹ️ [Hive Ingest] Skipping group message injection: messageId is empty');
          return;
        }

        final senderId =
            (data['senderId'] ?? data['senderUid'] ?? '').toString();
        if (senderId.isNotEmpty && senderId == currentUserId) return;

        DateTime timeSent = DateTime.now();
        if (data['timeSent'] != null) {
          timeSent =
              DateTime.tryParse(data['timeSent'].toString()) ?? DateTime.now();
        }

        final rawText = (data['text'] ?? data['body'] ?? '').toString();
        final rawMsgType = (data['messageType'] ?? 'text').toString();
        final fileData = data['fileMessageData']?.toString();

        final isMediaWithoutData =
            (rawMsgType == 'image' || rawMsgType == 'video') &&
                (fileData == null || fileData.isEmpty);
        if (isMediaWithoutData) {
          log('ℹ️ [Hive Ingest] Skipping group media message without fileMessageData');
          return;
        }

        if (messages.any((m) => m.messageId == rawMessageId)) {
          log('ℹ️ [Hive Ingest] Group message $rawMessageId already in local cache for $localKey');
          return;
        }

        List<String> receiverIds = [];
        if (data['receiverIds'] != null) {
          receiverIds = data['receiverIds'].toString().split(',').where((s) => s.isNotEmpty).toList();
        }

        final newMsg = GroupChatMessageModel(
          senderId: senderId,
          receiverIds: receiverIds,
          groupId: groupId,
          text: rawText,
          messageType: rawMsgType,
          timeSent: timeSent,
          messageId: rawMessageId,
          isSeen: false,
          isDelivered: true,
          isSending: false,
          fileMessageData: fileData,
          repliedMessage: (data['repliedMessage'] ?? '').toString(),
          repliedTo: (data['repliedTo'] ?? '').toString(),
          repliedMessageType: (data['repliedMessageType'] ?? 'text').toString(),
        );

        messages.add(newMsg);
        messages.sort((a, b) => a.timeSent.compareTo(b.timeSent));
        await messagesBox.put(localKey, messages);
        log('⚡ [Hive Ingest] Stored new group message $rawMessageId in Hive key $localKey');

        GroupRepository.notifyGroupChatListeners(groupId, messages);
      }
    } catch (e) {
      log('❌ Error in ingestNotificationDataIntoHive: $e');
    }
  }

  static Future<void> _updateContactsCacheForOneToOne({
    required String currentUserId,
    required String senderUid,
    required String name,
    String? profilePic,
    required String lastMessage,
    required DateTime timeSent,
  }) async {
    try {
      final box = await _safeOpenBox('contacts_cache');
      if (box == null) return;
      final cacheKey = 'user_chats_$currentUserId';
      final cachedRaw = box.get(cacheKey, defaultValue: []);
      final List<Map<String, dynamic>> contactMaps = [];
      if (cachedRaw is List) {
        for (final item in cachedRaw) {
          if (item is Map) {
            contactMaps.add(Map<String, dynamic>.from(item));
          }
        }
      }

      final existingIndex = contactMaps.indexWhere((c) => c['uid'] == senderUid);
      if (existingIndex >= 0) {
        final existing = contactMaps[existingIndex];
        existing['lastMessage'] = lastMessage;
        existing['timeSent'] = timeSent.millisecondsSinceEpoch;
        existing['unseenCount'] = true;
        if (name.isNotEmpty) existing['name'] = name;
        if (profilePic != null && profilePic.isNotEmpty) existing['profilePic'] = profilePic;
        contactMaps[existingIndex] = existing;
      } else if (name.isNotEmpty) {
        contactMaps.add({
          'name': name,
          'profilePic': profilePic,
          'uid': senderUid,
          'timeSent': timeSent.millisecondsSinceEpoch,
          'lastMessage': lastMessage,
          'fcmToken': '',
          'unseenCount': true,
          'chatBackgroundUrl': '',
        });
      }

      contactMaps.sort((a, b) {
        final tA = a['timeSent'] as int? ?? 0;
        final tB = b['timeSent'] as int? ?? 0;
        return tB.compareTo(tA);
      });

      await box.put(cacheKey, contactMaps);
      log('⚡ [Hive Ingest] Updated contacts_cache for $senderUid in $cacheKey');
    } catch (e) {
      log('Note: Error updating contacts_cache: $e');
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
    if (!AppCapabilities.current.notificationsEnabled) return;
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

  FirebaseMessaging get _firebaseMessaging => FirebaseMessaging.instance;

  // ── Public entry point ─────────────────────────────────────────────────────
  Future<void> initialize() async {
    if (!AppCapabilities.current.notificationsEnabled) return;
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
    if (!AppCapabilities.current.notificationsEnabled) return;
    try {
      await ensureStaticInitialized();
      log('Processing remote notification message: ${message.messageId}, data: ${message.data}');

      final msgType = message.data['type']?.toString().trim();
      if (msgType == 'app_update') {
        final rawCode = int.tryParse(
              (message.data['versionCode'] ?? message.data['buildNumber'] ?? '0')
                  .toString()
                  .trim(),
            ) ??
            0;
        final rawName = (message.data['versionName'] ??
                message.data['version'] ??
                message.notification?.title ??
                '')
            .toString()
            .trim();
        final releaseNotes =
            (message.data['releaseNotes'] ?? message.notification?.body ?? '')
                .toString()
                .trim();
        final forceUpdate = message.data['forceUpdate'] == 'true' ||
            message.data['forceUpdate'] == true;
        final effectiveName = rawName.isNotEmpty
            ? rawName
            : (rawCode > 0 ? 'b$rawCode' : 'Latest');
        await showAppUpdateNotification(
          versionName: effectiveName,
          versionCode: rawCode,
          releaseNotes: releaseNotes,
          forceUpdate: forceUpdate,
        );
        try {
          if (rawCode > 0) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setInt('notified_update_version_code', rawCode);
            await prefs.setString('notified_update_version_name', effectiveName);
          }
        } catch (_) {}
        return;
      }

      await ingestNotificationMessageIntoHive(message);
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

      final isWish = (message.data['isWish'] == 'true') ||
          WishHelper.isWish(text: safeBody) ||
          WishHelper.isWish(text: rawBody?.toString());

      final notificationMessageType =
          message.data['messageType']?.toString().trim();
      final rawFileData = message.data['fileMessageData']?.toString();
      final rawStatusUrl = message.data['statusUrl']?.toString();
      final hasPhotoPreview = !isWish &&
          NotificationMediaHelper.supportsPhotoPreview(
            messageType: notificationMessageType,
            notificationType: msgType,
            rawFileData: rawFileData,
            statusUrl: rawStatusUrl,
          );
      final mediaPreviewUrl = hasPhotoPreview
          ? (NotificationMediaHelper.extractMediaUrl(rawFileData) ??
              NotificationMediaHelper.normalizeHttpUrl(rawStatusUrl))
          : null;
      final isGif = (notificationMessageType ?? '').toLowerCase() == 'gif';

      final resolvedMeta = await Future.wait<dynamic>([
        _getPersistedNotificationMessages(chatId),
        SharedPreferences.getInstance(),
        NotificationMediaHelper.resolveUserAvatarUrl(
          directProfilePic: message.data['profilePic']?.toString(),
          uid: senderUid,
        ),
        isGroup
            ? NotificationMediaHelper.resolveGroupAvatarUrl(
                directGroupPic: message.data['groupPic']?.toString(),
                groupId: groupId,
              )
            : Future<String?>.value(null),
      ]);

      final existingMessages =
          List<Map<String, dynamic>>.from(resolvedMeta[0] as List);
      final prefs = resolvedMeta[1] as SharedPreferences;
      final resolvedSenderPicUrl = resolvedMeta[2] as String?;
      final resolvedGroupPicUrl = resolvedMeta[3] as String?;

      final primaryAvatarUrl = isGroup
          ? (resolvedGroupPicUrl ?? resolvedSenderPicUrl)
          : resolvedSenderPicUrl;

      // 3. Append new message to existing conversation thread in SharedPreferences
      // Persisted so that messages from the same conversation tile append sequentially!
      final isDuplicate = existingMessages.isNotEmpty &&
          existingMessages.last['text'] == safeBody &&
          (existingMessages.last['senderKey'] == (senderUid ?? chatId)) &&
          (DateTime.now().millisecondsSinceEpoch -
                  ((existingMessages.last['timestamp'] as int?) ?? 0))
              .abs() <
              2500;
      if (!isDuplicate) {
        existingMessages.add({
          'text': safeBody,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'senderName': senderName.isNotEmpty ? senderName : safeTitle,
          'senderKey': senderUid ?? chatId,
          if (resolvedSenderPicUrl != null) 'senderPic': resolvedSenderPicUrl,
        });
      }
      List<Map<String, dynamic>> trimmedMessages = existingMessages;
      if (trimmedMessages.length > 15) {
        trimmedMessages = trimmedMessages.sublist(trimmedMessages.length - 15);
      }
      await _savePersistedNotificationMessages(chatId, trimmedMessages);

      final notifId = chatId.hashCode.abs() % 2147483647;

      final currentUserId = FirebaseAuth.instance.currentUser?.uid ??
          prefs.getString('cached_current_user_id') ??
          'me';
      final currentUserName =
          prefs.getString('cached_current_user_name') ?? 'Me';
      final currentUserPicUrl = NotificationMediaHelper.normalizeHttpUrl(
        prefs.getString('cached_current_user_pic'),
      );

      final assets = await NotificationMediaHelper.fetchNotificationAssets(
        primaryAvatarUrl: primaryAvatarUrl,
        senderAvatarUrl: resolvedSenderPicUrl,
        mediaPreviewUrl: mediaPreviewUrl,
        isGif: isGif,
      );

      final Map<String, BitmapFilePathAndroidIcon> avatarIconByUrl = {};
      if (resolvedSenderPicUrl != null && assets.senderAvatarFile != null) {
        avatarIconByUrl[resolvedSenderPicUrl] =
            BitmapFilePathAndroidIcon(assets.senderAvatarFile!.path);
      }

      // Resolve cached circular avatars for any prior group participants or me.
      final extraAvatarUrls = <String>{};
      if (currentUserPicUrl != null &&
          !avatarIconByUrl.containsKey(currentUserPicUrl)) {
        extraAvatarUrls.add(currentUserPicUrl);
      }
      for (final m in trimmedMessages.reversed) {
        final sPic = NotificationMediaHelper.normalizeHttpUrl(
          m['senderPic']?.toString(),
        );
        if (sPic != null && !avatarIconByUrl.containsKey(sPic)) {
          extraAvatarUrls.add(sPic);
          if (extraAvatarUrls.length >= 4) break;
        }
      }
      if (extraAvatarUrls.isNotEmpty) {
        final extraList = extraAvatarUrls.toList();
        final extraFiles = await Future.wait(
          extraList.map(
            (u) => NotificationMediaHelper.downloadCircularAvatar(url: u),
          ),
        );
        for (int i = 0; i < extraList.length; i++) {
          final f = extraFiles[i];
          if (f != null) {
            avatarIconByUrl[extraList[i]] =
                BitmapFilePathAndroidIcon(f.path);
          }
        }
      }

      final mePerson = Person(
        name: currentUserName,
        key: currentUserId,
        icon: currentUserPicUrl != null
            ? avatarIconByUrl[currentUserPicUrl]
            : null,
      );

      final styleMessages = trimmedMessages.map((m) {
        final sName = m['senderName'] as String?;
        final sKey = m['senderKey'] as String?;
        final sPic = NotificationMediaHelper.normalizeHttpUrl(
          m['senderPic']?.toString(),
        );
        final isMe = (sKey != null && sKey == currentUserId) || sName == 'Me';
        final personIcon = sPic != null
            ? avatarIconByUrl[sPic]
            : (resolvedSenderPicUrl != null
                ? avatarIconByUrl[resolvedSenderPicUrl]
                : null);
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
                  icon: personIcon,
                ),
        );
      }).toList();

      final messagingStyle = MessagingStyleInformation(
        mePerson,
        conversationTitle: isGroup ? safeTitle : null,
        groupConversation: isGroup,
        messages: styleMessages,
      );

      final AndroidBitmap<Object>? largeIconBitmap =
          assets.primaryAvatarFile != null
              ? FilePathAndroidBitmap(assets.primaryAvatarFile!.path)
              : null;

      final BigPictureStyleInformation? bigPictureStyle =
          (!isWish && assets.mediaPreviewFile != null)
              ? BigPictureStyleInformation(
                  FilePathAndroidBitmap(assets.mediaPreviewFile!.path),
                  largeIcon: largeIconBitmap,
                  contentTitle: safeTitle,
                  summaryText: safeBody,
                  hideExpandedLargeIcon: false,
                )
              : null;

      final channelId = isWish
          ? _wishNotificationChannel.id
          : _highImportanceChannel.id;
      final channelName = isWish
          ? _wishNotificationChannel.name
          : _highImportanceChannel.name;
      final channelDesc = isWish
          ? _wishNotificationChannel.description
          : _highImportanceChannel.description;

      final stylizedWishBody = WishHelper.toRoyalScript(safeBody);

      final wishBigTextStyle = BigTextStyleInformation(
        stylizedWishBody,
        contentTitle: safeTitle,
      );

      final StyleInformation resolvedStyle = isWish
          ? wishBigTextStyle
          : (bigPictureStyle ?? messagingStyle);

      final standardActions = <AndroidNotificationAction>[
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
        const AndroidNotificationAction(
          'action_mark_read',
          'Mark as read',
          cancelNotification: true,
          showsUserInterface: false,
        ),
      ];

      final actions = standardActions;

      final vibrationPattern = isWish
          ? Int64List.fromList([0, 160, 100, 240, 100, 380])
          : null;

      final androidDetails = AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDesc,
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        vibrationPattern: vibrationPattern,
        enableLights: isWish,
        ledColor: isWish ? const Color(0xFFFFD700) : null,
        ledOnMs: isWish ? 500 : null,
        ledOffMs: isWish ? 500 : null,
        color: isWish ? const Color(0xFFD4AF37) : null, // Metallic Royal Gold
        icon: '@mipmap/launcher_icon',
        largeIcon: largeIconBitmap,
        tag: chatId,
        styleInformation: resolvedStyle,
        visibility: NotificationVisibility.public,
        category: isWish
            ? AndroidNotificationCategory.event
            : AndroidNotificationCategory.message,
        actions: actions,
      );

      final List<DarwinNotificationAttachment> darwinAttachments = [
        if (!isWish && assets.mediaPreviewFile != null)
          DarwinNotificationAttachment(assets.mediaPreviewFile!.path)
        else if (assets.primaryAvatarFile != null)
          DarwinNotificationAttachment(assets.primaryAvatarFile!.path),
      ];

      final darwinDetails = DarwinNotificationDetails(
        presentSound: true,
        presentBadge: true,
        presentAlert: true,
        attachments: darwinAttachments,
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
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
          isWish ? stylizedWishBody : safeBody,
          details,
          payload: payloadJson,
        );
        final activeStyleName = isWish
            ? 'WishStyle'
            : (bigPictureStyle != null ? 'BigPictureStyle' : 'MessagingStyle');
        log('✅ Notification posted ($activeStyleName) for $chatId (id: $notifId)');
      } catch (styleErr) {
        log('⚠️ Notification style failed, falling back to BigTextStyle: $styleErr');
        final fallbackAndroidDetails = AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: channelDesc,
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          vibrationPattern: vibrationPattern,
          enableLights: isWish,
          ledColor: isWish ? const Color(0xFFFFD700) : null,
          color: isWish ? const Color(0xFFD4AF37) : null,
          icon: '@mipmap/launcher_icon',
          largeIcon: largeIconBitmap,
          tag: chatId,
          styleInformation: BigTextStyleInformation(
            isWish ? WishHelper.toRoyalScript(safeBody) : safeBody,
            contentTitle: safeTitle,
          ),
          visibility: NotificationVisibility.public,
          category: isWish
              ? AndroidNotificationCategory.event
              : AndroidNotificationCategory.message,
          actions: actions,
        );
        await _staticLocalNotifications.show(
          notifId,
          safeTitle,
          isWish ? WishHelper.toRoyalScript(safeBody) : safeBody,
          NotificationDetails(
            android: fallbackAndroidDetails,
            iOS: DarwinNotificationDetails(
              presentSound: true,
              presentBadge: true,
              presentAlert: true,
              attachments: assets.primaryAvatarFile != null
                  ? [
                      DarwinNotificationAttachment(
                        assets.primaryAvatarFile!.path,
                      ),
                    ]
                  : const [],
            ),
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
    if (!AppCapabilities.current.notificationsEnabled) return;
    log('Foreground message: ${message.messageId}');
    await showNotificationFromRemoteMessage(message);
  }

  // ── Local notification response (tap or action button) ─────────────────────
  Future<void> _onLocalNotificationTapped(NotificationResponse response) async {
    if (!AppCapabilities.current.notificationsEnabled) return;
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
    if (!AppCapabilities.current.notificationsEnabled) return;
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

  // ── Background Notification Reply Local Storage ────────────────────────────

  /// Persists a notification reply sent in background immediately to local storage
  /// (both SharedPreferences persistent buffer and Hive 'messages' box).
  /// Guarantees that the reply is never lost regardless of isolate file locking or network delays.
  static Future<void> recordBackgroundReply({
    required String chatId,
    required bool isGroup,
    required Map<String, dynamic> messageMap,
    required String replyText,
    required DateTime timeSent,
    String? receiverName,
    String? receiverProfilePic,
    String? currentUserId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 1. Immediately store in persistent SharedPreferences buffer (cross-isolate safe)
      final rawList =
          prefs.getStringList('pending_bg_replies_$chatId') ?? <String>[];
      final messageId = messageMap['messageId']?.toString() ?? '';
      final encodedMessage = jsonEncode(messageMap);

      if (!rawList.any((s) => s.contains('"messageId":"$messageId"'))) {
        rawList.add(encodedMessage);
        await prefs.setStringList('pending_bg_replies_$chatId', rawList);
      }

      final chatIds =
          prefs.getStringList('pending_bg_reply_chat_ids') ?? <String>[];
      if (!chatIds.contains(chatId)) {
        chatIds.add(chatId);
        await prefs.setStringList('pending_bg_reply_chat_ids', chatIds);
      }

      await prefs.setBool('bg_is_group_$chatId', isGroup);
      await prefs.setString('bg_last_message_$chatId', replyText);
      await prefs.setInt(
          'bg_last_time_$chatId', timeSent.millisecondsSinceEpoch);

      log('💾 [Background Reply] Buffered reply for $chatId (${isGroup ? 'group' : 'chat'}) in SharedPreferences');

      // 2. Direct attempt to write into Hive box 'messages' in current isolate
      try {
        await ensureHiveInitialized();
        final box = await _safeOpenBox('messages');
        if (box != null) {
          final cachedData = box.get(chatId, defaultValue: []);
          if (isGroup) {
            final List<GroupChatMessageModel> msgs = [];
            if (cachedData is List) {
              for (final item in cachedData) {
                if (item is GroupChatMessageModel) {
                  msgs.add(item);
                } else if (item is Map) {
                  try {
                    msgs.add(GroupChatMessageModel.fromMap(
                        Map<String, dynamic>.from(item)));
                  } catch (_) {}
                }
              }
            }
            if (!msgs.any((m) => m.messageId == messageId)) {
              msgs.add(GroupChatMessageModel.fromMap(messageMap));
              msgs.sort((a, b) => a.timeSent.compareTo(b.timeSent));
              await box.put(chatId, msgs);
              GroupRepository.notifyGroupChatListeners(chatId, msgs);
              log('💾 [Background Reply] Saved directly into Hive group messages: $chatId');
            }
          } else {
            final List<OneToOneMessageModel> msgs = [];
            if (cachedData is List) {
              for (final item in cachedData) {
                if (item is OneToOneMessageModel) {
                  msgs.add(item);
                } else if (item is Map) {
                  try {
                    msgs.add(OneToOneMessageModel.fromMap(
                        Map<String, dynamic>.from(item)));
                  } catch (_) {}
                }
              }
            }
            if (!msgs.any((m) => m.messageId == messageId)) {
              msgs.add(OneToOneMessageModel.fromMap(messageMap));
              msgs.sort((a, b) => a.timeSent.compareTo(b.timeSent));
              await box.put(chatId, msgs);
              ChatRepository.notifyChatListeners(chatId, msgs);
              log('💾 [Background Reply] Saved directly into Hive 1-to-1 messages: $chatId');
            }
          }
        }
      } catch (hiveErr) {
        log('Note: Direct Hive save in background isolate: $hiveErr (buffered in SharedPreferences)');
      }

      // 3. Update contacts_cache if 1-to-1
      if (!isGroup && currentUserId != null && currentUserId.isNotEmpty) {
        final senderUid = messageMap['receiverId']?.toString() ?? '';
        if (senderUid.isNotEmpty) {
          try {
            await _updateContactsCacheForOneToOne(
              currentUserId: currentUserId,
              senderUid: senderUid,
              name: receiverName ?? 'User',
              profilePic: receiverProfilePic,
              lastMessage: replyText,
              timeSent: timeSent,
            );
          } catch (_) {}
        }
      }
    } catch (e) {
      log('❌ Error in recordBackgroundReply: $e');
    }
  }

  /// Synchronizes all pending background notification replies from SharedPreferences into Hive.
  /// Designed to run in the main isolate on app resume or chat open without lock contention.
  static Future<void> syncPendingBackgroundRepliesToHive({
    String? specificChatId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final allPendingChatIds =
          prefs.getStringList('pending_bg_reply_chat_ids') ?? <String>[];
      if (allPendingChatIds.isEmpty) return;

      final targetIds = specificChatId != null
          ? (allPendingChatIds.contains(specificChatId)
              ? [specificChatId]
              : <String>[])
          : List<String>.from(allPendingChatIds);

      if (targetIds.isEmpty) return;

      await ensureHiveInitialized();
      final box = await _safeOpenBox('messages');
      if (box == null) return;

      final List<String> successfullySynced = [];

      for (final chatId in targetIds) {
        final rawList =
            prefs.getStringList('pending_bg_replies_$chatId') ?? <String>[];
        if (rawList.isEmpty) {
          successfullySynced.add(chatId);
          continue;
        }

        final isGroup = prefs.getBool('bg_is_group_$chatId') ?? false;
        final cachedData = box.get(chatId, defaultValue: []);

        if (isGroup) {
          final List<GroupChatMessageModel> msgs = [];
          if (cachedData is List) {
            for (final item in cachedData) {
              if (item is GroupChatMessageModel) {
                msgs.add(item);
              } else if (item is Map) {
                try {
                  msgs.add(GroupChatMessageModel.fromMap(
                      Map<String, dynamic>.from(item)));
                } catch (_) {}
              }
            }
          }

          bool addedAny = false;
          for (final raw in rawList) {
            try {
              final map = jsonDecode(raw) as Map<String, dynamic>;
              final m = GroupChatMessageModel.fromMap(map);
              if (!msgs.any((existing) => existing.messageId == m.messageId)) {
                msgs.add(m);
                addedAny = true;
              }
            } catch (parseErr) {
              log('Error parsing pending group message: $parseErr');
            }
          }

          if (addedAny) {
            msgs.sort((a, b) => a.timeSent.compareTo(b.timeSent));
            await box.put(chatId, msgs);
            GroupRepository.notifyGroupChatListeners(chatId, msgs);
          }
        } else {
          final List<OneToOneMessageModel> msgs = [];
          if (cachedData is List) {
            for (final item in cachedData) {
              if (item is OneToOneMessageModel) {
                msgs.add(item);
              } else if (item is Map) {
                try {
                  msgs.add(OneToOneMessageModel.fromMap(
                      Map<String, dynamic>.from(item)));
                } catch (_) {}
              }
            }
          }

          bool addedAny = false;
          for (final raw in rawList) {
            try {
              final map = jsonDecode(raw) as Map<String, dynamic>;
              final m = OneToOneMessageModel.fromMap(map);
              if (!msgs.any((existing) => existing.messageId == m.messageId)) {
                msgs.add(m);
                addedAny = true;
              }
            } catch (parseErr) {
              log('Error parsing pending 1-to-1 message: $parseErr');
            }
          }

          if (addedAny) {
            msgs.sort((a, b) => a.timeSent.compareTo(b.timeSent));
            await box.put(chatId, msgs);
            ChatRepository.notifyChatListeners(chatId, msgs);
          }
        }

        await prefs.remove('pending_bg_replies_$chatId');
        await prefs.remove('bg_is_group_$chatId');
        await prefs.remove('bg_last_message_$chatId');
        await prefs.remove('bg_last_time_$chatId');
        successfullySynced.add(chatId);
        log('✅ [Background Sync] Merged ${rawList.length} background replies into Hive for $chatId');
      }

      final remainingChatIds = allPendingChatIds
          .where((id) => !successfullySynced.contains(id))
          .toList();
      await prefs.setStringList('pending_bg_reply_chat_ids', remainingChatIds);
    } catch (e) {
      log('❌ Error in syncPendingBackgroundRepliesToHive: $e');
    }
  }

  /// Returns any pending background notification replies cached in SharedPreferences for a given chat.
  static List<T> getPendingBackgroundRepliesForChat<T>({
    required String chatId,
    required bool isGroup,
    required SharedPreferences prefs,
  }) {
    try {
      final rawList =
          prefs.getStringList('pending_bg_replies_$chatId') ?? <String>[];
      if (rawList.isEmpty) return <T>[];

      final List<T> result = [];
      for (final raw in rawList) {
        try {
          final map = jsonDecode(raw) as Map<String, dynamic>;
          if (isGroup) {
            result.add(GroupChatMessageModel.fromMap(map) as T);
          } else {
            result.add(OneToOneMessageModel.fromMap(map) as T);
          }
        } catch (_) {}
      }
      return result;
    } catch (_) {
      return <T>[];
    }
  }

  // ── Notification Action: Reply ─────────────────────────────────────────────
  static Future<void> handleReplyAction(
    NotificationResponse response,
  ) async {
    if (!AppCapabilities.current.notificationsEnabled) return;
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

      // Robust current user resolution across isolates
      var currentUserId = FirebaseAuth.instance.currentUser?.uid ??
          prefs.getString('cached_current_user_id');
      if (currentUserId == null || currentUserId.isEmpty) {
        if (Hive.isBoxOpen('userBox')) {
          currentUserId =
              Hive.box<UserModel>('userBox').get('currentUser')?.uid;
        } else {
          try {
            await ensureHiveInitialized();
            final uBox = await _safeOpenBox('userBox');
            final u = uBox?.get('currentUser');
            if (u is UserModel) currentUserId = u.uid;
          } catch (_) {}
        }
      }
      currentUserId ??=
          (type == 'chat' ? data['receiverId']?.toString().trim() : null);

      if (currentUserId == null || currentUserId.isEmpty) {
        log('⚠️ User not authenticated, cannot send reply from notification');
        return;
      }
      await prefs.setString('cached_current_user_id', currentUserId);

      final chatId = (groupId ?? senderUid) ?? '';
      if (chatId.isNotEmpty) {
        await cancelNotificationsForChat(chatId);
      }

      // Resolve sender name and profile pic (prefer local cache for instant speed)
      String senderName = prefs.getString('cached_current_user_name') ?? '';
      String senderProfilePic = prefs.getString('cached_current_user_pic') ?? '';
      if (senderName.isEmpty) {
        if (Hive.isBoxOpen('userBox')) {
          final u = Hive.box<UserModel>('userBox').get('currentUser');
          if (u != null) {
            senderName = u.name ?? u.userName ?? '';
            senderProfilePic = u.profilePic ?? '';
          }
        }
      }

      // Fallback to Firestore if local cache didn't have the name
      if (senderName.isEmpty) {
        try {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(currentUserId)
              .get();
          if (userDoc.exists && userDoc.data() != null) {
            final u = UserModel.fromMap(userDoc.data()!);
            senderName = u.name ?? u.userName ?? 'User';
            senderProfilePic = u.profilePic ?? '';
            await prefs.setString('cached_current_user_name', senderName);
            if (senderProfilePic.isNotEmpty) {
              await prefs.setString('cached_current_user_pic', senderProfilePic);
            }
          }
        } catch (e) {
          log('Warning: could not fetch current user for reply: $e');
        }
      }
      if (senderName.isEmpty) senderName = 'User';

      final timeSent = DateTime.now();
      final messageId = const Uuid().v1();

      if (type == 'chat' && senderUid != null && senderUid.isNotEmpty) {
        final localKey = '${currentUserId}_$senderUid';
        final receiverName = (data['name'] as String?) ?? 'User';

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

        // 1. RECORD LOCALLY FIRST (Immediate 0ms local storage)
        await recordBackgroundReply(
          chatId: localKey,
          isGroup: false,
          messageMap: message.toMap(),
          replyText: replyText,
          timeSent: timeSent,
          receiverName: receiverName,
          currentUserId: currentUserId,
        );

        // 2. Fetch recipient data and sync to Firestore
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

        final resolvedReceiverName = receiverUser?.name ?? receiverName;
        final receiverToken = receiverUser?.fcmToken ?? '';

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

        // Update contacts in Firestore
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
          chatBackgroundUrl: null,
        );
        await FirebaseFirestore.instance
            .collection('users')
            .doc(senderUid)
            .collection('chats')
            .doc(currentUserId)
            .set(receiverContact.toMap(), SetOptions(merge: true));

        final senderContact = ChatContact(
          name: resolvedReceiverName,
          profilePic: receiverUser?.profilePic,
          uid: senderUid,
          timeSent: timeSent,
          lastMessage: replyText,
          fcmToken: receiverToken,
          unseenCount: false,
          chatBackgroundUrl: null,
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
              'receiverId': senderUid,
              'name': senderName,
              'profilePic': senderProfilePic,
              'tag': currentUserId,
              'messageId': messageId,
              'messageType': 'text',
              'text': replyText,
              'timeSent': timeSent.toIso8601String(),
            },
          );
        }
        log('✅ Direct notification reply sent for 1-to-1 chat');
      } else if (type == 'group' && groupId != null && groupId.isNotEmpty) {
        final groupName = (data['groupName'] ?? 'Group Chat') as String;
        final receiverIdsStr = (data['receiverIds'] as String?) ?? '';
        final fallbackReceiverIds = receiverIdsStr.isNotEmpty
            ? receiverIdsStr.split(',').where((id) => id != currentUserId).toList()
            : <String>[];

        final groupMessage = GroupChatMessageModel(
          senderId: currentUserId,
          receiverIds: fallbackReceiverIds,
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

        // 1. RECORD LOCALLY FIRST (Immediate 0ms local storage)
        await recordBackgroundReply(
          chatId: groupId,
          isGroup: true,
          messageMap: groupMessage.toMap(),
          replyText: replyText,
          timeSent: timeSent,
          currentUserId: currentUserId,
        );

        // 2. Fetch latest group metadata and sync to Firestore
        List<String> memberUids = [];
        String? groupPic = NotificationMediaHelper.normalizeHttpUrl(
          data['groupPic']?.toString(),
        );
        try {
          final groupDoc = await FirebaseFirestore.instance
              .collection('groups')
              .doc(groupId)
              .get();
          if (groupDoc.exists && groupDoc.data() != null) {
            final gData = groupDoc.data()!;
            memberUids = List<String>.from(gData['membersUid'] ?? []);
            groupPic ??= NotificationMediaHelper.normalizeHttpUrl(
              gData['groupPic']?.toString(),
            );
          }
        } catch (_) {}

        final actualReceiverIds = memberUids.isNotEmpty
            ? memberUids.where((m) => m != currentUserId).toList()
            : fallbackReceiverIds;

        final finalGroupMessage = actualReceiverIds != fallbackReceiverIds
            ? groupMessage.copyWith(receiverIds: actualReceiverIds)
            : groupMessage;

        await FirebaseFirestore.instance
            .collection('groups')
            .doc(groupId)
            .collection('chats')
            .doc(messageId)
            .set(finalGroupMessage.toMap());

        Map<String, bool> unseenMessages = {};
        for (var uid in memberUids) {
          unseenMessages[uid] = (uid != currentUserId);
        }

        await FirebaseFirestore.instance
            .collection('groups')
            .doc(groupId)
            .update({
          'senderId': currentUserId,
          'lastMessage': replyText,
          'timeSent': DateTime.now().millisecondsSinceEpoch,
          if (unseenMessages.isNotEmpty) 'unseenMessages': unseenMessages,
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
              if (groupPic != null && groupPic.isNotEmpty)
                'groupPic': groupPic,
              if (senderProfilePic.isNotEmpty)
                'profilePic': senderProfilePic,
              'tag': groupId,
              'name': senderName,
              'senderId': currentUserId,
              'senderUid': currentUserId,
              'messageId': messageId,
              'messageType': 'text',
              'text': replyText,
              'timeSent': timeSent.toIso8601String(),
              if (actualReceiverIds.isNotEmpty)
                'receiverIds': actualReceiverIds.join(','),
            },
          );
        }
        log('✅ Direct notification reply sent for group chat');
      }
    } catch (e) {
      log('❌ Error in handleReplyAction: $e');
    }
  }

  static Future<void> handleCelebrateAction(
    NotificationResponse response,
  ) async {
    try {
      if (response.payload == null) return;
      final data = Map<String, dynamic>.from(
        jsonDecode(response.payload!) as Map,
      );
      final chatId = (data['groupId'] ?? data['senderUid'] ?? data['chatId'])
          ?.toString()
          .trim();
      if (chatId != null && chatId.isNotEmpty) {
        await cancelNotificationsForChat(chatId);
      }
      log('🎉 Handled celebratory notification action for $chatId');
    } catch (e) {
      log('Error handling celebrate action: $e');
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
    if (!AppCapabilities.current.chatEnabled) return;
    // If the app is still at the splash screen / RootGate, queue and wait until HomeScreen mounts
    if (!isAppReady) {
      log('⏳ App is still initializing (RootGate), queueing pending notification: $data');
      _pendingNotificationData = data;
      return;
    }

    String? type = data['type'] as String?;
    if (type == 'app_update') {
      pendingUpdateNotificationNotifier.value =
          Map<String, dynamic>.from(data);
      return;
    }

    // Ensure notification payload message is stored in Hive before opening chat
    await ingestNotificationDataIntoHive(data);

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
    } else if (type == 'story' || type == 'status') {
      await _navigateToStatus(data);
    } else {
      log('Unknown or missing notification type: $type');
    }
  }

  // ── Navigate to a status / story screen ───────────────────────────────────
  Future<void> _navigateToStatus(Map<String, dynamic> data) async {
    if (!AppCapabilities.current.chatEnabled) return;
    final isAuthed = await _ensureAuthenticated();
    if (!isAuthed) {
      log('Cannot navigate to status: user not authenticated');
      return;
    }

    final nav = await _waitForNavigator();
    if (nav == null) {
      log('Cannot navigate to status: NavigatorState unavailable');
      return;
    }

    final targetUid =
        (data['uid'] ?? data['senderUid'] ?? data['senderId']) as String?;
    if (targetUid == null || targetUid.isEmpty) {
      log('Cannot navigate to status: missing targetUid');
      return;
    }

    try {
      final now = DateTime.now();
      final snapshot = await FirebaseFirestore.instance
          .collection('status')
          .where('uid', isEqualTo: targetUid)
          .get();

      final List<Map<String, dynamic>> active = [];
      for (final doc in snapshot.docs) {
        final docData = doc.data();
        final timeCreated = (docData['timeCreated'] as Timestamp?)?.toDate();
        if (timeCreated != null && now.difference(timeCreated).inHours < 24) {
          active.add(StatusRepository.sanitizeStatus(docData));
        }
      }

      active.sort((a, b) {
        final aTime =
            (a['timeCreated'] as Timestamp?)?.toDate() ?? DateTime.now();
        final bTime =
            (b['timeCreated'] as Timestamp?)?.toDate() ?? DateTime.now();
        return aTime.compareTo(bTime);
      });

      if (active.isNotEmpty) {
        nav.pushNamed(
          ViewStatusesScreen.routeName,
          arguments: {"statuses": active, "initialIndex": 0},
        );
      } else {
        nav.popUntil((route) => route.isFirst);
      }
    } catch (e) {
      log('Error navigating to status from notification: $e');
    }
  }

  // ── Navigate to a 1-to-1 chat screen ──────────────────────────────────────
  Future<void> _navigateToOneToOneChat(Map<String, dynamic> data) async {
    if (!AppCapabilities.current.chatEnabled) return;
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

    final targetUid =
        (data['senderUid'] ?? data['uid'] ?? data['senderId']) as String?;
    if (targetUid != null &&
        ActiveChatNotifier.instance.isChatActive(targetUid)) {
      log('User is already viewing chat $targetUid');
      return;
    }

    final chatScreen = await buildChatScreenFromNotificationData(data);
    if (chatScreen == null) return;

    try {
      nav.push(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => chatScreen,
          transitionsBuilder: (_, animation, __, child) => FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          ),
          transitionDuration: const Duration(milliseconds: 150),
        ),
      );
    } catch (e) {
      log('Error pushing 1-to-1 chat route: $e');
    }
  }

  // ── Navigate to a group chat screen ──────────────────────────────────────
  Future<void> _navigateToGroupChat(Map<String, dynamic> data) async {
    if (!AppCapabilities.current.chatEnabled) return;
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

    final targetGroupId = (data['groupId'] ?? data['id']) as String?;
    if (targetGroupId != null &&
        ActiveChatNotifier.instance.isChatActive(targetGroupId)) {
      log('User is already viewing group $targetGroupId');
      return;
    }

    final groupScreen = await buildChatScreenFromNotificationData(data);
    if (groupScreen == null) return;

    try {
      nav.push(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => groupScreen,
          transitionsBuilder: (_, animation, __, child) => FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          ),
          transitionDuration: const Duration(milliseconds: 150),
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
  if (!AppCapabilities.current.notificationsEnabled) return;
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
  if (!AppCapabilities.current.notificationsEnabled) return;
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
