import 'dart:developer';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:worship_chat/common/utils/firebase_notification_service.dart';
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
  final Ref ref;

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

  static Map<String, dynamic> sanitizeStatus(Map<String, dynamic> data) {
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
      final transform = isVideo ? 'f_mp4,vc_h264,q_auto:good' : 'f_auto,q_auto,w_1080';
      url =
          '${url.substring(0, idx + insertAfter.length)}$transform/${url.substring(idx + insertAfter.length)}';
    }
    return url;
  }

  // ── Upload multiple statuses ───────────────────────────────────────────────

  Future<void> uploadMultipleStatuses({
    required String userName,
    required String profilePic,
    required String email,
    required List<File> statusFiles,
    required bool isVideo,
    required BuildContext context,
    void Function(int current, int total)? onProgress,
  }) async {
    try {
      final currentUser = auth.currentUser;
      if (currentUser == null) {
        throw Exception('User is not authenticated.');
      }
      final uid = currentUser.uid;

      // 1. Fetch all users from Firestore to notify remaining users & grant visibility
      final allUsersSnapshot = await firestore.collection('users').get();
      final List<String> allUserIds = [];
      final List<String> recipientFcmTokens = [];

      for (final userDoc in allUsersSnapshot.docs) {
        final otherUid = userDoc.id;
        allUserIds.add(otherUid);
        if (otherUid != uid) {
          final token = userDoc.data()['fcmToken']?.toString().trim();
          if (token != null && token.isNotEmpty) {
            recipientFcmTokens.add(token);
          }
        }
      }

      if (!allUserIds.contains(uid)) {
        allUserIds.add(uid);
      }

      final List<String> uploadedStatusIds = [];
      String? firstStatusUrl;

      // 2. Upload each file in sequence
      for (int i = 0; i < statusFiles.length; i++) {
        final file = statusFiles[i];
        onProgress?.call(i, statusFiles.length);

        final statusId = const Uuid().v1();
        final timeCreated = DateTime.now().add(Duration(milliseconds: i * 50));

        final statusUrl = isVideo
            ? await _uploadVideoToCloudinary(file)
            : await _uploadImageToCloudinary(file);

        if (statusUrl == null) {
          log('Warning: Failed to upload status item at index $i, skipping');
          continue;
        }

        await firestore.collection('status').doc(statusId).set({
          'statusId': statusId,
          'uid': uid,
          'userName': userName,
          'email': email,
          'profilePic': _toHttps(profilePic),
          'statusUrl': statusUrl,
          'mediaType': isVideo ? 'video' : 'image',
          'timeCreated': Timestamp.fromDate(timeCreated),
          'visibleTo': allUserIds,
          'seenBy': {},
          'likes': {},
        });

        firstStatusUrl ??= statusUrl;
        uploadedStatusIds.add(statusId);
      }

      if (uploadedStatusIds.isEmpty) {
        throw Exception(
          'Failed to upload ${isVideo ? 'video' : 'photo'} to Cloudinary. Check network connection.',
        );
      }

      // 3. Send push notification to all remaining users about the new story!
      if (recipientFcmTokens.isNotEmpty) {
        final String title = '✨ $userName added a new story';
        final String body = isVideo
            ? '📽️ Watch video story from $userName'
            : (uploadedStatusIds.length > 1
                ? '📷 ${uploadedStatusIds.length} new photos added to story'
                : '📷 View new story photo from $userName');

        await sendMultipleNotification(
          recipientFcmTokens,
          title,
          body,
          data: {
            'type': 'story',
            'uid': uid,
            'senderUid': uid,
            'name': userName,
            'profilePic': profilePic,
            'statusId': uploadedStatusIds.first,
            'tag': 'story_$uid',
            if (!isVideo && firstStatusUrl != null) ...{
              'messageType': 'image',
              'fileMessageData': firstStatusUrl,
              'statusUrl': firstStatusUrl,
            },
          },
        );
        log('📢 Sent story notification to ${recipientFcmTokens.length} remaining users');
      }
    } catch (e) {
      log('uploadMultipleStatuses error: $e');
      if (context.mounted) {
        showSnackBar(context: context, content: e.toString());
      }
    }
  }

  // ── Upload status (backward compatible single file) ─────────────────────────

  Future<void> uploadStatus({
    required String userName,
    required String profilePic,
    required String email,
    required File statusFile,
    required bool isVideo,
    required BuildContext context,
  }) async {
    await uploadMultipleStatuses(
      userName: userName,
      profilePic: profilePic,
      email: email,
      statusFiles: [statusFile],
      isVideo: isVideo,
      context: context,
    );
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
    final clouds = ['debeuo9x0', _cloudName];
    for (final cloud in clouds) {
      try {
        log('Uploading image to Cloudinary ($cloud)...');
        final dio = Dio();
        final url = 'https://api.cloudinary.com/v1_1/$cloud/image/upload';
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
              log('Image upload ($cloud): ${(sent / total * 100).toStringAsFixed(1)}%');
            }
          },
        );
        log('Cloudinary image response ($cloud): ${response.statusCode}');
        if (response.statusCode == 200) {
          final raw =
              response.data['secure_url'] as String? ??
              response.data['url'] as String;
          return _optimiseUrl(raw, isVideo: false);
        }
      } on DioException catch (e) {
        log('Cloudinary image DioError on $cloud: ${e.message} | ${e.response?.data}');
      } catch (e) {
        log('Cloudinary image error on $cloud: $e');
      }
    }
    return null;
  }

  // ── Cloudinary video upload ────────────────────────────────────────────────

  Future<String?> _uploadVideoToCloudinary(File file) async {
    final clouds = ['debeuo9x0', _cloudName];
    for (final cloud in clouds) {
      try {
        log('Uploading video to Cloudinary ($cloud)...');
        final dio = Dio();
        final url = 'https://api.cloudinary.com/v1_1/$cloud/auto/upload';
        final formData = FormData.fromMap({
          'file': await MultipartFile.fromFile(file.path),
          'upload_preset': _uploadPreset,
          'resource_type': 'video',
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
              log('Video upload ($cloud): ${(sent / total * 100).toStringAsFixed(1)}%');
            }
          },
        );
        log('Cloudinary video response ($cloud): ${response.statusCode}');
        if (response.statusCode == 200) {
          final raw =
              response.data['secure_url'] as String? ??
              response.data['url'] as String;
          return _optimiseUrl(raw, isVideo: true);
        }
      } on DioException catch (e) {
        log('Cloudinary video DioError on $cloud: ${e.message} | ${e.response?.data}');
      } catch (e) {
        log('Cloudinary video error on $cloud: $e');
      }
    }
    return null;
  }

  static List<Map<String, dynamic>> _memoryCache = [];

  /// Returns cached statuses instantly (0ms) from memory or Hive.
  static List<Map<String, dynamic>> getCachedStatuses() {
    if (_memoryCache.isNotEmpty) return _memoryCache;
    try {
      if (Hive.isBoxOpen('status_cache')) {
        final box = Hive.box('status_cache');
        final raw = box.get('active_statuses') as List?;
        if (raw != null) {
          _memoryCache = raw.map((e) {
            final map = Map<String, dynamic>.from(e as Map);
            if (map['timeCreatedMillis'] != null && map['timeCreated'] == null) {
              map['timeCreated'] = Timestamp.fromMillisecondsSinceEpoch(
                map['timeCreatedMillis'] as int,
              );
            }
            return map;
          }).toList();
          return _memoryCache;
        }
      }
    } catch (_) {}
    return [];
  }

  static void _saveToCache(List<Map<String, dynamic>> list) {
    _memoryCache = list;
    try {
      if (Hive.isBoxOpen('status_cache')) {
        final serializable = list.map((item) {
          final copy = Map<String, dynamic>.from(item);
          if (copy['timeCreated'] is Timestamp) {
            copy['timeCreatedMillis'] =
                (copy['timeCreated'] as Timestamp).millisecondsSinceEpoch;
          }
          return copy;
        }).toList();
        Hive.box('status_cache').put('active_statuses', serializable);
      }
    } catch (_) {}
  }

  // ── Fetch active statuses ──────────────────────────────────────────────────

  Stream<List<Map<String, dynamic>>> getStatuses() async* {
    // 1. Instant local cache yield (0 ms) — eliminates initial loading lag completely
    final cached = getCachedStatuses();
    if (cached.isNotEmpty) {
      yield cached;
    }

    final currentUserUid = safeCurrentUserId() ?? auth.currentUser?.uid ?? '';
    final now = DateTime.now();

    final stream = firestore
        .collection('status')
        .orderBy('timeCreated', descending: false)
        .snapshots();

    await for (final snapshot in stream) {
      final List<Map<String, dynamic>> active = [];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final timeCreated = (data['timeCreated'] as Timestamp).toDate();
        if (now.difference(timeCreated).inHours >= 24) {
          firestore
              .collection('status')
              .doc(data['statusId'])
              .delete()
              .catchError((_) {});
          continue;
        }
        final visibleTo = List<String>.from(data['visibleTo'] as List? ?? []);
        if (currentUserUid.isNotEmpty && visibleTo.contains(currentUserUid)) {
          active.add(sanitizeStatus(data));
        }
      }
      active.sort((a, b) {
        final aTime = (a['timeCreated'] as Timestamp).toDate();
        final bTime = (b['timeCreated'] as Timestamp).toDate();
        return aTime.compareTo(bTime);
      });

      _saveToCache(active);
      yield active;
    }
  }
}
