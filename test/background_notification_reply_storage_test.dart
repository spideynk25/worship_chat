import 'dart:convert';
import 'dart:io';
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
    tempDir = await Directory.systemTemp.createTemp('bg_reply_test_');
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
      'cached_current_user_name': 'My Royal Self',
      'cached_current_user_profile_pic': 'https://example.com/me.png',
    });
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Background Notification Reply Local Storage Tests', () {
    test('recordBackgroundReply buffers 1-to-1 reply in SharedPreferences immediately', () async {
      final chatId = 'user_me_123_receiver_456';
      final timeSent = DateTime(2026, 11, 23, 21, 30);
      final msgMap = {
        'senderId': 'user_me_123',
        'receiverId': 'receiver_456',
        'text': 'Replying from background notification!',
        'messageType': 'text',
        'timeSent': timeSent.millisecondsSinceEpoch,
        'messageId': 'bg_msg_001',
        'isSeen': false,
        'isDelivered': true,
        'repliedMessage': '',
        'repliedTo': '',
        'repliedMessageType': 'text',
      };

      await FirebaseNotificationService.recordBackgroundReply(
        chatId: chatId,
        isGroup: false,
        messageMap: msgMap,
        replyText: 'Replying from background notification!',
        timeSent: timeSent,
        receiverName: 'Pooja',
        receiverProfilePic: 'https://example.com/pooja.png',
        currentUserId: 'user_me_123',
      );

      // Verify SharedPreferences buffer
      final prefs = await SharedPreferences.getInstance();
      final bufferedList = prefs.getStringList('pending_bg_replies_$chatId');
      expect(bufferedList, isNotNull);
      expect(bufferedList!.length, 1);
      final decoded = jsonDecode(bufferedList.first) as Map<String, dynamic>;
      expect(decoded['messageId'], 'bg_msg_001');
      expect(decoded['text'], 'Replying from background notification!');

      final chatIds = prefs.getStringList('pending_bg_reply_chat_ids');
      expect(chatIds, isNotNull);
      expect(chatIds!.contains(chatId), isTrue);

      expect(prefs.getBool('bg_is_group_$chatId'), isFalse);
      expect(prefs.getString('bg_last_message_$chatId'), 'Replying from background notification!');

      // Verify getPendingBackgroundRepliesForChat returns buffered reply
      final pendingReplies =
          FirebaseNotificationService.getPendingBackgroundRepliesForChat<
              OneToOneMessageModel>(
        chatId: chatId,
        isGroup: false,
        prefs: prefs,
      );
      expect(pendingReplies.length, 1);
      expect(pendingReplies.first.messageId, 'bg_msg_001');
    });

    test('recordBackgroundReply buffers group reply in SharedPreferences immediately', () async {
      final groupId = 'group_queendom_789';
      final timeSent = DateTime(2026, 11, 23, 21, 35);
      final msgMap = {
        'senderId': 'user_me_123',
        'receiverIds': ['user_me_123', 'member_2'],
        'groupId': groupId,
        'text': 'Royal greetings from notification reply!',
        'messageType': 'text',
        'timeSent': timeSent.millisecondsSinceEpoch,
        'messageId': 'bg_grp_001',
        'isSeen': false,
        'isDelivered': true,
        'repliedMessage': '',
        'repliedTo': '',
        'repliedMessageType': 'text',
      };

      await FirebaseNotificationService.recordBackgroundReply(
        chatId: groupId,
        isGroup: true,
        messageMap: msgMap,
        replyText: 'Royal greetings from notification reply!',
        timeSent: timeSent,
        currentUserId: 'user_me_123',
      );

      final prefs = await SharedPreferences.getInstance();
      final bufferedList = prefs.getStringList('pending_bg_replies_$groupId');
      expect(bufferedList, isNotNull);
      expect(bufferedList!.length, 1);

      final pendingReplies =
          FirebaseNotificationService.getPendingBackgroundRepliesForChat<
              GroupChatMessageModel>(
        chatId: groupId,
        isGroup: true,
        prefs: prefs,
      );
      expect(pendingReplies.length, 1);
      expect(pendingReplies.first.messageId, 'bg_grp_001');
      expect(pendingReplies.first.text, 'Royal greetings from notification reply!');
    });

    test('syncPendingBackgroundRepliesToHive merges 1-to-1 reply into Hive and clears buffer', () async {
      final chatId = 'user_me_123_receiver_456';
      final timeSent = DateTime(2026, 11, 23, 21, 40);
      final msgMap = {
        'senderId': 'user_me_123',
        'receiverId': 'receiver_456',
        'text': 'Sync me into Hive!',
        'messageType': 'text',
        'timeSent': timeSent.millisecondsSinceEpoch,
        'messageId': 'bg_sync_001',
        'isSeen': false,
        'isDelivered': true,
        'repliedMessage': '',
        'repliedTo': '',
        'repliedMessageType': 'text',
      };

      // Buffer into SharedPreferences
      await FirebaseNotificationService.recordBackgroundReply(
        chatId: chatId,
        isGroup: false,
        messageMap: msgMap,
        replyText: 'Sync me into Hive!',
        timeSent: timeSent,
        receiverName: 'Pooja',
        currentUserId: 'user_me_123',
      );

      // Verify buffered
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('pending_bg_replies_$chatId')?.length, 1);

      // Now simulate main isolate syncing pending background replies
      await FirebaseNotificationService.syncPendingBackgroundRepliesToHive(
        specificChatId: chatId,
      );

      // Verify Hive 'messages' box has the message
      final box = Hive.box('messages');
      final list = box.get(chatId) as List;
      expect(list.length, 1);
      final savedMsg = list.first as OneToOneMessageModel;
      expect(savedMsg.messageId, 'bg_sync_001');
      expect(savedMsg.text, 'Sync me into Hive!');

      // Verify SharedPreferences buffer is now cleared
      expect(prefs.getStringList('pending_bg_replies_$chatId'), isNull);
      final chatIds = prefs.getStringList('pending_bg_reply_chat_ids') ?? [];
      expect(chatIds.contains(chatId), isFalse);
    });

    test('syncPendingBackgroundRepliesToHive merges group reply into Hive and clears buffer', () async {
      final groupId = 'group_queendom_789';
      final timeSent = DateTime(2026, 11, 23, 21, 45);
      final msgMap = {
        'senderId': 'user_me_123',
        'receiverIds': ['user_me_123', 'member_2'],
        'groupId': groupId,
        'text': 'Group background reply synced!',
        'messageType': 'text',
        'timeSent': timeSent.millisecondsSinceEpoch,
        'messageId': 'bg_grp_sync_001',
        'isSeen': false,
        'isDelivered': true,
        'repliedMessage': '',
        'repliedTo': '',
        'repliedMessageType': 'text',
      };

      await FirebaseNotificationService.recordBackgroundReply(
        chatId: groupId,
        isGroup: true,
        messageMap: msgMap,
        replyText: 'Group background reply synced!',
        timeSent: timeSent,
        currentUserId: 'user_me_123',
      );

      await FirebaseNotificationService.syncPendingBackgroundRepliesToHive(
        specificChatId: groupId,
      );

      final box = Hive.box('messages');
      final list = box.get(groupId) as List;
      expect(list.length, 1);
      final savedMsg = list.first as GroupChatMessageModel;
      expect(savedMsg.messageId, 'bg_grp_sync_001');
      expect(savedMsg.text, 'Group background reply synced!');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('pending_bg_replies_$groupId'), isNull);
    });
  });
}
