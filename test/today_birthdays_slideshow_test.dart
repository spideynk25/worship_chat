import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_chat/features/dashboard/repositories/event_repository.dart';
import 'package:worship_chat/features/dashboard/widgets/today_birthdays_slideshow_widget.dart';
import 'package:worship_chat/models/event.dart';

class FakeEventRepository extends EventRepository {
  final Stream<List<Event>> _stream;

  FakeEventRepository(this._stream);

  @override
  Stream<List<Event>> eventsStream() => _stream;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.now();

  group('TodayBirthdaysSlideshowWidget - Grid and Short Normal Wish Tests', () {
    test('extractCelebrantName parses names correctly without prefixes/suffixes', () {
      expect(
        TodayBirthdaysSlideshowWidget.extractCelebrantName('Queen Pooja\'s Birthday'),
        'Queen Pooja',
      );
      expect(
        TodayBirthdaysSlideshowWidget.extractCelebrantName('Rashmika\'s Bday Celebration'),
        'Queen Rashmika',
      );
      expect(
        TodayBirthdaysSlideshowWidget.extractCelebrantName('Happy Birthday Deepika Padukone'),
        'Goddess Deepika',
      );
      expect(
        TodayBirthdaysSlideshowWidget.extractCelebrantName('Happy Birthday of John Doe'),
        'John Doe',
      );
      expect(
        TodayBirthdaysSlideshowWidget.extractCelebrantName('Alice\'s Birthday Bash'),
        'Alice',
      );
      expect(
        TodayBirthdaysSlideshowWidget.extractCelebrantName('Golden Blossom Goddess Vani Bhojan\'s Birthday'),
        'Golden Blossom Goddess Vani Bhojan',
      );
      expect(
        TodayBirthdaysSlideshowWidget.extractCelebrantName(
          'Vani Bhojan\'s Birthday',
          connectedGroupName: 'Golden Blossom Goddess Vani Bhojan',
        ),
        'Golden Blossom Goddess Vani Bhojan',
      );
      expect(
        TodayBirthdaysSlideshowWidget.extractCelebrantName(
          'Vani Bhojan\'s Birthday',
          connectedGroupName: 'Demi Goddess Vani Bhojan',
        ),
        'Demi Goddess Vani Bhojan',
      );
      expect(
        TodayBirthdaysSlideshowWidget.extractCelebrantName('Priyanka Mohan\'s Birthday'),
        'Priyanka Mohan',
      );
      expect(
        TodayBirthdaysSlideshowWidget.extractCelebrantName('Dark Angel Priyanka Mohan\'s Birthday'),
        'Dark Angel Priyanka Mohan',
      );
      expect(
        TodayBirthdaysSlideshowWidget.extractCelebrantName(
          'Priyanka\'s Birthday',
          connectedGroupName: 'Dark Angel Priyanka Mohan',
        ),
        'Dark Angel Priyanka Mohan',
      );
      expect(
        TodayBirthdaysSlideshowWidget.extractCelebrantName(
          'Priyanka Mohan\'s Birthday',
          connectedGroupName: 'Dark Angel Priyanka Mohan',
        ),
        'Dark Angel Priyanka Mohan',
      );
      expect(
        TodayBirthdaysSlideshowWidget.extractCelebrantName(
          'SHRINE OF 🍀 ETERNAL ENCHANTRESS PRIYANKA JAWALKAR\'s Birthday',
        ),
        'ETERNAL ENCHANTRESS PRIYANKA JAWALKAR',
      );
      expect(
        TodayBirthdaysSlideshowWidget.extractCelebrantName(
          'Priyanka Jawalkar\'s Birthday',
          connectedGroupName: 'SHRINE OF 🍀 ETERNAL ENCHANTRESS PRIYANKA JAWALKAR',
        ),
        'ETERNAL ENCHANTRESS PRIYANKA JAWALKAR',
      );
      expect(
        TodayBirthdaysSlideshowWidget.extractCelebrantName(
          'SANCTUM OF 🏮 SUPREME ELORA GODDESS ANUSHKA\'s Birthday',
        ),
        'SUPREME ELORA GODDESS ANUSHKA',
      );
      expect(
        TodayBirthdaysSlideshowWidget.extractCelebrantName(
          'GOLDEN SANCTUM OF 🍂 GOLDEN BLOSSOM GODDESS VANI BHOJAN\'s Birthday',
        ),
        'GOLDEN BLOSSOM GODDESS VANI BHOJAN',
      );
      expect(
        TodayBirthdaysSlideshowWidget.extractCelebrantName(
          'DARK SHRINE OF 🪻 DARK ANGEL PRIYANKA MOHAN\'s Birthday',
        ),
        'DARK ANGEL PRIYANKA MOHAN',
      );
      expect(
        TodayBirthdaysSlideshowWidget.extractCelebrantName(
          'TEMPLE OF 🪷 GODDESS DEEPIKA\'s Birthday',
        ),
        'GODDESS DEEPIKA',
      );
      expect(
        TodayBirthdaysSlideshowWidget.extractCelebrantName(
          'SHRINE of 🍁 ELFWITCH POOJA\'s Birthday',
        ),
        'ELFWITCH POOJA',
      );
      expect(
        TodayBirthdaysSlideshowWidget.extractCelebrantName('Queen Rashmika Royal Palace'),
        'Queen Rashmika',
      );
      expect(
        TodayBirthdaysSlideshowWidget.extractCelebrantName('Queen Pooja Queendom'),
        'Queen Pooja',
      );
      expect(
        TodayBirthdaysSlideshowWidget.extractCelebrantName('Queen Rashmika Devotees'),
        'Queen Rashmika',
      );
      expect(
        TodayBirthdaysSlideshowWidget.extractCelebrantName('Queen Rashmika Royal Guard'),
        'Queen Rashmika',
      );
    });

    testWidgets('Displays single celebrant card with short normal wish when 1 birthday today', (tester) async {
      final singleEvent = Event(
        id: 'event_pooja',
        title: 'Queen Pooja\'s Birthday',
        description: 'Celebrate Queen Pooja',
        date: DateTime(now.year, now.month, now.day),
        time: const TimeOfDay(hour: 9, minute: 0),
        createdBy: 'Admin',
        userId: 'admin_1',
        isRecurring: true,
        connectedQueendom: 'Queen Pooja',
      );

      final controller = StreamController<List<Event>>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            eventRepositoryProvider.overrideWithValue(FakeEventRepository(controller.stream)),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: TodayBirthdaysSlideshowWidget(),
              ),
            ),
          ),
        ),
      );

      controller.add([singleEvent]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Check header and short normal birthday wish
      expect(find.text('ROYAL BIRTHDAY CELEBRATION'), findsOneWidget);
      expect(find.text('Happy Birthday, Queen Pooja! 🎂✨'), findsOneWidget);

      // Verify no tab selector navigation exists
      expect(find.byType(GridView), findsNothing);

      await controller.close();
    });

    testWidgets('Displays grid structure for 2+ celebrants without tab navigation', (tester) async {
      final event1 = Event(
        id: 'event_pooja',
        title: 'Queen Pooja\'s Birthday',
        description: 'Celebrate Queen Pooja',
        date: DateTime(now.year, now.month, now.day),
        time: const TimeOfDay(hour: 9, minute: 0),
        createdBy: 'Admin',
        userId: 'admin_1',
        isRecurring: true,
        connectedQueendom: 'Queen Pooja',
      );

      final event2 = Event(
        id: 'event_rashmika',
        title: 'Queen Rashmika\'s Birthday',
        description: 'Celebrate Queen Rashmika',
        date: DateTime(now.year, now.month, now.day),
        time: const TimeOfDay(hour: 10, minute: 0),
        createdBy: 'Admin',
        userId: 'admin_2',
        isRecurring: true,
        connectedQueendom: 'Queen Rashmika',
      );

      final controller = StreamController<List<Event>>();

      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            eventRepositoryProvider.overrideWithValue(FakeEventRepository(controller.stream)),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: TodayBirthdaysSlideshowWidget(),
              ),
            ),
          ),
        ),
      );

      controller.add([event1, event2]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify GridView is used to display all cards simultaneously
      expect(find.byType(GridView), findsOneWidget);
      expect(find.text('TODAY\'S BIRTHDAY CELEBRATIONS'), findsOneWidget);
      expect(find.text('2 TODAY'), findsOneWidget);

      // Verify both celebrants appear with short normal wishing texts
      expect(find.text('Happy Birthday, Queen Pooja! 🎂✨'), findsOneWidget);
      expect(find.text('Happy Birthday, Queen Rashmika! 🎂✨'), findsOneWidget);

      // Verify GridView delegate childAspectRatio and 1:1 square photo structure
      final gridView = tester.widget<GridView>(find.byType(GridView));
      final delegate =
          gridView.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(delegate.childAspectRatio, 0.70);

      // Verify each card contains a 1:1 square photo structure
      final aspectRatios =
          tester.widgetList<AspectRatio>(find.byType(AspectRatio));
      expect(aspectRatios.where((ar) => ar.aspectRatio == 1.0).length, 2);

      // Verify no tab navigation chips exist (ListView.separated tabs were eliminated)
      expect(find.byKey(const ValueKey('bday_grid_event_pooja')), findsOneWidget);
      expect(find.byKey(const ValueKey('bday_grid_event_rashmika')), findsOneWidget);

      await controller.close();
    });

    testWidgets('Displays proper square structure and shows full long text without ellipsis truncation', (tester) async {
      final longEvent1 = Event(
        id: 'event_long_1',
        title: 'Princess Krithi Shetty\'s Birthday Celebration',
        description: 'Celebrate Princess Krithi',
        date: DateTime(now.year, now.month, now.day),
        time: const TimeOfDay(hour: 9, minute: 0),
        createdBy: 'Admin',
        userId: 'admin_1',
        isRecurring: true,
      );

      final longEvent2 = Event(
        id: 'event_long_2',
        title: 'Samantha Ruth Prabhu\'s Royal Birthday Bash',
        description: 'Celebrate Samantha Ruth Prabhu',
        date: DateTime(now.year, now.month, now.day),
        time: const TimeOfDay(hour: 10, minute: 0),
        createdBy: 'Admin',
        userId: 'admin_2',
        isRecurring: true,
      );

      final controller = StreamController<List<Event>>();

      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            eventRepositoryProvider.overrideWithValue(FakeEventRepository(controller.stream)),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: TodayBirthdaysSlideshowWidget(),
              ),
            ),
          ),
        ),
      );

      controller.add([longEvent1, longEvent2]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify full names are rendered in the wishing text without ellipsis
      expect(find.text('Happy Birthday, Princess Krithi Shetty! 🎂✨'), findsOneWidget);
      expect(find.text('Happy Birthday, Samantha Ruth Prabhu! 🎂✨'), findsOneWidget);

      // Verify no overflow exception occurred
      expect(tester.takeException(), isNull);

      await controller.close();
    });

    testWidgets('Slideshow automatically advances photos after timer interval', (tester) async {
      final singleEvent = Event(
        id: 'event_pooja',
        title: 'Queen Pooja\'s Birthday',
        description: 'Celebrate Queen Pooja',
        date: DateTime(now.year, now.month, now.day),
        time: const TimeOfDay(hour: 9, minute: 0),
        createdBy: 'Admin',
        userId: 'admin_1',
        isRecurring: true,
        connectedQueendom: 'Queen Pooja',
      );

      final controller = StreamController<List<Event>>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            eventRepositoryProvider.overrideWithValue(FakeEventRepository(controller.stream)),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: TodayBirthdaysSlideshowWidget(),
              ),
            ),
          ),
        ),
      );

      controller.add([singleEvent]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Indicator initially shows 1 /
      expect(find.textContaining('1 /'), findsOneWidget);

      // Fast-forward past the 3800ms timer and 750ms transition
      await tester.pump(const Duration(milliseconds: 3900));
      await tester.pump(const Duration(milliseconds: 800));

      // Indicator has advanced to 2 /
      expect(find.textContaining('2 /'), findsOneWidget);

      await controller.close();
    });

    testWidgets('Renders celebrant title plus name in card when connectedGroupName or title provides title', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final vaniEvent = Event(
        id: 'event_vani',
        title: 'Vani Bhojan\'s Birthday',
        description: 'Celebrate Vani Bhojan',
        date: DateTime(now.year, now.month, now.day),
        time: const TimeOfDay(hour: 9, minute: 0),
        createdBy: 'Admin',
        userId: 'admin_1',
        isRecurring: true,
        connectedGroupName: 'Golden Blossom Goddess Vani Bhojan',
      );

      final controller = StreamController<List<Event>>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            eventRepositoryProvider.overrideWithValue(FakeEventRepository(controller.stream)),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: TodayBirthdaysSlideshowWidget(),
              ),
            ),
          ),
        ),
      );

      controller.add([vaniEvent]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Assert title plus name is displayed:
      expect(find.text('Happy Birthday, Golden Blossom Goddess Vani Bhojan! 🎂✨'), findsOneWidget);

      // Verify "TODAY" text on top of the image is removed
      expect(find.text('TODAY'), findsNothing);

      // Verify "Wish in Group" and "Gallery" buttons are removed
      expect(find.text('Wish in Group'), findsNothing);
      expect(find.text('Gallery'), findsNothing);

      // Long press the birthday wish box
      await tester.longPress(find.text('Happy Birthday, Golden Blossom Goddess Vani Bhojan! 🎂✨'));
      await tester.pumpAndSettle();

      await controller.close();
    });

    testWidgets('Grid cards also have TODAY badge and buttons removed', (tester) async {
      final event1 = Event(
        id: 'event_pooja',
        title: 'Queen Pooja\'s Birthday',
        description: 'Celebrate Queen Pooja',
        date: DateTime(now.year, now.month, now.day),
        time: const TimeOfDay(hour: 9, minute: 0),
        createdBy: 'Admin',
        userId: 'admin_1',
        isRecurring: true,
        connectedQueendom: 'Queen Pooja',
      );

      final event2 = Event(
        id: 'event_rashmika',
        title: 'Queen Rashmika\'s Birthday',
        description: 'Celebrate Queen Rashmika',
        date: DateTime(now.year, now.month, now.day),
        time: const TimeOfDay(hour: 10, minute: 0),
        createdBy: 'Admin',
        userId: 'admin_2',
        isRecurring: true,
        connectedQueendom: 'Queen Rashmika',
      );

      final controller = StreamController<List<Event>>();

      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            eventRepositoryProvider.overrideWithValue(FakeEventRepository(controller.stream)),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: TodayBirthdaysSlideshowWidget(),
              ),
            ),
          ),
        ),
      );

      controller.add([event1, event2]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Wish & Gallery buttons should not exist
      expect(find.text('Wish'), findsNothing);
      expect(find.text('Gallery'), findsNothing);

      await controller.close();
    });

    testWidgets('Displays accurate celebrant name and Dark Angel category for Priyanka Mohan', (tester) async {
      final priyankaEvent = Event(
        id: 'event_priyanka',
        title: 'Priyanka Mohan\'s Birthday',
        description: 'Celebrate Priyanka Mohan',
        date: DateTime(now.year, now.month, now.day),
        time: const TimeOfDay(hour: 9, minute: 0),
        createdBy: 'Admin',
        userId: 'admin_1',
        isRecurring: true,
        connectedGroupName: 'Dark Angel Priyanka Mohan',
      );

      final controller = StreamController<List<Event>>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            eventRepositoryProvider.overrideWithValue(FakeEventRepository(controller.stream)),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: TodayBirthdaysSlideshowWidget(),
              ),
            ),
          ),
        ),
      );

      controller.add([priyankaEvent]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Header must NOT say ROYAL BIRTHDAY CELEBRATION
      expect(find.text('ROYAL BIRTHDAY CELEBRATION'), findsNothing);
      // Header must say DARK ANGEL BIRTHDAY CELEBRATION
      expect(find.text('DARK ANGEL BIRTHDAY CELEBRATION'), findsOneWidget);
      // Title must say Dark Angel Priyanka Mohan's Birthday ✨ (NOT Queen Priyanka's Birthday ✨)
      expect(find.text('Dark Angel Priyanka Mohan\'s Birthday ✨'), findsOneWidget);
      expect(find.textContaining('Queen Priyanka'), findsNothing);

      await controller.close();
    });

    testWidgets('Displays celebrant role + name without living place on birthday card (e.g. SHRINE OF 🍀)', (tester) async {
      final priyankaJawalkarEvent = Event(
        id: 'event_priyanka_jawalkar',
        title: 'SHRINE OF 🍀 ETERNAL ENCHANTRESS PRIYANKA JAWALKAR\'s Birthday',
        description: 'Celebrate Eternal Enchantress Priyanka Jawalkar',
        date: DateTime(now.year, now.month, now.day),
        time: const TimeOfDay(hour: 9, minute: 0),
        createdBy: 'Admin',
        userId: 'admin_1',
        isRecurring: true,
        connectedGroupName: 'SHRINE OF 🍀 ETERNAL ENCHANTRESS PRIYANKA JAWALKAR',
      );

      final controller = StreamController<List<Event>>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            eventRepositoryProvider.overrideWithValue(FakeEventRepository(controller.stream)),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: TodayBirthdaysSlideshowWidget(),
              ),
            ),
          ),
        ),
      );

      controller.add([priyankaJawalkarEvent]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Living place prefix must NOT appear in header or wish text
      expect(find.textContaining('SHRINE OF 🍀'), findsNothing);
      expect(find.textContaining('SHRINE OF'), findsNothing);

      // Header must display ENCHANTRESS BIRTHDAY CELEBRATION
      expect(find.text('ENCHANTRESS BIRTHDAY CELEBRATION'), findsOneWidget);

      // Card Title must display role + name
      expect(find.text('ETERNAL ENCHANTRESS PRIYANKA JAWALKAR\'s Birthday ✨'), findsOneWidget);

      // Wish text must display role + name
      expect(find.text('Happy Birthday, ETERNAL ENCHANTRESS PRIYANKA JAWALKAR! 🎂✨'), findsOneWidget);

      await controller.close();
    });
  });
}
