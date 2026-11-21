import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_handler/share_handler.dart';
import 'package:worship_chat/common/utils/share_intent_service.dart';
import 'package:worship_chat/features/share/screens/share_upload_screen.dart';
import 'package:worship_chat/features/group/controller/group_controller.dart';
import 'package:worship_chat/features/chat/controller/chat_controller.dart';
import 'package:worship_chat/models/group.dart';
import 'package:worship_chat/models/chat_contact.dart';

// Dummy group controller for mock streams
class _MockGroupController implements GroupController {
  @override
  Stream<List<GroupModel>> chatGroups() => Stream.value([]);
  @override
  Stream<List<GroupModel>> getQueenPoojaStream() => Stream.value([]);
  @override
  Stream<List<GroupModel>> getQueenRashmikaStream() => Stream.value([]);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _MockChatController implements ChatController {
  @override
  Stream<List<ChatContact>> chatContacts() => Stream.value([]);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  group('SharedPayload unit tests', () {
    test('Correctly identifies YouTube links and properties', () {
      final media = SharedMedia(
        content: 'Check out this video: https://youtu.be/dQw4w9WgXcQ',
      );
      final payload = extractSharedPayload(media);

      expect(payload.isYouTube, isTrue);
      expect(payload.isXTwitter, isFalse);
      expect(payload.isTextOnly, isTrue);
      expect(payload.canUploadToGallery, isFalse);
      expect(payload.displayTitle, equals('YouTube Link'));
      expect(payload.type, equals(SharedPayloadType.text));
    });

    test('Correctly identifies YouTube full URL links', () {
      final media = SharedMedia(
        content: 'https://www.youtube.com/watch?v=12345678',
      );
      final payload = extractSharedPayload(media);

      expect(payload.isYouTube, isTrue);
      expect(payload.isTextOnly, isTrue);
      expect(payload.displayTitle, equals('YouTube Link'));
    });

    test('Correctly identifies X / Twitter links', () {
      final media = SharedMedia(
        content: 'Look at this tweet! https://x.com/flutterdev/status/12345',
      );
      final payload = extractSharedPayload(media);

      expect(payload.isXTwitter, isTrue);
      expect(payload.isYouTube, isFalse);
      expect(payload.isTextOnly, isTrue);
      expect(payload.canUploadToGallery, isFalse);
      expect(payload.displayTitle, equals('X / Twitter Post'));
    });

    test('Correctly identifies Twitter classic domain', () {
      final media = SharedMedia(
        content: 'https://twitter.com/flutterdev/status/99999',
      );
      final payload = extractSharedPayload(media);

      expect(payload.isXTwitter, isTrue);
      expect(payload.displayTitle, equals('X / Twitter Post'));
    });

    test('Correctly identifies generic Web Links', () {
      final media = SharedMedia(
        content: 'https://flutter.dev/docs',
      );
      final payload = extractSharedPayload(media);

      expect(payload.isWebLink, isTrue);
      expect(payload.isYouTube, isFalse);
      expect(payload.isXTwitter, isFalse);
      expect(payload.displayTitle, equals('Web Link'));
    });

    test('Correctly identifies plain shared text', () {
      final media = SharedMedia(
        content: 'Good morning devotees of the Queendom!',
      );
      final payload = extractSharedPayload(media);

      expect(payload.isTextOnly, isTrue);
      expect(payload.isWebLink, isFalse);
      expect(payload.displayTitle, equals('Shared Text'));
    });

    test('Correctly identifies photo attachments', () {
      final media = SharedMedia(
        attachments: [
          SharedAttachment(path: '/storage/photo1.jpg', type: SharedAttachmentType.image),
          SharedAttachment(path: '/storage/photo2.png', type: SharedAttachmentType.image),
        ],
      );
      final payload = extractSharedPayload(media);

      expect(payload.isMedia, isTrue);
      expect(payload.canUploadToGallery, isTrue);
      expect(payload.type, equals(SharedPayloadType.image));
      expect(payload.files.length, equals(2));
      expect(payload.displayTitle, equals('2 Photos'));
    });

    test('Correctly identifies video attachments', () {
      final media = SharedMedia(
        attachments: [
          SharedAttachment(path: '/storage/video.mp4', type: SharedAttachmentType.video),
        ],
      );
      final payload = extractSharedPayload(media);

      expect(payload.isMedia, isTrue);
      expect(payload.type, equals(SharedPayloadType.video));
      expect(payload.canUploadToGallery, isFalse);
      expect(payload.displayTitle, equals('1 Video'));
    });
  });

  group('ShareUploadScreen Widget tests', () {
    testWidgets('renders modern Queendom branding and YouTube preview', (tester) async {
      const youtubePayload = SharedPayload(
        text: 'https://youtu.be/test_id',
        type: SharedPayloadType.text,
      );

      final mockGroup = _MockGroupController();
      final mockChat = _MockChatController();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            groupControllerProvider.overrideWithValue(mockGroup as dynamic),
            chatControllerProvider.overrideWithValue(mockChat as dynamic),
          ],
          child: const MaterialApp(
            home: ShareUploadScreen(
              payload: youtubePayload,
            ),
          ),
        ),
      );

      await tester.pump();

      // Verifies modern luxury title
      expect(find.text('QUEENDOM SHARE'), findsOneWidget);

      // Verifies YouTube platform badge
      expect(find.text('YOUTUBE'), findsOneWidget);

      // Verifies URL content preview
      expect(find.text('https://youtu.be/test_id'), findsOneWidget);

      // Verifies copy button is present
      expect(find.text('Copy'), findsOneWidget);

      // Verifies Queendom navigation tabs are rendered with Direct Message as first tab
      expect(find.text('Direct Message'), findsOneWidget);
      expect(find.text('My Groups'), findsOneWidget);
      expect(find.text('Queen Pooja'), findsOneWidget);
      expect(find.text('Queen Rashmika'), findsOneWidget);

      // Gallery toggle is hidden for text/YouTube link
      expect(find.text('Share Destination:'), findsNothing);
    });

