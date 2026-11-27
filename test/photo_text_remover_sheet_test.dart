import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:worship_chat/common/widgets/photo_text_remover_sheet.dart';
import 'package:worship_chat/features/bookmark/screens/bookmark_screen.dart';
import 'package:worship_chat/features/group/screens/slide_show_screen.dart';
import 'package:worship_chat/features/group/services/gallery_media_service.dart';
import 'package:worship_chat/models/bookmark_model.dart';
import 'package:worship_chat/models/group_gallery_image.dart';

Uint8List _solidPng({int r = 10, int g = 20, int b = 30}) {
  final image = img.Image(width: 16, height: 16);
  for (int y = 0; y < 16; y++) {
    for (int x = 0; x < 16; x++) {
      image.setPixelRgba(x, y, r, g, b, 255);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('text_remover_sheet_test_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('PhotoTextRemoverSheet end-to-end workflows', () {
    testWidgets(
        'local gallery flow opens editor, offers Overwrite/Save Copy, and overwrites file',
        (tester) async {
      final originalFile = File(p.join(tempDir.path, 'deity_photo.png'))
        ..writeAsBytesSync(_solidPng(r: 200, g: 20, b: 20));
      final cleanedFile = File(p.join(tempDir.path, 'deity_photo_clean.png'))
        ..writeAsBytesSync(_solidPng(r: 20, g: 220, b: 80));

      File? callbackUpdated;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () {
                    PhotoTextRemoverSheet.open(
                      ctx,
                      origin: PhotoTextRemoverOrigin.localGallery,
                      localPath: originalFile.path,
                      groupName: 'Local Shrine',
                      title: 'deity_photo.png',
                      onLocalFileUpdated: (f) => callbackUpdated = f,
                      studioBuilderOverride: (_) => Builder(
                        builder: (studioCtx) => Scaffold(
                          body: ElevatedButton(
                            onPressed: () =>
                                Navigator.pop(studioCtx, cleanedFile),
                            child: const Text('Finish Studio'),
                          ),
                        ),
                      ),
                    );
                  },
                  child: const Text('Launch Remover'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Launch Remover'));
      await tester.pumpAndSettle();

      expect(find.text('Finish Studio'), findsOneWidget);
      await tester.tap(find.text('Finish Studio'));
      await tester.pumpAndSettle();

      expect(find.text('Text Removed'), findsOneWidget);
      expect(find.text('Save to Device'), findsOneWidget);
      expect(find.text('Overwrite Original File'), findsOneWidget);
      expect(find.text('Save Copy in Folder'), findsOneWidget);

      await tester.tap(find.text('Overwrite Original File'));
      await tester.pump();
      for (int i = 0; i < 20 && callbackUpdated == null; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(callbackUpdated?.path, originalFile.path);
      expect(
        originalFile.readAsBytesSync(),
        equals(cleanedFile.readAsBytesSync()),
      );
      expect(find.text('✅ Updated original photo cleanly'), findsOneWidget);
    });

    testWidgets(
        'group gallery flow supports Edit Again loop and gallery upload destination',
        (tester) async {
      final sourceFile = File(p.join(tempDir.path, 'source.png'))
        ..writeAsBytesSync(_solidPng(r: 100, g: 100, b: 100));
      final pass1File = File(p.join(tempDir.path, 'pass1.png'))
        ..writeAsBytesSync(_solidPng(r: 10, g: 120, b: 200));
      final pass2File = File(p.join(tempDir.path, 'pass2.png'))
        ..writeAsBytesSync(_solidPng(r: 10, g: 240, b: 240));

      final studioInputs = <String>[];
      File? uploadedToGroup;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () {
                    PhotoTextRemoverSheet.open(
                      ctx,
                      origin: PhotoTextRemoverOrigin.groupGallery,
                      imageUrl: 'https://cdn.example.com/gallery/photo.jpg',
                      groupId: 'grp_pooja_1',
                      groupName: 'Queen Pooja Court',
                      sourceImageId: 'img_1',
                      title: 'Royal Shot',
                      resolveFileOverride: () async => sourceFile,
                      saveToGroupOverride: (f) async {
                        uploadedToGroup = f;
                        return true;
                      },
                      saveToBookmarksOverride: (_) async => true,
                      studioBuilderOverride: (input) {
                        studioInputs.add(input.path);
                        final result = studioInputs.length == 1
                            ? pass1File
                            : pass2File;
                        return Builder(
                          builder: (studioCtx) => Scaffold(
                            body: ElevatedButton(
                              onPressed: () =>
                                  Navigator.pop(studioCtx, result),
                              child: Text('Complete Pass ${studioInputs.length}'),
                            ),
                          ),
                        );
                      },
                    );
                  },
                  child: const Text('Open Group Remover'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Group Remover'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Complete Pass 1'));
      await tester.pumpAndSettle();

      expect(find.text('Save as New Photo in Gallery'), findsOneWidget);
      expect(find.text('Replace Original in Gallery'), findsOneWidget);
      expect(find.text('Save to Bookmarks'), findsOneWidget);

      await tester.tap(find.text('Edit Again'));
      await tester.pumpAndSettle();

      expect(studioInputs, [sourceFile.path, pass1File.path]);
      await tester.tap(find.text('Complete Pass 2'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save as New Photo in Gallery'));
      await tester.pumpAndSettle();

      expect(uploadedToGroup?.path, pass2File.path);
      expect(find.text('✅ Saved cleaned photo to Gallery'), findsOneWidget);
    });
  });

  group('Remove Text visibility in Gallery & Bookmarks viewers', () {
    testWidgets('SlideshowScreen shows Remove Text for photos and hides it for videos',
        (tester) async {
      final photoSlide = GroupGalleryImage(
        imageId: 'img_1',
        groupId: 'grp_1',
        imageUrl: p.join(tempDir.path, 'missing_photo.jpg'),
        uploadedBy: 'u1',
        uploadedByName: 'Tester',
        uploadedAt: DateTime(2026, 11, 27),
        mediaType: 'image',
      );
      final videoSlide = GroupGalleryImage(
        imageId: 'vid_1',
        groupId: 'grp_1',
        imageUrl: p.join(tempDir.path, 'sample.mp4'),
        uploadedBy: 'u1',
        uploadedByName: 'Tester',
        uploadedAt: DateTime(2026, 11, 27),
        mediaType: 'video',
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: SlideshowScreen(
              images: [photoSlide, videoSlide],
              initialIndex: 0,
              accentColor: Colors.amber,
              groupName: 'Test Gallery',
            ),
          ),
        ),
      );

      // Slideshow overlay is visible on initial frame and exposes Remove Text for photo slides.
      await tester.pump();
      expect(find.byTooltip('Remove Text'), findsOneWidget);

      // Verify PhotoLightboxViewer shows Remove Text for photos and hides it for videos.
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: PhotoLightboxViewer(
              photo: photoSlide,
              groupName: 'Test Gallery',
              accentColor: Colors.amber,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byTooltip('Remove Text'), findsOneWidget);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: PhotoLightboxViewer(
              photo: videoSlide,
              groupName: 'Test Gallery',
              accentColor: Colors.amber,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byTooltip('Remove Text'), findsNothing);
    });

    testWidgets('BookmarkFullscreenViewer shows Remove Text action in toolbar',
        (tester) async {
      final bm = BookmarkModel(
        bookmarkId: 'bm_1',
        userId: 'user_1',
        userName: 'Pooja',
        userProfilePic: '',
        imageUrl: 'https://example.com/bm1.jpg',
        groupId: 'grp_1',
        groupName: 'Sanctuary',
        bookmarkedAt: DateTime(2026, 11, 27),
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: BookmarkFullscreenViewer(
              bookmarks: [bm],
              initialIndex: 0,
              currentUserId: 'user_1',
              isOwner: true,
              sourceCollectionId: 'col_1',
              onRemove: (_) async {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byTooltip('Remove Text'), findsOneWidget);
      expect(find.byTooltip('Set as Profile Pic'), findsOneWidget);
    });

    test('GalleryMediaService.saveLocalImageFile saves local image bytes via override',
        () async {
      final src = File(p.join(tempDir.path, 'cleaned.jpg'))
        ..writeAsBytesSync(_solidPng(r: 50, g: 160, b: 220));
      String? savedName;
      Uint8List? savedBytes;

      final media = GalleryMediaService(
        saveFile: (name, bytes) async {
          savedName = name;
          savedBytes = bytes;
          return Uri.file(p.join(tempDir.path, name));
        },
        saveToAlbum: (_) async => true,
      );

      final res = await media.saveLocalImageFile(
        imageFile: src,
        fileName: 'cleaned_test.jpg',
      );
      expect(res, GallerySaveResult.saved);
      if (media.isDesktop) {
        expect(savedName, 'cleaned_test.jpg');
        expect(savedBytes, isNotEmpty);
      }
    });
  });
}
