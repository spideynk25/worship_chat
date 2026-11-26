import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_chat/common/utils/app_capabilities.dart';
import 'package:worship_chat/features/home/screens/gallery_home_screen.dart';
import 'package:worship_chat/features/home/screens/home_screen.dart';
import 'package:worship_chat/models/group.dart';

void main() {
  tearDown(() => AppCapabilities.debugOverride = null);

  group('Adaptive Platform Features & Navigation Tests', () {
    test('AppCapabilities correctly sets chatEnabled to false for macOS, Windows, and Tablets', () {
      // macOS desktop
      final macosCap = AppCapabilities(platform: TargetPlatform.macOS, isTablet: false);
      expect(macosCap.chatEnabled, isFalse);
      expect(macosCap.notificationsEnabled, isFalse);
      expect(macosCap.isDesktop, isTrue);

      // Windows desktop
      final winCap = AppCapabilities(platform: TargetPlatform.windows, isTablet: false);
      expect(winCap.chatEnabled, isFalse);
      expect(winCap.notificationsEnabled, isFalse);
      expect(winCap.isDesktop, isTrue);

      // Android tablet
      final androidTabletCap = AppCapabilities(platform: TargetPlatform.android, isTablet: true);
      expect(androidTabletCap.chatEnabled, isFalse);
      expect(androidTabletCap.notificationsEnabled, isFalse);
      expect(androidTabletCap.isTablet, isTrue);

      // iOS iPad / tablet
      final iosTabletCap = AppCapabilities(platform: TargetPlatform.iOS, isTablet: true);
      expect(iosTabletCap.chatEnabled, isFalse);
      expect(iosTabletCap.notificationsEnabled, isFalse);
      expect(iosTabletCap.isTablet, isTrue);

      // Android mobile phone retains chat
      final androidPhoneCap = AppCapabilities(platform: TargetPlatform.android, isTablet: false);
      expect(androidPhoneCap.chatEnabled, isTrue);
      expect(androidPhoneCap.notificationsEnabled, isTrue);
    });

    testWidgets('HomeScreen on desktop/tablet presents 3 tabs without Chats, Groups, or Chat FAB', (tester) async {
      AppCapabilities.debugOverride = const AppCapabilities(
        platform: TargetPlatform.macOS,
        isTablet: false,
      );

      tester.view.physicalSize = const Size(1280, 800);
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

      // Header indicates Worship Gallery
      expect(find.text('Worship Gallery'), findsOneWidget);

      // Core 3 tabs exist in side navigation rail
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Pooja'), findsWidgets);
      expect(find.text('Rashmika'), findsWidgets);
      expect(find.text('Groups'), findsNothing);
      expect(find.text('Gallery'), findsNothing);

      // Chat tab and chat action button are absent
      expect(find.text('Chats'), findsNothing);
      expect(find.byIcon(Icons.comment), findsNothing);
    });

    testWidgets('HomeScreen wide layout (>= 720px) uses royal Side Navigation Rail', (tester) async {
      AppCapabilities.debugOverride = const AppCapabilities(
        platform: TargetPlatform.windows,
        isTablet: false,
      );

      tester.view.physicalSize = const Size(1280, 800);
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

      // Wide layout displays the royal Side Navigation Rail container
      expect(find.text('Worship Gallery'), findsWidgets);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Groups'), findsNothing);
      expect(find.text('Gallery'), findsNothing);
    });

    testWidgets('HomeScreen compact layout (< 720px) uses modern Bottom Navigation Bar', (tester) async {
      AppCapabilities.debugOverride = const AppCapabilities(
        platform: TargetPlatform.android,
        isTablet: true,
      );

      tester.view.physicalSize = const Size(600, 900);
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

      // Compact layout renders all 3 tabs in the modern bottom bar (icon & photo only)
      expect(find.text('Home'), findsNothing); // icon/photo-only without text labels
      expect(find.bySemanticsLabel('Home'), findsOneWidget);
      expect(find.byIcon(Icons.groups_rounded), findsNothing);
      expect(find.byIcon(Icons.photo_library_rounded), findsNothing);
      expect(find.text('Gallery'), findsNothing);
      expect(find.text('Chats'), findsNothing);
    });

    testWidgets('HomeScreen defaults to index 0 on desktop/tablet when initialIndex is omitted', (tester) async {
      AppCapabilities.debugOverride = const AppCapabilities(
        platform: TargetPlatform.macOS,
        isTablet: false,
      );

      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            galleryGroupsProvider.overrideWith((_) => Stream.value(<GroupModel>[])),
          ],
          child: const MaterialApp(
            home: HomeScreen(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Chats'), findsNothing);
    });

    test('HomeScreen tab index logic selects Chats (index 1) for mobile and Home (index 0) for gallery', () {
      AppCapabilities.debugOverride = const AppCapabilities(
        platform: TargetPlatform.android,
        isTablet: false,
      );
      expect(AppCapabilities.current.chatEnabled ? 1 : 0, equals(1));

      AppCapabilities.debugOverride = const AppCapabilities(
        platform: TargetPlatform.macOS,
        isTablet: false,
      );
      expect(AppCapabilities.current.chatEnabled ? 1 : 0, equals(0));
    });
  });
}
