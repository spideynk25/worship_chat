import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_chat/features/group/controller/group_controller.dart';
import 'package:worship_chat/features/group/utils/group_template_helper.dart';
import 'package:worship_chat/features/group/widgets/queen_pooja_queendom_list.dart';
import 'package:worship_chat/features/group/widgets/queen_rashmika_queendom_list.dart';
import 'package:worship_chat/models/group.dart';

class _FakeGroupController extends Fake implements GroupController {
  final List<Map<String, dynamic>> sentMessages = [];
  final StreamController<List<GroupModel>> rashmikaStream =
      StreamController<List<GroupModel>>.broadcast();
  final StreamController<List<GroupModel>> poojaStream =
      StreamController<List<GroupModel>>.broadcast();

  @override
  List<GroupModel> getCachedGroups(String boxKey) => [];

  @override
  Stream<List<GroupModel>> getQueenRashmikaStream() => rashmikaStream.stream;

  @override
  Stream<List<GroupModel>> getQueenPoojaStream() => poojaStream.stream;

  @override
  Future<void> sendTextMessage(
    BuildContext context,
    String text,
    String groupId,
    String messageType,
    dynamic file,
    List<String> fcmToken,
    List<String> receiverIds,
    String groupName,
    String type, {
    String? mediaGroupId,
    dynamic messageReplyOverride,
    bool clearReply = false,
  }) async {
    sentMessages.add({
      'text': text,
      'groupId': groupId,
      'messageType': messageType,
      'fcmToken': fcmToken,
      'receiverIds': receiverIds,
      'groupName': groupName,
      'type': type,
      'clearReply': clearReply,
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Category Wish Button & Batch Wishing Tests', () {
    late _FakeGroupController fakeController;

    setUp(() {
      fakeController = _FakeGroupController();
    });

    final testGroup1 = GroupModel(
      senderId: 'user1',
      name: 'Rashmika Mandanna',
      groupId: 'grp_rashmika_1',
      lastMessage: 'Devotion active',
      groupPic: '',
      membersUid: ['user1', 'user2'],
      timeSent: DateTime.now(),
      fcmTokens: ['token_1'],
      unseenMessages: const {},
      position: 'Aura Elixiria',
      family: 'Aura',
      priority: 1,
      wish: '🙇‍♀️🙇‍♀️ Have Mercy on us Aura Elixiria Goddess Rashmika 🙇‍♀️🙇‍♀️',
    );

    final testGroup2 = GroupModel(
      senderId: 'user1',
      name: 'Pooja Hegde',
      groupId: 'grp_pooja_1',
      lastMessage: 'All Hail Goddess',
      groupPic: '',
      membersUid: ['user1'],
      timeSent: DateTime.now(),
      fcmTokens: ['token_2'],
      unseenMessages: const {},
      position: 'Aura Elixiria',
      family: 'Aura',
      priority: 2,
      wish: null, // Will test template generation fallback
    );

    test('Wish resolution prioritizes group.wish and falls back to template', () {
      // 1. Explicit wish on group doc
      expect(
        testGroup1.wish,
        equals('🙇‍♀️🙇‍♀️ Have Mercy on us Aura Elixiria Goddess Rashmika 🙇‍♀️🙇‍♀️'),
      );

      // 2. Fallback to GroupTemplateHelper when wish is null
      final generated = GroupTemplateHelper.generateTemplate(
        position: testGroup2.position ?? '',
        name: testGroup2.name,
        family: testGroup2.family ?? '',
      );
      expect(
        generated.wish,
        contains('Aura Elixiria Goddess Pooja Hegde'),
      );
    });

    testWidgets('QueenRashmikaQueendomList renders wish button and sends wishes on confirmation',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            groupControllerProvider.overrideWithValue(fakeController),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: QueenRashmikaQueendomList(),
            ),
          ),
        ),
      );

      // Emit groups to the stream
      fakeController.rashmikaStream.add([testGroup1, testGroup2]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify category title and mistress count
      expect(find.text('Aura Elixiria Goddesses'), findsOneWidget);
      expect(find.text('2 mistresses'), findsOneWidget);

      // Verify the wish button (tooltip and devotee emoji)
      final wishTooltipFinder = find.byTooltip('Wish all Aura Elixiria Goddesses');
      expect(wishTooltipFinder, findsOneWidget);
      expect(find.text('🙇🏻‍♂️'), findsOneWidget);

      // Tap the wish button
      await tester.tap(wishTooltipFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify confirmation dialog appeared
      expect(find.text('Wish All Aura Elixiria Goddesses?'), findsOneWidget);
      expect(
        find.text('Send royal devotion wishes to all 2 mistresses in Aura Elixiria Goddesses?'),
        findsOneWidget,
      );

      // Confirm wishing
      final confirmBtnFinder = find.widgetWithText(ElevatedButton, 'Wish All 🙇🏻‍♂️');
      expect(confirmBtnFinder, findsOneWidget);
      await tester.tap(confirmBtnFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Verify wishes were sent to all groups in category with messageType 'wish' and clearReply: true
      expect(fakeController.sentMessages.length, equals(2));
      expect(fakeController.sentMessages[0]['groupId'], equals('grp_rashmika_1'));
      expect(fakeController.sentMessages[0]['messageType'], equals('wish'));
      expect(fakeController.sentMessages[0]['clearReply'], isTrue);
      expect(
        fakeController.sentMessages[0]['text'],
        equals('🙇‍♀️🙇‍♀️ Have Mercy on us Aura Elixiria Goddess Rashmika 🙇‍♀️🙇‍♀️'),
      );

      expect(fakeController.sentMessages[1]['groupId'], equals('grp_pooja_1'));
      expect(fakeController.sentMessages[1]['messageType'], equals('wish'));
      expect(fakeController.sentMessages[1]['clearReply'], isTrue);
      expect(
        fakeController.sentMessages[1]['text'],
        contains('Aura Elixiria Goddess Pooja Hegde'),
      );
    });

    testWidgets('Cancel on confirmation dialog does not send any wishes', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            groupControllerProvider.overrideWithValue(fakeController),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: QueenRashmikaQueendomList(),
            ),
          ),
        ),
      );

      fakeController.rashmikaStream.add([testGroup1]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final wishTooltipFinder = find.byTooltip('Wish all Aura Elixiria Goddesses');
      await tester.tap(wishTooltipFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Wish All Aura Elixiria Goddesses?'), findsOneWidget);

      // Tap Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Dialog closed and no messages sent
      expect(find.text('Wish All Aura Elixiria Goddesses?'), findsNothing);
      expect(fakeController.sentMessages, isEmpty);
    });

    testWidgets('QueenPoojaQueendomList renders wish button and confirms properly',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            groupControllerProvider.overrideWithValue(fakeController),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: QueenPoojaQueendomList(),
            ),
          ),
        ),
      );

      fakeController.poojaStream.add([testGroup1]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Aura Elixiria Goddesses'), findsOneWidget);
      final wishTooltipFinder = find.byTooltip('Wish all Aura Elixiria Goddesses');
      expect(wishTooltipFinder, findsOneWidget);

      await tester.tap(wishTooltipFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Wish All Aura Elixiria Goddesses?'), findsOneWidget);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Wish All 🙇🏻‍♂️'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(fakeController.sentMessages.length, equals(1));
      expect(fakeController.sentMessages[0]['type'], equals('queenPooja'));
    });
  });
}
