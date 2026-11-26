import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:worship_chat/features/chat/widgets/chat_power_ups.dart';
import 'package:worship_chat/features/chat/widgets/message_reaction_dialog.dart';
import 'package:worship_chat/models/group_chat_message_model.dart';
import 'package:worship_chat/models/one_to_one_message_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Message Model & Hive Adapter Pin Tests', () {
    late Directory hiveDir;

    setUp(() {
      hiveDir = Directory.systemTemp.createTempSync('worship_pin_hive_test_');
      Hive.init(hiveDir.path);
    });

    tearDown(() async {
      await Hive.close();
      if (hiveDir.existsSync()) {
        hiveDir.deleteSync(recursive: true);
      }
    });

    test('OneToOneMessageModel toMap/fromMap/copyWith(clearPin) & Hive roundtrip', () async {
      final now = DateTime(2026, 11, 26, 8, 30);
      final pinTime = DateTime(2026, 11, 26, 9, 0);

      final msg = OneToOneMessageModel(
        senderId: 'u1',
        receiverId: 'u2',
        text: 'Praise the Queen',
        messageType: 'text',
        timeSent: now,
        messageId: 'm1',
        repliedMessage: '',
        repliedTo: '',
        repliedMessageType: 'text',
        isPinned: true,
        pinnedAt: pinTime,
        pinnedBy: 'u1',
      );

      final roundtripMap = OneToOneMessageModel.fromMap(msg.toMap());
      expect(roundtripMap.isPinned, isTrue);
      expect(roundtripMap.pinnedAt?.millisecondsSinceEpoch,
          pinTime.millisecondsSinceEpoch);
      expect(roundtripMap.pinnedBy, 'u1');

      final unpinned = roundtripMap.copyWith(clearPin: true);
      expect(unpinned.isPinned, isFalse);
      expect(unpinned.pinnedAt, isNull);
      expect(unpinned.pinnedBy, isNull);

      if (!Hive.isAdapterRegistered(1)) {
        Hive.registerAdapter(OneToOneMessageModelAdapter());
      }
      final box = await Hive.openBox('test_one_to_one');
      await box.put('m1', msg);
      final stored = box.get('m1') as OneToOneMessageModel;
      expect(stored.isPinned, isTrue);
      expect(stored.pinnedBy, 'u1');
      expect(stored.pinnedAt?.millisecondsSinceEpoch,
          pinTime.millisecondsSinceEpoch);
    });

    test('GroupChatMessageModel toMap/fromMap/copyWith(clearPin) & Hive roundtrip', () async {
      final now = DateTime(2026, 11, 26, 8, 30);
      final pinTime = DateTime(2026, 11, 26, 9, 15);

      final msg = GroupChatMessageModel(
        senderId: 'u1',
        receiverIds: const ['u2', 'u3'],
        groupId: 'g1',
        text: 'Sunday Worship Time',
        messageType: 'text',
        timeSent: now,
        messageId: 'gm1',
        repliedMessage: '',
        repliedTo: '',
        repliedMessageType: 'text',
        isPinned: true,
        pinnedAt: pinTime,
        pinnedBy: 'u1',
      );

      final parsed = GroupChatMessageModel.fromMap(msg.toMap());
      expect(parsed.isPinned, isTrue);
      expect(parsed.pinnedBy, 'u1');

      final unpinned = parsed.copyWith(clearPin: true);
      expect(unpinned.isPinned, isFalse);
      expect(unpinned.pinnedAt, isNull);
      expect(unpinned.pinnedBy, isNull);

      if (!Hive.isAdapterRegistered(2)) {
        Hive.registerAdapter(GroupChatMessageModelAdapter());
      }
      final box = await Hive.openBox('test_group_msgs');
      await box.put('gm1', msg);
      final stored = box.get('gm1') as GroupChatMessageModel;
      expect(stored.isPinned, isTrue);
      expect(stored.pinnedBy, 'u1');
    });
  });

  group('ChatPowerUpHelper Search & Pin Tests', () {
    final baseTime = DateTime(2026, 11, 26, 10, 0);
    final sampleMessages = [
      ChatMessageSummary(
        messageId: 'm1',
        senderId: 'u1',
        senderLabel: 'You',
        text: 'Welcome to Royal Queendom',
        messageType: 'text',
        timeSent: baseTime,
        isPinned: true,
        pinnedAt: baseTime.add(const Duration(minutes: 5)),
        isMyMessage: true,
      ),
      ChatMessageSummary(
        messageId: 'm2',
        senderId: 'u2',
        senderLabel: 'Queen Pooja',
        text: 'Check https://example.com/gallery for photos',
        messageType: 'text',
        timeSent: baseTime.add(const Duration(minutes: 2)),
      ),
      ChatMessageSummary(
        messageId: 'm3',
        senderId: 'u2',
        senderLabel: 'Queen Pooja',
        text: 'Royal crown',
        messageType: 'image',
        fileMessageData:
            'https://res.cloudinary.com/demo/image/upload/v1/royal.jpg',
        timeSent: baseTime.add(const Duration(minutes: 4)),
        isPinned: true,
        pinnedAt: baseTime.add(const Duration(minutes: 10)),
      ),
      ChatMessageSummary(
        messageId: 'm4',
        senderId: 'u1',
        senderLabel: 'You',
        text: '',
        messageType: 'document',
        fileMessageData:
            '{"url":"https://res.cloudinary.com/demo/raw/upload/doc","fileName":"ChantBook.pdf"}',
        timeSent: baseTime.add(const Duration(minutes: 6)),
        isMyMessage: true,
      ),
      ChatMessageSummary(
        messageId: 'm5_deleted',
        senderId: 'u1',
        senderLabel: 'You',
        text: 'Royal deleted secret',
        messageType: 'text',
        timeSent: baseTime.add(const Duration(minutes: 8)),
        isPinned: true,
        isDeleted: true,
        isMyMessage: true,
      ),
      ChatMessageSummary(
        messageId: 'm6_video',
        senderId: 'u2',
        senderLabel: 'Queen Pooja',
        text: 'Evening bhajan clip',
        messageType: 'video',
        fileMessageData:
            '{"url":"https://res.cloudinary.com/demo/video/upload/v2/clip.mp4","groupId":"g1"}',
        timeSent: baseTime.add(const Duration(minutes: 9)),
      ),
      ChatMessageSummary(
        messageId: 'm7_img_url_text',
        senderId: 'u1',
        senderLabel: 'You',
        text: 'https://res.cloudinary.com/demo/image/upload/v3/snap.jpg',
        messageType: 'image',
        fileMessageData:
            'https://res.cloudinary.com/demo/image/upload/v3/snap.jpg',
        timeSent: baseTime.add(const Duration(minutes: 10)),
        isMyMessage: true,
      ),
      ChatMessageSummary(
        messageId: 'm8_roleplay',
        senderId: 'roleplay',
        senderLabel: 'Roleplay',
        text: '',
        messageType: 'roleplay',
        fileMessageData:
            'https://res.cloudinary.com/demo/image/upload/v4/rp.jpg',
        timeSent: baseTime.add(const Duration(minutes: 11)),
      ),
      ChatMessageSummary(
        messageId: 'm9_gif',
        senderId: 'u1',
        senderLabel: 'You',
        text: '📷 Photo',
        messageType: 'image',
        fileMessageData: 'https://res.cloudinary.com/demo/image/upload/v5/p.jpg',
        timeSent: baseTime.add(const Duration(minutes: 12)),
        isMyMessage: true,
      ),
    ];

    test('extractPinned excludes deleted and sorts newest pinned first', () {
      final pinned = ChatPowerUpHelper.extractPinned(sampleMessages);
      expect(pinned.map((e) => e.messageId).toList(), ['m3', 'm1']);
    });

    test('searchMessages separates Photos, Videos, Links, Files, Text and never leaks CDN URLs', () {
      // Caption, text, document filename, and video caption search
      expect(
        ChatPowerUpHelper.searchMessages(sampleMessages, query: 'royal')
            .map((e) => e.messageId)
            .toList(),
        ['m1', 'm3'],
      );
      expect(
        ChatPowerUpHelper.searchMessages(sampleMessages, query: 'chantbook')
            .map((e) => e.messageId)
            .toList(),
        ['m4'],
      );
      expect(
        ChatPowerUpHelper.searchMessages(sampleMessages, query: 'bhajan')
            .map((e) => e.messageId)
            .toList(),
        ['m6_video'],
      );

      // Raw CDN URLs / URL substrings MUST NOT falsely match media or docs
      expect(
        ChatPowerUpHelper.searchMessages(sampleMessages, query: 'cloudinary'),
        isEmpty,
      );
      expect(
        ChatPowerUpHelper.searchMessages(sampleMessages, query: 'http')
            .map((e) => e.messageId)
            .toList(),
        ['m2'],
      );
      expect(
        ChatPowerUpHelper.searchMessages(sampleMessages, query: 'snap.jpg'),
        isEmpty,
      );

      // Dedicated non-confusing category filters
      expect(
        ChatPowerUpHelper.searchMessages(
          sampleMessages,
          query: '',
          filter: ChatSearchFilter.links,
        ).map((e) => e.messageId).toList(),
        ['m2'],
      );
      expect(
        ChatPowerUpHelper.searchMessages(
          sampleMessages,
          query: '',
          filter: ChatSearchFilter.photos,
        ).map((e) => e.messageId).toList(),
        ['m3', 'm7_img_url_text', 'm8_roleplay', 'm9_gif'],
      );
      expect(
        ChatPowerUpHelper.searchMessages(
          sampleMessages,
          query: '',
          filter: ChatSearchFilter.videos,
        ).map((e) => e.messageId).toList(),
        ['m6_video'],
      );
      expect(
        ChatPowerUpHelper.searchMessages(
          sampleMessages,
          query: '',
          filter: ChatSearchFilter.files,
        ).map((e) => e.messageId).toList(),
        ['m4'],
      );
      expect(
        ChatPowerUpHelper.searchMessages(
          sampleMessages,
          query: '',
          filter: ChatSearchFilter.text,
        ).map((e) => e.messageId).toList(),
        ['m1', 'm2'],
      );
      expect(
        ChatPowerUpHelper.searchMessages(
          sampleMessages,
          query: '',
          filter: ChatSearchFilter.pinned,
        ).map((e) => e.messageId).toList(),
        ['m1', 'm3'],
      );

      // Clean preview labels (never double-emoji or expose raw CDN attachment URLs)
      expect(ChatPowerUpHelper.previewText(sampleMessages[5]), '🎥 Evening bhajan clip');
      expect(ChatPowerUpHelper.previewText(sampleMessages[6]), '📷 Photo');
      expect(ChatPowerUpHelper.previewText(sampleMessages[8]), '📷 Photo');
      expect(ChatPowerUpHelper.previewText(sampleMessages[3]), '📄 ChantBook.pdf');
    });
  });

  group('Chat Power-Ups Widget Tests', () {
    testWidgets('MessageReactionDialog toggles Pin / Unpin action cleanly', (tester) async {
      var pinnedCalls = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  ElevatedButton(
                    onPressed: () {
                      MessageReactionDialog.show(
                        context: context,
                        targetRect: const Rect.fromLTWH(40, 200, 200, 60),
                        currentUserId: 'u1',
                        reactions: const {},
                        onReactionSelected: (_) {},
                        onReply: () {},
                        onPin: () => pinnedCalls++,
                        isPinned: false,
                      );
                    },
                    child: const Text('PinMenu'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      MessageReactionDialog.show(
                        context: context,
                        targetRect: const Rect.fromLTWH(40, 200, 200, 60),
                        currentUserId: 'u1',
                        reactions: const {},
                        onReactionSelected: (_) {},
                        onPin: () => pinnedCalls++,
                        isPinned: true,
                      );
                    },
                    child: const Text('UnpinMenu'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('PinMenu'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Pin'), findsOneWidget);
      await tester.tap(find.byTooltip('Pin'));
      await tester.pumpAndSettle();
      expect(pinnedCalls, 1);

      await tester.tap(find.text('UnpinMenu'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Unpin'), findsOneWidget);
      await tester.tap(find.byTooltip('Unpin'));
      await tester.pumpAndSettle();
      expect(pinnedCalls, 2);
    });

    testWidgets('ChatSearchToolbar filters, steps matches, and jumps cleanly', (tester) async {
      final jumpedIds = <String>[];
      final controller = ChatPowerUpController()
        ..attachJumpHandler(jumpedIds.add)
        ..updateMessages([
          ChatMessageSummary(
            messageId: 'a1',
            senderId: 'u1',
            senderLabel: 'You',
            text: 'First grace note',
            messageType: 'text',
            timeSent: DateTime(2026, 1, 1, 10, 0),
            isMyMessage: true,
          ),
          ChatMessageSummary(
            messageId: 'a2',
            senderId: 'u2',
            senderLabel: 'Anu',
            text: 'Unrelated line',
            messageType: 'text',
            timeSent: DateTime(2026, 1, 1, 10, 5),
          ),
          ChatMessageSummary(
            messageId: 'a3',
            senderId: 'u1',
            senderLabel: 'You',
            text: 'Second grace blessing',
            messageType: 'text',
            timeSent: DateTime(2026, 1, 1, 10, 10),
            isPinned: true,
            isMyMessage: true,
          ),
        ])
        ..openSearch();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                ChatSearchToolbar(controller: controller),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'grace');
      await tester.pumpAndSettle();

      expect(find.text('2/2'), findsOneWidget);
      expect(jumpedIds.last, 'a3');

      await tester.tap(find.byTooltip('Older match'));
      await tester.pumpAndSettle();
      expect(find.text('1/2'), findsOneWidget);
      expect(jumpedIds.last, 'a1');

      await tester.tap(find.byTooltip('Newer match'));
      await tester.pumpAndSettle();
      expect(find.text('2/2'), findsOneWidget);
      expect(jumpedIds.last, 'a3');

      await tester.tap(find.byTooltip('View matching messages'));
      await tester.pumpAndSettle();
      expect(find.text('2 Matches for "grace"'), findsOneWidget);
      await tester.tap(find.text('First grace note', findRichText: true));
      await tester.pumpAndSettle();
      expect(jumpedIds.last, 'a1');

      controller.dispose();
    });

    testWidgets('PinnedMessagesBanner cycles through pins, opens sheet, and unpins', (tester) async {
      final jumpedIds = <String>[];
      final unpinnedIds = <String>[];
      final t = DateTime(2026, 1, 1, 10, 0);

      final controller = ChatPowerUpController()
        ..attachJumpHandler(jumpedIds.add)
        ..updateMessages([
          ChatMessageSummary(
            messageId: 'p1',
            senderId: 'u1',
            senderLabel: 'You',
            text: 'Older Pin',
            messageType: 'text',
            timeSent: t,
            isPinned: true,
            pinnedAt: t.add(const Duration(minutes: 1)),
            isMyMessage: true,
          ),
          ChatMessageSummary(
            messageId: 'p2',
            senderId: 'u2',
            senderLabel: 'Priya',
            text: 'Latest Pin',
            messageType: 'text',
            timeSent: t.add(const Duration(minutes: 2)),
            isPinned: true,
            pinnedAt: t.add(const Duration(minutes: 5)),
          ),
        ]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                PinnedMessagesBanner(
                  controller: controller,
                  onUnpin: (id) async => unpinnedIds.add(id),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Pinned Message • 1 of 2'), findsOneWidget);
      expect(find.text('Latest Pin'), findsOneWidget);

      await tester.tap(find.text('Latest Pin'));
      await tester.pumpAndSettle();
      expect(jumpedIds, ['p2']);
      expect(find.text('Pinned Message • 2 of 2'), findsOneWidget);
      expect(find.text('Older Pin'), findsOneWidget);

      await tester.tap(find.byTooltip('All pinned messages'));
      await tester.pumpAndSettle();
      expect(find.text('Pinned Messages (2)'), findsOneWidget);

      await tester.tap(find.text('Unpin All'));
      await tester.pumpAndSettle();
      expect(unpinnedIds, ['p2', 'p1']);

      controller.dispose();
    });

    testWidgets('ChatScrollToBottomButton appears when scrolled up, shows unread badge, and jumps to bottom on tap', (tester) async {
      final scrollController = ScrollController();
      final bottomController = ChatScrollToBottomController();
      scrollController.addListener(() {
        if (scrollController.hasClients) {
          bottomController.handleScroll(scrollController.position);
        }
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                ListView.builder(
                  controller: scrollController,
                  reverse: true,
                  itemCount: 40,
                  itemBuilder: (_, idx) => ListTile(title: Text('Message $idx')),
                ),
                ChatScrollToBottomButton(
                  controller: bottomController,
                  scrollController: scrollController,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Hidden when already at bottom
      expect(bottomController.visibleNotifier.value, isFalse);

      // Scroll up into older messages
      scrollController.jumpTo(350.0);
      await tester.pumpAndSettle();
      expect(bottomController.visibleNotifier.value, isTrue);

      bottomController.notifyIncomingMessages(3);
      await tester.pumpAndSettle();
      expect(find.text('3'), findsOneWidget);

      await tester.tap(find.byTooltip('Jump to latest messages'));
      await tester.pumpAndSettle();

      expect(scrollController.position.pixels, 0.0);
      expect(bottomController.visibleNotifier.value, isFalse);
      expect(bottomController.unreadCountNotifier.value, 0);

      bottomController.dispose();
      scrollController.dispose();
    });

    testWidgets('ChatSearchToolbar switches between Photos, Videos, and Links without confusion', (tester) async {
      final jumpedIds = <String>[];
      final t = DateTime(2026, 1, 1, 10, 0);
      final controller = ChatPowerUpController()
        ..attachJumpHandler(jumpedIds.add)
        ..updateMessages([
          ChatMessageSummary(
            messageId: 'img1',
            senderId: 'u2',
            senderLabel: 'Pooja',
            text: '',
            messageType: 'image',
            fileMessageData:
                'https://res.cloudinary.com/demo/image/upload/pic.jpg',
            timeSent: t,
          ),
          ChatMessageSummary(
            messageId: 'vid1',
            senderId: 'u2',
            senderLabel: 'Pooja',
            text: '',
            messageType: 'video',
            fileMessageData:
                'https://res.cloudinary.com/demo/video/upload/clip.mp4',
            timeSent: t.add(const Duration(minutes: 1)),
          ),
          ChatMessageSummary(
            messageId: 'lnk1',
            senderId: 'u1',
            senderLabel: 'You',
            text: 'Watch at https://example.com/live',
            messageType: 'text',
            timeSent: t.add(const Duration(minutes: 2)),
            isMyMessage: true,
          ),
        ])
        ..openSearch();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatSearchToolbar(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Photos'));
      await tester.pumpAndSettle();
      expect(find.text('1/1'), findsOneWidget);
      expect(jumpedIds.last, 'img1');

      await tester.tap(find.text('Videos'));
      await tester.pumpAndSettle();
      expect(find.text('1/1'), findsOneWidget);
      expect(jumpedIds.last, 'vid1');

      await tester.tap(find.text('Links'));
      await tester.pumpAndSettle();
      expect(find.text('1/1'), findsOneWidget);
      expect(jumpedIds.last, 'lnk1');

      controller.dispose();
    });

    testWidgets('ChatListJumpHelper converges onto far off-screen variable-height row', (tester) async {
      final scrollController = ScrollController();
      const rowCount = 60;
      final keys = List.generate(rowCount, (_) => GlobalKey());
      final primaryIds = List.generate(rowCount, (i) => 'msg_$i');
      String? highlightedId;
      const targetIdx = 4; // Near oldest end, behind both short and 360px rows

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 500,
              child: ListView.builder(
                controller: scrollController,
                reverse: true,
                itemCount: rowCount,
                itemBuilder: (_, index) {
                  final rowIdx = rowCount - 1 - index;
                  final isTallMedia = rowIdx < 20;
                  return KeyedSubtree(
                    key: keys[rowIdx],
                    child: SizedBox(
                      height: isTallMedia ? 360.0 : 48.0,
                      child: Text('Row $rowIdx'),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(keys[targetIdx].currentContext, isNull);

      ChatListJumpHelper.convergeToMessage(
        generation: 1,
        currentGeneration: () => 1,
        isMounted: () => true,
        scrollController: scrollController,
        targetMessageId: primaryIds[targetIdx],
        keyForPrimaryId: (id) {
          final idx = int.parse(id.split('_').last);
          return keys[idx];
        },
        onHighlight: (id) => highlightedId = id,
        lookupTargetRow: () => ChatRowLookup(
          rowCount: rowCount,
          targetRowIndex: targetIdx,
          primaryMessageId: primaryIds[targetIdx],
        ),
        orderedPrimaryIds: () => primaryIds,
      );

      await tester.pumpAndSettle();

      expect(keys[targetIdx].currentContext, isNotNull);
      expect(highlightedId, 'msg_$targetIdx');

      scrollController.dispose();
    });

    testWidgets('ChatPaginationHelper auto-loads underfilled reverse list when hasMore is true', (tester) async {
      final scrollController = ScrollController();
      var loadMoreCalls = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 600,
              child: Builder(
                builder: (context) {
                  ChatPaginationHelper.scheduleUnderfilledCheck(
                    scrollController: scrollController,
                    hasMore: true,
                    isLoadingMore: false,
                    onLoadMore: () => loadMoreCalls++,
                  );
                  return ListView.builder(
                    controller: scrollController,
                    reverse: true,
                    itemCount: 3,
                    itemBuilder: (_, idx) => SizedBox(
                      height: 60,
                      child: Text('Grouped $idx'),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(loadMoreCalls, 1);

      scrollController.dispose();
    });
  });
}
