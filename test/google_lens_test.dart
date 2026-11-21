import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_chat/common/utils/google_lens_service.dart';
import 'package:worship_chat/features/chat/widgets/display_messages.dart';
import 'package:worship_chat/features/chat/widgets/message_reaction_dialog.dart';
import 'package:worship_chat/features/group/screens/folder_gallery_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GoogleLensService tests', () {
    test('buildLensWebUrl builds encoded URL correctly', () {
      const imageUrl = 'https://res.cloudinary.com/worship/image/upload/v1/temple.jpg';
      final lensUrl = GoogleLensService.buildLensWebUrl(imageUrl);
      expect(lensUrl, startsWith('https://lens.google.com/uploadbyurl?url='));
      expect(lensUrl, contains(Uri.encodeComponent(imageUrl)));
    });

    testWidgets('GoogleLensIcon renders correctly in multi-color and monochrome', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                GoogleLensIcon(size: 24),
                GoogleLensIcon(size: 32, color: Colors.white, useGoogleColors: false),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(GoogleLensIcon), findsNWidgets(2));
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('search returns false when no valid url or local file exists', (tester) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    result = await GoogleLensService.search(
                      context: context,
                      imageUrl: '',
                      localPath: '/non/existent/path.jpg',
                      showFeedback: false,
                    );
                  },
                  child: const Text('Search Lens'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Search Lens'));
      await tester.pumpAndSettle();

      expect(result, isFalse);
    });
  });

  group('Chats integration tests', () {
    testWidgets('MediaPreviewWidget displays Google Lens action button for images', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaPreviewWidget(
            mediaType: 'image',
            mediaUrl: 'https://example.com/test_image.jpg',
            showAppBar: true,
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Should find the Google Lens icon button with its tooltip
      expect(find.byTooltip('Search with Google Lens'), findsOneWidget);
      expect(find.byType(GoogleLensIcon), findsOneWidget);
    });

    testWidgets('MessageReactionDialog shows Lens action when onGoogleLens callback is provided', (tester) async {
      bool lensTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    MessageReactionDialog.show(
                      context: context,
                      targetRect: const Rect.fromLTWH(100, 100, 200, 60),
                      currentUserId: 'user1',
                      reactions: {},
                      onReactionSelected: (_) {},
                      onGoogleLens: () {
                        lensTapped = true;
                      },
                    );
                  },
                  child: const Text('Show Menu'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Menu'));
      await tester.pumpAndSettle();

      expect(find.text('Lens'), findsOneWidget);
      expect(find.byType(GoogleLensIcon), findsOneWidget);

      await tester.tap(find.text('Lens'));
      await tester.pumpAndSettle();

      expect(lensTapped, isTrue);
    });
  });

  group('Gallery and Slideshow integration tests', () {
    testWidgets('FolderGalleryScreen fullscreen viewer displays Google Lens button', (tester) async {
      final tempDir = Directory.systemTemp.createTempSync('lens_test_dir_');
      final testPhoto = File('${tempDir.path}/goddess.jpg');
      testPhoto.writeAsBytesSync([255, 216, 255, 217]);

      await tester.pumpWidget(
        MaterialApp(
          home: ProviderScope(
            child: FolderGalleryScreen(
              initialFolderPath: tempDir.path,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Tap photo to open fullscreen viewer
      await tester.tap(find.byKey(ValueKey('grid_photo_${testPhoto.path}')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byTooltip('Search with Google Lens'), findsOneWidget);
      expect(find.byType(GoogleLensIcon), findsOneWidget);

      tempDir.deleteSync(recursive: true);
    });
  });
}
