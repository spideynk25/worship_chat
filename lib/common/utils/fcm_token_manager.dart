import 'dart:developer';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class FCMTokenManager {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  // Initialize FCM and save token
  static Future<void> initializeFCM() async {
    try {
      // Request permission (iOS)
      NotificationSettings settings = await _messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        // Get and save token
        await refreshAndSaveFCMToken();

        // Listen for token refresh
        _messaging.onTokenRefresh.listen((newToken) {
          _saveFCMTokenToFirestore(newToken);
        });
      } else {}
    } catch (e) {
      log('❌ Error initializing FCM: $e');
    }
  }

  // Get current FCM token and save to Firestore
  static Future<String?> refreshAndSaveFCMToken() async {
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) {
        log('⚠️ No user logged in - cannot save FCM token');
        return null;
      }

      final token = await _messaging.getToken();

      if (token != null && token.isNotEmpty) {
        log('✅ Got FCM token: $token');
        await _saveFCMTokenToFirestore(token);
        return token;
      } else {
        log('⚠️ FCM token is null or empty');
        return null;
      }
    } catch (e) {
      log('❌ Error getting FCM token: $e');
      return null;
    }
  }

  // Save FCM token to user document
  static Future<void> _saveFCMTokenToFirestore(String token) async {
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) return;

      await _firestore.collection('users').doc(userId).update({
        'fcmToken': token,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      });

      log('✅ FCM token saved to Firestore for user: $userId');
    } catch (e) {
      log('❌ Error saving FCM token to Firestore: $e');
    }
  }

  // Get fresh FCM tokens for a list of user IDs
  static Future<List<String>> getFreshFCMTokens(List<String> userIds) async {
    List<String> tokens = [];

    try {
      for (var userId in userIds) {
        final userDoc = await _firestore.collection('users').doc(userId).get();

        if (userDoc.exists) {
          final token = userDoc.data()?['fcmToken'];
          if (token != null && token is String && token.isNotEmpty) {
            tokens.add(token);
            log('✅ Got token for user $userId: ${token.substring(0, 20)}...');
          } else {
            log('⚠️ No valid token for user: $userId');
          }
        } else {
          log('⚠️ User document not found: $userId');
        }
      }

      log('📊 Total valid tokens: ${tokens.length} out of ${userIds.length}');
    } catch (e) {
      log('❌ Error fetching FCM tokens: $e');
    }

    return tokens;
  }

  // Get FCM tokens for group members (excluding current user)
  static Future<List<String>> getGroupMemberTokens(String groupId) async {
    try {
      final groupDoc = await _firestore.collection('groups').doc(groupId).get();

      if (!groupDoc.exists) {
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

      return await getFreshFCMTokens(otherMembers);
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
