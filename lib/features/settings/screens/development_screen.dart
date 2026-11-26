import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/utils/diagnostics_service.dart';
import 'package:worship_chat/common/widgets/custom_snackbar.dart';

/// Developer diagnostics screen displaying crash reports, non-fatal errors,
/// frame-jank/startup performance metrics, and one-tap AI fix command export.
class DevelopmentScreen extends StatefulWidget {
  static const String routeName = '/development-screen';

  const DevelopmentScreen({super.key});

  @override
  State<DevelopmentScreen> createState() => _DevelopmentScreenState();
}

class _DevelopmentScreenState extends State<DevelopmentScreen> {
  DiagnosticReportKind? _selectedKind;
  bool _hideResolved = false;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    DiagnosticsService.instance.initialize();
  }

  Future<void> _syncCloud() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);
    try {
      final synced = await DiagnosticsService.instance.syncPendingReports();
      if (!mounted) return;
      final total = DiagnosticsService.instance.reportsNotifier.value.length;
      AppSnackBar.success(
        context,
        synced > 0
            ? 'Synced $synced report(s) to cloud ($total total loaded).'
            : 'Diagnostics synced ($total total loaded).',
        title: 'Cloud Sync',
      );
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  Future<void> _copyCommandPrompt(String prompt, {String? customMessage}) async {
    await Clipboard.setData(ClipboardData(text: prompt));
    if (!mounted) return;
    AppSnackBar.success(
      context,
      customMessage ??
          'Copied diagnostic command prompt — paste it to fix this issue.',
      title: 'Copied Command',
    );
  }

  Future<void> _confirmClearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161426),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Clear All Reports?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'This removes locally stored crash, error, and performance logs from this device.',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE53935),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await DiagnosticsService.instance.clearAll();
      if (mounted) {
        AppSnackBar.info(context, 'Local diagnostic logs cleared.');
      }
    }
  }

  Future<void> _simulateTestCrash() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161426),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Simulate Crash Report?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Records a safe synthetic crash report with stack trace, route breadcrumbs, and sync queue without closing the app.',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE53935),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Record Test Crash'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      throw StateError('Simulated crash report triggered from Development');
    } catch (e, st) {
      await DiagnosticsService.instance.recordCrash(
        e,
        st,
        fatal: true,
        source: 'DeveloperTestCrash',
      );
      if (mounted) {
        AppSnackBar.warning(
          context,
          'Test crash recorded & queued for Firebase sync.',
          title: 'Crash Captured',
        );
      }
    }
  }

  void _openReportDetails(DiagnosticReport report) {
    final accent = _colorForKind(report.kind);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF161426),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: DraggableScrollableSheet(
            initialChildSize: 0.78,
            minChildSize: 0.45,
            maxChildSize: 0.94,
            expand: false,
            builder: (_, scrollController) {
              return Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: accent.withValues(alpha: 0.45),
                            ),
                          ),
                          child: Icon(_iconForKind(report.kind), color: accent, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                report.title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${report.kind.label} • ${DateFormat('MMM d, y • h:mm:ss a').format(report.timestamp)}',
                                style: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      children: [
                        _DetailBlock(
                          label: 'DETAILS',
                          content: report.message.isNotEmpty
                              ? report.message
                              : report.title,
                        ),
                        const SizedBox(height: 12),
                        _DetailBlock(
                          label: 'ENVIRONMENT',
                          content: [
                            'Version: ${report.appVersion} (${report.platform})',
                            if (report.source != null && report.source!.isNotEmpty)
                              'Source: ${report.source}',
                            if (report.routeName != null &&
                                report.routeName!.isNotEmpty)
                              'Route: ${report.routeName}',
                            if (report.userLabel != null &&
                                report.userLabel!.isNotEmpty)
                              'User: ${report.userLabel}',
                            'Sync Status: ${report.isSynced ? 'Synced to Firebase' : 'Local Queue'}',
                          ].join('\n'),
                        ),
                        if (report.metrics.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _DetailBlock(
                            label: 'PERFORMANCE METRICS',
                            content: const JsonEncoder.withIndent('  ')
                                .convert(report.metrics),
                            monospace: true,
                          ),
                        ],
                        if (report.breadcrumbs.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _DetailBlock(
                            label: 'NAVIGATION BREADCRUMBS',
                            content: report.breadcrumbs.join(' -> '),
                          ),
                        ],
                        if (report.stackTrace != null &&
                            report.stackTrace!.trim().isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _DetailBlock(
                            label: 'STACK TRACE',
                            content: report.stackTrace!.trim(),
                            monospace: true,
                          ),
                        ],
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF121020),
                      border: Border(
                        top: BorderSide(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                            label: const Text('Copy Fix Command'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: tabColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: () {
                              Navigator.pop(ctx);
                              _copyCommandPrompt(report.toFixCommandPrompt());
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: Icon(
                                  report.isResolved
                                      ? Icons.replay_rounded
                                      : Icons.check_circle_outline_rounded,
                                  size: 17,
                                  color: report.isResolved
                                      ? Colors.amber
                                      : const Color(0xFF00E676),
                                ),
                                label: Text(
                                  report.isResolved ? 'Reopen' : 'Mark Resolved',
                                  style: const TextStyle(color: Colors.white),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.18),
                                  ),
                                ),
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  DiagnosticsService.instance.markResolved(
                                    report.id,
                                    resolved: !report.isResolved,
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            OutlinedButton.icon(
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                size: 17,
                                color: Colors.redAccent,
                              ),
                              label: const Text(
                                'Delete',
                                style: TextStyle(color: Colors.redAccent),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                  color: Colors.redAccent.withValues(alpha: 0.35),
                                ),
                              ),
                              onPressed: () {
                                Navigator.pop(ctx);
                                DiagnosticsService.instance
                                    .deleteReport(report.id);
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Color _colorForKind(DiagnosticReportKind kind) {
    switch (kind) {
      case DiagnosticReportKind.crash:
        return const Color(0xFFFF4D6D);
      case DiagnosticReportKind.performance:
        return const Color(0xFFFFC107);
      case DiagnosticReportKind.error:
        return const Color(0xFFFF7043);
      case DiagnosticReportKind.warning:
        return const Color(0xFF38BDF8);
    }
  }

  IconData _iconForKind(DiagnosticReportKind kind) {
    switch (kind) {
      case DiagnosticReportKind.crash:
        return Icons.dangerous_rounded;
      case DiagnosticReportKind.performance:
        return Icons.speed_rounded;
      case DiagnosticReportKind.error:
        return Icons.error_outline_rounded;
      case DiagnosticReportKind.warning:
        return Icons.warning_amber_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0E17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161426),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            const Text(
              'Development',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF00E5FF).withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFF00E5FF).withValues(alpha: 0.4),
                ),
              ),
              child: const Text(
                'DIAGNOSTICS',
                style: TextStyle(
                  color: Color(0xFF00E5FF),
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Sync with Firebase',
            onPressed: _isSyncing ? null : _syncCloud,
            icon: _isSyncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF00E5FF),
                    ),
                  )
                : const Icon(
                    Icons.cloud_sync_rounded,
                    color: Color(0xFF00E5FF),
                  ),
          ),
          IconButton(
            tooltip: 'Copy Fix Command Prompt',
            icon: const Icon(Icons.auto_fix_high_rounded, color: Color(0xFFFFD700)),
            onPressed: () {
              final prompt = DiagnosticsService.instance
                  .exportUnresolvedAsCommand(filterKind: _selectedKind);
              _copyCommandPrompt(
                prompt,
                customMessage:
                    'Copied unresolved diagnostics prompt — paste to fix.',
              );
            },
          ),
          PopupMenuButton<String>(
            color: const Color(0xFF1D1B30),
            icon: const Icon(Icons.more_vert_rounded, color: Colors.white70),
            onSelected: (value) {
              if (value == 'hide_resolved') {
                setState(() => _hideResolved = !_hideResolved);
              } else if (value == 'clear_resolved') {
                DiagnosticsService.instance.clearResolved();
              } else if (value == 'clear_all') {
                _confirmClearAll();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'hide_resolved',
                child: Text(
                  _hideResolved ? 'Show Resolved Items' : 'Hide Resolved Items',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
              const PopupMenuItem(
                value: 'clear_resolved',
                child: Text(
                  'Clear Resolved',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
              const PopupMenuItem(
                value: 'clear_all',
                child: Text(
                  'Clear All Logs',
                  style: TextStyle(color: Colors.redAccent, fontSize: 13),
                ),
              ),
            ],
          ),
        ],
      ),
      body: ValueListenableBuilder<List<DiagnosticReport>>(
        valueListenable: DiagnosticsService.instance.reportsNotifier,
        builder: (context, allReports, _) {
          final filtered = allReports.where((r) {
            if (_hideResolved && r.isResolved) return false;
            if (_selectedKind != null && r.kind != _selectedKind) return false;
            return true;
          }).toList(growable: false);

          final crashCount = allReports
              .where((r) => r.kind == DiagnosticReportKind.crash)
              .length;
          final perfCount = allReports
              .where((r) => r.kind == DiagnosticReportKind.performance)
              .length;
          final errorCount = allReports
              .where((r) =>
                  r.kind == DiagnosticReportKind.error ||
                  r.kind == DiagnosticReportKind.warning)
              .length;

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _TelemetryCard(
                        onSnapshotPerf: () async {
                          await DiagnosticsService.instance
                              .capturePerformanceSnapshot();
                          if (context.mounted) {
                            AppSnackBar.info(
                              context,
                              'Captured live frame & startup performance snapshot.',
                            );
                          }
                        },
                        onTestError: () async {
                          try {
                            throw Exception(
                              'Sample error logged from Development screen',
                            );
                          } catch (e, st) {
                            await DiagnosticsService.instance.recordError(
                              e,
                              stackTrace: st,
                              context: 'Diagnostic self-test',
                              source: 'DevelopmentScreen',
                            );
                            if (context.mounted) {
                              AppSnackBar.warning(
                                context,
                                'Test error captured & queued.',
                              );
                            }
                          }
                        },
                        onTestCrash: _simulateTestCrash,
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 36,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            _FilterChipItem(
                              label: 'All (${allReports.length})',
                              selected: _selectedKind == null,
                              color: tabColor,
                              onTap: () => setState(() => _selectedKind = null),
                            ),
                            const SizedBox(width: 8),
                            _FilterChipItem(
                              label: 'Crashes ($crashCount)',
                              selected:
                                  _selectedKind == DiagnosticReportKind.crash,
                              color: const Color(0xFFFF4D6D),
                              onTap: () => setState(
                                () =>
                                    _selectedKind = DiagnosticReportKind.crash,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _FilterChipItem(
                              label: 'Performance ($perfCount)',
                              selected: _selectedKind ==
                                  DiagnosticReportKind.performance,
                              color: const Color(0xFFFFC107),
                              onTap: () => setState(
                                () => _selectedKind =
                                    DiagnosticReportKind.performance,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _FilterChipItem(
                              label: 'Errors ($errorCount)',
                              selected:
                                  _selectedKind == DiagnosticReportKind.error,
                              color: const Color(0xFFFF7043),
                              onTap: () => setState(
                                () =>
                                    _selectedKind = DiagnosticReportKind.error,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (filtered.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF00E676)
                                  .withValues(alpha: 0.14),
                            ),
                            child: const Icon(
                              Icons.verified_rounded,
                              color: Color(0xFF00E676),
                              size: 32,
                            ),
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'No Reports Yet',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Crashes, UI errors, and slow-frame performance reports are captured here automatically and synced to Firebase.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  sliver: SliverList.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, idx) {
                      final report = filtered[idx];
                      final accent = _colorForKind(report.kind);
                      return _ReportCard(
                        report: report,
                        accent: accent,
                        icon: _iconForKind(report.kind),
                        onTap: () => _openReportDetails(report),
                        onCopyPrompt: () =>
                            _copyCommandPrompt(report.toFixCommandPrompt()),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _TelemetryCard extends StatelessWidget {
  final VoidCallback onSnapshotPerf;
  final VoidCallback onTestError;
  final VoidCallback onTestCrash;

  const _TelemetryCard({
    required this.onSnapshotPerf,
    required this.onTestError,
    required this.onTestCrash,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PerformanceTelemetrySnapshot>(
      valueListenable: DiagnosticsService.instance.telemetryNotifier,
      builder: (context, snap, _) {
        final fpsColor = snap.estimatedFps >= 55
            ? const Color(0xFF00E676)
            : (snap.estimatedFps >= 40
                ? const Color(0xFFFFC107)
                : const Color(0xFFFF4D6D));

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF161426),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.09),
              width: 0.8,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.monitor_heart_rounded,
                    color: Color(0xFF00E5FF),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Live Performance & Crash Monitor',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: fpsColor.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: fpsColor.withValues(alpha: 0.45),
                      ),
                    ),
                    child: Text(
                      '~${snap.estimatedFps.toStringAsFixed(0)} FPS',
                      style: TextStyle(
                        color: fpsColor,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MetricTile(label: 'Frames', value: '${snap.totalFrames}'),
                  _MetricTile(
                    label: 'Slow (>32ms)',
                    value: '${snap.slowFrames}',
                    valueColor:
                        snap.slowFrames > 0 ? Colors.amber : Colors.white,
                  ),
                  _MetricTile(
                    label: 'Avg Build',
                    value: '${snap.avgBuildMs.toStringAsFixed(1)}ms',
                  ),
                  _MetricTile(
                    label: 'Worst Frame',
                    value: '${snap.worstFrameMs.toStringAsFixed(1)}ms',
                  ),
                  if (snap.coldStartMs != null)
                    _MetricTile(
                      label: 'Startup',
                      value: '${snap.coldStartMs}ms',
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _ActionChip(
                    icon: Icons.speed_rounded,
                    label: 'Snapshot Perf',
                    color: const Color(0xFFFFC107),
                    onTap: onSnapshotPerf,
                  ),
                  _ActionChip(
                    icon: Icons.bug_report_rounded,
                    label: 'Test Error',
                    color: const Color(0xFFFF7043),
                    onTap: onTestError,
                  ),
                  _ActionChip(
                    icon: Icons.warning_rounded,
                    label: 'Test Crash',
                    color: const Color(0xFFFF4D6D),
                    onTap: onTestCrash,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;

  const _MetricTile({
    required this.label,
    required this.value,
    this.valueColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0E17),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.grey[400], fontSize: 10),
          ),
          const SizedBox(height: 1),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChipItem extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _FilterChipItem({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      selectedColor: color.withValues(alpha: 0.25),
      backgroundColor: const Color(0xFF161426),
      side: BorderSide(
        color: selected ? color : Colors.white.withValues(alpha: 0.10),
      ),
      labelStyle: TextStyle(
        color: selected ? Colors.white : Colors.grey[400],
        fontSize: 12,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
      onSelected: (_) => onTap(),
    );
  }
}

class _ReportCard extends StatelessWidget {
  final DiagnosticReport report;
  final Color accent;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback onCopyPrompt;

  const _ReportCard({
    required this.report,
    required this.accent,
    required this.icon,
    required this.onTap,
    required this.onCopyPrompt,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF161426),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: report.isResolved
                  ? Colors.white.withValues(alpha: 0.06)
                  : accent.withValues(alpha: 0.35),
              width: 0.9,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(icon, color: accent, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          report.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: report.isResolved
                                ? Colors.grey[400]
                                : Colors.white,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            decoration: report.isResolved
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          DateFormat('MMM d • h:mm:ss a')
                              .format(report.timestamp),
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy fix command',
                    onPressed: onCopyPrompt,
                    icon: const Icon(
                      Icons.copy_rounded,
                      size: 18,
                      color: Colors.white70,
                    ),
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
              if (report.message.isNotEmpty &&
                  report.message.trim() != report.title.trim()) ...[
                const SizedBox(height: 8),
                Text(
                  report.message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.grey[300], fontSize: 12),
                ),
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _TagBadge(label: report.kind.label, color: accent),
                  _TagBadge(
                    label: report.isSynced ? 'Synced' : 'Local',
                    color: report.isSynced
                        ? const Color(0xFF00E676)
                        : Colors.grey,
                  ),
                  if (report.routeName != null && report.routeName!.isNotEmpty)
                    _TagBadge(
                      label: report.routeName!,
                      color: const Color(0xFF8B5CF6),
                    ),
                  if (report.isResolved)
                    const _TagBadge(
                      label: 'Resolved',
                      color: Color(0xFF00E676),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TagBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _TagBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 0.7),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _DetailBlock extends StatelessWidget {
  final String label;
  final String content;
  final bool monospace;

  const _DetailBlock({
    required this.label,
    required this.content,
    this.monospace = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[400],
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 5),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: const Color(0xFF0F0E17),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: SelectableText(
            content,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: monospace ? 11.2 : 12.5,
              fontFamily: monospace ? 'monospace' : null,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
