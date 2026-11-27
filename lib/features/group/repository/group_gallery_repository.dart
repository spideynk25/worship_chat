import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:worship_chat/common/utils/background_task_service.dart';
import 'package:worship_chat/common/utils/file_messages.dart';
import 'package:worship_chat/common/utils/utils.dart';
import 'package:worship_chat/models/group.dart';
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

  static const String _recentCachePrefix = 'recent_gallery_photos_v1_';

  /// Ranks user groups so recently updated / populated galleries are queried first.
  @visibleForTesting
  static List<GroupModel> selectGroupsForRecentFetch(
    List<GroupModel> groups, {
    int maxGroups = 16,
  }) {
    final seen = <String>{};
    final unique = <GroupModel>[];
    for (final g in groups) {
      if (g.groupId.trim().isEmpty || !seen.add(g.groupId)) continue;
      unique.add(g);
    }

    int compareGroups(GroupModel a, GroupModel b) {
      final aHasGallery = a.galleryCount > 0 || a.lastGalleryUpdate != null;
      final bHasGallery = b.galleryCount > 0 || b.lastGalleryUpdate != null;
      if (aHasGallery != bHasGallery) return aHasGallery ? -1 : 1;

      final aGalleryMs = a.lastGalleryUpdate?.millisecondsSinceEpoch ?? 0;
      final bGalleryMs = b.lastGalleryUpdate?.millisecondsSinceEpoch ?? 0;
      if (aGalleryMs != bGalleryMs) return bGalleryMs.compareTo(aGalleryMs);

      final aMsgMs = a.timeSent?.millisecondsSinceEpoch ?? 0;
      final bMsgMs = b.timeSent?.millisecondsSinceEpoch ?? 0;
      if (aMsgMs != bMsgMs) return bMsgMs.compareTo(aMsgMs);

      if (a.galleryCount != b.galleryCount) {
        return b.galleryCount.compareTo(a.galleryCount);
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    }

    unique.sort(compareGroups);
    return unique.take(maxGroups).toList();
  }

  /// Merges per-group gallery slices, removes duplicates, filters media if needed,
  /// and returns newest-first entries capped to [maxItems].
  @visibleForTesting
  static List<GroupGalleryImage> mergeAndSortRecentPhotos(
    List<List<GroupGalleryImage>> perGroupLists, {
    int maxItems = 30,
    bool photosOnly = true,
  }) {
    final seenIds = <String>{};
    final merged = <GroupGalleryImage>[];
    for (final list in perGroupLists) {
      for (final img in list) {
        final cleanUrl = img.imageUrl.trim();
        if (cleanUrl.isEmpty) continue;
        if (photosOnly && img.isVideo) continue;
        final dedupeKey =
            img.imageId.trim().isNotEmpty ? img.imageId.trim() : cleanUrl;
        if (!seenIds.add(dedupeKey)) continue;
        merged.add(img);
      }
    }
    merged.sort((a, b) => b.uploadedAt.compareTo(a.uploadedAt));
    if (merged.length > maxItems) {
      return merged.sublist(0, maxItems);
    }
    return merged;
  }

  @visibleForTesting
  static List<GroupGalleryImage> decodeRecentPhotosCache(String rawJson) {
    if (rawJson.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! List) return const [];
      final out = <GroupGalleryImage>[];
      for (final item in decoded) {
        if (item is Map) {
          final img = GroupGalleryImage.fromMap(Map<String, dynamic>.from(item));
          if (img.imageUrl.trim().isNotEmpty) {
            out.add(img);
          }
        }
      }
      out.sort((a, b) => b.uploadedAt.compareTo(a.uploadedAt));
      return out;
    } catch (e) {
      log('Error decoding recent gallery cache: $e');
      return const [];
    }
  }

  @visibleForTesting
  static String encodeRecentPhotosCache(List<GroupGalleryImage> items) {
    return jsonEncode(items.map((e) => e.toMap()).toList());
  }

  Future<List<GroupGalleryImage>> getCachedRecentGalleryPhotos(String uid) async {
    if (uid.trim().isEmpty) return const [];
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_recentCachePrefix$uid');
      if (raw == null || raw.isEmpty) return const [];
      return decodeRecentPhotosCache(raw);
    } catch (e) {
      log('Error loading recent gallery cache: $e');
      return const [];
    }
  }

  Future<void> _saveRecentGalleryCache(
    String uid,
    List<GroupGalleryImage> items,
  ) async {
    if (uid.trim().isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_recentCachePrefix$uid',
        encodeRecentPhotosCache(items),
      );
    } catch (e) {
      log('Error saving recent gallery cache: $e');
    }
  }

  /// Fetches recently added gallery media across the user's groups, ordered
  /// newest first, and optionally updates local cache for instant next-open display.
  Future<List<GroupGalleryImage>> getRecentGalleryPhotos({
    required List<GroupModel> groups,
    int limit = 24,
    int limitPerGroup = 8,
    int maxGroupsToQuery = 16,
    bool photosOnly = true,
    bool saveCache = true,
  }) async {
    final prioritized = selectGroupsForRecentFetch(
      groups,
      maxGroups: maxGroupsToQuery,
    );
    if (prioritized.isEmpty) return const [];

    final perGroupResults = <List<GroupGalleryImage>>[];
    for (int i = 0; i < prioritized.length; i += 8) {
      final chunk = prioritized.sublist(
        i,
        i + 8 > prioritized.length ? prioritized.length : i + 8,
      );
      final chunkLists = await Future.wait(
        chunk.map((group) async {
          try {
            final snapshot = await firestore
                .collection('groups')
                .doc(group.groupId)
                .collection('gallery')
                .orderBy('uploadedAt', descending: true)
                .limit(limitPerGroup)
                .get();
            return snapshot.docs
                .map((doc) => GroupGalleryImage.fromMap(doc.data()))
                .toList();
          } catch (e) {
            log('Error fetching recent photos for group ${group.groupId}: $e');
            return const <GroupGalleryImage>[];
          }
        }),
      );
      perGroupResults.addAll(chunkLists);
    }

    final merged = mergeAndSortRecentPhotos(
      perGroupResults,
      maxItems: limit,
      photosOnly: photosOnly,
    );

    if (saveCache && photosOnly) {
      final uid = auth.currentUser?.uid ?? '';
      if (uid.isNotEmpty) {
        await _saveRecentGalleryCache(uid, merged.take(24).toList());
      }
    }
    return merged;
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
