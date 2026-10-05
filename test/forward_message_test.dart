import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_chat/features/chat/widgets/forward_message_sheet.dart';
import 'package:worship_chat/models/bookmark_model.dart';
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

      final bookmark = BookmarkModel(
        bookmarkId: 'bm-1',
        userId: 'u1',
        userName: 'Priya',
        userProfilePic: '',
        imageUrl: 'https://example.com/bm_pic.jpg',
        groupId: 'g1',
        groupName: 'Temple Worship',
        bookmarkedAt: DateTime.now(),
      );
      final bookmarkPayload = ForwardMessagePayload(
        text: '',
        messageType: 'image',
        fileMessageData: bookmark.imageUrl,
        isFromGallery: true,
        sourceGroupId: bookmark.groupId,
        sourceGroupName: bookmark.groupName.isNotEmpty
            ? bookmark.groupName
            : 'Bookmarks',
      );
      expect(bookmarkPayload.isImage, isTrue);
      expect(bookmarkPayload.isFromGallery, isTrue);
      expect(bookmarkPayload.effectiveMediaUrl,
          equals('https://example.com/bm_pic.jpg'));
      expect(bookmarkPayload.sourceGroupId, equals('g1'));
      expect(bookmarkPayload.sourceGroupName, equals('Temple Worship'));

      final bookmarkNoGroup = BookmarkModel(
        bookmarkId: 'bm-2',
        userId: 'u1',
        userName: 'Priya',
        userProfilePic: '',
        imageUrl: 'https://example.com/bm2.jpg',
        groupId: '',
        groupName: '',
        bookmarkedAt: DateTime.now(),
      );
      final bookmarkPayload2 = ForwardMessagePayload(
        text: '',
        messageType: 'image',
        fileMessageData: bookmarkNoGroup.imageUrl,
        isFromGallery: true,
        sourceGroupId: bookmarkNoGroup.groupId,
        sourceGroupName: bookmarkNoGroup.groupName.isNotEmpty
            ? bookmarkNoGroup.groupName
            : 'Bookmarks',
      );
      expect(bookmarkPayload2.sourceGroupName, equals('Bookmarks'));
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
