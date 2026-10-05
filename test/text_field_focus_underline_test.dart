import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_chat/features/auth/screens/forget_password_screen.dart';
import 'package:worship_chat/features/auth/screens/login_screen.dart';
import 'package:worship_chat/features/auth/screens/register_screen.dart';
import 'package:worship_chat/features/auth/screens/user_information_screen.dart';
import 'package:worship_chat/main.dart';

void main() {
  group('Text Field Focus Underline Removal Tests', () {
    test('Global theme inputDecorationTheme has no underline border', () {
      final inputTheme = MyApp.theme.inputDecorationTheme;

      expect(inputTheme.focusedBorder, equals(InputBorder.none));
      expect(inputTheme.enabledBorder, equals(InputBorder.none));
      expect(inputTheme.border, equals(InputBorder.none));
      expect(inputTheme.focusedBorder is UnderlineInputBorder, isFalse);
      expect(inputTheme.enabledBorder is UnderlineInputBorder, isFalse);
    });

    testWidgets('LoginScreen text fields have no focus or enabled underlines',
        (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: LoginScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final textFields = tester.widgetList<TextField>(
        find.byType(TextField),
      );
      expect(textFields.length, equals(2)); // Email & Password

      for (final field in textFields) {
        final decoration = field.decoration!;
        expect(decoration.focusedBorder is UnderlineInputBorder, isFalse);
        expect(decoration.enabledBorder is UnderlineInputBorder, isFalse);

        if (decoration.focusedBorder != null) {
          expect(decoration.focusedBorder!.borderSide.style, equals(BorderStyle.none));
        }
        if (decoration.enabledBorder != null) {
          expect(decoration.enabledBorder!.borderSide.style, equals(BorderStyle.none));
        }
      }

      // Tap email field to request focus
      await tester.tap(find.byType(TextField).first);
      await tester.pump();

      // Ensure no UnderlineInputBorder exists in the widget tree
      expect(find.byType(UnderlineInputBorder), findsNothing);
    });

    testWidgets('RegisterScreen text fields have no focus or enabled underlines',
        (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: RegisterScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final textFields = tester.widgetList<TextField>(
        find.byType(TextField),
      );
      expect(textFields.length, equals(5)); // Name, Username, Email, Password, Confirm Password

      for (final field in textFields) {
        final decoration = field.decoration!;
        expect(decoration.focusedBorder is UnderlineInputBorder, isFalse);
        expect(decoration.enabledBorder is UnderlineInputBorder, isFalse);

        if (decoration.focusedBorder != null) {
          expect(decoration.focusedBorder!.borderSide.style, equals(BorderStyle.none));
        }
        if (decoration.enabledBorder != null) {
          expect(decoration.enabledBorder!.borderSide.style, equals(BorderStyle.none));
        }
      }
    });

    testWidgets('ForgetPasswordScreen text field has no focus underline',
        (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: ForgetPasswordScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byType(TextField));
      final decoration = field.decoration!;
      expect(decoration.focusedBorder is UnderlineInputBorder, isFalse);
      expect(decoration.enabledBorder is UnderlineInputBorder, isFalse);
      expect(decoration.focusedBorder!.borderSide.style, equals(BorderStyle.none));
      expect(decoration.enabledBorder!.borderSide.style, equals(BorderStyle.none));
    });

    testWidgets('UserInformationScreen text field has InputBorder.none',
        (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: UserInformationScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byType(TextField));
      final decoration = field.decoration!;
      expect(decoration.focusedBorder, equals(InputBorder.none));
      expect(decoration.enabledBorder, equals(InputBorder.none));
      expect(decoration.border, equals(InputBorder.none));
    });
  });
}
