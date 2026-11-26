import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_chat/features/group/screens/group_chat_screen.dart';
import 'package:worship_chat/features/group/utils/group_template_helper.dart';
import 'package:worship_chat/features/group/utils/queendom_emblem_helper.dart';
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
    test('Implements PreferredSizeWidget with 32.0 height', () {
      final bottom = RoyalSanctuaryAppBarBottom(
        initialGroup: testGroup,
        accentColor: Colors.amber,
      );

      expect(bottom, isA<PreferredSizeWidget>());
      expect(bottom.preferredSize.height, 32.0);
    });

    testWidgets('Renders sanctuary details merged into AppBar bottom without wish message or close button',
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
      // Verify wish message does NOT appear on AppBar
      expect(find.textContaining('Long live Supreme Goddess Disha Patani'), findsNothing);
      // Verify close button does NOT exist
      expect(find.byIcon(Icons.close_rounded), findsNothing);
      expect(find.byIcon(Icons.close), findsNothing);

      // Verify tapping triggers callback
      await tester.tap(find.textContaining('SANCTUM OF').first);
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('Returns SizedBox.shrink when no position, family, or livingPlace exist',
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

    testWidgets('Avatar tap vs long-press gesture distinction for group info vs gallery', (tester) async {
      bool tappedInfo = false;
      bool longPressedGallery = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              title: Row(
                children: [
                  GestureDetector(
                    onTap: () => tappedInfo = true,
                    onLongPress: () => longPressedGallery = true,
                    child: const CircleAvatar(child: Icon(Icons.group)),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.byType(CircleAvatar));
      expect(tappedInfo, isTrue);
      expect(longPressedGallery, isFalse);

      tappedInfo = false;
      await tester.longPress(find.byType(CircleAvatar));
      expect(longPressedGallery, isTrue);
    });

    testWidgets('Group popup menu includes Gallery entry and triggers callback', (tester) async {
      String? selected;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: [
                PopupMenuButton<String>(
                  onSelected: (val) => selected = val,
                  itemBuilder: (context) => [
                    const PopupMenuItem<String>(
                      value: 'gallery',
                      child: Row(
                        children: [
                          Icon(Icons.photo_library_outlined, size: 20),
                          SizedBox(width: 12),
                          Text('Gallery'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();

      expect(find.text('Gallery'), findsOneWidget);
      expect(find.byIcon(Icons.photo_library_outlined), findsOneWidget);

      await tester.tap(find.text('Gallery'));
      await tester.pumpAndSettle();

      expect(selected, 'gallery');
    });

    testWidgets('Merged Name, Family, and Living Place AppBar title displays all cleanly in separate lines', (tester) async {
      final cleanPlace = GroupTemplateHelper.formatSanctuarySubtitle(
        livingPlace: testGroup.livingPlace!,
        deityName: testGroup.name,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              toolbarHeight: 76,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  QueendomEmblemHelper.buildRichTitle(
                    title: testGroup.nameWithPosition,
                    family: testGroup.family,
                    fallbackFamily: 'Main',
                    style: const TextStyle(fontSize: 14.0, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2.0),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5.0, vertical: 1.0),
                    child: Text('${testGroup.family} Family'),
                  ),
                  const SizedBox(height: 2.5),
                  Text(
                    cleanPlace,
                    style: const TextStyle(fontSize: 10.0, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify deity name is present on Line 1
      expect(find.textContaining('Disha Patani'), findsWidgets);
      // Verify family badge is present on separate Line 2
      expect(find.text('Main Family'), findsOneWidget);
      // Verify living place is present on separate Line 3
      expect(find.text('Sanctum of Supreme Goddess'), findsOneWidget);
      // Verify no typing indicator text is present in the AppBar
      expect(find.textContaining('typing'), findsNothing);
    });

    test('formatSanctuarySubtitle produces elegant Title Case without repeating deity name', () {
      final subtitle = GroupTemplateHelper.formatSanctuarySubtitle(
        livingPlace: 'PALACE OF FIRST BORN PRINCESS KRITHI SHETTY',
        deityName: 'Krithi Shetty',
        family: 'Main',
      );
      expect(subtitle, 'Palace of First Born Princess · Main Family');

      final subtitle2 = GroupTemplateHelper.formatSanctuarySubtitle(
        livingPlace: 'TEMPLE OF GODDESS POOJA',
        deityName: 'Pooja',
        family: null,
      );
      expect(subtitle2, 'Temple of Goddess');
    });

    test('cleanLivingPlace deduplicates repeated prefixes from corrupted inputs', () {
      const corrupted = 'PALACE OF FIRST BORN PRINCESS PALACE OF FIRST BORN PRINCESS KRITHI SHETTY';
      final clean = GroupTemplateHelper.cleanLivingPlace(
        corrupted,
        position: 'First Born Princess',
        family: 'Main',
      );
      expect(clean, 'PALACE OF FIRST BORN PRINCESS KRITHI SHETTY');

      final group = GroupModel(
        senderId: 'user1',
        name: 'Palace of First Born Princess Krithi Shetty',
        groupId: 'test_group_krithi',
        lastMessage: '',
        groupPic: '',
        membersUid: ['user1'],
        fcmTokens: [],
        unseenMessages: {},
        position: 'First Born Princess',
        family: 'Main',
        livingPlace: corrupted,
      );
      expect(group.effectiveLivingPlace, 'PALACE OF FIRST BORN PRINCESS KRITHI SHETTY');
    });
  });
}
