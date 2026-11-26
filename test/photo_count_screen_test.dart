import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_chat/features/dashboard/repositories/event_repository.dart';
import 'package:worship_chat/features/dashboard/screens/dashboard_page.dart';
import 'package:worship_chat/features/home/screens/gallery_home_screen.dart';
import 'package:worship_chat/features/home/screens/photo_count_screen.dart';
import 'package:worship_chat/models/event.dart';
import 'package:worship_chat/models/group.dart';
import 'package:worship_chat/router.dart';

class _FakeEventRepository implements EventRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #fetchEvents) {
      return Future.value(<Event>[]);
    }
    if (invocation.memberName == #eventsStream) {
      return Stream.value(<Event>[]);
    }
    return super.noSuchMethod(invocation);
  }
}

GroupModel _testGroup(String id, String name, String queendom, int count) =>
    GroupModel(
      senderId: 'user1',
      name: name,
      groupId: id,
      lastMessage: '',
      groupPic: '',
      membersUid: ['user1'],
      fcmTokens: [],
      unseenMessages: const {},
      queendom: queendom,
      galleryCount: count,
    );

void main() {
  testWidgets('PhotoCountScreen renders with Photo Counts title, search bar, and filters',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          galleryGroupsProvider.overrideWith(
            (_) => Stream.value([
              _testGroup('g1', 'Queen Pooja Main', 'Queen Pooja', 15),
              _testGroup('g2', 'Queen Rashmika Main', 'Queen Rashmika', 20),
            ]),
          ),
        ],
        child: const MaterialApp(
          home: PhotoCountScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify AppBar Title says 'Photo Counts'
    expect(find.text('Photo Counts'), findsOneWidget);

    // Verify Search Bar exists
    expect(find.byType(TextField), findsOneWidget);

    // Verify Filter Chips exist
    expect(find.widgetWithText(ChoiceChip, 'All'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Queen Pooja'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Queen Rashmika'), findsOneWidget);

    // Verify total photo count header
    expect(find.text('35 Photos'), findsOneWidget);

    // Verify groups with their counts
    expect(find.text('Queen Pooja Main'), findsOneWidget);
    expect(find.text('15 photos'), findsOneWidget);
    expect(find.text('Queen Rashmika Main'), findsOneWidget);
    expect(find.text('20 photos'), findsOneWidget);
  });

  testWidgets('Dashboard banner no longer contains Photo Counts or Folder action pills',
      (tester) async {
    final fakeRepo = _FakeEventRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          eventRepositoryProvider.overrideWithValue(fakeRepo),
          galleryGroupsProvider.overrideWith((_) => Stream.value([])),
        ],
        child: const MaterialApp(
          onGenerateRoute: generateRoute,
          home: Scaffold(
            body: DashboardPage(),
          ),
        ),
      ),
    );

    await tester.pump();

    // Verify Photo Counts and Folder action pills are removed from the banner
    expect(find.text('Photo Counts'), findsNothing);
    expect(find.text('Folder'), findsNothing);

    // Verify Bookmarks pill is still present
    expect(find.text('Bookmarks'), findsOneWidget);
  });
}
