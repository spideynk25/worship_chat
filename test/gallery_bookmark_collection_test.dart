import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_chat/features/bookmark/controller/bookmark_controller.dart';
import 'package:worship_chat/features/bookmark/repository/bookmark_repository.dart';
import 'package:worship_chat/features/bookmark/widgets/save_to_collection_sheet.dart';
import 'package:worship_chat/models/bookmark_collection_model.dart';
import 'package:worship_chat/models/bookmark_model.dart';

class FakeBookmarkController implements BookmarkController {
  final List<BookmarkCollectionModel> collections;

  String? toggledColId;
  String? toggledBmId;
  bool? toggledIsInCol;

  FakeBookmarkController({this.collections = const []});

  @override
  BookmarkRepository get repository => throw UnimplementedError();

  @override
  Stream<List<BookmarkCollectionModel>> collectionsForUser(String userId) {
    return Stream.value(collections);
  }

  @override
  Future<bool> toggleBookmarkInCollection({
    required String collectionId,
    required String bookmarkId,
    required bool isInCollection,
  }) async {
    toggledColId = collectionId;
    toggledBmId = bookmarkId;
    toggledIsInCol = isInCollection;
    return true;
  }

  @override
  Future<bool> replaceBookmarkImage({
    required String bookmarkId,
    required String newImageUrl,
  }) async =>
      true;

  @override
  Future<BookmarkCollectionModel?> createCollection({
    required String name,
    List<String> initialBookmarkIds = const [],
    String? coverImageUrl,
  }) async {
    return BookmarkCollectionModel(
      id: 'new_col_1',
      userId: 'test_user',
      name: name,
      bookmarkIds: initialBookmarkIds,
      coverImageUrl: coverImageUrl,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  @override
  Stream<bool> isBookmarked(String imageUrl) => Stream.value(false);

  @override
  Future<bool> toggleBookmark({
    required String imageUrl,
    required String groupId,
    required String groupName,
    required String userName,
    required String userProfilePic,
  }) async =>
      true;

  @override
  Future<BookmarkToggleResult> toggleBookmarkWithResult({
    required String imageUrl,
    required String groupId,
    required String groupName,
    required String userName,
    required String userProfilePic,
  }) async =>
      const BookmarkToggleResult(isBookmarked: true, bookmarkId: 'test_bm_id');

  @override
  Future<String?> ensureBookmarked({
    required String imageUrl,
    required String groupId,
    required String groupName,
    required String userName,
    required String userProfilePic,
  }) async =>
      'test_bm_id';

  @override
  Future<String?> getBookmarkIdForImage(String imageUrl) async => 'test_bm_id';

  @override
  Stream<List<BookmarkModel>> myBookmarks() => Stream.value([]);

  @override
  Stream<List<BookmarkModel>> allBookmarks() => Stream.value([]);

  @override
  Stream<List<BookmarkModel>> bookmarksForUser(String userId) =>
      Stream.value([]);

  @override
  Future<bool> updateCollectionName({
    required String collectionId,
    required String newName,
  }) async =>
      true;

  @override
  Future<bool> deleteCollection(String collectionId) async => true;

  @override
  Future<bool> addBookmarkToCollection({
    required String collectionId,
    required String bookmarkId,
  }) async =>
      true;

  @override
  Future<bool> addBookmarksToCollection({
    required String collectionId,
    required List<String> bookmarkIds,
  }) async =>
      true;

  @override
  Future<bool> removeBookmarkFromCollection({
    required String collectionId,
    required String bookmarkId,
  }) async =>
      true;
}

void main() {
  group('BookmarkToggleResult Unit Tests', () {
    test('Constructs with isBookmarked = true and bookmarkId', () {
      const result = BookmarkToggleResult(
        isBookmarked: true,
        bookmarkId: 'bm_abc_123',
      );
      expect(result.isBookmarked, isTrue);
      expect(result.bookmarkId, 'bm_abc_123');
    });

    test('Constructs with isBookmarked = false and null bookmarkId', () {
      const result = BookmarkToggleResult(
        isBookmarked: false,
        bookmarkId: null,
      );
      expect(result.isBookmarked, isFalse);
      expect(result.bookmarkId, isNull);
    });
  });

  group('SaveToCollectionSheet Widget Tests', () {
    testWidgets('Renders header, New Collection action, and collection list',
        (tester) async {
      final collections = [
        BookmarkCollectionModel(
          id: 'col_queen_pooja',
          userId: 'test_user',
          name: 'Queen Pooja Hegde',
          coverImageUrl: 'https://example.com/p1.jpg',
          bookmarkIds: const ['existing_bm'],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        BookmarkCollectionModel(
          id: 'col_queen_rashmika',
          userId: 'test_user',
          name: 'Queen Rashmika Mandanna',
          coverImageUrl: 'https://example.com/r1.jpg',
          bookmarkIds: const ['target_bm_id'],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ];

      final fakeController =
          FakeBookmarkController(collections: collections);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bookmarkControllerProvider.overrideWithValue(fakeController),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SaveToCollectionSheet(
                bookmarkId: 'target_bm_id',
                imageUrl: 'https://example.com/r1.jpg',
                userId: 'test_user',
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Header checks
      expect(find.text('Save to Collection'), findsOneWidget);
      expect(find.text('Tap to add or remove from folders'), findsOneWidget);
      expect(find.text('New Collection'), findsOneWidget);

      // Collections checks
      expect(find.text('Queen Pooja Hegde'), findsOneWidget);
      expect(find.text('Queen Rashmika Mandanna'), findsOneWidget);

      // Rashmika already contains 'target_bm_id' -> has check icon
      expect(find.byIcon(Icons.check), findsOneWidget);

      // Tap Queen Pooja Hegde to add to collection
      await tester.tap(find.text('Queen Pooja Hegde'));
      await tester.pump();

      expect(fakeController.toggledColId, 'col_queen_pooja');
      expect(fakeController.toggledBmId, 'target_bm_id');
      expect(fakeController.toggledIsInCol, isFalse);
    });

    testWidgets('Tapping New Collection opens dialog and creates collection',
        (tester) async {
      final fakeController = FakeBookmarkController(collections: const []);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bookmarkControllerProvider.overrideWithValue(fakeController),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SaveToCollectionSheet(
                bookmarkId: 'target_bm_id',
                imageUrl: 'https://example.com/test.jpg',
                userId: 'test_user',
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Tap "New Collection"
      await tester.tap(find.text('New Collection'));
      await tester.pumpAndSettle();

      // Verify dialog is shown
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Collection name'), findsOneWidget);

      // Enter name and submit
      await tester.enterText(find.byType(TextField), 'My Queen Pooja Collection');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      // Dialog dismissed
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('Displays empty state message when no collections exist',
        (tester) async {
      final fakeController = FakeBookmarkController(collections: const []);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bookmarkControllerProvider.overrideWithValue(fakeController),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SaveToCollectionSheet(
                bookmarkId: 'target_bm_id',
                imageUrl: 'https://example.com/test.jpg',
                userId: 'test_user',
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('No collections yet'), findsOneWidget);
      expect(
        find.text('Tap "New Collection" above to create your first folder.'),
        findsOneWidget,
      );
    });
  });
}