    testWidgets('renders photo upload controls for image payload', (tester) async {
      final imagePayload = SharedPayload(
        files: [File('/mock/test_image.jpg')],
        type: SharedPayloadType.image,
      );

      final mockGroup = _MockGroupController();
      final mockChat = _MockChatController();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            groupControllerProvider.overrideWithValue(mockGroup as dynamic),
            chatControllerProvider.overrideWithValue(mockChat as dynamic),
          ],
          child: MaterialApp(
            home: ShareUploadScreen(
              payload: imagePayload,
            ),
          ),
        ),
      );

      await tester.pump();

      // Verifies title
      expect(find.text('QUEENDOM SHARE'), findsOneWidget);

      // On initial tab (Direct Message), direct message banner is shown
      expect(find.text('Select a contact for direct message'), findsOneWidget);
      expect(find.text('Share Destination:'), findsNothing);

      // Switch to 'My Groups' tab
      await tester.tap(find.text('My Groups'));
      await tester.pumpAndSettle();

      // Verifies Gallery destination toggle is shown for images in group tab
      expect(find.text('Share Destination:'), findsOneWidget);
      expect(find.text('Gallery'), findsOneWidget);
      expect(find.text('Chat'), findsOneWidget);
    });

    testWidgets('renders group.nameWithPosition instead of raw group.name in intent share', (tester) async {
      final mockGroupModel = GroupModel(
        senderId: 'user1',
        name: 'Samantha',
        groupId: 'grp1',
        lastMessage: '',
        groupPic: '',
        membersUid: ['user1', 'user2'],
        timeSent: DateTime.now(),
        fcmTokens: [],
        unseenMessages: const {},
        position: 'Wife of Queen Pooja',
        family: 'Main',
        isSubGroup: true,
        parentGroupName: 'Queen Pooja',
        subGroupType: 'wife',
      );

      final mockGroup = _MockGroupControllerWithGroup(mockGroupModel);
      final mockChat = _MockChatController();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            groupControllerProvider.overrideWithValue(mockGroup as dynamic),
            chatControllerProvider.overrideWithValue(mockChat as dynamic),
          ],
          child: const MaterialApp(
            home: ShareUploadScreen(
              payload: SharedPayload(
                text: 'Glorious offering to the queen',
                type: SharedPayloadType.text,
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      // Switch to 'My Groups' tab
      await tester.tap(find.text('My Groups'));
      await tester.pumpAndSettle();

      // Should display formatted name: Wife of Queen Pooja - Samantha
      expect(
        find.textContaining(
          mockGroupModel.nameWithPosition,
          findRichText: true,
        ),
        findsOneWidget,
      );
    });

    testWidgets('searches and selects group displaying nameWithPosition in destination banner and button', (tester) async {
      final mockGroupModel = GroupModel(
        senderId: 'user1',
        name: 'Pooja',
        groupId: 'grp_pooja',
        lastMessage: '',
        groupPic: '',
        membersUid: ['user1', 'user2'],
        timeSent: DateTime.now(),
        fcmTokens: [],
        unseenMessages: const {},
        position: 'Queen',
        family: 'Main',
      );

      final mockGroup = _MockGroupControllerWithGroup(mockGroupModel);
      final mockChat = _MockChatController();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            groupControllerProvider.overrideWithValue(mockGroup as dynamic),
            chatControllerProvider.overrideWithValue(mockChat as dynamic),
          ],
          child: const MaterialApp(
            home: ShareUploadScreen(
              payload: SharedPayload(
                text: 'Glorious homage',
                type: SharedPayloadType.text,
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      // Switch to 'My Groups' tab
      await tester.tap(find.text('My Groups'));
      await tester.pumpAndSettle();

      // Search by position prefix "Queen"
      await tester.enterText(find.byType(TextField).first, 'Queen');
      await tester.pumpAndSettle();

      // Group should be visible because search checks nameWithPosition
      expect(find.textContaining('Queen Pooja', findRichText: true), findsWidgets);

      // Tap to select the group
      await tester.tap(find.textContaining('Queen Pooja', findRichText: true).first);
      await tester.pumpAndSettle();

      // Banner and submit button should now use Queen Pooja
      expect(find.textContaining('Queen Pooja', findRichText: true), findsWidgets);
      expect(find.text('Send 1 message to Queen Pooja'), findsOneWidget);
    });
  });
}

class _MockGroupControllerWithGroup implements GroupController {
  final GroupModel group;
  _MockGroupControllerWithGroup(this.group);

  @override
  Stream<List<GroupModel>> chatGroups() => Stream.value([group]);
  @override
  Stream<List<GroupModel>> getQueenPoojaStream() => Stream.value([group]);
  @override
  Stream<List<GroupModel>> getQueenRashmikaStream() => Stream.value([]);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
