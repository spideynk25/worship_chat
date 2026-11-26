import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_chat/features/group/widgets/queen_pooja_queendom_list.dart';
import 'package:worship_chat/features/group/widgets/queendom_search_view.dart';
import 'package:worship_chat/models/group.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('QueendomGroupCard Tests', () {
    final testGroup = GroupModel(
      senderId: 'user1',
      name: 'Pooja Hegde',
      groupId: 'grp_pooja_1',
      lastMessage: 'All Hail Queen Pooja',
      groupPic: '',
      membersUid: ['user1'],
      timeSent: DateTime.now(),
      fcmTokens: [],
      unseenMessages: const {},
      position: 'Supreme Goddess',
      family: 'Main',
      livingPlace: 'SANCTUM OF SUPREME GODDESS POOJA',
    );

    testWidgets('QueendomGroupCard shows position badge when showPositionBadge is true', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: QueendomGroupCard(
                group: testGroup,
                accentColor: const Color(0xFFF59E0B),
                hasUnseen: false,
                showPositionBadge: true,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.text('Supreme Goddess'), findsOneWidget);
    });

    testWidgets('QueendomGroupCard hides position badge when showPositionBadge is false', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: QueendomGroupCard(
                group: testGroup,
                accentColor: const Color(0xFFF59E0B),
                hasUnseen: false,
                showPositionBadge: false,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.text('Supreme Goddess'), findsNothing);
    });

    testWidgets('QueendomGroupCard displays matchedSubGroupInfo banner when provided', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: QueendomGroupCard(
                group: testGroup,
                accentColor: const Color(0xFFF59E0B),
                hasUnseen: false,
                showPositionBadge: false,
                matchedSubGroupInfo: 'Sub-group match: "Golden Crown Ritual"',
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.text('Sub-group match: "Golden Crown Ritual"'), findsOneWidget);
    });
  });

  group('QueendomSearchView Tests', () {
    final rashmikaParent = GroupModel(
      senderId: 'user1',
      name: 'Rashmika Mandanna',
      groupId: 'grp_rashmika_1',
      lastMessage: 'Crown of Radiance',
      groupPic: '',
      membersUid: ['user1'],
      timeSent: DateTime.now(),
      fcmTokens: [],
      unseenMessages: const {},
      position: 'Core Supreme Goddess',
      family: 'Main',
      livingPlace: 'PALACE OF QUEEN RASHMIKA',
    );

    final rashmikaSubGroup = GroupModel(
      senderId: 'user1',
      name: 'Rashmika Lotus Chambers',
      groupId: 'sub_rashmika_1',
      parentGroupId: 'grp_rashmika_1',
      lastMessage: 'Lotus prayer',
      groupPic: '',
      membersUid: ['user1'],
      timeSent: DateTime.now(),
      fcmTokens: [],
      unseenMessages: const {},
      position: 'Core Supreme Goddess',
      family: 'Main',
      livingPlace: 'PALACE OF QUEEN RASHMIKA',
      isSubGroup: true,
      subGroupType: 'Morning Worship',
    );

    final auraGoddessGroup = GroupModel(
      senderId: 'user1',
      name: 'Solar Aurelia',
      groupId: 'grp_aura_1',
      lastMessage: 'Golden dawn',
      groupPic: '',
      membersUid: ['user1'],
      timeSent: DateTime.now(),
      fcmTokens: [],
      unseenMessages: const {},
      position: 'Aura Elixiria',
      family: 'Royal Scent',
      livingPlace: 'SUN SHINE TEMPLE',
    );

    final testGroups = [rashmikaParent, rashmikaSubGroup, auraGoddessGroup];

    testWidgets('QueendomSearchView renders categories and filters, but NO Explore Realm headline or tags', (tester) async {
      bool closed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QueendomSearchView(
              realmName: 'Queen Rashmika',
              realmThemeColor: const Color(0xFFFF2D78),
              allGroups: testGroups,
              onClose: () => closed = true,
              cardBuilder: (context, group, accentColor, hasUnseen, subGroups, matchedSubGroupInfo) {
                return Text('CARD: ${group.name}');
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Top search hint uses "mistresses"
      expect(find.text('Search Queen Rashmika mistresses, sanctums…'), findsOneWidget);

      // Top category carousel and filter row ARE present
      expect(find.text('All Mistresses'), findsOneWidget);
      expect(find.text('Aura Elixiria Goddesses'), findsOneWidget);
      expect(find.text('Filters:'), findsOneWidget);
      expect(find.text('Has Unseen'), findsOneWidget);
      expect(find.text('With Sub-groups'), findsOneWidget);

      // Status bar uses "mistresses"
      expect(find.textContaining('mistresses found'), findsOneWidget);

      // Verify "Explore Queen Rashmika's Realm" text is REMOVED
      expect(find.textContaining("Explore Queen Rashmika's Realm"), findsNothing);
      expect(find.textContaining("Explore Queen Pooja's Realm"), findsNothing);

      // Verify close button calls onClose
      final backButton = find.byIcon(Icons.arrow_back_ios_new_rounded);
      expect(backButton, findsOneWidget);
      await tester.tap(backButton);
      expect(closed, isTrue);
    });

    testWidgets('QueendomSearchView category carousel filters mistresses', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QueendomSearchView(
              realmName: 'Queen Rashmika',
              realmThemeColor: const Color(0xFFFF2D78),
              allGroups: testGroups,
              onClose: () {},
              cardBuilder: (context, group, accentColor, hasUnseen, subGroups, matchedSubGroupInfo) {
                return Text('CARD: ${group.name}');
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Both initially visible in All Mistresses
      expect(find.text('CARD: Rashmika Mandanna'), findsOneWidget);
      expect(find.text('CARD: Solar Aurelia'), findsOneWidget);

      // Tap "Aura Elixiria Goddesses" category chip
      await tester.tap(find.text('Aura Elixiria Goddesses'));
      await tester.pumpAndSettle();

      // Only Aura mistress visible
      expect(find.text('CARD: Solar Aurelia'), findsOneWidget);
      expect(find.text('CARD: Rashmika Mandanna'), findsNothing);
    });

    testWidgets('QueendomSearchView filters mistresses by text query', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QueendomSearchView(
              realmName: 'Queen Rashmika',
              realmThemeColor: const Color(0xFFFF2D78),
              allGroups: testGroups,
              onClose: () {},
              cardBuilder: (context, group, accentColor, hasUnseen, subGroups, matchedSubGroupInfo) {
                return Text('CARD: ${group.name}');
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Search for Solar
      await tester.enterText(find.byType(TextField), 'Solar');
      await tester.pumpAndSettle();

      expect(find.text('CARD: Rashmika Mandanna'), findsNothing);
      expect(find.text('CARD: Solar Aurelia'), findsOneWidget);
      expect(find.textContaining('1 mistress found'), findsOneWidget);
    });

    testWidgets('QueendomSearchView matches sub-groups and returns parent with matched info', (tester) async {
      String? receivedMatchedInfo;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QueendomSearchView(
              realmName: 'Queen Rashmika',
              realmThemeColor: const Color(0xFFFF2D78),
              allGroups: testGroups,
              onClose: () {},
              cardBuilder: (context, group, accentColor, hasUnseen, subGroups, matchedSubGroupInfo) {
                receivedMatchedInfo = matchedSubGroupInfo;
                return Text('CARD: ${group.name}');
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Search for the sub-group name "Chambers"
      await tester.enterText(find.byType(TextField), 'Chambers');
      await tester.pumpAndSettle();

      // The parent group should be rendered
      expect(find.text('CARD: Rashmika Mandanna'), findsOneWidget);
      expect(find.text('CARD: Solar Aurelia'), findsNothing);

      // And it should have received the sub-group matched info
      expect(receivedMatchedInfo, contains('Rashmika Lotus Chambers'));
    });

    testWidgets('QueendomSearchView displays empty state with mistresses terminology when query yields no results', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QueendomSearchView(
              realmName: 'Queen Rashmika',
              realmThemeColor: const Color(0xFFFF2D78),
              allGroups: testGroups,
              onClose: () {},
              cardBuilder: (context, group, accentColor, hasUnseen, subGroups, matchedSubGroupInfo) {
                return Text('CARD: ${group.name}');
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Nonexistent Mistress 9999');
      await tester.pumpAndSettle();

      expect(find.text('No Mistresses Found in Queen Rashmika'), findsOneWidget);
      expect(find.text('Clear Query'), findsOneWidget);

      // Tapping "Clear Query" restores the query
      await tester.tap(find.text('Clear Query'));
      await tester.pumpAndSettle();

      expect(find.text('CARD: Rashmika Mandanna'), findsOneWidget);
    });
  });
}
