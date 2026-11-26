import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worship_chat/common/utils/app_capabilities.dart';
import 'package:worship_chat/common/utils/app_update_service.dart';
import 'package:worship_chat/common/utils/firebase_notification_service.dart';
import 'package:worship_chat/common/widgets/app_update_dialog.dart';
import 'package:worship_chat/common/widgets/skeleton_loader.dart';
import 'package:worship_chat/common/widgets/user_avatar.dart';
import 'package:worship_chat/features/home/screens/gallery_home_screen.dart';
import 'package:worship_chat/features/home/screens/home_screen.dart';
import 'package:worship_chat/features/settings/screens/settings_screen.dart';
import 'package:worship_chat/models/group.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AppUpdateInfo Model Tests', () {
    test('fromMap parses standard and alternate Firestore field names', () {
      final info = AppUpdateInfo.fromMap({
        'latestVersionCode': 5,
        'latestVersionName': '1.2.0',
        'apkUrl': 'https://cdn.example.com/worship_chat_v1.2.0.apk',
        'releaseNotes': 'Added self-hosted updater',
        'forceUpdate': true,
        'minSupportedVersionCode': 3,
        'sha256': 'ABCD1234',
      });

      expect(info, isNotNull);
      expect(info!.latestVersionCode, 5);
      expect(info.latestVersionName, '1.2.0');
      expect(info.apkUrl, 'https://cdn.example.com/worship_chat_v1.2.0.apk');
      expect(info.releaseNotes, 'Added self-hosted updater');
      expect(info.forceUpdate, isTrue);
      expect(info.minSupportedVersionCode, 3);
      expect(info.sha256, 'abcd1234');
    });

    test('fromMap rejects disabled releases or non-HTTP URLs', () {
      expect(
        AppUpdateInfo.fromMap({
          'enabled': false,
          'latestVersionCode': 2,
          'apkUrl': 'https://cdn.example.com/app.apk',
        }),
        isNull,
      );

      expect(
        AppUpdateInfo.fromMap({
          'latestVersionCode': 2,
          'apkUrl': '/local/path.apk',
        }),
        isNull,
      );

      expect(AppUpdateInfo.fromMap(null), isNull);
    });

    test('isNewerThan compares build number first and falls back to semver', () {
      const info = AppUpdateInfo(
        latestVersionCode: 4,
        latestVersionName: '1.1.0',
        apkUrl: 'https://cdn.example.com/app.apk',
      );

      expect(info.isNewerThan(3, currentVersionName: '1.0.9'), isTrue);
      expect(info.isNewerThan(4, currentVersionName: '1.1.0'), isFalse);
      expect(info.isNewerThan(5, currentVersionName: '1.0.0'), isFalse);

      // Same build number, newer semantic name
      expect(info.isNewerThan(4, currentVersionName: '1.0.9'), isTrue);
    });

    test('isForcedFor honors forceUpdate flag or minSupportedVersionCode', () {
      const forcedByMin = AppUpdateInfo(
        latestVersionCode: 5,
        latestVersionName: '1.2.0',
        apkUrl: 'https://cdn.example.com/app.apk',
        forceUpdate: false,
        minSupportedVersionCode: 3,
      );

      expect(forcedByMin.isForcedFor(2), isTrue);
      expect(forcedByMin.isForcedFor(3), isFalse);
      expect(forcedByMin.isForcedFor(4), isFalse);
    });

    test('fromGitHubReleaseJson parses tags, release APK asset, sha256, and [FORCE]', () {
      final hashHex = 'a' * 64;
      final info = AppUpdateInfo.fromGitHubReleaseJson({
        'tag_name': 'v1.0.2-b4',
        'draft': false,
        'prerelease': false,
        'body': '• Faster wishing\n• Improved duplicate scan\n[FORCE]\nsha256: $hashHex',
        'assets': [
          {
            'name': 'app-debug.apk',
            'browser_download_url': 'https://github.com/spideynk25/worship_chat/releases/download/v1.0.2-b4/app-debug.apk',
          },
          {
            'name': 'app-release.apk',
            'browser_download_url': 'https://github.com/spideynk25/worship_chat/releases/download/v1.0.2-b4/app-release.apk',
          },
        ],
      });

      expect(info, isNotNull);
      expect(info!.latestVersionName, '1.0.2');
      expect(info.latestVersionCode, 4);
      expect(
        info.apkUrl,
        'https://github.com/spideynk25/worship_chat/releases/download/v1.0.2-b4/app-release.apk',
      );
      expect(info.forceUpdate, isTrue);
      expect(info.sha256, hashHex);
      expect(info.releaseNotes, '• Faster wishing\n• Improved duplicate scan');

      // Supports +build tag and skips draft releases
      final plusTag = AppUpdateInfo.fromGitHubReleaseJson({
        'tag_name': 'v1.2.0+7',
        'draft': false,
        'prerelease': false,
        'body': 'Bug fixes',
        'assets': [
          {
            'name': 'worship_chat.apk',
            'browser_download_url': 'https://github.com/spideynk25/worship_chat/releases/download/v1.2.0+7/worship_chat.apk',
          },
        ],
      });
      expect(plusTag?.latestVersionName, '1.2.0');
      expect(plusTag?.latestVersionCode, 7);
      expect(plusTag?.forceUpdate, isFalse);

      expect(
        AppUpdateInfo.fromGitHubReleaseJson({
          'tag_name': 'v1.2.0+7',
          'draft': true,
          'assets': [
            {
              'name': 'app-release.apk',
              'browser_download_url': 'https://github.com/spideynk25/worship_chat/releases/download/v1.2.0+7/app-release.apk',
            },
          ],
        }),
        isNull,
      );
    });
  });

  group('AppUpdateService Check & Verification Tests', () {
    test('Respects skipped version for background auto-check unless forced', () async {
      const optionalUpdate = AppUpdateInfo(
        latestVersionCode: 2,
        latestVersionName: '1.0.1',
        apkUrl: 'https://cdn.example.com/v2.apk',
      );

      final service = AppUpdateService(
        isAndroidOverride: true,
        versionReader: () async => const InstalledAppVersion(
          versionName: '1.0.0',
          versionCode: 1,
        ),
        remoteFetcher: () async => optionalUpdate,
      );

      // Initially detects update
      var outcome = await service.checkForUpdate(respectSkippedVersion: true);
      expect(outcome.status, UpdateCheckStatus.updateAvailable);

      // Skip build 2
      await service.skipVersion(2);

      // Background check honors skip
      outcome = await service.checkForUpdate(respectSkippedVersion: true);
      expect(outcome.status, UpdateCheckStatus.upToDate);

      // Manual check ignores skip
      outcome = await service.checkForUpdate(respectSkippedVersion: false);
      expect(outcome.status, UpdateCheckStatus.updateAvailable);

      // Forced update ignores skip even during background check
      final forcedService = AppUpdateService(
        isAndroidOverride: true,
        versionReader: () async => const InstalledAppVersion(
          versionName: '1.0.0',
          versionCode: 1,
        ),
        remoteFetcher: () async => const AppUpdateInfo(
          latestVersionCode: 2,
          latestVersionName: '1.0.1',
          apkUrl: 'https://cdn.example.com/v2.apk',
          forceUpdate: true,
        ),
      );
      outcome = await forcedService.checkForUpdate(respectSkippedVersion: true);
      expect(outcome.status, UpdateCheckStatus.updateAvailable);
    });

    test('Returns unsupportedPlatform on non-Android and notConfigured when missing doc', () async {
      final nonAndroid = AppUpdateService(
        isAndroidOverride: false,
        versionReader: () async => const InstalledAppVersion(
          versionName: '1.0.0',
          versionCode: 1,
        ),
        remoteFetcher: () async => null,
      );
      expect(
        (await nonAndroid.checkForUpdate()).status,
        UpdateCheckStatus.unsupportedPlatform,
      );

      final notConfigured = AppUpdateService(
        isAndroidOverride: true,
        versionReader: () async => const InstalledAppVersion(
          versionName: '1.0.0',
          versionCode: 1,
        ),
        remoteFetcher: () async => null,
      );
      expect(
        (await notConfigured.checkForUpdate()).status,
        UpdateCheckStatus.notConfigured,
      );
    });

    test('verifySha256IfProvided validates streaming file digest accurately', () async {
      final tempDir = await Directory.systemTemp.createTemp('apk_sha_test_');
      try {
        final apkFile = File('${tempDir.path}/test.apk');
        final bytes = utf8.encode('synthetic apk binary content');
        await apkFile.writeAsBytes(bytes);
        final expected = sha256.convert(bytes).toString();

        final service = AppUpdateService(isAndroidOverride: true);
        expect(await service.verifySha256IfProvided(apkFile, null), isTrue);
        expect(await service.verifySha256IfProvided(apkFile, expected), isTrue);
        expect(
          await service.verifySha256IfProvided(apkFile, expected.toUpperCase()),
          isTrue,
        );
        expect(
          await service.verifySha256IfProvided(apkFile, '0000deadbeef'),
          isFalse,
        );
      } finally {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      }
    });
  });

  group('AppUpdateDialog & Settings Integration Widget Tests', () {
    testWidgets('Optional update dialog renders version diff, notes, Later, Update Now without Skip', (tester) async {
      final service = AppUpdateService(isAndroidOverride: true);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppUpdateDialog(
              service: service,
              installed: const InstalledAppVersion(
                versionName: '1.0.0',
                versionCode: 1,
              ),
              updateInfo: const AppUpdateInfo(
                latestVersionCode: 2,
                latestVersionName: '1.0.1',
                apkUrl: 'https://cdn.example.com/v1.0.1.apk',
                releaseNotes: '• Bug fixes and performance boosts',
                forceUpdate: false,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Update Available'), findsOneWidget);
      expect(find.textContaining('v1.0.0  →  v1.0.1 (Build 2)'), findsOneWidget);
      expect(find.text('• Bug fixes and performance boosts'), findsOneWidget);
      expect(find.text('Skip'), findsNothing);
      expect(find.text('Later'), findsOneWidget);
      expect(find.text('Update Now'), findsOneWidget);

      // Tapping Later closes dialog without persisting a skipped version
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(await service.getSkippedVersionCode(), isNull);
      expect(find.byType(AppUpdateDialog), findsNothing);
    });

    testWidgets('Forced update dialog hides Skip and Later buttons', (tester) async {
      final service = AppUpdateService(isAndroidOverride: true);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppUpdateDialog(
              service: service,
              installed: const InstalledAppVersion(
                versionName: '1.0.0',
                versionCode: 1,
              ),
              updateInfo: const AppUpdateInfo(
                latestVersionCode: 3,
                latestVersionName: '2.0.0',
                apkUrl: 'https://cdn.example.com/v2.0.0.apk',
                forceUpdate: true,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Required Update'), findsOneWidget);
      expect(find.text('Skip'), findsNothing);
      expect(find.text('Later'), findsNothing);
      expect(find.text('Update Now'), findsOneWidget);
    });

    testWidgets('SettingsScreen displays Check for Updates row', (tester) async {
      PackageInfo.setMockInitialValues(
        appName: 'Worship Chat',
        packageName: 'com.shadow.worshipchat',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '',
      );

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('APP UPDATES'), findsOneWidget);
      expect(find.text('Check for Updates'), findsOneWidget);
      expect(find.text('Check'), findsOneWidget);
      expect(find.textContaining('Installed: v1.0.0+1'), findsOneWidget);
    });

    test('availableOutcomeNotifier tracks available updates and clears when upToDate', () async {
      var remoteVersion = 4;
      var remoteName = '1.0.3';
      final service = AppUpdateService(
        isAndroidOverride: true,
        versionReader: () async => const InstalledAppVersion(
          versionName: '1.0.2',
          versionCode: 3,
        ),
        remoteFetcher: () async => AppUpdateInfo(
          latestVersionCode: remoteVersion,
          latestVersionName: remoteName,
          apkUrl: 'https://cdn.example.com/v$remoteVersion.apk',
        ),
      );
      addTearDown(service.resetSessionState);

      expect(service.availableOutcomeNotifier.value, isNull);

      await service.checkForUpdate(respectSkippedVersion: false);
      expect(
        service.availableOutcomeNotifier.value?.status,
        UpdateCheckStatus.updateAvailable,
      );
      expect(
        service.availableOutcomeNotifier.value?.updateInfo?.latestVersionCode,
        4,
      );

      // Simulate installed build matching remote build
      remoteVersion = 3;
      remoteName = '1.0.2';
      await service.checkForUpdate(respectSkippedVersion: false);
      expect(service.availableOutcomeNotifier.value, isNull);
    });

    testWidgets('HomeScreen shows "1" badge on profile avatar and Update button in dropdown when update exists', (tester) async {
      AppCapabilities.debugOverride = const AppCapabilities(
        platform: TargetPlatform.macOS,
        isTablet: false,
      );
      AppUpdateService.instance.resetSessionState();
      addTearDown(() {
        AppCapabilities.debugOverride = null;
        AppUpdateService.instance.resetSessionState();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            galleryGroupsProvider.overrideWith(
              (_) => Stream.value(<GroupModel>[]),
            ),
          ],
          child: const MaterialApp(
            home: HomeScreen(initialIndex: 0),
          ),
        ),
      );
      await tester.pump();

      // Username uses 10s-interval golden ShimmerEffect and avatar Hero has no ring Container
      final shimmer = tester.widget<ShimmerEffect>(find.byType(ShimmerEffect));
      expect(shimmer.duration, const Duration(seconds: 10));
      expect(shimmer.activeFraction, 0.14);
      final avatarHero = tester.widget<Hero>(find.byType(Hero).first);
      expect(avatarHero.child, isA<UserAvatar>());

      // Initially no badge and no Update dropdown button
      expect(find.text('1'), findsNothing);
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Update'), findsNothing);
      await tester.tapAt(const Offset(10, 10));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // Broadcast an available update
      AppUpdateService.instance.availableOutcomeNotifier.value =
          const UpdateCheckOutcome(
            status: UpdateCheckStatus.updateAvailable,
            installed: InstalledAppVersion(
              versionName: '1.0.2',
              versionCode: 3,
            ),
            updateInfo: AppUpdateInfo(
              latestVersionCode: 4,
              latestVersionName: '1.0.3',
              apkUrl: 'https://cdn.example.com/v1.0.3.apk',
              releaseNotes: '• Fresh release',
            ),
          );
      await tester.pump();

      // Profile pic now shows circular "1" reminder badge
      expect(find.text('1'), findsOneWidget);

      // Opening dropdown shows Update + version pill at top
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Update'), findsOneWidget);
      expect(find.text('v1.0.3'), findsOneWidget);

      // Tapping Update opens AppUpdateDialog cleanly
      await tester.tap(find.text('Update'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(AppUpdateDialog), findsOneWidget);
      expect(find.text('Later'), findsOneWidget);

      // Dismissing with Later keeps the "1" reminder badge visible
      await tester.tap(find.text('Later'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(AppUpdateDialog), findsNothing);
      expect(find.text('1'), findsOneWidget);
    });

    test('pushes update notification once per release build and clears when up to date', () async {
      AppCapabilities.debugOverride = const AppCapabilities(
        platform: TargetPlatform.android,
        isTablet: false,
      );
      addTearDown(AppCapabilities.resetForTests);

      final sentNotifications = <Map<String, dynamic>>[];
      var cancelCalls = 0;
      var remoteCode = 6;
      var remoteName = '1.0.5';

      final service = AppUpdateService(
        isAndroidOverride: true,
        versionReader: () async => const InstalledAppVersion(
          versionName: '1.0.4',
          versionCode: 5,
        ),
        remoteFetcher: () async => AppUpdateInfo(
          latestVersionCode: remoteCode,
          latestVersionName: remoteName,
          apkUrl: 'https://cdn.example.com/v$remoteName.apk',
          releaseNotes: '• Improved chat search\n• Faster sync',
        ),
        notificationSender: ({
          required String versionName,
          required int versionCode,
          String? releaseNotes,
          bool forceUpdate = false,
        }) async {
          sentNotifications.add({
            'versionName': versionName,
            'versionCode': versionCode,
            'releaseNotes': releaseNotes,
            'forceUpdate': forceUpdate,
          });
        },
        notificationCanceller: () async => cancelCalls++,
      );
      addTearDown(service.resetSessionState);

      // 1st discovery of v1.0.5+6 -> notifies
      await service.checkForUpdate(respectSkippedVersion: false);
      expect(sentNotifications.length, 1);
      expect(sentNotifications.first['versionName'], '1.0.5');
      expect(sentNotifications.first['versionCode'], 6);

      // Repeated check for the same build -> deduplicated, no spam
      await service.checkForUpdate(respectSkippedVersion: false);
      expect(sentNotifications.length, 1);

      // Newer release v1.0.6+7 -> pushes a fresh notification
      remoteCode = 7;
      remoteName = '1.0.6';
      await service.checkForUpdate(respectSkippedVersion: false);
      expect(sentNotifications.length, 2);
      expect(sentNotifications.last['versionCode'], 7);

      // Once user installs the latest version -> cancels stale update notification
      remoteCode = 5;
      remoteName = '1.0.4';
      await service.checkForUpdate(respectSkippedVersion: false);
      expect(cancelCalls, 1);
    });

    testWidgets('checkForUpdateOnResume obeys cooldown and notifies once expired', (tester) async {
      AppCapabilities.debugOverride = const AppCapabilities(
        platform: TargetPlatform.android,
        isTablet: false,
      );
      addTearDown(AppCapabilities.resetForTests);

      var now = DateTime(2026, 11, 26, 8, 0);
      var fetchCount = 0;
      var notifyCount = 0;

      final service = AppUpdateService(
        isAndroidOverride: true,
        nowProvider: () => now,
        versionReader: () async => const InstalledAppVersion(
          versionName: '1.0.4',
          versionCode: 5,
        ),
        remoteFetcher: () async {
          fetchCount++;
          return const AppUpdateInfo(
            latestVersionCode: 6,
            latestVersionName: '1.0.5',
            apkUrl: 'https://cdn.example.com/v1.0.5.apk',
          );
        },
        notificationSender: ({
          required String versionName,
          required int versionCode,
          String? releaseNotes,
          bool forceUpdate = false,
        }) async {
          notifyCount++;
        },
        notificationCanceller: () async {},
      );
      addTearDown(service.resetSessionState);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () => service.checkForUpdateOnResume(context),
                child: const Text('Resume'),
              );
            },
          ),
        ),
      );

      // Initial resume check runs and notifies
      await tester.tap(find.text('Resume'));
      await tester.pumpAndSettle();
      expect(fetchCount, 1);
      expect(notifyCount, 1);

      // 30 minutes later -> skipped due to 2-hour cooldown
      now = now.add(const Duration(minutes: 30));
      await tester.tap(find.text('Resume'));
      await tester.pumpAndSettle();
      expect(fetchCount, 1);

      // 3 hours later -> runs check again cleanly without duplicating notification
      now = now.add(const Duration(hours: 3));
      await tester.tap(find.text('Resume'));
      await tester.pumpAndSettle();
      expect(fetchCount, 2);
      expect(notifyCount, 1);
    });

    test('FirebaseNotificationService routes remote app_update FCM payload onto app_updates_channel', () async {
      AppCapabilities.debugOverride = const AppCapabilities(
        platform: TargetPlatform.android,
        isTablet: false,
      );
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      FlutterLocalNotificationsPlatform.instance =
          AndroidFlutterLocalNotificationsPlugin();

      final calls = <MethodCall>[];
      const channel = MethodChannel('dexterous.com/flutter/local_notifications');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return true;
      });
      addTearDown(() {
        AppCapabilities.resetForTests();
        debugDefaultTargetPlatformOverride = null;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      await FirebaseNotificationService.showNotificationFromRemoteMessage(
        const RemoteMessage(
          data: {
            'type': 'app_update',
            'versionName': '1.0.5',
            'versionCode': '6',
            'releaseNotes': 'Search fixes and update notifications',
          },
        ),
      );

      final showCalls = calls.where((c) => c.method == 'show').toList();
      expect(showCalls.length, 1);
      final args = Map<String, dynamic>.from(showCalls.first.arguments as Map);
      expect(args['id'], FirebaseNotificationService.appUpdateNotificationId);
      expect(args['title'].toString(), contains('1.0.5'));
      expect(args['payload'].toString(), contains('"type":"app_update"'));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('notified_update_version_code'), 6);
    });
  });
}
