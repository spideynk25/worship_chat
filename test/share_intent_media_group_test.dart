import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_chat/common/utils/share_intent_service.dart';
import 'package:worship_chat/features/auth/controller/auth_controller.dart';
import 'package:worship_chat/features/chat/controller/chat_controller.dart';
import 'package:worship_chat/features/chat/widgets/media_group_widget.dart';
import 'package:worship_chat/features/group/controller/group_controller.dart';
import 'package:worship_chat/features/group/controller/group_gallery_controller.dart';
import 'package:worship_chat/features/group/widgets/group_chat_list_widget.dart';
import 'package:worship_chat/features/share/screens/share_upload_screen.dart';
import 'package:worship_chat/models/chat_contact.dart';
import 'package:worship_chat/models/group.dart';
import 'package:worship_chat/models/group_chat_message_model.dart';
import 'package:worship_chat/models/user_model.dart';

class _DirectMessageCall {
  final String text;
  final String receiverUserId;
  final String messageType;
  final dynamic file;
  final String? groupId;

  _DirectMessageCall({
    required this.text,
    required this.receiverUserId,
    required this.messageType,
    required this.file,
    this.groupId,
  });
}

class _GroupMessageCall {
  final String text;
  final String groupId;
  final String messageType;
  final dynamic file;
  final String? mediaGroupId;

  _GroupMessageCall({
    required this.text,
    required this.groupId,
    required this.messageType,
    required this.file,
    this.mediaGroupId,
  });
}

class _RecordingChatController implements ChatController {
  final List<_DirectMessageCall> calls = [];

  @override
  Stream<List<ChatContact>> chatContacts() => Stream.value([
        ChatContact(
          name: 'Pooja Devotee',
          profilePic: '',
          uid: 'uid_devotee_1',
          timeSent: DateTime.now(),
          lastMessage: 'Hello',
          fcmToken: 'fcm_123',
          unseenCount: false,
          chatBackgroundUrl: null,
        ),
      ]);

  @override
  Stream<List<ChatContact>> fetchAllContacts() => chatContacts();

