# Worship Chat

Worship Chat shares one account and gallery across phones, tablets, macOS, and
Windows.

| Device | Gallery | Chat | Chat notifications |
| --- | --- | --- | --- |
| Android phone / iPhone | Yes | Yes | Yes |
| Android tablet / iPad | Yes | No | No |
| macOS / Windows | Yes | No | No |

Tablets are identified from the device itself before Firebase messaging starts.
On iOS this uses the iPad device idiom. On Android this uses the full display's
shortest side (600 logical pixels or more), so opening the app in a small
split-screen window does not enable chat. Desktop window size does not enable
chat either. Gallery-only devices do not request notification permission or
register chat messaging tokens.

## Development

```sh
flutter pub get
flutter test
```

Build on the target platform:

```sh
# On macOS (Xcode and CocoaPods required)
flutter build macos
flutter build ios --no-codesign

# On Windows (Visual Studio C++ desktop tooling required)
flutter build windows

# Android phones and tablets
flutter build apk
```

Apple targets require macOS 10.15 or later and iOS/iPadOS 15.5 or later; the
existing ML Kit dependencies set the iOS minimum. The iOS target supports both
iPhone and iPad. For local macOS builds and non-App Store runs, App Sandbox is
disabled in debug/release entitlements to allow direct, unprompted macOS Keychain
access for Firebase Auth without requiring a paid Apple Developer provisioning profile.
If publishing to the Mac App Store in the future, re-enable App Sandbox and configure
Keychain Sharing with an Apple Developer Team in Xcode.

The existing ML Kit binaries support x86_64 simulators and ARM64 physical Apple
devices. The iOS configurations keep their simulator ARM64 exclusion after
Flutter-generated settings, including Profile through the Release configuration.
Apple Silicon iOS 26+ simulators require ARM64, so use a physical iPad/iPhone or a
compatible simulator for runtime checks with this dependency set.

## Firebase configuration

The Android configuration and all platform options use the existing
`worship-chat-c60b5` Firebase project. Apple targets use the registered bundle ID
`com.shadow.worshipchat.worshipChat`; their matching `GoogleService-Info.plist`
files are included in the Xcode targets. Windows uses an existing Windows Firebase
app registration in the same project. Both authentication and gallery data remain
in the phone app's project.

Messaging auto-initialization is disabled in Android and iOS native configuration.
The app enables it only after identifying a phone. If the Firebase project or
bundle identifiers change, regenerate the matching configurations with the
FlutterFire CLI and update the native configuration files.

Firebase currently documents Windows plugins for development workflows, so
validate authentication and Firestore on the intended Windows distribution before
shipping. See the [Firebase Flutter setup guide](https://firebase.google.com/docs/flutter/setup).

## Validation

- `flutter analyze`: no errors or warnings.
- `flutter test`: 170 tests passed.
- Android debug APK: built successfully.
- macOS debug app: built with local Apple development signing, verified with
  `codesign --verify --deep --strict`, and launched successfully.
- iOS debug simulator app: built successfully for x86_64.
- Windows native compilation requires a Windows host and has not been verified in
  this workspace.
