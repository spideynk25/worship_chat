import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worship_chat/features/group/screens/folder_gallery_screen.dart';
import 'package:worship_chat/features/group/services/recent_folders_service.dart';
import 'package:worship_chat/features/group/widgets/folder_picker_bottom_sheet.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RecentFoldersService.setMockPrefs(null);
  });

  testWidgets('FolderPickerBottomSheet renders options and empty recents', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FolderPickerBottomSheet(),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify Title & Subtitle
    expect(find.text('Local Gallery Storage'), findsOneWidget);
    expect(find.text('Choose whether to browse a folder or a ZIP file'), findsOneWidget);

    // Verify Options
    expect(find.text('Open Device Folder'), findsOneWidget);
    expect(find.text('Browse uncompressed photos directory on your storage'), findsOneWidget);
    expect(find.text('Folder'), findsOneWidget);

    expect(find.text('Open ZIP Archive'), findsOneWidget);
    expect(find.text('Directly extract & view photos from a .zip file'), findsOneWidget);
    expect(find.text('ZIP'), findsOneWidget);

    // Verify Empty Recents State
    expect(find.text('No recent folders yet'), findsOneWidget);
    expect(find.text('Open Gallery Hub & Multi-Shuffle'), findsOneWidget);
  });

  testWidgets('FolderPickerBottomSheet renders recent folders and handles clearing', (tester) async {
    // Populate some recents
    await RecentFoldersService.addRecentFolder('/storage/photos/vacation');
    await RecentFoldersService.addRecentFolder('/storage/photos/archive.zip');

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FolderPickerBottomSheet(),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify recents header with count
    expect(find.text('Recently Opened (2)'), findsOneWidget);
    expect(find.text('vacation'), findsOneWidget);
    expect(find.text('archive'), findsOneWidget);
    expect(find.text('/storage/photos/archive.zip'), findsOneWidget);
    expect(find.text('Clear all'), findsOneWidget);

    // Tap Clear all
    await tester.tap(find.text('Clear all'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Recents should be cleared
    expect(find.text('No recent folders yet'), findsOneWidget);
    expect(find.text('vacation'), findsNothing);
  });

  testWidgets('FolderPickerBottomSheet handles removing a single recent item', (tester) async {
    await RecentFoldersService.addRecentFolder('/storage/photos/folder_a');
    await RecentFoldersService.addRecentFolder('/storage/photos/folder_b');

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FolderPickerBottomSheet(),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('folder_a'), findsOneWidget);
    expect(find.text('folder_b'), findsOneWidget);

    // Find remove buttons
    final removeButtons = find.byTooltip('Remove from recents');
    expect(removeButtons, findsNWidgets(2));

    // Tap first remove button
    await tester.tap(removeButtons.first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final recents = await RecentFoldersService.getRecentFolders();
    expect(recents.length, 1);
  });

  testWidgets('FolderGalleryScreen.showPickerOptions opens FolderPickerBottomSheet', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () => FolderGalleryScreen.showPickerOptions(context),
                child: const Text('Open Picker Options'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Picker Options'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(FolderPickerBottomSheet), findsOneWidget);
    expect(find.text('Local Gallery Storage'), findsOneWidget);
  });
}
