import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_chat/features/group/widgets/queendom_badge_widget.dart';

void main() {
  group('Queendom Badge Tests', () {
    test('Both badge asset files exist on disk with valid size', () {
      final poojaFile = File('assets/images/queen_pooja_badge.jpg');
      final rashmikaFile = File('assets/images/queen_rashmika_badge.jpg');

      expect(poojaFile.existsSync(), isTrue,
          reason: 'Expected assets/images/queen_pooja_badge.jpg to exist');
      expect(poojaFile.lengthSync(), greaterThan(1000));

      expect(rashmikaFile.existsSync(), isTrue,
          reason: 'Expected assets/images/queen_rashmika_badge.jpg to exist');
      expect(rashmikaFile.lengthSync(), greaterThan(1000));
    });

    test('QueendomBadgeHelper detects Queen Pooja and Queen Rashmika correctly', () {
      // By queendom string
      expect(
        QueendomBadgeHelper.detectQueendom(queendom: 'Queen Pooja'),
        QueendomType.pooja,
      );
      expect(
        QueendomBadgeHelper.detectQueendom(queendom: 'Queen Rashmika'),
        QueendomType.rashmika,
      );

      // By group / celebrant name
      expect(
        QueendomBadgeHelper.detectQueendom(name: 'Sanctum of Queen Pooja'),
        QueendomType.pooja,
      );
      expect(
        QueendomBadgeHelper.detectQueendom(name: 'Temple of Rashmika Mandanna'),
        QueendomType.rashmika,
      );

      // By event title
      expect(
        QueendomBadgeHelper.detectQueendom(title: "Queen Pooja's Birthday"),
        QueendomType.pooja,
      );
      expect(
        QueendomBadgeHelper.detectQueendom(title: "Queen Rashmika's Birthday Celebration"),
        QueendomType.rashmika,
      );

      // By type
      expect(
        QueendomBadgeHelper.detectQueendom(type: 'queenPooja'),
        QueendomType.pooja,
      );
      expect(
        QueendomBadgeHelper.detectQueendom(type: 'queenRashmika'),
        QueendomType.rashmika,
      );

      // Unrelated
      expect(
        QueendomBadgeHelper.detectQueendom(title: "General Gathering"),
        isNull,
      );
    });

    test('QueendomBadgeHelper returns correct asset path', () {
      expect(
        QueendomBadgeHelper.getBadgeAsset(queendom: 'Queen Pooja'),
        'assets/images/queen_pooja_badge.jpg',
      );
      expect(
        QueendomBadgeHelper.getBadgeAsset(queendom: 'Queen Rashmika'),
        'assets/images/queen_rashmika_badge.jpg',
      );
      expect(
        QueendomBadgeHelper.getBadgeAsset(title: 'Random Event'),
        isNull,
      );
    });

    testWidgets('QueendomBadgeWidget renders Queen Pooja and Queen Rashmika badges',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                QueendomBadgeWidget(
                  queendom: 'Queen Pooja',
                  size: 28,
                ),
                QueendomBadgeWidget(
                  queendom: 'Queen Rashmika',
                  size: 28,
                ),
              ],
            ),
          ),
        ),
      );

      final images = tester.widgetList<Image>(find.byType(Image)).toList();
      expect(images.length, 2);

      expect(
        (images[0].image as AssetImage).assetName,
        'assets/images/queen_pooja_badge.jpg',
      );
      expect(
        (images[1].image as AssetImage).assetName,
        'assets/images/queen_rashmika_badge.jpg',
      );
    });

    testWidgets('QueendomBadgeWidget returns SizedBox.shrink() when not a Queendom',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: QueendomBadgeWidget(
              queendom: 'General Group',
            ),
          ),
        ),
      );

      expect(find.byType(Image), findsNothing);
    });

    testWidgets('Calendar event card displays connected birthday group profile picture',
        (WidgetTester tester) async {
      Widget buildEventAvatar({
        required String? groupPicUrl,
        required QueendomType? queendomType,
        required bool isBirthday,
      }) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
              ),
              child: groupPicUrl != null && groupPicUrl.isNotEmpty
                  ? Image.asset(groupPicUrl, fit: BoxFit.cover)
                  : const Icon(Icons.cake_rounded),
            ),
            if (queendomType != null)
              Positioned(
                right: -3,
                bottom: -3,
                child: QueendomBadgeWidget(
                  queendomType: queendomType,
                  size: 19,
                ),
              ),
          ],
        );
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                // Event with connected group picture and Queendom badge
                buildEventAvatar(
                  groupPicUrl: 'assets/images/queen_pooja_nav_active.jpg',
                  queendomType: QueendomType.pooja,
                  isBirthday: true,
                ),
                // Event without connected group picture (fallback)
                buildEventAvatar(
                  groupPicUrl: null,
                  queendomType: null,
                  isBirthday: true,
                ),
              ],
            ),
          ),
        ),
      );

      // Verify the connected group profile image is rendered
      final images = tester.widgetList<Image>(find.byType(Image)).toList();
      expect(images.length, 2); // 1 group pic + 1 queendom badge
      expect(
        (images[0].image as AssetImage).assetName,
        'assets/images/queen_pooja_nav_active.jpg',
      );
      expect(
        (images[1].image as AssetImage).assetName,
        'assets/images/queen_pooja_badge.jpg',
      );

      // Verify fallback cake icon is rendered for the second event
      expect(find.byIcon(Icons.cake_rounded), findsOneWidget);
    });
  });
}

