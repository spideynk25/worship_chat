import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worship_chat/common/utils/app_capabilities.dart';
import 'package:worship_chat/common/utils/firebase_notification_service.dart';
import 'package:worship_chat/models/group.dart';
import 'package:worship_chat/models/group_chat_message_model.dart';

/// The three sacred devotion windows of the day.
enum WishWindowType {
  /// 6:00 PM to 6:00 AM (12-hour window): Aura Elixiria Goddesses & all Princesses
  eveningNight,

  /// 6:00 AM to 12:00 PM (6-hour window): Core Supreme, Supreme, Golden Blossom, Goddess, Demi Goddess
  morning,

  /// 12:00 PM to 6:00 PM (6-hour window): Dark Angels, Queens, Elfwitches, Enchantresses
  afternoon,
}

/// Metadata and mathematical thresholds for an active devotion window.
class WishWindowInfo {
  final WishWindowType type;
  final DateTime startTime;
  final DateTime endTime;
  final String title;

  const WishWindowInfo({
    required this.type,
    required this.startTime,
    required this.endTime,
    required this.title,
  });

  /// Total duration of the devotion window.
  Duration get duration => endTime.difference(startTime);

  /// Computes the elapsed completion fraction [0.0, 1.0] for the window at [currentTime].
  double getElapsedFraction([DateTime? currentTime]) {
    final now = currentTime ?? DateTime.now();
    if (now.isBefore(startTime)) return 0.0;
    if (now.isAfter(endTime)) return 1.0;
    final totalSeconds = duration.inSeconds;
    if (totalSeconds <= 0) return 0.0;
    final elapsedSeconds = now.difference(startTime).inSeconds;
    return (elapsedSeconds / totalSeconds).clamp(0.0, 1.0);
  }

  /// Returns the reached reminder thresholds (80%, 90%, 95%) in ascending order.
  List<int> getReachedThresholdsList([DateTime? currentTime]) {
    final fraction = getElapsedFraction(currentTime);
    final List<int> list = [];
    if (fraction >= 0.80) list.add(80);
    if (fraction >= 0.90) list.add(90);
    if (fraction >= 0.95) list.add(95);
    return list;
  }

  /// Calculates the highest reached reminder threshold (80, 90, 95) or null if under 80%.
  int? getHighestReachedThreshold([DateTime? currentTime]) {
    final reached = getReachedThresholdsList(currentTime);
    return reached.isEmpty ? null : reached.last;
  }

  /// Resolves the sacred wish window for any given [DateTime].
  static WishWindowInfo forDateTime(DateTime now) {
    if (now.hour >= 6 && now.hour < 12) {
      // 6:00 AM to 12:00 PM
      return WishWindowInfo(
        type: WishWindowType.morning,
        startTime: DateTime(now.year, now.month, now.day, 6, 0),
        endTime: DateTime(now.year, now.month, now.day, 12, 0),
        title: 'Morning Sacred Devotion',
      );
    } else if (now.hour >= 12 && now.hour < 18) {
      // 12:00 PM to 6:00 PM
      return WishWindowInfo(
        type: WishWindowType.afternoon,
        startTime: DateTime(now.year, now.month, now.day, 12, 0),
        endTime: DateTime(now.year, now.month, now.day, 18, 0),
        title: 'Afternoon Royal Sanctum Devotion',
      );
    } else if (now.hour >= 18) {
      // 6:00 PM today to 6:00 AM tomorrow
      final tomorrow = now.add(const Duration(days: 1));
      return WishWindowInfo(
        type: WishWindowType.eveningNight,
        startTime: DateTime(now.year, now.month, now.day, 18, 0),
        endTime: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 6, 0),
        title: 'Evening & Night Celestial Devotion',
      );
    } else {
      // 12:00 AM to 5:59 AM today (started at 6:00 PM yesterday)
      final yesterday = now.subtract(const Duration(days: 1));
      return WishWindowInfo(
        type: WishWindowType.eveningNight,
        startTime: DateTime(yesterday.year, yesterday.month, yesterday.day, 18, 0),
        endTime: DateTime(now.year, now.month, now.day, 6, 0),
        title: 'Evening & Night Celestial Devotion',
      );
    }
  }
}

