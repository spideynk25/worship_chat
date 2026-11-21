import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_chat/common/utils/app_capabilities.dart';
import 'package:worship_chat/features/group/controller/group_gallery_controller.dart';
import 'package:worship_chat/features/group/repository/group_gallery_repository.dart';
import 'package:worship_chat/features/group/screens/group_gallery_screen.dart';
import 'package:worship_chat/features/group/screens/slide_show_screen.dart';
import 'package:worship_chat/models/group_gallery_image.dart';

class FakeGroupGalleryRepository extends Fake
    implements GroupGalleryRepository {
  final Stream<List<GroupGalleryImage>> stream;
  FakeGroupGalleryRepository(this.stream);

  @override
  Stream<List<GroupGalleryImage>> getGalleryStream(String groupId) => stream;

  @override
  Future<int> getGalleryCount(String groupId) async => 0;

  @override
  Future<int> uploadImages({
    required String groupId,
    required List<File> imageFiles,
    required String uploaderName,
    String? caption,
    void Function(int uploaded, int total)? onProgress,
  }) async =>
      0;

  @override
  Future<int> uploadVideos({
    required String groupId,
    required List<File> videoFiles,
    required String uploaderName,
    String? caption,
    void Function(int uploaded, int total)? onProgress,
  }) async =>
      0;

  @override
  Future<void> deleteImage(String groupId, String imageId) async {}

  @override
  Future<bool> addGalleryImageFromUrl({
    required String groupId,
    required String imageUrl,
    required String uploaderName,
    String? caption,
  }) async =>
      true;
}

void main() {
  tearDown(() => AppCapabilities.debugOverride = null);

  final sampleImages = [
    GroupGalleryImage(
      imageId: 'img_1',
      groupId: 'grp_1',
      imageUrl: 'https://example.com/pic1.jpg',
      uploadedBy: 'u1',
      uploadedByName: 'Alice',
      uploadedAt: DateTime(2026, 1, 1),
    ),
    GroupGalleryImage(
      imageId: 'img_2',
      groupId: 'grp_1',
      imageUrl: 'https://example.com/pic2.jpg',
      uploadedBy: 'u2',
      uploadedByName: 'Bob',
      uploadedAt: DateTime(2026, 1, 2),
    ),
  ];

  testWidgets(
    'Download ZIP button appears when gallery has photos and opens confirmation dialog',
    (tester) async {
      final repo = FakeGroupGalleryRepository(Stream.value(sampleImages));
      final controller = GroupGalleryController(repository: repo);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            groupGalleryControllerProvider.overrideWithValue(controller),
          ],
          child: const MaterialApp(
            home: GroupGalleryScreen(
              groupId: 'grp_1',
              groupName: 'Queen Pooja Queendom',
              accentColor: Colors.amber,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify action buttons
      final downloadBtn = find.byTooltip('Download all as ZIP');
      expect(downloadBtn, findsOneWidget);
      expect(find.byIcon(Icons.download_rounded), findsOneWidget);

      final slideshowBtn = find.byTooltip('Slideshow');
      expect(slideshowBtn, findsOneWidget);
      expect(find.byIcon(Icons.slideshow_rounded), findsOneWidget);
      expect(find.byTooltip('Download all images as GIF'), findsNothing);

      // Tap the download button
      await tester.tap(downloadBtn);
      await tester.pumpAndSettle();

      // Confirmation dialog should be displayed
      expect(find.text('Download Gallery'), findsOneWidget);
      expect(
        find.text(
          'Download all 2 photos from Queen Pooja Queendom as a ZIP archive?',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Includes original high-quality photos'),
        findsOneWidget,
      );
      expect(find.text('Download ZIP'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      // Tapping Cancel dismisses the dialog
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Download Gallery'), findsNothing);
    },
  );

  testWidgets(
    'Download ZIP button is omitted when gallery has no photos',
    (tester) async {
      final repo = FakeGroupGalleryRepository(Stream.value([]));
      final controller = GroupGalleryController(repository: repo);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            groupGalleryControllerProvider.overrideWithValue(controller),
          ],
          child: const MaterialApp(
            home: GroupGalleryScreen(
              groupId: 'grp_empty',
              groupName: 'Empty Sanctuary',
              accentColor: Colors.purple,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Download ZIP and slideshow should not be rendered for empty gallery
      expect(find.byTooltip('Download all as ZIP'), findsNothing);
      expect(find.byTooltip('Slideshow'), findsNothing);
      expect(find.byTooltip('Download all images as GIF'), findsNothing);
      expect(find.text('No photos yet'), findsOneWidget);
    },
  );

  testWidgets(
    'Slideshow action button opens SlideshowScreen with gallery photos',
    (tester) async {
      final fakePhotos = [
        GroupGalleryImage(
          imageId: 'img1',
          groupId: 'grp_123',
          imageUrl: 'https://example.com/pooja1.jpg',
          uploadedBy: 'admin',
          uploadedByName: 'Admin',
          uploadedAt: DateTime.now(),
        ),
      ];

      final repo = FakeGroupGalleryRepository(Stream.value(fakePhotos));
      final controller = GroupGalleryController(repository: repo);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            groupGalleryControllerProvider.overrideWithValue(controller),
          ],
          child: const MaterialApp(
            home: GroupGalleryScreen(
              groupId: 'grp_123',
              groupName: 'Queen Pooja Queendom',
              accentColor: Colors.amber,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final slideshowBtn = find.byTooltip('Slideshow');
      expect(slideshowBtn, findsOneWidget);

      await tester.tap(slideshowBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Should have navigated to SlideshowScreen
      expect(find.byType(SlideshowScreen), findsOneWidget);
    },
  );
}
