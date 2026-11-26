import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:worship_chat/common/utils/app_capabilities.dart';

/// Categories of telemetry stored and displayed by [DiagnosticsService].
enum DiagnosticReportKind {
  crash('Crash'),
  performance('Performance'),
  error('Error'),
  warning('Warning');

  final String label;
  const DiagnosticReportKind(this.label);

  static DiagnosticReportKind fromName(String? raw) {
    final normalized = (raw ?? '').trim().toLowerCase();
    for (final value in DiagnosticReportKind.values) {
      if (value.name.toLowerCase() == normalized) return value;
    }
    return DiagnosticReportKind.error;
  }
}

/// Immutable diagnostic record for a crash, runtime error, or perf anomaly.
class DiagnosticReport {
  final String id;
  final DiagnosticReportKind kind;
  final String title;
  final String message;
  final String? stackTrace;
  final DateTime timestamp;
  final String appVersion;
  final String platform;
  final String? routeName;
  final List<String> breadcrumbs;
  final Map<String, dynamic> metrics;
  final String? source;
  final String? userId;
  final String? userLabel;
  final bool isFatal;
  final bool isSynced;
  final bool isResolved;

  const DiagnosticReport({
    required this.id,
    required this.kind,
    required this.title,
    required this.message,
    this.stackTrace,
    required this.timestamp,
    required this.appVersion,
    required this.platform,
    this.routeName,
    this.breadcrumbs = const [],
    this.metrics = const {},
    this.source,
    this.userId,
    this.userLabel,
    this.isFatal = false,
    this.isSynced = false,
    this.isResolved = false,
  });

  DiagnosticReport copyWith({
    bool? isSynced,
    bool? isResolved,
  }) {
    return DiagnosticReport(
      id: id,
      kind: kind,
      title: title,
      message: message,
      stackTrace: stackTrace,
      timestamp: timestamp,
      appVersion: appVersion,
      platform: platform,
      routeName: routeName,
      breadcrumbs: breadcrumbs,
      metrics: metrics,
      source: source,
      userId: userId,
      userLabel: userLabel,
      isFatal: isFatal,
      isSynced: isSynced ?? this.isSynced,
      isResolved: isResolved ?? this.isResolved,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'kind': kind.name,
      'title': title,
      'message': message,
      'stackTrace': stackTrace,
      'timestampMs': timestamp.millisecondsSinceEpoch,
      'timestampIso': timestamp.toIso8601String(),
      'appVersion': appVersion,
      'platform': platform,
      'routeName': routeName,
      'breadcrumbs': breadcrumbs,
      'metrics': metrics,
      'source': source,
      'userId': userId,
      'userLabel': userLabel,
      'isFatal': isFatal,
      'isSynced': isSynced,
      'isResolved': isResolved,
    };
  }

  factory DiagnosticReport.fromMap(Map<String, dynamic> map) {
    final tsMs = map['timestampMs'];
    DateTime resolvedTime;
    if (tsMs is int && tsMs > 0) {
      resolvedTime = DateTime.fromMillisecondsSinceEpoch(tsMs);
    } else if (tsMs is num && tsMs > 0) {
      resolvedTime = DateTime.fromMillisecondsSinceEpoch(tsMs.toInt());
    } else {
      resolvedTime = DateTime.tryParse(
            (map['timestampIso'] ?? '').toString(),
          ) ??
          DateTime.now();
    }

    final rawCrumbs = map['breadcrumbs'];
    final crumbs = rawCrumbs is List
        ? rawCrumbs.map((e) => e.toString()).toList(growable: false)
        : const <String>[];

    final rawMetrics = map['metrics'];
    final metricsMap = rawMetrics is Map
        ? Map<String, dynamic>.from(rawMetrics)
        : const <String, dynamic>{};

    return DiagnosticReport(
      id: (map['id'] ?? const Uuid().v4()).toString(),
      kind: DiagnosticReportKind.fromName(map['kind']?.toString()),
      title: (map['title'] ?? 'Diagnostic Event').toString(),
      message: (map['message'] ?? '').toString(),
      stackTrace: map['stackTrace']?.toString(),
      timestamp: resolvedTime,
      appVersion: (map['appVersion'] ?? 'unknown').toString(),
      platform: (map['platform'] ?? 'unknown').toString(),
      routeName: map['routeName']?.toString(),
      breadcrumbs: crumbs,
      metrics: metricsMap,
      source: map['source']?.toString(),
      userId: map['userId']?.toString(),
      userLabel: map['userLabel']?.toString(),
      isFatal: map['isFatal'] == true,
      isSynced: map['isSynced'] == true,
      isResolved: map['isResolved'] == true,
    );
  }