/// Service that monitors devotion windows and sends alert notifications at
/// 80%, 90%, and 95% deadline completion if deities are unwished.
class WishReminderService {
  WishReminderService._();
  static final WishReminderService instance = WishReminderService._();

  Timer? _checkTimer;
  bool _isRunning = false;

  // Custom dependency overrides for unit testing
  FirebaseFirestore? _firestoreOverride;
  FirebaseAuth? _authOverride;
  SharedPreferences? _prefsOverride;
  Future<void> Function({
    required int id,
    required String title,
    required String body,
    required String payload,
  })? _notificationSenderOverride;

  void setTestingOverrides({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    SharedPreferences? prefs,
    Future<void> Function({
      required int id,
      required String title,
      required String body,
      required String payload,
    })? notificationSender,
  }) {
    _firestoreOverride = firestore;
    _authOverride = auth;
    _prefsOverride = prefs;
    _notificationSenderOverride = notificationSender;
  }

  void resetTestingOverrides() {
    _firestoreOverride = null;
    _authOverride = null;
    _prefsOverride = null;
    _notificationSenderOverride = null;
  }

  /// Starts the periodic deadline monitor timer.
  void start({Duration interval = const Duration(minutes: 1)}) {
    if (_isRunning) return;
    _isRunning = true;
    log('👑 WishReminderService started (interval: ${interval.inSeconds}s)');
    _checkTimer = Timer.periodic(interval, (_) {
      checkReminders();
    });
    // Run an initial check shortly after startup
    Future.delayed(const Duration(seconds: 3), () {
      if (_isRunning) checkReminders();
    });
  }

  /// Stops the periodic deadline monitor timer.
  void stop() {
    _checkTimer?.cancel();
    _checkTimer = null;
    _isRunning = false;
    log('👑 WishReminderService stopped');
  }

  /// Checks whether a given [GroupModel] belongs to the specified [windowType].
  static bool isGroupInWindow(GroupModel group, WishWindowType windowType) {
    if (group.isSubGroup) return false;

    final pos = (group.position ?? '').trim().toLowerCase();
    final name = group.name.trim().toLowerCase();
    final fullName = group.nameWithPosition.trim().toLowerCase();

    switch (windowType) {
      case WishWindowType.eveningNight:
        // Aura Elixiria Goddesses & all Princesses
        final isAura = pos.contains('aura elixiria') ||
            pos.contains('aura goddesses') ||
            name.contains('aura elixiria') ||
            fullName.contains('aura elixiria');
        final isPrincess = pos.contains('princess') ||
            name.contains('princess') ||
            fullName.contains('princess');
        return isAura || isPrincess;

      case WishWindowType.morning:
        // Core Supreme, Supreme, Golden Blossom, Goddess, Demi Goddess
        // Note: Exclude Aura Elixiria even if it includes "goddess" in title
        if (pos.contains('aura elixiria') ||
            fullName.contains('aura elixiria') ||
            pos.contains('aura goddesses')) {
          return false;
        }
        final isCoreSupreme = pos.contains('core supreme') ||
            name.contains('core supreme') ||
            fullName.contains('core supreme');
        final isSupreme = pos.contains('supreme') ||
            name.contains('supreme') ||
            fullName.contains('supreme');
        final isGoldenBlossom = pos.contains('golden blossom') ||
            name.contains('golden blossom') ||
            fullName.contains('golden blossom');
        final isDemi = pos.contains('demi') ||
            name.contains('demi') ||
            fullName.contains('demi');
        final isGoddess = pos.contains('goddess') ||
            name.contains('goddess') ||
            fullName.contains('goddess');
        return isCoreSupreme ||
            isSupreme ||
            isGoldenBlossom ||
            isDemi ||
            isGoddess;

      case WishWindowType.afternoon:
        // Dark Angels, Queens, Elfwitches, Enchantresses
        final isDarkAngel = pos.contains('dark angel') ||
            name.contains('dark angel') ||
            fullName.contains('dark angel');
        final isQueen = pos.contains('queen') ||
            name.contains('queen') ||
            fullName.contains('queen');
        final isElfwitch = pos.contains('elfwitch') ||
            pos.contains('elf witch') ||
            name.contains('elfwitch') ||
            fullName.contains('elfwitch');
        final isEnchantress = pos.contains('enchantress') ||
            name.contains('enchantress') ||
            fullName.contains('enchantress');
        return isDarkAngel || isQueen || isElfwitch || isEnchantress;
    }
  }

