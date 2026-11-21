import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_chat/common/utils/app_capabilities.dart';
import 'package:worship_chat/features/chat/widgets/forward_message_sheet.dart';
import 'package:worship_chat/features/group/controller/group_gallery_controller.dart';
import 'package:worship_chat/features/group/repository/group_gallery_repository.dart';
import 'package:worship_chat/features/group/screens/group_gallery_screen.dart';
import 'package:worship_chat/models/group_gallery_image.dart';

class FakeGroupGallerySelectionRepo extends Fake
    implements GroupGalleryRepository {
  final Stream<List<GroupGalleryImage>> stream;
  final List<String> deletedImageIds = [];

  FakeGroupGallerySelectionRepo(this.stream);

  @override
  Stream<List<GroupGalleryImage>> getGalleryStream(String groupId) => stream;

  @override
  Future<int> getGalleryCount(String groupId) async => 0;

  @override
  Future<void> deleteImage(String groupId, String imageId) async {
    deletedImageIds.add(imageId);
  }

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
  }) async =>
      videoFiles.length;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppCapabilities.debugOverride = const AppCapabilities(
      platform: TargetPlatform.android,
      isTablet: false,
    );
  });

  tearDown(() => AppCapabilities.debugOverride = null);

  final List<GroupGalleryImage> testPhotos = [
    GroupGalleryImage(
      imageId: 'img_1',
      groupId: 'group_test_1',
      imageUrl: 'https://example.com/p1.jpg',
      uploadedBy: 'u1',
      uploadedByName: 'Alice',
      uploadedAt: DateTime(2026, 1, 1),
      mediaType: 'image',
    ),
    GroupGalleryImage(
      imageId: 'img_2',
      groupId: 'group_test_1',
      imageUrl: 'https://example.com/p2.jpg',
      uploadedBy: 'u1',
      uploadedByName: 'Alice',
      uploadedAt: DateTime(2026, 1, 2),
      mediaType: 'image',
    ),
    GroupGalleryImage(
      imageId: 'img_3',
      groupId: 'group_test_1',
      imageUrl: 'https://example.com/p3.jpg',
      uploadedBy: 'u2',
      uploadedByName: 'Bob',
      uploadedAt: DateTime(2026, 1, 3),
      mediaType: 'image',
    ),
  ];

  test('ForwardMessageSheet supports single and multiple payloads', () {
    const singlePayload = ForwardMessagePayload(
      text: 'Photo 1',
      messageType: 'image',
      fileMessageData: 'https://example.com/1.jpg',
    );
    final sheetSingle = ForwardMessageSheet(payload: singlePayload);
    expect(sheetSingle.payloads.length, 1);
    expect(sheetSingle.payload.fileMessageData, 'https://example.com/1.jpg');

    const multiplePayloads = [
      ForwardMessagePayload(
        text: 'Photo 1',
        messageType: 'image',
        fileMessageData: 'https://example.com/1.jpg',
      ),
      ForwardMessagePayload(
        text: 'Video 1',
        messageType: 'video',
        fileMessageData: 'https://example.com/v1.mp4',
      ),
    ];
    final sheetMulti = ForwardMessageSheet(payloads: multiplePayloads);
    expect(sheetMulti.payloads.length, 2);
    expect(sheetMulti.payloads[0].isImage, isTrue);
    expect(sheetMulti.payloads[1].isVideo, isTrue);
    expect(sheetMulti.payload.fileMessageData, 'https://example.com/1.jpg');
  });

  testWidgets(
      'GroupGalleryScreen enters selection mode and toggles item selections',
      (tester) async {
    final streamController =
        StreamController<List<GroupGalleryImage>>.broadcast();
    final fakeRepo = FakeGroupGallerySelectionRepo(streamController.stream);
    final controller = GroupGalleryController(repository: fakeRepo);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          groupGalleryControllerProvider.overrideWithValue(controller),
        ],
        child: const MaterialApp(
          home: GroupGalleryScreen(
            groupId: 'group_test_1',
            groupName: 'Test Royal Group',
            accentColor: Color(0xFFE91E63),
          ),
        ),
      ),
    );

    // Initial pump
    await tester.pump();

    // Emit photos into stream
    streamController.add(testPhotos);
    await tester.pumpAndSettle();

    // Verify initial normal AppBar state
    expect(find.text('Gallery'), findsOneWidget);
    expect(find.byIcon(Icons.checklist_rounded), findsOneWidget);

    // Tap the checklist icon to enter multi-select mode
    await tester.tap(find.byIcon(Icons.checklist_rounded));
    await tester.pumpAndSettle();

    // Verify Selection AppBar is displayed
    expect(find.text('Select photos'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    expect(find.byIcon(Icons.select_all_rounded), findsOneWidget);

    // Tap the first item in the grid to select it
    final firstItemFinder = find.byKey(const ValueKey('gallery_item_img_1'));
    expect(firstItemFinder, findsOneWidget);
    await tester.tap(firstItemFinder);
    await tester.pumpAndSettle();

    // Verify 1 item selected and action icons appear
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.byIcon(Icons.forward_rounded), findsOneWidget);
    expect(find.byIcon(Icons.download_rounded), findsOneWidget);
    expect(find.byIcon(Icons.slideshow_rounded), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);

    // Tap Select All
    await tester.tap(find.byIcon(Icons.select_all_rounded));
    await tester.pumpAndSettle();

    // Verify all 3 photos selected
    expect(find.text('3 selected'), findsOneWidget);
    expect(find.byIcon(Icons.deselect_rounded), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsNWidgets(3));

    // Tap Deselect All
    await tester.tap(find.byIcon(Icons.deselect_rounded));
    await tester.pumpAndSettle();

    // Verify 0 selected
    expect(find.text('Select photos'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsNothing);

    // Exit selection mode via close (X)
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    // Verify returned to normal AppBar
    expect(find.text('Gallery'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsNothing);
    expect(find.byIcon(Icons.checklist_rounded), findsOneWidget);

    await streamController.close();
  });

  testWidgets(
      'Long-pressing an item opens menu and selecting enters selection mode',
      (tester) async {
    final streamController =
        StreamController<List<GroupGalleryImage>>.broadcast();
    final fakeRepo = FakeGroupGallerySelectionRepo(streamController.stream);
    final controller = GroupGalleryController(repository: fakeRepo);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          groupGalleryControllerProvider.overrideWithValue(controller),
        ],
        child: const MaterialApp(
          home: GroupGalleryScreen(
            groupId: 'group_test_1',
            groupName: 'Test Royal Group',
            accentColor: Color(0xFFE91E63),
          ),
        ),
      ),
    );

    await tester.pump();
    streamController.add(testPhotos);
    await tester.pumpAndSettle();

    // Long press first item
    await tester.longPress(find.byKey(const ValueKey('gallery_item_img_1')));
    await tester.pumpAndSettle();

    // Context menu sheet should be open with 'Select' option
    final sheetSelectFinder = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.text('Select'),
    );
    expect(sheetSelectFinder, findsOneWidget);
    expect(find.text('Select multiple photos'), findsOneWidget);

    // Tap 'Select' in bottom sheet
    await tester.tap(sheetSelectFinder);
    await tester.pumpAndSettle();

    // Selection mode should be active with img_1 selected
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);

    // Press device back (PopScope) to exit selection mode
    final dynamic widgetsAppState = tester.state(find.byType(WidgetsApp));
    await widgetsAppState.didPopRoute();
    await tester.pumpAndSettle();

    // Verify back exited selection mode instead of popping the screen
    expect(find.text('Gallery'), findsOneWidget);
    expect(find.text('1 selected'), findsNothing);

    await streamController.close();
  });

  testWidgets(
      'Action toolbar displays down with good UI and handles Shuffle / Restore',
      (tester) async {
    final streamController =
        StreamController<List<GroupGalleryImage>>.broadcast();
    final fakeRepo = FakeGroupGallerySelectionRepo(streamController.stream);
    final controller = GroupGalleryController(repository: fakeRepo);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          groupGalleryControllerProvider.overrideWithValue(controller),
        ],
        child: const MaterialApp(
          home: GroupGalleryScreen(
            groupId: 'group_test_1',
            groupName: 'Aura Elixiria Goddess Rashmika Mandanna Supreme Queendom',
            accentColor: Color(0xFFE91E63),
          ),
        ),
      ),
    );

    await tester.pump();
    streamController.add(testPhotos);
    await tester.pumpAndSettle();

    // Verify full group name is rendered without hiding in the title
    expect(
      find.text('Aura Elixiria Goddess Rashmika Mandanna Supreme Queendom'),
      findsOneWidget,
    );

    // Verify subtitle shows Gallery and photo count
    expect(find.text('Gallery'), findsOneWidget);
    expect(find.text(' • 3 photos'), findsOneWidget);

    // Verify Action Toolbar is present below with all 4 action pills
    expect(find.text('Select'), findsOneWidget);
    expect(find.text('Folder'), findsOneWidget);
    expect(find.text('ZIP'), findsOneWidget);
    expect(find.text('Shuffle'), findsOneWidget);

    // Tap Shuffle pill
    await tester.tap(find.text('Shuffle'));
    await tester.pumpAndSettle();

    // Verify Shuffle button turns into Restore
    expect(find.text('Restore'), findsOneWidget);
    expect(find.byIcon(Icons.format_list_numbered_rounded), findsOneWidget);

    // Tap Restore pill
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();

    // Verify back to normal Shuffle state
    expect(find.text('Shuffle'), findsOneWidget);
    expect(find.byIcon(Icons.shuffle_rounded), findsOneWidget);

    await streamController.close();
  });
}