  /// Formats this report as a structured prompt ready to paste directly into
  /// Antigravity as a fix command.
  String toFixCommandPrompt() {
    final buf = StringBuffer()
      ..writeln('Fix this Worship Chat ${kind.name} report:')
      ..writeln('- Report ID: $id')
      ..writeln('- Kind: ${kind.label} (fatal: $isFatal)')
      ..writeln('- App Version: $appVersion ($platform)')
      ..writeln('- Timestamp: ${timestamp.toIso8601String()}');

    if (source != null && source!.isNotEmpty) {
      buf.writeln('- Source: $source');
    }
    if (routeName != null && routeName!.isNotEmpty) {
      buf.writeln('- Active Route: $routeName');
    }
    if (userLabel != null && userLabel!.isNotEmpty) {
      buf.writeln('- Device/User: $userLabel');
    }
    buf
      ..writeln('- Title: $title')
      ..writeln('- Details: $message');

    if (metrics.isNotEmpty) {
      buf.writeln('- Performance Metrics: ${jsonEncode(metrics)}');
    }
    if (breadcrumbs.isNotEmpty) {
      buf.writeln('- Navigation Breadcrumbs: ${breadcrumbs.join(' -> ')}');
    }
    if (stackTrace != null && stackTrace!.trim().isNotEmpty) {
      final trace = stackTrace!.trim();
      final clipped = trace.length > 3500
          ? '${trace.substring(0, 3500)}\n... (truncated)'
          : trace;
      buf
        ..writeln('- Stack Trace:')
        ..writeln('```')
        ..writeln(clipped)
        ..writeln('```');
    }
    return buf.toString().trim();
  }
}

/// Live session performance telemetry summarized from Flutter frame timings.
class PerformanceTelemetrySnapshot {
  final int totalFrames;
  final int slowFrames;
  final int frozenFrames;
  final double avgBuildMs;
  final double avgRasterMs;
  final double worstFrameMs;
  final double estimatedFps;
  final int? coldStartMs;
  final String? currentRoute;

  const PerformanceTelemetrySnapshot({
    this.totalFrames = 0,
    this.slowFrames = 0,
    this.frozenFrames = 0,
    this.avgBuildMs = 0.0,
    this.avgRasterMs = 0.0,
    this.worstFrameMs = 0.0,
    this.estimatedFps = 60.0,
    this.coldStartMs,
    this.currentRoute,
  });

  PerformanceTelemetrySnapshot copyWith({
    int? totalFrames,
    int? slowFrames,
    int? frozenFrames,
    double? avgBuildMs,
    double? avgRasterMs,
    double? worstFrameMs,
    double? estimatedFps,
    int? coldStartMs,
    String? currentRoute,
  }) {
    return PerformanceTelemetrySnapshot(
      totalFrames: totalFrames ?? this.totalFrames,
      slowFrames: slowFrames ?? this.slowFrames,
      frozenFrames: frozenFrames ?? this.frozenFrames,
      avgBuildMs: avgBuildMs ?? this.avgBuildMs,
      avgRasterMs: avgRasterMs ?? this.avgRasterMs,
      worstFrameMs: worstFrameMs ?? this.worstFrameMs,
      estimatedFps: estimatedFps ?? this.estimatedFps,
      coldStartMs: coldStartMs ?? this.coldStartMs,
      currentRoute: currentRoute ?? this.currentRoute,
    );
  }
}