  /// Retrieves all groups relevant to the current user and window type.
  Future<List<GroupModel>> getGroupsForWindow(
    WishWindowType windowType,
    String currentUserId,
  ) async {
    final List<GroupModel> groups = [];
    final Set<String> groupIds = {};

    // 1. Try reading from Hive local cache
    try {
      if (Hive.isBoxOpen('groups_cache')) {
        final box = Hive.box('groups_cache');
        final keysToCheck = [
          'groups_all_$currentUserId',
          'groups_pooja_$currentUserId',
          'groups_rashmika_$currentUserId',
        ];
        for (final key in keysToCheck) {
          final cached = box.get(key);
          if (cached is List) {
            for (final item in cached) {
              if (item is Map) {
                try {
                  final group =
                      GroupModel.fromMap(Map<String, dynamic>.from(item));
                  if (!groupIds.contains(group.groupId)) {
                    groupIds.add(group.groupId);
                    groups.add(group);
                  }
                } catch (_) {}
              }
            }
          }
        }
      }

      if (groups.isEmpty && Hive.isBoxOpen('groupsBox')) {
        final box = Hive.box<GroupModel>('groupsBox');
        for (final group in box.values) {
          if (!groupIds.contains(group.groupId)) {
            groupIds.add(group.groupId);
            groups.add(group);
          }
        }
      }
    } catch (e) {
      log('⚠️ Error retrieving cached groups for wish reminder: $e');
    }

    // 2. Fall back to Firestore if local cache returned no groups
    if (groups.isEmpty) {
      try {
        final firestore = _firestoreOverride ?? FirebaseFirestore.instance;
        final snap = await firestore.collection('groups').get();
        for (final doc in snap.docs) {
          try {
            final group = GroupModel.fromMap(doc.data());
            if (!groupIds.contains(group.groupId)) {
              groupIds.add(group.groupId);
              groups.add(group);
            }
          } catch (_) {}
        }
      } catch (e) {
        log('⚠️ Error querying groups from Firestore: $e');
      }
    }

    // 3. Filter for groups matching current user membership and window criteria
    return groups.where((g) {
      final isMember =
          g.membersUid.isEmpty || g.membersUid.contains(currentUserId);
      return isMember && isGroupInWindow(g, windowType);
    }).toList();
  }

  /// Checks whether [currentUserId] has sent a devotion/wish message to [groupId]
  /// between [windowStart] and [windowEnd].
  Future<bool> hasUserWishedGroup({
    required String groupId,
    required String currentUserId,
    required DateTime windowStart,
    required DateTime windowEnd,
  }) async {
    // 1. Fast path: Check Hive local messages cache
    try {
      if (Hive.isBoxOpen('messages')) {
        final box = Hive.box('messages');
        final cachedData = box.get(groupId, defaultValue: []);
        if (cachedData is List) {
          for (final item in cachedData) {
            GroupChatMessageModel? msg;
            if (item is GroupChatMessageModel) {
              msg = item;
            } else if (item is Map) {
              try {
                msg = GroupChatMessageModel.fromMap(
                  Map<String, dynamic>.from(item),
                );
              } catch (_) {}
            }
            if (msg != null &&
                msg.senderId == currentUserId &&
                !msg.isSending &&
                !msg.timeSent.isBefore(windowStart) &&
                !msg.timeSent.isAfter(windowEnd)) {
              return true;
            }
          }
        }
      }
    } catch (e) {
      log('⚠️ Hive check for wish message failed: $e');
    }

    // 2. Query Firestore messages for this group
    try {
      final firestore = _firestoreOverride ?? FirebaseFirestore.instance;
      final snap = await firestore
          .collection('groups')
          .doc(groupId)
          .collection('chats')
          .where('senderId', isEqualTo: currentUserId)
          .orderBy('timeSent', descending: true)
          .limit(15)
          .get();

      for (final doc in snap.docs) {
        try {
          final msg = GroupChatMessageModel.fromMap(doc.data());
          if (msg.senderId == currentUserId &&
              !msg.timeSent.isBefore(windowStart) &&
              !msg.timeSent.isAfter(windowEnd)) {
            return true;
          }
        } catch (_) {}
      }
    } catch (e) {
      log('⚠️ Firestore check for wish message failed: $e');
    }

    return false;
  }

