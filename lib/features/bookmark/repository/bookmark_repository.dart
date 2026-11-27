import 'dart:developer';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:worship_chat/models/bookmark_collection_model.dart';
import 'package:worship_chat/models/bookmark_model.dart';

class BookmarkToggleResult {
  final bool isBookmarked;
  final String? bookmarkId;

  const BookmarkToggleResult({
    required this.isBookmarked,
    this.bookmarkId,
  });
}

final bookmarkRepositoryProvider = Provider(
  (ref) => BookmarkRepository(
    firestore: FirebaseFirestore.instance,
    auth: FirebaseAuth.instance,
  ),
);

class BookmarkRepository {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  BookmarkRepository({required this.firestore, required this.auth});

  String? get _uid => auth.currentUser?.uid;

  // ── Check if image is bookmarked by current user ──────────────────────────
  Stream<bool> isBookmarked(String imageUrl) {
    if (_uid == null) return Stream.value(false);
    return firestore
        .collection('bookmarks')
        .where('userId', isEqualTo: _uid)
        .where('imageUrl', isEqualTo: imageUrl)
        .snapshots()
        .map((snap) => snap.docs.isNotEmpty);
  }

  // ── Toggle bookmark with result ───────────────────────────────────────────
  Future<BookmarkToggleResult> toggleBookmarkWithResult({
    required String imageUrl,
    required String groupId,
    required String groupName,
    required String userName,
    required String userProfilePic,
  }) async {
    if (_uid == null) {
      return const BookmarkToggleResult(isBookmarked: false, bookmarkId: null);
    }
    try {
      final existing = await firestore
          .collection('bookmarks')
          .where('userId', isEqualTo: _uid)
          .where('imageUrl', isEqualTo: imageUrl)
          .get();

      if (existing.docs.isNotEmpty) {
        final deletedId = existing.docs.first.id;
        await existing.docs.first.reference.delete();
        // Clean up bookmark ID from user's collections
        try {
          final colSnap = await firestore
              .collection('bookmark_collections')
              .where('userId', isEqualTo: _uid)
              .where('bookmarkIds', arrayContains: deletedId)
              .get();
          for (final doc in colSnap.docs) {
            await doc.reference.update({
              'bookmarkIds': FieldValue.arrayRemove([deletedId]),
              'updatedAt': DateTime.now().millisecondsSinceEpoch,
            });
          }
        } catch (e) {
          log('⚠️ Error cleaning bookmark from collections: $e');
        }
        return const BookmarkToggleResult(isBookmarked: false, bookmarkId: null);
      } else {
        String latestPic = userProfilePic;
        String latestName = userName;
        try {
          final userDoc = await firestore.collection('users').doc(_uid).get();
          if (userDoc.exists && userDoc.data() != null) {
            final uData = userDoc.data()!;
            final p = uData['profilePic'] as String?;
            if (p != null && p.isNotEmpty) latestPic = p;
            final n = uData['name'] as String?;
            if (n != null && n.isNotEmpty) latestName = n;
          }
        } catch (_) {}

        final id = const Uuid().v1();
        final bookmark = BookmarkModel(
          bookmarkId: id,
          userId: _uid!,
          userName: latestName,
          userProfilePic: latestPic,
          imageUrl: imageUrl,
          groupId: groupId,
          groupName: groupName,
          bookmarkedAt: DateTime.now(),
        );
        await firestore
            .collection('bookmarks')
            .doc(id)
            .set(bookmark.toMap());
        return BookmarkToggleResult(isBookmarked: true, bookmarkId: id);
      }
    } catch (e) {
      log('❌ toggleBookmark error: $e');
      return const BookmarkToggleResult(isBookmarked: false, bookmarkId: null);
    }
  }

  // ── Toggle bookmark ───────────────────────────────────────────────────────
  Future<bool> toggleBookmark({
    required String imageUrl,
    required String groupId,
    required String groupName,
    required String userName,
    required String userProfilePic,
  }) async {
    final result = await toggleBookmarkWithResult(
      imageUrl: imageUrl,
      groupId: groupId,
      groupName: groupName,
      userName: userName,
      userProfilePic: userProfilePic,
    );
    return result.isBookmarked;
  }

  // ── Ensure bookmarked (returns bookmark ID) ──────────────────────────────
  Future<String?> ensureBookmarked({
    required String imageUrl,
    required String groupId,
    required String groupName,
    required String userName,
    required String userProfilePic,
  }) async {
    if (_uid == null) return null;
    try {
      final existing = await firestore
          .collection('bookmarks')
          .where('userId', isEqualTo: _uid)
          .where('imageUrl', isEqualTo: imageUrl)
          .limit(1)
          .get();
      if (existing.docs.isNotEmpty) {
        return existing.docs.first.id;
      }
      final res = await toggleBookmarkWithResult(
        imageUrl: imageUrl,
        groupId: groupId,
        groupName: groupName,
        userName: userName,
        userProfilePic: userProfilePic,
      );
      return res.bookmarkId;
    } catch (e) {
      log('❌ ensureBookmarked error: $e');
      return null;
    }
  }

