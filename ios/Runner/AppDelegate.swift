import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var deviceChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      deviceChannel = FlutterMethodChannel(
        name: "worship_chat/device",
        binaryMessenger: controller.binaryMessenger
      )
      deviceChannel?.setMethodCallHandler { call, result in
        switch call.method {
        case "isTablet":
          result(UIDevice.current.userInterfaceIdiom == .pad)
        case "disableNotifications":
          if UIDevice.current.userInterfaceIdiom == .pad {
            self.disableNotifications()
            result(true)
          } else {
            result(false)
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    if UIDevice.current.userInterfaceIdiom == .pad {
      // Run after launch observers, including plugins that register with APNS.
      DispatchQueue.main.async { self.disableNotifications() }
    }
    return launched
  }

  private func disableNotifications() {
    UIApplication.shared.unregisterForRemoteNotifications()
    UIApplication.shared.applicationIconBadgeNumber = 0
    let center = UNUserNotificationCenter.current()
    center.removeAllDeliveredNotifications()
    center.removeAllPendingNotificationRequests()
  }
}
