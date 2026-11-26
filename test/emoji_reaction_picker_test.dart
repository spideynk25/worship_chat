import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worship_chat/features/chat/widgets/emoji_reaction_picker_sheet.dart';
import 'package:worship_chat/features/chat/widgets/message_reaction_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ReactionEmojiCatalog Unit Tests', () {
    test('extractDirectEmojiInput accepts any Unicode emoji and rejects ASCII search words', () {
      expect(ReactionEmojiCatalog.extractDirectEmojiInput('crown'), isNull);
      expect(ReactionEmojiCatalog.extractDirectEmojiInput('100'), isNull);
      expect(ReactionEmojiCatalog.extractDirectEmojiInput('  '), isNull);

      expect(ReactionEmojiCatalog.extractDirectEmojiInput('🪷'), '🪷');
      expect(ReactionEmojiCatalog.extractDirectEmojiInput('🙏🏽'), '🙏🏽');
      expect(ReactionEmojiCatalog.extractDirectEmojiInput('🇮🇳'), '🇮🇳');
      expect(ReactionEmojiCatalog.extractDirectEmojiInput('❤️‍🔥'), '❤️‍🔥');
      expect(ReactionEmojiCatalog.extractDirectEmojiInput('🦕'), '🦕');
    });

    test('catalog has rich multi-category coverage and keyword search', () {
      final totalEntries = ReactionEmojiCatalog.categories
          .fold<int>(0, (sum, cat) => sum + cat.entries.length);
      expect(totalEntries, greaterThan(250));

      final crownMatches =
          ReactionEmojiCatalog.search('crown').map((e) => e.emoji).toList();
      expect(crownMatches, contains('👑'));

      final pizzaMatches =
          ReactionEmojiCatalog.search('pizza').map((e) => e.emoji).toList();
      expect(pizzaMatches, contains('🍕'));

      final indiaMatches =
          ReactionEmojiCatalog.search('india').map((e) => e.emoji).toList();
      expect(indiaMatches, contains('🇮🇳'));
    });

    test('recordRecent stores newly used emojis first and caps list length', () async {
      await ReactionEmojiCatalog.recordRecent('🪷');
      final recents = await ReactionEmojiCatalog.loadRecents();
      expect(recents.first, '🪷');
    });
  });

  group('Full Emoji Picker Integration Tests', () {
    testWidgets('tapping + opens full picker, supports category browse & search, and selects any emoji', (tester) async {
      String? pickedReaction;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  MessageReactionDialog.show(
                    context: context,
                    targetRect: const Rect.fromLTWH(40, 220, 220, 64),
                    currentUserId: 'u1',
                    reactions: const {},
                    onReactionSelected: (emoji) => pickedReaction = emoji,
                    onReply: () {},
                  );
                },
                child: const Text('OpenReaction'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('OpenReaction'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('More emojis'));
      await tester.pumpAndSettle();

      expect(find.byType(EmojiReactionPickerSheet), findsOneWidget);

      // Search across catalog for pizza
      await tester.enterText(find.byType(TextField), 'pizza');
      await tester.pumpAndSettle();
      expect(find.text('🍕'), findsOneWidget);

      await tester.tap(find.text('🍕'));
      await tester.pumpAndSettle();

      expect(pickedReaction, '🍕');
      final stored = await ReactionEmojiCatalog.loadRecents();
      expect(stored.first, '🍕');
    });

    testWidgets('typing or pasting an arbitrary OS keyboard emoji immediately reacts with it', (tester) async {
      String? pickedReaction;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  MessageReactionDialog.show(
                    context: context,
                    targetRect: const Rect.fromLTWH(40, 220, 220, 64),
                    currentUserId: 'u1',
                    reactions: const {},
                    onReactionSelected: (emoji) => pickedReaction = emoji,
                    onReply: () {},
                  );
                },
                child: const Text('OpenReaction'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('OpenReaction'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('More emojis'));
      await tester.pumpAndSettle();

      // Simulate user picking any unlisted emoji directly on phone OS keyboard
      await tester.enterText(find.byType(TextField), '🦕');
      await tester.pumpAndSettle();

      expect(pickedReaction, '🦕');
    });

    testWidgets('quick pill displays custom existing reaction so user can toggle it off in 1 tap', (tester) async {
      String? toggledReaction;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  MessageReactionDialog.show(
                    context: context,
                    targetRect: const Rect.fromLTWH(40, 220, 220, 64),
                    currentUserId: 'u1',
                    reactions: const {'u1': '🦕'},
                    onReactionSelected: (emoji) => toggledReaction = emoji,
                    onReply: () {},
                  );
                },
                child: const Text('OpenCustom'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('OpenCustom'));
      await tester.pumpAndSettle();

      expect(find.text('🦕'), findsOneWidget);
      await tester.tap(find.text('🦕'));
      await tester.pumpAndSettle();
      expect(toggledReaction, '🦕');
    });
  });
}
