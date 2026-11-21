import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_chat/common/utils/app_capabilities.dart';
import 'package:worship_chat/common/utils/fcm_token_manager.dart';
import 'package:worship_chat/common/utils/firebase_notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final galleryDevices = <String, AppCapabilities>{
    'macOS': const AppCapabilities(
      platform: TargetPlatform.macOS,
      isTablet: false,
    ),
    'Windows': const AppCapabilities(
      platform: TargetPlatform.windows,
      isTablet: false,
    ),
    'iPad': const AppCapabilities(platform: TargetPlatform.iOS, isTablet: true),
    'Android tablet': const AppCapabilities(
      platform: TargetPlatform.android,
      isTablet: true,
    ),
  };

  for (final device in galleryDevices.entries) {
    test(
      '${device.key} skips notifications, tokens and chat deep links',
      () async {
        AppCapabilities.debugOverride = device.value;
        debugDefaultTargetPlatformOverride = device.value.platform;
        final pluginCalls = <MethodCall>[];
        const channels = [
          MethodChannel('dexterous.com/flutter/local_notifications'),
          MethodChannel('plugins.flutter.io/firebase_messaging'),
        ];
        for (final channel in channels) {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, (call) async {
                pluginCalls.add(call);
                return null;
              });
        }
        addTearDown(() {
          AppCapabilities.debugOverride = null;
          debugDefaultTargetPlatformOverride = null;
          for (final channel in channels) {
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
                .setMockMethodCallHandler(channel, null);
          }
        });

        // None of these entry points should require a Firebase app or plugin.
        expect(Firebase.apps, isEmpty);
        final service = FirebaseNotificationService(
          navigatorKey: GlobalKey<NavigatorState>(),
        );
        await service.initialize();
        await createDefaultNotificationChannels();
        await FirebaseNotificationService.ensureStaticInitialized();
        await FirebaseNotificationService.cancelNotificationsForChat(
          'phone-chat',
        );
        await FirebaseNotificationService.showNotificationFromRemoteMessage(
          const RemoteMessage(
            data: {'senderUid': 'phone-chat', 'text': 'Hello'},
          ),
        );
        const response = NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotificationAction,
          actionId: 'action_reply',
          input: 'Hello',
          payload: '{"type":"chat","senderUid":"phone-chat"}',
        );
        await FirebaseNotificationService.handleMarkAsReadAction(response);
        await FirebaseNotificationService.handleReplyAction(response);
        expect(
          await FirebaseNotificationService.getInitialNotificationData(),
          isNull,
        );
        expect(
          await FirebaseNotificationService.buildChatScreenFromNotificationData(
            {'type': 'chat', 'senderUid': 'phone-chat'},
          ),
          isNull,
        );
        expect(
          await FirebaseNotificationService.buildChatScreenFromNotificationData(
            {'type': 'group', 'groupId': 'phone-group'},
          ),
          isNull,
        );
        await FirebaseNotificationService.checkAndDispatchPendingNotification();
        await FCMTokenManager.initializeFCM();
        expect(await FCMTokenManager.refreshAndSaveFCMToken(), isNull);
        expect(await FCMTokenManager.getFreshFCMTokens(['user']), isEmpty);
        expect(await FCMTokenManager.getGroupMemberTokens('group'), isEmpty);
        expect(await FCMTokenManager.hasValidFCMToken('user'), isFalse);
        await FCMTokenManager.debugGroupTokens('group');

        var networkClients = 0;
        await HttpOverrides.runZoned(
          () async {
            await sendNotification('phone-token', 'Chat', 'Hello');
            await sendMultipleNotification(['phone-token'], 'Chat', 'Hello');
          },
          createHttpClient: (_) {
            networkClients++;
            throw StateError('Gallery sessions cannot send chat notifications');
          },
        );
        expect(networkClients, 0);
        expect(pluginCalls, isEmpty);
        expect(Firebase.apps, isEmpty);
      },
    );
  }
}
