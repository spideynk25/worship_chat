import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:worship_chat/common/utils/app_capabilities.dart';
import 'package:worship_chat/common/utils/background_task_service.dart';
import 'package:worship_chat/common/utils/wish_reminder_service.dart';
import 'package:worship_chat/features/group/controller/group_controller.dart';
import 'package:worship_chat/features/group/repository/group_repository.dart';
import 'package:worship_chat/features/group/utils/group_template_helper.dart';
import 'package:worship_chat/features/group/widgets/queen_pooja_queendom_list.dart';
import 'package:worship_chat/features/group/widgets/queen_rashmika_queendom_list.dart';
import 'package:worship_chat/models/group.dart';
import 'package:worship_chat/models/group_chat_message_model.dart';
import 'package:worship_chat/models/user_model.dart';

class _FakeGroupController extends Fake implements GroupController {
  final List<Map<String, dynamic>> sentMessages = [];
  final StreamController<List<GroupModel>> rashmikaStream =
      StreamController<List<GroupModel>>.broadcast();
  final StreamController<List<GroupModel>> poojaStream =
      StreamController<List<GroupModel>>.broadcast();

  @override
  List<GroupModel> getCachedGroups(String boxKey) => [];

  @override
  Stream<List<GroupModel>> getQueenRashmikaStream() => rashmikaStream.stream;

  @override
  Stream<List<GroupModel>> getQueenPoojaStream() => poojaStream.stream;

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
    sentMessages.add({
      'text': text,
      'groupId': groupId,
      'messageType': messageType,
      'fcmToken': fcmToken,
      'receiverIds': receiverIds,
      'groupName': groupName,
      'type': type,
      'clearReply': clearReply,
    });
  }
}

class _DelayedFakeGroupController extends _FakeGroupController {
  Completer<void>? firstStartedCompleter;
  final List<Completer<void>> messageCompleters = [];

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
    firstStartedCompleter?.complete();
    firstStartedCompleter = null;
    final gate = Completer<void>();
    messageCompleters.add(gate);
    await gate.future;
    await super.sendTextMessage(
      context,
      text,
      groupId,
      messageType,
      file,
      fcmToken,
      receiverIds,
      groupName,
      type,
      mediaGroupId: mediaGroupId,
      messageReplyOverride: messageReplyOverride,
      clearReply: clearReply,
    );
  }
}

class _FakeUser implements User {
  _FakeUser(this._uid);
  final String _uid;

