import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_chat/common/enums/message_status_enum.dart';
import 'package:worship_chat/common/providers/message_reply_provider.dart';
import 'package:worship_chat/common/utils/wish_helper.dart';
import 'package:worship_chat/features/chat/widgets/display_messages.dart';
import 'package:worship_chat/features/chat/widgets/message_reply_preview.dart';
import 'package:worship_chat/features/chat/widgets/wish_bubble_content_widget.dart';

import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });
  group('WishHelper Tests', () {
    test('isWish identifies birthday wishes correctly', () {
      expect(
        WishHelper.isWish(
          text: 'Wishing Her Supreme Royal Majesty Queen Pooja a magnificent birthday! 🎂✨',
        ),
        isTrue,
      );
      expect(
        WishHelper.isWish(
          text: 'Happy Birthday Queen Rashmika! 🎉',
        ),
        isTrue,
      );
      expect(
        WishHelper.isWish(
          messageType: 'wish',
          text: 'Special celebration',
        ),
        isTrue,
      );
    });

    test('isWish identifies divine sanctuary wishes correctly', () {
      expect(
        WishHelper.isWish(
          text: '🙇🏻‍♂️ Hail Her Supreme Royal Majesty Queen Pooja 🙇🏻‍♂️',
        ),
        isTrue,
      );
      expect(
        WishHelper.isWish(
          text: 'Long live Supreme Goddess Pooja! Have mercy on us worshippers 🙇',
        ),
        isTrue,
      );
    });

    test('isWish rejects normal text messages', () {
      expect(WishHelper.isWish(text: 'Hello, how are you?'), isFalse);
      expect(WishHelper.isWish(text: 'See you tomorrow at church'), isFalse);
      expect(WishHelper.isWish(text: 'Ok'), isFalse);
    });

    test('toRoyalScript converts text to authentic Royal Cursive Calligraphy Script', () {
      final script = WishHelper.toRoyalScript('Happy Birthday 2026');
      // Verify conversion to Mathematical Bold Script characters (𝓗𝓪𝓹𝓹𝔂 𝓑𝓲𝓻𝓽𝓱𝓭𝓪𝔂 𝟐𝟎𝟐𝟔)
      expect(script, equals('𝓗𝓪𝓹𝓹𝔂 𝓑𝓲𝓻𝓽𝓱𝓭𝓪𝔂 𝟐𝟎𝟐𝟔'));
    });

    test('getNotificationTitle returns clean sender or group title without extra banners', () {
      final personal = WishHelper.getNotificationTitle(
        senderName: 'Shadow',
        text: 'Happy Birthday Queen! 🎂',
      );
      expect(personal, equals('Shadow'));

      final group = WishHelper.getNotificationTitle(
        senderName: 'Shadow',
        groupName: 'Queen Pooja Queendom',
        text: 'Happy Birthday Queen! 🎂',
      );
      expect(group, equals('Queen Pooja Queendom'));
    });

    test('getNotificationBody formats body in royal script calligraphy without extra labels', () {
      final body = WishHelper.getNotificationBody(
        senderName: 'Shadow',
        text: 'Happy Birthday',
      );
      expect(body, equals('𝓗𝓪𝓹𝓹𝔂 𝓑𝓲𝓻𝓽𝓱𝓭𝓪𝔂'));
      expect(body, isNot(contains('“')));
      expect(body, isNot(contains('Proclamation')));
    });

    test('getBubbleRadius provides stately Imperial Proclamation Arch shape', () {
      final sentRadius = WishHelper.getBubbleRadius(isMe: true);
      final receivedRadius = WishHelper.getBubbleRadius(isMe: false);

      // Sent Imperial Proclamation Arch (Romanesque arch top, tailored anchor bottom-right)
      expect(sentRadius.topLeft.x, equals(26.0));
      expect(sentRadius.topRight.x, equals(26.0));
      expect(sentRadius.bottomLeft.x, equals(18.0));
      expect(sentRadius.bottomRight.x, equals(5.0));

      // Received Imperial Proclamation Arch (Romanesque arch top, tailored anchor bottom-left)
      expect(receivedRadius.topLeft.x, equals(26.0));
      expect(receivedRadius.topRight.x, equals(26.0));
      expect(receivedRadius.bottomLeft.x, equals(5.0));
      expect(receivedRadius.bottomRight.x, equals(18.0));
    });

    test('getBubbleGradient returns identical opulent Rich Antique Royal Gold gradient for both sender and receiver', () {
      final senderGradient = WishHelper.getBubbleGradient(
        isMe: true,
        text: 'Happy Birthday! 🎂',
      );
      final receiverGradient = WishHelper.getBubbleGradient(
        isMe: false,
        text: 'Happy Birthday! 🎂',
      );

      // Verify both sender and receiver have the exact same rich antique gold colors
      expect(senderGradient.colors, equals(receiverGradient.colors));
      expect(senderGradient.colors.first, equals(const Color(0xFFA17724).withValues(alpha: 0.55)));
      expect(senderGradient.colors[1], equals(const Color(0xFF785412).withValues(alpha: 0.60)));
      expect(senderGradient.colors.last, equals(const Color(0xFF503506).withValues(alpha: 0.68)));
    });

    test('getInnerBubbleRadius provides proportional inset arch radius', () {
      final innerSent = WishHelper.getInnerBubbleRadius(isMe: true);
      expect(innerSent.topLeft.x, equals(22.5));
      expect(innerSent.topRight.x, equals(22.5));
      expect(innerSent.bottomLeft.x, equals(14.5));
      expect(innerSent.bottomRight.x, equals(2.0));
    });

    test('getWishTextStyle returns Cormorant Garamond aristocratic serif font', () {
      final style = WishHelper.getWishTextStyle();
      expect(style.fontFamily, contains('CormorantGaramond'));
      expect(style.fontStyle, equals(FontStyle.italic));
      expect(style.fontWeight, equals(FontWeight.w700));
      expect(style.color, equals(const Color(0xFFFFF9E8)));
    });
  });

  group('WishBubbleContentWidget UI Tests', () {
    testWidgets('renders wish bubble with distinct font, dual filigree border and NO extra text', (tester) async {
      const wishText = 'Wishing Her Supreme Royal Majesty Queen Pooja an extraordinary day! 🎂✨';
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: WishBubbleContentWidget(
              text: wishText,
              date: '10:30 AM',
              isMe: true,
              deliveryStatus: MessageDeliveryStatus.delivered,
            ),
          ),
        ),
      );

      // Verify custom painter for dual filigree border is present
      expect(find.byType(CustomPaint), findsWidgets);

      // Verify wish message text and timestamp exist
      expect(find.text(wishText), findsOneWidget);
      expect(find.text('10:30 AM'), findsOneWidget);

      // Verify NO extra text / decorative headers / quote glyphs exist
      expect(find.text('ROYAL BIRTHDAY PROCLAMATION'), findsNothing);
      expect(find.text('Offered by'), findsNothing);
      expect(find.text('“'), findsNothing);
      expect(find.text('”'), findsNothing);
      expect(find.text('✦ ❖ ✦'), findsNothing);
      expect(find.text('🎉 Celebration Proclamation'), findsNothing);

      // Verify text widget uses Cormorant Garamond font style
      final textWidget = tester.widget<Text>(find.text(wishText));
      expect(textWidget.style?.fontFamily, contains('CormorantGaramond'));
      expect(textWidget.style?.fontStyle, equals(FontStyle.italic));
    });

    testWidgets('renders received wish message cleanly without sender label', (tester) async {
      const wishText = '🙇🏻‍♂️ Hail Her Supreme Royal Majesty Queen Pooja 🙇🏻‍♂️';
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: WishBubbleContentWidget(
              text: wishText,
              date: '11:15 AM',
              isMe: false,
              senderName: 'Worshipper Alex',
            ),
          ),
        ),
      );

      // Verify message and timestamp
      expect(find.text(wishText), findsOneWidget);
      expect(find.text('11:15 AM'), findsOneWidget);

      // Verify NO extra attribution or header text
      expect(find.text('DIVINE SANCTUARY DEVOTION'), findsNothing);
      expect(find.text('Offered by Worshipper Alex'), findsNothing);
      expect(find.text('🙇🏻‍♂️ Sacred Sanctuary Offering'), findsNothing);
    });
  });

  group('Wish Reply Tests', () {
    testWidgets('DisplayMessages renders wish type without falling back to unsupported', (tester) async {
      const wishText = 'Wishing you joy and grace! 🎂';
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DisplayMessages(
              message: wishText,
              messageType: 'wish',
              isPreviewable: false,
            ),
          ),
        ),
      );

      expect(find.text(wishText), findsOneWidget);
      expect(find.text('Unsupported message type'), findsNothing);
    });

    testWidgets('MessageReplyPreview renders wish reply preview with text and not blank', (tester) async {
      const wishText = 'Happy Birthday to Her Royal Majesty! 👑';
      final container = ProviderContainer(
        overrides: [
          messageReplyProvider.overrideWith(
            (ref) => MessageReply(
              message: wishText,
              isMe: false,
              messageType: 'wish',
              fileMessageData: '',
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: MessageReplyPreview(),
            ),
          ),
        ),
      );

      expect(find.text(wishText), findsOneWidget);
      expect(find.text('Royal wish'), findsOneWidget);
    });
  });
}
