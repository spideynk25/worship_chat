import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_chat/common/utils/app_capabilities.dart';
import 'package:worship_chat/features/group/controller/group_gallery_controller.dart';
import 'package:worship_chat/features/group/repository/group_gallery_repository.dart';
import 'package:worship_chat/features/group/screens/group_gallery_screen.dart';
import 'package:worship_chat/models/group_gallery_image.dart';

class FakeGroupGalleryVideoRepository extends Fake
    implements GroupGalleryRepository {
  final Stream<List<GroupGalleryImage>> stream;
  int uploadVideosCallCount = 0;
  List<File>? lastUploadedVideoFiles;

  FakeGroupGalleryVideoRepository(this.stream);

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
      imageFiles.length;

  @override
  Future<int> uploadVideos({
    required String groupId,
    required List<File> videoFiles,
    required String uploaderName,
    String? caption,
    void Function(int uploaded, int total)? onProgress,
  }) async {
    uploadVideosCallCount++;
    lastUploadedVideoFiles = videoFiles;
    return videoFiles.length;
  }

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
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => AppCapabilities.debugOverride = null);

  final sampleMedia = [
    GroupGalleryImage(
      imageId: 'img_1',
      groupId: 'grp_1',
      imageUrl: 'https://example.com/photo1.jpg',
      uploadedBy: 'u1',
      uploadedByName: 'Alice',
      uploadedAt: DateTime(2026, 1, 1),
      mediaType: 'image',
    ),
    GroupGalleryImage(
      imageId: 'img_2',
      groupId: 'grp_1',
      imageUrl: 'https://example.com/photo2.png',
      uploadedBy: 'u2',
      uploadedByName: 'Bob',
      uploadedAt: DateTime(2026, 1, 2),
      mediaType: 'image',
    ),
    GroupGalleryImage(
      imageId: 'vid_1',
      groupId: 'grp_1',
      imageUrl: 'https://example.com/clip1.mp4',
      uploadedBy: 'u3',
      uploadedByName: 'Charlie',
      uploadedAt: DateTime(2026, 1, 3),
      mediaType: 'video',
    ),
  ];

  group('GroupGalleryImage mediaType & video detection', () {
    test('correctly identifies video vs image by mediaType and URL extension', () {
      final img = GroupGalleryImage(
        imageId: '1',
        groupId: 'g',
        imageUrl: 'https://example.com/photo.jpg',
        uploadedBy: 'u',
        uploadedByName: 'User',
        uploadedAt: DateTime(2026, 1, 1),
      );
      expect(img.isImage, isTrue);
      expect(img.isVideo, isFalse);
      expect(img.mediaType, 'image');

      final videoByProp = GroupGalleryImage(
        imageId: '2',
        groupId: 'g',
        imageUrl: 'https://example.com/media123',
        uploadedBy: 'u',
        uploadedByName: 'User',
        uploadedAt: DateTime(2026, 1, 1),
        mediaType: 'video',
      );
      expect(videoByProp.isVideo, isTrue);
      expect(videoByProp.isImage, isFalse);

      final videoByExtension = GroupGalleryImage(
        imageId: '3',
        groupId: 'g',
        imageUrl: 'https://res.cloudinary.com/demo/video/upload/sample.mp4',
        uploadedBy: 'u',
        uploadedByName: 'User',
        uploadedAt: DateTime(2026, 1, 1),
      );
      expect(videoByExtension.isVideo, isTrue);
      expect(videoByExtension.isImage, isFalse);
    });

    test('serializes and deserializes mediaType correctly in toMap / fromMap', () {
      final orig = GroupGalleryImage(
        imageId: 'v1',
        groupId: 'g1',
        imageUrl: 'https://example.com/video.mp4',
        uploadedBy: 'u1',
        uploadedByName: 'Creator',
        uploadedAt: DateTime(2026, 1, 1),
        mediaType: 'video',
      );
      final map = orig.toMap();
      expect(map['mediaType'], 'video');

      final restored = GroupGalleryImage.fromMap(map);
      expect(restored.mediaType, 'video');
      expect(restored.isVideo, isTrue);
    });

    test('copyWith updates mediaType', () {
      final item = GroupGalleryImage(
        imageId: 'i1',
        groupId: 'g1',
        imageUrl: 'https://example.com/file',
        uploadedBy: 'u1',
        uploadedByName: 'Name',
        uploadedAt: DateTime(2026, 1, 1),
      );
      final updated = item.copyWith(mediaType: 'video');
      expect(updated.mediaType, 'video');
      expect(updated.isVideo, isTrue);
    });
  });

  group('GroupGalleryController uploadVideos', () {
    test('calls repository uploadVideos and returns uploaded count', () async {
      final repo = FakeGroupGalleryVideoRepository(Stream.value([]));
      final controller = GroupGalleryController(repository: repo);

      final result = await controller.uploadVideos(
        groupId: 'grp_1',
        videoFiles: [File('/fake/vid1.mp4'), File('/fake/vid2.mov')],
        uploaderName: 'Tester',
      );

      expect(result, 2);
      expect(repo.uploadVideosCallCount, 1);
      expect(repo.lastUploadedVideoFiles?.length, 2);
    });
  });

  group('GroupGalleryScreen Photos and Videos tabs', () {
    testWidgets('displays Photos and Videos tabs with separate counts', (tester) async {
      final repo = FakeGroupGalleryVideoRepository(Stream.value(sampleMedia));
      final controller = GroupGalleryController(repository: repo);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            groupGalleryControllerProvider.overrideWithValue(controller),
          ],
          child: const MaterialApp(
            home: GroupGalleryScreen(
              groupId: 'grp_1',
              groupName: 'Queen Gallery',
              accentColor: Colors.deepPurple,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check Tabs exist
      expect(find.text('Photos'), findsOneWidget);
      expect(find.text('Videos'), findsOneWidget);

      // Photos tab count = 2, Videos tab count = 1
      expect(find.text('2'), findsWidgets);
      expect(find.text('1'), findsWidgets);

      // Photos tab is active by default; FAB shows Add Photos
      expect(find.text('Add Photos'), findsOneWidget);

      // Tap the Videos tab
      await tester.tap(find.text('Videos'));
      await tester.pumpAndSettle();

      // Videos tab is now active; FAB updates to Add Videos
      expect(find.text('Add Videos'), findsOneWidget);

      // Video items display VIDEO badge
      expect(find.text('VIDEO'), findsOneWidget);
      expect(find.byIcon(Icons.videocam_rounded), findsWidgets);
    });

    testWidgets('shows No videos yet empty state when there are photos but no videos', (tester) async {
      final photosOnly = [
        GroupGalleryImage(
          imageId: 'img_1',
          groupId: 'grp_1',
          imageUrl: 'https://example.com/photo1.jpg',
          uploadedBy: 'u1',
          uploadedByName: 'Alice',
          uploadedAt: DateTime(2026, 1, 1),
          mediaType: 'image',
        ),
      ];

      final repo = FakeGroupGalleryVideoRepository(Stream.value(photosOnly));
      final controller = GroupGalleryController(repository: repo);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            groupGalleryControllerProvider.overrideWithValue(controller),
          ],
          child: const MaterialApp(
            home: GroupGalleryScreen(
              groupId: 'grp_1',
              groupName: 'Queen Gallery',
              accentColor: Colors.teal,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap Videos tab
      await tester.tap(find.text('Videos'));
      await tester.pumpAndSettle();

      // Empty state for videos
      expect(find.text('No videos yet'), findsOneWidget);
      expect(find.text('Add Videos'), findsWidgets);
    });
  });
}