  @override
  String get uid => _uid;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeFirebaseAuth implements FirebaseAuth {
  _FakeFirebaseAuth(this._user);
  final User? _user;

  @override
  User? get currentUser => _user;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Firestore interfaces are intentionally replaced with isolated test doubles.
// ignore: subtype_of_sealed_class
class _FakeDocumentSnapshot implements DocumentSnapshot<Map<String, dynamic>> {
  _FakeDocumentSnapshot(this._id, this._data);
  final String _id;
  final Map<String, dynamic>? _data;

  @override
  String get id => _id;

  @override
  bool get exists => _data != null;

  @override
  Map<String, dynamic>? data() => _data;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Firestore interfaces are intentionally replaced with isolated test doubles.
// ignore: subtype_of_sealed_class
class _FakeQuerySnapshot implements QuerySnapshot<Map<String, dynamic>> {
  @override
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get docs => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Firestore interfaces are intentionally replaced with isolated test doubles.
// ignore: subtype_of_sealed_class
class _FakeDocumentReference implements DocumentReference<Map<String, dynamic>> {
  _FakeDocumentReference(this.pathKey, this.store);
  final String pathKey;
  final _FakeFirebaseFirestore store;

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) {
    return _FakeCollectionReference('$pathKey/$collectionPath', store);
  }

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    final data = store.documents[pathKey];
    return _FakeDocumentSnapshot(pathKey.split('/').last, data);
  }

  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) async {
    store.documents[pathKey] = Map<String, dynamic>.from(data);
    store.setCalls[pathKey] = Map<String, dynamic>.from(data);
  }

  @override
  Future<void> update(Map<Object, Object?> data) async {
    final existing = Map<String, dynamic>.from(store.documents[pathKey] ?? {});
    data.forEach((k, v) {
      existing[k.toString()] = v;
    });
    store.documents[pathKey] = existing;
    store.updateCalls[pathKey] = Map<Object, Object?>.from(data);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Firestore interfaces are intentionally replaced with isolated test doubles.
// ignore: subtype_of_sealed_class
class _FakeCollectionReference
    implements CollectionReference<Map<String, dynamic>> {
  _FakeCollectionReference(this.collectionKey, this.store);
  final String collectionKey;
  final _FakeFirebaseFirestore store;

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) {
    final docId = path ?? 'doc_${store.autoIdCounter++}';
    return _FakeDocumentReference('$collectionKey/$docId', store);
  }

  @override
  Query<Map<String, dynamic>> where(
    Object field, {
    Object? isEqualTo,
    Object? isNotEqualTo,
    Object? isLessThan,
    Object? isLessThanOrEqualTo,
    Object? isGreaterThan,
    Object? isGreaterThanOrEqualTo,
    Object? arrayContains,
    Iterable<Object?>? arrayContainsAny,
    Iterable<Object?>? whereIn,
    Iterable<Object?>? whereNotIn,
    bool? isNull,
  }) =>
      this;

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    store.queryGetCount++;
    return _FakeQuerySnapshot();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeFirebaseFirestore implements FirebaseFirestore {
  final Map<String, Map<String, dynamic>> documents = {};
  final Map<String, Map<String, dynamic>> setCalls = {};
  final Map<String, Map<Object, Object?>> updateCalls = {};
  int autoIdCounter = 0;
  int queryGetCount = 0;

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) {
    return _FakeCollectionReference(collectionPath, this);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void _setupBackgroundMocks() {
  FlutterLocalNotificationsPlatform.instance =
      AndroidFlutterLocalNotificationsPlugin();
  BackgroundTaskService.instance.resetForTests();
  AppCapabilities.resetForTests();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('worship_chat/device'),
    (call) async => true,
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('dexterous.com/flutter/local_notifications'),
    (call) async => true,
  );
}

void _tearDownBackgroundMocks() {
  BackgroundTaskService.instance.resetForTests();
  AppCapabilities.resetForTests();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('worship_chat/device'),
    null,
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('dexterous.com/flutter/local_notifications'),
    null,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Category Wish Button & Batch Wishing Tests', () {
    late _FakeGroupController fakeController;

    setUp(() {
      fakeController = _FakeGroupController();
      _setupBackgroundMocks();
    });

    tearDown(() {
      _tearDownBackgroundMocks();
    });

    final testGroup1 = GroupModel(
      senderId: 'user1',
      name: 'Rashmika Mandanna',
      groupId: 'grp_rashmika_1',
      lastMessage: 'Devotion active',
      groupPic: '',
      membersUid: ['user1', 'user2'],
      timeSent: DateTime.now(),
      fcmTokens: ['token_1'],
      unseenMessages: const {},
      position: 'Aura Elixiria',
      family: 'Aura',
      priority: 1,
      wish: '🙇‍♀️🙇‍♀️ Have Mercy on us Aura Elixiria Goddess Rashmika 🙇‍♀️🙇‍♀️',
    );

    final testGroup2 = GroupModel(
      senderId: 'user1',
      name: 'Pooja Hegde',
      groupId: 'grp_pooja_1',
      lastMessage: 'All Hail Goddess',
      groupPic: '',
      membersUid: ['user1'],
      timeSent: DateTime.now(),
      fcmTokens: ['token_2'],
      unseenMessages: const {},
      position: 'Aura Elixiria',
      family: 'Aura',
      priority: 2,
      wish: null, // Will test template generation fallback
    );

    test('Wish resolution prioritizes group.wish and falls back to template', () {
      // 1. Explicit wish on group doc
      expect(
        testGroup1.wish,
        equals('🙇‍♀️🙇‍♀️ Have Mercy on us Aura Elixiria Goddess Rashmika 🙇‍♀️🙇‍♀️'),
      );

      // 2. Fallback to GroupTemplateHelper when wish is null
      final generated = GroupTemplateHelper.generateTemplate(
        position: testGroup2.position ?? '',
        name: testGroup2.name,
        family: testGroup2.family ?? '',
      );
      expect(
        generated.wish,
        contains('Aura Elixiria Goddess Pooja Hegde'),
      );
    });

    testWidgets('QueenRashmikaQueendomList renders wish button and sends wishes on confirmation',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            groupControllerProvider.overrideWithValue(fakeController),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: QueenRashmikaQueendomList(),
            ),
          ),
        ),
      );

