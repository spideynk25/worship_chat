import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_chat/features/group/utils/queendom_emblem_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final expectedFamilies = [
    'Aura',
    'Core',
    'Main',
    'Eternal',
    'Divine',
    'Wicked',
    'Lustra',
    'Rumia',
    'Erotica',
    'Elegant',
    'Elora',
    'Zyra',
    'Velisse',
  ];

  group('Queendom Family Emblem Asset Files on Disk', () {
    test('all 13 family crest PNG files exist on disk with valid size', () {

      for (final family in expectedFamilies) {
        final assetPath = QueendomFamilyEmblemHelper.getAsset(family);
        expect(assetPath, isNotNull, reason: 'Family $family should have an asset path');

        final file = File(assetPath!);
        expect(file.existsSync(), isTrue, reason: 'Asset file $assetPath should exist on disk');

        final bytes = file.lengthSync();
        expect(bytes, greaterThan(10000), reason: 'Asset file $assetPath should have content (>10KB)');
      }
    });
  });

  group('QueendomFamilyEmblemHelper Unit Tests', () {
    test('returns correct asset for every family name', () {
      for (final family in expectedFamilies) {
        final asset = QueendomFamilyEmblemHelper.getAsset(family);
        expect(asset, equals('assets/emojis/family_${family.toLowerCase()}.png'));
      }
    });

    test('supports case-insensitive lookup and whitespace trimming', () {
      expect(
        QueendomFamilyEmblemHelper.getAsset('  aura  '),
        equals('assets/emojis/family_aura.png'),
      );
      expect(
        QueendomFamilyEmblemHelper.getAsset('DIVINE'),
        equals('assets/emojis/family_divine.png'),
      );
      expect(
        QueendomFamilyEmblemHelper.getAsset('elora'),
        equals('assets/emojis/family_elora.png'),
      );
    });

    test('returns null for None, empty, or unknown family', () {
      expect(QueendomFamilyEmblemHelper.getAsset(null), isNull);
      expect(QueendomFamilyEmblemHelper.getAsset(''), isNull);
      expect(QueendomFamilyEmblemHelper.getAsset('None'), isNull);
      expect(QueendomFamilyEmblemHelper.getAsset('NonExistentFamily'), isNull);
    });
  });

  group('QueendomFamilyEmblemWidget Widget Tests', () {
    testWidgets('renders Image.asset for valid family', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: QueendomFamilyEmblemWidget(
              family: 'Elora',
              size: 20.0,
            ),
          ),
        ),
      );

      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('renders fallback or SizedBox for null/None family', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: QueendomFamilyEmblemWidget(
              family: 'None',
              size: 20.0,
              fallback: Text('No Family'),
            ),
          ),
        ),
      );

      expect(find.text('No Family'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });
  });
}
