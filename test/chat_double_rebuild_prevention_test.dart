import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worship_chat/common/utils/firebase_notification_service.dart';
import 'package:worship_chat/models/group_chat_message_model.dart';
import 'package:worship_chat/models/group_gallery_image.dart';
import 'package:worship_chat/models/one_to_one_message_model.dart';
import 'package:worship_chat/models/user_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_rebuild_test_');
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

  group('Background Message Double Rebuild Prevention Tests', () {
    test('1-to-1 background message: opening chat marks message seen optimistically without rebuild loop', () async {
      final currentUserId = 'user_me_123';
      final partnerId = 'sender_456';

      // 1. Ingest background notification message into Hive while chat is not focused
      final payload = {
        'type': 'chat',
        'senderUid': partnerId,
        'receiverId': currentUserId,
        'name': 'Pooja',
        'messageId': 'msg_bg_001',
        'messageType': 'text',
        'text': 'Hello while chat was unfocused!',
        'timeSent': DateTime(2026, 11, 22, 10, 00).toIso8601String(),
      };
      await FirebaseNotificationService.ingestNotificationDataIntoHive(payload);

      final box = Hive.box('messages');
      final localKey = '${currentUserId}_$partnerId';
      final cachedList = box.get(localKey) as List;
      expect(cachedList.length, 1);

      // In Hive, message arrives with isSeen: false
      final bgMsg = cachedList.first as OneToOneMessageModel;
      expect(bgMsg.isSeen, isFalse);

      // 2. Simulate opening chat: _loadInitialCachedMessages()
      final List<OneToOneMessageModel> displayMessages = [];
      bool hasUnseenIncoming = false;

      for (final item in cachedList) {
        OneToOneMessageModel? m;
        if (item is OneToOneMessageModel) {
          m = item;
        }
        if (m != null) {
          if (m.receiverId == currentUserId && (!m.isSeen || !m.isDelivered)) {
            hasUnseenIncoming = true;
            m = m.copyWith(isSeen: true, isDelivered: true);
          }
          displayMessages.add(m);
        }
      }

      expect(hasUnseenIncoming, isTrue);
      expect(displayMessages.first.isSeen, isTrue);

      // 3. Status comparison function (_hasDeliveryOrSeenStatusChanged)
      bool hasStatusChanged(List<OneToOneMessageModel> display, List<OneToOneMessageModel> newMsgs) {
        if (display.length != newMsgs.length) return true;
        for (int i = 0; i < newMsgs.length; i++) {
          final oldMsg = display[i];
          final newMsg = newMsgs[i];
          if (oldMsg.messageId != newMsg.messageId ||
              oldMsg.text != newMsg.text ||
              oldMsg.fileMessageData != newMsg.fileMessageData ||
              oldMsg.isEdited != newMsg.isEdited ||
              oldMsg.isDeleted != newMsg.isDeleted ||
              !mapEquals(oldMsg.reactions, newMsg.reactions)) {
            return true;
          }
          if (oldMsg.senderId == currentUserId) {
            if (oldMsg.isSeen != newMsg.isSeen ||
                oldMsg.isDelivered != newMsg.isDelivered ||
                oldMsg.isSending != newMsg.isSending) {
              return true;
            }
          }
        }
        return false;
      }

      // 4. When Firestore snapshot arrives with isSeen: true
      final firestoreSnapshotMessages = [
        bgMsg.copyWith(isSeen: true, isDelivered: true),
      ];

      // Must NOT report change because displayMessages is already seen
      expect(hasStatusChanged(displayMessages, firestoreSnapshotMessages), isFalse);

      // Even if Firestore snapshot had isSeen: false initially, incoming messages
      // never trigger a visual change for the receiver
      final firestoreSnapshotInitial = [
        bgMsg.copyWith(isSeen: false, isDelivered: true),
      ];
      expect(hasStatusChanged(displayMessages, firestoreSnapshotInitial), isFalse);
    });

    test('Group background message: opening chat marks message seen optimistically without rebuild loop', () async {
      final currentUserId = 'user_me_123';
      final groupId = 'group_queendom_789';

      // 1. Ingest group notification into Hive
      final payload = {
        'type': 'group',
        'groupId': groupId,
        'groupName': 'Queendom of Pooja',
        'name': 'Rashmika',
        'senderId': 'sender_rashmika',
        'senderUid': 'sender_rashmika',
        'messageId': 'grp_bg_001',
        'messageType': 'text',
        'text': 'Group message while unfocused!',
        'timeSent': DateTime(2026, 11, 22, 10, 30).toIso8601String(),
        'receiverIds': 'user_me_123,other_user',
      };
      await FirebaseNotificationService.ingestNotificationDataIntoHive(payload);

      final box = Hive.box('messages');
      final cachedList = box.get(groupId) as List;
      expect(cachedList.length, 1);

      // 2. Simulate opening group chat: _loadInitialCachedMessages()
      final List<GroupChatMessageModel> displayMessages = [];
      bool hasUnseenIncoming = false;

      for (final item in cachedList) {
        GroupChatMessageModel? m;
        if (item is GroupChatMessageModel) {
          m = item;
        }
        if (m != null) {
          if (m.senderId != currentUserId && (!m.isSeen || !m.isDelivered)) {
            hasUnseenIncoming = true;
            m = m.copyWith(isSeen: true, isDelivered: true);
          }
          displayMessages.add(m);
        }
      }

      expect(hasUnseenIncoming, isTrue);
      expect(displayMessages.first.isSeen, isTrue);

      // 3. Status comparison function (_hasDeliveryOrSeenStatusChanged)
      bool hasStatusChanged(List<GroupChatMessageModel> display, List<GroupChatMessageModel> newMsgs) {
        if (display.length != newMsgs.length) return true;
        for (int i = 0; i < newMsgs.length; i++) {
          final oldMsg = display[i];
          final newMsg = newMsgs[i];
          if (oldMsg.messageId != newMsg.messageId ||
              oldMsg.text != newMsg.text ||
              oldMsg.fileMessageData != newMsg.fileMessageData ||
              oldMsg.isEdited != newMsg.isEdited ||
              oldMsg.isDeleted != newMsg.isDeleted ||
              !mapEquals(oldMsg.reactions, newMsg.reactions)) {
            return true;
          }
          if (oldMsg.senderId == currentUserId) {
            if (oldMsg.isSeen != newMsg.isSeen ||
                oldMsg.isDelivered != newMsg.isDelivered ||
                oldMsg.isSending != newMsg.isSending) {
              return true;
            }
          }
        }
        return false;
      }

      // 4. When Firestore snapshot arrives with isSeen: true
      final firestoreGroupMessages = [
        (cachedList.first as GroupChatMessageModel).copyWith(isSeen: true, isDelivered: true),
      ];

      expect(hasStatusChanged(displayMessages, firestoreGroupMessages), isFalse);
    });

    test('Outgoing messages still correctly trigger rebuild when receiver marks them seen', () {
      final currentUserId = 'user_me_123';
      final now = DateTime(2026, 11, 22, 11, 00);

      final myMessage = OneToOneMessageModel(
        senderId: currentUserId, // Sent by ME
        receiverId: 'partner_456',
        text: 'Hello partner!',
        messageType: 'text',
        timeSent: now,
        messageId: 'my_msg_001',
        isDelivered: true,
        isSeen: false, // Not yet seen by partner
        repliedMessage: '',
        repliedTo: '',
        repliedMessageType: 'text',
      );

      final displayMessages = [myMessage];

      bool hasStatusChanged(List<OneToOneMessageModel> display, List<OneToOneMessageModel> newMsgs) {
        if (display.length != newMsgs.length) return true;
        for (int i = 0; i < newMsgs.length; i++) {
          final oldMsg = display[i];
          final newMsg = newMsgs[i];
          if (oldMsg.messageId != newMsg.messageId ||
              oldMsg.text != newMsg.text ||
              oldMsg.fileMessageData != newMsg.fileMessageData ||
              oldMsg.isEdited != newMsg.isEdited ||
              oldMsg.isDeleted != newMsg.isDeleted ||
              !mapEquals(oldMsg.reactions, newMsg.reactions)) {
            return true;
          }
          if (oldMsg.senderId == currentUserId) {
            if (oldMsg.isSeen != newMsg.isSeen ||
                oldMsg.isDelivered != newMsg.isDelivered ||
                oldMsg.isSending != newMsg.isSending) {
              return true;
            }
          }
        }
        return false;
      }

      // Partner reads message: isSeen changes from false to true
      final partnerReadMessages = [
        myMessage.copyWith(isSeen: true),
      ];

      // MUST trigger rebuild so MyMessageCard shows the blue double ticks!
      expect(hasStatusChanged(displayMessages, partnerReadMessages), isTrue);
    });
  });
}
