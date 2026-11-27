import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:worship_chat/common/utils/app_capabilities.dart';
import 'package:worship_chat/common/widgets/skeleton_loader.dart';
import 'package:worship_chat/common/widgets/user_avatar.dart';
import 'package:worship_chat/features/dashboard/repositories/event_repository.dart';
import 'package:worship_chat/features/home/screens/gallery_home_screen.dart';
import 'package:worship_chat/features/home/screens/home_screen.dart';
import 'package:worship_chat/features/home/widgets/dynamic_text_widget.dart';
import 'package:worship_chat/features/home/widgets/home_birthday_deities_app_bar_bottom.dart';
import 'package:worship_chat/models/event.dart';
import 'package:worship_chat/models/group.dart';
import 'package:worship_chat/models/user_model.dart';

class _FakeEventRepository extends EventRepository {
  final List<Event> events;

  _FakeEventRepository(this.events);

  @override
  Future<List<Event>> fetchEvents() async => events;

  @override
  Stream<List<Event>> eventsStream() => Stream.value(events);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('home_header_ui_test_');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(UserModelAdapter());
    }
    final userBox = await Hive.openBox<UserModel>('userBox');
    await userBox.put(
      'currentUser',
      UserModel(
        name: 'Anu Rashmika',
        userName: 'mrs_pooja',
        uid: 'u_test_1',
        profilePic: '',
        isOnline: true,
        email: 'anu@example.com',
        groupId: const [],
        fcmToken: '',
      ),
    );
  });

  tearDown(() async {
    AppCapabilities.debugOverride = null;
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  testWidgets(
      'HomeScreen minimal borderless header aligns cleanly on narrow phones without overlapping DynamicTextWidget',
      (tester) async {
    AppCapabilities.debugOverride = const AppCapabilities(
      platform: TargetPlatform.macOS,
      isTablet: false,
    );
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          galleryGroupsProvider.overrideWith((_) => Stream.value(<GroupModel>[])),
        ],
        child: const MaterialApp(
          home: HomeScreen(initialIndex: 0),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Worship Gallery'), findsOneWidget);
    expect(find.text('Anu Rashmika'), findsOneWidget);
    expect(find.text('mrs_pooja'), findsOneWidget);
    expect(find.byType(DynamicTextWidget), findsOneWidget);

    // Full-width DynamicTextWidget is flush-left aligned with title and sits cleanly BELOW Row 1.
    final brandLeft = tester.getTopLeft(find.text('Worship Gallery')).dx;
    final dynamicTextFinder = find.descendant(
      of: find.byType(DynamicTextWidget),
      matching: find.byType(Text),
    );
    final dynamicLeft = tester.getTopLeft(dynamicTextFinder).dx;
    expect((dynamicLeft - brandLeft).abs(), lessThanOrEqualTo(1.0));

    final brandBottom = tester.getBottomLeft(find.text('Worship Gallery')).dy;
    final profileNameBottom = tester.getBottomLeft(find.text('Anu Rashmika')).dy;
    final dynamicTop = tester.getTopLeft(find.byType(DynamicTextWidget)).dy;
    expect(dynamicTop, greaterThanOrEqualTo(brandBottom));
    expect(dynamicTop, greaterThanOrEqualTo(profileNameBottom));

    // Preserves 10s golden ShimmerEffect and Hero->UserAvatar structure.
    final shimmer = tester.widget<ShimmerEffect>(find.byType(ShimmerEffect));
    expect(shimmer.duration, const Duration(seconds: 10));
    expect(shimmer.activeFraction, 0.14);
    final hero = tester.widget<Hero>(find.byType(Hero).first);
    expect(hero.child, isA<UserAvatar>());
    expect((hero.child as UserAvatar).radius, 25);

    // Tapping profile opens popup menu cleanly.
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Photo Counts'), findsOneWidget);
    expect(find.text('Bookmarks'), findsWidgets);
  });

  testWidgets(
      'HomeScreen handles 6 simultaneous birthdays on the same day with horizontal scroll and all-celebrants sheet',
      (tester) async {
    AppCapabilities.debugOverride = const AppCapabilities(
      platform: TargetPlatform.macOS,
      isTablet: false,
    );
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now();
    const deities = [
      ('priyanka', 'Priyanka Jawalkar', 'assets/auth_images/queen_priyanka.png'),
      ('pooja', 'Pooja Hegde', 'assets/auth_images/queen_pooja.png'),
      ('rashmika', 'Rashmika Mandanna', 'assets/auth_images/queen_rashmika.png'),
      ('samantha', 'Samantha Ruth', 'assets/auth_images/queen_priyanka.png'),
      ('kriti', 'Kriti Kharbanda', 'assets/auth_images/queen_pooja.png'),
      ('deepika', 'Deepika Padukone', 'assets/auth_images/queen_rashmika.png'),
    ];
    final todayEvents = [
      for (final (id, name, asset) in deities)
        Event(
          id: 'bday_$id',
          title: "$name's Birthday",
          description: 'Annual Royal Birthday celebration',
          date: now,
          time: const TimeOfDay(hour: 0, minute: 0),
          createdBy: 'admin',
          userId: 'admin',
          isRecurring: true,
          connectedGroupId: 'group_$id',
          connectedGroupName: name,
          connectedGroupPic: asset,
        ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          galleryGroupsProvider.overrideWith((_) => Stream.value(<GroupModel>[])),
          eventRepositoryProvider.overrideWithValue(
            _FakeEventRepository(todayEvents),
          ),
        ],
        child: const MaterialApp(
          home: HomeScreen(initialIndex: 0),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    final appBarFinder = find.byType(AppBar);
    // Title text is replaced by birthday profiles when birthdays exist today.
    expect(
      find.descendant(of: appBarFinder, matching: find.text('Worship Gallery')),
      findsNothing,
    );
    expect(
      find.descendant(of: appBarFinder, matching: find.text('Worship Chat')),
      findsNothing,
    );

    // All 6 birthday avatars render with AnimatedBirthdayDeityAvatar special effects.
    final birthdayAvatarFinder = find.descendant(
      of: appBarFinder,
      matching: find.byType(AnimatedBirthdayDeityAvatar),
    );
    expect(birthdayAvatarFinder, findsNWidgets(6));
    expect(
      tester.widget<AnimatedBirthdayDeityAvatar>(birthdayAvatarFinder.first).radius,
      23,
    );
    expect(
      find.descendant(of: appBarFinder, matching: find.text('🎂')),
      findsNWidgets(6),
    );
    await tester.pump(const Duration(milliseconds: 800));
    expect(tester.takeException(), isNull);
    final countFinder =
        find.descendant(of: appBarFinder, matching: find.text('6'));
    expect(countFinder, findsOneWidget);

    // Birthday profiles occupy Row 1 ABOVE DynamicTextWidget and flush-left.
    final dynamicTop = tester.getTopLeft(find.byType(DynamicTextWidget)).dy;
    final cakeBottom = tester
        .getBottomLeft(
          find.descendant(of: appBarFinder, matching: find.text('🎂')).first,
        )
        .dy;
    expect(dynamicTop, greaterThanOrEqualTo(cakeBottom));

    // Happy Birthday text replaces normal wishing text and cycles across all celebrants.
    expect(
      find.descendant(
        of: appBarFinder,
        matching: find.text('Happy Birthday Priyanka Jawalkar'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: appBarFinder,
        matching: find.text('Long live Core Supreme Goddess Deepika'),
      ),
      findsNothing,
    );

    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 800));
    expect(
      find.descendant(
        of: appBarFinder,
        matching: find.text('Happy Birthday Queen Pooja'),
      ),
      findsOneWidget,
    );

    // Tapping count button opens the full list of all 6 birthdays
    await tester.tap(countFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(tester.takeException(), isNull);
    final sheetFinder = find.byType(BottomSheet);
    expect(sheetFinder, findsOneWidget);
    expect(
      find.descendant(
        of: sheetFinder,
        matching: find.text("Today's Birthdays (6)"),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: sheetFinder,
        matching: find.text('Priyanka Jawalkar'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: sheetFinder,
        matching: find.text('Kriti Kharbanda'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: sheetFinder,
        matching: find.text('Goddess Deepika'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'HomeScreen wraps long AppBar birthday wish cleanly on small 320dp screen without truncation or clipping',
      (tester) async {
    AppCapabilities.debugOverride = const AppCapabilities(
      platform: TargetPlatform.macOS,
      isTablet: false,
    );
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now();
    final longBirthdayEvent = Event(
      id: 'bday_anikha_long',
      title: "Second Born Eternal Princess Anikha Surendran's Birthday",
      description: 'Annual Royal Birthday celebration',
      date: now,
      time: const TimeOfDay(hour: 0, minute: 0),
      createdBy: 'admin',
      userId: 'admin',
      isRecurring: true,
      connectedGroupId: 'group_anikha',
      connectedGroupName: 'Second Born Eternal Princess Anikha Surendran',
      connectedGroupPic: 'assets/auth_images/queen_priyanka.png',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          galleryGroupsProvider.overrideWith((_) => Stream.value(<GroupModel>[])),
          eventRepositoryProvider.overrideWithValue(
            _FakeEventRepository([longBirthdayEvent]),
          ),
        ],
        child: const MaterialApp(
          home: HomeScreen(initialIndex: 0),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    expect(tester.takeException(), isNull);

    final dynamicWidget =
        tester.widget<DynamicTextWidget>(find.byType(DynamicTextWidget));
    expect(dynamicWidget.maxLines, 2);

    const expectedWish =
        'Happy Birthday Second Born Eternal Princess Anikha Surendran';
    final wishTextFinder = find.descendant(
      of: find.byType(DynamicTextWidget),
      matching: find.text(expectedWish),
    );
    expect(wishTextFinder, findsOneWidget);

    final wishTextWidget = tester.widget<Text>(wishTextFinder);
    expect(wishTextWidget.maxLines, 2);
    expect(wishTextWidget.softWrap, isTrue);

    final appBarRect = tester.getRect(find.byType(AppBar));
    final wishRect = tester.getRect(wishTextFinder);
    expect(appBarRect.height, greaterThan(92.0));
    expect(wishRect.height, greaterThan(20.0));
    expect(wishRect.bottom, lessThanOrEqualTo(appBarRect.bottom));
    expect(wishRect.right, lessThanOrEqualTo(appBarRect.right));
  });

  testWidgets(
      'HomeScreen expands AppBar height under 1.3x font scale on narrow mobile so 2-line wishes never clip',
      (tester) async {
    AppCapabilities.debugOverride = const AppCapabilities(
      platform: TargetPlatform.macOS,
      isTablet: false,
    );
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now();
    final longBirthdayEvent = Event(
      id: 'bday_anikha_scaled',
      title: "Second Born Eternal Princess Anikha Surendran's Birthday",
      description: 'Annual Royal Birthday celebration',
      date: now,
      time: const TimeOfDay(hour: 0, minute: 0),
      createdBy: 'admin',
      userId: 'admin',
      isRecurring: true,
      connectedGroupId: 'group_anikha',
      connectedGroupName: 'Second Born Eternal Princess Anikha Surendran',
      connectedGroupPic: 'assets/auth_images/queen_priyanka.png',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          galleryGroupsProvider.overrideWith((_) => Stream.value(<GroupModel>[])),
          eventRepositoryProvider.overrideWithValue(
            _FakeEventRepository([longBirthdayEvent]),
          ),
        ],
        child: MaterialApp(
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(1.3),
              ),
              child: child!,
            );
          },
          home: const HomeScreen(initialIndex: 0),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    expect(tester.takeException(), isNull);

    final appBarFinder = find.byType(AppBar);
    final appBarRect = tester.getRect(appBarFinder);
    final wishFinder = find.descendant(
      of: find.byType(DynamicTextWidget),
      matching: find.text(
        'Happy Birthday Second Born Eternal Princess Anikha Surendran',
      ),
    );
    expect(wishFinder, findsOneWidget);
    final wishRect = tester.getRect(wishFinder);
    final cakeBottom = tester
        .getBottomLeft(
          find.descendant(of: appBarFinder, matching: find.text('🎂')).first,
        )
        .dy;

    expect(appBarRect.height, greaterThan(102.0));
    expect(wishRect.top, greaterThanOrEqualTo(cakeBottom));
    expect(wishRect.bottom, lessThanOrEqualTo(appBarRect.bottom));
  });
}
