import 'dart:developer';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloudinary_flutter/cloudinary_context.dart';
import 'package:cloudinary_url_gen/cloudinary.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:worship_chat/common/utils/utils.dart';

final statusRepositoryProvider = Provider((ref) {
  return StatusRepository(
    firestore: FirebaseFirestore.instance,
    auth: FirebaseAuth.instance,
    ref: ref,
  );
});

class StatusRepository {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final ProviderRef ref;

  static const _uploadPreset = 'ml_default'; // 👈 change this
  static const _cloudName = 'djr22nlx9';

  StatusRepository({
    required this.firestore,
    required this.auth,
    required this.ref,
  });

  // ── HTTPS sanitizer ────────────────────────────────────────────────────────

  static String _toHttps(String url) =>
      url.startsWith('http://') ? url.replaceFirst('http://', 'https://') : url;

  static Map<String, dynamic> _sanitizeStatus(Map<String, dynamic> data) {
    final sanitized = Map<String, dynamic>.from(data);
    if (sanitized['statusUrl'] is String) {
      sanitized['statusUrl'] = _toHttps(sanitized['statusUrl'] as String);
    }
    if (sanitized['profilePic'] is String) {
      sanitized['profilePic'] = _toHttps(sanitized['profilePic'] as String);
    }
    return sanitized;
  }

  // ── Cloudinary URL optimiser ───────────────────────────────────────────────

  static String _optimiseUrl(String raw, {bool isVideo = false}) {
    var url = raw.replaceFirst('http://', 'https://');
    const insertAfter = '/upload/';
    final idx = url.indexOf(insertAfter);
    if (idx != -1) {
      final transform = isVideo ? 'f_auto,q_auto:good' : 'f_auto,q_auto,w_1080';
      url =
          url.substring(0, idx + insertAfter.length) +
          '$transform/' +
          url.substring(idx + insertAfter.length);
    }
    return url;
  }

  // ── Upload status ──────────────────────────────────────────────────────────

  Future<void> uploadStatus({
    required String userName,
    required String profilePic,
    required String email,
    required File statusFile,
    required bool isVideo,
    required BuildContext context,
  }) async {
    try {
      final currentUser = auth.currentUser!;
      final uid = currentUser.uid;
      final statusId = const Uuid().v1();
      final timeCreated = DateTime.now();

      final statusUrl = isVideo
          ? await _uploadVideoToCloudinary(statusFile)
          : await _uploadImageToCloudinary(statusFile);

      if (statusUrl == null) {
        throw Exception(
          'Failed to upload ${isVideo ? 'video' : 'image'} to Cloudinary. '
          'Check your upload preset and network connection.',
        );
      }

      final chatsSnapshot = await firestore
          .collection('users')
          .doc(uid)
          .collection('chats')
          .get();

      final List<String> visibleTo =
          chatsSnapshot.docs.map((doc) => doc.id).toList()..add(uid);

      await firestore.collection('status').doc(statusId).set({
        'statusId': statusId,
        'uid': uid,
        'userName': userName,
        'email': email,
        'profilePic': _toHttps(profilePic),
        'statusUrl': statusUrl,
        'mediaType': isVideo ? 'video' : 'image',
        'timeCreated': Timestamp.fromDate(timeCreated),
        'visibleTo': visibleTo,
        'seenBy': {},
        'likes': {}, // { uid: { userName, profilePic, likedAt } }
      });
    } catch (e) {
      log('uploadStatus error: $e');
      showSnackBar(context: context, content: e.toString());
    }
  }

  // ── Seen tracking ──────────────────────────────────────────────────────────

  Future<void> markStatusAsSeen({
    required String statusId,
    required String viewerUid,
    required String viewerName,
    required String viewerProfilePic,
  }) async {
    try {
      await firestore.collection('status').doc(statusId).update({
        'seenBy.$viewerUid': {
          'userName': viewerName,
          'profilePic': _toHttps(viewerProfilePic),
          'seenAt': FieldValue.serverTimestamp(),
        },
      });
    } catch (e) {
      log('markStatusAsSeen error: $e');
    }
  }

