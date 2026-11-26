import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worship_chat/common/utils/app_capabilities.dart';
import 'package:worship_chat/common/utils/firebase_notification_service.dart';
import 'package:worship_chat/common/widgets/app_update_dialog.dart';
import 'package:worship_chat/common/widgets/custom_snackbar.dart';

/// Metadata describing an available Android APK release stored in Firestore
/// under `app_config/android_update`.
class AppUpdateInfo {
  final int latestVersionCode;
  final String latestVersionName;
  final String apkUrl;
  final String releaseNotes;
  final bool forceUpdate;
  final int minSupportedVersionCode;
  final String? sha256;
  final bool enabled;

  const AppUpdateInfo({
    required this.latestVersionCode,
    required this.latestVersionName,
    required this.apkUrl,
    this.releaseNotes = '',
    this.forceUpdate = false,
    this.minSupportedVersionCode = 0,
    this.sha256,
    this.enabled = true,
  });

  /// Parses Firestore `app_config/android_update` data safely.
  static AppUpdateInfo? fromMap(Map<String, dynamic>? map) {
    if (map == null) return null;

    final enabled = map['enabled'] is bool ? map['enabled'] as bool : true;
    final apkUrl = (map['apkUrl'] ?? map['downloadUrl'] ?? map['url'] ?? '')
        .toString()
        .trim();

    if (!enabled ||
        (!apkUrl.startsWith('http://') && !apkUrl.startsWith('https://'))) {
      return null;
    }

    final versionCode = _parseInt(
      map['latestVersionCode'] ?? map['versionCode'] ?? map['buildNumber'],
    );
    final versionName =
        (map['latestVersionName'] ?? map['versionName'] ?? map['version'] ?? '')
            .toString()
            .trim();

    if (versionCode <= 0 && versionName.isEmpty) {
      return null;
    }

    final rawNotes =
        (map['releaseNotes'] ?? map['changelog'] ?? map['notes'] ?? '')
            .toString()
            .trim();

    final minSupported = _parseInt(map['minSupportedVersionCode']);
    final forceFlag = map['forceUpdate'] == true;
    final rawSha = map['sha256']?.toString().trim();

    return AppUpdateInfo(
      latestVersionCode: versionCode,
      latestVersionName:
          versionName.isNotEmpty ? versionName : 'v$versionCode',
      apkUrl: apkUrl,
      releaseNotes: rawNotes,
      forceUpdate: forceFlag,
      minSupportedVersionCode: minSupported,
      sha256: (rawSha != null && rawSha.isNotEmpty) ? rawSha.toLowerCase() : null,
      enabled: enabled,
    );
  }

  /// Parses a GitHub Releases API JSON payload (`/repos/<owner>/<repo>/releases/latest`).
  ///
  /// Supports tag names such as `v1.0.1+2`, `v1.0.1-b2`, `v1.0.1-build.2`, or `v1.0.1`.
  /// Optional directives in the release body:
  /// - `[FORCE]` or `forceUpdate: true` marks the update mandatory
  /// - `sha256: <64-hex>` attaches integrity verification
  static AppUpdateInfo? fromGitHubReleaseJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    if (json['draft'] == true || json['prerelease'] == true) return null;

    final rawAssets = json['assets'];
    if (rawAssets is! List || rawAssets.isEmpty) return null;

    String? preferredApkUrl;
    String? fallbackApkUrl;
    for (final item in rawAssets) {
      if (item is! Map) continue;
      final name = (item['name'] ?? '').toString().trim().toLowerCase();
      final url = (item['browser_download_url'] ?? '').toString().trim();
      if (!name.endsWith('.apk')) continue;
      if (!url.startsWith('http://') && !url.startsWith('https://')) continue;
      if (!name.contains('debug')) {
        preferredApkUrl ??= url;
      } else {
        fallbackApkUrl ??= url;
      }
    }

    final apkUrl = preferredApkUrl ?? fallbackApkUrl;
    if (apkUrl == null) return null;

    final rawTag = (json['tag_name'] ?? json['name'] ?? '').toString().trim();
    if (rawTag.isEmpty) return null;

