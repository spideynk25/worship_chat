import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_chat/common/enums/message_status_enum.dart';
import 'package:worship_chat/features/chat/widgets/my_message_card.dart';
import 'package:worship_chat/features/chat/widgets/sender_message_card.dart';
import 'package:worship_chat/models/one_to_one_message_model.dart';
import 'package:worship_chat/models/group_chat_message_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:worship_chat/common/widgets/skeleton_loader.dart';
import 'package:worship_chat/common/widgets/user_avatar.dart';
import 'package:worship_chat/models/chat_contact.dart';
import 'package:worship_chat/models/user_model.dart';

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
}

