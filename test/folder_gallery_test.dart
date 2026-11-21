import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worship_chat/features/group/screens/folder_gallery_screen.dart';
import 'package:worship_chat/features/group/screens/slide_show_screen.dart';
import 'package:worship_chat/features/group/services/recent_folders_service.dart';

void main() {
  late Directory tempDir;
  late File fileA;
  late File fileB;
  late File fileC;
  late File nonImageFile;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RecentFoldersService.setMockPrefs(null);

    tempDir = Directory.systemTemp.createTempSync('folder_gallery_test_');
    fileA = File('${tempDir.path}/a_pooja.jpg');
    fileB = File('${tempDir.path}/b_rashmika.png');
    fileC = File('${tempDir.path}/c_temple.webp');
    nonImageFile = File('${tempDir.path}/notes.txt');

    fileA.writeAsBytesSync([255, 216, 255, 217]);
    fileB.writeAsBytesSync([137, 80, 78, 71]);
    fileC.writeAsBytesSync([82, 73, 70, 70]);
    nonImageFile.writeAsStringSync('hello world');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  testWidgets(
    'FolderGalleryScreen renders photos from folder with count badge and actions',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ProviderScope(
            child: FolderGalleryScreen(
              initialFolderPath: tempDir.path,
              accentColor: Colors.amber,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify folder count badge shows 3 (ignoring notes.txt)
      expect(find.text('3'), findsOneWidget);
      expect(find.text('3 Photos'), findsOneWidget);

      // Verify action buttons exist in AppBar
      expect(find.byTooltip('Start slideshow'), findsOneWidget);
      expect(find.byTooltip('Shuffle photos'), findsOneWidget);
      expect(find.byTooltip('Open different folder'), findsOneWidget);

      // Tap Shuffle button
      await tester.tap(find.byTooltip('Shuffle photos'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Shuffled state should show "Shuffle again" and "Restore order"
      expect(find.byTooltip('Shuffle again'), findsOneWidget);
      expect(find.byTooltip('Restore order'), findsOneWidget);

      // Tap Restore order
      await tester.tap(find.byTooltip('Restore order'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byTooltip('Shuffle photos'), findsOneWidget);
      expect(find.byTooltip('Restore order'), findsNothing);
    },
  );

  testWidgets(
    'FolderGalleryScreen shows empty state when directory has no image files',
    (tester) async {
      final emptyDir = Directory.systemTemp.createTempSync('empty_gallery_test_');

      await tester.pumpWidget(
        MaterialApp(
          home: ProviderScope(
            child: FolderGalleryScreen(
              initialFolderPath: emptyDir.path,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('No photos found in this folder'), findsOneWidget);
      expect(find.text('Open Another Folder'), findsOneWidget);
      expect(find.byTooltip('Start slideshow'), findsNothing);

      emptyDir.deleteSync(recursive: true);
    },
  );

  testWidgets(
    'Tapping Start Slideshow navigates to SlideshowScreen with local photos',
    (tester) async {
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

      final slideshowBtn = find.byTooltip('Start slideshow');
      expect(slideshowBtn, findsOneWidget);

      await tester.tap(slideshowBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(SlideshowScreen), findsOneWidget);
    },
  );

  test('resolveActualDirectoryPath properly sanitizes Android SAF & encoded paths', () {
    expect(
      resolveActualDirectoryPath('/storage/raw//storage/emulated/0/Download/WorshipChat'),
      '/storage/emulated/0/Download/WorshipChat',
    );
    expect(
      resolveActualDirectoryPath('raw:/storage/emulated/0/Download/WorshipChat'),
      '/storage/emulated/0/Download/WorshipChat',
    );
    expect(
      resolveActualDirectoryPath('/storage/emulated/0/Download/Worship%20Chat'),
      '/storage/emulated/0/Download/Worship Chat',
    );
    expect(
      resolveActualDirectoryPath('content://com.android.externalstorage.documents/tree/primary%3ADownload%2FWorshipChat'),
      '/storage/emulated/0/Download/WorshipChat',
    );
    expect(
      resolveActualDirectoryPath('file:///storage/emulated/0/Download/WorshipChat'),
      '/storage/emulated/0/Download/WorshipChat',
    );
  });

  testWidgets(
    'FolderGalleryScreen finds photos inside extracted subfolders (simulating zip extraction)',
    (tester) async {
      final parentDir = Directory.systemTemp.createTempSync('parent_extracted_');
      final subDir = Directory('${parentDir.path}/Queen_Poojas_Queendom_gallery');
      subDir.createSync(recursive: true);

      final photo1 = File('${subDir.path}/Queen_001.jpg');
      final photo2 = File('${subDir.path}/Queen_002.png');
      photo1.writeAsBytesSync([255, 216, 255, 217]);
      photo2.writeAsBytesSync([137, 80, 78, 71]);

      await tester.pumpWidget(
        MaterialApp(
          home: ProviderScope(
            child: FolderGalleryScreen(
              initialFolderPath: parentDir.path,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Both photos from the subfolder should be discovered
      expect(find.text('2'), findsOneWidget);
      expect(find.text('2 Photos'), findsOneWidget);

      parentDir.deleteSync(recursive: true);
    },
  );

  testWidgets(
    'FolderGalleryScreen automatically unpacks and displays photos from a .zip file path',
    (tester) async {
      final zipDir = Directory.systemTemp.createTempSync('zip_file_test_');
      final zipFile = File('${zipDir.path}/Queen_Pooja_gallery.zip');

      final archive = Archive();
      final photoData = [255, 216, 255, 224, 0, 16];
      archive.addFile(ArchiveFile('Queen_001.jpg', photoData.length, photoData));
      archive.addFile(ArchiveFile('Queen_002.png', photoData.length, photoData));
      final zipBytes = ZipEncoder().encode(archive);
      zipFile.writeAsBytesSync(zipBytes);

      await tester.pumpWidget(
        MaterialApp(
          home: ProviderScope(
            child: FolderGalleryScreen(
              initialFolderPath: zipFile.path,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('2'), findsOneWidget);
      expect(find.text('2 Photos'), findsOneWidget);

      zipDir.deleteSync(recursive: true);
    },
  );

  testWidgets(
    'Multi-select mode enters via action, allows select-all, and cancels',
    (tester) async {
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

      expect(find.byTooltip('Select multiple'), findsOneWidget);
      await tester.tap(find.byTooltip('Select multiple'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // In selection mode with 0 selected
      expect(find.text('Select photos'), findsOneWidget);

      // Tap on the first item in the grid to select it
      await tester.tap(find.byKey(ValueKey('grid_photo_${fileA.path}')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('1 selected'), findsOneWidget);

      // Select All
      expect(find.byTooltip('Select all'), findsOneWidget);
      await tester.tap(find.byTooltip('Select all'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('3 selected'), findsOneWidget);

      // Deselect All
      expect(find.byTooltip('Deselect all'), findsOneWidget);
      await tester.tap(find.byTooltip('Deselect all'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Select photos'), findsOneWidget);

      // Cancel selection
      expect(find.byTooltip('Cancel selection'), findsOneWidget);
      await tester.tap(find.byTooltip('Cancel selection'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byTooltip('Select multiple'), findsOneWidget);
      expect(find.text('Select photos'), findsNothing);
    },
  );

  testWidgets(
    'Multi-select deletes selected files from disk and updates grid count',
    (tester) async {
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

      // Enter selection mode
      await tester.tap(find.byTooltip('Select multiple'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Tap first item
      await tester.tap(find.byKey(ValueKey('grid_photo_${fileA.path}')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Tap second item
      await tester.tap(find.byKey(ValueKey('grid_photo_${fileB.path}')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('2 selected'), findsOneWidget);

      // Tap Delete selected in AppBar
      final deleteBtn = find.byTooltip('Delete selected');
      expect(deleteBtn, findsOneWidget);
      await tester.tap(deleteBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Confirm dialog appears
      expect(find.text('Delete 2 Photos?'), findsOneWidget);
      final confirmDeleteBtn = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(ElevatedButton, 'Delete'),
      );
      await tester.tap(confirmDeleteBtn);
      await tester.pumpAndSettle();

      // Verify files deleted from disk
      expect(fileA.existsSync(), isFalse);
      expect(fileB.existsSync(), isFalse);
      expect(fileC.existsSync(), isTrue);

      // Grid should now only have 1 photo remaining
      expect(find.text('1'), findsOneWidget);
      expect(find.text('1 Photo'), findsOneWidget);
    },
  );

  testWidgets(
    'LocalFullscreenViewer deletes single photo on confirmation',
    (tester) async {
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

      // Tap first image to open fullscreen viewer
      await tester.tap(find.byKey(ValueKey('grid_photo_${fileA.path}')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify fullscreen viewer has delete photo button
      final deleteBtn = find.byTooltip('Delete photo');
      expect(deleteBtn, findsOneWidget);

      await tester.tap(deleteBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Confirm dialog appears
      expect(find.text('Delete Photo?'), findsOneWidget);
      final confirmBtn = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(ElevatedButton, 'Delete'),
      );
      await tester.tap(confirmBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify fileA deleted from disk
      expect(fileA.existsSync(), isFalse);

      // Viewer updates count to '1 of 2'
      expect(find.text('1 of 2'), findsOneWidget);
    },
  );

  testWidgets(
    'LocalFullscreenViewer places action buttons inside AppBar bottom down the title to prevent title truncation',
    (tester) async {
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

      // Tap first image to open fullscreen viewer
      await tester.tap(find.byKey(ValueKey('grid_photo_${fileB.path}')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify action buttons exist in top bar below the title (top half of screen)
      expect(find.byTooltip('Delete photo'), findsOneWidget);
      expect(find.byTooltip('Slideshow'), findsOneWidget);

      final scaffoldHeight = tester.getSize(find.byType(Scaffold).last).height;
      final deletePos = tester.getCenter(find.byTooltip('Delete photo'));
      expect(deletePos.dy, lessThan(scaffoldHeight / 2));
    },
  );

  testWidgets(
    'FolderGalleryScreen displays and opens recently opened folders',
    (tester) async {
      await RecentFoldersService.addRecentFolder(tempDir.path);

      await tester.pumpWidget(
        const MaterialApp(
          home: ProviderScope(
            child: FolderGalleryScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Recent folder header and item should appear
      expect(find.text('Recently Opened'), findsOneWidget);
      expect(find.text(tempDir.path.split('/').last), findsOneWidget);

      // Tap the recent folder item to load it
      await tester.tap(find.text(tempDir.path.split('/').last));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Folder loaded with its photos
      expect(find.text('3 Photos'), findsOneWidget);
    },
  );

  testWidgets(
    'FolderGalleryScreen supports multi-selection shuffle and continuous multi-reshuffling',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ProviderScope(
            child: FolderGalleryScreen(
              initialFolderPath: tempDir.path,
              accentColor: Colors.deepPurple,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Enter selection mode
      await tester.tap(find.byTooltip('Select multiple'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Initially 0 selected, no shuffle icon
      expect(find.byTooltip('Multi-shuffle selected'), findsNothing);

      // Select first photo
      await tester.tap(find.byKey(ValueKey('grid_photo_${fileA.path}')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // 1 selected -> still not multi-shuffle
      expect(find.byTooltip('Multi-shuffle selected'), findsNothing);

      // Select second photo -> 2 selected -> multi-shuffle should appear!
      await tester.tap(find.byKey(ValueKey('grid_photo_${fileB.path}')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byTooltip('Multi-shuffle selected'), findsOneWidget);
      expect(find.text('Shuffle'), findsOneWidget);

      // Tap multi-shuffle selected -> opens SlideshowScreen
      await tester.tap(find.byTooltip('Multi-shuffle selected'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(SlideshowScreen), findsOneWidget);

      // Verify shuffle option is removed from inside slideshow
      expect(find.byTooltip('Shuffle slideshow'), findsNothing);
      expect(find.byTooltip('Shuffle again (multi-shuffle)'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