    final parsedTag = _parseTagVersion(rawTag);
    if (parsedTag.versionCode <= 0 && parsedTag.versionName.isEmpty) {
      return null;
    }

    final rawBody = (json['body'] ?? '').toString();
    final shaMatch = RegExp(
      r'sha256\s*:\s*([a-fA-F0-9]{64})',
      caseSensitive: false,
    ).firstMatch(rawBody);
    final shaValue = shaMatch?.group(1)?.toLowerCase();

    final forceUpdate = RegExp(
      r'(\[FORCE\]|forceUpdate\s*:\s*true)',
      caseSensitive: false,
    ).hasMatch(rawBody);

    final cleanedNotes = rawBody
        .replaceAll(RegExp(r'sha256\s*:\s*[a-fA-F0-9]{64}', caseSensitive: false), '')
        .replaceAll(RegExp(r'forceUpdate\s*:\s*(true|false)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\[FORCE\]', caseSensitive: false), '')
        .split('\n')
        .map((line) => line.trimRight())
        .where((line) => line.trim().isNotEmpty)
        .join('\n')
        .trim();

    return AppUpdateInfo(
      latestVersionCode: parsedTag.versionCode,
      latestVersionName: parsedTag.versionName.isNotEmpty
          ? parsedTag.versionName
          : 'v${parsedTag.versionCode}',
      apkUrl: apkUrl,
      releaseNotes: cleanedNotes,
      forceUpdate: forceUpdate,
      sha256: shaValue,
      enabled: true,
    );
  }

  static ({String versionName, int versionCode}) _parseTagVersion(String rawTag) {
    final cleaned = rawTag.replaceFirst(RegExp(r'^v', caseSensitive: false), '').trim();
    // Matches e.g. 1.0.1+2, 1.0.1-b2, 1.0.1-build.2, 1.0.1-build2
    final match = RegExp(
      r'^(\d+(?:\.\d+)*)(?:(?:\+|-b(?:uild)?\.?)(\d+))?',
      caseSensitive: false,
    ).firstMatch(cleaned);
    if (match != null) {
      return (
        versionName: match.group(1) ?? '',
        versionCode: int.tryParse(match.group(2) ?? '') ?? 0,
      );
    }
    return (versionName: cleaned, versionCode: 0);
  }

  static int _parseInt(dynamic raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim()) ?? 0;
    return 0;
  }

  /// Whether this update is mandatory for an installation on [currentVersionCode].
  bool isForcedFor(int currentVersionCode) {
    return forceUpdate ||
        (minSupportedVersionCode > 0 &&
            currentVersionCode < minSupportedVersionCode);
  }

  /// Checks whether this remote release is newer than the installed build.
  bool isNewerThan(
    int currentVersionCode, {
    String? currentVersionName,
  }) {
    if (latestVersionCode > currentVersionCode) {
      return true;
    }
    if (latestVersionCode < currentVersionCode && latestVersionCode > 0) {
      return false;
    }
    if (currentVersionName != null && latestVersionName.isNotEmpty) {
      return _compareSemanticVersions(latestVersionName, currentVersionName) >
          0;
    }
    return false;
  }

  static int _compareSemanticVersions(String a, String b) {
    List<int> parseParts(String v) {
      final clean = v.replaceFirst(RegExp(r'^v', caseSensitive: false), '');
      final withoutBuild = clean.split('+').first.split('-').first;
      return withoutBuild
          .split('.')
          .map((p) => int.tryParse(p.trim()) ?? 0)
          .toList();
    }

    final partsA = parseParts(a);
    final partsB = parseParts(b);
    final len =
        partsA.length > partsB.length ? partsA.length : partsB.length;
    for (int i = 0; i < len; i++) {
      final va = i < partsA.length ? partsA[i] : 0;
      final vb = i < partsB.length ? partsB[i] : 0;
      if (va != vb) return va.compareTo(vb);
    }
    return 0;
  }
}

/// Installed app version descriptor.
class InstalledAppVersion {
  final String versionName;
  final int versionCode;

  const InstalledAppVersion({
    required this.versionName,
    required this.versionCode,
  });
}

