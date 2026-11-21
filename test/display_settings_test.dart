import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worship_chat/features/settings/providers/chat_bubble_settings_provider.dart';
import 'package:worship_chat/features/settings/screens/display_settings_screen.dart';
import 'package:worship_chat/features/settings/screens/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ChatBubbleSettings Provider & Model Tests', () {
    test('Default transparency is 0.70 and opacity is 0.30', () {
      const settings = ChatBubbleSettings();
      expect(settings.transparency, 0.70);
      expect((settings.opacity - 0.30).abs() < 0.001, isTrue);
    });

    test('computeAlpha returns exact default base alpha when transparency is 0.70', () {
      const settings = ChatBubbleSettings(transparency: 0.70);
      final alphaMyMessage = settings.computeAlpha(0.26);
      expect((alphaMyMessage - 0.26).abs() < 0.001, isTrue);

      final alphaSender = settings.computeAlpha(0.18);
      expect((alphaSender - 0.18).abs() < 0.001, isTrue);
    });

    test('computeAlpha scales up to maxAlpha when transparency is 0.0 (solid)', () {
      const settings = ChatBubbleSettings(transparency: 0.0);
      expect(settings.opacity, 1.0);
      final alphaSolid = settings.computeAlpha(0.26, maxAlpha: 0.95);
      expect((alphaSolid - 0.95).abs() < 0.001, isTrue);
    });

    test('computeAlpha scales down to minAlpha when transparency is 1.0 (ultra glass)', () {
      const settings = ChatBubbleSettings(transparency: 1.0);
      expect(settings.opacity, 0.0);
      final alphaGlass = settings.computeAlpha(0.26, minAlpha: 0.02);
      expect((alphaGlass - 0.02).abs() < 0.001, isTrue);
    });

    test('Solid received bubble gradient is comfortable dark slate-violet, NOT glaring white', () {
      const solidSettings = ChatBubbleSettings(transparency: 0.0);
      final colors = solidSettings.getBubbleGradientColors(isMe: false);
      expect(colors.length, 3);

      // Verify each stop is dark (luminance < 0.2), never bright white
      for (final color in colors) {
        expect(color.computeLuminance() < 0.2, isTrue,
            reason: 'Color $color should have dark comfortable luminance');
      }

      // Check effective background color on dark backdrop
      final effectiveBg = solidSettings.getBubbleEffectiveBackgroundColor(
        isMe: false,
        backdropColor: const Color(0xFF0A0A0F),
      );
      expect(effectiveBg.computeLuminance() < 0.15, isTrue);
    });

    test('Solid sent bubble gradient is rich jewel-toned magenta/purple, NOT electric neon', () {
      const solidSettings = ChatBubbleSettings(transparency: 0.0);
      final colors = solidSettings.getBubbleGradientColors(isMe: true);
      expect(colors.length, 3);

      // Verify sent colors have rich deep tone (comfortable luminance between 0.05 and 0.25)
      for (final color in colors) {
        expect(color.computeLuminance() < 0.30, isTrue);
      }
    });

    test('At 26% transparency, bubble colors remain translucent jewel/obsidian tones, never chalky grey', () {
      const settings26 = ChatBubbleSettings(transparency: 0.26);
      final receivedColors = settings26.getBubbleGradientColors(isMe: false);
      expect(receivedColors.length, 3);

      for (final color in receivedColors) {
        // Must be dark obsidian tones, never chalky grey
        expect(color.computeLuminance() < 0.20, isTrue);
        // Alpha must be comfortably translucent (< 0.60), not prematurely solid
        expect(color.a < 0.60, isTrue);
        expect(color.a > 0.45, isTrue);
      }

      final sentColors = settings26.getBubbleGradientColors(isMe: true);
      expect(sentColors.length, 3);
      for (final color in sentColors) {
        expect(color.computeLuminance() < 0.25, isTrue);
        expect(color.a < 0.60, isTrue);
        expect(color.a > 0.45, isTrue);
      }
    });

    test('getTextContrast dynamically adapts font color based on background', () {
      // 1. Dark background -> light text
      final darkContrast = ChatBubbleSettings.contrastForBackground(const Color(0xFF100E1A));
      expect(darkContrast.isLightBackground, isFalse);
      expect(darkContrast.primaryTextColor, Colors.white);
      expect(darkContrast.statusIconColor, Colors.white70);

      // 2. Bright/light background -> dark text
      final lightContrast = ChatBubbleSettings.contrastForBackground(const Color(0xFFF7F5FA));
      expect(lightContrast.isLightBackground, isTrue);
      expect(lightContrast.primaryTextColor, const Color(0xFF14131D));
      expect(lightContrast.statusIconColor, const Color(0xFF454256));
    });

    test('ChatBubbleSettingsNotifier sets and clamps transparency value', () async {
      final notifier = ChatBubbleSettingsNotifier();

      await notifier.setTransparency(0.40);
      expect((notifier.state.transparency - 0.40).abs() < 0.001, isTrue);

      // Clamp above 1.0
      await notifier.setTransparency(1.5);
      expect(notifier.state.transparency, 1.0);

      // Clamp below 0.0
      await notifier.setTransparency(-0.5);
      expect(notifier.state.transparency, 0.0);

      // Reset to default
      await notifier.resetToDefault();
      expect(notifier.state.transparency, ChatBubbleSettings.defaultTransparency);
    });
  });

  group('DisplaySettingsScreen Widget Tests', () {
    testWidgets('DisplaySettingsScreen renders header, preview, slider, presets and backdrop toggle', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: DisplaySettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Display Settings'), findsOneWidget);
      expect(find.text('LIVE BUBBLE PREVIEW'), findsOneWidget);
      expect(find.text('Dark Backdrop'), findsOneWidget);
      expect(find.text('CHAT BUBBLE TRANSPARENCY'), findsOneWidget);
      expect(find.text('Transparency Level'), findsOneWidget);
      expect(find.text('70%'), findsNWidgets(2)); // Badge and preset label
      expect(find.byType(Slider), findsOneWidget);

      // Presets
      expect(find.text('Solid'), findsOneWidget);
      expect(find.text('Tinted'), findsOneWidget);
      expect(find.text('Default'), findsOneWidget);
      expect(find.text('Glass'), findsOneWidget);

      // Reset button
      expect(find.text('Reset to Default (70%)'), findsOneWidget);
    });

    testWidgets('Tapping a preset updates the slider transparency value and percentage pill', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: DisplaySettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap on 'Solid' (0%) preset
      await tester.ensureVisible(find.text('Solid'));
      await tester.tap(find.text('Solid'));
      await tester.pumpAndSettle();

      expect(find.text('0%'), findsNWidgets(2)); // Badge and preset percent
      expect(find.textContaining('Solid Level'), findsOneWidget);

      // Tap on 'Glass' (90%) preset
      await tester.ensureVisible(find.text('Glass'));
      await tester.tap(find.text('Glass'));
      await tester.pumpAndSettle();

      expect(find.text('90%'), findsNWidgets(2));
      expect(find.textContaining('Ultra Glass'), findsOneWidget);

      // Tap Reset
      await tester.ensureVisible(find.text('Reset to Default (70%)'));
      await tester.tap(find.text('Reset to Default (70%)'));
      await tester.pumpAndSettle();

      expect(find.text('70%'), findsNWidgets(2));
    });

    testWidgets('Tapping backdrop toggle switches between Dark Backdrop and Light Backdrop', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: DisplaySettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Dark Backdrop'), findsOneWidget);

      // Tap toggle to switch to Light Backdrop
      await tester.tap(find.text('Dark Backdrop'));
      await tester.pumpAndSettle();

      expect(find.text('Light Backdrop'), findsOneWidget);

      // Tap toggle back to Dark Backdrop
      await tester.tap(find.text('Light Backdrop'));
      await tester.pumpAndSettle();

      expect(find.text('Dark Backdrop'), findsOneWidget);
    });
  });

  group('SettingsScreen Widget Tests', () {
    testWidgets('SettingsScreen renders Display Settings option and navigates to DisplaySettingsScreen', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Display Settings'), findsOneWidget);
      expect(find.text('Chat bubble transparency, slider & preview'), findsOneWidget);

      // Tap Display Settings tile
      await tester.tap(find.text('Display Settings'));
      await tester.pumpAndSettle();

      // Verify navigation to DisplaySettingsScreen
      expect(find.byType(DisplaySettingsScreen), findsOneWidget);
      expect(find.text('LIVE BUBBLE PREVIEW'), findsOneWidget);
    });
  });
}
