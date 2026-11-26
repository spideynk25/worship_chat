import 'dart:developer';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloudinary_flutter/cloudinary_context.dart';
import 'package:cloudinary_url_gen/cloudinary.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/adapters.dart';
import 'package:worship_chat/common/utils/fcm_token_manager.dart';
import 'package:worship_chat/common/utils/app_capabilities.dart';
import 'package:worship_chat/common/utils/utils.dart';
import 'package:worship_chat/features/auth/screens/login_screen.dart';
import 'package:worship_chat/features/auth/controller/auth_controller.dart';
import 'package:worship_chat/features/home/screens/home_screen.dart';
import 'package:worship_chat/models/user_model.dart';

final authRepositoryProvider = Provider(
  (ref) => AuthRepository(
    auth: FirebaseAuth.instance,
    firestore: FirebaseFirestore.instance,
  ),
);

class AuthRepository {
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  AuthRepository({required this.auth, required this.firestore});

  Future<void> _saveUserToHive(UserModel user) async {
    final userBox = Hive.box<UserModel>('userBox');
    await userBox.put('currentUser', user);
  }

  Future<UserModel?> getCurrentUserData() async {
    final userId = auth.currentUser?.uid ?? (Hive.isBoxOpen('userBox') ? Hive.box<UserModel>('userBox').get('currentUser')?.uid : null);
    if (userId == null) return null;
    try {
      var userData = await firestore
          .collection('users')
          .doc(userId)
          .get();
      // A previous account's in-flight read must not overwrite the new cache.
      if (auth.currentUser?.uid != null && auth.currentUser?.uid != userId) return null;
      UserModel? user;
      if (userData.data() != null) {
        user = UserModel.fromMap(userData.data()!);
        await _saveUserToHive(user); // Save to Hive
      }
      return user ?? (Hive.isBoxOpen('userBox') ? Hive.box<UserModel>('userBox').get('currentUser') : null);
    } catch (_) {
      if (Hive.isBoxOpen('userBox')) {
        return Hive.box<UserModel>('userBox').get('currentUser');
      }
      return null;
    }
  }