/// Captures fatal crashes, non-fatal errors, UI exceptions, and frame-jank /
/// startup performance reports, persisting locally in SharedPreferences and
/// syncing asynchronously to Firestore `diagnostics_reports`.
class DiagnosticsService {
  DiagnosticsService._();
  static final DiagnosticsService instance = DiagnosticsService._();

  static const String storagePrefKey = 'diagnostics_reports_v1';
  static const String firestoreCollection = 'diagnostics_reports';
  static const int maxStoredReports = 120;
  static const Duration duplicateCooldown = Duration(seconds: 5);
  static const Duration performanceReportCooldown = Duration(minutes: 2);
  static const double slowFrameThresholdMs = 32.0;
  static const double frozenFrameThresholdMs = 120.0;
  static const int jankBurstThreshold = 6;

  final ValueNotifier<List<DiagnosticReport>> reportsNotifier =
      ValueNotifier<List<DiagnosticReport>>(const []);
  final ValueNotifier<PerformanceTelemetrySnapshot> telemetryNotifier =
      ValueNotifier<PerformanceTelemetrySnapshot>(
    const PerformanceTelemetrySnapshot(),
  );

  final List<String> _breadcrumbs = <String>[];
  final Map<String, DateTime> _recentSignatures = <String, DateTime>{};
  final List<double> _recentSlowWindow = <double>[];

  String _cachedAppVersion = 'unknown';
  String? _currentRoute;
  bool _initialized = false;
  bool _handlersInstalled = false;
  bool _frameMonitorInstalled = false;
  bool _isRecording = false;
  bool _isSyncing = false;
  DateTime? _lastPerformanceReportAt;
  DateTime Function() _nowProvider = DateTime.now;
  Future<void> Function(DiagnosticReport report)? _remoteUploaderOverride;
  Future<List<DiagnosticReport>> Function()? _remoteFetcherOverride;

  double _totalBuildMsAccum = 0.0;
  double _totalRasterMsAccum = 0.0;
  int _sampledFrames = 0;
  double _worstFrameMs = 0.0;
  int _slowFrames = 0;
  int _frozenFrames = 0;
  int? _coldStartMs;

  @visibleForTesting
  void configureForTests({
    DateTime Function()? nowProvider,
    Future<void> Function(DiagnosticReport report)? remoteUploader,
    Future<List<DiagnosticReport>> Function()? remoteFetcher,
    String appVersion = '1.0.5+6',
  }) {
    if (nowProvider != null) _nowProvider = nowProvider;
    _remoteUploaderOverride = remoteUploader;
    _remoteFetcherOverride = remoteFetcher;
    _cachedAppVersion = appVersion;
  }

  @visibleForTesting
  void resetForTests() {
    _breadcrumbs.clear();
    _recentSignatures.clear();
    _recentSlowWindow.clear();
    _currentRoute = null;
    _initialized = false;
    _handlersInstalled = false;
    _isRecording = false;
    _isSyncing = false;
    _lastPerformanceReportAt = null;
    _nowProvider = DateTime.now;
    _remoteUploaderOverride = null;
    _remoteFetcherOverride = null;
    _totalBuildMsAccum = 0.0;
    _totalRasterMsAccum = 0.0;
    _sampledFrames = 0;
    _worstFrameMs = 0.0;
    _slowFrames = 0;
    _frozenFrames = 0;
    _coldStartMs = null;
    reportsNotifier.value = const [];
    telemetryNotifier.value = const PerformanceTelemetrySnapshot();
  }

  String get _platformName =>
      kIsWeb ? 'web' : defaultTargetPlatform.name;

