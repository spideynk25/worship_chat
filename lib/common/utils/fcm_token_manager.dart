import 'dart:developer';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:worship_chat/models/user_model.dart';

class FCMTokenManager {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  // Initialize FCM and save token
  static Future<void> initializeFCM() async {
    try {
      // Request permission (iOS / Android 13+)
      try {
        await _messaging.requestPermission(
          alert: true,
          announcement: false,
          badge: true,
          carPlay: false,
          criticalAlert: false,
          provisional: false,
          sound: true,
        );
      } catch (e) {
        log('Warning: requestPermission error: $e');
      }

      // Always listen for token refresh
      _messaging.onTokenRefresh.listen((newToken) {
        log('🔄 FCM token refreshed: $newToken');
        _saveFCMTokenToFirestore(newToken);
      });

      // Always listen for auth state changes so when user logs in, token is immediately saved
      _auth.authStateChanges().listen((user) {
        if (user != null) {
          log(
            '👤 User authenticated (${user.uid}) - refreshing and saving FCM token',
          );
          refreshAndSaveFCMToken();
        }
      });

      // Try initial token refresh if user is currently logged in
      if (_auth.currentUser != null) {
        await refreshAndSaveFCMToken();
      }
    } catch (e) {
      log('❌ Error initializing FCM: $e');
    }
  }

  // Get current FCM token and save to Firestore + local Hive
  static Future<String?> refreshAndSaveFCMToken({int maxRetries = 3}) async {
    try {
      // 1. Wait briefly for auth to resolve if still initializing
      String? userId = _auth.currentUser?.uid;
      if (userId == null) {
        for (int i = 0; i < 6; i++) {
          await Future.delayed(const Duration(milliseconds: 250));
          userId = _auth.currentUser?.uid;
          if (userId != null) break;
        }
      }

      if (userId == null) {
        log('⚠️ No user logged in - cannot save FCM token');
        return null;
      }

      // 2. Fetch token with retries
      String? token;
      for (int attempt = 1; attempt <= maxRetries; attempt++) {
        try {
          token = await _messaging.getToken();
          if (token != null && token.isNotEmpty) break;
        } catch (e) {
          log('⚠️ getToken attempt $attempt failed: $e');
          if (attempt < maxRetries) {
            await Future.delayed(Duration(milliseconds: 500 * attempt));
          }
        }
      }

      if (token != null && token.isNotEmpty) {
        log('✅ Got FCM token: ${token.substring(0, token.length > 20 ? 20 : token.length)}...');
        await _saveFCMTokenToFirestore(token, targetUserId: userId);
        return token;
      } else {
        log('⚠️ FCM token is null or empty after $maxRetries attempts');
        return null;
      }
    } catch (e) {
      log('❌ Error getting FCM token: $e');
      return null;
    }
  }