  // ── My bookmarks ──────────────────────────────────────────────────────────
  Stream<List<BookmarkModel>> myBookmarks() {
    if (_uid == null) return Stream.value([]);
    return firestore
        .collection('bookmarks')
        .where('userId', isEqualTo: _uid)
        .orderBy('bookmarkedAt', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => BookmarkModel.fromMap(d.data())).toList());
  }

  // ── All bookmarks grouped by user ─────────────────────────────────────────
  Stream<List<BookmarkModel>> allBookmarks() {
    return firestore
        .collection('bookmarks')
        .orderBy('bookmarkedAt', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => BookmarkModel.fromMap(d.data())).toList());
  }

  // ── Bookmarks for a specific user ─────────────────────────────────────────
  Stream<List<BookmarkModel>> bookmarksForUser(String userId) {
    return firestore
        .collection('bookmarks')
        .where('userId', isEqualTo: userId)
        .orderBy('bookmarkedAt', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => BookmarkModel.fromMap(d.data())).toList());
  }

  // ── Find Bookmark ID for image ────────────────────────────────────────────
  Future<String?> getBookmarkIdForImage(String imageUrl) async {
    if (_uid == null) return null;
    try {
      final snap = await firestore
          .collection('bookmarks')
          .where('userId', isEqualTo: _uid)
          .where('imageUrl', isEqualTo: imageUrl)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        return snap.docs.first.id;
      }
    } catch (e) {
      log('❌ getBookmarkIdForImage error: $e');
    }
    return null;
  }

  // ── Collections for a specific user ───────────────────────────────────────
  Stream<List<BookmarkCollectionModel>> collectionsForUser(String userId) {
    return firestore
        .collection('bookmark_collections')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map((d) => BookmarkCollectionModel.fromMap(d.data()))
          .toList();
      list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return list;
    });
  }

  // ── Create a new collection / folder ──────────────────────────────────────
  Future<BookmarkCollectionModel?> createCollection({
    required String name,
    List<String> initialBookmarkIds = const [],
    String? coverImageUrl,
  }) async {
    if (_uid == null) return null;
    try {
      final trimmedName = name.trim();
      if (trimmedName.isEmpty) return null;
      final now = DateTime.now();
      final id = const Uuid().v1();
      final collection = BookmarkCollectionModel(
        id: id,
        userId: _uid!,
        name: trimmedName,
        coverImageUrl: coverImageUrl,
        bookmarkIds: initialBookmarkIds,
        createdAt: now,
        updatedAt: now,
      );
      await firestore
          .collection('bookmark_collections')
          .doc(id)
          .set(collection.toMap());
      return collection;
    } catch (e) {
      log('❌ createCollection error: $e');
      return null;
    }
  }

  // ── Update collection name ────────────────────────────────────────────────
  Future<bool> updateCollectionName({
    required String collectionId,
    required String newName,
  }) async {
    try {
      final trimmed = newName.trim();
      if (trimmed.isEmpty) return false;
      await firestore
          .collection('bookmark_collections')
          .doc(collectionId)
          .update({
        'name': trimmed,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
      return true;
    } catch (e) {
      log('❌ updateCollectionName error: $e');
      return false;
    }
  }

  // ── Delete a collection (keeps bookmarks intact) ──────────────────────────
  Future<bool> deleteCollection(String collectionId) async {
    try {
      await firestore
          .collection('bookmark_collections')
          .doc(collectionId)
          .delete();
      return true;
    } catch (e) {
      log('❌ deleteCollection error: $e');
      return false;
    }
  }

  // ── Add single bookmark to collection ─────────────────────────────────────
  Future<bool> addBookmarkToCollection({
    required String collectionId,
    required String bookmarkId,
  }) async {
    try {
      await firestore
          .collection('bookmark_collections')
          .doc(collectionId)
          .update({
        'bookmarkIds': FieldValue.arrayUnion([bookmarkId]),
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
      return true;
    } catch (e) {
      log('❌ addBookmarkToCollection error: $e');
      return false;
    }
  }

  // ── Remove single bookmark from collection ────────────────────────────────
  Future<bool> removeBookmarkFromCollection({
    required String collectionId,
    required String bookmarkId,
  }) async {
    try {
      await firestore
          .collection('bookmark_collections')
          .doc(collectionId)
          .update({
        'bookmarkIds': FieldValue.arrayRemove([bookmarkId]),
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
      return true;
    } catch (e) {
      log('❌ removeBookmarkFromCollection error: $e');
      return false;
    }
  }

  /// Replaces the image URL on an existing bookmark document while keeping all
  /// collection memberships intact.
  Future<bool> replaceBookmarkImage({
    required String bookmarkId,
    required String newImageUrl,
  }) async {
    if (_uid == null || bookmarkId.trim().isEmpty || newImageUrl.trim().isEmpty) {
      return false;
    }
    try {
      await firestore.collection('bookmarks').doc(bookmarkId).update({
        'imageUrl': newImageUrl.trim(),
        'bookmarkedAt': DateTime.now().millisecondsSinceEpoch,
      });
      return true;
    } catch (e) {
      log('❌ replaceBookmarkImage error: $e');
      return false;
    }
  }

  // ── Add multiple bookmarks to collection ──────────────────────────────────
  Future<bool> addBookmarksToCollection({
    required String collectionId,
    required List<String> bookmarkIds,
  }) async {
    if (bookmarkIds.isEmpty) return true;
    try {
      await firestore
          .collection('bookmark_collections')
          .doc(collectionId)
          .update({
        'bookmarkIds': FieldValue.arrayUnion(bookmarkIds),
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
      return true;
    } catch (e) {
      log('❌ addBookmarksToCollection error: $e');
      return false;
    }
  }

  // ── Toggle bookmark in collection ─────────────────────────────────────────
  Future<bool> toggleBookmarkInCollection({
    required String collectionId,
    required String bookmarkId,
    required bool isInCollection,
  }) async {
    if (isInCollection) {
      return removeBookmarkFromCollection(
        collectionId: collectionId,
        bookmarkId: bookmarkId,
      );
    } else {
      return addBookmarkToCollection(
        collectionId: collectionId,
        bookmarkId: bookmarkId,
      );
    }
  }
}