  Stream<List<Map<String, dynamic>>> getStatusViewers(String statusId) {
    return firestore.collection('status').doc(statusId).snapshots().map((doc) {
      if (!doc.exists) return [];
      final data = doc.data()!;
      final seenBy = Map<String, dynamic>.from(data['seenBy'] as Map? ?? {});
      return seenBy.entries.map((entry) {
        final v = Map<String, dynamic>.from(entry.value as Map);
        return {
          'uid': entry.key,
          'userName': v['userName'] ?? '',
          'profilePic': _toHttps((v['profilePic'] as String?) ?? ''),
          'seenAt': (v['seenAt'] as Timestamp?)?.toDate(),
        };
      }).toList()..sort((a, b) {
        final aTime = a['seenAt'] as DateTime?;
        final bTime = b['seenAt'] as DateTime?;
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime);
      });
    });
  }

  // ── Likes ──────────────────────────────────────────────────────────────────

  /// Toggles like. Returns true = now liked, false = unliked.
  Future<bool> toggleLike({
    required String statusId,
    required String likerUid,
    required String likerName,
    required String likerProfilePic,
  }) async {
    try {
      final docRef = firestore.collection('status').doc(statusId);
      final doc = await docRef.get();
      if (!doc.exists) return false;

      final likes = Map<String, dynamic>.from(
        doc.data()!['likes'] as Map? ?? {},
      );
      final alreadyLiked = likes.containsKey(likerUid);

      if (alreadyLiked) {
        await docRef.update({'likes.$likerUid': FieldValue.delete()});
        return false;
      } else {
        await docRef.update({
          'likes.$likerUid': {
            'userName': likerName,
            'profilePic': _toHttps(likerProfilePic),
            'likedAt': FieldValue.serverTimestamp(),
          },
        });
        return true;
      }
    } catch (e) {
      log('toggleLike error: $e');
      return false;
    }
  }

  /// Live stream of the likes map for a status.
  Stream<Map<String, dynamic>> getLikesStream(String statusId) {
    return firestore.collection('status').doc(statusId).snapshots().map((doc) {
      if (!doc.exists) return {};
      return Map<String, dynamic>.from(doc.data()!['likes'] as Map? ?? {});
    });
  }

  // ── Cloudinary image upload ────────────────────────────────────────────────

  Future<String?> _uploadImageToCloudinary(File file) async {
    try {
      log('Uploading image to Cloudinary...');
      _initCloudinary();
      final dio = Dio();
      const url = 'https://api.cloudinary.com/v1_1/$_cloudName/image/upload';
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(file.path),
        'upload_preset': _uploadPreset,
      });
      final response = await dio.post(
        url,
        data: formData,
        options: Options(
          sendTimeout: const Duration(minutes: 3),
          receiveTimeout: const Duration(minutes: 3),
        ),
        onSendProgress: (sent, total) {
          if (total > 0) {
            log('Image upload: ${(sent / total * 100).toStringAsFixed(1)}%');
          }
        },
      );
      log('Cloudinary image response: ${response.statusCode}');
      if (response.statusCode == 200) {
        final raw =
            response.data['secure_url'] as String? ??
            response.data['url'] as String;
        return _optimiseUrl(raw, isVideo: false);
      }
      return null;
    } on DioException catch (e) {
      log('Cloudinary image DioError: ${e.message} | ${e.response?.data}');
      return null;
    } catch (e) {
      log('Cloudinary image error: $e');
      return null;
    }
  }

  // ── Cloudinary video upload ────────────────────────────────────────────────

  Future<String?> _uploadVideoToCloudinary(File file) async {
    try {
      log('Uploading video to Cloudinary...');
      _initCloudinary();
      final dio = Dio();
      const url = 'https://api.cloudinary.com/v1_1/$_cloudName/video/upload';
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(file.path),
        'upload_preset': _uploadPreset,
      });
      final response = await dio.post(
        url,
        data: formData,
        options: Options(
          sendTimeout: const Duration(minutes: 10),
          receiveTimeout: const Duration(minutes: 5),
        ),
        onSendProgress: (sent, total) {
          if (total > 0) {
            log('Video upload: ${(sent / total * 100).toStringAsFixed(1)}%');
          }
        },
      );
      log('Cloudinary video response: ${response.statusCode}');
      if (response.statusCode == 200) {
        final raw =
            response.data['secure_url'] as String? ??
            response.data['url'] as String;
        return _optimiseUrl(raw, isVideo: true);
      }
      return null;
    } on DioException catch (e) {
      log('Cloudinary video DioError: ${e.message} | ${e.response?.data}');
      return null;
    } catch (e) {
      log('Cloudinary video error: $e');
      return null;
    }
  }

  void _initCloudinary() {
    CloudinaryContext.cloudinary = Cloudinary.fromCloudName(
      cloudName: _cloudName,
    );
  }

  // ── Fetch active statuses ──────────────────────────────────────────────────

  Stream<List<Map<String, dynamic>>> getStatuses() {
    final currentUserUid = auth.currentUser!.uid;
    final now = DateTime.now();

    return firestore
        .collection('status')
        .orderBy('timeCreated', descending: false)
        .snapshots()
        .map((snapshot) {
          final List<Map<String, dynamic>> active = [];
          for (final doc in snapshot.docs) {
            final data = doc.data();
            final timeCreated = (data['timeCreated'] as Timestamp).toDate();
            if (now.difference(timeCreated).inHours >= 24) {
              firestore.collection('status').doc(data['statusId']).delete();
              continue;
            }
            final visibleTo = List<String>.from(data['visibleTo'] as List);
            if (visibleTo.contains(currentUserUid)) {
              active.add(_sanitizeStatus(data));
            }
          }
          active.sort((a, b) {
            final aTime = (a['timeCreated'] as Timestamp).toDate();
            final bTime = (b['timeCreated'] as Timestamp).toDate();
            return aTime.compareTo(bTime);
          });
          return active;
        });
  }
}
