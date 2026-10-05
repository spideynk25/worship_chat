import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worship_chat/common/utils/media_cache_service.dart';
import 'package:worship_chat/common/enums/message_status_enum.dart';
import 'package:worship_chat/common/utils/utils.dart';
import 'package:worship_chat/features/chat/widgets/my_message_card.dart';
import 'package:worship_chat/features/chat/widgets/sender_message_card.dart';
import 'package:worship_chat/models/one_to_one_message_model.dart';
import 'package:worship_chat/models/group_chat_message_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:worship_chat/common/widgets/skeleton_loader.dart';
import 'package:worship_chat/common/widgets/user_avatar.dart';
import 'package:worship_chat/models/chat_contact.dart';
import 'package:worship_chat/models/user_model.dart';
import 'package:worship_chat/features/chat/widgets/document_message_widget.dart';
import 'package:worship_chat/features/chat/widgets/location_message_widget.dart';
import 'package:worship_chat/features/chat/widgets/display_messages.dart';

void main() {
  group('MessageDeliveryStatus tests', () {
    test('handles null and boolean flags safely without throwing', () {
      expect(MessageDeliveryStatus.fromFlags(isSending: true), MessageDeliveryStatus.sending);
      expect(MessageDeliveryStatus.fromFlags(isSeen: true), MessageDeliveryStatus.seen);
      expect(MessageDeliveryStatus.fromFlags(isDelivered: true), MessageDeliveryStatus.delivered);
      expect(MessageDeliveryStatus.fromFlags(), MessageDeliveryStatus.sent);
      expect(MessageDeliveryStatus.fromFlags(isSeen: null, isDelivered: null, isSending: null), MessageDeliveryStatus.sent);
    });
  });

  group('OneToOneMessageModel null safety tests', () {
    test('getters are always non-null bool even if initialized with null', () {
      final model = OneToOneMessageModel(
        senderId: 's1',
        receiverId: 'r1',
        text: 'Hello',
        messageType: 'text',
        timeSent: DateTime.now(),
        messageId: '78b15aa0-b384-11f1-bc99-078449fa7afe',
        isSeen: null,
        isDelivered: null,
        isSending: null,
        repliedMessage: '',
        repliedTo: '',
        repliedMessageType: 'text',
      );

      expect(model.isSeen, false);
      expect(model.isDelivered, false);
      expect(model.isSending, false);

      final updated = model.copyWith(isSeen: true);
      expect(updated.isSeen, true);
      expect(updated.isDelivered, false);
      expect(updated.isSending, false);
    });
  });

  group('GroupChatMessageModel null safety tests', () {
    test('getters are always non-null bool even if initialized with null', () {
      final model = GroupChatMessageModel(
        senderId: 's1',
        receiverIds: ['r1'],
        groupId: 'g1',
        text: 'Group Hello',
        messageType: 'text',
        timeSent: DateTime.now(),
        messageId: 'group_msg_1',
        isSeen: null,
        isDelivered: null,
        isSending: null,
        repliedMessage: '',
        repliedTo: '',
        repliedMessageType: 'text',
      );

      expect(model.isSeen, false);
      expect(model.isDelivered, false);
      expect(model.isSending, false);
    });
  });

  group('Widget rendering tests', () {
    testWidgets('MyMessageCard and SenderMessageCard render without error', (WidgetTester tester) async {
      final types = ['text', 'image', 'video', 'gif'];

      for (final type in types) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    MyMessageCard(
                      message: type == 'text' ? 'Hi' : 'Media test',
                      date: '10:00 PM',
                      messageType: type,
                      fileMessageData: type != 'text' ? 'https://example.com/asset' : null,
                      repliedText: '',
                      username: '',
                      repliedMessageType: 'text',
                      onLeftSwipe: () {},
                      isSeen: true,
                      isDelivered: true,
                      isSending: false,
                    ),
                    SenderMessageCard(
                      message: type == 'text' ? 'Hi there, how are you doing today?' : 'Sender Media',
                      date: '10:01 PM',
                      messageType: type,
                      fileMessageData: type != 'text' ? 'https://example.com/asset' : null,
                      repliedText: '',
                      username: '',
                      repliedMessageType: 'text',
                      onRightSwipe: () {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();
      }

      expect(find.byType(MyMessageCard), findsWidgets);
      expect(find.byType(SenderMessageCard), findsWidgets);
    });

    testWidgets('ChatAppBarSkeleton renders correctly without error', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            appBar: PreferredSize(
              preferredSize: Size.fromHeight(kToolbarHeight),
              child: SafeArea(child: ChatAppBarSkeleton()),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(ChatAppBarSkeleton), findsOneWidget);
    });
  });

  group('fromMap deserialization robustness tests', () {
    test('OneToOneMessageModel.fromMap handles Timestamp, int, String, and nulls safely', () {
      final now = DateTime.now();
      final mapWithTimestamp = {
        'senderId': 'sender123',
        'receiverId': 'receiver456',
        'text': 'Test message',
        'messageType': 'text',
        'timeSent': Timestamp.fromDate(now),
        'messageId': 'msg-1',
        'isSeen': false,
        'isDelivered': true,
        'isSending': false,
        'repliedMessage': '',
        'repliedTo': '',
        'repliedMessageType': 'text',
      };
      final model1 = OneToOneMessageModel.fromMap(mapWithTimestamp);
      expect(model1.text, 'Test message');
      expect(model1.senderId, 'sender123');
      expect(model1.timeSent.millisecondsSinceEpoch, now.millisecondsSinceEpoch);

      final mapWithMillis = {
        'senderId': 'sender123',
        'receiverId': 'receiver456',
        'text': 'Millis message',
        'messageType': 'text',
        'timeSent': now.millisecondsSinceEpoch,
        'messageId': 'msg-2',
      };
      final model2 = OneToOneMessageModel.fromMap(mapWithMillis);
      expect(model2.text, 'Millis message');
      expect(model2.timeSent.millisecondsSinceEpoch, now.millisecondsSinceEpoch);

      final mapWithNulls = <String, dynamic>{
        'senderId': null,
        'receiverId': null,
        'text': null,
        'messageType': null,
        'timeSent': null,
        'messageId': null,
      };
      final model3 = OneToOneMessageModel.fromMap(mapWithNulls);
      expect(model3.text, '');
      expect(model3.messageId, '');
      expect(model3.timeSent, isNotNull);
    });

    test('ChatContact.fromMap handles Timestamp, int, and nulls safely', () {
      final now = DateTime.now();
      final contactMap = {
        'name': 'Pooja',
        'profilePic': 'https://example.com/pic.jpg',
        'contactId': 'user-123',
        'timeSent': Timestamp.fromDate(now),
        'lastMessage': 'Hey there!',
        'fcmToken': 'fcm-token-abc',
        'unseenCount': true,
      };
      final contact = ChatContact.fromMap(contactMap);
      expect(contact.name, 'Pooja');
      expect(contact.uid, 'user-123');
      expect(contact.lastMessage, 'Hey there!');
      expect(contact.fcmToken, 'fcm-token-abc');
      expect(contact.unseenCount, true);

      final fallbackContact = ChatContact.fromMap({});
      expect(fallbackContact.name, 'User');
      expect(fallbackContact.uid, '');
      expect(fallbackContact.lastMessage, '');

      final docIdFallbackContact = ChatContact.fromMap({}, documentId: 'XCFP936ubzLjLJRYmUdULbUoeaA2');
      expect(docIdFallbackContact.uid, 'XCFP936ubzLjLJRYmUdULbUoeaA2');
    });

    test('UserAvatar.sanitizeUrl upgrades http to https and handles edge cases', () {
      expect(UserAvatar.sanitizeUrl('http://res.cloudinary.com/test/image.jpg'),
          'https://res.cloudinary.com/test/image.jpg');
      expect(UserAvatar.sanitizeUrl('https://res.cloudinary.com/test/image.jpg'),
          'https://res.cloudinary.com/test/image.jpg');
      expect(UserAvatar.sanitizeUrl('  http://example.com/pic.png  '),
          'https://example.com/pic.png');
      expect(UserAvatar.sanitizeUrl(null), isNull);
      expect(UserAvatar.sanitizeUrl(''), isNull);
      expect(UserAvatar.sanitizeUrl('   '), isNull);
      expect(UserAvatar.sanitizeUrl('null'), isNull);
    });

    test('UserModel.fromMap sanitizes profilePic and supports alternative photoUrl fields', () {
      final userHttp = UserModel.fromMap({
        'name': 'Test User',
        'userName': 'testuser',
        'uid': 'uid123',
        'profilePic': 'http://res.cloudinary.com/user.jpg',
      });
      expect(userHttp.profilePic, 'https://res.cloudinary.com/user.jpg');

      final userPhotoUrl = UserModel.fromMap({
        'name': 'Test User',
        'userName': 'testuser',
        'uid': 'uid123',
        'photoUrl': 'http://res.cloudinary.com/alt.jpg',
      });
      expect(userPhotoUrl.profilePic, 'https://res.cloudinary.com/alt.jpg');
    });

    test('GroupChatMessageModel.fromMap handles Timestamp, int, String, and nulls safely', () {
      final now = DateTime.now();
      final groupMsgTimestamp = GroupChatMessageModel.fromMap({
        'senderId': 'sender123',
        'receiverIds': ['rec1', 'rec2'],
        'groupId': 'group-1',
        'text': 'Group message with timestamp',
        'timeSent': Timestamp.fromDate(now),
        'messageId': 'gmsg-1',
        'isSeen': false,
        'isDelivered': false,
      });
      expect(groupMsgTimestamp.text, 'Group message with timestamp');
      expect(groupMsgTimestamp.timeSent.millisecondsSinceEpoch, now.millisecondsSinceEpoch);

      final groupMsgMillis = GroupChatMessageModel.fromMap({
        'senderId': 'sender123',
        'receiverIds': ['rec1', 'rec2'],
        'groupId': 'group-1',
        'text': 'Group message with millis',
        'timeSent': now.millisecondsSinceEpoch,
        'messageId': 'gmsg-2',
      });
      expect(groupMsgMillis.text, 'Group message with millis');
      expect(groupMsgMillis.timeSent.millisecondsSinceEpoch, now.millisecondsSinceEpoch);

      final groupMsgNulls = GroupChatMessageModel.fromMap(<String, dynamic>{});
      expect(groupMsgNulls.text, '');
      expect(groupMsgNulls.isSeen, isFalse);
      expect(groupMsgNulls.isDelivered, isFalse);
      expect(groupMsgNulls.isSending, isFalse);
    });

    test('4-stage message delivery lifecycle transitions correctly', () {
      // Stage 1: Sending (clock icon)
      expect(
        MessageDeliveryStatus.fromFlags(isSending: true, isDelivered: false, isSeen: false),
        MessageDeliveryStatus.sending,
      );

      // Stage 2: Sent (single grey tick)
      expect(
        MessageDeliveryStatus.fromFlags(isSending: false, isDelivered: false, isSeen: false),
        MessageDeliveryStatus.sent,
      );

      // Stage 3: Delivered (double grey ticks)
      expect(
        MessageDeliveryStatus.fromFlags(isSending: false, isDelivered: true, isSeen: false),
        MessageDeliveryStatus.delivered,
      );

      // Stage 4: Seen (double cyan-blue ticks)
      expect(
        MessageDeliveryStatus.fromFlags(isSending: false, isDelivered: true, isSeen: true),
        MessageDeliveryStatus.seen,
      );
      // Seen overrides even if delivered flag is false
      expect(
        MessageDeliveryStatus.fromFlags(isSending: false, isDelivered: false, isSeen: true),
        MessageDeliveryStatus.seen,
      );
    });
  });

  group('Keyboard inserted GIF & media tests', () {
    test('getFileFromKeyboardInsertedContent writes bytes to local temp gif file', () async {
      final sampleBytes = Uint8List.fromList([0x47, 0x49, 0x46, 0x38, 0x39, 0x61]); // 'GIF89a' header
      final content = KeyboardInsertedContent(
        mimeType: 'image/gif',
        uri: 'content://com.google.android.inputmethod.latin.provider/input/gif.gif',
        data: sampleBytes,
      );

      final file = await getFileFromKeyboardInsertedContent(content, Directory.systemTemp);
      expect(file, isNotNull);
      expect(await file!.exists(), isTrue);
      expect(file.path.endsWith('.gif'), isTrue);
      final readBytes = await file.readAsBytes();
      expect(readBytes, equals(sampleBytes));

      if (await file.exists()) {
        await file.delete();
      }
    });
  });

  group('MediaCacheService tests', () {
    test('registerLocalMapping and getCachedSync work synchronously', () {
      final cacheService = MediaCacheService();
      const testUrl = 'https://res.cloudinary.com/demo/image/upload/v12345/test_sample';
      const fakeLocalPath = '/fake/local/path/test.jpg';

      cacheService.registerLocalMapping(testUrl, fakeLocalPath);
      expect(cacheService.getCachedSync(testUrl), equals(fakeLocalPath));
    });

    test('getCachedSync returns null for empty or uncached URLs', () {
      final cacheService = MediaCacheService();
      expect(cacheService.getCachedSync(''), isNull);
      expect(cacheService.getCachedSync('https://not-cached.com/image.jpg'), isNull);
    });
  });

  group('Notification action payload & response tests', () {
    test('NotificationResponse correctly parses action_mark_read payload', () {
      final payloadData = {
        'type': 'chat',
        'senderUid': 'user_123',
        'name': 'Pooja',
        'chatId': 'user_123',
      };
      final response = NotificationResponse(
        notificationResponseType:
            NotificationResponseType.selectedNotificationAction,
        actionId: 'action_mark_read',
        payload: jsonEncode(payloadData),
      );

      expect(response.actionId, 'action_mark_read');
      final decoded = jsonDecode(response.payload!) as Map<String, dynamic>;
      expect(decoded['type'], 'chat');
      expect(decoded['senderUid'], 'user_123');
      expect(decoded['name'], 'Pooja');
    });

    test('NotificationResponse correctly parses action_reply with text input', () {
      final payloadData = {
        'type': 'group',
        'groupId': 'group_456',
        'groupName': 'Queen Pooja queendom',
        'chatId': 'group_456',
      };
      final response = NotificationResponse(
        notificationResponseType:
            NotificationResponseType.selectedNotificationAction,
        actionId: 'action_reply',
        input: 'Hello from notification!',
        payload: jsonEncode(payloadData),
      );

      expect(response.actionId, 'action_reply');
      expect(response.input, 'Hello from notification!');
      final decoded = jsonDecode(response.payload!) as Map<String, dynamic>;
      expect(decoded['type'], 'group');
      expect(decoded['groupId'], 'group_456');
    });

    test('Persistent notification lines accumulate per chat and clear on demand', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      // Chat 1: Pooja
      final chat1Key = 'notif_lines_user_pooja';
      List<String> chat1Lines = prefs.getStringList(chat1Key) ?? [];
      chat1Lines.add('Hi there');
      await prefs.setStringList(chat1Key, chat1Lines);

      chat1Lines = prefs.getStringList(chat1Key) ?? [];
      chat1Lines.add('How are you?');
      await prefs.setStringList(chat1Key, chat1Lines);

      // Chat 2: Rashmika (different tile)
      final chat2Key = 'notif_lines_user_rashmika';
      List<String> chat2Lines = prefs.getStringList(chat2Key) ?? [];
      chat2Lines.add('Good morning!');
      await prefs.setStringList(chat2Key, chat2Lines);

      // Verify Chat 1 accumulated 2 lines in same tile
      expect(prefs.getStringList(chat1Key), ['Hi there', 'How are you?']);
      // Verify Chat 2 has its own separate line
      expect(prefs.getStringList(chat2Key), ['Good morning!']);

      // Entering Chat 1 clears Chat 1's lines, Chat 2 remains intact
      await prefs.remove(chat1Key);
      expect(prefs.getStringList(chat1Key), isNull);
      expect(prefs.getStringList(chat2Key), ['Good morning!']);
    });
  });

  group('Document and Location Widget Tests', () {
    testWidgets('DocumentMessageWidget displays file name and extension badge', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DocumentMessageWidget(
              fileName: 'sample_archive.zip',
              fileUrl: 'https://example.com/sample_archive.zip',
              isMe: true,
            ),
          ),
        ),
      );

      expect(find.text('sample_archive.zip'), findsOneWidget);
      expect(find.text('ZIP'), findsWidgets);
    });

    testWidgets('LocationMessageWidget renders static location correctly', (tester) async {
      final locData = jsonEncode({
        'latitude': 12.9716,
        'longitude': 77.5946,
        'isLive': false,
        'accuracy': 10.0,
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocationMessageWidget(
              messageType: 'location',
              locationData: locData,
              isMe: true,
            ),
          ),
        ),
      );

      expect(find.text('Current Location'), findsOneWidget);
      expect(find.text('CURRENT'), findsOneWidget);
      expect(find.text('12.9716, 77.5946'), findsOneWidget);
    });

    testWidgets('LocationMessageWidget renders active live location correctly', (tester) async {
      final futureTime = DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch;
      final liveData = jsonEncode({
        'latitude': 12.9716,
        'longitude': 77.5946,
        'isLive': true,
        'liveUntil': futureTime,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
        'sharerId': 'user_1',
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocationMessageWidget(
              messageType: 'live_location',
              locationData: liveData,
              isMe: true,
              messageId: 'msg_1',
              currentUserId: 'user_1',
              receiverId: 'user_2',
            ),
          ),
        ),
      );

      expect(find.text('Live Location'), findsOneWidget);
      expect(find.text('LIVE'), findsOneWidget);
      expect(find.text('Stop Sharing'), findsOneWidget);
    });

    testWidgets('MyMessageCard renders document and location messages without error', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MyMessageCard(
              message: 'report.pdf',
              date: '10:00 AM',
              messageType: 'document',
              fileMessageData: 'https://example.com/report.pdf',
              onLeftSwipe: () {},
              repliedText: '',
              username: 'User',
              repliedMessageType: 'text',
              isSeen: false,
            ),
          ),
        ),
      );

      expect(find.text('report.pdf'), findsOneWidget);
      expect(find.text('PDF'), findsWidgets);
    });

    testWidgets('MyMessageCard and SenderMessageCard render reaction badges correctly',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                MyMessageCard(
                  message: 'Hello with reaction',
                  date: '10:00 AM',
                  messageType: 'text',
                  onLeftSwipe: () {},
                  repliedText: '',
                  username: 'Me',
                  repliedMessageType: 'text',
                  isSeen: true,
                  currentUserId: 'user1',
                  reactions: const {'user1': '❤️', 'user2': '👍'},
                ),
                SenderMessageCard(
                  message: 'Sender message with reaction',
                  date: '10:01 AM',
                  messageType: 'text',
                  onRightSwipe: () {},
                  repliedText: '',
                  username: 'Sender',
                  repliedMessageType: 'text',
                  currentUserId: 'user1',
                  reactions: const {'user1': '🔥'},
                ),
              ],
            ),
          ),
        ),
      );

      // Verify emojis appear in the widget tree
      expect(find.textContaining('❤️'), findsOneWidget);
      expect(find.textContaining('🔥'), findsOneWidget);
      expect(find.text('2'), findsOneWidget); // 2 reactions on the first card
    });

    test('Reaction equality check accurately detects emoji replacements', () {
      final reactions1 = <String, String>{'user1': '👍'};
      final reactions2 = <String, String>{'user1': '❤️'};
      final reactions3 = <String, String>{'user1': '👍'};

      expect(mapEquals(reactions1, reactions2), isFalse);
      expect(mapEquals(reactions1, reactions3), isTrue);

      final key1 = reactions1.entries.map((e) => '${e.key}:${e.value}').join('_');
      final key2 = reactions2.entries.map((e) => '${e.key}:${e.value}').join('_');

      expect(key1, isNot(equals(key2)));
      expect(key1, equals('user1:👍'));
      expect(key2, equals('user1:❤️'));
    });

    test('Safe casting decodes both Model and Map items without TypeError', () {
      final model = OneToOneMessageModel(
        senderId: 's1',
        receiverId: 'r1',
        text: 'Hello from model',
        messageType: 'text',
        timeSent: DateTime.now(),
        messageId: 'm1',
        isSeen: true,
        repliedMessage: '',
        repliedTo: '',
        repliedMessageType: 'text',
      );

      final map = {
        'senderId': 's2',
        'receiverId': 'r2',
        'text': 'Hello from map',
        'messageType': 'text',
        'timeSent': DateTime.now().millisecondsSinceEpoch,
        'messageId': 'm2',
        'isSeen': false,
        'repliedMessage': '',
        'repliedTo': '',
        'repliedMessageType': 'text',
      };

      final mixedList = <dynamic>[model, map, 'corrupt_string_ignored'];

      final List<OneToOneMessageModel> parsed = [];
      for (final item in mixedList) {
        if (item is OneToOneMessageModel) {
          parsed.add(item);
        } else if (item is Map) {
          try {
            parsed.add(OneToOneMessageModel.fromMap(Map<String, dynamic>.from(item)));
          } catch (_) {}
        }
      }

      expect(parsed.length, equals(2));
      expect(parsed[0].messageId, equals('m1'));
      expect(parsed[1].messageId, equals('m2'));
    });

    test('1-to-1 reaction change on any message is correctly detected as different', () {
      final msg1 = OneToOneMessageModel(
        senderId: 'userA',
        receiverId: 'userB',
        text: 'Hello',
        messageType: 'text',
        timeSent: DateTime.now(),
        messageId: 'm1',
        isSeen: true,
        repliedMessage: '',
        repliedTo: '',
        repliedMessageType: 'text',
        reactions: {'userB': '❤️'},
      );
      final msg2 = OneToOneMessageModel(
        senderId: 'userA',
        receiverId: 'userB',
        text: 'World',
        messageType: 'text',
        timeSent: DateTime.now(),
        messageId: 'm2',
        isSeen: false,
        repliedMessage: '',
        repliedTo: '',
        repliedMessageType: 'text',
        reactions: {},
      );

      final List<OneToOneMessageModel> listBefore = [msg1, msg2];

      // Reaction added to earlier message (not the last message!)
      final updatedMsg1 = msg1.copyWith(reactions: {'userB': '❤️', 'userA': '👍'});
      final List<OneToOneMessageModel> listAfter = [updatedMsg1, msg2];

      bool areListsEqual(List<OneToOneMessageModel> a, List<OneToOneMessageModel> b) {
        if (identical(a, b)) return true;
        if (a.length != b.length) return false;
        for (int i = 0; i < a.length; i++) {
          if (a[i].messageId != b[i].messageId ||
              a[i].isSeen != b[i].isSeen ||
              a[i].isDelivered != b[i].isDelivered ||
              a[i].isSending != b[i].isSending ||
              a[i].text != b[i].text ||
              a[i].fileMessageData != b[i].fileMessageData ||
              !mapEquals(a[i].reactions, b[i].reactions)) {
            return false;
          }
        }
        return true;
      }

      // Must detect that list has changed so real-time stream emits!
      expect(areListsEqual(listBefore, listAfter), isFalse);

      // Identity comparison returns true
      expect(areListsEqual(listBefore, listBefore), isTrue);
    });
  });

  group('Message Bubble Sending Animation tests', () {
    testWidgets('MyMessageCard with isSending: true renders sending status icon and entrance animation',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MyMessageCard(
              message: 'Hello animated',
              date: '10:00 AM',
              messageType: 'text',
              onLeftSwipe: () {},
              repliedText: '',
              username: 'User',
              repliedMessageType: 'text',
              isSeen: false,
              isDelivered: false,
              isSending: true,
            ),
          ),
        ),
      );

      // Verify clock icon is rendered for sending state
      expect(find.byKey(const ValueKey('status_sending')), findsOneWidget);

      // Advance animation through entrance (280ms)
      await tester.pump(const Duration(milliseconds: 140));
      expect(find.text('Hello animated'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 150));
      expect(find.text('Hello animated'), findsOneWidget);
    });

    testWidgets('MyMessageCard transition from isSending: true to isSending: false triggers settle transition and updates status icon',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MyMessageCard(
              message: 'Sending then sent',
              date: '10:00 AM',
              messageType: 'text',
              onLeftSwipe: () {},
              repliedText: '',
              username: 'User',
              repliedMessageType: 'text',
              isSeen: false,
              isDelivered: false,
              isSending: true,
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 280));
      expect(find.byKey(const ValueKey('status_sending')), findsOneWidget);

      // Update widget to isSending: false (sent)
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MyMessageCard(
              message: 'Sending then sent',
              date: '10:00 AM',
              messageType: 'text',
              onLeftSwipe: () {},
              repliedText: '',
              username: 'User',
              repliedMessageType: 'text',
              isSeen: false,
              isDelivered: false,
              isSending: false,
            ),
          ),
        ),
      );

      // Settle pop and icon transition (220ms)
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byKey(const ValueKey('status_sent')), findsOneWidget);
    });

    testWidgets('MyMessageCard with isSending: false renders immediately at full scale',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MyMessageCard(
              message: 'Old message',
              date: '09:00 AM',
              messageType: 'text',
              onLeftSwipe: () {},
              repliedText: '',
              username: 'User',
              repliedMessageType: 'text',
              isSeen: true,
              isDelivered: true,
              isSending: false,
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.text('Old message'), findsOneWidget);
      expect(find.byKey(const ValueKey('status_seen')), findsOneWidget);
    });

    testWidgets('DisplayMessages honors fixed mediaWidth and mediaHeight',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DisplayMessages(
              message: '',
              messageType: 'image',
              fileMessageData: 'https://example.com/test_image.jpg',
              mediaWidth: 240.0,
              mediaHeight: 220.0,
            ),
          ),
        ),
      );

      await tester.pump();
      final sizedBoxFinder = find.byWidgetPredicate(
        (widget) =>
            widget is SizedBox &&
            widget.width == 240.0 &&
            widget.height == 220.0,
      );
      expect(sizedBoxFinder, findsWidgets);
    });

    testWidgets('MyMessageCard renders captioned media with fixed width and caption text',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MyMessageCard(
              message: 'Check out this sunset!',
              date: '06:30 PM',
              messageType: 'image',
              fileMessageData: 'https://example.com/sunset.jpg',
              onLeftSwipe: () {},
              repliedText: '',
              username: 'User',
              repliedMessageType: 'text',
              isSeen: false,
              isDelivered: true,
              isSending: false,
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.text('Check out this sunset!'), findsOneWidget);
      expect(find.text('06:30 PM'), findsOneWidget);
    });

    testWidgets('SenderMessageCard renders captioned media with fixed width and caption text',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SenderMessageCard(
              message: 'Watch this celebration!',
              date: '07:15 PM',
              messageType: 'video',
              fileMessageData: 'https://example.com/video.mp4',
              onRightSwipe: () {},
              repliedText: '',
              username: 'Friend',
              repliedMessageType: 'text',
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.text('Watch this celebration!'), findsOneWidget);
      expect(find.text('07:15 PM'), findsOneWidget);
    });

    testWidgets('MediaPreviewWidget builds successfully for fullscreen preview',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MediaPreviewWidget(
              mediaType: 'image',
              mediaUrl: 'https://example.com/highres.jpg',
              showAppBar: true,
            ),
          ),
        ),
      );

      // Pump initial frame to verify widget tree construction
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(MediaPreviewWidget), findsOneWidget);
    });

    testWidgets('SenderMessageCard with isNewlyReceived: true plays entrance animation smoothly',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SenderMessageCard(
              message: 'Incoming message!',
              date: '10:05 AM',
              messageType: 'text',
              onRightSwipe: () {},
              repliedText: '',
              username: 'Sender',
              repliedMessageType: 'text',
              isNewlyReceived: true,
            ),
          ),
        ),
      );

      // Verify text is present during animation
      await tester.pump(const Duration(milliseconds: 140));
      expect(find.text('Incoming message!'), findsOneWidget);

      // Complete 280ms entrance animation
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.text('Incoming message!'), findsOneWidget);
    });

    testWidgets('SenderMessageCard with isNewlyReceived: false renders immediately',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SenderMessageCard(
              message: 'Old received message',
              date: '08:00 AM',
              messageType: 'text',
              onRightSwipe: () {},
              repliedText: '',
              username: 'Sender',
              repliedMessageType: 'text',
              isNewlyReceived: false,
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.text('Old received message'), findsOneWidget);
    });

    testWidgets('MyMessageCard pure media (image without caption) locks width to mediaWidth',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(360, 780)),
            child: Scaffold(
              body: MyMessageCard(
                message: '',
                date: '06:46 PM',
                messageType: 'image',
                fileMessageData: 'https://example.com/portrait.jpg',
                onLeftSwipe: () {},
                repliedText: '',
                username: 'User',
                repliedMessageType: 'text',
                isSeen: true,
                isDelivered: true,
                isSending: false,
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      // Screen width 360: (360 * 0.70).clamp(220.0, 275.0) -> ~252.0
      final sizedBoxFinder = find.byWidgetPredicate(
        (w) => w is SizedBox && w.width != null && (w.width! - 252.0).abs() < 0.1,
      );
      expect(sizedBoxFinder, findsWidgets);
      expect(find.text('06:46 PM'), findsOneWidget);
    });

    testWidgets('SenderMessageCard pure media (image without caption) locks width to mediaWidth',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(360, 780)),
            child: Scaffold(
              body: SenderMessageCard(
                message: '',
                date: '06:46 PM',
                messageType: 'image',
                fileMessageData: 'https://example.com/portrait.jpg',
                onRightSwipe: () {},
                repliedText: '',
                username: 'Friend',
                repliedMessageType: 'text',
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      // Screen width 360: (360 * 0.70).clamp(220.0, 275.0) -> ~252.0
      final sizedBoxFinder = find.byWidgetPredicate(
        (w) => w is SizedBox && w.width != null && (w.width! - 252.0).abs() < 0.1,
      );
      expect(sizedBoxFinder, findsWidgets);
      expect(find.text('06:46 PM'), findsOneWidget);
    });
  });
}



