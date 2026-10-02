import 'dart:developer';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:worship_chat/common/providers/message_reply_provider.dart';
import 'package:worship_chat/features/auth/controller/auth_controller.dart';
import 'package:worship_chat/features/group/repository/group_repository.dart';
import 'package:worship_chat/models/chat_contact.dart';
import 'package:worship_chat/models/group.dart';
import 'package:worship_chat/models/group_chat_message_model.dart';
import 'package:worship_chat/models/user_model.dart';

final groupControllerProvider = Provider((ref) {
  final groupRepository = ref.read(groupRepositoryProvider);
  return GroupController(groupRepository: groupRepository, ref: ref);
});

class GroupController {
  final GroupRepository groupRepository;
  final Ref ref;

  GroupController({required this.groupRepository, required this.ref});

  Future<void> updateGroup(
    BuildContext context,
    String groupId,
    String name,
    String? wish,
    String selectedQueendom,
    String selectedFamily,
    String selectedPosition,
    File? groupProfilePic,
    String type
  ) async {
    groupRepository.updateGroup(
      context,
      groupId,
      name,
      wish,
      selectedQueendom,
      selectedFamily,
      selectedPosition,
      groupProfilePic,
      type
    );
  }

  void createGroup(
    BuildContext context,
    String name,
    String? wish,
    String selectedQueendom,
    String selectedFamily,
    String selectedPosition,
    File groupProfilePic,
    List<ChatContact> selectedContact,
    String type
  ) {
    groupRepository.createGroup(
      context,
      name,
      wish,
      selectedQueendom,
      selectedFamily,
      selectedPosition,
      groupProfilePic,
      selectedContact,
      type
    );
  }

  List<GroupModel> getCachedGroups(String category) {
    return groupRepository.getCachedGroups(category);
  }

  Stream<List<GroupModel>> chatGroups() {
    return groupRepository.getChatGroups();
  }

  Stream<List<GroupModel>> getQueenPoojaStream() {
    return groupRepository.getQueenPoojaStream();
  }

  Stream<List<GroupModel>> getQueenRashmikaStream() {
    return groupRepository.getQueenRashmikaStream();
  }

  Stream<List<GroupModel>> getAllUserGroups() {
    return groupRepository.getAllUserGroups();
  }

  Stream<List<GroupChatMessageModel>> getGroupChat(String groupId) {
    return groupRepository.getGroupChatStream(groupId);
  }

  Stream<Map<String, String>> getGroupTypingStatus(String groupId) {
    return groupRepository.getGroupTypingStatus(groupId);
  }

  void setGroupTypingStatus(String groupId, bool isTyping) {
    groupRepository.setGroupTypingStatus(groupId, isTyping);
  }

  Future<void> updateChatBackground(
    String groupId,
    String backgroundImageUrl,
  ) async {
    try {
      groupRepository.updateChatBackground(groupId, backgroundImageUrl);
    } catch (e) {
      log("error on setChatBackground: $e");
    }
  }

  Future<void> sendTextMessage(
    BuildContext context,
    String text,
    String groupId,
    String messageType,
    dynamic file,
    List<String> fcmToken,
    List<String> receiverIds,
    String groupName,
    String type, {
    MessageReply? messageReplyOverride,
    bool clearReply = false,
  }) async {
    try {
      final messageReply = clearReply
          ? null
          : (messageReplyOverride ?? ref.read(messageReplyProvider));

      UserModel? userDataAsync = await ref.read(userDataAuthProvider.future);
      if (userDataAsync == null && Hive.isBoxOpen('userBox')) {
        userDataAsync = Hive.box<UserModel>('userBox').get('currentUser');
      }
      if (userDataAsync == null) {
        final authUser = FirebaseAuth.instance.currentUser;
        if (authUser != null) {
          userDataAsync = UserModel(
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

      if (userDataAsync == null) {
        log("User data is null in group_controller");
        return;
      }

      await groupRepository.sendTextMessage(
        messageReply: messageReply,
        messageType: messageType,
        file: file,
        context: context,
        text: text,
        groupId: groupId,
        senderUser: userDataAsync,
        fcmToken: fcmToken,
        receiverIds: receiverIds,
        groupName: groupName,
        type: type,
      );

      // ✅ Use .notifier.state instead of deprecated .state provider
      ref.read(messageReplyProvider.notifier).state = null;
    } catch (e) {
      log("error in send text message group_controller: $e");
    }
  }

  // ✅ Now async and properly awaited
  Future<void> setChatMessageSeen(
    BuildContext context,
    String groupId,
    String messageId,
  ) async {
    try {
      await groupRepository.setChatMessageSeen(context, groupId, messageId);
    } catch (e) {
      log("error on setChatMessageSeen: $e");
    }
  }

  void markGroupAsSeen(String groupId) {
    try {
      groupRepository.markGroupAsSeen(groupId);
    } catch (e) {
      log("error on markGroupAsSeen: $e");
    }
  }

  Future<List<GroupChatMessageModel>> getSharedGroupMedia(
    String groupId,
  ) async {
    try {
      return await groupRepository.getSharedGroupMedia(groupId);
    } catch (e) {
      log('error on getSharedGroupMedia: $e');
      return [];
    }
  }

  Future<List<GroupChatMessageModel>> getSharedGroupLinks(
    String groupId,
  ) async {
    try {
      return await groupRepository.getSharedGroupLinks(groupId);
    } catch (e) {
      log('error on getSharedGroupLinks: $e');
      return [];
    }
  }

  void toggleGroupReaction({
    required String groupId,
    required String messageId,
    required String emoji,
  }) {
    groupRepository.toggleGroupReaction(
      groupId: groupId,
      messageId: messageId,
      emoji: emoji,
    );
  }
}
