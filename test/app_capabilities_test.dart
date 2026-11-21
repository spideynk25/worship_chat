import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worship_chat/common/utils/app_capabilities.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('worship_chat/device');

  setUp(() {
    AppCapabilities.resetForTests();
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() {
    AppCapabilities.resetForTests();
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'chat and notifications are exclusive to native Android and iOS phones',
    () {
      for (final platform in TargetPlatform.values) {
        for (final tablet in [false, true]) {
          final capabilities = AppCapabilities(
            platform: platform,
            isTablet: tablet,
          );
          final phone =
              !tablet &&
              (platform == TargetPlatform.android ||
                  platform == TargetPlatform.iOS);
          expect(
            capabilities.chatEnabled,
            phone,
            reason: '$platform tablet=$tablet',
          );
          expect(capabilities.notificationsEnabled, phone);
          expect(
            AppCapabilities(
              platform: platform,
              isTablet: tablet,
              isWeb: true,
            ).chatEnabled,
            isFalse,
          );
        }
      }
    },
  );

  testWidgets('a tablet stays gallery-only when its window is phone-sized', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => true);

    await AppCapabilities.initialize();
    expect(AppCapabilities.current.isTablet, isTrue);
    expect(AppCapabilities.current.chatEnabled, isFalse);
    expect(
      (await SharedPreferences.getInstance()).getBool('phone_chat_enabled'),
      isFalse,
    );
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'native phone classification enables messaging and persists for background work',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => false);
      await AppCapabilities.initialize();
      expect(AppCapabilities.current.notificationsEnabled, isTrue);

      AppCapabilities.resetForTests();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (_) async => throw StateError('Background must not call activity'),
          );
      await AppCapabilities.initialize(background: true);
      expect(AppCapabilities.current.notificationsEnabled, isTrue);
    },
  );

  test(
    'a background isolate with no saved phone classification denies notifications',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await AppCapabilities.initialize(background: true);
      expect(AppCapabilities.current.notificationsEnabled, isFalse);
    },
  );

  test('desktop startup needs no mobile native channel', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => throw StateError('Desktop must not call mobile channel'),
        );
    await AppCapabilities.initialize();
    expect(AppCapabilities.current.isDesktop, isTrue);
    expect(AppCapabilities.current.notificationsEnabled, isFalse);
  });
}
