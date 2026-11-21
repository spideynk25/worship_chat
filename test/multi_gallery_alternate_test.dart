import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_chat/features/group/screens/multi_gallery_shuffled_screen.dart';
import 'package:worship_chat/features/group/screens/slide_show_screen.dart';
import 'package:worship_chat/features/group/utils/multi_gallery_shuffler_helper.dart';
import 'package:worship_chat/models/group_gallery_image.dart';

GroupGalleryImage _fakeImage({
  required String id,
  required String groupId,
}) {
  return GroupGalleryImage(
    imageId: id,
    groupId: groupId,
    imageUrl: 'https://example.com/$id.jpg',
    uploadedBy: 'user1',
    uploadedByName: 'Tester',
    uploadedAt: DateTime.now(),
  );
}

void main() {
  group('alternatePhotosAcrossGroups', () {
    test('handles empty and single-item lists cleanly', () {
      expect(alternatePhotosAcrossGroups([]), isEmpty);

      final single = [_fakeImage(id: 'img1', groupId: 'g1')];
      final res = alternatePhotosAcrossGroups(single);
      expect(res.length, 1);
      expect(res.first.imageId, 'img1');
    });

    test('single group returns all its images shuffled', () {
      final images = List.generate(
        10,
        (i) => _fakeImage(id: 'img_$i', groupId: 'single_group'),
      );
      final res = alternatePhotosAcrossGroups(images, Random(42));
      expect(res.length, 10);
      expect(res.map((e) => e.imageId).toSet(), images.map((e) => e.imageId).toSet());
    });

    test('strictly alternates photos between 2 groups of equal size', () {
      final g1Images = List.generate(
        15,
        (i) => _fakeImage(id: 'g1_$i', groupId: 'group_1'),
      );
      final g2Images = List.generate(
        15,
        (i) => _fakeImage(id: 'g2_$i', groupId: 'group_2'),
      );

      final combined = [...g1Images, ...g2Images];
      final result = alternatePhotosAcrossGroups(combined, Random(123));

      expect(result.length, 30);
      // Verify that every consecutive pair alternates between group_1 and group_2
      for (int i = 0; i < result.length - 1; i++) {
        expect(
          result[i].groupId,
          isNot(equals(result[i + 1].groupId)),
          reason: 'Item at $i (${result[i].groupId}) must alternate with item at ${i + 1} (${result[i + 1].groupId})',
        );
      }
    });

    test('strictly alternates photos across 3 groups of equal size', () {
      final g1 = List.generate(10, (i) => _fakeImage(id: 'g1_$i', groupId: 'g1'));
      final g2 = List.generate(10, (i) => _fakeImage(id: 'g2_$i', groupId: 'g2'));
      final g3 = List.generate(10, (i) => _fakeImage(id: 'g3_$i', groupId: 'g3'));

      final combined = [...g1, ...g2, ...g3];
      final result = alternatePhotosAcrossGroups(combined, Random(999));

      expect(result.length, 30);
      for (int i = 0; i < result.length - 1; i++) {
        expect(
          result[i].groupId,
          isNot(equals(result[i + 1].groupId)),
          reason: 'Photo at index $i must not share groupId with photo at index ${i + 1}',
        );
      }
    });

    test('alternates across unequal groups until smaller groups run out', () {
      // Group A: 10 photos, Group B: 4 photos, Group C: 6 photos
      final gA = List.generate(10, (i) => _fakeImage(id: 'A_$i', groupId: 'A'));
      final gB = List.generate(4, (i) => _fakeImage(id: 'B_$i', groupId: 'B'));
      final gC = List.generate(6, (i) => _fakeImage(id: 'C_$i', groupId: 'C'));

      final combined = [...gA, ...gB, ...gC];
      final result = alternatePhotosAcrossGroups(combined, Random(777));

      expect(result.length, 20);

      // Check all elements are preserved
      expect(result.map((e) => e.imageId).toSet(), combined.map((e) => e.imageId).toSet());

      // Non-A photos total 10 (B: 4, C: 6). Strict alternation holds for index 0..14
      for (int i = 0; i < 15; i++) {
        expect(
          result[i].groupId,
          isNot(equals(result[i + 1].groupId)),
          reason: 'At index $i (${result[i].groupId}) and ${i + 1} (${result[i + 1].groupId}) photos must alternate',
        );
      }
    });

    test('randomizes photo order within each group', () {
      final g1 = List.generate(20, (i) => _fakeImage(id: 'g1_$i', groupId: 'g1'));
      final g2 = List.generate(20, (i) => _fakeImage(id: 'g2_$i', groupId: 'g2'));

      final combined = [...g1, ...g2];
      final pass1 = alternatePhotosAcrossGroups(combined, Random(1));
      final pass2 = alternatePhotosAcrossGroups(combined, Random(2));

      final pass1Ids = pass1.map((e) => e.imageId).toList();
      final pass2Ids = pass2.map((e) => e.imageId).toList();

      expect(pass1Ids, isNot(equals(pass2Ids)));
    });
  });

  group('buildMultiGallerySlideSets', () {
    test('handles empty images cleanly', () {
      final sets = buildMultiGallerySlideSets(images: []);
      expect(sets, isEmpty);
    });

    test('builds slide sets with 1 photo from each group for equal groups', () {
      final g1 = List.generate(5, (i) => _fakeImage(id: 'g1_$i', groupId: 'g1'));
      final g2 = List.generate(5, (i) => _fakeImage(id: 'g2_$i', groupId: 'g2'));
      final g3 = List.generate(5, (i) => _fakeImage(id: 'g3_$i', groupId: 'g3'));

      final combined = [...g1, ...g2, ...g3];
      final sets = buildMultiGallerySlideSets(
        images: combined,
        groupOrder: ['g1', 'g2', 'g3'],
        random: Random(42),
      );

      // Total slides = 5 (max count)
      expect(sets.length, 5);

      for (int i = 0; i < sets.length; i++) {
        final slide = sets[i];
        expect(slide.slideIndex, i);
        expect(slide.photos.length, 3);
        // Exactly one photo from each group
        final groupIds = slide.photos.map((p) => p.groupId).toList();
        expect(groupIds, equals(['g1', 'g2', 'g3']));
      }
    });

    test('cycles smaller groups so every slide has a photo from every group', () {
      // Group A: 6 photos, Group B: 2 photos
      final gA = List.generate(6, (i) => _fakeImage(id: 'A_$i', groupId: 'A'));
      final gB = List.generate(2, (i) => _fakeImage(id: 'B_$i', groupId: 'B'));

      final combined = [...gA, ...gB];
      final sets = buildMultiGallerySlideSets(
        images: combined,
        groupOrder: ['A', 'B'],
        random: Random(99),
      );

      // Total slides = max(6, 2) = 6
      expect(sets.length, 6);

      for (int i = 0; i < 6; i++) {
        final slide = sets[i];
        expect(slide.photos.length, 2);
        expect(slide.photos[0].groupId, 'A');
        expect(slide.photos[1].groupId, 'B');
      }

      // Group B has 2 photos, so across 6 slides it cycles: B[0], B[1], B[0], B[1], B[0], B[1]
      final bPhotoIds = sets.map((s) => s.photos[1].imageId).toList();
      expect(bPhotoIds[0], equals(bPhotoIds[2]));
      expect(bPhotoIds[2], equals(bPhotoIds[4]));
      expect(bPhotoIds[1], equals(bPhotoIds[3]));
      expect(bPhotoIds[3], equals(bPhotoIds[5]));
    });
  });

  group('MultiGalleryShuffledScreen Widget Tests', () {
    testWidgets('renders MultiGalleryShuffledScreen with alternate grid by default without Same Slide option outside', (tester) async {
      final imgA1 = _fakeImage(id: 'a1', groupId: 'groupA');
      final imgA2 = _fakeImage(id: 'a2', groupId: 'groupA');
      final imgB1 = _fakeImage(id: 'b1', groupId: 'groupB');
      final imgB2 = _fakeImage(id: 'b2', groupId: 'groupB');

      final images = [imgA1, imgB1, imgA2, imgB2];
      final namesMap = {
        'groupA': 'Queen Pooja',
        'groupB': 'Queen Rashmika',
      };

      await tester.pumpWidget(
        MaterialApp(
          home: MultiGalleryShuffledScreen(
            images: images,
            groupNamesMap: namesMap,
            initialMode: MultiGalleryMode.alternate,
          ),
        ),
      );

      // Verify header and filter chips
      expect(find.text('2 Groups'), findsOneWidget);
      expect(find.text('All (4)'), findsOneWidget);
      expect(find.text('Queen Pooja (2)'), findsOneWidget);
      expect(find.text('Queen Rashmika (2)'), findsOneWidget);

      // In alternate mode, GridView is present and NO Same Slide tab outside
      expect(find.byType(GridView), findsOneWidget);
      expect(find.text('Same Slide'), findsNothing);

      // Verify AppBar actions is empty so title is uncrowded
      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.actions, isEmpty);
      expect(appBar.bottom, isNotNull);

      // Verify Shuffle and Slideshow buttons are positioned below the title
      expect(find.byTooltip('Shuffle again (multi-shuffle)'), findsOneWidget);
      expect(find.byTooltip('Start slideshow'), findsOneWidget);
    });

    testWidgets('SlideshowScreen supports Same Slide mode and mode toggling', (tester) async {
      final imgA = _fakeImage(id: 'a1', groupId: 'groupA');
      final imgB = _fakeImage(id: 'b1', groupId: 'groupB');

      final slideSets = [
        MultiGallerySlideSet(slideIndex: 0, photos: [imgA, imgB]),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: SlideshowScreen(
            images: [imgA, imgB],
            initialIndex: 0,
            accentColor: Colors.amber,
            groupName: 'Test Slideshow',
            mode: MultiGalleryMode.sameSlide,
            slideSets: slideSets,
            groupNamesMap: {
              'groupA': 'Queen Pooja',
              'groupB': 'Queen Rashmika',
            },
          ),
        ),
      );

      // Pump 1 frame
      await tester.pump(const Duration(milliseconds: 100));

      // In Same Slide mode, title shows Slide 1 of 1 • Same Slide
      expect(find.text('Slide 1 of 1 • Same Slide'), findsOneWidget);
      expect(find.text('2 Galleries synced together'), findsOneWidget);

      // Verify default slide interval is 10 seconds
      expect(find.text('10s'), findsOneWidget);

      // Verify Download as GIF option is completely removed from slideshow gallery
      expect(find.byTooltip('Download all as GIF'), findsNothing);
      expect(find.byIcon(Icons.gif_box_outlined), findsNothing);

      // Verify exactly 2 images on the slide with group badges
      expect(find.text('Queen Pooja'), findsOneWidget);
      expect(find.text('Queen Rashmika'), findsOneWidget);
      // Maximize buttons are icon-only (no text)
      expect(find.text('Maximize'), findsNothing);
      expect(find.byIcon(Icons.open_in_full_rounded), findsNWidgets(2));

      // Tapping on the photo card itself DOES NOT maximize the photo
      await tester.tap(find.byKey(ValueKey('slide_photo_${imgA.imageId}')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Paused'), findsNothing);
      expect(find.byIcon(Icons.close_fullscreen_rounded), findsNothing);

      // Tap on Queen Pooja's Maximize icon button to maximize it
      await tester.tap(find.byKey(ValueKey('maximize_btn_${imgA.imageId}')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Photo is now maximized: Paused badge is displayed and Minimize icon button is visible (no text)
      expect(find.text('Paused'), findsOneWidget);
      expect(find.text('Minimize'), findsNothing);
      expect(find.byIcon(Icons.close_fullscreen_rounded), findsOneWidget);

      // Tap Minimize icon button: photo minimizes back to 2-image split view and slideshow automatically resumes
      await tester.tap(find.byKey(const ValueKey('minimize_photo_btn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Paused'), findsNothing);
      expect(find.byIcon(Icons.open_in_full_rounded), findsNWidgets(2));

      // Verify layout switcher button exists for 2-photo Same Slide mode
      final layoutToggleBtn = find.byKey(const ValueKey('two_photos_layout_toggle_btn'));
      expect(layoutToggleBtn, findsOneWidget);
      expect(find.byTooltip('Switch to Side-by-Side'), findsOneWidget);

      // Tap to toggle to Side-by-Side layout
      await tester.tap(layoutToggleBtn);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byTooltip('Switch to Stacked (Top & Bottom)'), findsOneWidget);

      // Tap again to toggle back to Stacked layout
      await tester.tap(layoutToggleBtn);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byTooltip('Switch to Side-by-Side'), findsOneWidget);

      // Find the mode toggle icon and tap to switch to Alternate Images
      final toggleFinder = find.byTooltip('Switch to Alternate Images Mode');
      expect(toggleFinder, findsOneWidget);
      await tester.tap(toggleFinder);
      await tester.pump(const Duration(milliseconds: 100));

      // Title should now reflect Alternate mode
      expect(find.text('Slideshow (1/2)'), findsOneWidget);
    });

    testWidgets('SlideshowScreen renders 3-image Same Slide with balanced Hero + Split layout', (tester) async {
      final imgA = _fakeImage(id: 'a1', groupId: 'groupA');
      final imgB = _fakeImage(id: 'b1', groupId: 'groupB');
      final imgC = _fakeImage(id: 'c1', groupId: 'groupC');

      final slideSets = [
        MultiGallerySlideSet(slideIndex: 0, photos: [imgA, imgB, imgC]),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: SlideshowScreen(
            images: [imgA, imgB, imgC],
            initialIndex: 0,
            accentColor: Colors.amber,
            groupName: 'Test Slideshow 3',
            mode: MultiGalleryMode.sameSlide,
            slideSets: slideSets,
            groupNamesMap: {
              'groupA': 'Queen Pooja',
              'groupB': 'Queen Rashmika',
              'groupC': 'Goddess Deepika',
            },
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Slide 1 of 1 • Same Slide'), findsOneWidget);
      expect(find.text('3 Galleries synced together'), findsOneWidget);

      // Verify all 3 images are displayed with their group badges and icon-only maximize buttons (no text)
      expect(find.text('Queen Pooja'), findsOneWidget);
      expect(find.text('Queen Rashmika'), findsOneWidget);
      expect(find.text('Goddess Deepika'), findsOneWidget);
      expect(find.text('Maximize'), findsNothing);
      expect(find.byIcon(Icons.open_in_full_rounded), findsNWidgets(3));

      // Tap on Goddess Deepika's Maximize icon button
      await tester.tap(find.byKey(ValueKey('maximize_btn_${imgC.imageId}')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Paused'), findsOneWidget);
      expect(find.text('Minimize'), findsNothing);
      expect(find.byIcon(Icons.close_fullscreen_rounded), findsOneWidget);

      // Tap Minimize icon button: resumes slideshow
      await tester.tap(find.byKey(const ValueKey('minimize_photo_btn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Paused'), findsNothing);
      expect(find.byIcon(Icons.open_in_full_rounded), findsNWidgets(3));
    });
  });
}