  Future<void> registerWithEmail(
    BuildContext context,
    String name,
    String userName,
    String email,
    String password,
  ) async {
    try {
      // 🔍 Check if username already exists in Firestore
      final usernameQuery = await firestore
          .collection('users')
          .where('userName', isEqualTo: userName)
          .get();

      if (usernameQuery.docs.isNotEmpty) {
        AppSnackBar.error(
          context,
          'Username is already taken. Please choose another.',
        );
        return;
      }

      // 👤 Create user with Firebase Auth
      final response = await auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );

      final user = response.user;
      if (user == null) {
        throw Exception('User creation failed.');
      }

      // 🆔 Update display name
      await user.updateDisplayName(userName);

      // 📧 Send email verification
      await user.sendEmailVerification();

      // Notification registration is optional and only available on phones.
      String? token;
      if (AppCapabilities.current.notificationsEnabled) {
        try {
          token = await FirebaseMessaging.instance.getToken();
        } catch (e) {
          log('Could not get FCM token during registration: $e');
        }
      }

      // 🗃️ Save user to Firestore
      await firestore.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'name': name,
        'userName': userName,
        'email': email.trim(),
        'profilePic': '',
        'isOnline': AppCapabilities.current.chatEnabled,
        'groupId': [],
        'createdAt': FieldValue.serverTimestamp(),
        'lastSeen': FieldValue.serverTimestamp(),
        if (token != null && token.isNotEmpty) 'fcmToken': token,
      });

      // 💾 Save to Hive immediately so HomeScreen can show name/userName right away
      final newUser = UserModel(
        userName: userName,
        name: name,
        uid: user.uid,
        profilePic: '',
        isOnline: AppCapabilities.current.chatEnabled,
        email: email.trim(),
        groupId: [],
        fcmToken: token,
        lastSeen: DateTime.now(),
      );
      await _saveUserToHive(newUser);
      log('✅ New user saved to Hive: ${newUser.name}');

      AppSnackBar.success(
        context,
        'Registration successful! Please verify your email.',
      );

      log("Registration successful for user: ${user.uid}");
    } on FirebaseAuthException catch (e) {
      String errorMessage;
      switch (e.code) {
        case 'weak-password':
          errorMessage = 'The password is too weak.';
          break;
        case 'email-already-in-use':
          errorMessage = 'This email is already in use.';
          break;
        case 'invalid-email':
          errorMessage = 'The email address is invalid.';
          break;
        case 'operation-not-allowed':
          errorMessage = 'Email/password sign-in is not enabled.';
          break;
        default:
          errorMessage = 'Registration failed: ${e.message}';
      }

      AppSnackBar.error(context, errorMessage);
    } catch (e) {
      AppSnackBar.error(context, 'Unexpected error: ${e.toString()}');
    }
  }

  Future<void> loginWithEmail(
    BuildContext context,
    String email,
    String password,
  ) async {
    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );

      // 🔥 THIS FIXES POCO
      await credential.user?.getIdToken(true);

      // 🔥 SMALL DELAY (HyperOS needs it)
      await Future.delayed(const Duration(milliseconds: 400));

      if (!credential.user!.emailVerified) {
        AppSnackBar.warning(context, 'Please verify your email');
        return;
      }

      // Ensure fresh FCM token is stored for group and 1-to-1 notifications
      if (AppCapabilities.current.notificationsEnabled) {
        FCMTokenManager.refreshAndSaveFCMToken();
      }

      // 💾 Eagerly fetch & cache user data to Hive so HomeScreen shows
      // name / userName / profilePic immediately (no waiting for a message).
      try {
        await getCurrentUserData();
        log('✅ User data cached to Hive on login');
      } catch (e) {
        log('⚠️ Could not pre-cache user data on login: $e');
      }

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (_) => false,
      );
    } on FirebaseAuthException catch (e) {
      String errorMessage;
      switch (e.code) {
        case 'invalid-credential':
        case 'wrong-password':
        case 'user-not-found':
          errorMessage = 'Incorrect email or password. Please check your credentials or reset your password.';
          break;
        case 'user-disabled':
          errorMessage = 'This user account has been disabled.';
          break;
        case 'too-many-requests':
          errorMessage =
              'Too many failed attempts. Please reset your password or try again later.';
          break;
        case 'keychain-error':
          errorMessage =
              'macOS Keychain access restricted. Enable Keychain Sharing in Xcode or use "Enter Gallery Directly".';
          break;
        case 'network-request-failed':
          errorMessage = 'Network error. Please check your internet connection.';
          break;
        default:
          errorMessage = e.message ?? 'Login failed. Please try again.';
      }
      AppSnackBar.error(context, errorMessage);
    }
  }

  void resetPassword(BuildContext context, String email) async {
    try {
      log(email);
      await auth.sendPasswordResetEmail(email: email);
      AppSnackBar.info(context, 'Check your inbox for password reset link');
    } catch (e) {
      showSnackBar(context: context, content: e.toString());
    }
  }

  Future<bool> saveUserDataToFirebase({
    required String name,
    required File? profilePic,
    String? userName, // Added userName parameter
    required Ref ref,
    required BuildContext context,
    bool navigateHomeOnComplete = true,
    bool removeProfilePic = false,
  }) async {
    try {
      final currentUserData = auth.currentUser;
      if (currentUserData == null) {
        if (context.mounted) {
          AppSnackBar.error(context, 'Not signed in. Please log in again.');
        }
        return false;
      }

      final cleanName = name.trim();
      final cleanUserName = userName?.trim();

      if (cleanName.isEmpty) {
        if (context.mounted) {
          AppSnackBar.warning(context, 'Display name cannot be empty.');
        }
        return false;
      }

      // Validate username format & uniqueness BEFORE uploading any new photo.
      if (cleanUserName != null) {
        if (cleanUserName.isEmpty) {
          if (context.mounted) {
            AppSnackBar.warning(context, 'Username cannot be empty.');
          }
          return false;
        }
        if (RegExp(r'\s').hasMatch(cleanUserName)) {
          if (context.mounted) {
            AppSnackBar.warning(context, 'Username cannot contain spaces.');
          }
          return false;
        }
        if (cleanUserName != currentUserData.displayName) {
          final usernameQuery = await firestore
              .collection('users')
              .where('userName', isEqualTo: cleanUserName)
              .get();
          if (usernameQuery.docs.isNotEmpty &&
              usernameQuery.docs.first.id != currentUserData.uid) {
            if (context.mounted) {
              AppSnackBar.error(
                context,
                'Username is already taken. Please choose another.',
              );
            }
            return false;
          }
        }
      }

      String? photoUrl = removeProfilePic ? '' : currentUserData.photoURL;
      if (!removeProfilePic && profilePic != null) {
        final uploadedUrl = await uploadImageToCloudinary(profilePic);
        if (uploadedUrl == null || uploadedUrl.isEmpty) {
          if (context.mounted) {
            AppSnackBar.error(
              context,
              'Failed to upload profile photo. Please try again.',
            );
          }
          return false;
        }
        photoUrl = uploadedUrl;
      }
      if (photoUrl != null && photoUrl.startsWith('http://')) {
        photoUrl = photoUrl.replaceFirst('http://', 'https://');
      }

      await currentUserData.updateProfile(
        displayName: cleanUserName ?? currentUserData.displayName,
        photoURL: removeProfilePic ? null : photoUrl,
      );

      // Preserve existing user fields like fcmToken and groupId
      final cachedUser = Hive.box<UserModel>('userBox').get('currentUser');
      final currentCache = cachedUser?.uid == currentUserData.uid ? cachedUser : null;
      String existingFcm = currentCache?.fcmToken ?? "";
      List<String> existingGroup = currentCache?.groupId ?? [];
      bool existingOnline = currentCache?.isOnline ?? false;
      DateTime? existingLastSeen = currentCache?.lastSeen;
      try {
        final existingDoc = await firestore
            .collection('users')
            .doc(currentUserData.uid)
            .get();
        if (existingDoc.exists && existingDoc.data() != null) {
          final data = existingDoc.data()!;
          existingFcm = data['fcmToken']?.toString() ?? "";
          existingGroup = List<String>.from(data['groupId'] ?? []);
          existingOnline = data['isOnline'] == true;
          final rawLastSeen = data['lastSeen'];
          if (rawLastSeen is Timestamp) {
            existingLastSeen = rawLastSeen.toDate();
          } else if (rawLastSeen is DateTime) {
            existingLastSeen = rawLastSeen;
          } else if (rawLastSeen is int) {
            existingLastSeen = DateTime.fromMillisecondsSinceEpoch(rawLastSeen);
          }
        }
      } catch (_) {}

      if (AppCapabilities.current.notificationsEnabled && existingFcm.isEmpty) {
        try {
          existingFcm = await FirebaseMessaging.instance.getToken() ?? "";
        } catch (_) {}
      }

      var user = UserModel(
        userName: cleanUserName ?? currentUserData.displayName ?? '',
        name: cleanName,
        uid: currentUserData.uid,
        profilePic: photoUrl ?? "",
        isOnline: AppCapabilities.current.chatEnabled ? true : existingOnline,
        email: currentUserData.email ?? '',
        groupId: existingGroup,
        fcmToken: existingFcm,
        lastSeen: existingLastSeen,
      );

      final profileUpdate = user.toMap();
      // Profile edits cannot change membership, including when metadata is offline.
      profileUpdate.remove('groupId');
      profileUpdate.remove('lastSeen');
      if (!AppCapabilities.current.notificationsEnabled) {
        // A gallery session must never replace a token registered by a phone.
        profileUpdate.remove('fcmToken');
      }
      if (!AppCapabilities.current.chatEnabled) {
        // Online presence describes the user's phone chat session.
        profileUpdate.remove('isOnline');
      }
      await firestore
          .collection('users')
          .doc(currentUserData.uid)
          .set(profileUpdate, SetOptions(merge: true));

      await _saveUserToHive(user);
      ref.invalidate(userDataAuthProvider);
      log('User data saved to Firestore and Hive: ${user.toMap()}');

      // Update existing bookmarks created by this user to keep profile pic and name in sync
      try {
        final bookmarksQuery = await firestore
            .collection('bookmarks')
            .where('userId', isEqualTo: currentUserData.uid)
            .get();
        if (bookmarksQuery.docs.isNotEmpty) {
          final docs = bookmarksQuery.docs;
          for (var i = 0; i < docs.length; i += 450) {
            final chunk = docs.sublist(
              i,
              i + 450 > docs.length ? docs.length : i + 450,
            );
            final batch = firestore.batch();
            for (final doc in chunk) {
              batch.update(doc.reference, {
                'userProfilePic': photoUrl ?? "",
                'userName': cleanName,
              });
            }
            await batch.commit();
          }
          log('✅ Updated ${bookmarksQuery.docs.length} bookmarks with new user profile pic');
        }
      } catch (e) {
        log('⚠️ Could not batch update bookmarks on profile pic change: $e');
      }

      if (navigateHomeOnComplete && context.mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
          (route) => false,
        );
      }
      return true;
    } catch (e) {
      log("Error saving user data: $e");
      if (context.mounted) {
        AppSnackBar.error(context, e.toString());
      }
      return false;
    }
  }

  Stream<UserModel> userData(String userId) {
    final cleanUid = userId.trim();
    if (cleanUid.isEmpty) return const Stream.empty();
    return firestore
        .collection('users')
        .doc(cleanUid)
        .snapshots()
        .where((event) => event.exists && event.data() != null)
        .map((event) {
          final user = UserModel.fromMap(event.data()!);
          if (cleanUid == auth.currentUser?.uid) {
            _saveUserToHive(user);
          }
          return user;
        });
  }

  void setUserState(bool isOnline) async {
    if (!AppCapabilities.current.chatEnabled) return;
    final userId = auth.currentUser?.uid;
    if (userId == null) return;
    try {
      final updateData = <String, dynamic>{
        'isOnline': isOnline,
      };
      if (!isOnline) {
        updateData['lastSeen'] = FieldValue.serverTimestamp();
      }
      await firestore.collection('users').doc(userId).update(updateData);
    } catch (e) {
      log('Error updating user state: $e');
    }
  }

  void logout(BuildContext context) async {
    try {
      final userId = auth.currentUser?.uid;
      if (userId != null) {
        try {
          await firestore.collection('users').doc(userId).update({
            'isOnline': false,
            'lastSeen': FieldValue.serverTimestamp(),
          });
        } catch (e) {
          log('Error setting offline status on logout: $e');
        }
      }
      await auth.signOut();
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    } catch (e) {
      showSnackBar(
        context: context,
        content: 'Error during logout: ${e.toString()}',
      );
    }
  }

  Future<String?> uploadImageToCloudinary(File file) async {
    try {
      log("reached image cloundinary");
      CloudinaryContext.cloudinary = Cloudinary.fromCloudName(
        cloudName: "djr22nlx9",
      );
      final dio = Dio();
      const url = 'https://api.cloudinary.com/v1_1/djr22nlx9/upload';

      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(file.path),
        'upload_preset': 'ml_default',
      });

      final response = await dio.post(url, data: formData);
      log("image response $response");
      if (response.statusCode == 200) {
        final raw = response.data["secure_url"] as String? ??
            response.data["url"] as String? ??
            '';
        final cleanUrl = raw.startsWith('http://')
            ? raw.replaceFirst('http://', 'https://')
            : raw;
        log("Cloudinary image URL: $cleanUrl");
        return cleanUrl;
      } else {
        throw Exception('Failed to upload image: ${response.data}');
      }
    } catch (e) {
      debugPrint('Error uploading image: $e');
      return null;
    }
  }
}
