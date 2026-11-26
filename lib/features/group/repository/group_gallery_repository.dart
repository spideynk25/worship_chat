import 'dart:developer';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:worship_chat/common/utils/background_task_service.dart';
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

  /// Fetches gallery images across multiple group IDs in parallel chunks for
  /// picker UIs, excluding videos and sorting newest-first.
  Future<List<GroupGalleryImage>> getAllGalleryImagesForPicker(
    List<String> groupIds, {
    int maxPerGroup = 60,
  }) async {
    final allImages = <GroupGalleryImage>[];
    for (int i = 0; i < groupIds.length; i += 8) {
      final chunk = groupIds.sublist(
        i,
        i + 8 > groupIds.length ? groupIds.length : i + 8,
      );
      final chunkResults = await Future.wait(
        chunk.map((id) async {
          try {
            final snapshot = await firestore
                .collection('groups')
                .doc(id)
                .collection('gallery')
                .orderBy('uploadedAt', descending: true)
                .limit(maxPerGroup)
                .get();
            return snapshot.docs
                .map((doc) => GroupGalleryImage.fromMap(doc.data()))
                .where((img) => !img.isVideo && img.imageUrl.trim().isNotEmpty)
                .toList();
          } catch (e) {
            log('Error fetching picker gallery for group $id: $e');
            return const <GroupGalleryImage>[];
          }
        }),
      );
      for (final list in chunkResults) {
        allImages.addAll(list);
      }
    }
    allImages.sort((a, b) => b.uploadedAt.compareTo(a.uploadedAt));
    return allImages;
  }

  /// Fetches gallery images across multiple group IDs for multi-gallery shuffling
  Future<List<GroupGalleryImage>> getMultiGalleryImages(List<String> groupIds) async {
    final allImages = <GroupGalleryImage>[];
    for (final id in groupIds) {
      try {
        final snapshot = await firestore
            .collection('groups')
            .doc(id)
            .collection('gallery')
            .get();
        final images = snapshot.docs
            .map((doc) => GroupGalleryImage.fromMap(doc.data()))
            .toList();
        allImages.addAll(images);
      } catch (e) {
        log('Error fetching multi-gallery for group $id: $e');
      }
    }
    return allImages;
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

    if (imageFiles.isEmpty) return 0;

    return await BackgroundTaskService.instance.runWithBackgroundTask<int>(
      title: 'Uploading to Gallery',
      initialMessage: 'Uploading 1 of ${imageFiles.length} photos...',
      successMessage: '${imageFiles.length} photo${imageFiles.length == 1 ? '' : 's'} added to gallery',
      task: (updateProgress) async {
        int successCount = 0;

        for (int i = 0; i < imageFiles.length; i++) {
          try {
            final file = imageFiles[i];
            updateProgress(
              'Uploading photo ${i + 1} of ${imageFiles.length}...',
              progress: i,
              maxProgress: imageFiles.length,
            );

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
            updateProgress(
              'Uploaded $successCount of ${imageFiles.length} photos',
              progress: successCount,
              maxProgress: imageFiles.length,
            );
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
      },
    );
  }

  // ── Upload multiple videos ────────────────────────────────────────────────
  /// Returns the count of successfully uploaded videos.
  Future<int> uploadVideos({
    required String groupId,
    required List<File> videoFiles,
    required String uploaderName,
    String? caption,
    void Function(int uploaded, int total)? onProgress,
  }) async {
    final currentUserId = auth.currentUser?.uid;
    if (currentUserId == null) {
      log('❌ uploadVideos: no current user');
      return 0;
    }

    if (videoFiles.isEmpty) return 0;

    return await BackgroundTaskService.instance.runWithBackgroundTask<int>(
      title: 'Uploading to Gallery',
      initialMessage: 'Uploading 1 of ${videoFiles.length} videos...',
      successMessage:
          '${videoFiles.length} video${videoFiles.length == 1 ? '' : 's'} added to gallery',
      task: (updateProgress) async {
        int successCount = 0;

        for (int i = 0; i < videoFiles.length; i++) {
          try {
            final file = videoFiles[i];
            updateProgress(
              'Uploading video ${i + 1} of ${videoFiles.length}...',
              progress: i,
              maxProgress: videoFiles.length,
            );

            // Upload video to Cloudinary
            final videoUrl = await uploadVideoToCloudinary(file, 'gallery');
            if (videoUrl == null || videoUrl.isEmpty) {
              log('⚠️ Cloudinary video upload returned null for file $i');
              continue;
            }

            final imageId = const Uuid().v1();
            final galleryVideo = GroupGalleryImage(
              imageId: imageId,
              groupId: groupId,
              imageUrl: videoUrl,
              uploadedBy: currentUserId,
              uploadedByName: uploaderName,
              uploadedAt: DateTime.now(),
              caption: (caption != null && caption.trim().isNotEmpty)
                  ? caption.trim()
                  : null,
              mediaType: 'video',
            );

            await firestore
                .collection('groups')
                .doc(groupId)
                .collection('gallery')
                .doc(imageId)
                .set(galleryVideo.toMap());

            successCount++;
            log('✅ Uploaded gallery video ${i + 1}/${videoFiles.length}');
            onProgress?.call(successCount, videoFiles.length);
            updateProgress(
              'Uploaded $successCount of ${videoFiles.length} videos',
              progress: successCount,
              maxProgress: videoFiles.length,
            );
          } catch (e) {
            log('❌ Error uploading gallery video $i: $e');
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
      },
    );
  }

  // ── Add single image from existing URL (Forwarding) ──────────────────────
  Future<bool> addGalleryImageFromUrl({
    required String groupId,
    required String imageUrl,
    required String uploaderName,
    String? caption,
  }) async {
    if (imageUrl.trim().isEmpty) {
      log('❌ addGalleryImageFromUrl: empty imageUrl');
      return false;
    }

    final currentUserId = auth.currentUser?.uid;
    if (currentUserId == null) {
      log('❌ addGalleryImageFromUrl: no authenticated user');
      return false;
    }

    try {
      final imageId = const Uuid().v1();
      final isVideo = imageUrl.contains('/video/upload') ||
          imageUrl.toLowerCase().endsWith('.mp4') ||
          imageUrl.toLowerCase().endsWith('.mov') ||
          imageUrl.toLowerCase().endsWith('.webm') ||
          imageUrl.toLowerCase().endsWith('.m4v');
      final cleanUrl = isVideo
          ? imageUrl.trim()
          : getOriginalHighQualityImageUrl(imageUrl.trim());
      final galleryImage = GroupGalleryImage(
        imageId: imageId,
        groupId: groupId,
        imageUrl: cleanUrl,
        uploadedBy: currentUserId,
        uploadedByName: uploaderName,
        uploadedAt: DateTime.now(),
        caption: (caption != null && caption.trim().isNotEmpty)
            ? caption.trim()
            : null,
        mediaType: isVideo ? 'video' : 'image',
      );

      await firestore
          .collection('groups')
          .doc(groupId)
          .collection('gallery')
          .doc(imageId)
          .set(galleryImage.toMap());

      await firestore.collection('groups').doc(groupId).set({
        'galleryCount': FieldValue.increment(1),
        'lastGalleryUpdate': DateTime.now().millisecondsSinceEpoch,
      }, SetOptions(merge: true));

      log('✅ Forwarded image to gallery: $imageId in group $groupId');
      return true;
    } catch (e) {
      log('❌ Error adding gallery image from url: $e');
      return false;
    }
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
