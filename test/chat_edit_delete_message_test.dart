import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_chat/common/providers/message_edit_provider.dart';
import 'package:worship_chat/features/chat/widgets/delete_message_dialog.dart';
import 'package:worship_chat/features/chat/widgets/message_edit_preview.dart';
import 'package:worship_chat/features/chat/widgets/my_message_card.dart';
import 'package:worship_chat/features/chat/widgets/sender_message_card.dart';
import 'package:worship_chat/models/group_chat_message_model.dart';
import 'package:worship_chat/models/one_to_one_message_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Message Models - Edit & Delete Fields', () {
    test('OneToOneMessageModel serialization and defaults', () {
      final now = DateTime.now();
      final msg = OneToOneMessageModel(
        senderId: 'user1',
        receiverId: 'user2',
        text: 'Hello world',
        messageType: 'text',
        timeSent: now,
        messageId: 'msg-1',
        isSeen: false,
        repliedMessage: '',
        repliedTo: '',
        repliedMessageType: '',
      );

      // Defaults
      expect(msg.isEdited, isFalse);
      expect(msg.isDeleted, isFalse);
      expect(msg.deletedFor, isEmpty);

      // toMap / fromMap roundtrip with defaults
      final map = msg.toMap();
      expect(map['isEdited'], isFalse);
      expect(map['isDeleted'], isFalse);
      expect(map['deletedFor'], isEmpty);

      final reconstructed = OneToOneMessageModel.fromMap(map);
      expect(reconstructed.isEdited, isFalse);
      expect(reconstructed.isDeleted, isFalse);
      expect(reconstructed.deletedFor, isEmpty);

      // With edit and delete flags set
      final edited = msg.copyWith(
        text: 'Edited text',
        isEdited: true,
      );
      expect(edited.text, equals('Edited text'));
      expect(edited.isEdited, isTrue);
      expect(edited.isDeleted, isFalse);

      final deleted = msg.copyWith(
        text: 'This message was deleted',
        isDeleted: true,
        deletedFor: ['user1'],
      );
      expect(deleted.isDeleted, isTrue);
      expect(deleted.deletedFor, contains('user1'));

      final deletedMap = deleted.toMap();
      final reconstructedDeleted = OneToOneMessageModel.fromMap(deletedMap);
      expect(reconstructedDeleted.isDeleted, isTrue);
      expect(reconstructedDeleted.deletedFor, contains('user1'));

      // Backward-compatible fallback for legacy maps without new keys
      final legacyMap = {
        'senderId': 'user1',
        'receiverId': 'user2',
        'text': 'Old message',
        'type': 'text',
        'timeSent': now.millisecondsSinceEpoch,
        'messageId': 'old-msg',
        'isSeen': true,
        'repliedMessage': '',
        'repliedTo': '',
        'repliedMessageType': '',
      };
      final fromLegacy = OneToOneMessageModel.fromMap(legacyMap);
      expect(fromLegacy.isEdited, isFalse);
      expect(fromLegacy.isDeleted, isFalse);
      expect(fromLegacy.deletedFor, isEmpty);
    });

    test('GroupChatMessageModel serialization and defaults', () {
      final now = DateTime.now();
      final groupMsg = GroupChatMessageModel(
        senderId: 'user1',
        receiverIds: ['user2', 'user3'],
        text: 'Group greetings',
        messageType: 'text',
        timeSent: now,
        messageId: 'grp-msg-1',
        groupId: 'grp-1',
        repliedMessage: '',
        repliedTo: '',
        repliedMessageType: '',
      );

      // Defaults
      expect(groupMsg.isEdited, isFalse);
      expect(groupMsg.isDeleted, isFalse);
      expect(groupMsg.deletedFor, isEmpty);

      // toMap / fromMap roundtrip
      final map = groupMsg.toMap();
      expect(map['isEdited'], isFalse);
      expect(map['isDeleted'], isFalse);
      expect(map['deletedFor'], isEmpty);

      final reconstructed = GroupChatMessageModel.fromMap(map);
      expect(reconstructed.isEdited, isFalse);
      expect(reconstructed.isDeleted, isFalse);
      expect(reconstructed.deletedFor, isEmpty);

      // copyWith edit and delete
      final updated = groupMsg.copyWith(
        text: 'Updated group text',
        isEdited: true,
        isDeleted: false,
        deletedFor: ['user3'],
      );
      expect(updated.text, equals('Updated group text'));
      expect(updated.isEdited, isTrue);
      expect(updated.deletedFor, contains('user3'));

      final updatedMap = updated.toMap();
      final fromUpdatedMap = GroupChatMessageModel.fromMap(updatedMap);
      expect(fromUpdatedMap.isEdited, isTrue);
      expect(fromUpdatedMap.deletedFor, contains('user3'));

      // Backward-compatible fallback
      final legacyMap = {
        'senderId': 'user1',
        'receiverIds': ['user2'],
        'text': 'Legacy group text',
        'type': 'text',
        'timeSent': now.millisecondsSinceEpoch,
        'messageId': 'legacy-grp-msg',
        'groupId': 'grp-1',
        'repliedMessage': '',
        'repliedTo': '',
        'repliedMessageType': '',
      };
      final fromLegacy = GroupChatMessageModel.fromMap(legacyMap);
      expect(fromLegacy.isEdited, isFalse);
      expect(fromLegacy.isDeleted, isFalse);
      expect(fromLegacy.deletedFor, isEmpty);
    });
  });

  group('DeleteMessageDialog Widget Tests', () {
    testWidgets('Shows Delete for Everyone and Delete for Me when isMyMessage is true', (tester) async {
      bool deletedForMe = false;
      bool deletedForEveryone = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DeleteMessageDialog(
              isMyMessage: true,
              isDeleted: false,
              onDeleteForMe: () => deletedForMe = true,
              onDeleteForEveryone: () => deletedForEveryone = true,
            ),
          ),
        ),
      );

      // Check title and options
      expect(find.text('Delete message?'), findsOneWidget);
      expect(find.text('Delete for everyone'), findsOneWidget);
      expect(find.text('Delete for me'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      // Tap Delete for everyone
      await tester.tap(find.text('Delete for everyone'));
      await tester.pumpAndSettle();
      expect(deletedForEveryone, isTrue);
      expect(deletedForMe, isFalse);
    });

    testWidgets('Shows only Delete for Me when isMyMessage is false', (tester) async {
      bool deletedForMe = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DeleteMessageDialog(
              isMyMessage: false,
              isDeleted: false,
              onDeleteForMe: () => deletedForMe = true,
              onDeleteForEveryone: null,
            ),
          ),
        ),
      );

      expect(find.text('Delete message?'), findsOneWidget);
      expect(find.text('Delete for everyone'), findsNothing);
      expect(find.text('Delete for me'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      await tester.tap(find.text('Delete for me'));
      await tester.pumpAndSettle();
      expect(deletedForMe, isTrue);
    });

    testWidgets('Shows only Delete for Me when message is already deleted', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DeleteMessageDialog(
              isMyMessage: true,
              isDeleted: true,
              onDeleteForMe: () {},
              onDeleteForEveryone: () {},
            ),
          ),
        ),
      );

      // If already deleted for everyone, only "Delete for me" should be available
      expect(find.text('Delete for everyone'), findsNothing);
      expect(find.text('Delete for me'), findsOneWidget);
    });
  });

  group('MessageEditPreview Widget Tests', () {
    testWidgets('Renders Edit Message banner and handles cancel tap', (tester) async {
      bool cancelled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageEditPreview(
              text: 'Original message before editing',
              onCancel: () => cancelled = true,
            ),
          ),
        ),
      );

      expect(find.text('Edit Message'), findsOneWidget);
      expect(find.text('Original message before editing'), findsOneWidget);
      expect(find.byIcon(Icons.edit_rounded), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();
      expect(cancelled, isTrue);
    });
  });

  group('Message Cards Deleted & Edited UI Tests', () {
    testWidgets('MyMessageCard renders deleted message state', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: MyMessageCard(
                message: '🚫 This message was deleted',
                date: '10:30 AM',
                messageType: 'text',
                repliedText: '',
                username: '',
                repliedMessageType: '',
                onLeftSwipe: _dummyCallback,
                isSeen: true,
                isDeleted: true,
              ),
            ),
          ),
        ),
      );

      expect(find.text('This message was deleted'), findsOneWidget);
      expect(find.textContaining('🚫'), findsNothing);
      expect(find.byIcon(Icons.block_flipped), findsOneWidget);
    });

    testWidgets('MyMessageCard renders edited indicator when isEdited is true', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: MyMessageCard(
                message: 'Edited message text',
                date: '10:30 AM',
                messageType: 'text',
                repliedText: '',
                username: '',
                repliedMessageType: '',
                onLeftSwipe: _dummyCallback,
                isSeen: true,
                isEdited: true,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Edited message text'), findsOneWidget);
      expect(find.text('edited'), findsOneWidget);
    });

    testWidgets('SenderMessageCard renders deleted message state', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SenderMessageCard(
                message: '🚫 This message was deleted',
                date: '10:35 AM',
                messageType: 'text',
                repliedText: '',
                username: 'Friend',
                repliedMessageType: '',
                onRightSwipe: _dummyCallback,
                isDeleted: true,
              ),
            ),
          ),
        ),
      );

      expect(find.text('This message was deleted'), findsOneWidget);
      expect(find.textContaining('🚫'), findsNothing);
      expect(find.byIcon(Icons.block_flipped), findsOneWidget);
    });

    testWidgets('SenderMessageCard renders edited indicator when isEdited is true', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SenderMessageCard(
                message: 'Friend edited text',
                date: '10:35 AM',
                messageType: 'text',
                repliedText: '',
                username: 'Friend',
                repliedMessageType: '',
                onRightSwipe: _dummyCallback,
                isEdited: true,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Friend edited text'), findsOneWidget);
      expect(find.text('edited'), findsOneWidget);
    });
  });
}

void _dummyCallback() {}
