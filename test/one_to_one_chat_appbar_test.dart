import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/widgets/chat_status_indicator.dart';
import 'package:worship_chat/common/widgets/user_avatar.dart';
import 'package:worship_chat/models/user_model.dart';

void main() {
  group('One-to-One Chat AppBar & Subtitle Tests', () {
    test('AppBarStatusSubtitle.formatLastSeen formats WhatsApp style accurately', () {
      final now = DateTime.now();

      // Today
      final todayTime = DateTime(now.year, now.month, now.day, 14, 30);
      final todayExpected =
          'last seen today at ${DateFormat('h:mm a').format(todayTime).toLowerCase()}';
      expect(AppBarStatusSubtitle.formatLastSeen(todayTime), todayExpected);

      // Yesterday
      final yesterday = now.subtract(const Duration(days: 1));
      final yesterdayTime =
          DateTime(yesterday.year, yesterday.month, yesterday.day, 9, 15);
      final yesterdayExpected =
          'last seen yesterday at ${DateFormat('h:mm a').format(yesterdayTime).toLowerCase()}';
      expect(AppBarStatusSubtitle.formatLastSeen(yesterdayTime), yesterdayExpected);

      // Specific past date in same year
      final pastDateThisYear = DateTime(now.year, 1, 15, 16, 45);
      if (now.difference(pastDateThisYear).inDays > 1) {
        final pastDateStr = DateFormat('dd/MM/yy').format(pastDateThisYear);
        final timeStr = DateFormat('h:mm a').format(pastDateThisYear).toLowerCase();
        expect(
          AppBarStatusSubtitle.formatLastSeen(pastDateThisYear),
          'last seen $pastDateStr at $timeStr',
        );
      }

      // Past year
      final pastYearDate = DateTime(2023, 5, 20, 11, 0);
      final pastYearDateStr = DateFormat('dd/MM/yyyy').format(pastYearDate);
      final pastYearTimeStr =
          DateFormat('h:mm a').format(pastYearDate).toLowerCase();
      expect(
        AppBarStatusSubtitle.formatLastSeen(pastYearDate),
        'last seen $pastYearDateStr at $pastYearTimeStr',
      );
    });

    test('UserModel serializes and deserializes lastSeen from Timestamp, int, DateTime, and String', () {
      final now = DateTime.now();

      // From Timestamp
      final userFromTimestamp = UserModel.fromMap({
        'name': 'Pooja Hegde',
        'isOnline': false,
        'lastSeen': Timestamp.fromDate(now),
      });
      expect(userFromTimestamp.lastSeen?.millisecondsSinceEpoch,
          closeTo(now.millisecondsSinceEpoch, 1000));

      // From int (millis)
      final userFromInt = UserModel.fromMap({
        'name': 'Rashmika Mandanna',
        'isOnline': false,
        'lastSeen': now.millisecondsSinceEpoch,
      });
      expect(userFromInt.lastSeen?.millisecondsSinceEpoch,
          closeTo(now.millisecondsSinceEpoch, 1000));

      // From DateTime
      final userFromDateTime = UserModel.fromMap({
        'name': 'Queen',
        'isOnline': false,
        'lastSeen': now,
      });
      expect(userFromDateTime.lastSeen, now);

      // From String
      final userFromString = UserModel.fromMap({
        'name': 'Devotee',
        'isOnline': false,
        'lastSeen': now.toIso8601String(),
      });
      expect(userFromString.lastSeen?.millisecondsSinceEpoch,
          closeTo(now.millisecondsSinceEpoch, 1000));

      // toMap creates Firestore Timestamp
      final userMap = userFromDateTime.toMap();
      expect(userMap['lastSeen'], isA<Timestamp>());
      expect((userMap['lastSeen'] as Timestamp).toDate(), now);
    });

    testWidgets('AppBarStatusSubtitle displays WhatsApp last seen when offline', (tester) async {
      final now = DateTime.now();
      final todayTime = DateTime(now.year, now.month, now.day, 16, 20);
      final expectedTodayText =
          'last seen today at ${DateFormat('h:mm a').format(todayTime).toLowerCase()}';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppBarStatusSubtitle(
              isTyping: false,
              isOnline: false,
              lastSeen: todayTime,
            ),
          ),
        ),
      );

      expect(find.text(expectedTodayText), findsOneWidget);
      // Pulsing green dot should not be visible when offline
      expect(find.byType(PulsingOnlineDot), findsNothing);
    });

    testWidgets('AppBarStatusSubtitle transitions between typing, online, and offline', (tester) async {
      // 1. Offline state
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppBarStatusSubtitle(
              isTyping: false,
              isOnline: false,
            ),
          ),
        ),
      );

      expect(find.text('Offline'), findsOneWidget);

      // 2. Online state
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppBarStatusSubtitle(
              isTyping: false,
              isOnline: true,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Online'), findsOneWidget);
      expect(find.byType(PulsingOnlineDot), findsOneWidget);

      // 3. Typing state
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppBarStatusSubtitle(
              isTyping: true,
              isOnline: true,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('typing'), findsOneWidget);
      expect(find.byType(BouncingTypingDots), findsOneWidget);
    });

    testWidgets('UserAvatar displays online indicator badge when online', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: UserAvatar(
              url: null,
              radius: 20,
              isOnline: true,
              showOnlineIndicator: true,
              borderColor: appBarColor,
            ),
          ),
        ),
      );

      expect(find.byType(UserAvatar), findsOneWidget);
      // The Stack should contain the fallback avatar and the online badge container
      final containers = find.descendant(
        of: find.byType(UserAvatar),
        matching: find.byType(Container),
      );
      expect(containers, findsWidgets);
    });

    testWidgets('AppBar layout renders back button, title, and actions', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              toolbarHeight: 64,
              elevation: 0,
              scrolledUnderElevation: 0,
              backgroundColor: appBarColor,
              automaticallyImplyLeading: false,
              leadingWidth: 0,
              titleSpacing: 0,
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(0.6),
                child: Container(
                  color: dividerColor.withValues(alpha: 0.5),
                  height: 0.6,
                ),
              ),
              title: Padding(
                padding: const EdgeInsets.only(left: 4, right: 4),
                child: Row(
                  children: [
                    IconButton(
                      alignment: Alignment.centerLeft,
                      onPressed: () {},
                      icon: const Icon(CupertinoIcons.back, size: 24),
                      padding: const EdgeInsets.only(left: 6, right: 4),
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 44),
                    ),
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFF00E676).withValues(alpha: 0.5),
                                width: 1.5,
                              ),
                            ),
                            child: const UserAvatar(
                              url: null,
                              radius: 20,
                              isOnline: true,
                              showOnlineIndicator: true,
                              borderColor: appBarColor,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Aura Elixiria',
                                  style: TextStyle(
                                    fontSize: 16.0,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(height: 2),
                                AppBarStatusSubtitle(
                                  isTyping: false,
                                  isOnline: true,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                IconButton(
                  icon: const Icon(CupertinoIcons.photo),
                  onPressed: () {},
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'view_profile',
                      child: Text('View Profile'),
                    ),
                    PopupMenuItem(
                      value: 'media_links',
                      child: Text('Media, Links & Docs'),
                    ),
                    PopupMenuItem(
                      value: 'change_background',
                      child: Text('Change Background'),
                    ),
                    PopupMenuItem(
                      value: 'toggle_background',
                      child: Text('Hide Background'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byIcon(CupertinoIcons.back), findsOneWidget);
      expect(find.text('Aura Elixiria'), findsOneWidget);
      expect(find.text('Online'), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.photo), findsOneWidget);
      expect(find.byIcon(Icons.more_vert), findsOneWidget);

      // Open popup menu
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('View Profile'), findsOneWidget);
      expect(find.text('Media, Links & Docs'), findsOneWidget);
      expect(find.text('Change Background'), findsOneWidget);
      expect(find.text('Hide Background'), findsOneWidget);
    });
  });
}
