import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_chat/features/chat/widgets/forward_message_sheet.dart';
import 'package:worship_chat/models/chat_contact.dart';

void main() {
  group('ForwardMessagePayload tests', () {
    test('Correctly determines message types and preview titles', () {
      const textPayload = ForwardMessagePayload(
        text: 'Hello world',
        messageType: 'text',
      );
      expect(textPayload.isText, isTrue);
      expect(textPayload.isImage, isFalse);
      expect(textPayload.previewTitle, equals('Hello world'));

      const imagePayload = ForwardMessagePayload(
        text: 'https://example.com/pic.jpg',
        messageType: 'image',
        fileMessageData: '{"url":"https://example.com/pic.jpg"}',
        caption: 'Look at this photo',
      );
      expect(imagePayload.isImage, isTrue);
      expect(imagePayload.effectiveMediaUrl, equals('https://example.com/pic.jpg'));
      expect(imagePayload.caption, equals('Look at this photo'));

      const galleryPayload = ForwardMessagePayload(
        text: 'Flower',
        messageType: 'image',
        fileMessageData: 'https://example.com/flower.png',
        isFromGallery: true,
        sourceGroupId: 'group-123',
        sourceGroupName: 'Devotees',
      );
      expect(galleryPayload.isFromGallery, isTrue);
      expect(galleryPayload.sourceGroupId, equals('group-123'));
      expect(galleryPayload.sourceGroupName, equals('Devotees'));
      expect(galleryPayload.effectiveMediaUrl, equals('https://example.com/flower.png'));
    });

    test('ForwardTarget equality and hashcode compare id and type correctly', () {
      final contact1 = ChatContact(
        name: 'Devotee A',
        profilePic: '',
        uid: 'user-1',
        timeSent: DateTime.now(),
        lastMessage: '',
        fcmToken: '',
        unseenCount: false,
        chatBackgroundUrl: null,
      );

      final contact2 = ChatContact(
        name: 'Devotee A',
        profilePic: '',
        uid: 'user-1',
        timeSent: DateTime.now(),
        lastMessage: '',
        fcmToken: '',
        unseenCount: false,
        chatBackgroundUrl: null,
      );

      final target1 = ForwardTarget(
        id: contact1.uid,
        name: contact1.name,
        type: ForwardTargetType.directChat,
        data: contact1,
      );

      final target2 = ForwardTarget(
        id: contact2.uid,
        name: contact2.name,
        type: ForwardTargetType.directChat,
        data: contact2,
      );

      expect(target1, equals(target2));
      expect(target1.hashCode, equals(target2.hashCode));

      final targetGroupGallery = ForwardTarget(
        id: contact1.uid,
        name: contact1.name,
        type: ForwardTargetType.groupGallery,
        data: contact1,
      );

      expect(target1 == targetGroupGallery, isFalse);
    });

    testWidgets('ForwardMessageSheet builds without error', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ForwardMessageSheet(
                payload: ForwardMessagePayload(
                  text: 'Test message',
                  messageType: 'text',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Forward to...'), findsOneWidget);
    });
  });
}
