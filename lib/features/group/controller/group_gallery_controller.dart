import 'dart:developer';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:worship_chat/features/group/repository/group_gallery_repository.dart';
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

  Future<void> deleteImage(String groupId, String imageId) async {
    try {
      await repository.deleteImage(groupId, imageId);
    } catch (e) {
      log('❌ GroupGalleryController.deleteImage error: $e');
    }
  }

  Future<int> getGalleryCount(String groupId) async {
    return repository.getGalleryCount(groupId);
  }
}