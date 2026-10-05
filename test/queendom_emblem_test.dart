import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_chat/features/group/utils/queendom_emblem_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Queendom Emblem Helper & Asset Tests', () {
    final expectedEmblems = [
      'aura_elixiria',
      'core_supreme',
      'supreme_goddess',
      'golden_blossom',
      'goddess',
      'demi_goddess',
      'dark_angel',
      'queen',
      'elfwitch',
      'enchantress',
      'first_born_princess',
      'second_born_princess',
      'third_born_princess',
    ];

    test('All 13 custom emblem PNG files exist on disk with valid size', () {
      for (final name in expectedEmblems) {
        final file = File('assets/emojis/$name.png');
        expect(file.existsSync(), isTrue, reason: 'Missing assets/emojis/$name.png');
        expect(file.lengthSync(), greaterThan(1000), reason: '$name.png is too small or empty');
      }
    });

    test('getAsset returns correct asset for every queendom position', () {
      expect(
        QueendomEmblemHelper.getAsset(position: 'First Born Princess'),
        equals('assets/emojis/first_born_princess.png'),
      );
      expect(
        QueendomEmblemHelper.getAsset(position: 'Aura Elixiria'),
        equals('assets/emojis/aura_elixiria.png'),
      );
      expect(
        QueendomEmblemHelper.getAsset(position: 'Goddess'),
        equals('assets/emojis/goddess.png'),
      );
      expect(
        QueendomEmblemHelper.getAsset(position: 'Queen'),
        equals('assets/emojis/queen.png'),
      );
      expect(
        QueendomEmblemHelper.getAsset(position: 'Enchantress'),
        equals('assets/emojis/enchantress.png'),
      );
    });

    test('getAsset returns correct asset for every Unicode emoji', () {
      expect(
        QueendomEmblemHelper.getAsset(emoji: '🌺'),
        equals('assets/emojis/first_born_princess.png'),
      );
      expect(
        QueendomEmblemHelper.getAsset(emoji: '☀️'),
        equals('assets/emojis/aura_elixiria.png'),
      );
      expect(
        QueendomEmblemHelper.getAsset(emoji: '🌟'),
        equals('assets/emojis/core_supreme.png'),
      );
      expect(
        QueendomEmblemHelper.getAsset(emoji: '🏮'),
        equals('assets/emojis/supreme_goddess.png'),
      );
      expect(
        QueendomEmblemHelper.getAsset(emoji: '🍀'),
        equals('assets/emojis/enchantress.png'),
      );
    });

    test('getAssetFromLivingPlace finds emblem from formatted sanctuary title', () {
      const title = 'PALACE OF 🌺 FIRST BORN PRINCESS KRITHIKA';
      expect(
        QueendomEmblemHelper.getAssetFromLivingPlace(title),
        equals('assets/emojis/first_born_princess.png'),
      );
    });

    testWidgets('buildRichTitle renders RichText with WidgetSpan for matching title',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QueendomEmblemHelper.buildRichTitle(
              title: 'PALACE OF 🌺 FIRST BORN PRINCESS KRITHIKA',
              style: const TextStyle(fontSize: 14, color: Colors.white),
            ),
          ),
        ),
      );

      expect(find.byType(RichText), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('buildRichTitle falls back to plain Text for titles without emojis',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QueendomEmblemHelper.buildRichTitle(
              title: 'GENERAL CHAT ROOM',
              style: const TextStyle(fontSize: 14, color: Colors.white),
            ),
          ),
        ),
      );

      expect(find.text('GENERAL CHAT ROOM'), findsOneWidget);
    });

    testWidgets('buildRichTitle renders queen crown for FORTRESS OF 👑 QUEEN POOJA HEGDE',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QueendomEmblemHelper.buildRichTitle(
              title: 'FORTRESS OF 👑 QUEEN POOJA HEGDE',
              style: const TextStyle(fontSize: 14, color: Colors.white),
            ),
          ),
        ),
      );

      expect(find.byType(RichText), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      final imageWidget = tester.widget<Image>(find.byType(Image));
      final assetImage = imageWidget.image as AssetImage;
      expect(assetImage.assetName, equals('assets/emojis/queen.png'));
    });

    test('cleanTitle strips old emojis from title', () {
      expect(
        QueendomEmblemHelper.cleanTitle('FORTRESS OF 👑 QUEEN POOJA HEGDE'),
        equals('FORTRESS OF QUEEN POOJA HEGDE'),
      );
    });

    testWidgets('QueendomEmblemWidget renders without errors', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: QueendomEmblemWidget(
              position: 'First Born Princess',
              size: 32,
            ),
          ),
        ),
      );

      expect(find.byType(QueendomEmblemWidget), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('buildRichTitle renders RichText with inline leadingPosition emblem',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QueendomEmblemHelper.buildRichTitle(
              title: 'Supreme Divine Goddess Taapsee',
              leadingPosition: 'Supreme Goddess',
              style: const TextStyle(fontSize: 15, color: Colors.white),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      );

      expect(find.byType(RichText), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      final imageWidget = tester.widget<Image>(find.byType(Image));
      final assetImage = imageWidget.image as AssetImage;
      expect(assetImage.assetName, equals('assets/emojis/supreme_goddess.png'));
    });

    testWidgets(
        'buildRichTitle renders position crown and places family emblem at end of title',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QueendomEmblemHelper.buildRichTitle(
              title: 'SANCTUM OF 🏮 SUPREME GODDESS DISHA PATANI',
              family: 'Main',
              style: const TextStyle(fontSize: 14, color: Colors.white),
            ),
          ),
        ),
      );

      expect(find.byType(RichText), findsOneWidget);
      expect(find.byType(Image), findsNWidgets(2));

      final images = tester.widgetList<Image>(find.byType(Image)).toList();
      final crownAsset = images[0].image as AssetImage;
      final familyAsset = images[1].image as AssetImage;

      expect(crownAsset.assetName, equals('assets/emojis/supreme_goddess.png'));
      expect(familyAsset.assetName, equals('assets/emojis/family_main.png'));
    });

    testWidgets(
        'buildRichTitle renders Aura family emblem at end of title when family is Aura',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QueendomEmblemHelper.buildRichTitle(
              title: 'SANCTUM OF 🏮 SUPREME GODDESS DISHA PATANI',
              family: 'Aura',
              style: const TextStyle(fontSize: 14, color: Colors.white),
            ),
          ),
        ),
      );

      expect(find.byType(Image), findsNWidgets(2));
      final images = tester.widgetList<Image>(find.byType(Image)).toList();
      final crownAsset = images[0].image as AssetImage;
      final familyAsset = images[1].image as AssetImage;

      expect(crownAsset.assetName, equals('assets/emojis/supreme_goddess.png'));
      expect(familyAsset.assetName, equals('assets/emojis/family_aura.png'));
    });

    testWidgets(
        'buildRichTitle falls back to Main family emblem when fallbackFamily is provided',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QueendomEmblemHelper.buildRichTitle(
              title: 'SANCTUM OF 🏮 SUPREME GODDESS DISHA PATANI',
              family: null,
              fallbackFamily: 'Main',
              style: const TextStyle(fontSize: 14, color: Colors.white),
            ),
          ),
        ),
      );

      expect(find.byType(Image), findsNWidgets(2));
      final images = tester.widgetList<Image>(find.byType(Image)).toList();
      expect((images[0].image as AssetImage).assetName,
          equals('assets/emojis/supreme_goddess.png'));
      expect((images[1].image as AssetImage).assetName,
          equals('assets/emojis/family_main.png'));
    });
  });
}
