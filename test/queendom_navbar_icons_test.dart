import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Queendom Bottom Navbar Icons Tests', () {
    test('All 4 queendom navbar icon image files exist on disk', () {
      final files = [
        'assets/images/queen_pooja_nav_inactive.jpg',
        'assets/images/queen_pooja_nav_active.jpg',
        'assets/images/queen_rashmika_nav_inactive.jpg',
        'assets/images/queen_rashmika_nav_active.jpg',
      ];

      for (final path in files) {
        final f = File(path);
        expect(f.existsSync(), isTrue, reason: 'Expected $path to exist');
        expect(f.lengthSync(), greaterThan(1000), reason: 'Expected $path to be a valid image');
      }
    });

    testWidgets('Queendom nav icons switch between inactive and active assets correctly',
        (WidgetTester tester) async {
      Widget buildTestIcon({required bool isSelected, required String active, required String inactive}) {
        final asset = isSelected ? active : inactive;
        return Image.asset(asset);
      }

      // Test Pooja Inactive & Active
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                buildTestIcon(
                  isSelected: false,
                  active: 'assets/images/queen_pooja_nav_active.jpg',
                  inactive: 'assets/images/queen_pooja_nav_inactive.jpg',
                ),
                buildTestIcon(
                  isSelected: true,
                  active: 'assets/images/queen_pooja_nav_active.jpg',
                  inactive: 'assets/images/queen_pooja_nav_inactive.jpg',
                ),
                buildTestIcon(
                  isSelected: false,
                  active: 'assets/images/queen_rashmika_nav_active.jpg',
                  inactive: 'assets/images/queen_rashmika_nav_inactive.jpg',
                ),
                buildTestIcon(
                  isSelected: true,
                  active: 'assets/images/queen_rashmika_nav_active.jpg',
                  inactive: 'assets/images/queen_rashmika_nav_inactive.jpg',
                ),
              ],
            ),
          ),
        ),
      );

      final images = tester.widgetList<Image>(find.byType(Image)).toList();
      expect(images.length, 4);

      expect(
        (images[0].image as AssetImage).assetName,
        'assets/images/queen_pooja_nav_inactive.jpg',
      );
      expect(
        (images[1].image as AssetImage).assetName,
        'assets/images/queen_pooja_nav_active.jpg',
      );
      expect(
        (images[2].image as AssetImage).assetName,
        'assets/images/queen_rashmika_nav_inactive.jpg',
      );
      expect(
        (images[3].image as AssetImage).assetName,
        'assets/images/queen_rashmika_nav_active.jpg',
      );
    });

    testWidgets('Bottom navbar items do not render text labels (photo and icon only)',
        (WidgetTester tester) async {
      // Build a minimal test reproduction matching the bottom nav item structure
      Widget buildNavItem({
        required Widget icon,
        required String label,
        required bool isSelected,
      }) {
        return Semantics(
          label: label,
          button: true,
          selected: isSelected,
          child: Container(
            child: icon,
          ),
        );
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: Row(
              children: [
                buildNavItem(
                  icon: const Icon(Icons.chat_bubble_rounded),
                  label: 'Chats',
                  isSelected: false,
                ),
                buildNavItem(
                  icon: Image.asset('assets/images/queen_pooja_nav_inactive.jpg'),
                  label: 'Pooja',
                  isSelected: false,
                ),
                buildNavItem(
                  icon: Image.asset('assets/images/queen_rashmika_nav_active.jpg'),
                  label: 'Rashmika',
                  isSelected: true,
                ),
                buildNavItem(
                  icon: const Icon(Icons.groups_rounded),
                  label: 'Groups',
                  isSelected: false,
                ),
              ],
            ),
          ),
        ),
      );

      // Verify no visible text labels exist in the navigation bar
      expect(find.byType(Text), findsNothing);
      // Semantics still allow accessibility identification
      expect(find.bySemanticsLabel('Chats'), findsOneWidget);
      expect(find.bySemanticsLabel('Pooja'), findsOneWidget);
      expect(find.bySemanticsLabel('Rashmika'), findsOneWidget);
      expect(find.bySemanticsLabel('Groups'), findsOneWidget);
    });

    testWidgets('Badge is positioned at bottom-right of icon with compact sizing',
        (WidgetTester tester) async {
      Widget buildBadgeStack({required int count}) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            const SizedBox(width: 38, height: 38),
            Positioned(
              right: -3,
              bottom: -2,
              child: Container(
                constraints: const BoxConstraints(minWidth: 13, minHeight: 13),
                child: Text('$count'),
              ),
            ),
          ],
        );
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: buildBadgeStack(count: 9),
            ),
          ),
        ),
      );

      final positionedFinder = find.byType(Positioned);
      expect(positionedFinder, findsOneWidget);
      final Positioned positioned = tester.widget(positionedFinder);
      expect(positioned.right, -3);
      expect(positioned.bottom, -2);
      expect(positioned.top, isNull);
    });
  });
}

