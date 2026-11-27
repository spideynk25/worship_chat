import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/screens/combined_contact_screen.dart';
import 'package:worship_chat/features/chat/controller/chat_controller.dart';
import 'package:worship_chat/features/group/controller/group_controller.dart';
import 'package:worship_chat/features/group/controller/group_gallery_controller.dart';
import 'package:worship_chat/features/status/controller/status_controller.dart';
import 'package:worship_chat/models/chat_contact.dart';
import 'package:worship_chat/models/group.dart';
import 'package:worship_chat/models/group_gallery_image.dart';

class _FakeStatusController implements StatusController {
  int statusFetches = 0;

  @override
  Stream<List<Map<String, dynamic>>> getStatuses() {
    statusFetches++;
    return Stream.value(const []);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeChatController implements ChatController {
  int contactsFetches = 0;
  String latestMessage = 'Initial message';

  @override
  List<ChatContact> getCachedContacts({required bool isAllChats}) => const [];

  @override
  Stream<List<ChatContact>> chatContacts() {
    contactsFetches++;
    final currentMsg = latestMessage;
    return Stream.value([
      ChatContact(
        name: 'Pooja Devotee',
        profilePic: '',
        uid: 'u_contact_1',
        timeSent: DateTime.now(),
        lastMessage: currentMsg,
        fcmToken: '',
        unseenCount: false,
        chatBackgroundUrl: null,
      ),
    ]);
  }

  @override
  Stream<List<ChatContact>> fetchAllContacts() => chatContacts();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeGroupController implements GroupController {
  final List<GroupModel> groups = [
    GroupModel(
      senderId: 'u1',
      name: 'Royal Chamber',
      groupId: 'grp_1',
      lastMessage: 'Hello',
      groupPic: '',
      membersUid: const ['u1'],
      fcmTokens: const [],
      unseenMessages: const {},
      queendom: 'Queen Pooja',
      galleryCount: 1,
      lastGalleryUpdate: DateTime.now(),
    ),
  ];

  @override
  List<GroupModel> getCachedGroups(String category) => const [];

  @override
  Stream<List<GroupModel>> getQueenPoojaStream() => Stream.value(groups);

  @override
  Stream<List<GroupModel>> getQueenRashmikaStream() => Stream.value(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeGroupGalleryController implements GroupGalleryController {
  int recentFetches = 0;
  List<GroupGalleryImage> photosToReturn = [
    GroupGalleryImage(
      imageId: 'img_1',
      groupId: 'grp_1',
      imageUrl: 'https://example.com/recent1.jpg',
      uploadedBy: 'u1',
      uploadedByName: 'Admin',
      uploadedAt: DateTime.now().subtract(const Duration(minutes: 5)),
    ),
  ];

  @override
  Future<List<GroupGalleryImage>> getCachedRecentGalleryPhotos(
    String uid,
  ) async =>
      const [];

  @override
  Future<List<GroupGalleryImage>> getRecentGalleryPhotos({
    required List<GroupModel> groups,
    int limit = 24,
    int limitPerGroup = 8,
    int maxGroupsToQuery = 16,
    bool photosOnly = true,
    bool saveCache = true,
  }) async {
    recentFetches++;
    return List<GroupGalleryImage>.of(photosToReturn);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'CombinedContactsScreen wraps Chats & Recent Gallery in RefreshIndicator and refreshes statuses, contacts, and gallery photos on pull',
    (tester) async {
      final statusCtrl = _FakeStatusController();
      final chatCtrl = _FakeChatController();
      final groupCtrl = _FakeGroupController();
      final galleryCtrl = _FakeGroupGalleryController();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            statusControllerProvider.overrideWithValue(statusCtrl),
            chatControllerProvider.overrideWithValue(chatCtrl),
            groupControllerProvider.overrideWithValue(groupCtrl),
            groupGalleryControllerProvider.overrideWithValue(galleryCtrl),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: CombinedContactsScreen(isAllChats: false),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(tester.takeException(), isNull);
      expect(find.byType(RefreshIndicator), findsOneWidget);

      final indicator = tester.widget<RefreshIndicator>(
        find.byType(RefreshIndicator),
      );
      expect(indicator.color, tabColor);
      expect(indicator.backgroundColor, const Color(0xFF1B1528));

      final scrollView = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView).first,
      );
      expect(scrollView.physics, isA<AlwaysScrollableScrollPhysics>());

      expect(find.text('Pooja Devotee'), findsOneWidget);
      expect(find.text('Initial message'), findsOneWidget);
      expect(find.text('RECENT GALLERY PHOTOS'), findsOneWidget);

      final initialStatusFetches = statusCtrl.statusFetches;
      final initialContactsFetches = chatCtrl.contactsFetches;
      final initialGalleryFetches = galleryCtrl.recentFetches;

      // Update mock responses before pulling to refresh.
      chatCtrl.latestMessage = 'Freshly pulled message';
      galleryCtrl.photosToReturn = [
        GroupGalleryImage(
          imageId: 'img_2',
          groupId: 'grp_1',
          imageUrl: 'https://example.com/recent2.jpg',
          uploadedBy: 'u1',
          uploadedByName: 'Admin',
          uploadedAt: DateTime.now(),
        ),
        ...galleryCtrl.photosToReturn,
      ];

      await tester.fling(
        find.byType(SingleChildScrollView).first,
        const Offset(0, 320),
        1000,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      expect(tester.takeException(), isNull);
      expect(statusCtrl.statusFetches, greaterThan(initialStatusFetches));
      expect(chatCtrl.contactsFetches, greaterThan(initialContactsFetches));
      expect(galleryCtrl.recentFetches, greaterThan(initialGalleryFetches));
      expect(find.text('Freshly pulled message'), findsOneWidget);
      expect(find.text('Just now'), findsOneWidget);
    },
  );
}