  @override
  Future<void> sendTextMessage(
    BuildContext context,
    String text,
    String receiverUserId,
    String messageType,
    dynamic file,
    String fcmToken,
    bool? unseenCount,
    String? chatBackgroundUrl,
    String type, {
    String? groupId,
    dynamic messageReplyOverride,
    bool clearReply = false,
  }) async {
    calls.add(_DirectMessageCall(
      text: text,
      receiverUserId: receiverUserId,
      messageType: messageType,
      file: file,
      groupId: groupId,
    ));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _RecordingGroupController implements GroupController {
  final List<_GroupMessageCall> calls = [];
  List<GroupChatMessageModel> messagesToStream = [];

  static final List<GroupModel> _testGroups = [
    GroupModel(
      senderId: 'current_user_id',
      name: 'Royal Chamber',
      groupId: 'royal_group_1',
      lastMessage: 'Hail',
      groupPic: '',
      membersUid: ['current_user_id', 'other_uid'],
      timeSent: DateTime.now(),
      fcmTokens: ['fcm_grp_1'],
      unseenMessages: const {},
    ),
    GroupModel(
      senderId: 'current_user_id',
      name: 'Royal Courtyard',
      groupId: 'royal_group_2',
      lastMessage: 'Greetings',
      groupPic: '',
      membersUid: ['current_user_id', 'other_uid_2'],
      timeSent: DateTime.now(),
      fcmTokens: ['fcm_grp_2'],
      unseenMessages: const {},
    ),
  ];

  @override
  Stream<List<GroupModel>> chatGroups() => Stream.value(_testGroups);

  @override
  Stream<List<GroupModel>> getQueenPoojaStream() => Stream.value(_testGroups);
  @override
  Stream<List<GroupModel>> getQueenRashmikaStream() => Stream.value([]);

  @override
  Stream<List<GroupChatMessageModel>> getGroupChat(String groupId) =>
      Stream.value(messagesToStream);

  @override
  Future<void> sendTextMessage(
    BuildContext context,
    String text,
    String groupId,
    String messageType,
    dynamic file,
    List<String> fcmToken,
    List<String> receiverIds,
    String groupName,
    String type, {
    String? mediaGroupId,
    dynamic messageReplyOverride,
    bool clearReply = false,
  }) async {
    calls.add(_GroupMessageCall(
      text: text,
      groupId: groupId,
      messageType: messageType,
      file: file,
      mediaGroupId: mediaGroupId,
    ));
  }

  @override
  Future<void> setChatMessageSeen(BuildContext context, String groupId, String messageId) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _RecordingGalleryController implements GroupGalleryController {
  final List<String> uploadedGroupIds = [];

  @override
  Future<int> uploadImages({
    required String groupId,
    required List<File> imageFiles,
    required String uploaderName,
    String? caption,
    void Function(int uploaded, int total)? onProgress,
  }) async {
    uploadedGroupIds.add(groupId);
    onProgress?.call(imageFiles.length, imageFiles.length);
    return imageFiles.length;
  }

  @override
  Future<int> uploadVideos({
    required String groupId,
    required List<File> videoFiles,
    required String uploaderName,
    String? caption,
    void Function(int uploaded, int total)? onProgress,
  }) async {
    uploadedGroupIds.add(groupId);
    onProgress?.call(videoFiles.length, videoFiles.length);
    return videoFiles.length;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testUser = UserModel(
    name: 'Devotee Admin',
    userName: 'devotee_admin',
    uid: 'current_user_id',
    profilePic: '',
    isOnline: true,
    email: 'devotee@queendom.com',
    groupId: ['royal_group_1'],
  );

  Future<void> pumpPushedShareScreen(
    WidgetTester tester, {
    required _RecordingChatController chatController,
    required _RecordingGroupController groupController,
    required SharedPayload payload,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatControllerProvider.overrideWithValue(chatController),
          groupControllerProvider.overrideWithValue(groupController),
          userDataAuthProvider.overrideWith((ref) => Future.value(testUser)),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ShareUploadScreen(payload: payload),
                  ),
                ),
                child: const Text('Open Share'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Share'));
    await tester.pumpAndSettle();
  }

  group('Intent Share Media Grouping Tests', () {
    testWidgets(
        'Multi-photo direct chat intent passes shared groupId and attaches caption to first only',
        (tester) async {
      final mockChatController = _RecordingChatController();
      final mockGroupController = _RecordingGroupController();

      final payload = SharedPayload(
        type: SharedPayloadType.image,
        files: [
          File('/tmp/photo1.jpg'),
          File('/tmp/photo2.png'),
          File('/tmp/photo3.jpeg'),
        ],
        text: 'Royal blessings from the garden',
      );

      await pumpPushedShareScreen(
        tester,
        chatController: mockChatController,
        groupController: mockGroupController,
        payload: payload,
      );

      // Initial tab is "Direct Message"
      final contactTile = find.text('Pooja Devotee');
      expect(contactTile, findsOneWidget);
      await tester.tap(contactTile);
      await tester.pumpAndSettle();

      // Verify destination button
      final sendButton = find.text('Send 3 photos to Pooja Devotee');
      expect(sendButton, findsOneWidget);
      await tester.tap(sendButton);
      await tester.pumpAndSettle();

      // Verify that sendTextMessage was called 3 times
      expect(mockChatController.calls.length, equals(3));

      // Verify all 3 messages share the EXACT same non-null groupId
      final firstGroupId = mockChatController.calls.first.groupId;
      expect(firstGroupId, isNotNull);
      expect(firstGroupId!.isNotEmpty, isTrue);

      for (final call in mockChatController.calls) {
        expect(call.groupId, equals(firstGroupId));
        expect(call.receiverUserId, equals('uid_devotee_1'));
        expect(call.messageType, equals('image'));
      }

      // Verify caption attached only to the first message
      expect(mockChatController.calls[0].text,
          equals('Royal blessings from the garden'));
      expect(mockChatController.calls[1].text, equals(''));
      expect(mockChatController.calls[2].text, equals(''));
    });

    testWidgets(
        'Multi-photo group chat intent passes shared mediaGroupId and attaches caption to first only',
        (tester) async {
      final mockChatController = _RecordingChatController();
      final mockGroupController = _RecordingGroupController();

      final payload = SharedPayload(
        type: SharedPayloadType.image,
        files: [
          File('/tmp/royal_photo1.jpg'),
          File('/tmp/royal_photo2.png'),
        ],
        text: 'Royal group greetings',
      );

      await pumpPushedShareScreen(
        tester,
        chatController: mockChatController,
        groupController: mockGroupController,
        payload: payload,
      );

      // Switch to 'Queen Pooja' tab
      await tester.tap(find.text('Queen Pooja'));
      await tester.pumpAndSettle();

      // For image payloads, the default target on group tab is Gallery. Switch to Chat toggle:
      final chatToggle = find.text('Chat');
      expect(chatToggle, findsOneWidget);
      await tester.tap(chatToggle);
      await tester.pumpAndSettle();

      // Select group "Royal Chamber"
      final groupTile = find.textContaining('Royal Chamber', findRichText: true).first;
      expect(groupTile, findsOneWidget);
      await tester.tap(groupTile);
      await tester.pumpAndSettle();

      // Tap send button
      final sendButton = find.text('Send 2 photos to Royal Chamber');
      expect(sendButton, findsOneWidget);
      await tester.tap(sendButton);
      await tester.pumpAndSettle();

      // Verify that sendTextMessage was called 2 times
      expect(mockGroupController.calls.length, equals(2));

      // Verify all messages share the same mediaGroupId
      final firstMediaGroupId = mockGroupController.calls.first.mediaGroupId;
      expect(firstMediaGroupId, isNotNull);
      expect(firstMediaGroupId!.isNotEmpty, isTrue);

      for (final call in mockGroupController.calls) {
        expect(call.mediaGroupId, equals(firstMediaGroupId));
        expect(call.groupId, equals('royal_group_1'));
        expect(call.messageType, equals('image'));
      }

      // Caption on first only
      expect(mockGroupController.calls[0].text, equals('Royal group greetings'));
      expect(mockGroupController.calls[1].text, equals(''));
    });

    testWidgets(
        'Multi-photo intent share to multiple groups sends photos to all selected groups',
        (tester) async {
      final mockChatController = _RecordingChatController();
      final mockGroupController = _RecordingGroupController();

      final payload = SharedPayload(
        type: SharedPayloadType.image,
        files: [
          File('/tmp/royal_photo1.jpg'),
          File('/tmp/royal_photo2.png'),
        ],
        text: 'Royal multi greetings',
      );

      await pumpPushedShareScreen(
        tester,
        chatController: mockChatController,
        groupController: mockGroupController,
        payload: payload,
      );

      // Switch to 'Queen Pooja' tab
      await tester.tap(find.text('Queen Pooja'));
      await tester.pumpAndSettle();

      // Switch to Chat toggle
      await tester.tap(find.text('Chat'));
      await tester.pumpAndSettle();

      // Select group 1 ("Royal Chamber")
      await tester.tap(find.textContaining('Royal Chamber', findRichText: true).first);
      await tester.pumpAndSettle();

      // Select group 2 ("Royal Courtyard")
      final group2Finder = find.textContaining('Royal Courtyard', findRichText: true).first;
      await tester.ensureVisible(group2Finder);
      await tester.tap(group2Finder);
      await tester.pumpAndSettle();

      // Verify submit button says: 'Send 2 photos to 2 Groups'
      final sendButton = find.text('Send 2 photos to 2 Groups');
      expect(sendButton, findsOneWidget);

      await tester.tap(sendButton);
      await tester.pumpAndSettle();

      // Total calls = 2 photos * 2 groups = 4 calls
      expect(mockGroupController.calls.length, equals(4));

      // Calls 0 and 1 are for group 1 (royal_group_1)
      expect(mockGroupController.calls[0].groupId, equals('royal_group_1'));
      expect(mockGroupController.calls[1].groupId, equals('royal_group_1'));
      // Calls 2 and 3 are for group 2 (royal_group_2)
      expect(mockGroupController.calls[2].groupId, equals('royal_group_2'));
      expect(mockGroupController.calls[3].groupId, equals('royal_group_2'));
    });

    testWidgets('Single photo intent share does not assign groupId',
        (tester) async {
      final mockChatController = _RecordingChatController();
      final mockGroupController = _RecordingGroupController();

      final payload = SharedPayload(
        type: SharedPayloadType.image,
        files: [
          File('/tmp/single_photo.jpg'),
        ],
        text: 'Single photo caption',
      );

      await pumpPushedShareScreen(
        tester,
        chatController: mockChatController,
        groupController: mockGroupController,
        payload: payload,
      );

      // Initial tab is Direct Message: select contact
      final contactTile = find.text('Pooja Devotee');
      expect(contactTile, findsOneWidget);
      await tester.tap(contactTile);
      await tester.pumpAndSettle();

      // Send
      final sendButton = find.text('Send 1 photo to Pooja Devotee');
      expect(sendButton, findsOneWidget);
      await tester.tap(sendButton);
      await tester.pumpAndSettle();

      expect(mockChatController.calls.length, equals(1));
      // Single photo: groupId must be null so it displays as standard card
      expect(mockChatController.calls.first.groupId, isNull);
      expect(mockChatController.calls.first.text,
          equals('Single photo caption'));
    });
  });

  group('GroupChatListWidget Media Grouping Logic', () {
    testWidgets('Renders MediaGroupWidget when multiple media share same groupId',
        (tester) async {
      const sharedGroupId = 'test-media-group-123';
      final now = DateTime.now();

      final messages = [
        GroupChatMessageModel(
          senderId: 'current_user_id',
          receiverIds: ['other_uid'],
          text: 'Collage caption',
          messageType: 'image',
          timeSent: now,
          messageId: 'msg_1',
          fileMessageData: jsonEncode({
            'url': 'https://example.com/img1.jpg',
            'groupId': sharedGroupId,
          }),
          repliedMessage: '',
          repliedTo: '',
          repliedMessageType: 'text',
          groupId: 'royal_group_1',
        ),
        GroupChatMessageModel(
          senderId: 'current_user_id',
          receiverIds: ['other_uid'],
          text: '',
          messageType: 'image',
          timeSent: now.add(const Duration(milliseconds: 100)),
          messageId: 'msg_2',
          fileMessageData: jsonEncode({
            'url': 'https://example.com/img2.jpg',
            'groupId': sharedGroupId,
          }),
          repliedMessage: '',
          repliedTo: '',
          repliedMessageType: 'text',
          groupId: 'royal_group_1',
        ),
        GroupChatMessageModel(
          senderId: 'current_user_id',
          receiverIds: ['other_uid'],
          text: '',
          messageType: 'video',
          timeSent: now.add(const Duration(milliseconds: 200)),
          messageId: 'msg_3',
          fileMessageData: jsonEncode({
            'url': 'https://example.com/vid3.mp4',
            'groupId': sharedGroupId,
          }),
          repliedMessage: '',
          repliedTo: '',
          repliedMessageType: 'text',
          groupId: 'royal_group_1',
        ),
      ];

      final mockGroupController = _RecordingGroupController();
      mockGroupController.messagesToStream = messages;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            groupControllerProvider.overrideWithValue(mockGroupController),
            userDataAuthProvider.overrideWith((ref) => Future.value(testUser)),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: GroupChatListWidget(
                groupId: 'royal_group_1',
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Find MediaGroupWidget
      expect(find.byType(MediaGroupWidget), findsOneWidget);

      final mediaGroupWidget =
          tester.widget<MediaGroupWidget>(find.byType(MediaGroupWidget));
      expect(mediaGroupWidget.items.length, equals(3));
      expect(mediaGroupWidget.items[0].url, equals('https://example.com/img1.jpg'));
      expect(mediaGroupWidget.items[0].type, equals('image'));
      expect(mediaGroupWidget.items[1].url, equals('https://example.com/img2.jpg'));
      expect(mediaGroupWidget.items[1].type, equals('image'));
      expect(mediaGroupWidget.items[2].url, equals('https://example.com/vid3.mp4'));
      expect(mediaGroupWidget.items[2].type, equals('video'));
      expect(mediaGroupWidget.caption, equals('Collage caption'));
    });
  });

  group('Post-Send Destination & Back Navigation Tests', () {
    Future<void> pumpShareWithStack(
      WidgetTester tester, {
      required _RecordingChatController chatController,
      required _RecordingGroupController groupController,
      required _RecordingGalleryController galleryController,
      required SharedPayload payload,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatControllerProvider.overrideWithValue(chatController),
            groupControllerProvider.overrideWithValue(groupController),
            groupGalleryControllerProvider.overrideWithValue(galleryController),
            userDataAuthProvider.overrideWith((ref) => Future.value(testUser)),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (rootCtx) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    // Push an intermediate screen first, then ShareUploadScreen,
                    // verifying Back from the destination skips both and goes Home.
                    Navigator.of(rootCtx).push(
                      MaterialPageRoute(
                        builder: (midCtx) => Scaffold(
                          body: ElevatedButton(
                            onPressed: () => Navigator.of(midCtx).push(
                              MaterialPageRoute(
                                builder: (_) => ShareUploadScreen(
                                  payload: payload,
                                  homeScreenBuilder: () => const Scaffold(
                                    body: Center(child: Text('HOME_ROOT')),
                                  ),
                                  directChatScreenBuilder: (contact) =>
                                      Scaffold(
                                    appBar: AppBar(
                                      title: Text('DIRECT:${contact.uid}'),
                                    ),
                                    body: const SizedBox.shrink(),
                                  ),
                                  groupChatScreenBuilder:
                                      (group, accent, type) => Scaffold(
                                    appBar: AppBar(
                                      title: Text('GROUP:${group.groupId}'),
                                    ),
                                    body: const SizedBox.shrink(),
                                  ),
                                  groupGalleryScreenBuilder: (group, accent) =>
                                      Scaffold(
                                    appBar: AppBar(
                                      title: Text('GALLERY:${group.groupId}'),
                                    ),
                                    body: const SizedBox.shrink(),
                                  ),
                                ),
                              ),
                            ),
                            child: const Text('Push Share'),
                          ),
                        ),
                      ),
                    );
                  },
                  child: const Text('Push Intermediate'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Push Intermediate'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Push Share'));
      await tester.pumpAndSettle();
    }

    testWidgets(
        'Direct chat share navigates to 1:1 chat and going back lands on Home',
        (tester) async {
      final chatCtrl = _RecordingChatController();
      final groupCtrl = _RecordingGroupController();
      final galleryCtrl = _RecordingGalleryController();

      await pumpShareWithStack(
        tester,
        chatController: chatCtrl,
        groupController: groupCtrl,
        galleryController: galleryCtrl,
        payload: const SharedPayload(
          text: 'Hello via intent',
          type: SharedPayloadType.text,
        ),
      );

      await tester.tap(find.text('Pooja Devotee'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send 1 message to Pooja Devotee'));
      await tester.pumpAndSettle();

      expect(find.text('DIRECT:uid_devotee_1'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('HOME_ROOT'), findsOneWidget);
      expect(find.text('Push Share'), findsNothing);
    });

    testWidgets(
        'Single group chat share navigates to group chat and going back lands on Home',
        (tester) async {
      final chatCtrl = _RecordingChatController();
      final groupCtrl = _RecordingGroupController();
      final galleryCtrl = _RecordingGalleryController();

      await pumpShareWithStack(
        tester,
        chatController: chatCtrl,
        groupController: groupCtrl,
        galleryController: galleryCtrl,
        payload: SharedPayload(
          type: SharedPayloadType.image,
          files: [File('/tmp/royal_single.jpg')],
        ),
      );

      await tester.tap(find.text('Queen Pooja'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chat'));
      await tester.pumpAndSettle();
      await tester
          .tap(find.textContaining('Royal Chamber', findRichText: true).first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Send 1 photo to Royal Chamber'));
      await tester.pumpAndSettle();

      expect(find.text('GROUP:royal_group_1'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('HOME_ROOT'), findsOneWidget);
      expect(find.text('Push Share'), findsNothing);
    });

    testWidgets(
        'Single group gallery share navigates to gallery screen and going back lands on Home',
        (tester) async {
      final chatCtrl = _RecordingChatController();
      final groupCtrl = _RecordingGroupController();
      final galleryCtrl = _RecordingGalleryController();

      await pumpShareWithStack(
        tester,
        chatController: chatCtrl,
        groupController: groupCtrl,
        galleryController: galleryCtrl,
        payload: SharedPayload(
          type: SharedPayloadType.image,
          files: [File('/tmp/gallery_1.jpg'), File('/tmp/gallery_2.jpg')],
        ),
      );

      await tester.tap(find.text('Queen Pooja'));
      await tester.pumpAndSettle();
      await tester
          .tap(find.textContaining('Royal Chamber', findRichText: true).first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Upload 2 photos to Gallery'));
      await tester.pumpAndSettle();

      expect(galleryCtrl.uploadedGroupIds, ['royal_group_1']);
      expect(find.text('GALLERY:royal_group_1'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('HOME_ROOT'), findsOneWidget);
    });

    testWidgets(
        'Multi-group share navigates cleanly back to Home root',
        (tester) async {
      final chatCtrl = _RecordingChatController();
      final groupCtrl = _RecordingGroupController();
      final galleryCtrl = _RecordingGalleryController();

      await pumpShareWithStack(
        tester,
        chatController: chatCtrl,
        groupController: groupCtrl,
        galleryController: galleryCtrl,
        payload: const SharedPayload(
          text: 'Broadcast link',
          type: SharedPayloadType.text,
        ),
      );

      await tester.tap(find.text('Queen Pooja'));
      await tester.pumpAndSettle();
      await tester
          .tap(find.textContaining('Royal Chamber', findRichText: true).first);
      await tester.pumpAndSettle();
      final grp2 =
          find.textContaining('Royal Courtyard', findRichText: true).first;
      await tester.ensureVisible(grp2);
      await tester.tap(grp2);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Send 1 message to 2 Groups'));
      await tester.pumpAndSettle();

      expect(find.text('HOME_ROOT'), findsOneWidget);
    });
  });
}
