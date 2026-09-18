import 'dart:developer';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:worship_chat/features/auth/repository/auth_repository.dart';
import 'package:worship_chat/models/user_model.dart';

final authControllerProvider = Provider((ref) {
  final authRepository = ref.watch(authRepositoryProvider);
  return AuthController(authRepository: authRepository, ref: ref);
});

final userDataAuthProvider = FutureProvider<UserModel?>((ref) {
  final authController = ref.watch(authControllerProvider);
  return authController.getUsetData();
});

final authStateChangesProvider = StreamProvider<User?>((ref) {
  final auth = FirebaseAuth.instance;

  log('🔐 Auth state provider initialized');

  // Create a custom stream that handles reload properly
  return auth
      .authStateChanges()
      .asyncMap((user) async {
        if (user != null) {
          try {
            // Always reload to get the latest user state
            //   await user.reload();
            final refreshedUser = auth.currentUser;

            if (refreshedUser == null) {
              log('⚠️ User signed out during reload');
              return null;
            }

            log(
              '✅ User reloaded - Email verified: ${refreshedUser.emailVerified}',
            );
            return refreshedUser;
          } catch (e) {
            // If reload fails, user might be deleted or token expired
            log('❌ Error reloading user: $e');

            // Force sign out if user is invalid
            if (e is FirebaseAuthException) {
              if (e.code == 'user-not-found' ||
                  e.code == 'user-disabled' ||
                  e.code == 'user-token-expired') {
                log('🚪 Signing out invalid user');
                await auth.signOut();
                return null;
              }
            }

            // Return current user if reload fails for other reasons
            return user;
          }
        }

        log('👤 No user authenticated');
        return null;
      })
      .handleError((error, stackTrace) {
        log('❌ Auth stream error: $error');
        log('Stack trace: $stackTrace');
        return null;
      });
});

// Helper provider to manually trigger auth refresh
final forceAuthRefreshProvider = Provider<void Function()>((ref) {
  return () {
    log('🔄 Force refreshing auth state');
    ref.invalidate(authStateChangesProvider);
  };
});

// Provider to check if user email is verified
final isEmailVerifiedProvider = StreamProvider<bool>((ref) {
  return FirebaseAuth.instance.authStateChanges().asyncMap((user) async {
    if (user == null) return false;

    try {
      await user.reload();
      final refreshedUser = FirebaseAuth.instance.currentUser;
      return refreshedUser?.emailVerified ?? false;
    } catch (e) {
      log('❌ Error checking email verification: $e');
      return user.emailVerified;
    }
  });
});

final userSetupProvider = FutureProvider<bool>((ref) async {
  final userModel = await ref.watch(userDataAuthProvider.future);

  // Null user or missing name/profilePic → not set up
  if (userModel == null) return false;
  return userModel.name!.isNotEmpty && userModel.profilePic != null;
});

class AuthController {
  final AuthRepository authRepository;
  final Ref ref;
  AuthController({required this.authRepository, required this.ref});

  Future<UserModel?> getUsetData() async {
    UserModel? user = await authRepository.getCurrentUserData();
    return user;
  }

  Future<void> registerWithEmail(
    BuildContext context,
    String name,
    String userName,
    String email,
    String password,
  ) async {
    await authRepository.registerWithEmail(
      context,
      name,
      userName,
      email,
      password,
    );
  }

  Future<void> loginWithEmail(
    BuildContext context,
    String email,
    String password,
  ) async {
    await authRepository.loginWithEmail(context, email, password);
  }

  void resetPassword(BuildContext context, String email) {
    log(email);
    authRepository.resetPassword(context, email);
  }

  void saveUserDatatoFirebase(
    BuildContext context,
    String name,
    File? profilePic, {
    String? userName, // Added userName parameter
  }) {
    authRepository.saveUserDataToFirebase(
      name: name,
      profilePic: profilePic,
      userName: userName, // Pass userName
      ref: ref,
      context: context,
    );
  }

  Stream<UserModel> userDataById(String userId) {
    return authRepository.userData(userId);
  }

  void setUserState(bool isOnline) {
    authRepository.setUserState(isOnline);
  }

  void logout(BuildContext context) {
    authRepository.logout(context);
  }
}
