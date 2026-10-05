import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_chat/features/group/utils/queendom_emblem_helper.dart';
import 'package:worship_chat/features/group/widgets/royal_avatar_decoration.dart';

void main() {
  group('RoyalAvatarDecoration Widget Tests', () {
    testWidgets(
        'renders rotating stardust dots vortex and forms unified Queen crown',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: RoyalAvatarDecoration(
                position: 'Queen',
                avatarRadius: 50,
                child: CircleAvatar(
                  radius: 50,
                  child: Text('QP'),
                ),
              ),
            ),
          ),
        ),
      );

      // Verify child avatar is present
      expect(find.byType(CircleAvatar), findsOneWidget);
      expect(find.text('QP'), findsOneWidget);

      // Swirling stardust dots vortex custom painter is present
      expect(find.byType(CustomPaint), findsWidgets);

      // Crown asset is pre-mounted and ready
      expect(find.byType(Image), findsOneWidget);
      final crownImage = tester.widget<Image>(find.byType(Image).first);
      final assetImage = crownImage.image as AssetImage;
      expect(assetImage.assetName, equals('assets/emojis/queen.png'));

      // Pump 2.6 seconds into the forged crown hover phase (t = 0.50 of 5.2s loop)
      await tester.pump(const Duration(milliseconds: 2600));
      // Unified crown is forged and visible
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('renders floatAndBreathe style correctly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: RoyalAvatarDecoration(
                position: 'Queen',
                avatarRadius: 50,
                animationStyle: RoyalCrownAnimationStyle.floatAndBreathe,
                child: CircleAvatar(
                  radius: 50,
                  child: Text('FB'),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(Image), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(RoyalAvatarDecoration), findsOneWidget);
    });

    testWidgets('gracefully renders without crown when position is null',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: RoyalAvatarDecoration(
                position: null,
                avatarRadius: 50,
                child: CircleAvatar(
                  radius: 50,
                  child: Text('No Crown'),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('No Crown'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('renders badge and responds to tap', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: RoyalAvatarDecoration(
                position: 'First Born Princess',
                avatarRadius: 40,
                badge: const Icon(Icons.zoom_in),
                onTap: () => tapped = true,
                child: const CircleAvatar(radius: 40),
              ),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.zoom_in), findsOneWidget);

      await tester.tap(find.byType(RoyalAvatarDecoration));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('perches crown outside avatar clip box and renders emblem badge',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: RoyalAvatarDecoration(
                position: 'Queen',
                avatarRadius: 50,
                perchOutside: true,
                badge: Container(
                  key: const ValueKey('emblem_badge'),
                  child: const Text('👑'),
                ),
                child: const CircleAvatar(radius: 50),
              ),
            ),
          ),
        ),
      );

      // Verify the badge is rendered
      expect(find.byKey(const ValueKey('emblem_badge')), findsOneWidget);

      // Crown image is present and positioned outside
      expect(find.byType(Image), findsOneWidget);

      // Find the Positioned widget holding the crown
      final positionedWidgets =
          tester.widgetList<Positioned>(find.byType(Positioned));
      // One of the Positioned widgets should have a negative top offset outside the clip box
      final crownPositioned =
          positionedWidgets.firstWhere((p) => p.top != null);
      // For avatarRadius 50, diameter 100, crownSize 62, 8.0 - 62 * 0.85 = -44.7
      expect(crownPositioned.top!, lessThan(-40.0));
    });

    testWidgets('QueendomEmblemHelper.buildEmblemBadge builds glowing badge with overlay',
        (tester) async {
      final badge = QueendomEmblemHelper.buildEmblemBadge(
        position: 'Aura Elixiria Goddess',
        accentColor: const Color(0xFFFFD700),
        size: 16.0,
        overlayWidget: Container(
          key: const ValueKey('unread_indicator'),
          width: 8,
          height: 8,
        ),
      );

      expect(badge, isNotNull);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: RoyalAvatarDecoration(
                position: 'Aura Elixiria Goddess',
                avatarRadius: 28,
                accentColor: const Color(0xFFFFD700),
                badge: badge,
                badgeBottomOffset: 0,
                badgeRightOffset: 0,
                child: const CircleAvatar(radius: 28),
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('unread_indicator')), findsOneWidget);
      // Both crown and badge images rendered
      expect(find.byType(Image), findsWidgets);
    });

    testWidgets('QueendomFamilyEmblemHelper.buildFamilyEmblemBadge builds family crest badge',
        (tester) async {
      final badge = QueendomFamilyEmblemHelper.buildFamilyEmblemBadge(
        family: 'Aura',
        accentColor: const Color(0xFFFFD700),
        size: 16.0,
        overlayWidget: Container(
          key: const ValueKey('unread_family_dot'),
          width: 8,
          height: 8,
        ),
      );

      expect(badge, isNotNull);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: RoyalAvatarDecoration(
                position: 'Aura Elixiria Goddess',
                avatarRadius: 28,
                accentColor: const Color(0xFFFFD700),
                badge: badge,
                badgeBottomOffset: 0,
                badgeRightOffset: 0,
                child: const CircleAvatar(radius: 28),
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('unread_family_dot')), findsOneWidget);
      expect(find.byType(Image), findsWidgets);
    });
  });
}

