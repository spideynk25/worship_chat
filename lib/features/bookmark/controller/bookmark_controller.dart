import 'dart:developer';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:worship_chat/features/bookmark/repository/bookmark_repository.dart';
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
}