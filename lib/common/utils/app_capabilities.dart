import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device capabilities are resolved before Firebase or notification startup.
/// Window resizing and tablet split-screen affect layout, not chat availability.
class AppCapabilities {
  const AppCapabilities({
    required this.platform,
    required this.isTablet,
    this.isWeb = false,
  });

  final TargetPlatform platform;
  final bool isTablet;
  final bool isWeb;

  bool get isDesktop =>
      !isWeb &&
      (platform == TargetPlatform.macOS ||
          platform == TargetPlatform.windows ||
          platform == TargetPlatform.linux);

  bool get chatEnabled =>
      !isWeb &&
      !isTablet &&
      (platform == TargetPlatform.android || platform == TargetPlatform.iOS);

  bool get notificationsEnabled => chatEnabled;

  static const _deviceChannel = MethodChannel('worship_chat/device');
  static const _phonePreference = 'phone_chat_enabled';
  static AppCapabilities? _resolved;
  static AppCapabilities? _debugOverride;

  // Unknown devices never start chat services or request notification permission.
  static AppCapabilities get current =>
      _debugOverride ??
      _resolved ??
      AppCapabilities(
        platform: defaultTargetPlatform,
        isTablet: true,
        isWeb: kIsWeb,
      );

  @visibleForTesting
  static set debugOverride(AppCapabilities? value) => _debugOverride = value;

  @visibleForTesting
  static void resetForTests() {
    _resolved = null;
    _debugOverride = null;
  }

  static Future<void> initialize({bool background = false}) async {
    if (_resolved != null || _debugOverride != null) return;
    final platform = defaultTargetPlatform;
    final mobile =
        !kIsWeb &&
        (platform == TargetPlatform.android || platform == TargetPlatform.iOS);
    if (!mobile) {
      _resolved = AppCapabilities(
        platform: platform,
        isTablet: false,
        isWeb: kIsWeb,
      );
      return;
    }

    bool isTablet = true;
    SharedPreferences? preferences;
    try {
      preferences = await SharedPreferences.getInstance();
      if (background) {
        // Background isolates have no activity/controller to identify the device.
        await preferences.reload();
        isTablet = !(preferences.getBool(_phonePreference) ?? false);
      }
    } catch (error) {
      debugPrint('Unable to read device capabilities: $error');
    }

    if (!background) {
      try {
        isTablet = await _deviceChannel.invokeMethod<bool>('isTablet') ?? true;
      } on MissingPluginException {
        isTablet = _tabletFromDisplay();
      } on PlatformException {
        isTablet = _tabletFromDisplay();
      }
      if (isTablet) {
        try {
          // Native Apple messaging registers at launch even with auto-init off.
          // Remove that registration and any notifications from older installs.
          await _deviceChannel.invokeMethod<void>('disableNotifications');
        } on MissingPluginException {
          // Older runners still use the Dart policy and installation cleanup.
        } on PlatformException catch (error) {
          debugPrint('Unable to disable native notifications: $error');
        }
      }
      try {
        await preferences?.setBool(_phonePreference, !isTablet);
      } catch (error) {
        debugPrint('Unable to persist device capabilities: $error');
      }
    }

    _resolved = AppCapabilities(platform: platform, isTablet: isTablet);
  }

  static bool _tabletFromDisplay() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return true;
    final display = views.first.display;
    final ratio = display.devicePixelRatio;
    if (ratio <= 0 || display.size.isEmpty) return true;
    return display.size.shortestSide / ratio >= 600;
  }
}