  // Save FCM token to user document in Firestore and sync to Hive cache
  static Future<void> _saveFCMTokenToFirestore(String token, {String? targetUserId}) async {
    try {
      final userId = targetUserId ?? _auth.currentUser?.uid;
      if (userId == null) return;

      // 1. Save to Firestore
      await _firestore.collection('users').doc(userId).set({
        'fcmToken': token,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      log('✅ FCM token saved to Firestore for user: $userId');

      // 2. Sync to local Hive user cache immediately
      try {
        if (Hive.isBoxOpen('userBox')) {
          final box = Hive.box<UserModel>('userBox');
          final current = box.get('currentUser');
          if (current != null && current.uid == userId) {
            final updated = UserModel(
              userName: current.userName,
              name: current.name,
              uid: current.uid,
              profilePic: current.profilePic,
              isOnline: current.isOnline,
              email: current.email,
              groupId: current.groupId,
              fcmToken: token,
            );
            await box.put('currentUser', updated);
            log('✅ Synced fresh FCM token to Hive userBox');
          }
        }
      } catch (e) {
        log('Note: could not update token in userBox: $e');
      }
    } catch (e) {
      log('❌ Error saving FCM token to Firestore: $e');
    }
  }

  // Get fresh FCM tokens for a list of user IDs (server-first with cache fallback)
  static Future<List<String>> getFreshFCMTokens(List<String> userIds) async {
    if (userIds.isEmpty) return [];

    try {
      final futures = userIds.map((userId) async {
        try {
          DocumentSnapshot<Map<String, dynamic>> userDoc;
          try {
            userDoc = await _firestore
                .collection('users')
                .doc(userId)
                .get(const GetOptions(source: Source.server))
                .timeout(const Duration(seconds: 3));
          } catch (_) {
            userDoc = await _firestore
                .collection('users')
                .doc(userId)
                .get();
          }

          if (userDoc.exists) {
            final token = userDoc.data()?['fcmToken'];
            if (token != null && token is String && token.isNotEmpty) {
              log('✅ Got token for user $userId: ${token.substring(0, 20)}...');
              return token;
            } else {
              log('⚠️ No valid token for user: $userId');
            }
          } else {
            log('⚠️ User document not found: $userId');
          }
        } catch (e) {
          log('❌ Error fetching token for user $userId: $e');
        }
        return null;
      }).toList();

      final results = await Future.wait(futures);
      final tokens = results
          .where((t) => t != null && t.isNotEmpty)
          .cast<String>()
          .toSet()
          .toList();

      log('📊 Total valid tokens: ${tokens.length} out of ${userIds.length}');
      return tokens;
    } catch (e) {
      log('❌ Error fetching FCM tokens: $e');
      return [];
    }
  }

  // Get FCM tokens for group members (excluding current user)
  static Future<List<String>> getGroupMemberTokens(String groupId) async {
    try {
      final groupDoc = await _firestore.collection('groups').doc(groupId).get();

      if (!groupDoc.exists || groupDoc.data() == null) {
        log('⚠️ Group not found: $groupId');
        return [];
      }

      final groupData = groupDoc.data()!;
      final membersUid = List<String>.from(groupData['membersUid'] ?? []);
      final currentUserId = _auth.currentUser?.uid;

      // Remove current user from list
      final otherMembers = membersUid
          .where((uid) => uid != currentUserId)
          .toList();

      log('👥 Getting tokens for ${otherMembers.length} group members');

      List<String> tokens = await getFreshFCMTokens(otherMembers);

      // Fallback: If no tokens found from user documents, check group.fcmTokens
      if (tokens.isEmpty) {
        log(
          '⚠️ No tokens from user documents, checking stored group.fcmTokens as fallback',
        );
        final storedTokens = List<String>.from(groupData['fcmTokens'] ?? []);
        final currentToken = await _messaging.getToken();
        tokens = storedTokens
            .where((t) => t.isNotEmpty && t != currentToken)
            .toSet()
            .toList();
        log('📦 Fallback group tokens count: ${tokens.length}');
      }

      return tokens;
    } catch (e) {
      log('❌ Error getting group member tokens: $e');
      return [];
    }
  }

  // Verify if user has valid FCM token
  static Future<bool> hasValidFCMToken(String userId) async {
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();

      if (userDoc.exists) {
        final token = userDoc.data()?['fcmToken'];
        return token != null && token is String && token.isNotEmpty;
      }
      return false;
    } catch (e) {
      log('❌ Error checking FCM token: $e');
      return false;
    }
  }

  // Debug: Print all FCM tokens in a group
  static Future<void> debugGroupTokens(String groupId) async {
    try {
      log('🔍 === FCM TOKEN DEBUG FOR GROUP: $groupId ===');

      final groupDoc = await _firestore.collection('groups').doc(groupId).get();

      if (!groupDoc.exists) {
        log('❌ Group not found');
        return;
      }

      final groupData = groupDoc.data()!;
      final membersUid = List<String>.from(groupData['membersUid'] ?? []);
      final storedTokens = List<String>.from(groupData['fcmTokens'] ?? []);

      log('👥 Group has ${membersUid.length} members');
      log('📱 Stored FCM tokens in group: ${storedTokens.length}');

      for (var uid in membersUid) {
        final userDoc = await _firestore.collection('users').doc(uid).get();
        if (userDoc.exists) {
          final token = userDoc.data()?['fcmToken'];
          log('User $uid: ${token != null ? "✅ Has token" : "❌ No token"}');
        } else {
          log('User $uid: ❌ User document not found');
        }
      }

      log('🔍 === END DEBUG ===');
    } catch (e) {
      log('❌ Debug error: $e');
    }
  }
}
