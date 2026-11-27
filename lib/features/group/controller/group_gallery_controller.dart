import 'dart:developer';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:worship_chat/features/group/repository/group_gallery_repository.dart';
import 'package:worship_chat/models/group.dart';
import 'package:worship_chat/models/group_gallery_image.dart';

final groupGalleryControllerProvider = Provider((ref) {
  final repository = ref.read(groupGalleryRepositoryProvider);
  return GroupGalleryController(repository: repository);
});

class GroupGalleryController {
  final GroupGalleryRepository repository;

  GroupGalleryController({required this.repository});

  Stream<List<GroupGalleryImage>> getGalleryStream(String groupId) {
    return repository.getGalleryStream(groupId);
  }

  Future<List<GroupGalleryImage>> getMultiGalleryImages(List<String> groupIds) {
    return repository.getMultiGalleryImages(groupIds);
  }

  Future<List<GroupGalleryImage>> getAllGalleryImagesForPicker(
    List<String> groupIds, {
    int maxPerGroup = 60,
  }) {
    return repository.getAllGalleryImagesForPicker(
      groupIds,
      maxPerGroup: maxPerGroup,
    );
  }

  Future<int> uploadImages({
    required String groupId,
    required List<File> imageFiles,
    required String uploaderName,
    String? caption,
    void Function(int uploaded, int total)? onProgress,
  }) async {
    try {
      return await repository.uploadImages(
        groupId: groupId,
        imageFiles: imageFiles,
        uploaderName: uploaderName,
        caption: caption,
        onProgress: onProgress,
      );
    } catch (e) {
      log('❌ GroupGalleryController.uploadImages error: $e');
      return 0;
    }
  }

  Future<int> uploadVideos({
    required String groupId,
    required List<File> videoFiles,
    required String uploaderName,
    String? caption,
    void Function(int uploaded, int total)? onProgress,
  }) async {
    try {
      return await repository.uploadVideos(
        groupId: groupId,
        videoFiles: videoFiles,
        uploaderName: uploaderName,
        caption: caption,
        onProgress: onProgress,
      );
    } catch (e) {
      log('❌ GroupGalleryController.uploadVideos error: $e');
      return 0;
    }
  }

  Future<void> deleteImage(String groupId, String imageId) async {
    try {
      await repository.deleteImage(groupId, imageId);
    } catch (e) {
      log('❌ GroupGalleryController.deleteImage error: $e');
    }
  }

  Future<bool> addGalleryImageFromUrl({
    required String groupId,
    required String imageUrl,
    required String uploaderName,
    String? caption,
  }) async {
    try {
      return await repository.addGalleryImageFromUrl(
        groupId: groupId,
        imageUrl: imageUrl,
        uploaderName: uploaderName,
        caption: caption,
      );
    } catch (e) {
      log('❌ GroupGalleryController.addGalleryImageFromUrl error: $e');
      return false;
    }
  }

  Future<int> getGalleryCount(String groupId) async {
    return repository.getGalleryCount(groupId);
  }

  Future<List<GroupGalleryImage>> getCachedRecentGalleryPhotos(String uid) {
    return repository.getCachedRecentGalleryPhotos(uid);
  }

  Future<List<GroupGalleryImage>> getRecentGalleryPhotos({
    required List<GroupModel> groups,
    int limit = 24,
    int limitPerGroup = 8,
    int maxGroupsToQuery = 16,
    bool photosOnly = true,
    bool saveCache = true,
  }) async {
    try {
      return await repository.getRecentGalleryPhotos(
        groups: groups,
        limit: limit,
        limitPerGroup: limitPerGroup,
        maxGroupsToQuery: maxGroupsToQuery,
        photosOnly: photosOnly,
        saveCache: saveCache,
      );
    } catch (e) {
      log('❌ GroupGalleryController.getRecentGalleryPhotos error: $e');
      return const [];
    }
  }
}