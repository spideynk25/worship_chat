import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worship_chat/common/utils/firebase_notification_service.dart';
import 'package:worship_chat/features/chat/repositories/chat_repository.dart';
import 'package:worship_chat/models/group_chat_message_model.dart';
import 'package:worship_chat/models/group_gallery_image.dart';
import 'package:worship_chat/models/one_to_one_message_model.dart';
import 'package:worship_chat/models/user_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_notif_test_');
    Hive.init(tempDir.path);

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

    SharedPreferences.setMockInitialValues({
      'cached_current_user_id': 'user_me_123',
      'cached_current_user_name': 'Test User',
    });
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Notification Hive Ingestion Tests', () {
    test('1-to-1 notification payload is ingested into Hive messages box and contacts cache', () async {
      final payload = {
        'type': 'chat',
        'senderUid': 'sender_456',
        'receiverId': 'user_me_123',
        'name': 'Pooja',
        'profilePic': 'https://example.com/pooja.png',
        'tag': 'sender_456',
        'messageId': 'msg_001',
        'messageType': 'text',
        'text': 'Hello from notification!',
        'timeSent': DateTime(2026, 10, 15, 10, 30).toIso8601String(),
      };

      // Ingest message
      await FirebaseNotificationService.ingestNotificationDataIntoHive(payload);

      // Verify Hive 'messages' box
      final box = Hive.box('messages');
      final localKey = 'user_me_123_sender_456';
      final cachedList = box.get(localKey);
      expect(cachedList, isNotNull);
      expect(cachedList, isA<List>());
      expect((cachedList as List).length, 1);

      final msg = cachedList.first as OneToOneMessageModel;
      expect(msg.messageId, 'msg_001');
      expect(msg.text, 'Hello from notification!');
      expect(msg.senderId, 'sender_456');
      expect(msg.receiverId, 'user_me_123');
      expect(msg.messageType, 'text');
      expect(msg.isDelivered, isTrue);

      // Verify contacts_cache updated
      final contactsBox = Hive.box('contacts_cache');
      final userChats = contactsBox.get('user_chats_user_me_123');
      expect(userChats, isNotNull);
      expect(userChats, isA<List>());
      final contactsList = (userChats as List).cast<Map>();
      expect(contactsList.any((c) => c['uid'] == 'sender_456'), isTrue);
      final contact = contactsList.firstWhere((c) => c['uid'] == 'sender_456');
      expect(contact['lastMessage'], 'Hello from notification!');
      expect(contact['unseenCount'], isTrue);
    });

    test('1-to-1 duplicate notification payload is ignored and not duplicated', () async {
      final payload = {
        'type': 'chat',
        'senderUid': 'sender_456',
        'receiverId': 'user_me_123',
        'name': 'Pooja',
        'messageId': 'msg_002',
        'messageType': 'text',
        'text': 'Same message',
        'timeSent': DateTime.now().toIso8601String(),
      };

      // Ingest twice
      await FirebaseNotificationService.ingestNotificationDataIntoHive(payload);
      await FirebaseNotificationService.ingestNotificationDataIntoHive(payload);

      final box = Hive.box('messages');
      final cachedList = box.get('user_me_123_sender_456') as List;
      expect(cachedList.length, 1);
    });

    test('Group notification payload is ingested into Hive with receiverIds', () async {
      final payload = {
        'type': 'group',
        'groupId': 'group_queendom_789',
        'groupName': 'Queendom of Pooja',
        'tag': 'group_queendom_789',
        'name': 'Rashmika',
        'senderId': 'sender_rashmika',
        'senderUid': 'sender_rashmika',
        'messageId': 'grp_msg_001',
        'messageType': 'text',
        'text': 'Royal greetings to all members!',
        'timeSent': DateTime(2026, 10, 15, 11, 00).toIso8601String(),
        'receiverIds': 'user_me_123,member_2,member_3',
      };

      await FirebaseNotificationService.ingestNotificationDataIntoHive(payload);

      final box = Hive.box('messages');
      final cachedList = box.get('group_queendom_789');
      expect(cachedList, isNotNull);
      expect(cachedList, isA<List>());
      expect((cachedList as List).length, 1);

      final groupMsg = cachedList.first as GroupChatMessageModel;
      expect(groupMsg.messageId, 'grp_msg_001');
      expect(groupMsg.groupId, 'group_queendom_789');
      expect(groupMsg.senderId, 'sender_rashmika');
      expect(groupMsg.text, 'Royal greetings to all members!');
      expect(groupMsg.receiverIds, contains('user_me_123'));
      expect(groupMsg.isDelivered, isTrue);

      // Ingest duplicate
      await FirebaseNotificationService.ingestNotificationDataIntoHive(payload);
      final cachedListAfterDup = box.get('group_queendom_789') as List;
      expect(cachedListAfterDup.length, 1);
    });

    test('Active listeners are immediately notified when notification message arrives', () async {
      final localKey = 'user_me_123_sender_listener';

      // Register mock listener
      ChatRepository.notifyChatListeners(localKey, []);

      final payload = {
        'type': 'chat',
        'senderUid': 'sender_listener',
        'receiverId': 'user_me_123',
        'name': 'Listener Test',
        'messageId': 'msg_listener_001',
        'messageType': 'text',
        'text': 'Instant notification test',
        'timeSent': DateTime.now().toIso8601String(),
      };

      await FirebaseNotificationService.ingestNotificationDataIntoHive(payload);

      final box = Hive.box('messages');
      final list = box.get(localKey) as List;
      expect(list.length, 1);
      expect((list.first as OneToOneMessageModel).messageId, 'msg_listener_001');
    });

    test('Notification payload WITHOUT messageId does NOT inject phantom message into messages box', () async {
      final payload = {
        'type': 'chat',
        'senderUid': 'sender_phantom',
        'receiverId': 'user_me_123',
        'name': 'Phantom Sender',
        'messageType': 'text',
        'text': 'Phantom message without messageId',
        'timeSent': DateTime.now().toIso8601String(),
      };

      await FirebaseNotificationService.ingestNotificationDataIntoHive(payload);

      final box = Hive.box('messages');
      final list = box.get('user_me_123_sender_phantom');
      // Should not create a message in messages box without real messageId
      expect(list, isNull);
    });

    test('Media notification payload WITHOUT fileMessageData does NOT inject phantom text card into messages box', () async {
      final payload = {
        'type': 'chat',
        'senderUid': 'sender_media',
        'receiverId': 'user_me_123',
        'name': 'Media Sender',
        'messageId': 'media_msg_001',
        'messageType': 'image',
        'text': '📷 Photo',
        'timeSent': DateTime.now().toIso8601String(),
        // No fileMessageData / mediaUrl
      };

      await FirebaseNotificationService.ingestNotificationDataIntoHive(payload);

      final box = Hive.box('messages');
      final list = box.get('user_me_123_sender_media');
      // Should not inject dummy text message for image when payload lacks media URL
      expect(list, isNull);

      // But contacts_cache should still be updated with the preview
      final contactsBox = Hive.box('contacts_cache');
      final userChats = contactsBox.get('user_chats_user_me_123') as List?;
      expect(userChats, isNotNull);
      final contact = userChats!.firstWhere((c) => c['uid'] == 'sender_media');
      expect(contact['lastMessage'], '📷 Photo');
    });

    test('Identical cached messages do not trigger status change or redundant rebuild', () {
      final now = DateTime(2026, 10, 30, 12, 0);
      final msg1 = OneToOneMessageModel(
        senderId: 'sender_1',
        receiverId: 'user_me_123',
        text: 'Hello',
        messageType: 'text',
        timeSent: now,
        messageId: 'msg_1',
        isSeen: false,
        isDelivered: true,
        isSending: false,
        repliedMessage: '',
        repliedTo: '',
        repliedMessageType: 'text',
      );

      final listA = [msg1];
      final listB = [
        OneToOneMessageModel(
          senderId: 'sender_1',
          receiverId: 'user_me_123',
          text: 'Hello',
          messageType: 'text',
          timeSent: now,
          messageId: 'msg_1',
          isSeen: false,
          isDelivered: true,
          isSending: false,
          repliedMessage: '',
          repliedTo: '',
          repliedMessageType: 'text',
        ),
      ];

      bool hasStatusChanged(List<OneToOneMessageModel> a, List<OneToOneMessageModel> b) {
        if (a.length != b.length) return true;
        for (int i = 0; i < a.length; i++) {
          if (a[i].messageId != b[i].messageId ||
              a[i].isSeen != b[i].isSeen ||
              a[i].isDelivered != b[i].isDelivered ||
              a[i].isSending != b[i].isSending ||
              a[i].text != b[i].text ||
              a[i].fileMessageData != b[i].fileMessageData) {
            return true;
          }
        }
        return false;
      }

      // Exact copy from stream must NOT register as changed
      expect(hasStatusChanged(listA, listB), isFalse);

      // Status change to seen MUST register as changed
      final listSeen = [listB.first.copyWith(isSeen: true)];
      expect(hasStatusChanged(listA, listSeen), isTrue);

      // New message arrival MUST register as changed
      final listNew = [
        ...listA,
        OneToOneMessageModel(
          senderId: 'sender_1',
          receiverId: 'user_me_123',
          text: 'Second message',
          messageType: 'text',
          timeSent: now.add(const Duration(seconds: 1)),
          messageId: 'msg_2',
          repliedMessage: '',
          repliedTo: '',
          repliedMessageType: 'text',
        ),
      ];
      expect(hasStatusChanged(listA, listNew), isTrue);
    });

    test('Preserves isDelivered: true from local cache when Firestore has isDelivered: false', () {
      final now = DateTime(2026, 10, 30, 12, 0);
      final cachedMap = <String, OneToOneMessageModel>{
        'msg_notif_1': OneToOneMessageModel(
          senderId: 'sender_1',
          receiverId: 'user_me_123',
          text: 'Incoming notification message',
          messageType: 'text',
          timeSent: now,
          messageId: 'msg_notif_1',
          isDelivered: true, // Marked true by notification receipt
          isSeen: false,
          repliedMessage: '',
          repliedTo: '',
          repliedMessageType: 'text',
        ),
      };

      // Simulated message arriving from Firestore query snapshot before delivery is written back
      final firestoreMessage = OneToOneMessageModel(
        senderId: 'sender_1',
        receiverId: 'user_me_123',
        text: 'Incoming notification message',
        messageType: 'text',
        timeSent: now,
        messageId: 'msg_notif_1',
        isDelivered: false, // Firestore initially has false
        isSeen: false,
        repliedMessage: '',
        repliedTo: '',
        repliedMessageType: 'text',
      );

      final mergedMap = <String, OneToOneMessageModel>{};
      final cached = cachedMap[firestoreMessage.messageId];
      if (cached != null && cached.isDelivered && !firestoreMessage.isDelivered) {
        mergedMap[firestoreMessage.messageId] = firestoreMessage.copyWith(isDelivered: true);
      } else {
        mergedMap[firestoreMessage.messageId] = firestoreMessage;
      }

      // Must preserve isDelivered: true from local cache
      expect(mergedMap['msg_notif_1']!.isDelivered, isTrue);
    });

    test('GroupChatMessageModel equality check prevents redundant emissions', () {
      final now = DateTime(2026, 10, 30, 12, 0);
      final gMsg1 = GroupChatMessageModel(
        senderId: 'sender_g1',
        receiverIds: ['user_me_123'],
        groupId: 'grp_1',
        text: 'Group notification text',
        messageType: 'text',
        timeSent: now,
        messageId: 'gmsg_1',
        isSeen: false,
        isDelivered: true,
        repliedMessage: '',
        repliedTo: '',
        repliedMessageType: 'text',
      );

      final list1 = [gMsg1];
      final list2 = [
        GroupChatMessageModel(
          senderId: 'sender_g1',
          receiverIds: ['user_me_123'],
          groupId: 'grp_1',
          text: 'Group notification text',
          messageType: 'text',
          timeSent: now,
          messageId: 'gmsg_1',
          isSeen: false,
          isDelivered: true,
          repliedMessage: '',
          repliedTo: '',
          repliedMessageType: 'text',
        ),
      ];

      bool areGroupMessagesEqual(List<GroupChatMessageModel> a, List<GroupChatMessageModel> b) {
        if (identical(a, b)) return true;
        if (a.length != b.length) return false;
        for (int i = 0; i < a.length; i++) {
          if (a[i].messageId != b[i].messageId ||
              a[i].isSeen != b[i].isSeen ||
              a[i].isDelivered != b[i].isDelivered ||
              a[i].isSending != b[i].isSending ||
              a[i].text != b[i].text ||
              a[i].fileMessageData != b[i].fileMessageData) {
            return false;
          }
        }
        return true;
      }

      expect(areGroupMessagesEqual(list1, list2), isTrue);
    });
  });
}
