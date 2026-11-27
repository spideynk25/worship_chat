import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worship_chat/common/utils/app_capabilities.dart';
import 'package:worship_chat/common/utils/diagnostics_service.dart';
import 'package:worship_chat/features/settings/screens/development_screen.dart';
import 'package:worship_chat/features/settings/screens/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DiagnosticsService.instance.resetForTests();
    AppCapabilities.resetForTests();
  });

  tearDown(() {
    DiagnosticsService.instance.resetForTests();
    AppCapabilities.resetForTests();
  });

  group('DiagnosticsService Unit Tests', () {
    test('captures crashes, non-fatal errors, breadcrumbs, and formats AI fix command', () async {
      final uploaded = <DiagnosticReport>[];
      DiagnosticsService.instance.configureForTests(
        appVersion: '1.0.5+6',
        remoteUploader: (report) async => uploaded.add(report),
      );
      await DiagnosticsService.instance.initialize();

      DiagnosticsService.instance.recordBreadcrumb(
        'Push /one-to-one-chat-screen',
        routeName: '/one-to-one-chat-screen',
      );

      final crash = await DiagnosticsService.instance.recordCrash(
        RangeError.index(5, [1, 2], 'messages'),
        StackTrace.fromString('#0 ChatList._build (chat_list.dart:42)'),
        fatal: true,
        source: 'Zone',
      );

      expect(crash, isNotNull);
      expect(crash!.kind, DiagnosticReportKind.crash);
      expect(crash.isFatal, isTrue);
      expect(crash.routeName, '/one-to-one-chat-screen');
      expect(crash.appVersion, '1.0.5+6');

      final prompt = crash.toFixCommandPrompt();
      expect(prompt, contains('Fix this Worship Chat crash report:'));
      expect(prompt, contains('/one-to-one-chat-screen'));
      expect(prompt, contains('chat_list.dart:42'));
      expect(prompt, contains('1.0.5+6'));

      // Allow async remote upload microtask to finish
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(uploaded.length, 1);
      expect(
        DiagnosticsService.instance.reportsNotifier.value.first.isSynced,
        isTrue,
      );
    });

    test('deduplicates rapid identical non-fatal errors and persists locally', () async {
      var now = DateTime(2026, 11, 26, 19, 0);
      DiagnosticsService.instance.configureForTests(
        nowProvider: () => now,
        remoteUploader: (_) async => throw Exception('offline'),
      );
      await DiagnosticsService.instance.initialize();

      await DiagnosticsService.instance.recordError(
        StateError('Repeated layout overflow'),
        source: 'ErrorWidget',
      );
      // Within 5s cooldown -> deduplicated
      await DiagnosticsService.instance.recordError(
        StateError('Repeated layout overflow'),
        source: 'ErrorWidget',
      );
      expect(DiagnosticsService.instance.reportsNotifier.value.length, 1);

      // After cooldown -> recorded cleanly
      now = now.add(const Duration(seconds: 6));
      await DiagnosticsService.instance.recordError(
        StateError('Repeated layout overflow'),
        source: 'ErrorWidget',
      );
      expect(DiagnosticsService.instance.reportsNotifier.value.length, 2);

      // Verify reload from SharedPreferences preserves records
      DiagnosticsService.instance.resetForTests();
      await DiagnosticsService.instance.initialize();
      expect(DiagnosticsService.instance.reportsNotifier.value.length, 2);
      expect(
        DiagnosticsService.instance.reportsNotifier.value.first.isSynced,
        isFalse,
      );
    });

    test('detects UI jank burst / frozen frames and creates throttled performance report', () async {
      var now = DateTime(2026, 11, 26, 19, 15);
      DiagnosticsService.instance.configureForTests(
        nowProvider: () => now,
        remoteUploader: (_) async {},
      );
      await DiagnosticsService.instance.initialize();
      DiagnosticsService.instance.recordBreadcrumb(
        'Push /group-gallery-screen',
        routeName: '/group-gallery-screen',
      );

      // Normal 8ms frames -> no performance anomaly
      for (int i = 0; i < 10; i++) {
        DiagnosticsService.instance.processFrameSample(
          buildMs: 4.0,
          rasterMs: 4.0,
          totalMs: 8.0,
        );
      }
      expect(DiagnosticsService.instance.reportsNotifier.value, isEmpty);

      // Frozen 160ms frame -> creates a Performance report
      DiagnosticsService.instance.processFrameSample(
        buildMs: 110.0,
        rasterMs: 50.0,
        totalMs: 160.0,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final reports = DiagnosticsService.instance.reportsNotifier.value;
      expect(reports.length, 1);
      expect(reports.first.kind, DiagnosticReportKind.performance);
      expect(reports.first.title, contains('UI Freeze Detected'));
      expect(reports.first.routeName, '/group-gallery-screen');
      expect(reports.first.metrics['totalMs'], 160.0);

      // Another slow frame inside 2-minute cooldown -> throttled
      now = now.add(const Duration(seconds: 30));
      DiagnosticsService.instance.processFrameSample(
        buildMs: 90.0,
        rasterMs: 60.0,
        totalMs: 150.0,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(DiagnosticsService.instance.reportsNotifier.value.length, 1);
    });

    test('syncPendingReports uploads local queue and merges remote cloud reports', () async {
      final cloud = <DiagnosticReport>[
        DiagnosticReport(
          id: 'remote-1',
          kind: DiagnosticReportKind.crash,
          title: 'Remote Device Crash',
          message: 'Null check operator used on a null value',
          timestamp: DateTime(2026, 11, 26, 18, 0),
          appVersion: '1.0.5+6',
          platform: 'android',
          isFatal: true,
          isSynced: true,
        ),
      ];
      var allowUpload = false;

      DiagnosticsService.instance.configureForTests(
        remoteUploader: (report) async {
          if (!allowUpload) throw Exception('Offline');
          cloud.add(report.copyWith(isSynced: true));
        },
        remoteFetcher: () async => cloud,
      );
      await DiagnosticsService.instance.initialize();

      await DiagnosticsService.instance.recordError(
        Exception('Offline media timeout'),
        source: 'MediaCache',
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        DiagnosticsService.instance.reportsNotifier.value.first.isSynced,
        isFalse,
      );

      // Regain network & sync
      allowUpload = true;
      final synced = await DiagnosticsService.instance.syncPendingReports();
      expect(synced, 1);
      expect(DiagnosticsService.instance.reportsNotifier.value.length, 2);
      expect(
        DiagnosticsService.instance.reportsNotifier.value
            .every((r) => r.isSynced),
        isTrue,
      );
    });
  });

  group('SettingsScreen & DevelopmentScreen Widget Tests', () {
    testWidgets('SettingsScreen lists Development with badge and navigates to DevelopmentScreen', (tester) async {
      DiagnosticsService.instance.configureForTests(
        remoteUploader: (_) async {},
      );
      await DiagnosticsService.instance.recordCrash(
        StateError('Splash crash'),
        StackTrace.current,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: SettingsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('DEVELOPMENT'), findsOneWidget);
      expect(find.text('Development'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Development'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Development'));
      await tester.pumpAndSettle();

      expect(find.byType(DevelopmentScreen), findsOneWidget);
      expect(find.text('DIAGNOSTICS'), findsOneWidget);
      expect(find.textContaining('Splash crash'), findsOneWidget);
    });

    testWidgets('DevelopmentScreen filters, creates perf snapshot/test error, and copies fix command', (tester) async {
      String? copiedClipboard;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedClipboard = (call.arguments as Map)['text'] as String?;
        }
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      DiagnosticsService.instance.configureForTests(
        remoteUploader: (_) async {},
      );
      await DiagnosticsService.instance.recordCrash(
        RangeError('Index out of range'),
        StackTrace.fromString('#0 ChatWidget (chat.dart:12)'),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: DevelopmentScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('All (1)'), findsOneWidget);
      expect(find.text('Crashes (1)'), findsOneWidget);

      // Trigger Snapshot Perf
      await tester.tap(find.text('Snapshot Perf'));
      await tester.pumpAndSettle();
      expect(find.text('Performance (1)'), findsOneWidget);

      // Trigger Test Error
      await tester.tap(find.text('Test Error'));
      await tester.pumpAndSettle();
      expect(find.text('Errors (1)'), findsOneWidget);

      // Filter to Crashes
      await tester.tap(find.text('Crashes (1)'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Index out of range'), findsOneWidget);
      expect(find.textContaining('Sample error logged'), findsNothing);

      // Open details sheet and copy Fix Command
      await tester.tap(find.textContaining('Index out of range'));
      await tester.pumpAndSettle();
      expect(find.text('Copy Fix Command'), findsOneWidget);

      await tester.tap(find.text('Copy Fix Command'));
      await tester.pumpAndSettle();
      expect(copiedClipboard, isNotNull);
      expect(copiedClipboard, contains('Index out of range'));
      expect(copiedClipboard, contains('chat.dart:12'));
    });

    test('deleteReport, clearResolved, and clearAll sync deletions to remote hooks and storage', () async {
      final deletedIds = <String>[];
      var clearResolvedCalls = 0;
      var clearAllCalls = 0;

      DiagnosticsService.instance.configureForTests(
        remoteDeleter: (id) async => deletedIds.add(id),
        remoteClearResolved: () async => clearResolvedCalls++,
        remoteClearAll: () async => clearAllCalls++,
      );

      final r1 = await DiagnosticsService.instance.recordReport(
        kind: DiagnosticReportKind.crash,
        title: 'Crash 1',
        message: 'First crash',
        stackTrace: 'a.dart:1',
      );
      final r2 = await DiagnosticsService.instance.recordReport(
        kind: DiagnosticReportKind.error,
        title: 'Error 2',
        message: 'Second error',
        stackTrace: 'b.dart:2',
      );
      final r3 = await DiagnosticsService.instance.recordReport(
        kind: DiagnosticReportKind.performance,
        title: 'Perf 3',
        message: 'Third perf',
        stackTrace: 'c.dart:3',
      );

      expect(r1, isNotNull);
      expect(r2, isNotNull);
      expect(r3, isNotNull);

      await DiagnosticsService.instance.deleteReport(r1!.id);
      expect(deletedIds, [r1.id]);
      expect(
        DiagnosticsService.instance.reportsNotifier.value.map((r) => r.id),
        isNot(contains(r1.id)),
      );

      await DiagnosticsService.instance.markResolved(r2!.id);
      await DiagnosticsService.instance.clearResolved();
      expect(clearResolvedCalls, 1);
      expect(
        DiagnosticsService.instance.reportsNotifier.value.map((r) => r.id),
        equals([r3!.id]),
      );

      await DiagnosticsService.instance.clearAll();
      expect(clearAllCalls, 1);
      expect(DiagnosticsService.instance.reportsNotifier.value, isEmpty);

      // Re-initializing from SharedPreferences confirms cleared state stays empty.
      DiagnosticsService.instance.resetForTests();
      await DiagnosticsService.instance.initialize();
      expect(DiagnosticsService.instance.reportsNotifier.value, isEmpty);
    });

    testWidgets('DevelopmentScreen fits 360px width without RenderFlex overflow and clears backend', (tester) async {
      var clearAllCalls = 0;
      DiagnosticsService.instance.configureForTests(
        remoteClearAll: () async => clearAllCalls++,
      );

      await DiagnosticsService.instance.recordReport(
        kind: DiagnosticReportKind.crash,
        title: 'Overflow regression crash',
        message: 'Sample crash',
        stackTrace: 'screen.dart:10',
      );

      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(home: DevelopmentScreen()),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Development'), findsOneWidget);
      expect(find.text('DIAGNOSTICS'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear All Logs'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear All'));
      await tester.pumpAndSettle();

      expect(clearAllCalls, 1);
      expect(DiagnosticsService.instance.reportsNotifier.value, isEmpty);
    });
  });
}