      // Emit groups to the stream
      fakeController.rashmikaStream.add([testGroup1, testGroup2]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify category title and mistress count
      expect(find.text('Aura Elixiria Goddesses'), findsOneWidget);
      expect(find.text('2 mistresses'), findsOneWidget);

      // Verify the wish button (tooltip and devotee emoji)
      final wishTooltipFinder = find.byTooltip('Wish all Aura Elixiria Goddesses');
      expect(wishTooltipFinder, findsOneWidget);
      expect(find.text('🙇🏻‍♂️'), findsOneWidget);

      // Tap the wish button
      await tester.tap(wishTooltipFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify confirmation dialog appeared
      expect(find.text('Wish All Aura Elixiria Goddesses?'), findsOneWidget);
      expect(
        find.text('Send royal devotion wishes to all 2 mistresses in Aura Elixiria Goddesses?'),
        findsOneWidget,
      );

      // Confirm wishing
      final confirmBtnFinder = find.widgetWithText(ElevatedButton, 'Wish All 🙇🏻‍♂️');
      expect(confirmBtnFinder, findsOneWidget);
      await tester.tap(confirmBtnFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Verify wishes were sent to all groups in category with messageType 'wish' and clearReply: true
      expect(fakeController.sentMessages.length, equals(2));
      expect(fakeController.sentMessages[0]['groupId'], equals('grp_rashmika_1'));
      expect(fakeController.sentMessages[0]['messageType'], equals('wish'));
      expect(fakeController.sentMessages[0]['clearReply'], isTrue);
      expect(
        fakeController.sentMessages[0]['text'],
        equals('🙇‍♀️🙇‍♀️ Have Mercy on us Aura Elixiria Goddess Rashmika 🙇‍♀️🙇‍♀️'),
      );

      expect(fakeController.sentMessages[1]['groupId'], equals('grp_pooja_1'));
      expect(fakeController.sentMessages[1]['messageType'], equals('wish'));
      expect(fakeController.sentMessages[1]['clearReply'], isTrue);
      expect(
        fakeController.sentMessages[1]['text'],
        contains('Aura Elixiria Goddess Pooja Hegde'),
      );
    });

    testWidgets('Cancel on confirmation dialog does not send any wishes', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            groupControllerProvider.overrideWithValue(fakeController),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: QueenRashmikaQueendomList(),
            ),
          ),
        ),
      );

      fakeController.rashmikaStream.add([testGroup1]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final wishTooltipFinder = find.byTooltip('Wish all Aura Elixiria Goddesses');
      await tester.tap(wishTooltipFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Wish All Aura Elixiria Goddesses?'), findsOneWidget);

      // Tap Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Dialog closed and no messages sent
      expect(find.text('Wish All Aura Elixiria Goddesses?'), findsNothing);
      expect(fakeController.sentMessages, isEmpty);
    });

    testWidgets('QueenPoojaQueendomList renders wish button and confirms properly',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            groupControllerProvider.overrideWithValue(fakeController),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: QueenPoojaQueendomList(),
            ),
          ),
        ),
      );

      fakeController.poojaStream.add([testGroup1]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Aura Elixiria Goddesses'), findsOneWidget);
      final wishTooltipFinder = find.byTooltip('Wish all Aura Elixiria Goddesses');
      expect(wishTooltipFinder, findsOneWidget);

      await tester.tap(wishTooltipFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Wish All Aura Elixiria Goddesses?'), findsOneWidget);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Wish All 🙇🏻‍♂️'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(fakeController.sentMessages.length, equals(1));
      expect(fakeController.sentMessages[0]['type'], equals('queenPooja'));
    });
  });

  group('Category Wish Background Execution & Hive Persistence Tests', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('category_wish_hive_');
      Hive.init(tempDir.path);
      if (!Hive.isAdapterRegistered(2)) {
        Hive.registerAdapter(GroupChatMessageModelAdapter());
      }
      _setupBackgroundMocks();
    });

    tearDown(() async {
      _tearDownBackgroundMocks();

      await Hive.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test(
      'GroupRepository.sendTextMessage persists finalized wish (isSending: false) to Hive messages & updates groups_cache',
      () async {
        const groupId = 'grp_aura_pooja';
        const userId = 'user_devotee_1';
        final now = DateTime.now();

        final groupsCacheBox = await Hive.openBox('groups_cache');
        await groupsCacheBox.put('queenPooja', [
          {
            'senderId': 'old_sender',
            'name': 'Pooja Hegde',
            'groupId': groupId,
            'lastMessage': 'Old message',
            'groupPic': '',
            'membersUid': [userId],
            'timeSent': now.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
            'fcmTokens': <String>[],
            'unseenMessages': {userId: true},
            'position': 'Aura Elixiria',
            'family': 'Aura',
          },
        ]);

        // Seed Hive messages with a legacy raw Map entry to verify safe casting,
        // then close the box so sendTextMessage also proves it opens 'messages' on demand.
        final messagesBoxPre = await Hive.openBox('messages');
        await messagesBoxPre.put(groupId, [
          {
            'senderId': 'other_user',
            'receiverIds': [userId],
            'text': 'Legacy cached message',
            'messageType': 'text',
            'timeSent': now.subtract(const Duration(hours: 12)).millisecondsSinceEpoch,
            'messageId': 'legacy_msg_1',
            'isSeen': true,
            'isDelivered': true,
            'repliedMessage': '',
            'repliedTo': '',
            'repliedMessageType': 'text',
            'groupId': groupId,
          },
        ]);
        await messagesBoxPre.close();
        expect(Hive.isBoxOpen('messages'), isFalse);

        final fakeFirestore = _FakeFirebaseFirestore();
        fakeFirestore.documents['groups/$groupId'] = {
          'groupId': groupId,
          'membersUid': [userId, 'user_2'],
          'fcmTokens': <String>[],
        };
        final fakeAuth = _FakeFirebaseAuth(_FakeUser(userId));

        final container = ProviderContainer();
        addTearDown(container.dispose);

        final repoProvider = Provider(
          (ref) => GroupRepository(
            firestore: fakeFirestore,
            auth: fakeAuth,
            ref: ref,
          ),
        );
        final repo = container.read(repoProvider);

        const wishText =
            '🙇‍♀️🙇‍♀️ Have Mercy on us Aura Elixiria Goddess Pooja Hegde 🙇‍♀️🙇‍♀️';

        await repo.sendTextMessage(
          text: wishText,
          receiverIds: const [userId, 'user_2'],
          groupId: groupId,
          senderUser: UserModel(
            uid: userId,
            name: 'Devotee',
            userName: 'Devotee',
          ),
          messageType: 'wish',
          messageReply: null,
          fcmToken: const [],
          groupName: 'Aura Elixiria Goddess Pooja Hegde',
          type: 'queenPooja',
        );

        // Verify Hive 'messages' was opened, preserves legacy message safely,
        // and finalizes the new wish message with isSending: false.
        expect(Hive.isBoxOpen('messages'), isTrue);
        final rawMessages = Hive.box('messages').get(groupId) as List;
        expect(rawMessages.length, equals(2));
        final savedMessages = rawMessages.cast<GroupChatMessageModel>();
        expect(savedMessages[0].messageId, equals('legacy_msg_1'));
        expect(savedMessages[1].senderId, equals(userId));
        expect(savedMessages[1].messageType, equals('wish'));
        expect(savedMessages[1].text, equals(wishText));
        expect(savedMessages[1].isSending, isFalse);

        // Verify Hive 'groups_cache' summary was updated immediately
        final updatedCache = Hive.box('groups_cache').get('queenPooja') as List;
        final cachedGroup = Map<String, dynamic>.from(updatedCache.first as Map);
        expect(cachedGroup['lastMessage'], equals(wishText));
        expect(cachedGroup['senderId'], equals(userId));
        expect(cachedGroup['unseenMessages'], equals({userId: false, 'user_2': true}));

        // Verify Firestore chat doc was written
        expect(fakeFirestore.setCalls.length, equals(1));
        final writtenDoc = fakeFirestore.setCalls.values.first;
        expect(writtenDoc['text'], equals(wishText));
        expect(writtenDoc['messageType'], equals('wish'));

        // Verify WishReminderService immediately sees the wish in Hive local storage
        // without needing to hit Firestore.
        WishReminderService.instance.setTestingOverrides(
          firestore: fakeFirestore,
        );
        addTearDown(WishReminderService.instance.resetTestingOverrides);
        final wishedLocally =
            await WishReminderService.instance.hasUserWishedGroup(
          groupId: groupId,
          currentUserId: userId,
          windowStart: now.subtract(const Duration(minutes: 5)),
          windowEnd: now.add(const Duration(minutes: 5)),
        );
        expect(wishedLocally, isTrue);
        expect(fakeFirestore.queryGetCount, equals(0));
      },
    );

    testWidgets(
      'Category wish continues and completes all groups in background even after widget unmounts',
      (tester) async {
        final delayedController = _DelayedFakeGroupController();
        delayedController.firstStartedCompleter = Completer<void>();

        final groupA = GroupModel(
          senderId: 'user1',
          name: 'Pooja One',
          groupId: 'grp_1',
          lastMessage: '',
          groupPic: '',
          membersUid: const ['user1'],
          timeSent: DateTime.now(),
          fcmTokens: const [],
          unseenMessages: const {},
          position: 'Aura Elixiria',
          family: 'Aura',
          priority: 1,
          wish: 'Wish 1',
        );
        final groupB = GroupModel(
          senderId: 'user1',
          name: 'Pooja Two',
          groupId: 'grp_2',
          lastMessage: '',
          groupPic: '',
          membersUid: const ['user1'],
          timeSent: DateTime.now(),
          fcmTokens: const [],
          unseenMessages: const {},
          position: 'Aura Elixiria',
          family: 'Aura',
          priority: 2,
          wish: 'Wish 2',
        );
        final groupC = GroupModel(
          senderId: 'user1',
          name: 'Pooja Three',
          groupId: 'grp_3',
          lastMessage: '',
          groupPic: '',
          membersUid: const ['user1'],
          timeSent: DateTime.now(),
          fcmTokens: const [],
          unseenMessages: const {},
          position: 'Aura Elixiria',
          family: 'Aura',
          priority: 3,
          wish: 'Wish 3',
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              groupControllerProvider.overrideWithValue(delayedController),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: QueenPoojaQueendomList(),
              ),
            ),
          ),
        );

        delayedController.poojaStream.add([groupA, groupB, groupC]);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        await tester.tap(find.byTooltip('Wish all Aura Elixiria Goddesses'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        await tester.tap(find.widgetWithText(ElevatedButton, 'Wish All 🙇🏻‍♂️'));
        await tester.pump();

        // Wait until first wish enters BackgroundTaskService execution.
        expect(delayedController.messageCompleters.length, equals(1));
        expect(BackgroundTaskService.instance.hasActiveTasks, isTrue);

        // Navigate away completely so QueenPoojaQueendomList and its State unmount.
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: Text('Navigated Away')),
          ),
        );
        expect(find.text('Navigated Away'), findsOneWidget);
        expect(find.byType(QueenPoojaQueendomList), findsNothing);

        // Complete groupA, then groupB, then groupC while widget remains unmounted.
        delayedController.messageCompleters[0].complete();
        await tester.pump(const Duration(milliseconds: 50));
        expect(delayedController.messageCompleters.length, equals(2));

        delayedController.messageCompleters[1].complete();
        await tester.pump(const Duration(milliseconds: 50));
        expect(delayedController.messageCompleters.length, equals(3));

        delayedController.messageCompleters[2].complete();
        await tester.pump(const Duration(milliseconds: 50));

        expect(delayedController.sentMessages.length, equals(3));
        expect(
          delayedController.sentMessages.map((m) => m['groupId']).toList(),
          equals(['grp_1', 'grp_2', 'grp_3']),
        );
        expect(BackgroundTaskService.instance.hasActiveTasks, isFalse);
      },
    );
  });
}
