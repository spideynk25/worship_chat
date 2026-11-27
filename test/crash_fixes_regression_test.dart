import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:worship_chat/common/providers/message_edit_provider.dart';
import 'package:worship_chat/common/utils/app_capabilities.dart';
import 'package:worship_chat/features/auth/controller/auth_controller.dart';
import 'package:worship_chat/features/chat/controller/chat_controller.dart';
import 'package:worship_chat/features/chat/widgets/one_to_one_bottom_chat_field_widget.dart';
import 'package:worship_chat/features/dashboard/repositories/event_repository.dart';
import 'package:worship_chat/features/group/controller/group_controller.dart';
import 'package:worship_chat/features/group/utils/queendom_group_helper.dart';
import 'package:worship_chat/features/group/widgets/group_bottom_chat_field_widget.dart';
import 'package:worship_chat/features/home/screens/gallery_home_screen.dart';
import 'package:worship_chat/features/home/screens/home_screen.dart';
import 'package:worship_chat/models/event.dart';
import 'package:worship_chat/models/group.dart';
import 'package:worship_chat/models/user_model.dart';

class _FakeAuthController implements AuthController {
  final List<bool> userStateCalls = [];

  @override
  void setUserState(bool isOnline) {
    userStateCalls.add(isOnline);
  }