  /// Core evaluation: evaluates the active window at [nowOverride] and triggers
  /// alert notifications if deadline thresholds (80%, 90%, 95%) are met and unwished.
  ///
  /// Returns the list of unwished groups that were alerted.
  Future<List<GroupModel>> checkReminders({DateTime? nowOverride}) async {
    if (!AppCapabilities.current.notificationsEnabled) {
      return [];
    }

    final now = nowOverride ?? DateTime.now();
    final windowInfo = WishWindowInfo.forDateTime(now);
    final reachedThresholds = windowInfo.getReachedThresholdsList(now);

    if (reachedThresholds.isEmpty) {
      // Under 80% deadline completion, no reminder alert needed yet
      return [];
    }

    final prefs = _prefsOverride ?? await SharedPreferences.getInstance();
    final currentUserId = (_authOverride ?? FirebaseAuth.instance).currentUser?.uid ??
        prefs.getString('cached_current_user_id');

    if (currentUserId == null || currentUserId.isEmpty) {
      return [];
    }

    final eligibleGroups = await getGroupsForWindow(
      windowInfo.type,
      currentUserId,
    );
    if (eligibleGroups.isEmpty) {
      return [];
    }

    final List<GroupModel> alertedGroups = [];
    final highestThreshold = reachedThresholds.last;

    for (final group in eligibleGroups) {
      final dedupeKeyHighest =
          'wish_reminder_${group.groupId}_${windowInfo.startTime.millisecondsSinceEpoch}_$highestThreshold';

      // If highest reached threshold was already notified for this group, skip
      if (prefs.getBool(dedupeKeyHighest) == true) {
        continue;
      }

      // Check if user has already wished this deity in the active window
      final wished = await hasUserWishedGroup(
        groupId: group.groupId,
        currentUserId: currentUserId,
        windowStart: windowInfo.startTime,
        windowEnd: windowInfo.endTime,
      );

      if (wished) {
        // Mark all reached thresholds as completed so no future alerts fire for this window
        for (final t in reachedThresholds) {
          final key =
              'wish_reminder_${group.groupId}_${windowInfo.startTime.millisecondsSinceEpoch}_$t';
          await prefs.setBool(key, true);
        }
        continue;
      }

      // Deity is unwished and deadline has completed 80%, 90%, or 95%!
      // Post alert notification with navigation payload targeting this deity sanctuary.
      final notifId =
          (group.groupId.hashCode ^ highestThreshold).abs() % 1000000 + 10000;
      final remainingPercent = 100 - highestThreshold;
      final title = '👑 Royal Wish Alert ($highestThreshold% Deadline)';
      final body =
          'You haven\'t wished ${group.nameWithPosition}! Only $remainingPercent% of the sacred devotion window remains.';

      final payload = jsonEncode({
        'type': 'group',
        'groupId': group.groupId,
        'groupName': group.nameWithPosition,
        'name': group.nameWithPosition,
        'groupPic': group.groupPic,
        'queendom': group.queendom,
        'chatBackgroundUrl': group.chatBackgroundUrl,
        'wish': group.wish,
      });

      if (_notificationSenderOverride != null) {
        await _notificationSenderOverride!(
          id: notifId,
          title: title,
          body: body,
          payload: payload,
        );
      } else {
        await FirebaseNotificationService.showWishReminderNotification(
          id: notifId,
          title: title,
          body: body,
          payload: payload,
        );
      }

      // Mark all reached thresholds as notified in SharedPreferences
      for (final t in reachedThresholds) {
        final key =
            'wish_reminder_${group.groupId}_${windowInfo.startTime.millisecondsSinceEpoch}_$t';
        await prefs.setBool(key, true);
      }

      alertedGroups.add(group);
      log('🚨 Wish reminder triggered for ${group.nameWithPosition} at $highestThreshold% deadline');
    }

    return alertedGroups;
  }
}

