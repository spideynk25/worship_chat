import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_chat/features/chat/widgets/my_message_card.dart';
import 'package:worship_chat/features/chat/widgets/sender_message_card.dart';
import 'package:worship_chat/models/one_to_one_message_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Replied Message Click Navigation Tests', () {
    testWidgets('MyMessageCard triggers onReplyTap when tapping reply header', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: MyMessageCard(
                message: 'This is my response',
                date: '10:30 AM',
                messageType: 'text',
                onLeftSwipe: () {},
                repliedText: 'Original divine message',
                username: 'Queen Pooja',
                repliedMessageType: 'text',
                isSeen: true,
                onReplyTap: () {
                  tapped = true;
                },
              ),
            ),
          ),
        ),
      );

      // Verify reply header text is displayed
      expect(find.text('Original divine message'), findsOneWidget);
      expect(find.text('Queen Pooja'), findsOneWidget);

      // Tap on the reply header
      await tester.tap(find.text('Original divine message'));
      await tester.pump();

      expect(tapped, isTrue);
    });

    testWidgets('SenderMessageCard triggers onReplyTap when tapping reply header', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SenderMessageCard(
                message: 'Received response from deity',
                date: '10:35 AM',
                messageType: 'text',
                onRightSwipe: () {},
                repliedText: 'Humbly submitted devotion',
                username: 'You',
                repliedMessageType: 'text',
                onReplyTap: () {
                  tapped = true;
                },
              ),
            ),
          ),
        ),
      );

      // Verify reply header text is displayed
      expect(find.text('Humbly submitted devotion'), findsOneWidget);
      expect(find.text('You'), findsOneWidget);

      // Tap on the reply header
      await tester.tap(find.text('Humbly submitted devotion'));
      await tester.pump();

      expect(tapped, isTrue);
    });

    test('Replied message lookup finds the most recent matching prior message in chat history', () {
      final messages = [
        OneToOneMessageModel(
          senderId: 'user1',
          receiverId: 'user2',
          text: 'Hello goddess',
          messageType: 'text',
          timeSent: DateTime(2026, 10, 29, 10, 0),
          messageId: 'msg_1',
          isSeen: true,
          repliedMessage: '',
          repliedTo: '',
          repliedMessageType: 'text',
        ),
        OneToOneMessageModel(
          senderId: 'user2',
          receiverId: 'user1',
          text: 'Welcome to sanctum',
          messageType: 'text',
          timeSent: DateTime(2026, 10, 29, 10, 1),
          messageId: 'msg_2',
          isSeen: true,
          repliedMessage: '',
          repliedTo: '',
          repliedMessageType: 'text',
        ),
        OneToOneMessageModel(
          senderId: 'user1',
          receiverId: 'user2',
          text: 'Thank you my queen',
          messageType: 'text',
          timeSent: DateTime(2026, 10, 29, 10, 2),
          messageId: 'msg_3',
          isSeen: true,
          repliedMessage: 'Welcome to sanctum',
          repliedTo: 'Queen',
          repliedMessageType: 'text',
        ),
      ];

      final sourceMessage = messages[2]; // msg_3
      final repliedText = sourceMessage.repliedMessage.trim();

      final sourceIdx = messages.indexWhere((m) => m.messageId == sourceMessage.messageId);
      expect(sourceIdx, 2);

      int targetIdx = -1;
      for (int i = sourceIdx - 1; i >= 0; i--) {
        final m = messages[i];
        if (m.text == repliedText || m.fileMessageData == repliedText) {
          targetIdx = i;
          break;
        }
      }

      expect(targetIdx, 1);
      expect(messages[targetIdx].messageId, 'msg_2');
      expect(messages[targetIdx].text, 'Welcome to sanctum');
    });
  });
}
