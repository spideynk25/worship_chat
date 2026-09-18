import 'dart:developer';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:worship_chat/common/utils/file_messages.dart';
import 'package:worship_chat/common/utils/utils.dart';
import 'package:worship_chat/models/group_gallery_image.dart';

final groupGalleryRepositoryProvider = Provider(
  (ref) => GroupGalleryRepository(
    firestore: FirebaseFirestore.instance,
    auth: FirebaseAuth.instance,
  ),
);

class GroupGalleryRepository {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  GroupGalleryRepository({required this.firestore, required this.auth});

  // ── Stream all gallery images for a group ─────────────────────────────────
  Stream<List<GroupGalleryImage>> getGalleryStream(String groupId) {
    return firestore
        .collection('groups')
        .doc(groupId)
        .collection('gallery')
        .orderBy('uploadedAt', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            return GroupGalleryImage.fromMap(doc.data());
          }).toList();
        });
  }

  // ── Upload multiple images ────────────────────────────────────────────────
  /// Returns the count of successfully uploaded images.
  Future<int> uploadImages({
    required String groupId,
    required List<File> imageFiles,
    required String uploaderName,
    String? caption,
    void Function(int uploaded, int total)? onProgress,
  }) async {
    final currentUserId = auth.currentUser?.uid;
    if (currentUserId == null) {
      log('❌ uploadImages: no current user');
      return 0;
    }

    int successCount = 0;

    for (int i = 0; i < imageFiles.length; i++) {
      try {
        final file = imageFiles[i];

        // Upload to Cloudinary (reuse existing util)
        final imageUrl = await uploadImageToCloudinary(file, 'gallery');
        if (imageUrl == null || imageUrl.isEmpty) {
          log('⚠️ Cloudinary upload returned null for file $i');
          continue;
        }

        final imageId = const Uuid().v1();
        final galleryImage = GroupGalleryImage(
          imageId: imageId,
          groupId: groupId,
          imageUrl: imageUrl,
          uploadedBy: currentUserId,
          uploadedByName: uploaderName,
          uploadedAt: DateTime.now(),
          caption: (caption != null && caption.trim().isNotEmpty)
              ? caption.trim()
              : null,
        );

        await firestore
            .collection('groups')
            .doc(groupId)
            .collection('gallery')
            .doc(imageId)
            .set(galleryImage.toMap());

        successCount++;
        log('✅ Uploaded gallery image ${i + 1}/${imageFiles.length}');
        onProgress?.call(successCount, imageFiles.length);
      } catch (e) {
        log('❌ Error uploading gallery image $i: $e');
      }
    }

    // Update group doc with gallery count
    try {
      await firestore.collection('groups').doc(groupId).update({
        'galleryCount': FieldValue.increment(successCount),
        'lastGalleryUpdate': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      log('⚠️ Could not update galleryCount on group doc: $e');
    }

    return successCount;
  }

  // ── Delete an image ───────────────────────────────────────────────────────
  Future<void> deleteImage(String groupId, String imageId) async {
    final currentUserId = auth.currentUser?.uid;
    if (currentUserId == null) return;

    try {
      final docRef = firestore
          .collection('groups')
          .doc(groupId)
          .collection('gallery')
          .doc(imageId);

      final doc = await docRef.get();
      if (!doc.exists) return;

      // ✅ Removed the uploadedBy ownership check entirely

      await docRef.delete();

      await firestore.collection('groups').doc(groupId).update({
        'galleryCount': FieldValue.increment(-1),
      });

      log('✅ Deleted gallery image $imageId');
    } catch (e) {
      log('❌ Error deleting gallery image: $e');
    }
  }

  // ── Get total image count ─────────────────────────────────────────────────
  Future<int> getGalleryCount(String groupId) async {
    try {
      final snapshot = await firestore
          .collection('groups')
          .doc(groupId)
          .collection('gallery')
          .count()
          .get();
      return snapshot.count ?? 0;
    } catch (e) {
      log('❌ Error getting gallery count: $e');
      return 0;
    }
  }
}
