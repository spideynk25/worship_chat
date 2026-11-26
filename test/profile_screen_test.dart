import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:worship_chat/features/auth/controller/auth_controller.dart';
import 'package:worship_chat/features/auth/repository/auth_repository.dart';
import 'package:worship_chat/features/home/screens/profile_screen.dart';
import 'package:worship_chat/features/settings/screens/settings_screen.dart';
import 'package:worship_chat/models/user_model.dart';

class _FakeAuthController implements AuthController {
  bool saveResult = true;
  int saveCalls = 0;
  bool? lastNavigateHomeOnComplete;
  bool? lastRemoveProfilePic;
  String? lastSavedName;
  String? lastSavedUserName;
  String? resetPasswordEmail;
  int logoutCalls = 0;

  @override
  Future<bool> saveUserDatatoFirebase(
    BuildContext context,
    String name,
    File? profilePic, {
    String? userName,
    String? profilePicUrlOverride,
    bool navigateHomeOnComplete = true,
    bool removeProfilePic = false,
  }) async {
    saveCalls++;
    lastSavedName = name;
    lastSavedUserName = userName;
    lastNavigateHomeOnComplete = navigateHomeOnComplete;
    lastRemoveProfilePic = removeProfilePic;
    return saveResult;
  }

  @override
  Future<bool> updateCurrentUserProfilePic({
    BuildContext? context,
    File? imageFile,
    String? imageUrl,
  }) async =>
      saveResult;

  @override
  void resetPassword(BuildContext context, String email) {
    resetPasswordEmail = email;
  }

  @override
  void logout(BuildContext context) {
    logoutCalls++;
  }

  @override
  AuthRepository get authRepository => throw UnimplementedError();

  @override
  Future<UserModel?> getUsetData() async => null;

  @override
  Future<void> loginWithEmail(
    BuildContext context,
    String email,
    String password,
  ) async {}

  @override
  Ref<Object?> get ref => throw UnimplementedError();

  @override
  Future<void> registerWithEmail(
    BuildContext context,
    String name,
    String userName,
    String email,
    String password,
  ) async {}

  @override
  void setUserState(bool isOnline) {}

  @override
  Stream<UserModel> userDataById(String userId) => const Stream.empty();
}

void main() {
  late Directory hiveDirectory;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('profile_ui_test_');
    Hive.init(hiveDirectory.path);
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(UserModelAdapter());
    }
    await Hive.openBox<UserModel>('userBox');
  });

  tearDownAll(() async {
    await Hive.close();
    if (hiveDirectory.existsSync()) {
      await hiveDirectory.delete(recursive: true);
    }
  });

  setUp(() async {
    final box = Hive.box<UserModel>('userBox');
    await box.clear();
    await box.put(
      'currentUser',
      UserModel(
        uid: 'u1',
        name: 'Royal Devotee',
        userName: 'royal_bhakt',
        email: 'devotee@example.com',
        profilePic: 'https://example.com/avatar.jpg',
        isOnline: true,
        groupId: const ['g1', 'g2'],
      ),
    );
  });

  testWidgets('ProfileScreen displays hero details, inline username check, and discard', (tester) async {
    final fakeAuth = _FakeAuthController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authControllerProvider.overrideWithValue(fakeAuth)],
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Royal Devotee'), findsWidgets);
    expect(find.text('@royal_bhakt'), findsOneWidget);
    expect(find.text('Active'), findsNothing);
    expect(find.text('2 Groups'), findsNothing);
    expect(find.text('Tap photo to change'), findsNothing);
    expect(find.text('IDENTITY DETAILS'), findsOneWidget);
    expect(find.text('Reset Password'), findsOneWidget);
    expect(find.text('ACCOUNT'), findsOneWidget);
    expect(find.text('Sign Out'), findsOneWidget);

    // Spaces in username trigger inline badge and block backend save
    final usernameField = find.widgetWithText(TextField, 'royal_bhakt');
    await tester.enterText(usernameField, 'bad handle');
    await tester.pumpAndSettle();
    expect(find.text('No spaces'), findsOneWidget);

    await tester.ensureVisible(find.text('Update Profile'));
    await tester.tap(find.text('Update Profile'));
    await tester.pumpAndSettle();
    expect(fakeAuth.saveCalls, 0);

    // Discard reverts field cleanly back to initial state
    await tester.ensureVisible(find.text('Discard'));
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('No spaces'), findsNothing);
    expect(find.text('You have unsaved profile changes'), findsNothing);
  });

  testWidgets('Smooth save keeps user on Profile and clears unsaved indicator', (tester) async {
    final fakeAuth = _FakeAuthController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authControllerProvider.overrideWithValue(fakeAuth)],
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Royal Devotee'),
      'Imperial Servant',
    );
    await tester.pumpAndSettle();
    expect(find.text('You have unsaved profile changes'), findsOneWidget);

    await tester.ensureVisible(find.text('Update Profile'));
    await tester.tap(find.text('Update Profile'));
    await tester.pumpAndSettle();

    expect(fakeAuth.saveCalls, 1);
    expect(fakeAuth.lastSavedName, 'Imperial Servant');
    expect(fakeAuth.lastSavedUserName, 'royal_bhakt');
    expect(fakeAuth.lastNavigateHomeOnComplete, isFalse);
    expect(fakeAuth.lastRemoveProfilePic, isFalse);
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(find.text('You have unsaved profile changes'), findsNothing);
  });

  testWidgets('Tapping avatar shows Profile Photo sheet and Remove Photo updates save flag', (tester) async {
    final fakeAuth = _FakeAuthController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authControllerProvider.overrideWithValue(fakeAuth)],
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.camera_alt_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Profile Photo'), findsOneWidget);
    expect(find.text('View Photo'), findsOneWidget);
    expect(find.text('Choose from Gallery'), findsOneWidget);
    expect(find.text('Remove Photo'), findsOneWidget);

    await tester.tap(find.text('Remove Photo'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Update Profile'));
    await tester.tap(find.text('Update Profile'));
    await tester.pumpAndSettle();

    expect(fakeAuth.saveCalls, 1);
    expect(fakeAuth.lastRemoveProfilePic, isTrue);
  });

  testWidgets('ProfileScreen confirms password reset, sign out, and navigates to SettingsScreen', (tester) async {
    final fakeAuth = _FakeAuthController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authControllerProvider.overrideWithValue(fakeAuth)],
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Reset Password sits inside the ACCOUNT section right above Sign Out
    expect(
      tester.getTopLeft(find.text('Reset Password')).dy,
      greaterThan(tester.getTopLeft(find.text('ACCOUNT')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Reset Password')).dy,
      lessThan(tester.getTopLeft(find.text('Sign Out')).dy),
    );

    // Password reset confirmation
    await tester.ensureVisible(find.text('Reset Password'));
    await tester.tap(find.text('Reset Password'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send Link'));
    await tester.pumpAndSettle();
    expect(fakeAuth.resetPasswordEmail, 'devotee@example.com');

    // Sign out confirmation
    await tester.ensureVisible(find.text('Sign Out'));
    await tester.tap(find.text('Sign Out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Sign Out'));
    await tester.pumpAndSettle();
    expect(fakeAuth.logoutCalls, 1);

    // AppBar Settings navigation
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
  });
}