  /// Loads cached diagnostic reports from local storage and flushes any
  /// unsynced entries to Firestore in the background.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final info = await PackageInfo.fromPlatform();
      final ver = info.version.trim();
      final code = info.buildNumber.trim();
      if (ver.isNotEmpty) {
        _cachedAppVersion = code.isNotEmpty ? '$ver+$code' : ver;
      }
    } catch (_) {}

    await _loadFromStorage();
    unawaited(syncPendingReports());
  }

  /// Hooks [FlutterError.onError], [PlatformDispatcher.instance.onError],
  /// and Flutter [SchedulerBinding] frame timings monitoring.
  void installGlobalHandlers({
    FlutterExceptionHandler? forwardFlutterError,
  }) {
    if (_handlersInstalled) return;
    _handlersInstalled = true;

    final previousOnError = forwardFlutterError ?? FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      unawaited(recordFlutterError(details));
      previousOnError?.call(details);
    };

    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      unawaited(
        recordCrash(
          error,
          stack,
          fatal: true,
          source: 'PlatformDispatcher',
        ),
      );
      return false;
    };

    installFramePerformanceMonitor();
  }

  /// Registers [SchedulerBinding.instance.addTimingsCallback] once to monitor
  /// slow/frozen frames and capture actionable performance reports.
  void installFramePerformanceMonitor() {
    if (_frameMonitorInstalled) return;
    _frameMonitorInstalled = true;
    try {
      SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
    } catch (_) {}
  }

  void recordBreadcrumb(String event, {String? routeName}) {
    final trimmed = event.trim();
    if (trimmed.isEmpty) return;
    if (routeName != null && routeName.trim().isNotEmpty) {
      _currentRoute = routeName.trim();
    }
    _breadcrumbs.add(trimmed);
    if (_breadcrumbs.length > 15) {
      _breadcrumbs.removeAt(0);
    }
    telemetryNotifier.value = telemetryNotifier.value.copyWith(
      currentRoute: _currentRoute,
    );
  }

  /// Records cold startup duration and logs a performance anomaly if slow.
  Future<void> recordStartupDuration(int durationMs) async {
    _coldStartMs = durationMs;
    telemetryNotifier.value = telemetryNotifier.value.copyWith(
      coldStartMs: durationMs,
    );
    if (durationMs >= 3500) {
      await recordPerformanceAnomaly(
        title: 'Slow App Startup (${durationMs}ms)',
        message:
            'Cold startup took ${durationMs}ms before first interactive frame.',
        metrics: {
          'coldStartMs': durationMs,
        },
        source: 'StartupTimer',
      );
    }
  }

  /// Feeds raw frame timings (exposed for unit tests cleanly).
  @visibleForTesting
  void processFrameSample({
    required double buildMs,
    required double rasterMs,
    required double totalMs,
  }) {
    _sampledFrames++;
    _totalBuildMsAccum += buildMs;
    _totalRasterMsAccum += rasterMs;
    if (totalMs > _worstFrameMs) {
      _worstFrameMs = totalMs;
    }

    final isSlow = totalMs > slowFrameThresholdMs;
    final isFrozen = totalMs >= frozenFrameThresholdMs;
    if (isSlow) _slowFrames++;
    if (isFrozen) _frozenFrames++;

    _recentSlowWindow.add(totalMs);
    if (_recentSlowWindow.length > 60) {
      _recentSlowWindow.removeAt(0);
    }

    final avgBuild = _totalBuildMsAccum / _sampledFrames;
    final avgRaster = _totalRasterMsAccum / _sampledFrames;
    final avgFrame = avgBuild + avgRaster;
    final estFps = avgFrame <= 16.67
        ? 60.0
        : (1000.0 / avgFrame).clamp(1.0, 60.0);

    telemetryNotifier.value = telemetryNotifier.value.copyWith(
      totalFrames: _sampledFrames,
      slowFrames: _slowFrames,
      frozenFrames: _frozenFrames,
      avgBuildMs: double.parse(avgBuild.toStringAsFixed(1)),
      avgRasterMs: double.parse(avgRaster.toStringAsFixed(1)),
      worstFrameMs: double.parse(_worstFrameMs.toStringAsFixed(1)),
      estimatedFps: double.parse(estFps.toStringAsFixed(1)),
      coldStartMs: _coldStartMs,
      currentRoute: _currentRoute,
    );

    final slowInWindow =
        _recentSlowWindow.where((ms) => ms > slowFrameThresholdMs).length;
    if (isFrozen || slowInWindow >= jankBurstThreshold) {
      final now = _nowProvider();
      final lastAt = _lastPerformanceReportAt;
      if (lastAt == null ||
          now.difference(lastAt) >= performanceReportCooldown) {
        _lastPerformanceReportAt = now;
        final routeLabel = _currentRoute ?? 'Unknown Route';
        final label = isFrozen
            ? 'UI Freeze Detected (${totalMs.toStringAsFixed(0)}ms frame)'
            : 'UI Frame Jank Burst ($slowInWindow/60 slow frames)';
        unawaited(
          recordPerformanceAnomaly(
            title: label,
            message:
                'Frame build=${buildMs.toStringAsFixed(1)}ms, raster=${rasterMs.toStringAsFixed(1)}ms, total=${totalMs.toStringAsFixed(1)}ms on $routeLabel.',
            metrics: {
              'buildMs': double.parse(buildMs.toStringAsFixed(1)),
              'rasterMs': double.parse(rasterMs.toStringAsFixed(1)),
              'totalMs': double.parse(totalMs.toStringAsFixed(1)),
              'slowInWindow': slowInWindow,
              'estimatedFps': telemetryNotifier.value.estimatedFps,
            },
            source: 'FrameTimingMonitor',
          ),
        );
      }
    }
  }

  void _onFrameTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      processFrameSample(
        buildMs: t.buildDuration.inMicroseconds / 1000.0,
        rasterMs: t.rasterDuration.inMicroseconds / 1000.0,
        totalMs: t.totalSpan.inMicroseconds / 1000.0,
      );
    }
  }

  Future<DiagnosticReport?> recordFlutterError(
    FlutterErrorDetails details,
  ) async {
    final exc = details.exception;
    final stack = details.stack;
    final isFatal = !(details.silent);
    final library = details.library ?? 'flutter';
    final contextDesc = details.context?.toDescription();
    final msg = contextDesc != null && contextDesc.isNotEmpty
        ? '$exc ($contextDesc)'
        : '$exc';

    return recordReport(
      kind: isFatal ? DiagnosticReportKind.crash : DiagnosticReportKind.error,
      title: _extractTitle(exc),
      message: msg,
      stackTrace: stack?.toString(),
      source: 'FlutterError:$library',
      isFatal: isFatal,
    );
  }

  Future<DiagnosticReport?> recordCrash(
    Object error,
    StackTrace? stack, {
    bool fatal = true,
    String source = 'Zone',
    Map<String, dynamic> metrics = const {},
  }) async {
    return recordReport(
      kind: DiagnosticReportKind.crash,
      title: _extractTitle(error),
      message: error.toString(),
      stackTrace: stack?.toString(),
      source: source,
      metrics: metrics,
      isFatal: fatal,
    );
  }

  Future<DiagnosticReport?> recordError(
    Object error, {
    StackTrace? stackTrace,
    String? context,
    String source = 'AppError',
    Map<String, dynamic> metrics = const {},
  }) async {
    final msg = (context != null && context.trim().isNotEmpty)
        ? '$context: $error'
        : error.toString();
    return recordReport(
      kind: DiagnosticReportKind.error,
      title: _extractTitle(error),
      message: msg,
      stackTrace: (stackTrace ?? StackTrace.current).toString(),
      source: source,
      metrics: metrics,
      isFatal: false,
    );
  }

  Future<DiagnosticReport?> recordWarning({
    required String title,
    required String message,
    String source = 'AppWarning',
    Map<String, dynamic> metrics = const {},
  }) async {
    return recordReport(
      kind: DiagnosticReportKind.warning,
      title: title,
      message: message,
      source: source,
      metrics: metrics,
      isFatal: false,
    );
  }

  Future<DiagnosticReport?> recordPerformanceAnomaly({
    required String title,
    required String message,
    Map<String, dynamic> metrics = const {},
    String source = 'Performance',
  }) async {
    return recordReport(
      kind: DiagnosticReportKind.performance,
      title: title,
      message: message,
      source: source,
      metrics: metrics,
      isFatal: false,
    );
  }

  /// Captures a manual performance snapshot for developer inspection.
  Future<DiagnosticReport?> capturePerformanceSnapshot() async {
    final snap = telemetryNotifier.value;
    return recordReport(
      kind: DiagnosticReportKind.performance,
      title:
          'Performance Snapshot (~${snap.estimatedFps.toStringAsFixed(0)} FPS)',
      message:
          'Frames: ${snap.totalFrames}, Slow: ${snap.slowFrames}, Frozen: ${snap.frozenFrames}, Avg Build: ${snap.avgBuildMs}ms, Avg Raster: ${snap.avgRasterMs}ms, Worst: ${snap.worstFrameMs}ms.',
      metrics: {
        'totalFrames': snap.totalFrames,
        'slowFrames': snap.slowFrames,
        'frozenFrames': snap.frozenFrames,
        'avgBuildMs': snap.avgBuildMs,
        'avgRasterMs': snap.avgRasterMs,
        'worstFrameMs': snap.worstFrameMs,
        'estimatedFps': snap.estimatedFps,
        if (snap.coldStartMs != null) 'coldStartMs': snap.coldStartMs,
      },
      source: 'ManualSnapshot',
      allowDuplicateImmediate: true,
    );
  }

  Future<DiagnosticReport?> recordReport({
    required DiagnosticReportKind kind,
    required String title,
    required String message,
    String? stackTrace,
    String? source,
    Map<String, dynamic> metrics = const {},
    bool isFatal = false,
    bool allowDuplicateImmediate = false,
  }) async {
    if (_isRecording) return null;
    _isRecording = true;
    try {
      final now = _nowProvider();
      final signature = '${kind.name}|$title|${message.hashCode}';
      if (!allowDuplicateImmediate && !isFatal) {
        final prevAt = _recentSignatures[signature];
        if (prevAt != null && now.difference(prevAt) < duplicateCooldown) {
          return null;
        }
      }
      _recentSignatures[signature] = now;
      if (_recentSignatures.length > 50) {
        _recentSignatures.clear();
      }

      String? uid;
      String? userLabel;
      try {
        if (Firebase.apps.isNotEmpty) {
          final user = FirebaseAuth.instance.currentUser;
          uid = user?.uid;
          userLabel = user?.displayName ?? user?.email ?? uid;
        }
      } catch (_) {}

      final report = DiagnosticReport(
        id: const Uuid().v4(),
        kind: kind,
        title: title.trim().isEmpty ? kind.label : title.trim(),
        message: message.trim(),
        stackTrace: stackTrace,
        timestamp: now,
        appVersion: _cachedAppVersion,
        platform: '$_platformName${AppCapabilities.current.isTablet ? ' (tablet)' : ''}',
        routeName: _currentRoute,
        breadcrumbs: List<String>.unmodifiable(_breadcrumbs),
        metrics: Map<String, dynamic>.unmodifiable(metrics),
        source: source,
        userId: uid,
        userLabel: userLabel,
        isFatal: isFatal,
        isSynced: false,
        isResolved: false,
      );

      final updated = <DiagnosticReport>[report, ...reportsNotifier.value];
      if (updated.length > maxStoredReports) {
        updated.removeRange(maxStoredReports, updated.length);
      }
      reportsNotifier.value = List<DiagnosticReport>.unmodifiable(updated);
      await _persistToStorage();

      // Best-effort remote upload without blocking UI or causing recursion.
      unawaited(_uploadSingleReport(report));
      return report;
    } catch (e) {
      log('DiagnosticsService recordReport error: $e');
      return null;
    } finally {
      _isRecording = false;
    }
  }

  /// Syncs any locally queued reports to Firestore and merges recent remote
  /// reports so issues across test devices appear inside DevelopmentScreen.
  Future<int> syncPendingReports({bool pullRemote = true}) async {
    if (_isSyncing) return 0;
    _isSyncing = true;
    int syncedCount = 0;
    try {
      final snapshot = List<DiagnosticReport>.from(reportsNotifier.value);
      final newlySyncedIds = <String>{};
      for (final item in snapshot) {
        if (!item.isSynced) {
          final ok = await _tryRemoteUpload(item);
          if (ok) {
            newlySyncedIds.add(item.id);
            syncedCount++;
          }
        }
      }

      final remoteList =
          pullRemote ? await _tryFetchRemoteReports() : const <DiagnosticReport>[];

      // Re-read reportsNotifier after awaits so concurrent recordReport() calls
      // made during network I/O are preserved cleanly.
      final latestById = <String, DiagnosticReport>{
        for (final r in reportsNotifier.value)
          r.id: newlySyncedIds.contains(r.id) ? r.copyWith(isSynced: true) : r,
      };

      bool changed = newlySyncedIds.isNotEmpty;
      for (final remote in remoteList) {
        final local = latestById[remote.id];
        if (local == null) {
          latestById[remote.id] = remote.copyWith(isSynced: true);
          changed = true;
        } else if (!local.isResolved && remote.isResolved) {
          latestById[remote.id] = local.copyWith(
            isResolved: true,
            isSynced: true,
          );
          changed = true;
        }
      }

      if (changed) {
        final merged = latestById.values.toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        if (merged.length > maxStoredReports) {
          merged.removeRange(maxStoredReports, merged.length);
        }
        reportsNotifier.value = List<DiagnosticReport>.unmodifiable(merged);
        await _persistToStorage();
      }
    } catch (_) {
    } finally {
      _isSyncing = false;
    }
    return syncedCount;
  }

  Future<void> markResolved(String id, {bool resolved = true}) async {
    final current = reportsNotifier.value
        .map((r) => r.id == id ? r.copyWith(isResolved: resolved) : r)
        .toList(growable: false);
    reportsNotifier.value = List<DiagnosticReport>.unmodifiable(current);
    await _persistToStorage();

    if (_remoteUploaderOverride == null && Firebase.apps.isNotEmpty) {
      try {
        await FirebaseFirestore.instance
            .collection(firestoreCollection)
            .doc(id)
            .set({'isResolved': resolved}, SetOptions(merge: true));
      } catch (_) {}
    }
  }

  Future<void> deleteReport(String id) async {
    final current = reportsNotifier.value
        .where((r) => r.id != id)
        .toList(growable: false);
    reportsNotifier.value = List<DiagnosticReport>.unmodifiable(current);
    await _persistToStorage();
  }

  Future<void> clearResolved() async {
    final current = reportsNotifier.value
        .where((r) => !r.isResolved)
        .toList(growable: false);
    reportsNotifier.value = List<DiagnosticReport>.unmodifiable(current);
    await _persistToStorage();
  }

  Future<void> clearAll() async {
    reportsNotifier.value = const [];
    await _persistToStorage();
  }

  String exportUnresolvedAsCommand({DiagnosticReportKind? filterKind}) {
    final items = reportsNotifier.value.where((r) {
      if (r.isResolved) return false;
      if (filterKind != null && r.kind != filterKind) return false;
      return true;
    }).take(10).toList();

    if (items.isEmpty) {
      return 'All Worship Chat diagnostics look healthy (0 unresolved issues on $_cachedAppVersion).';
    }

    final buf = StringBuffer()
      ..writeln(
        'Analyze and fix these ${items.length} Worship Chat issue(s) reported on v$_cachedAppVersion:',
      )
      ..writeln();
    for (int i = 0; i < items.length; i++) {
      buf
        ..writeln('### Issue ${i + 1}')
        ..writeln(items[i].toFixCommandPrompt())
        ..writeln();
    }
    return buf.toString().trim();
  }

  Future<void> _uploadSingleReport(DiagnosticReport report) async {
    final ok = await _tryRemoteUpload(report);
    if (!ok) return;
    final updated = reportsNotifier.value
        .map((r) => r.id == report.id ? r.copyWith(isSynced: true) : r)
        .toList(growable: false);
    reportsNotifier.value = List<DiagnosticReport>.unmodifiable(updated);
    await _persistToStorage();
  }

  Future<bool> _tryRemoteUpload(DiagnosticReport report) async {
    if (_remoteUploaderOverride != null) {
      try {
        await _remoteUploaderOverride!(report);
        return true;
      } catch (_) {
        return false;
      }
    }
    if (Firebase.apps.isEmpty) return false;
    try {
      await FirebaseFirestore.instance
          .collection(firestoreCollection)
          .doc(report.id)
          .set({...report.toMap(), 'isSynced': true})
          .timeout(const Duration(seconds: 6));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<List<DiagnosticReport>> _tryFetchRemoteReports() async {
    if (_remoteFetcherOverride != null) {
      try {
        return await _remoteFetcherOverride!();
      } catch (_) {
        return const [];
      }
    }
    if (Firebase.apps.isEmpty) return const [];
    try {
      final snap = await FirebaseFirestore.instance
          .collection(firestoreCollection)
          .orderBy('timestampMs', descending: true)
          .limit(50)
          .get()
          .timeout(const Duration(seconds: 6));
      return snap.docs
          .map((d) => DiagnosticReport.fromMap(d.data()))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storagePrefKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final parsed = <DiagnosticReport>[];
      for (final item in decoded) {
        if (item is Map) {
          parsed.add(
            DiagnosticReport.fromMap(Map<String, dynamic>.from(item)),
          );
        }
      }
      parsed.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      reportsNotifier.value = List<DiagnosticReport>.unmodifiable(parsed);
    } catch (_) {}
  }

  Future<void> _persistToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(
        reportsNotifier.value.map((r) => r.toMap()).toList(growable: false),
      );
      await prefs.setString(storagePrefKey, encoded);
    } catch (_) {}
  }

  static String _extractTitle(Object error) {
    final text = error.toString().trim();
    if (text.isEmpty) return error.runtimeType.toString();
    final firstLine = text.split('\n').first.trim();
    if (firstLine.length <= 72) return firstLine;
    return '${firstLine.substring(0, 69)}...';
  }
}

/// NavigatorObserver that feeds route breadcrumbs and active screen context
/// into [DiagnosticsService] so every report includes where it occurred.
class DiagnosticsNavigatorObserver extends NavigatorObserver {
  String _labelFor(Route<dynamic>? route) {
    if (route == null) return 'unknown';
    final name = route.settings.name?.trim();
    if (name != null && name.isNotEmpty) return name;
    return route.runtimeType.toString();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    final label = _labelFor(route);
    DiagnosticsService.instance.recordBreadcrumb('Push $label', routeName: label);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (newRoute != null) {
      final label = _labelFor(newRoute);
      DiagnosticsService.instance
          .recordBreadcrumb('Replace $label', routeName: label);
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    final prevLabel = _labelFor(previousRoute);
    DiagnosticsService.instance.recordBreadcrumb(
      'Pop to $prevLabel',
      routeName: previousRoute != null ? prevLabel : null,
    );
  }
}
