import 'dart:async';
import 'dart:developer';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:worship_chat/common/utils/app_capabilities.dart';
import 'package:worship_chat/common/utils/firebase_notification_service.dart';

class _TaskState {
  final int id;
  String title;
  String message;
  int? progress;
  int? maxProgress;

  _TaskState({
    required this.id,
    required this.title,
    required this.message,
    this.progress,
    this.maxProgress,
  });
}

/// Centralized service to coordinate and execute background tasks
/// (media upload, file sending, gallery upload, share intent transfers, and image/zip downloads).
///
/// Keeps Android process active and network unthrottled via Android Foreground Service
/// (dataSync) and native WakeLock, with live system progress notifications that automatically
/// clear immediately upon completion.
class BackgroundTaskService {
  BackgroundTaskService._();
  static final BackgroundTaskService instance = BackgroundTaskService._();

  static const _deviceChannel = MethodChannel('worship_chat/device');
  final Map<int, _TaskState> _activeTasks = {};
  int _activeTaskCount = 0;
  int _nextNotificationId = 9100;
  int? _foregroundServiceTaskId;

  bool get hasActiveTasks => _activeTaskCount > 0;
  int get activeTaskCount => _activeTaskCount;

  @visibleForTesting
  void resetForTests() {
    _activeTasks.clear();
    _activeTaskCount = 0;
    _foregroundServiceTaskId = null;
  }

