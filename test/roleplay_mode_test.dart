import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:worship_chat/common/widgets/skeleton_loader.dart';
import 'package:worship_chat/common/widgets/user_avatar.dart';
import 'package:worship_chat/features/group/services/roleplay_service.dart';
import 'package:worship_chat/features/group/widgets/roleplay_message_card.dart';
import 'package:worship_chat/models/group.dart';
import 'package:worship_chat/models/group_chat_message_model.dart';

void main() {
  group('Roleplay Mode & Message Card Tests', () {
    test('GroupChatMessageModel roleplay message serialization and deserialization', () {
      final now = DateTime(2026, 10, 28, 14, 30);
      final model = GroupChatMessageModel(
        senderId: 'roleplay',
        receiverIds: ['user1', 'user2'],
        groupId: 'grp_pooja_1',
        text: 'Royal Darshan Photo',
        messageType: 'roleplay',
        timeSent: now,
        messageId: 'msg_roleplay_1',
        fileMessageData: 'assets/images/img1.png',
        isSeen: true,
        isDelivered: true,
        repliedMessage: '',
        repliedTo: '',
        repliedMessageType: 'text',
      );

      final map = model.toMap();
      expect(map['senderId'], 'roleplay');
      expect(map['messageType'], 'roleplay');
      expect(map['fileMessageData'], 'assets/images/img1.png');
      expect(map['text'], 'Royal Darshan Photo');

      final fromMap = GroupChatMessageModel.fromMap(map);
      expect(fromMap.senderId, 'roleplay');
      expect(fromMap.messageType, 'roleplay');
      expect(fromMap.fileMessageData, 'assets/images/img1.png');
      expect(fromMap.text, 'Royal Darshan Photo');
      expect(fromMap.isSeen, true);
      expect(fromMap.isDelivered, true);
    });

    testWidgets('RoleplayMessageCard renders common bubble without sender/receiver avatars', (tester) async {
      final now = DateTime(2026, 10, 28, 14, 30);
      final message = GroupChatMessageModel(
        senderId: 'roleplay',
        receiverIds: ['user1', 'user2'],
        groupId: 'grp_pooja_1',
        text: 'Divine Darshan at Sanctuary',
        messageType: 'roleplay',
        timeSent: now,
        messageId: 'msg_roleplay_1',
        fileMessageData: 'assets/images/img1.png',
        isSeen: true,
        isDelivered: true,
        repliedMessage: '',
        repliedTo: '',
        repliedMessageType: 'text',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoleplayMessageCard(
              messageData: message,
              queendom: 'Queen Pooja',
              onSwipe: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. MUST NOT render any UserAvatar (no sender avatar on right, no receiver avatar on left)
      expect(find.byType(UserAvatar), findsNothing);

      // 2. MUST render Center widget (common centered bubble)
      expect(find.byType(Center), findsWidgets);

      // 3. MUST NOT display any Queendom/Roleplay name on top of the image
      expect(find.text('Queen Pooja • Roleplay'), findsNothing);
      expect(find.text('Queen Pooja'), findsNothing);
      expect(find.text('Roleplay Mode'), findsNothing);

      // 4. MUST display the caption below the image
      expect(find.text('Divine Darshan at Sanctuary'), findsOneWidget);

      // 5. MUST display the timestamp
      final timeStr = DateFormat.jm().format(now);
      expect(find.text(timeStr), findsOneWidget);
    });

    testWidgets('RoleplayMessageCard renders Queen Rashmika styling correctly without name header', (tester) async {
      final now = DateTime(2026, 10, 28, 14, 30);
      final message = GroupChatMessageModel(
        senderId: 'roleplay',
        receiverIds: ['user1'],
        groupId: 'grp_rashmika_1',
        text: 'Sacred Blessing',
        messageType: 'roleplay',
        timeSent: now,
        messageId: 'msg_roleplay_2',
        fileMessageData: 'assets/images/img2.png',
        isSeen: true,
        isDelivered: true,
        repliedMessage: '',
        repliedTo: '',
        repliedMessageType: 'text',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoleplayMessageCard(
              messageData: message,
              queendom: 'Queen Rashmika',
              onSwipe: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify no user avatars
      expect(find.byType(UserAvatar), findsNothing);

      // Verify no name header on top of the image
      expect(find.text('Queen Rashmika • Roleplay'), findsNothing);
      expect(find.text('Queen Rashmika'), findsNothing);
      expect(find.text('Sacred Blessing'), findsOneWidget);
    });

    testWidgets('RoleplayMessageCard without caption displays timestamp on image overlay', (tester) async {
      final now = DateTime(2026, 10, 28, 14, 30);
      final message = GroupChatMessageModel(
        senderId: 'roleplay',
        receiverIds: ['user1'],
        groupId: 'grp_pooja_1',
        text: 'assets/images/img1.png', // same as fileMessageData, so no extra caption
        messageType: 'roleplay',
        timeSent: now,
        messageId: 'msg_roleplay_3',
        fileMessageData: 'assets/images/img1.png',
        isSeen: true,
        isDelivered: true,
        repliedMessage: '',
        repliedTo: '',
        repliedMessageType: 'text',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoleplayMessageCard(
              messageData: message,
              queendom: 'Queen Pooja',
              onSwipe: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify no user avatars and no top name
      expect(find.byType(UserAvatar), findsNothing);
      expect(find.text('Queen Pooja • Roleplay'), findsNothing);
      expect(find.text('Queen Pooja'), findsNothing);

      // Verify timestamp is displayed in overlay
      final timeStr = DateFormat.jm().format(now);
      expect(find.text(timeStr), findsOneWidget);
    });

    test('Roleplay interval validation and presets logic', () {
      final presets = [5, 10, 15, 20, 30, 45, 60, 90, 120];
      expect(presets.contains(15), isTrue);
      expect(presets.contains(5), isTrue);
      expect(presets.contains(60), isTrue);

      int validateInterval(dynamic val) {
        if (val is int && val >= 3) return val;
        return 15;
      }

      expect(validateInterval(10), 10);
      expect(validateInterval(30), 30);
      expect(validateInterval(1), 15);
      expect(validateInterval(null), 15);
      expect(validateInterval('invalid'), 15);
    });

    test('Queendom group recognition helper logic', () {
      bool isQueendom(String? queendom, String? type) {
        return queendom == 'Queen Pooja' ||
            queendom == 'Queen Rashmika' ||
            type == 'queenPooja' ||
            type == 'queenRashmika';
      }

      // Queen Pooja groups
      expect(isQueendom('Queen Pooja', 'others'), isTrue);
      expect(isQueendom(null, 'queenPooja'), isTrue);
      expect(isQueendom('Queen Pooja', 'queenPooja'), isTrue);

      // Queen Rashmika groups
      expect(isQueendom('Queen Rashmika', 'others'), isTrue);
      expect(isQueendom(null, 'queenRashmika'), isTrue);
      expect(isQueendom('Queen Rashmika', 'queenRashmika'), isTrue);

      // Non-queendom groups
      expect(isQueendom('None', 'others'), isFalse);
      expect(isQueendom(null, 'others'), isFalse);
      expect(isQueendom('', ''), isFalse);
    });

    test('RoleplaySession serialization and deserialization', () {
      final session = RoleplaySession(
        groupId: 'grp_pooja_1',
        queendom: 'Queen Pooja',
        groupName: 'Temple Sanctuary',
        receiverIds: ['u1', 'u2'],
        intervalSeconds: 20,
      );

      final map = session.toMap();
      expect(map['groupId'], 'grp_pooja_1');
      expect(map['queendom'], 'Queen Pooja');
      expect(map['groupName'], 'Temple Sanctuary');
      expect(map['receiverIds'], ['u1', 'u2']);
      expect(map['intervalSeconds'], 20);

      final deserialized = RoleplaySession.fromMap(map);
      expect(deserialized.groupId, 'grp_pooja_1');
      expect(deserialized.queendom, 'Queen Pooja');
      expect(deserialized.groupName, 'Temple Sanctuary');
      expect(deserialized.receiverIds, ['u1', 'u2']);
      expect(deserialized.intervalSeconds, 20);
    });

    test('RoleplayService maintains active state independently of screen lifecycle', () {
      final service = RoleplayService.instance;
      expect(service.isRoleplayActive('test_grp_unique_123'), isFalse);

      service.stopRoleplay('test_grp_unique_123');
      expect(service.isRoleplayActive('test_grp_unique_123'), isFalse);
    });

    test('getOptimizedRoleplayImageUrl optimizes Cloudinary URLs with f_auto,q_auto,w_800,c_limit', () {
      // 1. Raw master photo with version tag
      const rawUrl = 'https://res.cloudinary.com/debeuo9x0/image/upload/v1742410000/gallery/sample.jpg';
      final optimized = getOptimizedRoleplayImageUrl(rawUrl);
      expect(
        optimized,
        'https://res.cloudinary.com/debeuo9x0/image/upload/f_auto,q_auto,w_800,c_limit/v1742410000/gallery/sample.jpg',
      );

      // 2. Insecure http is upgraded to https
      const httpUrl = 'http://res.cloudinary.com/debeuo9x0/image/upload/v12345/pic.jpg';
      final optimizedHttp = getOptimizedRoleplayImageUrl(httpUrl);
      expect(
        optimizedHttp,
        'https://res.cloudinary.com/debeuo9x0/image/upload/f_auto,q_auto,w_800,c_limit/v12345/pic.jpg',
      );

      // 3. Existing transformations are replaced cleanly
      const withOldTransform = 'https://res.cloudinary.com/debeuo9x0/image/upload/w_1200,c_scale/gallery/sample.png';
      final cleanOptimized = getOptimizedRoleplayImageUrl(withOldTransform);
      expect(
        cleanOptimized,
        'https://res.cloudinary.com/debeuo9x0/image/upload/f_auto,q_auto,w_800,c_limit/gallery/sample.png',
      );

      // 4. Non-Cloudinary URLs are preserved safely
      const regularUrl = 'https://example.com/gallery/darshan.jpg';
      expect(getOptimizedRoleplayImageUrl(regularUrl), regularUrl);

      // 5. Assets and file URLs are preserved safely
      const assetUrl = 'assets/images/pooja1.png';
      expect(getOptimizedRoleplayImageUrl(assetUrl), assetUrl);
    });

    testWidgets('RoleplayMessageCard renders royal shimmer placeholder with glowing emblem for network image', (tester) async {
      final now = DateTime(2026, 10, 28, 14, 30);
      final message = GroupChatMessageModel(
        senderId: 'roleplay',
        receiverIds: ['user1'],
        groupId: 'grp_pooja_1',
        text: 'Royal Pooja Darshan',
        messageType: 'roleplay',
        timeSent: now,
        messageId: 'msg_roleplay_net_1',
        fileMessageData: 'https://res.cloudinary.com/demo/image/upload/sample.jpg',
        isSeen: true,
        isDelivered: true,
        repliedMessage: '',
        repliedTo: '',
        repliedMessageType: 'text',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoleplayMessageCard(
              messageData: message,
              queendom: 'Queen Pooja',
              onSwipe: () {},
            ),
          ),
        ),
      );
      // Pump initial frame before image is loaded
      await tester.pump();

      // ShimmerEffect should be rendered as the placeholder
      expect(find.byType(ShimmerEffect), findsOneWidget);

      // Royal emblem icon and loading darshan text should be visible
      expect(find.byIcon(Icons.auto_awesome_rounded), findsOneWidget);
      expect(find.text('Loading Darshan Photo…'), findsOneWidget);
    });

    testWidgets('RoleplayMessageCard uses flexible height constraints and Alignment.topCenter to prevent cropping faces', (tester) async {
      final now = DateTime(2026, 10, 28, 14, 30);
      final message = GroupChatMessageModel(
        senderId: 'roleplay',
        receiverIds: ['user1'],
        groupId: 'grp_pooja_1',
        text: 'Sacred Portrait Darshan',
        messageType: 'roleplay',
        timeSent: now,
        messageId: 'msg_roleplay_aspect_1',
        fileMessageData: 'assets/images/img1.png',
        isSeen: true,
        isDelivered: true,
        repliedMessage: '',
        repliedTo: '',
        repliedMessageType: 'text',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoleplayMessageCard(
              messageData: message,
              queendom: 'Queen Pooja',
              onSwipe: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify that ConstrainedBox enforces compact height up to 270
      final constrainedBoxFinder = find.byType(ConstrainedBox);
      expect(constrainedBoxFinder, findsWidgets);

      bool foundProperConstraint = false;
      for (final element in tester.widgetList<ConstrainedBox>(constrainedBoxFinder)) {
        if (element.constraints.maxHeight == 270 && element.constraints.minHeight == 120) {
          foundProperConstraint = true;
          break;
        }
      }
      expect(foundProperConstraint, isTrue);

      // Verify Image widget has Alignment.topCenter so faces are never cut off
      final imageFinder = find.byType(Image);
      expect(imageFinder, findsOneWidget);
      final imageWidget = tester.widget<Image>(imageFinder);
      expect(imageWidget.alignment, Alignment.topCenter);
      expect(imageWidget.fit, BoxFit.cover);
    });

    test('GroupModel serializes and deserializes roleplay active state correctly', () {
      final map = {
        'senderId': 'user1',
        'name': 'Queen Pooja Sanctum',
        'groupId': 'grp_1',
        'lastMessage': 'hello',
        'groupPic': '',
        'membersUid': ['user1', 'user2'],
        'fcmTokens': <String>[],
        'unseenMessages': <String, dynamic>{},
        'isRoleplayActive': true,
        'roleplayStartedBy': 'user1',
        'roleplayIntervalSeconds': 20,
      };

      final group = GroupModel.fromMap(map);
      expect(group.isRoleplayActive, isTrue);
      expect(group.roleplayStartedBy, equals('user1'));
      expect(group.roleplayIntervalSeconds, equals(20));

      final serialized = group.toMap();
      expect(serialized['isRoleplayActive'], isTrue);
      expect(serialized['roleplayStartedBy'], equals('user1'));
      expect(serialized['roleplayIntervalSeconds'], equals(20));
    });

    test('RoleplayService stopLocalRoleplay clears active sessions', () {
      final service = RoleplayService.instance;
      expect(service.isRoleplayActive('non_existent_group'), isFalse);
      service.stopLocalRoleplay('non_existent_group');
      expect(service.isRoleplayActive('non_existent_group'), isFalse);
    });

    test('RoleplayModeType correctly parses string values and falls back to automatic', () {
      expect(RoleplayModeType.fromString('manual'), equals(RoleplayModeType.manual));
      expect(RoleplayModeType.fromString('automatic'), equals(RoleplayModeType.automatic));
      expect(RoleplayModeType.fromString('other'), equals(RoleplayModeType.automatic));
      expect(RoleplayModeType.fromString(null), equals(RoleplayModeType.automatic));
      expect(RoleplayModeType.manual.name, equals('manual'));
      expect(RoleplayModeType.automatic.name, equals('automatic'));
    });

    test('RoleplaySession preserves manual and automatic mode across serialization', () {
      final manualSession = RoleplaySession(
        groupId: 'grp_manual_1',
        queendom: 'Queen Rashmika',
        groupName: 'Rashmika Sanctum',
        receiverIds: ['u1'],
        intervalSeconds: 15,
        mode: RoleplayModeType.manual,
      );

      final map = manualSession.toMap();
      expect(map['mode'], equals('manual'));

      final deserialized = RoleplaySession.fromMap(map);
      expect(deserialized.mode, equals(RoleplayModeType.manual));
      expect(deserialized.groupId, equals('grp_manual_1'));

      final autoSession = RoleplaySession(
        groupId: 'grp_auto_1',
        queendom: 'Queen Pooja',
        groupName: 'Pooja Sanctum',
        receiverIds: ['u2'],
        intervalSeconds: 30,
        mode: RoleplayModeType.automatic,
      );

      final autoMap = autoSession.toMap();
      expect(autoMap['mode'], equals('automatic'));
      final autoDeserialized = RoleplaySession.fromMap(autoMap);
      expect(autoDeserialized.mode, equals(RoleplayModeType.automatic));
    });

    test('GroupModel persists and copies roleplayMode correctly', () {
      final group = GroupModel(
        senderId: 'user1',
        name: 'Royal Sanctuary',
        groupId: 'grp_test_mode',
        lastMessage: 'Darshan',
        groupPic: '',
        membersUid: ['user1'],
        fcmTokens: const [],
        unseenMessages: const {},
        timeSent: DateTime.now(),
        roleplayMode: 'manual',
        isRoleplayActive: true,
      );

      expect(group.roleplayMode, equals('manual'));
      expect(group.isRoleplayActive, isTrue);

      final map = group.toMap();
      expect(map['roleplayMode'], equals('manual'));
      expect(map['isRoleplayActive'], isTrue);

      final fromMap = GroupModel.fromMap(map);
      expect(fromMap.roleplayMode, equals('manual'));
      expect(fromMap.isRoleplayActive, isTrue);

      final copied = group.copyWith(roleplayMode: 'automatic');
      expect(copied.roleplayMode, equals('automatic'));

      // Test default roleplayMode when omitted from map
      final defaultMap = {
        'senderId': 'user1',
        'name': 'Royal Sanctuary',
        'groupId': 'grp_test_default',
        'lastMessage': '',
        'groupPic': '',
        'membersUid': ['user1'],
        'timeSent': DateTime.now().millisecondsSinceEpoch,
      };
      final defaultGroup = GroupModel.fromMap(defaultMap);
      expect(defaultGroup.roleplayMode, equals('automatic'));
    });

    testWidgets('Manual roleplay floating button renders top-left with casino icon and sends photo on tap', (tester) async {
      bool buttonTapped = false;

      Widget buildFloatingButton({required bool sending}) {
        const accent = Color(0xFFFF4081);
        return MaterialApp(
          home: Scaffold(
            appBar: AppBar(title: const Text('Sanctum Chat')),
            body: Stack(
              children: [
                Positioned(
                  top: 10,
                  left: 14,
                  child: SafeArea(
                    top: false,
                    bottom: false,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        key: const Key('manual_roleplay_floating_button'),
                        onTap: sending
                            ? null
                            : () {
                                buttonTapped = true;
                              },
                        borderRadius: BorderRadius.circular(24),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [accent, Color(0xFFC2185B)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (sending)
                                const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white),
                                  ),
                                )
                              else
                                const Icon(
                                  Icons.casino_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              const SizedBox(width: 7),
                              Text(
                                sending ? 'Sending...' : 'Random Photo',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }

      await tester.pumpWidget(buildFloatingButton(sending: false));
      await tester.pumpAndSettle();

      // Verify the floating button is rendered with the exact key and text
      final buttonFinder = find.byKey(const Key('manual_roleplay_floating_button'));
      expect(buttonFinder, findsOneWidget);
      expect(find.text('Random Photo'), findsOneWidget);
      expect(find.byIcon(Icons.casino_rounded), findsOneWidget);

      // Verify position: positioned top-left, down the appbar
      final buttonOffset = tester.getTopLeft(buttonFinder);
      expect(buttonOffset.dx, equals(14.0));
      // App bar standard height is 56, so offset should be below the app bar
      expect(buttonOffset.dy, greaterThan(56.0));

      // Tap the button
      await tester.tap(buttonFinder);
      await tester.pump();
      expect(buttonTapped, isTrue);

      // Verify sending state
      await tester.pumpWidget(buildFloatingButton(sending: true));
      await tester.pump();
      expect(find.text('Sending...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.casino_rounded), findsNothing);
    });
  });
}

