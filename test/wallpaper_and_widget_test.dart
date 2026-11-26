import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worship_chat/common/utils/home_widget_service.dart';
import 'package:worship_chat/common/utils/phone_wallpaper_service.dart';
import 'package:worship_chat/common/widgets/wallpaper_widget_sheet.dart';
import 'package:worship_chat/features/settings/screens/home_widget_settings_screen.dart';
import 'package:worship_chat/features/settings/screens/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const deviceChannel = MethodChannel('worship_chat/device');

  late Directory tempDir;
  late List<MethodCall> recordedCalls;
  late int mockNativeCurrentIndex;
  late int mockInstalledWidgetCount;
  late bool mockCanPin;
  late bool mockWallpaperSuccess;
  String? mockWallpaperErrorCode;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tempDir = Directory.systemTemp.createTempSync('worship_widget_test_');
    recordedCalls = [];
    mockNativeCurrentIndex = 0;
    mockInstalledWidgetCount = 1;
    mockCanPin = true;
    mockWallpaperSuccess = true;
    mockWallpaperErrorCode = null;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(deviceChannel, (call) async {
      recordedCalls.add(call);
      switch (call.method) {
        case 'updatePhotoWidget':
          final args = call.arguments as Map?;
          if (args != null && args['currentIndex'] is num) {
            mockNativeCurrentIndex = (args['currentIndex'] as num).toInt();
          }
          return true;
        case 'nextPhotoWidget':
          mockNativeCurrentIndex++;
          return true;
        case 'requestPinPhotoWidget':
          return mockCanPin;
        case 'getPhotoWidgetInfo':
          return <String, dynamic>{
            'installedCount': mockInstalledWidgetCount,
            'canPin': mockCanPin,
            'currentIndex': mockNativeCurrentIndex,
          };
        case 'setWallpaper':
          if (mockWallpaperErrorCode != null) {
            throw PlatformException(
              code: mockWallpaperErrorCode!,
              message: 'Simulated wallpaper failure',
            );
          }
          return mockWallpaperSuccess;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(deviceChannel, null);
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
    HomeWidgetService.instance.configNotifier.value = const HomeWidgetConfig();
  });

  File createSampleImageFile(String name) {
    final file = File('${tempDir.path}/$name');
    file.writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0, 0x01, 0x02, 0x03]);
    return file;
  }

  group('HomeWidgetConfig Unit Tests', () {
    test('copyWith wraps currentIndex cleanly within playlist bounds', () {
      const photos = [
        HomeWidgetPhoto(id: '1', localPath: '/tmp/a.jpg', title: 'One'),
        HomeWidgetPhoto(id: '2', localPath: '/tmp/b.jpg', title: 'Two'),
      ];
      const base = HomeWidgetConfig(photos: photos, currentIndex: 0);

      expect(base.copyWith(currentIndex: 2).currentIndex, 0);
      expect(base.copyWith(currentIndex: -1).currentIndex, 1);
      expect(base.copyWith(photos: const []).currentIndex, 0);
    });

    test('JSON roundtrip preserves fields and handles invalid payloads', () {
      const config = HomeWidgetConfig(
        photos: [
          HomeWidgetPhoto(
            id: 'p1',
            localPath: '/data/p1.jpg',
            sourceUrl: 'https://example.com/p1.jpg',
            title: 'Grace',
            subtitle: 'Collection',
          ),
        ],
        currentIndex: 0,
        showTitle: false,
        intervalMinutes: 360,
        sourceLabel: 'Royal Favorites',
      );

      final parsed = HomeWidgetConfig.fromJsonString(config.toJsonString());
      expect(parsed.photos.length, 1);
      expect(parsed.photos.first.id, 'p1');
      expect(parsed.photos.first.title, 'Grace');
      expect(parsed.showTitle, isFalse);
      expect(parsed.intervalMinutes, 360);
      expect(parsed.sourceLabel, 'Royal Favorites');

      final fallback = HomeWidgetConfig.fromJsonString('{broken json');
      expect(fallback.photos, isEmpty);
      expect(fallback.intervalMinutes, 60);
      expect(fallback.showTitle, isTrue);
    });
  });

  group('HomeWidgetService Unit Tests', () {
    test('pinSinglePhoto materializes offline file, deduplicates, and updates Android widget', () async {
      final sample1 = createSampleImageFile('first.jpg');
      final sample2 = createSampleImageFile('second.png');

      final service = HomeWidgetService(
        directoryProviderOverride: () async => tempDir,
        isAndroidOverride: true,
      );

      final ok1 = await service.pinSinglePhoto(
        HomeWidgetPhotoInput(
          id: 'photo_1',
          localPath: sample1.path,
          title: 'Morning Praise',
          subtitle: 'Gallery',
        ),
      );
      expect(ok1, isTrue);

      final ok2 = await service.pinSinglePhoto(
        HomeWidgetPhotoInput(
          id: 'photo_2',
          localPath: sample2.path,
          title: 'Evening Glory',
          subtitle: 'Collection',
        ),
      );
      expect(ok2, isTrue);

      // Re-pinning photo_1 moves it to index 0 without duplicating
      final repin = await service.pinSinglePhoto(
        HomeWidgetPhotoInput(
          id: 'photo_1',
          localPath: sample1.path,
          title: 'Morning Praise',
          subtitle: 'Gallery',
        ),
      );
      expect(repin, isTrue);

      final config = await service.loadConfig();
      expect(config.photos.length, 2);
      expect(config.photos.first.id, 'photo_1');
      expect(File(config.photos.first.localPath).existsSync(), isTrue);

      final updateCalls =
          recordedCalls.where((c) => c.method == 'updatePhotoWidget').toList();
      expect(updateCalls.length, 3);
      final latestArgs = Map<String, dynamic>.from(updateCalls.last.arguments);
      expect((latestArgs['photos'] as List).length, 2);
      expect(latestArgs['currentIndex'], 0);
    });

    test('syncPlaylist caps at 24 photos, prunes removed cache files, and rotates index', () async {
      final service = HomeWidgetService(
        directoryProviderOverride: () async => tempDir,
        isAndroidOverride: true,
      );

      final firstPhoto = createSampleImageFile('keep_old.jpg');
      await service.pinSinglePhoto(
        HomeWidgetPhotoInput(id: 'old_one', localPath: firstPhoto.path),
      );
      final oldCachedPath = (await service.loadConfig()).photos.first.localPath;
      expect(File(oldCachedPath).existsSync(), isTrue);

      final inputs = List.generate(30, (i) {
        final f = createSampleImageFile('batch_$i.jpg');
        return HomeWidgetPhotoInput(
          id: 'item_$i',
          localPath: f.path,
          title: 'Title $i',
        );
      });

      final syncedCount = await service.syncPlaylist(
        items: inputs,
        sourceLabel: 'Sunday Worship',
      );
      expect(syncedCount, HomeWidgetService.maxPlaylistLength);
      expect(File(oldCachedPath).existsSync(), isFalse);

      var loaded = await service.loadConfig();
      expect(loaded.sourceLabel, 'Sunday Worship');
      expect(loaded.photos.length, 24);
      expect(loaded.currentIndex, 0);

      await service.nextPhoto();
      loaded = await service.loadConfig();
      expect(loaded.currentIndex, 1);

      await service.updatePreferences(showTitle: false, intervalMinutes: 30);
      loaded = await service.loadConfig();
      expect(loaded.showTitle, isFalse);
      expect(loaded.intervalMinutes, 30);

      await service.removePhoto('item_0');
      loaded = await service.loadConfig();
      expect(loaded.photos.length, 23);

      await service.clearAll();
      loaded = await service.loadConfig();
      expect(loaded.photos, isEmpty);
    });

    test('loadConfig reconciles native index and requestPinWidget forwards platform check', () async {
      final f1 = createSampleImageFile('s1.jpg');
      final f2 = createSampleImageFile('s2.jpg');

      final service = HomeWidgetService(
        directoryProviderOverride: () async => tempDir,
        isAndroidOverride: true,
      );
      await service.syncPlaylist(
        items: [
          HomeWidgetPhotoInput(id: 'a', localPath: f1.path),
          HomeWidgetPhotoInput(id: 'b', localPath: f2.path),
        ],
        sourceLabel: 'Test',
      );

      mockNativeCurrentIndex = 1;
      final loaded = await service.loadConfig();
      expect(loaded.currentIndex, 1);

      expect(await service.requestPinWidget(), isTrue);

      final desktopService = HomeWidgetService(
        directoryProviderOverride: () async => tempDir,
        isAndroidOverride: false,
      );
      expect(await desktopService.requestPinWidget(), isFalse);
    });
  });

  group('PhoneWallpaperService Unit Tests', () {
    test('returns unsupported message when not on Android', () async {
      final service = PhoneWallpaperService(isAndroidOverride: false);
      final result = await service.applyWallpaper(
        localPath: '/tmp/any.jpg',
        target: WallpaperTarget.home,
      );
      expect(result.success, isFalse);
      expect(result.message, contains('Android'));
    });

    test('resolves local and cached remote files and sends target key cleanly', () async {
      final local = createSampleImageFile('wall.jpg');
      final remoteCached = createSampleImageFile('remote_cached.jpg');

      final service = PhoneWallpaperService(
        isAndroidOverride: true,
        resolverOverride: (_) async => remoteCached.path,
      );

      final localResult = await service.applyWallpaper(
        localPath: local.path,
        target: WallpaperTarget.lock,
      );
      expect(localResult.success, isTrue);
      expect(localResult.message, contains('Lock Screen'));

      final remoteResult = await service.applyWallpaper(
        imageUrl: 'https://cdn.example.com/photo.jpg',
        target: WallpaperTarget.both,
      );
      expect(remoteResult.success, isTrue);

      final calls =
          recordedCalls.where((c) => c.method == 'setWallpaper').toList();
      expect(calls.length, 2);
      expect(calls[0].arguments, {
        'path': local.path,
        'target': 'lock',
      });
      expect(calls[1].arguments, {
        'path': remoteCached.path,
        'target': 'both',
      });
    });

    test('handles missing file and native PlatformException gracefully', () async {
      final local = createSampleImageFile('wall_err.jpg');
      final service = PhoneWallpaperService(isAndroidOverride: true);

      final missingResult = await service.applyWallpaper(
        localPath: '${tempDir.path}/does_not_exist.jpg',
        target: WallpaperTarget.home,
      );
      expect(missingResult.success, isFalse);

      mockWallpaperErrorCode = 'WALLPAPER_ERROR';
      final errorResult = await service.applyWallpaper(
        localPath: local.path,
        target: WallpaperTarget.home,
      );
      expect(errorResult.success, isFalse);
      expect(errorResult.message, contains('Simulated wallpaper failure'));
    });
  });

  group('Wallpaper & Widget UI Tests', () {
    testWidgets('WallpaperAndWidgetSheet renders actions and toggles crop switch', (tester) async {
      final sample = createSampleImageFile('ui_preview.jpg');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WallpaperAndWidgetSheet(
              photoId: 'ui_1',
              localPath: sample.path,
              title: 'Royal Queen',
              subtitle: 'Gallery',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Wallpaper & Home Widget'), findsOneWidget);
      expect(find.text('Royal Queen'), findsOneWidget);
      expect(find.text('Crop to Screen Before Applying'), findsOneWidget);
      expect(find.text('Home Screen Wallpaper'), findsOneWidget);
      expect(find.text('Lock Screen Wallpaper'), findsOneWidget);
      expect(find.text('Both Home & Lock Screens'), findsOneWidget);
      expect(find.text('Pin Photo to Home Widget'), findsOneWidget);
      expect(find.text('Widget Settings & Collection Sync'), findsOneWidget);

      final cropSwitch = tester.widget<Switch>(find.byType(Switch));
      expect(cropSwitch.value, isFalse);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      final updatedSwitch = tester.widget<Switch>(find.byType(Switch));
      expect(updatedSwitch.value, isTrue);
    });

    testWidgets('HomeWidgetSettingsScreen displays controls and updates rotation interval & caption', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: HomeWidgetSettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Home Screen Widget'), findsOneWidget);
      expect(find.text('No Photos Pinned'), findsOneWidget);
      expect(find.text('SYNC SOURCE'), findsOneWidget);
      expect(find.text('WIDGET PREFERENCES'), findsOneWidget);
      expect(find.text('Add Widget to Home Screen'), findsOneWidget);
      expect(find.text('Sync Bookmark Collection'), findsOneWidget);
      expect(find.text('Sync Group Gallery'), findsOneWidget);
      expect(find.text('Every 30m'), findsOneWidget);
      expect(find.text('Show Photo Caption'), findsOneWidget);

      await tester.ensureVisible(find.text('Every 30m'));
      await tester.tap(find.text('Every 30m'));
      await tester.pumpAndSettle();

      expect(HomeWidgetService.instance.configNotifier.value.intervalMinutes, 30);

      await tester.ensureVisible(find.text('Show Photo Caption'));
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(HomeWidgetService.instance.configNotifier.value.showTitle, isFalse);
    });

    testWidgets('SettingsScreen lists Home Screen Widget and navigates to HomeWidgetSettingsScreen', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Home Screen Widget'), findsOneWidget);
      expect(
        find.text('Android photo widget playlist, rotation & preview'),
        findsOneWidget,
      );

      await tester.tap(find.text('Home Screen Widget'));
      await tester.pumpAndSettle();

      expect(find.byType(HomeWidgetSettingsScreen), findsOneWidget);
      expect(find.text('SYNC SOURCE'), findsOneWidget);
      expect(find.text('WIDGET PREFERENCES'), findsOneWidget);
    });
  });
}
