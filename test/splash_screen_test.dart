import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_chat/splash_screen.dart';

void main() {
  group('SplashScreen UI & Lifecycle Tests', () {
    testWidgets('SplashScreen mounts and renders branding and title smoothly',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SplashScreen(),
        ),
      );

      // Verify Title exists and tagline is removed
      expect(find.text('Worship Chat'), findsOneWidget);
      expect(find.text('Connect • Share • Inspire'), findsNothing);

      // Verify bottom branding exists
      expect(find.text('from'), findsOneWidget);
      expect(find.text('WORSHIP'), findsOneWidget);

      // Advance animation frames
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Worship Chat'), findsOneWidget);
    });

    testWidgets('SplashScreen handles image fallback without crashing',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SplashScreen(),
        ),
      );

      // Ensure no exceptions occur during full animation cycle
      await tester.pump(const Duration(milliseconds: 750));
      await tester.pump(const Duration(milliseconds: 1000));

      expect(find.byType(SplashScreen), findsOneWidget);
    });
  });
}

