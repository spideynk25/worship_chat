import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/widgets/chat_status_indicator.dart';
import 'package:worship_chat/common/widgets/user_avatar.dart';

void main() {
  group('One-to-One Chat AppBar & Subtitle Tests', () {
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
