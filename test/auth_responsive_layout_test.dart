import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:worship_chat/features/auth/screens/forget_password_screen.dart';
import 'package:worship_chat/features/auth/screens/login_screen.dart';
import 'package:worship_chat/features/auth/screens/register_screen.dart';
import 'package:worship_chat/features/auth/screens/user_information_screen.dart';
import 'package:worship_chat/features/home/screens/profile_screen.dart';
import 'package:worship_chat/models/user_model.dart';

void main() {
  late Directory hiveDirectory;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('auth_layout_test_');
    Hive.init(hiveDirectory.path);
    await Hive.openBox<UserModel>('userBox');
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  final screens = <String, (Widget, Finder)>{
    'Login': (
      const LoginScreen(),
      find.widgetWithText(ElevatedButton, 'Login'),
    ),
    'Registration': (
      const RegisterScreen(),
      find.widgetWithText(ElevatedButton, 'Register'),
    ),
    'Password reset': (
      const ForgetPasswordScreen(),
      find.widgetWithText(ElevatedButton, 'Send Reset Link'),
    ),
    'User information': (
      const UserInformationScreen(),
      find.widgetWithIcon(IconButton, Icons.done),
    ),
    'Profile': (
      const ProfileScreen(),
      find.widgetWithText(ElevatedButton, 'Update Profile'),
    ),
  };

  for (final screen in screens.entries) {
    testWidgets(
      '${screen.key} fits desktop, resized windows and tablet keyboard',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1280, 800);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpWidget(
          ProviderScope(child: MaterialApp(home: screen.value.$1)),
        );
        await tester.pumpAndSettle();

        for (final field in find.byType(TextField).evaluate()) {
          expect(
            tester.getSize(find.byWidget(field.widget)).width,
            lessThanOrEqualTo(480),
          );
        }
        expect(tester.takeException(), isNull);

        tester.view.physicalSize = const Size(320, 240);
        await tester.pumpAndSettle();
        await tester.ensureVisible(screen.value.$2);
        await tester.pumpAndSettle();
        expect(screen.value.$2.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);

        tester.view.physicalSize = const Size(1024, 600);
        tester.view.viewInsets = const FakeViewPadding(bottom: 240);
        await tester.pumpAndSettle();
        await tester.ensureVisible(screen.value.$2);
        await tester.pumpAndSettle();
        expect(screen.value.$2.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
