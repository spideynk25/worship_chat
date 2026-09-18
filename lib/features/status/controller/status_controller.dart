import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:worship_chat/features/status/repository/status_repository.dart';

final statusControllerProvider = Provider((ref) {
  final statusRepository = ref.read(statusRepositoryProvider);
  return StatusController(statusRepository: statusRepository, ref: ref);
});

final statusStreamProvider = StreamProvider((ref) {
  return ref.read(statusControllerProvider).getStatuses();
});

class StatusController {
  final StatusRepository statusRepository;
  final ProviderRef ref;

  StatusController({required this.statusRepository, required this.ref});

  Future<void> uploadStatus({
    required String userName,
    required String profilePic,
    required String email,
    required File statusFile,
    required bool isVideo,
    required BuildContext context,
  }) async {
    await statusRepository.uploadStatus(
      userName: userName,
      profilePic: profilePic,
      email: email,
      statusFile: statusFile,
      isVideo: isVideo,
      context: context,
    );
  }

  Stream<List<Map<String, dynamic>>> getStatuses() {
    return statusRepository.getStatuses();
  }

  Future<void> markStatusAsSeen({
    required String statusId,
    required String viewerUid,
    required String viewerName,
    required String viewerProfilePic,
  }) async {
    await statusRepository.markStatusAsSeen(
      statusId: statusId,
      viewerUid: viewerUid,
      viewerName: viewerName,
      viewerProfilePic: viewerProfilePic,
    );
  }

  Stream<List<Map<String, dynamic>>> getStatusViewers(String statusId) {
    return statusRepository.getStatusViewers(statusId);
  }

  // ── Likes ──────────────────────────────────────────────────────────────────

  Future<bool> toggleLike({
    required String statusId,
    required String likerUid,
    required String likerName,
    required String likerProfilePic,
  }) {
    return statusRepository.toggleLike(
      statusId: statusId,
      likerUid: likerUid,
      likerName: likerName,
      likerProfilePic: likerProfilePic,
    );
  }

  Stream<Map<String, dynamic>> getLikesStream(String statusId) {
    return statusRepository.getLikesStream(statusId);
  }
}