  @override
  Future<UserModel?> getUsetData() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeChatController implements ChatController {
  final List<String> typingCalls = [];

  @override
  void setTypingStatus(String receiverUserId, bool isTyping) {
    typingCalls.add('$receiverUserId:$isTyping');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeGroupController implements GroupController {
  final List<String> typingCalls = [];
  final List<GroupModel> poojaGroups;
  final List<GroupModel> rashmikaGroups;

  _FakeGroupController({
    this.poojaGroups = const [],
    this.rashmikaGroups = const [],
  });

  @override
  void setGroupTypingStatus(String groupId, bool isTyping) {
    typingCalls.add('$groupId:$isTyping');
  }

  @override
  List<GroupModel> getCachedGroups(String key) => const [];

  @override
  Stream<List<GroupModel>> getQueenPoojaStream() async* {
    // Deliberately single-subscription async* stream matching production.
    yield poojaGroups;
  }

  @override
  Stream<List<GroupModel>> getQueenRashmikaStream() async* {
    // Deliberately single-subscription async* stream matching production.
    yield rashmikaGroups;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeEventRepository extends EventRepository {
  @override
  Future<List<Event>> fetchEvents() async => const [];

  @override
  Stream<List<Event>> eventsStream() => Stream.value(const []);
}

GroupModel _sampleGroup({
  required String id,
  required String name,
  required String queendom,
}) {
  return GroupModel(
    senderId: 'u1',
    name: name,
    groupId: id,
    lastMessage: '',
    groupPic: '',
    membersUid: const ['u1'],
    fcmTokens: const [],
    unseenMessages: const {},
    timeSent: DateTime(2026, 11, 27),
    queendom: queendom,
    family: 'Main',
    position: 'Queen',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    AppCapabilities.debugOverride = null;
  });

  testWidgets(
      'OneToOneBottomChatFieldWidget disposes safely while typing & editing without ref-after-dispose crash',
      (tester) async {
    final fakeChatController = _FakeChatController();
    final container = ProviderContainer(
      overrides: [
        chatControllerProvider.overrideWithValue(fakeChatController),
      ],
    );
    addTearDown(container.dispose);

    container.read(messageEditProvider.notifier).state = MessageEdit(
      messageId: 'm1',
      text: 'Original',
      chatType: 'one_to_one',
      receiverUserId: 'receiver_1',
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: OneToOneBottomChatFieldWidget(
              receiverUserId: 'receiver_1',
              fcmToken: '',
              unseenCount: false,
              chatBackgroundUrl: null,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'Om Namah Shivaya');
    await tester.pump();
    expect(fakeChatController.typingCalls, ['receiver_1:true']);

    // Immediately dispose the widget while _isTyping == true and _typingTimer is active.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);

    expect(
      fakeChatController.typingCalls,
      ['receiver_1:true', 'receiver_1:false'],
    );
    expect(container.read(messageEditProvider), isNull);

    // Ensure the cancelled 2s timer never fires into a disposed State.
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'GroupBottomChatFieldWidget disposes safely while typing & editing without ref-after-dispose crash',
      (tester) async {
    final fakeGroupController = _FakeGroupController();
    final container = ProviderContainer(
      overrides: [
        groupControllerProvider.overrideWithValue(fakeGroupController),
      ],
    );
    addTearDown(container.dispose);

    container.read(messageEditProvider.notifier).state = MessageEdit(
      messageId: 'm2',
      text: 'Original group msg',
      chatType: 'group',
      groupId: 'group_1',
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: GroupBottomChatFieldWidget(
              groupId: 'group_1',
              receiverIds: ['u2'],
              fcmToken: ['tok'],
              groupName: 'Sanctuary',
              wish: 'Blessings',
              queendom: 'Queen Pooja',
              type: 'group',
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'Happy Birthday');
    await tester.pump();
    expect(fakeGroupController.typingCalls, ['group_1:true']);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);

    expect(
      fakeGroupController.typingCalls,
      ['group_1:true', 'group_1:false'],
    );
    expect(container.read(messageEditProvider), isNull);

    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'showQueendomGroupPicker keeps TabBarView single-subscription streams alive across tab swipes',
      (tester) async {
    final pooja = _sampleGroup(
      id: 'g_pooja',
      name: 'Pooja Temple',
      queendom: 'Queen Pooja',
    );
    final rashmika = _sampleGroup(
      id: 'g_rashmika',
      name: 'Rashmika Temple',
      queendom: 'Queen Rashmika',
    );
    final fakeGroupController = _FakeGroupController(
      poojaGroups: [pooja],
      rashmikaGroups: [rashmika],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          groupControllerProvider.overrideWithValue(fakeGroupController),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => ElevatedButton(
                onPressed: () {
                  showQueendomGroupPicker(context, ref: ref);
                },
                child: const Text('Open Picker'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Picker'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Pooja Temple', findRichText: true, skipOffstage: false),
      findsNothing,
    );
    expect(
      find.textContaining('POOJA TEMPLE', findRichText: true),
      findsOneWidget,
    );

    // Switch to Queen Rashmika tab and back multiple times; single-subscription
    // async* streams must NOT throw "Stream has already been listened to."
    await tester.tap(find.text('Queen Rashmika'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      find.textContaining('RASHMIKA TEMPLE', findRichText: true),
      findsOneWidget,
    );

    await tester.tap(find.text('Queen Pooja'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      find.textContaining('POOJA TEMPLE', findRichText: true),
      findsOneWidget,
    );

    await tester.tap(find.text('Queen Rashmika'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  group('HomeScreen lifecycle safety', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('home_lifecycle_test_');
      Hive.init(tempDir.path);
      if (!Hive.isAdapterRegistered(0)) {
        Hive.registerAdapter(UserModelAdapter());
      }
      final userBox = await Hive.openBox<UserModel>('userBox');
      await userBox.put(
        'currentUser',
        UserModel(
          name: 'Test User',
          userName: 'test_user',
          uid: 'u1',
          profilePic: '',
          isOnline: true,
          email: 'test@example.com',
          groupId: const [],
          fcmToken: '',
        ),
      );
    });

    tearDown(() async {
      await Hive.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    testWidgets(
        'HomeScreen ignores late lifecycle notifications delivered after tree deactivation/dispose',
        (tester) async {
      AppCapabilities.debugOverride = const AppCapabilities(
        platform: TargetPlatform.macOS,
        isTablet: false,
      );
      final fakeAuthController = _FakeAuthController();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWithValue(fakeAuthController),
            galleryGroupsProvider
                .overrideWith((_) => Stream.value(<GroupModel>[])),
            eventRepositoryProvider.overrideWithValue(_FakeEventRepository()),
          ],
          child: const MaterialApp(
            home: HomeScreen(initialIndex: 0),
          ),
        ),
      );
      await tester.pump();

      final observer =
          tester.state(find.byType(HomeScreen)) as WidgetsBindingObserver;

      // Tear down ProviderScope + HomeScreen and simulate an in-flight snapshot
      // observer callback matching WidgetsBinding.handleAppLifecycleStateChanged.
      await tester.pumpWidget(const SizedBox.shrink());
      observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
      observer.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(tester.takeException(), isNull);
    });
  });
}
