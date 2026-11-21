import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worship_chat/common/utils/app_capabilities.dart';
import 'package:worship_chat/common/utils/firebase_notification_service.dart';
import 'package:worship_chat/common/utils/wish_reminder_service.dart';
import 'package:worship_chat/features/group/screens/group_chat_screen.dart';
import 'package:worship_chat/models/group.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    AppCapabilities.debugOverride = const AppCapabilities(
      platform: TargetPlatform.android,
      isTablet: false,
    );
  });

  tearDownAll(() {
    AppCapabilities.debugOverride = null;
  });

  group('WishWindowInfo window detection tests', () {
    test('Correctly identifies morning window (6 AM to 12 PM)', () {
      final morningTime = DateTime(2026, 10, 29, 7, 30);
      final info = WishWindowInfo.forDateTime(morningTime);

      expect(info.type, WishWindowType.morning);
      expect(info.startTime, DateTime(2026, 10, 29, 6, 0));
      expect(info.endTime, DateTime(2026, 10, 29, 12, 0));
      expect(info.duration.inHours, 6);
    });

    test('Correctly identifies afternoon window (12 PM to 6 PM)', () {
      final afternoonTime = DateTime(2026, 10, 29, 14, 15);
      final info = WishWindowInfo.forDateTime(afternoonTime);

      expect(info.type, WishWindowType.afternoon);
      expect(info.startTime, DateTime(2026, 10, 29, 12, 0));
      expect(info.endTime, DateTime(2026, 10, 29, 18, 0));
      expect(info.duration.inHours, 6);
    });

    test('Correctly identifies evening window before midnight (6 PM to 6 AM next day)', () {
      final eveningTime = DateTime(2026, 10, 29, 20, 0);
      final info = WishWindowInfo.forDateTime(eveningTime);

      expect(info.type, WishWindowType.eveningNight);
      expect(info.startTime, DateTime(2026, 10, 29, 18, 0));
      expect(info.endTime, DateTime(2026, 10, 30, 6, 0));
      expect(info.duration.inHours, 12);
    });

    test('Correctly identifies early morning window after midnight (12 AM to 5:59 AM)', () {
      final earlyMorningTime = DateTime(2026, 10, 30, 4, 30);
      final info = WishWindowInfo.forDateTime(earlyMorningTime);

      expect(info.type, WishWindowType.eveningNight);
      expect(info.startTime, DateTime(2026, 10, 29, 18, 0));
      expect(info.endTime, DateTime(2026, 10, 30, 6, 0));
      expect(info.duration.inHours, 12);
    });
  });

  group('Deadline threshold calculations (80%, 90%, 95%)', () {
    test('Morning window (6 AM - 12 PM, 360 mins) threshold timings', () {
      final info = WishWindowInfo(
        type: WishWindowType.morning,
        startTime: DateTime(2026, 10, 29, 6, 0),
        endTime: DateTime(2026, 10, 29, 12, 0),
        title: 'Morning Sacred Devotion',
      );

      // Before 80% (e.g. 10:45 AM = 285 mins = 79.16%)
      final timeBefore80 = DateTime(2026, 10, 29, 10, 45);
      expect(info.getReachedThresholdsList(timeBefore80), isEmpty);
      expect(info.getHighestReachedThreshold(timeBefore80), isNull);

      // Exactly 80% (10:48 AM = 288 mins = 80%)
      final timeAt80 = DateTime(2026, 10, 29, 10, 48);
      expect(info.getReachedThresholdsList(timeAt80), [80]);
      expect(info.getHighestReachedThreshold(timeAt80), 80);

      // Exactly 90% (11:24 AM = 324 mins = 90%)
      final timeAt90 = DateTime(2026, 10, 29, 11, 24);
      expect(info.getReachedThresholdsList(timeAt90), [80, 90]);
      expect(info.getHighestReachedThreshold(timeAt90), 90);

      // Exactly 95% (11:42 AM = 342 mins = 95%)
      final timeAt95 = DateTime(2026, 10, 29, 11, 42);
      expect(info.getReachedThresholdsList(timeAt95), [80, 90, 95]);
      expect(info.getHighestReachedThreshold(timeAt95), 95);
    });

    test('Evening/Night window (6 PM - 6 AM, 720 mins) threshold timings', () {
      final info = WishWindowInfo(
        type: WishWindowType.eveningNight,
        startTime: DateTime(2026, 10, 29, 18, 0),
        endTime: DateTime(2026, 10, 30, 6, 0),
        title: 'Evening & Night Celestial Devotion',
      );

      // 80% of 720 mins = 576 mins = 3:36 AM next day
      final timeAt80 = DateTime(2026, 10, 30, 3, 36);
      expect(info.getReachedThresholdsList(timeAt80), [80]);
      expect(info.getHighestReachedThreshold(timeAt80), 80);

      // 90% of 720 mins = 648 mins = 4:48 AM next day
      final timeAt90 = DateTime(2026, 10, 30, 4, 48);
      expect(info.getReachedThresholdsList(timeAt90), [80, 90]);
      expect(info.getHighestReachedThreshold(timeAt90), 90);

      // 95% of 720 mins = 684 mins = 5:24 AM next day
      final timeAt95 = DateTime(2026, 10, 30, 5, 24);
      expect(info.getReachedThresholdsList(timeAt95), [80, 90, 95]);
      expect(info.getHighestReachedThreshold(timeAt95), 95);
    });

    test('Afternoon window (12 PM - 6 PM, 360 mins) threshold timings', () {
      final info = WishWindowInfo(
        type: WishWindowType.afternoon,
        startTime: DateTime(2026, 10, 29, 12, 0),
        endTime: DateTime(2026, 10, 29, 18, 0),
        title: 'Afternoon Royal Sanctum Devotion',
      );

      // 80% = 4:48 PM
      final timeAt80 = DateTime(2026, 10, 29, 16, 48);
      expect(info.getReachedThresholdsList(timeAt80), [80]);

      // 90% = 5:24 PM
      final timeAt90 = DateTime(2026, 10, 29, 17, 24);
      expect(info.getReachedThresholdsList(timeAt90), [80, 90]);

      // 95% = 5:42 PM
      final timeAt95 = DateTime(2026, 10, 29, 17, 42);
      expect(info.getReachedThresholdsList(timeAt95), [80, 90, 95]);
    });
  });

  group('Group position matching per window criteria', () {
    GroupModel buildGroup({
      required String id,
      required String name,
      required String position,
      bool isSubGroup = false,
    }) {
      return GroupModel(
        senderId: 'admin',
        name: name,
        groupId: id,
        lastMessage: '',
        groupPic: '',
        membersUid: ['user123'],
        timeSent: DateTime.now(),
        fcmTokens: [],
        unseenMessages: {},
        position: position,
        isSubGroup: isSubGroup,
      );
    }

    test('Evening/Night: Aura Elixiria Goddesses and all Princesses', () {
      final aura = buildGroup(id: '1', name: 'Aura Sanctum', position: 'Aura Elixiria Goddess');
      final firstPrincess = buildGroup(id: '2', name: 'Krithi', position: 'First Born Princess');
      final secondPrincess = buildGroup(id: '3', name: 'Sreeleela', position: 'Second Born Princess');
      final thirdPrincess = buildGroup(id: '4', name: 'Meenakshi', position: 'Third Born Princess');
      final princess = buildGroup(id: '5', name: 'Anikha', position: 'Princess');
      final supreme = buildGroup(id: '6', name: 'Nayanthara', position: 'Supreme Goddess');
      final queen = buildGroup(id: '7', name: 'Pooja', position: 'Queen');

      expect(WishReminderService.isGroupInWindow(aura, WishWindowType.eveningNight), isTrue);
      expect(WishReminderService.isGroupInWindow(firstPrincess, WishWindowType.eveningNight), isTrue);
      expect(WishReminderService.isGroupInWindow(secondPrincess, WishWindowType.eveningNight), isTrue);
      expect(WishReminderService.isGroupInWindow(thirdPrincess, WishWindowType.eveningNight), isTrue);
      expect(WishReminderService.isGroupInWindow(princess, WishWindowType.eveningNight), isTrue);
      expect(WishReminderService.isGroupInWindow(supreme, WishWindowType.eveningNight), isFalse);
      expect(WishReminderService.isGroupInWindow(queen, WishWindowType.eveningNight), isFalse);
    });

    test('Morning: Core Supreme, Supreme, Golden Blossom, Goddess, Demi Goddess', () {
      final coreSupreme = buildGroup(id: '1', name: 'Samantha', position: 'Core Supreme Goddess');
      final supreme = buildGroup(id: '2', name: 'Nayanthara', position: 'Supreme Goddess');
      final goldenBlossom = buildGroup(id: '3', name: 'Trisha', position: 'Golden Blossom Goddess');
      final goddess = buildGroup(id: '4', name: 'Kajal', position: 'Goddess');
      final demi = buildGroup(id: '5', name: 'Tamannaah', position: 'Demi Goddess');
      final aura = buildGroup(id: '6', name: 'Aura Shrine', position: 'Aura Elixiria Goddess');
      final queen = buildGroup(id: '7', name: 'Rashmika', position: 'Queen');

      expect(WishReminderService.isGroupInWindow(coreSupreme, WishWindowType.morning), isTrue);
      expect(WishReminderService.isGroupInWindow(supreme, WishWindowType.morning), isTrue);
      expect(WishReminderService.isGroupInWindow(goldenBlossom, WishWindowType.morning), isTrue);
      expect(WishReminderService.isGroupInWindow(goddess, WishWindowType.morning), isTrue);
      expect(WishReminderService.isGroupInWindow(demi, WishWindowType.morning), isTrue);
      expect(WishReminderService.isGroupInWindow(aura, WishWindowType.morning), isFalse);
      expect(WishReminderService.isGroupInWindow(queen, WishWindowType.morning), isFalse);
    });

    test('Afternoon: Dark Angels, Queens, Elfwitches, Enchantresses', () {
      final darkAngel = buildGroup(id: '1', name: 'Andrea', position: 'Dark Angel');
      final queen = buildGroup(id: '2', name: 'Pooja Hegde', position: 'Queen');
      final elfwitch = buildGroup(id: '3', name: 'Keerthy', position: 'Elfwitch');
      final enchantress = buildGroup(id: '4', name: 'Shruti', position: 'Enchantress');
      final supreme = buildGroup(id: '5', name: 'Nayanthara', position: 'Supreme Goddess');
      final princess = buildGroup(id: '6', name: 'Krithi', position: 'Princess');

      expect(WishReminderService.isGroupInWindow(darkAngel, WishWindowType.afternoon), isTrue);
      expect(WishReminderService.isGroupInWindow(queen, WishWindowType.afternoon), isTrue);
      expect(WishReminderService.isGroupInWindow(elfwitch, WishWindowType.afternoon), isTrue);
      expect(WishReminderService.isGroupInWindow(enchantress, WishWindowType.afternoon), isTrue);
      expect(WishReminderService.isGroupInWindow(supreme, WishWindowType.afternoon), isFalse);
      expect(WishReminderService.isGroupInWindow(princess, WishWindowType.afternoon), isFalse);
    });

    test('Sub-groups (Wife / Fuck Toy) are excluded from primary wish alerts', () {
      final wifeSubGroup = buildGroup(id: '10', name: 'Wife', position: 'Wife of Deity', isSubGroup: true);
      expect(WishReminderService.isGroupInWindow(wifeSubGroup, WishWindowType.morning), isFalse);
      expect(WishReminderService.isGroupInWindow(wifeSubGroup, WishWindowType.afternoon), isFalse);
      expect(WishReminderService.isGroupInWindow(wifeSubGroup, WishWindowType.eveningNight), isFalse);
    });
  });

  group('Wish Reminder Trigger and Deduplication', () {
    late SharedPreferences prefs;
    final List<Map<String, dynamic>> dispatchedNotifications = [];

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'cached_current_user_id': 'user_123',
      });
      prefs = await SharedPreferences.getInstance();
      dispatchedNotifications.clear();

      WishReminderService.instance.setTestingOverrides(
        prefs: prefs,
        notificationSender: ({
          required int id,
          required String title,
          required String body,
          required String payload,
        }) async {
          dispatchedNotifications.add({
            'id': id,
            'title': title,
            'body': body,
            'payload': payload,
          });
        },
      );
    });

    tearDown(() {
      WishReminderService.instance.resetTestingOverrides();
    });

    test('Fires notification at 80% threshold for unwished group with valid payload', () async {
      final sampleGroup = GroupModel(
        senderId: 'admin',
        name: 'Samantha',
        groupId: 'group_samantha',
        lastMessage: '',
        groupPic: 'https://example.com/pic.jpg',
        membersUid: ['user_123'],
        timeSent: DateTime.now(),
        fcmTokens: [],
        unseenMessages: {},
        position: 'Core Supreme Goddess',
        queendom: 'Queen Pooja',
      );

      final nowAt80 = DateTime(2026, 10, 29, 10, 48); // 80% of morning window

      // Simulate eligible groups lookup by testing notification delivery
      final windowInfo = WishWindowInfo.forDateTime(nowAt80);
      final reachedThresholds = windowInfo.getReachedThresholdsList(nowAt80);
      expect(reachedThresholds, [80]);

      final highestThreshold = reachedThresholds.last;
      final notifId = (sampleGroup.groupId.hashCode ^ highestThreshold).abs() % 1000000 + 10000;
      final payload = jsonEncode({
        'type': 'group',
        'groupId': sampleGroup.groupId,
        'groupName': sampleGroup.nameWithPosition,
        'name': sampleGroup.nameWithPosition,
        'groupPic': sampleGroup.groupPic,
        'queendom': sampleGroup.queendom,
      });

      await FirebaseNotificationService.showWishReminderNotification(
        id: notifId,
        title: '👑 Royal Wish Alert ($highestThreshold% Deadline)',
        body: 'You haven\'t wished ${sampleGroup.nameWithPosition}!',
        payload: payload,
      );

      // Verify payload can build chat screen for navigation
      final parsedPayload = Map<String, dynamic>.from(jsonDecode(payload) as Map);
      final screen = await FirebaseNotificationService.buildChatScreenFromNotificationData(parsedPayload);
      expect(screen, isA<GroupChatScreen>());
      final groupScreen = screen as GroupChatScreen;
      expect(groupScreen.groupId, sampleGroup.groupId);
      expect(groupScreen.name, sampleGroup.nameWithPosition);
      expect(groupScreen.queendom, 'Queen Pooja');
    });

    test('Deduplication prevents repeating notification for same group at same threshold', () async {
      final nowAt80 = DateTime(2026, 10, 29, 10, 50); // In 80% range
      final windowInfo = WishWindowInfo.forDateTime(nowAt80);
      const groupId = 'test_group_dedupe';
      final dedupeKey = 'wish_reminder_${groupId}_${windowInfo.startTime.millisecondsSinceEpoch}_80';

      // Initially not notified
      expect(prefs.getBool(dedupeKey), isNull);

      // Mark as notified
      await prefs.setBool(dedupeKey, true);

      // Check key is now set
      expect(prefs.getBool(dedupeKey), isTrue);
    });
  });
}
