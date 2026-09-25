import 'dart:developer';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:worship_chat/common/providers/message_reply_provider.dart';
import 'package:worship_chat/features/auth/controller/auth_controller.dart';
import 'package:worship_chat/features/chat/repositories/chat_repository.dart';
import 'package:worship_chat/models/chat_contact.dart';
import 'package:worship_chat/models/one_to_one_message_model.dart';
import 'package:worship_chat/models/user_model.dart';

final chatControllerProvider = Provider((ref) {
  final chatRepository = ref.watch(chatRepositoryProvider);
  return ChatController(chatRepository: chatRepository, ref: ref);
});

class ChatController {
  final ChatRepository chatRepository;
  final Ref ref;

  ChatController({required this.chatRepository, required this.ref});

  List<ChatContact> getCachedContacts({required bool isAllChats}) {
    return chatRepository.getCachedContacts(isAllChats: isAllChats);
  }

  Stream<List<ChatContact>> chatContacts() {
    return chatRepository.getChatContact();
  }

  Stream<List<ChatContact>> fetchAllContacts() {
    return chatRepository.fetchAllContacts();
  }

  Stream<List<OneToOneMessageModel>> chatStream(String receiverUserId) {
    return chatRepository.getChatStream(receiverUserId);
  }

  Future<void> updateChatBackground(
    String receiverUserId,
    String backgroundImageUrl,
  ) async {
    try {
      chatRepository.updateChatBackground(receiverUserId, backgroundImageUrl);
    } catch (e) {
      log("error on setChatBackground: $e");
    }
  }

  Stream<bool> getTypingStatus(String receiverUserId) {
    return chatRepository.getTypingStatus(receiverUserId);
  }

  void setTypingStatus(String receiverUserId, bool isTyping) {
    chatRepository.setTypingStatus(receiverUserId, isTyping);
  }

  Future<void> sendTextMessage(
    BuildContext context,
    String text,
    String receiverUserId,
    String messageType,
    dynamic file,
    String fcmToken,
    bool? unseenCount,
    String? chatBackgroundUrl,
    String type,
  ) async {
    try {
      final messageReply = ref.read(messageReplyProvider);
      log("controller sendTextMessage: $fcmToken");

      UserModel? senderUser = await ref.read(userDataAuthProvider.future);
      if (senderUser == null && Hive.isBoxOpen('userBox')) {
        senderUser = Hive.box<UserModel>('userBox').get('currentUser');
      }
      if (senderUser == null) {
        final authUser = FirebaseAuth.instance.currentUser;
        if (authUser != null) {
          senderUser = UserModel(
            name: authUser.displayName ?? 'User',
            userName: authUser.displayName ?? 'User',
            uid: authUser.uid,
            profilePic: authUser.photoURL ?? '',
            isOnline: true,
            email: authUser.email ?? '',
            groupId: [],
            fcmToken: await FirebaseMessaging.instance.getToken(),
          );
        }
      }

      if (senderUser != null) {
        await chatRepository.sendTextMessage(
          messageReply: messageReply,
          messageType: messageType,
          file: file,
          context: context,
          text: text,
          receiverUserId: receiverUserId,
          senderUser: senderUser,
          fcmToken: fcmToken,
          unseenCount: unseenCount,
          chatBackgroundUrl: chatBackgroundUrl,
          type: type,
        );
        ref.read(messageReplyProvider.notifier).state = null;
      } else {
        log("User data is null");
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Unable to send message')),
          );
        }
      }
    } catch (e) {
      log("error in send text message chat_controller: $e");
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to send message')));
      }
    }
  }

  // ✅ Now async and properly awaited
  Future<void> setChatMessageSeen(
    BuildContext context,
    String receiverUserId,
    String messageId,
  ) async {
    try {
      await chatRepository.setChatMessageSeen(
        context,
        receiverUserId,
        messageId,
      );
    } catch (e) {
      log("error on setChatMessageSeen: $e");
    }
  }

  void markChatAsSeen(String partnerUserId) {
    try {
      chatRepository.markChatAsSeen(partnerUserId);
    } catch (e) {
      log("error on markChatAsSeen: $e");
    }
  }

  // ── Add these two methods to ChatController ──────────────────────────────────

  Future<List<OneToOneMessageModel>> getSharedMedia(
    String receiverUserId,
  ) async {
    try {
      return await chatRepository.getSharedMedia(receiverUserId);
    } catch (e) {
      log('error on getSharedMedia: $e');
      return [];
    }
  }

  Future<List<OneToOneMessageModel>> getSharedLinks(
    String receiverUserId,
  ) async {
    try {
      return await chatRepository.getSharedLinks(receiverUserId);
    } catch (e) {
      log('error on getSharedLinks: $e');
      return [];
    }
  }
}