/// Outcome of attempting to trigger Android's APK installer.
class ApkInstallResult {
  final bool launched;
  final bool needsPermission;
  final String message;

  const ApkInstallResult({
    required this.launched,
    this.needsPermission = false,
    this.message = '',
  });
}

enum UpdateCheckStatus {
  updateAvailable,
  upToDate,
  notConfigured,
  unsupportedPlatform,
  failed,
}

class UpdateCheckOutcome {
  final UpdateCheckStatus status;
  final InstalledAppVersion installed;
  final AppUpdateInfo? updateInfo;
  final String? errorMessage;

  const UpdateCheckOutcome({
    required this.status,
    required this.installed,
    this.updateInfo,
    this.errorMessage,
  });
}

typedef RemoteUpdateFetcher = Future<AppUpdateInfo?> Function();
typedef InstalledVersionReader = Future<InstalledAppVersion> Function();
typedef UpdateNotificationSender = Future<void> Function({
  required String versionName,
  required int versionCode,
  String? releaseNotes,
  bool forceUpdate,
});
typedef UpdateNotificationCanceller = Future<void> Function();

/// Self-hosted in-app APK updater for non-Play-Store Android distribution.
class AppUpdateService {
  AppUpdateService({
    RemoteUpdateFetcher? remoteFetcher,
    InstalledVersionReader? versionReader,
    UpdateNotificationSender? notificationSender,
    UpdateNotificationCanceller? notificationCanceller,
    DateTime Function()? nowProvider,
    Dio? dio,
    bool? isAndroidOverride,
  })  : _remoteFetcher = remoteFetcher,
        _versionReader = versionReader,
        _notificationSender = notificationSender,
        _notificationCanceller = notificationCanceller,
        _nowProvider = nowProvider ?? DateTime.now,
        _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 20),
                receiveTimeout: const Duration(minutes: 5),
                followRedirects: true,
                maxRedirects: 5,
              ),
            ),
        _isAndroidOverride = isAndroidOverride;

  static final AppUpdateService instance = AppUpdateService();

  static const String configCollection = 'app_config';
  static const String configDocument = 'android_update';
  static const String githubRepo = 'spideynk25/worship_chat';
  static const String skippedVersionPrefKey = 'skipped_update_version_code';
  static const String notifiedVersionCodePrefKey =
      'notified_update_version_code';
  static const String notifiedVersionNamePrefKey =
      'notified_update_version_name';
  static const String lastCheckMillisPrefKey = 'last_update_check_ms';
  static const Duration resumeCheckCooldown = Duration(hours: 2);
  static const MethodChannel _deviceChannel =
      MethodChannel('worship_chat/device');

  final RemoteUpdateFetcher? _remoteFetcher;
  final InstalledVersionReader? _versionReader;
  final UpdateNotificationSender? _notificationSender;
  final UpdateNotificationCanceller? _notificationCanceller;
  final DateTime Function() _nowProvider;
  final Dio _dio;
  final bool? _isAndroidOverride;

  /// Broadcasts the currently available update so top-bar badges and menus
  /// stay in sync even after dismissing a prompt with "Later".
  final ValueNotifier<UpdateCheckOutcome?> availableOutcomeNotifier =
      ValueNotifier<UpdateCheckOutcome?>(null);

  bool _hasCheckedAutoThisSession = false;
  bool _isDialogVisible = false;
  bool _isCheckingResume = false;
  bool _hasScheduledBackgroundJob = false;

  bool get _isAndroid =>
      _isAndroidOverride ??
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  @visibleForTesting
  void resetSessionState() {
    _hasCheckedAutoThisSession = false;
    _isDialogVisible = false;
    _isCheckingResume = false;
    _hasScheduledBackgroundJob = false;
    availableOutcomeNotifier.value = null;
  }

  /// Reads installed app version safely (falls back gracefully in unit tests).
  Future<InstalledAppVersion> getInstalledVersion() async {
    if (_versionReader != null) {
      return _versionReader();
    }
    try {
      final info = await PackageInfo.fromPlatform();
      final code = int.tryParse(info.buildNumber.trim()) ?? 1;
      final name = info.version.trim().isNotEmpty ? info.version.trim() : '1.0.0';
      return InstalledAppVersion(versionName: name, versionCode: code);
    } catch (e) {
      log('AppUpdateService: PackageInfo fallback used ($e)');
      return const InstalledAppVersion(versionName: '1.0.0', versionCode: 1);
    }
  }

  /// Fetches remote APK metadata from Firestore (`app_config/android_update`)
  /// and falls back to GitHub Releases (`spideynk25/worship_chat/releases/latest`).
  ///
  /// If Firestore exists and explicitly sets `enabled: false`, updates stay paused.
  Future<AppUpdateInfo?> fetchRemoteUpdateInfo() async {
    if (_remoteFetcher != null) {
      return _remoteFetcher();
    }

    AppUpdateInfo? firestoreInfo;
    if (Firebase.apps.isNotEmpty) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection(configCollection)
            .doc(configDocument)
            .get();
        if (doc.exists) {
          final data = doc.data();
          if (data != null && data['enabled'] == false) {
            return null;
          }
          firestoreInfo = AppUpdateInfo.fromMap(data);
        }
      } catch (e) {
        log('AppUpdateService: Firestore update check skipped ($e)');
      }
    }

    final githubInfo = await fetchGitHubLatestRelease();
    if (firestoreInfo == null) return githubInfo;
    if (githubInfo == null) return firestoreInfo;

    return githubInfo.isNewerThan(
      firestoreInfo.latestVersionCode,
      currentVersionName: firestoreInfo.latestVersionName,
    )
        ? githubInfo
        : firestoreInfo;
  }

  /// Queries GitHub Releases API for the latest published APK release.
  Future<AppUpdateInfo?> fetchGitHubLatestRelease() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        'https://api.github.com/repos/$githubRepo/releases/latest',
        options: Options(
          headers: const {'Accept': 'application/vnd.github+json'},
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      if (response.statusCode != 200 || response.data == null) {
        return null;
      }
      return AppUpdateInfo.fromGitHubReleaseJson(response.data);
    } catch (e) {
      log('AppUpdateService: GitHub release check failed ($e)');
      return null;
    }
  }

  /// Pushes a local notification once per newly discovered remote version.
  Future<bool> notifyIfNewUpdateAvailable(UpdateCheckOutcome outcome) async {
    if (!_isAndroid || !AppCapabilities.current.notificationsEnabled) {
      return false;
    }
    final info = outcome.updateInfo;
    if (outcome.status != UpdateCheckStatus.updateAvailable || info == null) {
      return false;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastCode = prefs.getInt(notifiedVersionCodePrefKey) ?? 0;
      final lastName = prefs.getString(notifiedVersionNamePrefKey) ?? '';

      final alreadyNotified = lastCode > 0 &&
          !info.isNewerThan(lastCode, currentVersionName: lastName);
      if (alreadyNotified) {
        return false;
      }

      final sender = _notificationSender ??
          ({
            required String versionName,
            required int versionCode,
            String? releaseNotes,
            bool forceUpdate = false,
          }) =>
              FirebaseNotificationService.showAppUpdateNotification(
                versionName: versionName,
                versionCode: versionCode,
                releaseNotes: releaseNotes,
                forceUpdate: forceUpdate,
              );

      await sender(
        versionName: info.latestVersionName,
        versionCode: info.latestVersionCode,
        releaseNotes: info.releaseNotes,
        forceUpdate: info.isForcedFor(outcome.installed.versionCode),
      );

      await prefs.setInt(notifiedVersionCodePrefKey, info.latestVersionCode);
      await prefs.setString(notifiedVersionNamePrefKey, info.latestVersionName);
      return true;
    } catch (e) {
      log('AppUpdateService: could not push update notification ($e)');
      return false;
    }
  }

  Future<void> _cancelUpdateNotification() async {
    if (!AppCapabilities.current.notificationsEnabled) return;
    try {
      final canceller = _notificationCanceller ??
          FirebaseNotificationService.cancelAppUpdateNotification;
      await canceller();
    } catch (_) {}
  }

  Future<void> _recordLastCheckTimestamp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        lastCheckMillisPrefKey,
        _nowProvider().millisecondsSinceEpoch,
      );
    } catch (_) {}
  }

  /// Schedules the periodic native Android JobScheduler release checker.
  Future<void> scheduleBackgroundUpdateCheck() async {
    if (_hasScheduledBackgroundJob ||
        !_isAndroid ||
        !AppCapabilities.current.notificationsEnabled) {
      return;
    }
    _hasScheduledBackgroundJob = true;
    try {
      await _deviceChannel.invokeMethod<void>('scheduleUpdateCheckJob');
    } on MissingPluginException {
      // Safe no-op in widget/unit tests.
    } catch (e) {
      log('AppUpdateService: could not schedule background update job ($e)');
    }
  }

  /// Consumes whether Android MainActivity was opened by tapping a background
  /// update notification.
  Future<bool> consumePendingNativeUpdateLaunch() async {
    if (!_isAndroid) return false;
    try {
      return await _deviceChannel
              .invokeMethod<bool>('consumePendingUpdateLaunch') ??
          false;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Registers or clears a callback invoked when Android delivers a warm
  /// tap intent from a native background update notification.
  void setNativeUpdateTapHandler(VoidCallback? onTapped) {
    if (!_isAndroid) return;
    if (onTapped == null) {
      _deviceChannel.setMethodCallHandler(null);
      return;
    }
    _deviceChannel.setMethodCallHandler((call) async {
      if (call.method == 'onUpdateNotificationTapped') {
        onTapped();
      }
    });
  }

  /// Checks whether an update is available compared to the installed build.
  Future<UpdateCheckOutcome> checkForUpdate({
    bool respectSkippedVersion = false,
    bool notifyIfAvailable = true,
  }) async {
    final installed = await getInstalledVersion();
    if (!_isAndroid) {
      return UpdateCheckOutcome(
        status: UpdateCheckStatus.unsupportedPlatform,
        installed: installed,
      );
    }

    try {
      final remote = await fetchRemoteUpdateInfo();
      await _recordLastCheckTimestamp();
      if (remote == null) {
        return UpdateCheckOutcome(
          status: UpdateCheckStatus.notConfigured,
          installed: installed,
        );
      }

      if (!remote.isNewerThan(
        installed.versionCode,
        currentVersionName: installed.versionName,
      )) {
        availableOutcomeNotifier.value = null;
        await _cancelUpdateNotification();
        return UpdateCheckOutcome(
          status: UpdateCheckStatus.upToDate,
          installed: installed,
          updateInfo: remote,
        );
      }

      final outcome = UpdateCheckOutcome(
        status: UpdateCheckStatus.updateAvailable,
        installed: installed,
        updateInfo: remote,
      );
      availableOutcomeNotifier.value = outcome;

      if (notifyIfAvailable) {
        await notifyIfNewUpdateAvailable(outcome);
      }

      final forced = remote.isForcedFor(installed.versionCode);
      if (respectSkippedVersion && !forced) {
        final skipped = await getSkippedVersionCode();
        if (skipped != null && skipped == remote.latestVersionCode) {
          return UpdateCheckOutcome(
            status: UpdateCheckStatus.upToDate,
            installed: installed,
            updateInfo: remote,
          );
        }
      }

      return outcome;
    } catch (e) {
      log('AppUpdateService: update check failed: $e');
      return UpdateCheckOutcome(
        status: UpdateCheckStatus.failed,
        installed: installed,
        errorMessage: e.toString(),
      );
    }
  }

  /// Silent check run once per session when HomeScreen opens.
  Future<void> checkForUpdateIfAvailable(BuildContext context) async {
    if (!_isAndroid || _hasCheckedAutoThisSession || _isDialogVisible) return;
    if (_remoteFetcher == null && Firebase.apps.isEmpty) return;

    _hasCheckedAutoThisSession = true;
    unawaited(scheduleBackgroundUpdateCheck());
    final outcome = await checkForUpdate(
      respectSkippedVersion: false,
      notifyIfAvailable: true,
    );
    if (!context.mounted) return;

    final isTopRoute = ModalRoute.of(context)?.isCurrent ?? true;
    if (isTopRoute &&
        outcome.status == UpdateCheckStatus.updateAvailable &&
        outcome.updateInfo != null) {
      await showUpdateDialog(
        context,
        installed: outcome.installed,
        updateInfo: outcome.updateInfo!,
      );
    }
  }

  /// Silent cooldown-gated update check when returning to foreground so newly
  /// published releases trigger a notification and badge without dialog spam.
  Future<void> checkForUpdateOnResume(BuildContext context) async {
    if (!_isAndroid || _isCheckingResume) return;
    if (_remoteFetcher == null && Firebase.apps.isEmpty) return;

    _isCheckingResume = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastMs = prefs.getInt(lastCheckMillisPrefKey) ?? 0;
      final nowMs = _nowProvider().millisecondsSinceEpoch;
      if (lastMs > 0 && nowMs - lastMs < resumeCheckCooldown.inMilliseconds) {
        return;
      }

      await checkForUpdate(
        respectSkippedVersion: false,
        notifyIfAvailable: true,
      );
    } catch (_) {
    } finally {
      _isCheckingResume = false;
    }
  }

  /// Opens the update dialog directly from cached availability state, or falls
  /// back to a live manual update check if no cached update is held.
  Future<void> openAvailableUpdateDialog(BuildContext context) async {
    unawaited(_cancelUpdateNotification());
    final cached = availableOutcomeNotifier.value;
    if (cached != null &&
        cached.status == UpdateCheckStatus.updateAvailable &&
        cached.updateInfo != null) {
      await showUpdateDialog(
        context,
        installed: cached.installed,
        updateInfo: cached.updateInfo!,
      );
      return;
    }
    await checkManually(context);
  }

  /// Explicit user-triggered update check (e.g. from Settings screen).
  Future<void> checkManually(BuildContext context) async {
    final outcome = await checkForUpdate(respectSkippedVersion: false);
    if (!context.mounted) return;

    switch (outcome.status) {
      case UpdateCheckStatus.updateAvailable:
        if (outcome.updateInfo != null) {
          await clearSkippedVersion();
          if (!context.mounted) return;
          await showUpdateDialog(
            context,
            installed: outcome.installed,
            updateInfo: outcome.updateInfo!,
          );
        }
        break;
      case UpdateCheckStatus.upToDate:
        AppSnackBar.success(
          context,
          'You are on the latest version (v${outcome.installed.versionName}+${outcome.installed.versionCode}).',
          title: 'Up to Date',
        );
        break;
      case UpdateCheckStatus.notConfigured:
        AppSnackBar.info(
          context,
          'No release published yet on GitHub Releases ($githubRepo) or Firestore.',
          title: 'v${outcome.installed.versionName}+${outcome.installed.versionCode}',
        );
        break;
      case UpdateCheckStatus.unsupportedPlatform:
        AppSnackBar.info(
          context,
          'In-app APK updates are supported on Android devices.',
        );
        break;
      case UpdateCheckStatus.failed:
        AppSnackBar.error(
          context,
          'Could not check for updates. Please verify your internet connection.',
        );
        break;
    }
  }

  /// Opens the update prompt & download modal dialog.
  Future<void> showUpdateDialog(
    BuildContext context, {
    required InstalledAppVersion installed,
    required AppUpdateInfo updateInfo,
  }) async {
    if (_isDialogVisible || !context.mounted) return;
    _isDialogVisible = true;
    unawaited(_cancelUpdateNotification());
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: !updateInfo.isForcedFor(installed.versionCode),
        builder: (_) => AppUpdateDialog(
          service: this,
          installed: installed,
          updateInfo: updateInfo,
        ),
      );
    } finally {
      _isDialogVisible = false;
    }
  }

  Future<int?> getSkippedVersionCode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(skippedVersionPrefKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> skipVersion(int versionCode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(skippedVersionPrefKey, versionCode);
    } catch (_) {}
  }

  Future<void> clearSkippedVersion() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(skippedVersionPrefKey);
    } catch (_) {}
  }

  /// Resolves a deterministic local cache path for a release APK.
  Future<File> resolveTargetApkFile(AppUpdateInfo info) async {
    final dir = await getTemporaryDirectory();
    final safeVer = info.latestVersionName.replaceAll(RegExp(r'[^\w.\-]'), '_');
    return File(
      '${dir.path}/worship_chat_v${safeVer}_${info.latestVersionCode}.apk',
    );
  }

  /// Downloads the APK atomically to a `.part` temp file, optionally verifies
  /// its SHA-256 checksum via streaming digest, and renames it to `.apk`.
  Future<File> downloadApk(
    AppUpdateInfo info, {
    CancelToken? cancelToken,
    void Function(int receivedBytes, int totalBytes)? onProgress,
  }) async {
    final targetFile = await resolveTargetApkFile(info);

    // Clean up older cached APKs or stray .part files so storage doesn't grow
    await _cleanupStaleApks(targetFile);

    // If an already-downloaded file exists and passes verification, reuse it
    if (await targetFile.exists()) {
      final len = await targetFile.length();
      if (len > 0 && await verifySha256IfProvided(targetFile, info.sha256)) {
        onProgress?.call(len, len);
        return targetFile;
      }
      await targetFile.delete();
    }

    final partFile = File('${targetFile.path}.part');
    if (await partFile.exists()) {
      await partFile.delete();
    }

    try {
      await _dio.download(
        info.apkUrl,
        partFile.path,
        cancelToken: cancelToken,
        deleteOnError: true,
        onReceiveProgress: (received, total) {
          onProgress?.call(received, total);
        },
      );

      if (!await partFile.exists() || await partFile.length() == 0) {
        throw const FileSystemException('Downloaded APK file is empty.');
      }

      final valid = await verifySha256IfProvided(partFile, info.sha256);
      if (!valid) {
        await partFile.delete();
        throw const FormatException(
          'APK integrity check failed (SHA-256 mismatch).',
        );
      }

      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      return await partFile.rename(targetFile.path);
    } catch (_) {
      if (await partFile.exists()) {
        try {
          await partFile.delete();
        } catch (_) {}
      }
      rethrow;
    }
  }

  /// Verifies [file] against [expectedSha256] using a streaming digest so
  /// large APKs never spike memory.
  Future<bool> verifySha256IfProvided(File file, String? expectedSha256) async {
    if (expectedSha256 == null || expectedSha256.trim().isEmpty) {
      return true;
    }
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString().toLowerCase() ==
        expectedSha256.trim().toLowerCase();
  }

  Future<void> _cleanupStaleApks(File keepFile) async {
    try {
      final parent = keepFile.parent;
      await for (final entity in parent.list()) {
        if (entity is File && entity.path != keepFile.path) {
          final name = entity.uri.pathSegments.last;
          if (name.startsWith('worship_chat_v') &&
              (name.endsWith('.apk') || name.endsWith('.part'))) {
            await entity.delete();
          }
        }
      }
    } catch (_) {}
  }

  /// Ensures Android "Install unknown apps" permission is granted and invokes
  /// the native package installer via [OpenFilex].
  Future<ApkInstallResult> installApk(File apkFile) async {
    if (!await apkFile.exists()) {
      return const ApkInstallResult(
        launched: false,
        message: 'APK file not found. Please download again.',
      );
    }

    if (!_isAndroid) {
      return const ApkInstallResult(
        launched: false,
        message: 'APK installation is only supported on Android.',
      );
    }

    try {
      var status = await Permission.requestInstallPackages.status;
      if (!status.isGranted) {
        status = await Permission.requestInstallPackages.request();
      }
      if (!status.isGranted) {
        return const ApkInstallResult(
          launched: false,
          needsPermission: true,
          message:
              'Please allow "Install unknown apps" for Worship Chat in Settings, then tap Install Now.',
        );
      }

      final result = await OpenFilex.open(
        apkFile.path,
        type: 'application/vnd.android.package-archive',
      );
      if (result.type == ResultType.done) {
        return const ApkInstallResult(launched: true);
      }
      return ApkInstallResult(
        launched: false,
        message: result.message.isNotEmpty
            ? result.message
            : 'Could not launch package installer.',
      );
    } catch (e) {
      return ApkInstallResult(
        launched: false,
        message: 'Install failed: $e',
      );
    }
  }
}
