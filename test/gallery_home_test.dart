import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_chat/common/utils/app_capabilities.dart';
import 'package:worship_chat/common/widgets/chat_unavailable_screen.dart';
import 'package:worship_chat/features/chat/screens/one_to_one_chat_screen.dart';
import 'package:worship_chat/features/home/screens/gallery_home_screen.dart';
import 'package:worship_chat/models/group.dart';
import 'package:worship_chat/router.dart';

GroupModel gallery(String id, String name, String category) => GroupModel(
  senderId: '',
  name: name,
  groupId: id,
  lastMessage: 'Private chat preview',
  groupPic: '',
  membersUid: [],
  fcmTokens: [],
  unseenMessages: {},
  queendom: category,
  galleryCount: 5,
);

void main() {
  tearDown(() => AppCapabilities.debugOverride = null);

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.iOS,
    TargetPlatform.android,
  ]) {
    testWidgets(
      '$platform uses gallery home without chat or Firebase startup',
      (tester) async {
        AppCapabilities.debugOverride = AppCapabilities(
          platform: platform,
          isTablet: true,
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              galleryGroupsProvider.overrideWith((_) => Stream.value([])),
            ],
            child: const MaterialApp(home: GalleryHomeScreen()),
          ),
        );
        await tester.pump();
        expect(find.text('Worship Gallery'), findsOneWidget);
        expect(find.text('Chats'), findsNothing);
        expect(find.byIcon(Icons.comment), findsNothing);
        expect(
          find.text('Your group galleries will appear here.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);

        await tester.tap(find.byType(PopupMenuButton<String>));
        await tester.pumpAndSettle();
        expect(find.text('Profile'), findsOneWidget);
        expect(find.text('Logout'), findsOneWidget);
        expect(find.text('Create Group'), findsNothing);
      },
    );
  }

  testWidgets(
    'gallery home searches and filters groups without displaying chat previews',
    (tester) async {
      AppCapabilities.debugOverride = const AppCapabilities(
        platform: TargetPlatform.macOS,
        isTablet: false,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            galleryGroupsProvider.overrideWith(
              (_) => Stream.value([
                gallery('a', 'Pooja Photos', 'Queen Pooja'),
                gallery('b', 'Rashmika Photos', 'Queen Rashmika'),
                gallery('c', 'Family Photos', 'None'),
              ]),
            ),
          ],
          child: const MaterialApp(home: GalleryHomeScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Private chat preview'), findsNothing);
      expect(find.textContaining('Family Photos'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Queen Pooja'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Pooja Photos'), findsOneWidget);
      expect(find.textContaining('Family Photos'), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
      await tester.enterText(find.byType(TextField), 'family');
      await tester.pumpAndSettle();
      expect(find.textContaining('Family Photos'), findsOneWidget);
      expect(find.textContaining('Pooja Photos'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('tablet chat routes reject arguments before constructing chat', (
    tester,
  ) async {
    AppCapabilities.debugOverride = const AppCapabilities(
      platform: TargetPlatform.iOS,
      isTablet: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        onGenerateRoute: generateRoute,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                Navigator.pushNamed(context, OneToOneChatScreen.routeName),
            child: const Text('Open saved chat link'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open saved chat link'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatUnavailableScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('direct chat widgets on Windows never start chat listeners', (
    tester,
  ) async {
    AppCapabilities.debugOverride = const AppCapabilities(
      platform: TargetPlatform.windows,
      isTablet: false,
    );
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: OneToOneChatScreen(
            name: 'Contact',
            uid: 'contact',
            fcmToken: '',
            profilePic: null,
            unseenCount: false,
            chatBackgroundUrl: null,
          ),
        ),
      ),
    );
    expect(find.byType(ChatUnavailableScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('gallery errors fit a short resized desktop window', (
    tester,
  ) async {
    AppCapabilities.debugOverride = const AppCapabilities(
      platform: TargetPlatform.windows,
      isTablet: false,
    );
    tester.view.physicalSize = const Size(320, 240);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          galleryGroupsProvider.overrideWith(
            (_) => Stream.error(StateError('offline')),
          ),
        ],
        child: const MaterialApp(home: GalleryHomeScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Unable to load galleries.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'gallery home displays multi-shuffle button and action chip',
    (tester) async {
      AppCapabilities.debugOverride = const AppCapabilities(
        platform: TargetPlatform.macOS,
        isTablet: false,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            galleryGroupsProvider.overrideWith(
              (_) => Stream.value([
                gallery('a', 'Pooja Photos', 'Queen Pooja'),
                gallery('b', 'Rashmika Photos', 'Queen Rashmika'),
              ]),
            ),
          ],
          child: const MaterialApp(home: GalleryHomeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Multi Gallery Shuffle action button exists in AppBar
      expect(find.byTooltip('Multi Gallery Shuffle'), findsOneWidget);

      // Verify Multi Shuffle ActionChip exists
      expect(find.widgetWithText(ActionChip, 'Multi Shuffle'), findsOneWidget);

      // Tap Multi Gallery Shuffle button to open bottom sheet
      await tester.tap(find.byTooltip('Multi Gallery Shuffle'));
      await tester.pumpAndSettle();

      // Bottom sheet should open with title "Multi-Gallery Shuffle"
      expect(find.text('Multi-Gallery Shuffle'), findsOneWidget);
      expect(
        find.text('Combine & shuffle photos across multiple groups'),
        findsOneWidget,
      );
    },
  );
}
