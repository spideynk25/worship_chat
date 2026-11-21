import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_chat/features/bookmark/widgets/bookmark_collection_card.dart';
import 'package:worship_chat/models/bookmark_collection_model.dart';
import 'package:worship_chat/models/bookmark_model.dart';

void main() {
  group('Bookmark Collection Model Tests', () {
    test('BookmarkCollectionModel serialization and deserialization roundtrip', () {
      final now = DateTime.now();
      final collection = BookmarkCollectionModel(
        id: 'col_123',
        userId: 'user_456',
        name: 'Royal Goddesses',
        coverImageUrl: 'https://res.cloudinary.com/test/cover.jpg',
        bookmarkIds: ['bm_1', 'bm_2', 'bm_3'],
        createdAt: now,
        updatedAt: now,
      );

      final map = collection.toMap();
      expect(map['id'], 'col_123');
      expect(map['userId'], 'user_456');
      expect(map['name'], 'Royal Goddesses');
      expect(map['coverImageUrl'], 'https://res.cloudinary.com/test/cover.jpg');
      expect(map['bookmarkIds'], ['bm_1', 'bm_2', 'bm_3']);
      expect(map['createdAt'], now.millisecondsSinceEpoch);
      expect(map['updatedAt'], now.millisecondsSinceEpoch);

      final fromMap = BookmarkCollectionModel.fromMap(map);
      expect(fromMap.id, collection.id);
      expect(fromMap.userId, collection.userId);
      expect(fromMap.name, collection.name);
      expect(fromMap.coverImageUrl, collection.coverImageUrl);
      expect(fromMap.bookmarkIds, collection.bookmarkIds);
      expect(fromMap.count, 3);
      expect(fromMap.containsBookmark('bm_2'), isTrue);
      expect(fromMap.containsBookmark('bm_99'), isFalse);
    });

    test('BookmarkCollectionModel copyWith modifies fields cleanly', () {
      final now = DateTime.now();
      final collection = BookmarkCollectionModel(
        id: 'col_1',
        userId: 'user_1',
        name: 'Queens',
        bookmarkIds: ['b1'],
        createdAt: now,
        updatedAt: now,
      );

      final updated = collection.copyWith(
        name: 'Supreme Queens',
        bookmarkIds: ['b1', 'b2'],
      );

      expect(updated.id, 'col_1');
      expect(updated.name, 'Supreme Queens');
      expect(updated.bookmarkIds.length, 2);
      expect(updated.count, 2);
      expect(updated.containsBookmark('b2'), isTrue);
    });

    test('BookmarkModel serialization preserves data intact', () {
      final now = DateTime.now();
      final bm = BookmarkModel(
        bookmarkId: 'bm_001',
        userId: 'user_001',
        userName: 'Queen Rashmika',
        userProfilePic: 'https://example.com/pic.jpg',
        imageUrl: 'https://example.com/img.jpg',
        groupId: 'grp_001',
        groupName: 'Rashmika Queendom',
        bookmarkedAt: now,
      );

      final map = bm.toMap();
      expect(map['bookmarkId'], 'bm_001');
      expect(map['groupName'], 'Rashmika Queendom');

      final from = BookmarkModel.fromMap(map);
      expect(from.bookmarkId, 'bm_001');
      expect(from.userName, 'Queen Rashmika');
      expect(from.groupName, 'Rashmika Queendom');
    });
  });

  group('BookmarkCollectionCard Widget Tests', () {
    testWidgets('Renders All Bookmarks card with proper title and count',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BookmarkCollectionCard(
              title: 'All Bookmarks',
              count: 14,
              previewImageUrls: const [],
              isAllBookmarks: true,
              canManage: false,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text('All Bookmarks'), findsOneWidget);
      expect(find.text('14 items'), findsOneWidget);
      expect(find.byIcon(Icons.bookmark_rounded), findsOneWidget);
    });

    testWidgets('Renders Custom Collection card with folder icon and manage menu',
        (WidgetTester tester) async {
      bool tapped = false;
      bool renamed = false;
      bool deleted = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BookmarkCollectionCard(
              title: 'Pooja Favorites',
              count: 1,
              previewImageUrls: const [],
              isAllBookmarks: false,
              canManage: true,
              onTap: () => tapped = true,
              onRename: () => renamed = true,
              onDelete: () => deleted = true,
            ),
          ),
        ),
      );

      expect(find.text('Pooja Favorites'), findsOneWidget);
      expect(find.text('1 item'), findsOneWidget);
      expect(find.byIcon(Icons.folder_rounded), findsOneWidget);

      // Verify tap works
      await tester.tap(find.text('Pooja Favorites'));
      expect(tapped, isTrue);

      // Verify popup menu works
      expect(find.byType(PopupMenuButton<String>), findsOneWidget);
    });
  });
}

