import 'dart:async';
import 'dart:developer';
import 'dart:math' hide log;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:worship_chat/common/utils/utils.dart';
import 'package:worship_chat/features/group/repository/group_repository.dart';
import 'package:worship_chat/models/group_chat_message_model.dart';
import 'package:worship_chat/models/group_gallery_image.dart';

export 'package:worship_chat/common/utils/utils.dart' show getOptimizedRoleplayImageUrl;

enum RoleplayModeType {
  automatic,
  manual;

  static RoleplayModeType fromString(String? val) {
    if (val == 'manual') return RoleplayModeType.manual;
    return RoleplayModeType.automatic;
  }
}

class RoleplaySession {
  final String groupId;
  final String queendom;
  final String groupName;
  final List<String> receiverIds;
  final String? chatBackgroundUrl;
  final String? groupPic;
  int intervalSeconds;
  Timer? timer;
  List<GroupGalleryImage> cachedImages;
  String? lastPostedImageUrl;
  final DateTime startedAt;
  RoleplayModeType mode;

  RoleplaySession({
    required this.groupId,
    required this.queendom,
    required this.groupName,
    required this.receiverIds,
    this.chatBackgroundUrl,
    this.groupPic,
    required this.intervalSeconds,
    this.timer,
    this.cachedImages = const [],
    this.lastPostedImageUrl,
    DateTime? startedAt,
    this.mode = RoleplayModeType.automatic,
  }) : startedAt = startedAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'groupId': groupId,
      'queendom': queendom,
      'groupName': groupName,
      'receiverIds': receiverIds,
      'chatBackgroundUrl': chatBackgroundUrl,
      'groupPic': groupPic,
      'intervalSeconds': intervalSeconds,
      'startedAt': startedAt.toIso8601String(),
      'mode': mode.name,
    };
  }

  factory RoleplaySession.fromMap(Map<String, dynamic> map) {
    return RoleplaySession(
      groupId: map['groupId'] as String? ?? '',
      queendom: map['queendom'] as String? ?? '',
      groupName: map['groupName'] as String? ?? '',
      receiverIds: List<String>.from(map['receiverIds'] as List? ?? []),
      chatBackgroundUrl: map['chatBackgroundUrl'] as String?,
      groupPic: map['groupPic'] as String?,
      intervalSeconds: (map['intervalSeconds'] as int?) ?? 15,
      startedAt: map['startedAt'] != null
          ? DateTime.tryParse(map['startedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      mode: RoleplayModeType.fromString(map['mode'] as String?),
    );
  }
}

/// Global service managing Roleplay Mode across all groups.
/// Runs in the background and does NOT stop when the user navigates away from the chat screen.
class RoleplayService extends ChangeNotifier with WidgetsBindingObserver {
  RoleplayService._() {
    WidgetsBinding.instance.addObserver(this);
  }

  static final RoleplayService instance = RoleplayService._();

  final Map<String, RoleplaySession> _activeSessions = {};
  final Map<String, StreamSubscription> _groupDocSubscriptions = {};

  bool isRoleplayActive(String groupId) => _activeSessions.containsKey(groupId);

  RoleplaySession? getSession(String groupId) => _activeSessions[groupId];

  RoleplayModeType getRoleplayMode(String groupId) {
    final session = _activeSessions[groupId];
    if (session != null) return session.mode;
    try {
      if (Hive.isBoxOpen('roleplay_settings')) {
        final box = Hive.box('roleplay_settings');
        final saved = box.get('roleplay_mode_$groupId');
        if (saved != null) return RoleplayModeType.fromString(saved.toString());
      }
    } catch (_) {}
    return RoleplayModeType.automatic;
  }

  bool isManualRoleplay(String groupId) =>
      isRoleplayActive(groupId) &&
      getRoleplayMode(groupId) == RoleplayModeType.manual;

  bool isAutomaticRoleplay(String groupId) =>
      isRoleplayActive(groupId) &&
      getRoleplayMode(groupId) == RoleplayModeType.automatic;

  int getInterval(String groupId) {
    return _activeSessions[groupId]?.intervalSeconds ?? getSavedInterval(groupId);
  }

  int getSavedInterval(String groupId) {
    try {
      if (Hive.isBoxOpen('roleplay_settings')) {
        final box = Hive.box('roleplay_settings');
        final val = box.get('roleplay_interval_$groupId') ??
            box.get('roleplay_interval') ??
            15;
        if (val is int && val >= 3) return val;
      }
    } catch (e) {
      log('Error reading saved roleplay interval: $e');
    }
    return 15;
  }

  Future<void> setInterval(String groupId, int seconds) async {
    try {
      Box box;
      if (!Hive.isBoxOpen('roleplay_settings')) {
        box = await Hive.openBox('roleplay_settings');
      } else {
        box = Hive.box('roleplay_settings');
      }
      await box.put('roleplay_interval_$groupId', seconds);
      await box.put('roleplay_interval', seconds);
    } catch (e) {
      log('Error saving roleplay interval to Hive: $e');
    }

    final session = _activeSessions[groupId];
    if (session != null) {
      session.intervalSeconds = seconds;
      if (session.mode == RoleplayModeType.automatic) {
        session.timer?.cancel();
        session.timer = Timer.periodic(Duration(seconds: seconds), (_) {
          _postRandomRoleplayPhoto(groupId);
        });
      }
    }
    notifyListeners();
  }

  Future<bool> startRoleplay({
    required String groupId,
    required String queendom,
    required String groupName,
    required List<String> receiverIds,
    String? chatBackgroundUrl,
    String? groupPic,
    int? intervalSeconds,
    RoleplayModeType mode = RoleplayModeType.automatic,
  }) async {
    final interval = intervalSeconds ?? getSavedInterval(groupId);
    final images = await loadGalleryImages(
      groupId: groupId,
      queendom: queendom,
      chatBackgroundUrl: chatBackgroundUrl,
      groupPic: groupPic,
      groupName: groupName,
    );

    if (images.isEmpty) {
      return false;
    }

    // Preload gallery photos into cache in background for ultra-fast rendering
    _preloadGalleryImages(images);

    // Stop existing timer for this group if any
    _activeSessions[groupId]?.timer?.cancel();

    final session = RoleplaySession(
      groupId: groupId,
      queendom: queendom,
      groupName: groupName,
      receiverIds: receiverIds,
      chatBackgroundUrl: chatBackgroundUrl,
      groupPic: groupPic,
      intervalSeconds: interval,
      cachedImages: images,
      mode: mode,
    );

    _activeSessions[groupId] = session;
    await _saveSessionToHive(groupId, session);

    // Synchronize to Firestore so all users in the group know roleplay mode is active
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    try {
      await FirebaseFirestore.instance.collection('groups').doc(groupId).update({
        'isRoleplayActive': true,
        'roleplayStartedBy': currentUserId,
        'roleplayIntervalSeconds': interval,
        'roleplayMode': mode.name,
      });
    } catch (e) {
      log('Error syncing roleplay start to Firestore: $e');
    }

    // Listen to remote Firestore doc: if another user cancels or changes mode
    _listenToRemoteGroupState(groupId);

    if (mode == RoleplayModeType.automatic) {
      // Post first photo immediately for automatic mode
      await _postRandomRoleplayPhoto(groupId);

      // Schedule background periodic timer
      session.timer = Timer.periodic(Duration(seconds: interval), (_) {
        _postRandomRoleplayPhoto(groupId);
      });
    }

    notifyListeners();
    return true;
  }

  /// Sends a single random photo immediately from gallery in Manual mode.
  Future<bool> postSingleRoleplayPhoto(
    String groupId, {
    String? queendom,
    String? groupName,
    List<String>? receiverIds,
    String? chatBackgroundUrl,
    String? groupPic,
  }) async {
    var session = _activeSessions[groupId];
    if (session == null) {
      // Attempt to restore session from Hive or fallback to provided arguments
      RoleplaySession? restored;
      if (Hive.isBoxOpen('roleplay_settings')) {
        final box = Hive.box('roleplay_settings');
        final raw = box.get('roleplay_session_$groupId');
        if (raw is Map) {
          restored = RoleplaySession.fromMap(Map<String, dynamic>.from(raw));
        }
      }
      if (restored != null) {
        session = restored;
      } else {
        session = RoleplaySession(
          groupId: groupId,
          queendom: queendom ?? '',
          groupName: groupName ?? '',
          receiverIds: receiverIds ?? [],
          chatBackgroundUrl: chatBackgroundUrl,
          groupPic: groupPic,
          intervalSeconds: getSavedInterval(groupId),
          mode: RoleplayModeType.manual,
        );
      }
      _activeSessions[groupId] = session;
      _listenToRemoteGroupState(groupId);
    }

    if (session.cachedImages.isEmpty) {
      final images = await loadGalleryImages(
        groupId: groupId,
        queendom: session.queendom.isNotEmpty
            ? session.queendom
            : (queendom ?? ''),
        chatBackgroundUrl: session.chatBackgroundUrl ?? chatBackgroundUrl,
        groupPic: session.groupPic ?? groupPic,
        groupName: session.groupName.isNotEmpty
            ? session.groupName
            : (groupName ?? ''),
      );
      if (images.isEmpty) return false;
      session.cachedImages = images;
      _preloadGalleryImages(images);
    }

    await _postRandomRoleplayPhoto(groupId);
    notifyListeners();
    return true;
  }

  /// Switches active session between Automatic and Manual mode.
  Future<void> switchRoleplayMode(
    String groupId,
    RoleplayModeType newMode,
  ) async {
    final session = _activeSessions[groupId];
    if (session == null) return;
    if (session.mode == newMode) return;

    session.mode = newMode;
    if (newMode == RoleplayModeType.automatic) {
      session.timer?.cancel();
      // Post photo right away on switch to automatic
      await _postRandomRoleplayPhoto(groupId);
      session.timer = Timer.periodic(
        Duration(seconds: session.intervalSeconds),
        (_) => _postRandomRoleplayPhoto(groupId),
      );
    } else {
      // Manual mode: cancel periodic timer
      session.timer?.cancel();
      session.timer = null;
    }

    await _saveSessionToHive(groupId, session);

    try {
      await FirebaseFirestore.instance.collection('groups').doc(groupId).update({
        'roleplayMode': newMode.name,
      });
    } catch (e) {
      log('Error updating roleplayMode in Firestore: $e');
    }

    notifyListeners();
  }

  void _listenToRemoteGroupState(String groupId) {
    _groupDocSubscriptions[groupId]?.cancel();
    _groupDocSubscriptions[groupId] = FirebaseFirestore.instance
        .collection('groups')
        .doc(groupId)
        .snapshots()
        .listen((snapshot) {
      if (!snapshot.exists) return;
      final data = snapshot.data();
      if (data == null) return;
      final isRoleplayActive = (data['isRoleplayActive'] as bool?) ?? false;
      if (!isRoleplayActive) {
        // Another user stopped roleplay mode
        stopLocalRoleplay(groupId);
      } else {
        // Synchronize remote roleplayMode
        final remoteModeStr = data['roleplayMode'] as String?;
        if (remoteModeStr != null) {
          final remoteMode = RoleplayModeType.fromString(remoteModeStr);
          final session = _activeSessions[groupId];
          if (session != null && session.mode != remoteMode) {
            session.mode = remoteMode;
            if (remoteMode == RoleplayModeType.automatic) {
              session.timer?.cancel();
              session.timer = Timer.periodic(
                Duration(seconds: session.intervalSeconds),
                (_) => _postRandomRoleplayPhoto(groupId),
              );
            } else {
              session.timer?.cancel();
              session.timer = null;
            }
            notifyListeners();
          }
        }
      }
    });
  }

  void stopLocalRoleplay(String groupId) {
    final session = _activeSessions.remove(groupId);
    session?.timer?.cancel();
    _groupDocSubscriptions[groupId]?.cancel();
    _groupDocSubscriptions.remove(groupId);
    _removeSessionFromHive(groupId);
    notifyListeners();
  }

  Future<void> stopRoleplay(String groupId) async {
    stopLocalRoleplay(groupId);

    try {
      await FirebaseFirestore.instance.collection('groups').doc(groupId).update({
        'isRoleplayActive': false,
        'roleplayStartedBy': null,
      });
    } catch (e) {
      log('Error syncing roleplay stop to Firestore: $e');
    }
  }

  Future<void> _saveSessionToHive(String groupId, RoleplaySession session) async {
    try {
      Box box;
      if (!Hive.isBoxOpen('roleplay_settings')) {
        box = await Hive.openBox('roleplay_settings');
      } else {
        box = Hive.box('roleplay_settings');
      }
      await box.put('roleplay_active_$groupId', true);
      await box.put('roleplay_interval_$groupId', session.intervalSeconds);
      await box.put('roleplay_mode_$groupId', session.mode.name);
      await box.put('roleplay_session_$groupId', session.toMap());
    } catch (e) {
      log('Error saving roleplay session to Hive: $e');
    }
  }

  Future<void> _removeSessionFromHive(String groupId) async {
    try {
      if (Hive.isBoxOpen('roleplay_settings')) {
        final box = Hive.box('roleplay_settings');
        await box.put('roleplay_active_$groupId', false);
        await box.delete('roleplay_mode_$groupId');
        await box.delete('roleplay_session_$groupId');
      }
    } catch (e) {
      log('Error removing roleplay session from Hive: $e');
    }
  }

  Future<void> _postRandomRoleplayPhoto(String groupId) async {
    final session = _activeSessions[groupId];
    if (session == null || session.cachedImages.isEmpty) return;

    GroupGalleryImage picked;
    if (session.cachedImages.length == 1) {
      picked = session.cachedImages.first;
    } else {
      final candidates = session.cachedImages
          .where((img) => img.imageUrl != session.lastPostedImageUrl)
          .toList();
      final pool = candidates.isNotEmpty ? candidates : session.cachedImages;
      picked = pool[Random().nextInt(pool.length)];
    }

    session.lastPostedImageUrl = picked.imageUrl;

    // Pre-warm the cache for this picked photo and upcoming candidates
    _prewarmImage(picked.imageUrl);
    if (session.cachedImages.length > 1) {
      final upcoming = session.cachedImages
          .where((img) => img.imageUrl != picked.imageUrl)
          .take(3);
      for (final nextImg in upcoming) {
        _prewarmImage(nextImg.imageUrl);
      }
    }

    try {
      final messageId = const Uuid().v1();
      final timeSent = DateTime.now();

      final message = GroupChatMessageModel(
        senderId: 'roleplay',
        receiverIds: session.receiverIds,
        groupId: groupId,
        text: picked.caption ?? '',
        messageType: 'roleplay',
        timeSent: timeSent,
        messageId: messageId,
        isSeen: true,
        isDelivered: true,
        fileMessageData: picked.imageUrl,
        repliedMessage: '',
        repliedTo: '',
        repliedMessageType: 'text',
      );

      // Save to optimistic Hive cache
      _saveOptimisticGroupMessageToHive(groupId, message);

      // Firestore write
      final firestore = FirebaseFirestore.instance;
      await firestore
          .collection('groups')
          .doc(groupId)
          .collection('chats')
          .doc(messageId)
          .set(message.toMap());

      await firestore.collection('groups').doc(groupId).update({
        'lastMessage': '🎭 Roleplay photo',
        'timeSent': timeSent.millisecondsSinceEpoch,
      });

      log('🎭 RoleplayService: Posted photo for group $groupId');
    } catch (e) {
      log('❌ RoleplayService error posting photo: $e');
    }
  }

  void _saveOptimisticGroupMessageToHive(
    String groupId,
    GroupChatMessageModel message,
  ) async {
    try {
      final box = Hive.isBoxOpen('messages')
          ? Hive.box('messages')
          : await Hive.openBox('messages');

      final cachedData = box.get(groupId, defaultValue: []);
      List<GroupChatMessageModel> messages = [];
      if (cachedData is List) {
        for (var item in cachedData) {
          if (item is GroupChatMessageModel) {
            messages.add(item);
          } else if (item is Map) {
            try {
              messages.add(
                GroupChatMessageModel.fromMap(Map<String, dynamic>.from(item)),
              );
            } catch (_) {}
          }
        }
      }
      final existingIndex =
          messages.indexWhere((m) => m.messageId == message.messageId);
      if (existingIndex >= 0) {
        messages[existingIndex] = message;
      } else {
        messages.add(message);
      }
      await box.put(groupId, messages);

      GroupRepository.notifyGroupChatListeners(groupId, messages);
    } catch (e) {
      log('❌ Error saving optimistic roleplay message to Hive: $e');
    }
  }

  Future<List<GroupGalleryImage>> loadGalleryImages({
    required String groupId,
    required String queendom,
    String? chatBackgroundUrl,
    String? groupPic,
    String? groupName,
  }) async {
    try {
      final firestore = FirebaseFirestore.instance;
      List<GroupGalleryImage> loaded = [];

      // 1. Current group gallery
      final snap = await firestore
          .collection('groups')
          .doc(groupId)
          .collection('gallery')
          .orderBy('uploadedAt', descending: true)
          .limit(100)
          .get();

      loaded = snap.docs
          .map((doc) => GroupGalleryImage.fromMap(doc.data()))
          .where((img) => img.imageUrl.isNotEmpty)
          .toList();

      // 2. Parent group gallery if subgroup
      if (loaded.isEmpty) {
        final groupDoc =
            await firestore.collection('groups').doc(groupId).get();
        final parentId = groupDoc.data()?['parentGroupId'] as String?;
        if (parentId != null && parentId.isNotEmpty) {
          final parentSnap = await firestore
              .collection('groups')
              .doc(parentId)
              .collection('gallery')
              .orderBy('uploadedAt', descending: true)
              .limit(100)
              .get();
          loaded = parentSnap.docs
              .map((doc) => GroupGalleryImage.fromMap(doc.data()))
              .where((img) => img.imageUrl.isNotEmpty)
              .toList();
        }
      }

      // 3. Same queendom fallback
      if (loaded.isEmpty && queendom.isNotEmpty) {
        final sameQueendomGroups = await firestore
            .collection('groups')
            .where('queendom', isEqualTo: queendom)
            .limit(5)
            .get();
        for (final doc in sameQueendomGroups.docs) {
          if (doc.id == groupId) continue;
          final qSnap = await firestore
              .collection('groups')
              .doc(doc.id)
              .collection('gallery')
              .limit(30)
              .get();
          if (qSnap.docs.isNotEmpty) {
            loaded.addAll(
              qSnap.docs
                  .map((d) => GroupGalleryImage.fromMap(d.data()))
                  .where((img) => img.imageUrl.isNotEmpty),
            );
            break;
          }
        }
      }

      // 4. Background / group pic fallback
      if (loaded.isEmpty) {
        if (chatBackgroundUrl != null && chatBackgroundUrl.isNotEmpty) {
          loaded.add(
            GroupGalleryImage(
              imageId: 'bg_$groupId',
              groupId: groupId,
              imageUrl: chatBackgroundUrl,
              uploadedBy: 'system',
              uploadedByName: 'Royal Sanctuary',
              uploadedAt: DateTime.now(),
              caption: groupName ?? '',
            ),
          );
        }
        if (groupPic != null && groupPic.isNotEmpty) {
          loaded.add(
            GroupGalleryImage(
              imageId: 'pic_$groupId',
              groupId: groupId,
              imageUrl: groupPic,
              uploadedBy: 'system',
              uploadedByName: 'Royal Sanctuary',
              uploadedAt: DateTime.now(),
              caption: groupName ?? '',
            ),
          );
        }
      }

      return loaded;
    } catch (e) {
      log('❌ Error loading gallery images: $e');
      return [];
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resumeActiveTimers();
    }
  }

  void _resumeActiveTimers() {
    for (final entry in _activeSessions.entries) {
      final session = entry.value;
      if (session.mode == RoleplayModeType.automatic &&
          (session.timer == null || !session.timer!.isActive)) {
        session.timer?.cancel();
        session.timer = Timer.periodic(
          Duration(seconds: session.intervalSeconds),
          (_) {
            _postRandomRoleplayPhoto(session.groupId);
          },
        );
      }
    }
  }

  /// Restores sessions on app startup if they were active in Hive
  Future<void> restoreActiveSessions() async {
    try {
      Box box;
      if (!Hive.isBoxOpen('roleplay_settings')) {
        box = await Hive.openBox('roleplay_settings');
      } else {
        box = Hive.box('roleplay_settings');
      }

      final currentUserId = FirebaseAuth.instance.currentUser?.uid;

      for (final key in box.keys) {
        if (key is String && key.startsWith('roleplay_active_')) {
          final isActive = box.get(key) == true;
          if (isActive) {
            final groupId = key.replaceFirst('roleplay_active_', '');

            // Verify with Firestore if roleplay is still active and started by current user
            bool isStillActive = false;
            try {
              final doc = await FirebaseFirestore.instance
                  .collection('groups')
                  .doc(groupId)
                  .get();
              if (doc.exists) {
                final data = doc.data() ?? {};
                final firestoreActive = data['isRoleplayActive'] == true;
                final startedBy = data['roleplayStartedBy'];
                isStillActive = firestoreActive &&
                    (startedBy == null || startedBy == currentUserId);
              }
            } catch (e) {
              log('Could not verify roleplay active with Firestore: $e');
              isStillActive = true;
            }

            if (!isStillActive) {
              await _removeSessionFromHive(groupId);
              continue;
            }

            final rawSession = box.get('roleplay_session_$groupId');
            if (rawSession is Map) {
              final session = RoleplaySession.fromMap(
                Map<String, dynamic>.from(rawSession),
              );
              final images = await loadGalleryImages(
                groupId: session.groupId,
                queendom: session.queendom,
                chatBackgroundUrl: session.chatBackgroundUrl,
                groupPic: session.groupPic,
                groupName: session.groupName,
              );
              session.cachedImages = images;
              _preloadGalleryImages(images);
              _activeSessions[groupId] = session;
              if (session.mode == RoleplayModeType.automatic) {
                session.timer = Timer.periodic(
                  Duration(seconds: session.intervalSeconds),
                  (_) {
                    _postRandomRoleplayPhoto(session.groupId);
                  },
                );
              }
              _listenToRemoteGroupState(session.groupId);
              log('🎭 Restored background roleplay session for $groupId (${session.mode.name})');
            }
          }
        }
      }
      notifyListeners();
    } catch (e) {
      log('Error restoring roleplay sessions: $e');
    }
  }

  /// Pre-warms the image cache for a batch of gallery images.
  void _preloadGalleryImages(List<GroupGalleryImage> images) {
    if (images.isEmpty) return;
    for (final img in images.take(25)) {
      _prewarmImage(img.imageUrl);
    }
  }

  /// Pre-warms an individual image URL in memory and disk cache.
  void _prewarmImage(String rawUrl) {
    final clean = rawUrl.trim();
    if (clean.startsWith('http://') || clean.startsWith('https://')) {
      final optUrl = getOptimizedRoleplayImageUrl(clean);
      try {
        CachedNetworkImageProvider(
          optUrl,
          maxWidth: 800,
        ).resolve(ImageConfiguration.empty);
      } catch (e) {
        log('Prewarm image failed: $e');
      }
    }
  }
}
