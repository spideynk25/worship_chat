import 'dart:developer';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:worship_chat/models/bookmark_model.dart';

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

  // ── Toggle bookmark ───────────────────────────────────────────────────────
  Future<bool> toggleBookmark({
    required String imageUrl,
    required String groupId,
    required String groupName,
    required String userName,
    required String userProfilePic,
  }) async {
    if (_uid == null) return false;
    try {
      final existing = await firestore
          .collection('bookmarks')
          .where('userId', isEqualTo: _uid)
          .where('imageUrl', isEqualTo: imageUrl)
          .get();

      if (existing.docs.isNotEmpty) {
        await existing.docs.first.reference.delete();
        return false;
      } else {
        final id = const Uuid().v1();
        final bookmark = BookmarkModel(
          bookmarkId: id,
          userId: _uid!,
          userName: userName,
          userProfilePic: userProfilePic,
          imageUrl: imageUrl,
          groupId: groupId,
          groupName: groupName,
          bookmarkedAt: DateTime.now(),
        );
        await firestore
            .collection('bookmarks')
            .doc(id)
            .set(bookmark.toMap());
        return true;
      }
    } catch (e) {
      log('❌ toggleBookmark error: $e');
      return false;
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
}