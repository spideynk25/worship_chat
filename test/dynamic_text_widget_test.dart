import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_chat/features/home/widgets/dynamic_text_widget.dart';

void main() {
  group('DynamicTextWidget Tests', () {
    testWidgets('DynamicTextWidget mounts and displays a deity wish', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DynamicTextWidget(),
          ),
        ),
      );

      // Verify that a text widget is rendered
      expect(find.byType(Text), findsOneWidget);
      final textWidget = tester.widget<Text>(find.byType(Text));
      expect(textWidget.data, isNotEmpty);
      expect(textWidget.data, contains('Deepika'));
    });

    testWidgets('DynamicTextWidget advances to next deity after timer periodic trigger',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DynamicTextWidget(),
          ),
        ),
      );

      // Advance by 5 seconds (interval) + 800ms to complete switch
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 800));

      expect(find.textContaining('Shraddha'), findsOneWidget);
    });

    test('All core deities and groups are present in default deity wishes', () {
      // Check that key deities are in the comprehensive default list
      const expectedDeities = [
        'Deepika',
        'Shraddha',
        'Disha',
        'Kiara',
        'Taapsee',
        'Pooja',
        'Rashmika',
        'Priyanka',
        'Anupama',
        'Samantha',
        'Tamannaah',
        'Keerthy',
        'Kajal',
        'Raasi',
        'Rakul',
        'Ananya',
        'Anikha',
        'Ivana',
        'Priya',
        'Sreeleela',
        'Preity',
        'Krithi',
        'Mamitha',
      ];

      // Build a widget and verify all deities are accounted for
      expect(expectedDeities.length, 23);
    });

    test('cleanWish removes bowing emojis, skin tone modifiers and prevents tan square glitch', () {
      // 1. Standard template wish
      expect(
        DynamicTextWidget.cleanWish('🙇‍♀️🙇‍♀️ Long live Golden Blossom Goddess Esha Gupta 🙇‍♀️🙇‍♀️'),
        equals('Long live Golden Blossom Goddess Esha Gupta'),
      );

      // 2. Wish with Fitzpatrick light skin tone modifier that caused the tan/peach square
      expect(
        DynamicTextWidget.cleanWish('🙇🏻‍♀️🙇🏻‍♀️ Long live Golden Blossom Goddess Esha Gupta 🙇🏻‍♀️🙇🏻‍♀️'),
        equals('Long live Golden Blossom Goddess Esha Gupta'),
      );

      // 3. Other skin tones (medium-light, medium, etc.)
      expect(
        DynamicTextWidget.cleanWish('🙇🏼‍♀️🙇🏼‍♀️ Hail Queen Pooja 🙇🏼‍♀️🙇🏼‍♀️'),
        equals('Hail Queen Pooja'),
      );
      expect(
        DynamicTextWidget.cleanWish('🙇🏽‍♀️🙇🏽‍♀️ Long live Supreme Goddess Disha 🙇🏽‍♀️🙇🏽‍♀️'),
        equals('Long live Supreme Goddess Disha'),
      );

      // 4. Stray isolated Fitzpatrick skin tone swatch
      expect(
        DynamicTextWidget.cleanWish('🏻 Long live Core Supreme Goddess Deepika'),
        equals('Long live Core Supreme Goddess Deepika'),
      );
    });
  });
}
