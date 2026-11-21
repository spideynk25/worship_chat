import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_chat/common/utils/app_capabilities.dart';
import 'package:worship_chat/common/utils/background_task_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<MethodCall> deviceMethodCalls = [];
  final List<MethodCall> notificationMethodCalls = [];

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    FlutterLocalNotificationsPlatform.instance = AndroidFlutterLocalNotificationsPlugin();
    deviceMethodCalls.clear();
    notificationMethodCalls.clear();
    BackgroundTaskService.instance.resetForTests();
    AppCapabilities.resetForTests();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('worship_chat/device'),
      (MethodCall call) async {
        deviceMethodCalls.add(call);
        return true;
      },
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      (MethodCall call) async {
        notificationMethodCalls.add(call);
        return true;
      },
    );
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
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
  });

  group('BackgroundTaskService Tests', () {
    test('initial state has no active tasks', () {
      final service = BackgroundTaskService.instance;
      expect(service.hasActiveTasks, isFalse);
      expect(service.activeTaskCount, equals(0));
    });

    test('startTask and completeTask correctly track active task count', () async {
      final service = BackgroundTaskService.instance;

      final taskId1 = await service.startTask(
        title: 'Sending photo',
        initialMessage: 'Uploading...',
      );
      expect(taskId1, isNotNull);
      expect(service.hasActiveTasks, isTrue);
      expect(service.activeTaskCount, equals(1));

      final taskId2 = await service.startTask(
        title: 'Downloading ZIP',
        initialMessage: 'Downloading...',
      );
      expect(taskId2, isNotNull);
      expect(service.activeTaskCount, equals(2));

      await service.updateProgress(
        taskId2,
        title: 'Downloading ZIP',
        message: 'Downloading photo 5 of 10...',
        progress: 5,
        maxProgress: 10,
      );

      await service.completeTask(
        taskId1,
        title: 'Sending photo',
        message: 'Photo sent',
      );
      expect(service.activeTaskCount, equals(1));
      expect(service.hasActiveTasks, isTrue);

      await service.completeTask(
        taskId2,
        title: 'Downloading ZIP',
        message: 'Saved to Downloads',
      );
      expect(service.activeTaskCount, equals(0));
      expect(service.hasActiveTasks, isFalse);
    });

    test('runWithBackgroundTask returns result and cleans up state on success', () async {
      final service = BackgroundTaskService.instance;

      final result = await service.runWithBackgroundTask<String>(
        title: 'Uploading to Gallery',
        initialMessage: 'Preparing...',
        successMessage: 'Uploaded 5 photos',
        task: (updateProgress) async {
          expect(service.hasActiveTasks, isTrue);
          updateProgress('Uploading 1 of 5...', progress: 1, maxProgress: 5);
          updateProgress('Uploading 5 of 5...', progress: 5, maxProgress: 5);
          return 'upload_complete_result';
        },
      );

      expect(result, equals('upload_complete_result'));
      expect(service.hasActiveTasks, isFalse);
      expect(service.activeTaskCount, equals(0));
    });

    test('runWithBackgroundTask cleans up state and propagates error on failure', () async {
      final service = BackgroundTaskService.instance;

      await expectLater(
        service.runWithBackgroundTask<void>(
          title: 'Failing transfer',
          initialMessage: 'Starting...',
          task: (updateProgress) async {
            throw Exception('Network disconnected');
          },
        ),
        throwsA(isA<Exception>()),
      );

      // Even after failure, task count must be cleaned up
      expect(service.hasActiveTasks, isFalse);
      expect(service.activeTaskCount, equals(0));
    });

    test('starts foreground service with dataSync on Android and cancels immediately upon completion', () async {
      AppCapabilities.debugOverride = const AppCapabilities(
        platform: TargetPlatform.android,
        isTablet: false,
      );
      final service = BackgroundTaskService.instance;

      final taskId = await service.startTask(
        title: 'Uploading Video',
        initialMessage: 'Uploading 0%...',
        maxProgress: 100,
      );

      // Verify WakeLock was acquired
      expect(deviceMethodCalls.any((call) => call.method == 'acquireWakeLock'), isTrue);

      // Verify startForegroundService was called with dataSync type (value 1)
      final fgCalls = notificationMethodCalls
          .where((call) => call.method == 'startForegroundService')
          .toList();
      expect(fgCalls.isNotEmpty, isTrue);
      final fgArgs = fgCalls.first.arguments as Map<dynamic, dynamic>;
      expect(fgArgs['foregroundServiceTypes'], equals([1])); // foregroundServiceTypeDataSync

      // Update progress
      await service.updateProgress(
        taskId,
        title: 'Uploading Video',
        message: 'Uploading 50%...',
        progress: 50,
        maxProgress: 100,
      );

      // Complete task
      await service.completeTask(
        taskId,
        title: 'Uploading Video',
        message: 'Video uploaded',
      );

      // Progression notification must be immediately canceled
      final cancelCalls = notificationMethodCalls
          .where((call) => call.method == 'cancel')
          .toList();
      expect(cancelCalls.isNotEmpty, isTrue);
      expect(
        cancelCalls.any((call) =>
            call.arguments == taskId ||
            (call.arguments is Map && call.arguments['id'] == taskId)),
        isTrue,
      );

      // Foreground service must be stopped and WakeLock released when all tasks done
      expect(notificationMethodCalls.any((call) => call.method == 'stopForegroundService'), isTrue);
      expect(deviceMethodCalls.any((call) => call.method == 'releaseWakeLock'), isTrue);
      expect(service.hasActiveTasks, isFalse);
    });

    test('multi-task foreground service promotion and cleanup', () async {
      AppCapabilities.debugOverride = const AppCapabilities(
        platform: TargetPlatform.android,
        isTablet: false,
      );
      final service = BackgroundTaskService.instance;

      final task1 = await service.startTask(
        title: 'Gallery Upload 1',
        initialMessage: 'Uploading 1...',
      );
      final task2 = await service.startTask(
        title: 'Gallery Upload 2',
        initialMessage: 'Uploading 2...',
      );

      expect(service.activeTaskCount, equals(2));

      // Clear calls so we can check subsequent operations
      notificationMethodCalls.clear();

      // Complete task1: foreground service should NOT stop because task2 is still running
      await service.completeTask(
        task1,
        title: 'Gallery Upload 1',
        message: 'Done',
      );

      expect(service.activeTaskCount, equals(1));
      // task1 notification cancelled immediately
      expect(
        notificationMethodCalls.any((call) =>
            call.method == 'cancel' &&
            (call.arguments == task1 ||
                (call.arguments is Map && call.arguments['id'] == task1))),
        isTrue,
      );
      // foreground service NOT stopped yet
      expect(notificationMethodCalls.any((call) => call.method == 'stopForegroundService'), isFalse);

      // Complete task2: now all tasks finished, foreground service stopped!
      await service.completeTask(
        task2,
        title: 'Gallery Upload 2',
        message: 'Done',
      );

      expect(service.activeTaskCount, equals(0));
      expect(
        notificationMethodCalls.any((call) =>
            call.method == 'cancel' &&
            (call.arguments == task2 ||
                (call.arguments is Map && call.arguments['id'] == task2))),
        isTrue,
      );
      expect(notificationMethodCalls.any((call) => call.method == 'stopForegroundService'), isTrue);
    });
  });
}
