import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_chat/features/chat/widgets/message_reaction_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpAndShowDialog(
    WidgetTester tester, {
    required Size screenSize,
    required Rect targetRect,
    bool isMyMessage = true,
    double textScale = 1.0,
    EdgeInsets viewPadding = EdgeInsets.zero,
    VoidCallback? onReply,
    VoidCallback? onCopy,
    VoidCallback? onForward,
    VoidCallback? onGoogleLens,
    VoidCallback? onPin,
    VoidCallback? onEdit,
    VoidCallback? onDelete,
  }) async {
    tester.view.physicalSize = screenSize;
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding = FakeViewPadding(
      left: viewPadding.left,
      top: viewPadding.top,
      right: viewPadding.right,
      bottom: viewPadding.bottom,
    );
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetPadding();
    });

    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          size: screenSize,
          padding: viewPadding,
          textScaler: TextScaler.linear(textScale),
        ),
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  MessageReactionDialog.show(
                    context: context,
                    targetRect: targetRect,
                    currentUserId: 'u1',
                    reactions: const {'u1': '❤️'},
                    onReactionSelected: (_) {},
                    onReply: onReply,
                    onCopy: onCopy,
                    onForward: onForward,
                    onGoogleLens: onGoogleLens,
                    onPin: onPin,
                    onEdit: onEdit,
                    onDelete: onDelete,
                    isMyMessage: isMyMessage,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  void expectInsideRect(
    WidgetTester tester,
    Finder finder,
    Rect bounds,
    String label,
  ) {
    expect(finder, findsOneWidget, reason: '$label should be visible');
    final rect = tester.getRect(finder);
    expect(
      rect.left >= bounds.left - 0.5,
      isTrue,
      reason: '$label left edge (${rect.left}) must stay >= ${bounds.left}',
    );
    expect(
      rect.right <= bounds.right + 0.5,
      isTrue,
      reason: '$label right edge (${rect.right}) must stay <= ${bounds.right}',
    );
    expect(
      rect.top >= bounds.top - 0.5,
      isTrue,
      reason: '$label top edge (${rect.top}) must stay >= ${bounds.top}',
    );
    expect(
      rect.bottom <= bounds.bottom + 0.5,
      isTrue,
      reason: '$label bottom edge (${rect.bottom}) must stay <= ${bounds.bottom}',
    );
  }

  group('WhatsApp-Style Contextual AppBar & Emoji Overlay Tests', () {
    testWidgets(
      'displays message actions in top Contextual AppBar and floats only emoji pill near bubble',
      (tester) async {
        const size = Size(390, 844);
        var replyTapped = false;
        var deleteTapped = false;
        const appBarBounds = Rect.fromLTWH(0, 0, 390, 76);

        await pumpAndShowDialog(
          tester,
          screenSize: size,
          targetRect: const Rect.fromLTWH(90, 340, 280, 64),
          isMyMessage: true,
          onReply: () => replyTapped = true,
          onPin: () {},
          onCopy: () {},
          onForward: () {},
          onEdit: () {},
          onDelete: () => deleteTapped = true,
        );

        expectInsideRect(tester, find.text('1'), appBarBounds, 'Selection count');
        expectInsideRect(tester, find.byTooltip('Close'), appBarBounds, 'Close');

        for (final tip in ['Reply', 'Pin', 'Copy', 'Forward', 'Edit', 'Delete']) {
          expectInsideRect(
            tester,
            find.byTooltip(tip),
            appBarBounds,
            'AppBar $tip',
          );
        }

        // Actions are in the top AppBar, NOT duplicated as text labels below the emoji bar
        expect(find.text('Reply'), findsNothing);
        expect(find.text('Delete'), findsNothing);

        // Quick emoji bar floats cleanly below the AppBar and within screen bounds
        final contentBounds = Rect.fromLTWH(0, 76, size.width, size.height - 76);
        for (final emoji in kQuickReactionEmojis) {
          expectInsideRect(tester, find.text(emoji), contentBounds, 'Emoji $emoji');
        }

        await tester.tap(find.byTooltip('Reply'));
        await tester.pumpAndSettle();
        expect(replyTapped, isTrue);

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Delete'));
        await tester.pumpAndSettle();
        expect(deleteTapped, isTrue);
      },
    );

    testWidgets(
      'spills extra AppBar icons cleanly into More actions menu on 320px compact phone',
      (tester) async {
        const size = Size(320, 568);
        var copyTapped = false;
        var editTapped = false;

        await pumpAndShowDialog(
          tester,
          screenSize: size,
          targetRect: const Rect.fromLTWH(60, 260, 240, 64),
          isMyMessage: true,
          onReply: () {},
          onPin: () {},
          onDelete: () {},
          onForward: () {},
          onCopy: () => copyTapped = true,
          onEdit: () => editTapped = true,
          onGoogleLens: () {},
        );

        const appBarBounds = Rect.fromLTWH(0, 0, 320, 76);
        expectInsideRect(
          tester,
          find.byTooltip('More actions'),
          appBarBounds,
          'Overflow button',
        );

        for (final emoji in kQuickReactionEmojis) {
          expectInsideRect(
            tester,
            find.text(emoji),
            const Rect.fromLTWH(0, 76, 320, 492),
            'Compact emoji $emoji',
          );
        }

        await tester.tap(find.byTooltip('More actions'));
        await tester.pumpAndSettle();
        expect(find.text('Copy'), findsOneWidget);
        expect(find.text('Edit'), findsOneWidget);

        await tester.tap(find.text('Edit'));
        await tester.pumpAndSettle();
        expect(editTapped, isTrue);
        expect(copyTapped, isFalse);
      },
    );

    testWidgets(
      'keeps emoji bar & full emoji picker sheet cleanly inside screen for top-edge message',
      (tester) async {
        const size = Size(360, 640);

        await pumpAndShowDialog(
          tester,
          screenSize: size,
          targetRect: const Rect.fromLTWH(16, 80, 260, 58),
          isMyMessage: false,
          textScale: 1.3,
          viewPadding: const EdgeInsets.only(top: 24, bottom: 16),
          onReply: () {},
          onCopy: () {},
          onForward: () {},
          onDelete: () {},
        );

        await tester.tap(find.byIcon(Icons.add_rounded));
        await tester.pumpAndSettle();

        expectInsideRect(
          tester,
          find.text('🔥'),
          Rect.fromLTWH(0, 0, size.width, size.height),
          'Full emoji picker inside screen bounds',
        );
      },
    );
  });
}
