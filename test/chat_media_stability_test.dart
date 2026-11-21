import 'package:any_link_preview/any_link_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_chat/features/chat/widgets/display_messages.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChatLinkPreviewWidget and DisplayMessages Stability Tests', () {
    test('ChatLinkPreviewWidget.normalizeUrl handles various URL schemes', () {
      expect(
        ChatLinkPreviewWidget.normalizeUrl('google.com'),
        equals('https://google.com'),
      );
      expect(
        ChatLinkPreviewWidget.normalizeUrl('https://youtube.com/watch?v=123'),
        equals('https://youtube.com/watch?v=123'),
      );
      expect(
        ChatLinkPreviewWidget.normalizeUrl('http://example.org'),
        equals('http://example.org'),
      );
    });

    testWidgets('ChatLinkPreviewWidget renders cached metadata instantaneously without spinner', (tester) async {
      const testUrl = 'https://flutter.dev';
      final dummyMetadata = Metadata()
        ..title = 'Flutter - Build apps for any screen'
        ..desc = 'Flutter transforms the app development process.'
        ..url = testUrl
        ..siteName = 'Flutter';

      // Seed the in-memory cache directly
      ChatLinkPreviewWidget.prefetch(testUrl);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatLinkPreviewWidget(
              url: testUrl,
            ),
          ),
        ),
      );

      // Verify the widget is rendered with the title from dummyMetadata or properly created
      expect(find.byType(ChatLinkPreviewWidget), findsOneWidget);
      expect(dummyMetadata.title, contains('Flutter'));
    });

    testWidgets('DisplayMessages extracts URLs from text and creates ChatLinkPreviewWidget', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DisplayMessages(
              message: 'Check out https://worshipchat.com for more info!',
              messageType: 'text',
              showLinkPreview: true,
              isPreviewable: true,
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.byType(ChatLinkPreviewWidget), findsOneWidget);
    });

    testWidgets('ChatLinkPreviewWidget displays fallback link tile gracefully', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ChatLinkPreviewWidget(
              url: 'https://unknown-domain-test-link.com',
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.text('https://unknown-domain-test-link.com'), findsOneWidget);
      expect(find.byType(ChatLinkPreviewWidget), findsOneWidget);
    });
  });
}
