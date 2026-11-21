import 'dart:developer';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:worship_chat/features/bookmark/repository/bookmark_repository.dart';
import 'package:worship_chat/models/bookmark_collection_model.dart';
import 'package:worship_chat/models/bookmark_model.dart';

final bookmarkControllerProvider = Provider(
  (ref) => BookmarkController(
    repository: ref.read(bookmarkRepositoryProvider),
  ),
);

class BookmarkController {
  final BookmarkRepository repository;
  BookmarkController({required this.repository});

  Stream<bool> isBookmarked(String imageUrl) =>
      repository.isBookmarked(imageUrl);

  Future<bool> toggleBookmark({
    required String imageUrl,
    required String groupId,
    required String groupName,
    required String userName,
    required String userProfilePic,
  }) async {
    try {
      return await repository.toggleBookmark(
        imageUrl: imageUrl,
        groupId: groupId,
        groupName: groupName,
        userName: userName,
        userProfilePic: userProfilePic,
      );
    } catch (e) {
      log('❌ BookmarkController.toggleBookmark: $e');
      return false;
    }
  }

  Stream<List<BookmarkModel>> myBookmarks() => repository.myBookmarks();

  Stream<List<BookmarkModel>> allBookmarks() => repository.allBookmarks();

  Stream<List<BookmarkModel>> bookmarksForUser(String userId) =>
      repository.bookmarksForUser(userId);

  Stream<List<BookmarkCollectionModel>> collectionsForUser(String userId) =>
      repository.collectionsForUser(userId);

  Future<String?> getBookmarkIdForImage(String imageUrl) =>
      repository.getBookmarkIdForImage(imageUrl);

  Future<BookmarkCollectionModel?> createCollection({
    required String name,
    List<String> initialBookmarkIds = const [],
    String? coverImageUrl,
  }) async {
    try {
      return await repository.createCollection(
        name: name,
        initialBookmarkIds: initialBookmarkIds,
        coverImageUrl: coverImageUrl,
      );
    } catch (e) {
      log('❌ BookmarkController.createCollection: $e');
      return null;
    }
  }

  Future<bool> updateCollectionName({
    required String collectionId,
    required String newName,
  }) async {
    try {
      return await repository.updateCollectionName(
        collectionId: collectionId,
        newName: newName,
      );
    } catch (e) {
      log('❌ BookmarkController.updateCollectionName: $e');
      return false;
    }
  }

  Future<bool> deleteCollection(String collectionId) async {
    try {
      return await repository.deleteCollection(collectionId);
    } catch (e) {
      log('❌ BookmarkController.deleteCollection: $e');
      return false;
    }
  }

  Future<bool> addBookmarkToCollection({
    required String collectionId,
    required String bookmarkId,
  }) async {
    try {
      return await repository.addBookmarkToCollection(
        collectionId: collectionId,
        bookmarkId: bookmarkId,
      );
    } catch (e) {
      log('❌ BookmarkController.addBookmarkToCollection: $e');
      return false;
    }
  }

  Future<bool> removeBookmarkFromCollection({
    required String collectionId,
    required String bookmarkId,
  }) async {
    try {
      return await repository.removeBookmarkFromCollection(
        collectionId: collectionId,
        bookmarkId: bookmarkId,
      );
    } catch (e) {
      log('❌ BookmarkController.removeBookmarkFromCollection: $e');
      return false;
    }
  }

  Future<bool> addBookmarksToCollection({
    required String collectionId,
    required List<String> bookmarkIds,
  }) async {
    try {
      return await repository.addBookmarksToCollection(
        collectionId: collectionId,
        bookmarkIds: bookmarkIds,
      );
    } catch (e) {
      log('❌ BookmarkController.addBookmarksToCollection: $e');
      return false;
    }
  }

  Future<bool> toggleBookmarkInCollection({
    required String collectionId,
    required String bookmarkId,
    required bool isInCollection,
  }) async {
    try {
      return await repository.toggleBookmarkInCollection(
        collectionId: collectionId,
        bookmarkId: bookmarkId,
        isInCollection: isInCollection,
      );
    } catch (e) {
      log('❌ BookmarkController.toggleBookmarkInCollection: $e');
      return false;
    }
  }
}