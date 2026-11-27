import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worship_chat/features/dashboard/widgets/recent_gallery_photos_section.dart';
import 'package:worship_chat/features/group/repository/group_gallery_repository.dart';
import 'package:worship_chat/features/group/screens/recent_gallery_photos_screen.dart';
import 'package:worship_chat/models/group.dart';
import 'package:worship_chat/models/group_gallery_image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  GroupModel makeGroup({
    required String id,
    required String name,
    int galleryCount = 0,
    DateTime? lastGalleryUpdate,
    DateTime? timeSent,
    String queendom = 'Queen Pooja',
  }) {
    return GroupModel(
      senderId: 'u1',
      name: name,
      groupId: id,
      lastMessage: '',
      groupPic: '',
      membersUid: const ['u1'],
      fcmTokens: const [],
      unseenMessages: const {},
      queendom: queendom,
      galleryCount: galleryCount,
      lastGalleryUpdate: lastGalleryUpdate,
      timeSent: timeSent,
    );
  }

  group('Recent Gallery Repository Logic & Cache', () {
    test('GroupModel serializes and parses lastGalleryUpdate cleanly', () {
      final ts = DateTime(2026, 11, 27, 18, 30);
      final group = makeGroup(
        id: 'g1',
        name: 'Queen Pooja',
        galleryCount: 12,
        lastGalleryUpdate: ts,
      );

      final map = group.toMap();
      expect(map['lastGalleryUpdate'], ts.millisecondsSinceEpoch);

      final restored = GroupModel.fromMap(map);
      expect(restored.lastGalleryUpdate, ts);
      expect(restored.galleryCount, 12);
    });

    test('selectGroupsForRecentFetch prioritizes groups with recent gallery updates', () {
      final now = DateTime(2026, 11, 27, 19, 0);
      final groups = [
        makeGroup(id: 'empty', name: 'Empty Group', galleryCount: 0),
        makeGroup(
          id: 'older_gallery',
          name: 'Older Gallery',
          galleryCount: 25,
          lastGalleryUpdate: now.subtract(const Duration(days: 2)),
        ),
        makeGroup(
          id: 'newest_gallery',
          name: 'Newest Gallery',
          galleryCount: 5,
          lastGalleryUpdate: now.subtract(const Duration(minutes: 10)),
        ),
        makeGroup(
          id: 'duplicate_newest',
          name: 'Dup',
          galleryCount: 1,
        ),
        makeGroup(
          id: 'newest_gallery',
          name: 'Newest Gallery Dup',
          galleryCount: 5,
          lastGalleryUpdate: now.subtract(const Duration(minutes: 10)),
        ),
      ];

      final selected = GroupGalleryRepository.selectGroupsForRecentFetch(
        groups,
        maxGroups: 4,
      );

      expect(selected.map((g) => g.groupId).toList(), [
        'newest_gallery',
        'older_gallery',
        'duplicate_newest',
        'empty',
      ]);
    });

    test('mergeAndSortRecentPhotos deduplicates, filters videos when photosOnly, and sorts newest first', () {
      final now = DateTime(2026, 11, 27, 19, 0);
      final img1 = GroupGalleryImage(
        imageId: 'img_old',
        groupId: 'g1',
        imageUrl: 'https://example.com/old.jpg',
        uploadedBy: 'u1',
        uploadedByName: 'Nandha',
        uploadedAt: now.subtract(const Duration(hours: 3)),
      );
      final img2 = GroupGalleryImage(
        imageId: 'img_new',
        groupId: 'g2',
        imageUrl: 'https://example.com/new.jpg',
        uploadedBy: 'u2',
        uploadedByName: 'Kumar',
        uploadedAt: now.subtract(const Duration(minutes: 5)),
      );
      final vid = GroupGalleryImage(
        imageId: 'vid_1',
        groupId: 'g2',
        imageUrl: 'https://example.com/clip.mp4',
        uploadedBy: 'u2',
        uploadedByName: 'Kumar',
        uploadedAt: now.subtract(const Duration(minutes: 1)),
        mediaType: 'video',
      );
      final emptyUrl = GroupGalleryImage(
        imageId: 'bad',
        groupId: 'g1',
        imageUrl: '   ',
        uploadedBy: 'u1',
        uploadedByName: 'Nandha',
        uploadedAt: now,
      );

      final photosOnly = GroupGalleryRepository.mergeAndSortRecentPhotos(
        [
          [img1, vid, emptyUrl],
          [img2, img1],
        ],
        photosOnly: true,
        maxItems: 10,
      );

      expect(photosOnly.map((e) => e.imageId).toList(), ['img_new', 'img_old']);

      final allMedia = GroupGalleryRepository.mergeAndSortRecentPhotos(
        [
          [img1, vid],
          [img2],
        ],
        photosOnly: false,
        maxItems: 10,
      );

      expect(
        allMedia.map((e) => e.imageId).toList(),
        ['vid_1', 'img_new', 'img_old'],
      );
    });

    test('encodeRecentPhotosCache and decodeRecentPhotosCache round-trip cleanly', () {
      final now = DateTime(2026, 11, 27, 19, 0);
      final items = [
        GroupGalleryImage(
          imageId: 'p1',
          groupId: 'g1',
          imageUrl: 'https://res.cloudinary.com/demo/image/upload/sample.jpg',
          uploadedBy: 'u1',
          uploadedByName: 'Nandha',
          uploadedAt: now.subtract(const Duration(minutes: 15)),
          caption: 'Temple Morning',
        ),
        GroupGalleryImage(
          imageId: 'p2',
          groupId: 'g2',
          imageUrl: 'https://res.cloudinary.com/demo/image/upload/sample2.jpg',
          uploadedBy: 'u2',
          uploadedByName: 'Roy',
          uploadedAt: now,
        ),
      ];

      final raw = GroupGalleryRepository.encodeRecentPhotosCache(items);
      final decoded = GroupGalleryRepository.decodeRecentPhotosCache(raw);
      expect(decoded, hasLength(2));
      expect(decoded.first.imageId, 'p2');
      expect(decoded.last.caption, 'Temple Morning');
    });

    test('formatRecentGalleryTimeAgo produces crisp human labels', () {
      final now = DateTime(2026, 11, 27, 19, 0);
      expect(
        formatRecentGalleryTimeAgo(now.subtract(const Duration(seconds: 20)), now: now),
        'Just now',
      );
      expect(
        formatRecentGalleryTimeAgo(now.subtract(const Duration(minutes: 12)), now: now),
        '12m ago',
      );
      expect(
        formatRecentGalleryTimeAgo(now.subtract(const Duration(hours: 4)), now: now),
        '4h ago',
      );
      expect(
        formatRecentGalleryTimeAgo(now.subtract(const Duration(days: 1)), now: now),
        'Yesterday',
      );
      expect(
        formatRecentGalleryTimeAgo(now.subtract(const Duration(days: 3)), now: now),
        '3d ago',
      );
    });
  });

  group('RecentGalleryPhotos Widgets UI Tests', () {
    testWidgets(
      'RecentGalleryPhotosSection renders on 360px phone, collapses/expands, and handles empty & populated states',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final now = DateTime.now();
        final groups = [
          makeGroup(
            id: 'g_pooja',
            name: 'Pooja Sanctuary',
            galleryCount: 2,
            lastGalleryUpdate: now,
            queendom: 'Queen Pooja',
          ),
          makeGroup(
            id: 'g_rashmika',
            name: 'Rashmika Royal',
            galleryCount: 1,
            lastGalleryUpdate: now.subtract(const Duration(hours: 1)),
            queendom: 'Queen Rashmika',
          ),
        ];

        final photos = [
          GroupGalleryImage(
            imageId: 'ph_1',
            groupId: 'g_pooja',
            imageUrl: 'https://example.com/a.jpg',
            uploadedBy: 'u1',
            uploadedByName: 'Nandha',
            uploadedAt: now.subtract(const Duration(minutes: 4)),
          ),
          GroupGalleryImage(
            imageId: 'ph_2',
            groupId: 'g_rashmika',
            imageUrl: 'https://example.com/b.jpg',
            uploadedBy: 'u1',
            uploadedByName: 'Nandha',
            uploadedAt: now.subtract(const Duration(hours: 2)),
          ),
        ];

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: RecentGalleryPhotosSection(
                    currentUserId: 'u1',
                    overrideGroups: groups,
                    overrideImages: photos,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.text('RECENT GALLERY PHOTOS'), findsOneWidget);
        expect(find.text('2'), findsOneWidget);
        expect(find.text('Pooja Sanctuary'), findsNothing);
        expect(find.text('Rashmika Royal'), findsNothing);
        expect(find.text('4m ago'), findsOneWidget);
        expect(find.text('2h ago'), findsOneWidget);
        expect(find.text('See All'), findsNothing);
        expect(find.text('View All'), findsNothing);
        expect(find.byIcon(Icons.slideshow_rounded), findsNothing);

        // Collapse the section via header tap
        await tester.tap(find.text('RECENT GALLERY PHOTOS'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          find.text('Tap to view 2 recently added gallery photos'),
          findsOneWidget,
        );

        // Re-expand the section
        await tester.tap(find.text('RECENT GALLERY PHOTOS'));
        await tester.pumpAndSettle();
        expect(find.text('4m ago'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Verify clean empty state when user has no gallery photos yet
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: RecentGalleryPhotosSection(
                    currentUserId: 'u1',
                    overrideGroups: groups,
                    overrideImages: const [],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.text('No recent gallery photos yet'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'RecentGalleryPhotosScreen filters photos cleanly by group on 360px screen',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final now = DateTime.now();
        final groups = [
          makeGroup(id: 'g1', name: 'Sanctuary One', galleryCount: 1),
          makeGroup(
            id: 'g2',
            name: 'Sanctuary Two',
            galleryCount: 1,
            queendom: 'Queen Rashmika',
          ),
        ];

        final photos = [
          GroupGalleryImage(
            imageId: 'a1',
            groupId: 'g1',
            imageUrl: 'https://example.com/1.jpg',
            uploadedBy: 'u1',
            uploadedByName: 'Nandha',
            uploadedAt: now,
          ),
          GroupGalleryImage(
            imageId: 'b1',
            groupId: 'g2',
            imageUrl: 'https://example.com/2.jpg',
            uploadedBy: 'u1',
            uploadedByName: 'Nandha',
            uploadedAt: now.subtract(const Duration(hours: 1)),
          ),
        ];

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: RecentGalleryPhotosScreen(
                initialImages: photos,
                groups: groups,
                autoRefreshOnOpen: false,
              ),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.text('Recently Added Photos'), findsOneWidget);
        expect(find.text('All (2)'), findsOneWidget);
        expect(find.text('Sanctuary One (1)'), findsOneWidget);

        await tester.tap(find.text('Sanctuary One (1)'));
        await tester.pump();
        expect(find.text('1 item across 2 groups'), findsOneWidget);

        // Scroll filter bar horizontally to reveal the second group chip.
        final chipScrollable = find.descendant(
          of: find.byType(ListView).first,
          matching: find.byType(Scrollable),
        );
        await tester.scrollUntilVisible(
          find.text('Sanctuary Two (1)'),
          120,
          scrollable: chipScrollable,
        );
        expect(find.text('Sanctuary Two (1)'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
