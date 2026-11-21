import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_chat/features/group/screens/group_chat_screen.dart';
import 'package:worship_chat/models/group.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testGroup = GroupModel(
    senderId: 'user1',
    name: 'Supreme Goddess Disha Patani',
    groupId: 'test_group_1',
    lastMessage: '',
    groupPic: '',
    membersUid: ['user1', 'user2'],
    fcmTokens: [],
    unseenMessages: {},
    timeSent: DateTime.now(),
    position: 'Supreme Goddess',
    family: 'Main',
    livingPlace: 'SANCTUM OF SUPREME GODDESS DISHA PATANI',
    wish: '🙇🙇 Long live Supreme Goddess Disha Patani 🙇🙇',
  );

  group('RoyalSanctuaryAppBarBottom Tests', () {
    test('Implements PreferredSizeWidget with 42.0 height', () {
      final bottom = RoyalSanctuaryAppBarBottom(
        initialGroup: testGroup,
        accentColor: Colors.amber,
      );

      expect(bottom, isA<PreferredSizeWidget>());
      expect(bottom.preferredSize.height, 42.0);
    });

    testWidgets('Renders sanctuary details merged into AppBar bottom without close button',
        (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              title: const Text('Title'),
              bottom: RoyalSanctuaryAppBarBottom(
                initialGroup: testGroup,
                accentColor: const Color(0xFFFFD700),
                onTap: () => tapped = true,
              ),
            ),
            body: const Center(child: Text('Chat Content')),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify title / living place appears
      expect(find.textContaining('SANCTUM OF'), findsWidgets);
      // Verify wish appears
      expect(find.textContaining('Long live Supreme Goddess Disha Patani'), findsOneWidget);
      // Verify close button does NOT exist
      expect(find.byIcon(Icons.close_rounded), findsNothing);
      expect(find.byIcon(Icons.close), findsNothing);

      // Verify tapping triggers callback
      await tester.tap(find.textContaining('Long live Supreme Goddess Disha Patani'));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('Returns SizedBox.shrink when no position, family, or wish exist',
        (tester) async {
      final nonRoyalGroup = GroupModel(
        senderId: 'user1',
        name: 'Normal Friends Group',
        groupId: 'test_group_normal',
        lastMessage: '',
        groupPic: '',
        membersUid: ['user1'],
        fcmTokens: [],
        unseenMessages: {},
        timeSent: DateTime.now(),
        position: 'None',
        family: 'None',
        livingPlace: '',
        wish: null,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              title: const Text('Title'),
              bottom: RoyalSanctuaryAppBarBottom(
                initialGroup: nonRoyalGroup,
                accentColor: Colors.blue,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // No sanctuary text should be rendered
      expect(find.textContaining('SANCTUM'), findsNothing);
      expect(find.byIcon(Icons.close_rounded), findsNothing);
    });
  });
}