  /// Native WakeLock acquisition (Android only)
  Future<void> _acquireWakeLock() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _deviceChannel.invokeMethod('acquireWakeLock');
      log('⚡ [BackgroundTaskService] WakeLock acquired');
    } catch (e) {
      log('⚠️ [BackgroundTaskService] Failed to acquire WakeLock: $e');
    }
  }

  /// Native WakeLock release (Android only)
  Future<void> _releaseWakeLock() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _deviceChannel.invokeMethod('releaseWakeLock');
      log('⚡ [BackgroundTaskService] WakeLock released');
    } catch (e) {
      log('⚠️ [BackgroundTaskService] Failed to release WakeLock: $e');
    }
  }

  /// Starts or updates the Android Foreground Service for data sync.
  Future<void> _startForegroundService(_TaskState task) async {
    if (!AppCapabilities.current.notificationsEnabled) return;

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await FirebaseNotificationService.ensureStaticInitialized();
        final androidPlugin = FirebaseNotificationService.localNotifications
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        if (androidPlugin != null) {
          final hasProgress = task.progress != null &&
              task.maxProgress != null &&
              task.maxProgress! > 0;
          final androidDetails = AndroidNotificationDetails(
            backgroundTransfersChannel.id,
            backgroundTransfersChannel.name,
            channelDescription: backgroundTransfersChannel.description,
            importance: Importance.low,
            priority: Priority.low,
            showProgress: hasProgress,
            maxProgress: task.maxProgress ?? 100,
            progress: task.progress ?? 0,
            indeterminate: !hasProgress,
            ongoing: true,
            autoCancel: false,
            onlyAlertOnce: true,
            playSound: false,
            enableVibration: false,
          );

          await androidPlugin.startForegroundService(
            task.id,
            task.title,
            task.message,
            notificationDetails: androidDetails,
            foregroundServiceTypes: {
              AndroidServiceForegroundType.foregroundServiceTypeDataSync,
            },
          );
          log('⚡ [BackgroundTaskService] ForegroundService started/updated (id: ${task.id})');
          return;
        }
      } catch (e) {
        log('⚠️ [BackgroundTaskService] Failed to start ForegroundService: $e');
      }
    }

    // Fallback for non-Android or if startForegroundService failed
    await _showNotification(
      id: task.id,
      title: task.title,
      body: task.message,
      progress: task.progress,
      maxProgress: task.maxProgress,
      ongoing: true,
    );
  }

  /// Stops the Android Foreground Service when no background tasks remain.
  Future<void> _stopForegroundService() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final androidPlugin = FirebaseNotificationService.localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        await androidPlugin.stopForegroundService();
        log('⚡ [BackgroundTaskService] ForegroundService stopped');
      }
    } catch (e) {
      log('⚠️ [BackgroundTaskService] Failed to stop ForegroundService: $e');
    }
  }

  /// Starts a new tracked background task, acquires WakeLock, starts the foreground
  /// service if this is the first active task, and displays ongoing progress notification.
  Future<int> startTask({
    required String title,
    required String initialMessage,
    int? maxProgress,
  }) async {
    _activeTaskCount++;
    final taskId = _nextNotificationId++;
    if (_nextNotificationId > 9999) _nextNotificationId = 9100;

    final taskState = _TaskState(
      id: taskId,
      title: title,
      message: initialMessage,
      progress: maxProgress != null ? 0 : null,
      maxProgress: maxProgress,
    );
    _activeTasks[taskId] = taskState;

    if (_activeTaskCount == 1 || _foregroundServiceTaskId == null) {
      _foregroundServiceTaskId = taskId;
      await _acquireWakeLock();
      await _startForegroundService(taskState);
    } else {
      await _showNotification(
        id: taskId,
        title: title,
        body: initialMessage,
        progress: taskState.progress,
        maxProgress: maxProgress,
        ongoing: true,
      );
    }

    log('🚀 [BackgroundTaskService] Started task #$taskId: "$title" (Active: $_activeTaskCount)');
    return taskId;
  }

  /// Updates progress for an active background task.
  Future<void> updateProgress(
    int taskId, {
    required String title,
    required String message,
    int? progress,
    int? maxProgress,
  }) async {
    final taskState = _activeTasks[taskId];
    if (taskState != null) {
      taskState.title = title;
      taskState.message = message;
      taskState.progress = progress;
      taskState.maxProgress = maxProgress;
    }

    if (taskId == _foregroundServiceTaskId) {
      await _startForegroundService(
        taskState ??
            _TaskState(
              id: taskId,
              title: title,
              message: message,
              progress: progress,
              maxProgress: maxProgress,
            ),
      );
    } else {
      await _showNotification(
        id: taskId,
        title: title,
        body: message,
        progress: progress,
        maxProgress: maxProgress,
        ongoing: true,
      );
    }
  }

  /// Completes a background task, immediately cancels its notification,
  /// stops foreground service and releases WakeLock if all tasks finished.
  Future<void> completeTask(
    int taskId, {
    required String title,
    required String message,
    bool success = true,
  }) async {
    _activeTasks.remove(taskId);
    _activeTaskCount = (_activeTaskCount - 1).clamp(0, 9999);

    // Immediately cancel the task notification so progression is cleared
    await cancelNotification(taskId);

    if (_activeTasks.isEmpty || _activeTaskCount == 0) {
      _activeTaskCount = 0;
      _foregroundServiceTaskId = null;
      await _stopForegroundService();
      await _releaseWakeLock();
    } else if (_foregroundServiceTaskId == taskId) {
      // Promote the next active task to foreground service
      final nextTask = _activeTasks.values.first;
      _foregroundServiceTaskId = nextTask.id;
      await _startForegroundService(nextTask);
    }

    log('🏁 [BackgroundTaskService] Completed task #$taskId (Remaining: $_activeTaskCount)');
  }

  /// Cancels a specific task notification immediately.
  Future<void> cancelNotification(int taskId) async {
    try {
      if (AppCapabilities.current.notificationsEnabled) {
        await FirebaseNotificationService.localNotifications.cancel(taskId);
      }
    } catch (_) {}
  }

  /// Executes [task] safely inside a tracked background lifecycle.
  /// Handles Foreground Service, WakeLock, progress notifications, and immediate cleanup automatically.
  Future<T> runWithBackgroundTask<T>({
    required String title,
    required String initialMessage,
    required Future<T> Function(
      void Function(String message, {int? progress, int? maxProgress}) update,
    ) task,
    String? successMessage,
    String? errorMessage,
  }) async {
    final taskId = await startTask(
      title: title,
      initialMessage: initialMessage,
    );

    try {
      final result = await task((message, {int? progress, int? maxProgress}) {
        updateProgress(
          taskId,
          title: title,
          message: message,
          progress: progress,
          maxProgress: maxProgress,
        );
      });

      await completeTask(
        taskId,
        title: title,
        message: successMessage ?? 'Finished successfully',
        success: true,
      );

      return result;
    } catch (e) {
      log('❌ [BackgroundTaskService] Error in task "$title": $e');
      await completeTask(
        taskId,
        title: title,
        message: errorMessage ?? 'Failed: $e',
        success: false,
      );
      rethrow;
    }
  }

  Future<void> _showNotification({
    required int id,
    required String title,
    required String body,
    int? progress,
    int? maxProgress,
    bool ongoing = false,
    bool autoCancel = true,
  }) async {
    if (!AppCapabilities.current.notificationsEnabled) return;
    try {
      await FirebaseNotificationService.ensureStaticInitialized();

      final hasProgress = progress != null && maxProgress != null && maxProgress > 0;

      final androidDetails = AndroidNotificationDetails(
        backgroundTransfersChannel.id,
        backgroundTransfersChannel.name,
        channelDescription: backgroundTransfersChannel.description,
        importance: Importance.low,
        priority: Priority.low,
        showProgress: hasProgress || ongoing,
        maxProgress: maxProgress ?? 100,
        progress: progress ?? 0,
        indeterminate: ongoing && !hasProgress,
        ongoing: ongoing,
        autoCancel: autoCancel,
        onlyAlertOnce: true,
        playSound: false,
        enableVibration: false,
      );

      const darwinDetails = DarwinNotificationDetails(
        presentAlert: false,
        presentBadge: false,
        presentSound: false,
      );

      await FirebaseNotificationService.localNotifications.show(
        id,
        title,
        body,
        NotificationDetails(
          android: androidDetails,
          iOS: darwinDetails,
        ),
      );
    } catch (e) {
      log('⚠️ [BackgroundTaskService] Notification error: $e');
    }
  }
}
