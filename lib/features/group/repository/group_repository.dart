import 'dart:developer';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:worship_chat/common/providers/message_reply_provider.dart';
import 'package:worship_chat/common/utils/fcm_token_manager.dart';
import 'package:worship_chat/common/utils/file_messages.dart';
import 'package:worship_chat/common/utils/firebase_notification_service.dart';
import 'package:worship_chat/common/utils/media_cache_service.dart';
import 'package:worship_chat/common/utils/utils.dart';
import 'package:worship_chat/models/chat_contact.dart';
import 'package:worship_chat/models/group.dart' as model;
import 'package:worship_chat/models/group.dart';
import 'package:worship_chat/models/group_chat_message_model.dart';
import 'package:worship_chat/models/user_model.dart';

final groupRepositoryProvider = Provider(
  (ref) => GroupRepository(
    firestore: FirebaseFirestore.instance,
    auth: FirebaseAuth.instance,
    ref: ref,
  ),
);

class GroupRepository {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final ProviderRef ref;

  GroupRepository({
    required this.firestore,
    required this.auth,
    required this.ref,
  });

  void updateGroup(
    BuildContext context,
    String groupId,
    String name,
    String? wish,
    String selectedQueendom,
    String selectedFamily,
    String selectedPosition,
    File? groupProfilePic,
    String type,
  ) async {
    try {
      Map<String, dynamic> updateData = {
        'name': name,
        'wish': wish,
        'queendom': selectedQueendom,
        'family': selectedFamily,
        'position': selectedPosition,
      };

      if (groupProfilePic != null) {
        final groupProfileUrl = await uploadImageToCloudinary(
          groupProfilePic,
          type,
        );
        if (groupProfileUrl != null) {
          updateData['groupPic'] = groupProfileUrl;
        }
      }

      await firestore.collection('groups').doc(groupId).update(updateData);
      log('✅ Group updated successfully');
    } catch (e) {
      log('❌ Error updating group: $e');
      showSnackBar(context: context, content: e.toString());
    }
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
    String type,
  ) async {
    try {
      List<String> uids = [];
      List<String> fcmTokens = [];

      log('🔍 Creating group with ${selectedContact.length} contacts');

      final userFutures = selectedContact.map((contact) async {
        try {
          final userCollection = await firestore
              .collection('users')
              .where("uid", isEqualTo: contact.uid)
              .get();

          if (userCollection.docs.isNotEmpty && userCollection.docs[0].exists) {
            final userData = userCollection.docs[0].data();
            final uid = userData['uid'];
            final fcmToken = userData['fcmToken'];

            if (fcmToken != null && fcmToken.isNotEmpty) {
              return {'uid': uid, 'fcmToken': fcmToken};
            } else {
              return {'uid': uid, 'fcmToken': null};
            }
          }
        } catch (e) {
          log('❌ Error fetching user ${contact.uid}: $e');
        }
        return null;
      }).toList();

      final results = await Future.wait(userFutures);

      for (var result in results) {
        if (result != null) {
          uids.add(result['uid']);
          if (result['fcmToken'] != null) {
            fcmTokens.add(result['fcmToken']);
          }
        }
      }

      var groupId = const Uuid().v1();
      final groupProfileUrl = await uploadImageToCloudinary(
        groupProfilePic,
        type,
      );
      String currentUserFcmToken =
          await FirebaseMessaging.instance.getToken() ?? "";

      Map<String, bool> unseenMessages = {};
      for (var uid in [auth.currentUser!.uid, ...uids]) {
        unseenMessages[uid] = false;
      }

      final allFcmTokens = [
        if (currentUserFcmToken.isNotEmpty) currentUserFcmToken,
        ...fcmTokens,
      ];

      model.GroupModel group = model.GroupModel(
        senderId: auth.currentUser!.uid,
        name: name,
        groupId: groupId,
        lastMessage: '',
        groupPic: groupProfileUrl ?? '',
        membersUid: [auth.currentUser!.uid, ...uids],
        timeSent: DateTime.now(),
        fcmTokens: allFcmTokens,
        unseenMessages: unseenMessages,
        queendom: selectedQueendom,
        family: selectedFamily,
        position: selectedPosition,
        wish: wish,
      );

      await firestore.collection('groups').doc(groupId).set(group.toMap());
      log('✅ Group created successfully');
    } catch (e) {
      log('❌ Error creating group: $e');
      showSnackBar(context: context, content: e.toString());
    }
  }

  Stream<Map<String, String>> getGroupTypingStatus(String groupId) {
    return firestore
        .collection('groups')
        .doc(groupId)
        .collection('typing')
        .snapshots()
        .asyncMap((snapshot) async {
          Map<String, String> typingUsers = {};
          final currentUserId = auth.currentUser?.uid;

          for (var doc in snapshot.docs) {
            if (doc.exists && doc.data().isNotEmpty) {
              final data = doc.data();
              final userId = doc.id;
              final isTyping = data['isTyping'] ?? false;
              final timestamp = (data['timestamp'] as Timestamp?)?.toDate();
              final userName = data['userName'] ?? '';

              if (userId == currentUserId) continue;

              if (timestamp != null && isTyping && userName.isNotEmpty) {
                final difference = DateTime.now().difference(timestamp);
                if (difference.inSeconds < 5) {
                  typingUsers[userId] = userName;
                }
              }
            }
          }

          return typingUsers;
        });
  }

  void setGroupTypingStatus(String groupId, bool isTyping) async {
    try {
      final currentUserId = auth.currentUser?.uid;
      if (currentUserId == null) return;

      final userDoc = await firestore
          .collection('users')
          .doc(currentUserId)
          .get();
      final userName = userDoc.data()?['name'] ?? 'Unknown';

      await firestore
          .collection('groups')
          .doc(groupId)
          .collection('typing')
          .doc(currentUserId)
          .set({
            'isTyping': isTyping,
            'userName': isTyping ? userName : '',
            'timestamp': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    } catch (e) {
      log('Error updating group typing status: $e');
    }
  }

  void updateChatBackground(String groupId, String backgroundUrl) async {
    try {
      await firestore.collection('groups').doc(groupId).update({
        'chatBackgroundUrl': backgroundUrl,
      });
    } catch (e) {
      log('Error updating chat background: $e');
    }
  }

  Future<void> saveUserFcmToken(String userId) async {
    try {
      final fcmToken = await FirebaseMessaging.instance.getToken();
      if (fcmToken != null && fcmToken.isNotEmpty) {
        await FirebaseFirestore.instance.collection('users').doc(userId).update(
          {'fcmToken': fcmToken},
        );
      }
    } catch (e) {
      log('❌ Error saving FCM token: $e');
    }
  }

  Stream<List<GroupChatMessageModel>> getGroupChatStream(
      String groupId) async* {
    // 1. Immediately emit cached messages from Hive (0ms)
    try {
      if (Hive.isBoxOpen('messages')) {
        final box = Hive.box('messages');
        final cachedData = box.get(groupId, defaultValue: []);
        if (cachedData is List && cachedData.isNotEmpty) {
          final cachedMessages = cachedData.cast<GroupChatMessageModel>();
          log('⚡ [Instant Cache] Emitted ${cachedMessages.length} cached group messages for $groupId');
          yield cachedMessages;
        }
      }
    } catch (e) {
      log('❌ Error emitting cached group messages: $e');
    }

    // 2. Stream updates from Firestore and keep Hive in sync
    yield* firestore
        .collection('groups')
        .doc(groupId)
        .collection('chats')
        .orderBy('timeSent')
        .snapshots()
        .asyncMap((event) async {
          try {
            return await _processGroupMessages(event, groupId);
          } catch (e) {
            log('❌ Error processing group messages: $e');
            return <GroupChatMessageModel>[];
          }
        })
        .distinct((prev, next) {
          if (prev.length != next.length) return false;
          for (int i = 0; i < prev.length; i++) {
            if (prev[i].messageId != next[i].messageId ||
                prev[i].isSeen != next[i].isSeen ||
                prev[i].isDelivered != next[i].isDelivered ||
                prev[i].isSending != next[i].isSending ||
                prev[i].text != next[i].text) {
              return false;
            }
          }
          return true;
        });
  }

  Future<List<GroupChatMessageModel>> _processGroupMessages(
    QuerySnapshot<Map<String, dynamic>> snapshot,
    String groupId,
  ) async {
    final localKey = groupId;

    // Parse Firestore messages — source of truth
    List<GroupChatMessageModel> firestoreMessages = snapshot.docs.map((doc) {
      final data = doc.data();
      data['isSeen'] = data['isSeen'] ?? false;
      return GroupChatMessageModel.fromMap(data);
    }).toList();

    log('🔥 Loaded ${firestoreMessages.length} messages from Firestore');

    // Open Hive
    Box? box;
    try {
      box = Hive.isBoxOpen('messages')
          ? Hive.box('messages')
          : await Hive.openBox('messages');
    } catch (e) {
      log('❌ Error opening Hive box: $e');
    }

    // Build map starting from Firestore (wins on conflict)
    final Map<String, GroupChatMessageModel> allMessagesMap = {};

    // ✅ FIX: Load ALL cached messages first (not just seen ones)
    // Previously only seen cached messages were kept, causing unseen
    // sent messages to vanish if they hadn't been seen yet
    if (box != null) {
      try {
        final cachedData = box.get(localKey, defaultValue: []);
        if (cachedData is List) {
          final localMessages = cachedData.cast<GroupChatMessageModel>();
          for (var m in localMessages) {
            allMessagesMap[m.messageId] = m;
          }
          log('📦 Loaded ${localMessages.length} messages from cache');
        }
      } catch (e) {
        log('❌ Error loading from Hive: $e');
      }
    }

    // Firestore overwrites cache (newer data wins)
    for (var m in firestoreMessages) {
      allMessagesMap[m.messageId] = m;
    }

    // Sort by time
    final allMessages = allMessagesMap.values.toList()
      ..sort((a, b) => a.timeSent.compareTo(b.timeSent));

    log('📊 Total unique messages: ${allMessages.length}');

    // ✅ Save merged list to Hive immediately, then batch clean seen/old messages from Firestore
    if (box != null) {
      _saveToHiveAsync(box, localKey, allMessages, groupId, firestoreMessages);
    }

    return allMessages;
  }

  void _saveToHiveAsync(
    Box box,
    String key,
    List<GroupChatMessageModel> messages,
    String groupId,
    List<GroupChatMessageModel> firestoreMessages,
  ) {
    Future.microtask(() async {
      try {
        await box.put(key, messages);
        log('💾 Saved ${messages.length} group messages to Hive');
      } catch (e) {
        log('❌ Error saving to Hive: $e');
      }
    });
  }



  List<GroupModel> getCachedGroups(String category) {
    final currentUser = auth.currentUser;
    if (currentUser == null) return [];
    try {
      if (Hive.isBoxOpen('groups_cache')) {
        final box = Hive.box('groups_cache');
        final cachedRaw =
            box.get('${category}_${currentUser.uid}', defaultValue: []);
        if (cachedRaw is List && cachedRaw.isNotEmpty) {
          return cachedRaw
              .map((item) =>
                  GroupModel.fromMap(Map<String, dynamic>.from(item as Map)))
              .toList();
        }
      }
    } catch (e) {
      log('Error reading cached groups: $e');
    }
    return [];
  }

  Stream<List<GroupModel>> getQueenPoojaStream() async* {
    final currentUser = auth.currentUser;
    if (currentUser == null) return;

    // 1. Immediately emit cached Pooja groups from Hive (0ms)
    final cached = getCachedGroups('groups_pooja');
    if (cached.isNotEmpty) {
      log('⚡ [Instant Cache] Emitted ${cached.length} Queen Pooja groups from Hive');
      yield cached;
    }

    // 2. Stream from Firestore and update Hive
    yield* firestore
        .collection('groups')
        .where('queendom', isEqualTo: 'Queen Pooja')
        .orderBy('order')
        .snapshots()
        .map((event) {
          List<GroupModel> groups = [];
          for (var document in event.docs) {
            try {
              var group = GroupModel.fromMap(document.data());
              if (group.membersUid.contains(currentUser.uid)) {
                groups.add(group);
              }
            } catch (e) {
              log("Error parsing group: $e");
            }
          }

          try {
            if (Hive.isBoxOpen('groups_cache')) {
              Hive.box('groups_cache').put(
                'groups_pooja_${currentUser.uid}',
                groups.map((g) => g.toMap()).toList(),
              );
            }
          } catch (e) {
            log('Error saving Pooja groups to Hive: $e');
          }

          return groups;
        });
  }

  Stream<List<GroupModel>> getQueenRashmikaStream() async* {
    final currentUser = auth.currentUser;
    if (currentUser == null) return;

    // 1. Immediately emit cached Rashmika groups from Hive (0ms)
    final cached = getCachedGroups('groups_rashmika');
    if (cached.isNotEmpty) {
      log('⚡ [Instant Cache] Emitted ${cached.length} Queen Rashmika groups from Hive');
      yield cached;
    }

    // 2. Stream from Firestore and update Hive
    yield* firestore
        .collection('groups')
        .where('queendom', isEqualTo: 'Queen Rashmika')
        .orderBy('order')
        .snapshots()
        .map((event) {
          List<GroupModel> groups = [];
          for (var document in event.docs) {
            try {
              var group = GroupModel.fromMap(document.data());
              if (group.membersUid.contains(currentUser.uid)) {
                groups.add(group);
              }
            } catch (e) {
              log("Error parsing group: $e");
            }
          }

          try {
            if (Hive.isBoxOpen('groups_cache')) {
              Hive.box('groups_cache').put(
                'groups_rashmika_${currentUser.uid}',
                groups.map((g) => g.toMap()).toList(),
              );
            }
          } catch (e) {
            log('Error saving Rashmika groups to Hive: $e');
          }

          return groups;
        });
  }

  Stream<List<GroupModel>> getChatGroups() async* {
    final currentUser = auth.currentUser;
    if (currentUser == null) return;

    // 1. Immediately emit cached chat groups from Hive (0ms)
    final cached = getCachedGroups('groups_none');
    if (cached.isNotEmpty) {
      log('⚡ [Instant Cache] Emitted ${cached.length} chat groups from Hive');
      yield cached;
    }

    // 2. Stream from Firestore and update Hive
    yield* firestore
        .collection('groups')
        .where('queendom', isEqualTo: 'None')
        .snapshots()
        .map((event) {
          List<GroupModel> groups = [];
          for (var document in event.docs) {
            try {
              var group = GroupModel.fromMap(document.data());
              if (group.membersUid.contains(currentUser.uid)) {
                groups.add(group);
              }
            } catch (e) {
              log("Error parsing group: $e");
            }
          }

          try {
            if (Hive.isBoxOpen('groups_cache')) {
              Hive.box('groups_cache').put(
                'groups_none_${currentUser.uid}',
                groups.map((g) => g.toMap()).toList(),
              );
            }
          } catch (e) {
            log('Error saving chat groups to Hive: $e');
          }

          return groups;
        });
  }

  Future<void> setChatMessageSeen(
    BuildContext context,
    String groupId,
    String messageId,
  ) async {
    try {
      final currentUserId = auth.currentUser?.uid;
      if (currentUserId == null) return;

      log('👁️ Marking group message as seen: $messageId');

      // ✅ Check if message still exists in Firestore before updating
      final messageDoc = await firestore
          .collection('groups')
          .doc(groupId)
          .collection('chats')
          .doc(messageId)
          .get();

      if (messageDoc.exists) {
        await firestore
            .collection('groups')
            .doc(groupId)
            .collection('chats')
            .doc(messageId)
            .update({'isSeen': true, 'isDelivered': true});

        log('✅ Marked message $messageId as seen in Firestore');

        // ✅ Update Hive cache immediately so UI reflects change
        await _updateSeenInHive(groupId, messageId);
      } else {
        log('⚠️ Message $messageId not in Firestore — updating Hive only');
        await _updateSeenInHive(groupId, messageId);
      }

      // ✅ Always clear unseen count for current user
      await firestore.collection('groups').doc(groupId).update({
        'unseenMessages.$currentUserId': false,
      });

      log('✅ Cleared unseen count for user $currentUserId');
    } catch (e) {
      log('❌ Error in setChatMessageSeen: $e');
    }
  }

  /// Mark all unread group messages as seen and clear the group badge for current user
  Future<void> markGroupAsSeen(String groupId) async {
    final currentUserId = auth.currentUser?.uid;
    if (currentUserId == null || groupId.isEmpty) return;

    // 1. Immediately clear unseen badge on the group document for current user
    try {
      await firestore.collection('groups').doc(groupId).update({
        'unseenMessages.$currentUserId': false,
      });
      log('✅ Cleared unseen badge on group $groupId for user $currentUserId');
    } catch (e) {
      log('Note: could not update group unseenMessages: $e');
    }

    // 2. Find any unseen messages not sent by current user and mark them as seen
    try {
      final unreadDocs = await firestore
          .collection('groups')
          .doc(groupId)
          .collection('chats')
          .where('isSeen', isEqualTo: false)
          .get();

      final toUpdate = unreadDocs.docs.where((doc) {
        final data = doc.data();
        return data['senderId'] != currentUserId;
      }).toList();

      if (toUpdate.isNotEmpty) {
        log('👁️ Found ${toUpdate.length} unread group messages to mark seen');
        final batch = firestore.batch();
        for (var doc in toUpdate) {
          batch.update(doc.reference, {'isSeen': true, 'isDelivered': true});
        }
        await batch.commit();
        log('✅ Batch marked ${toUpdate.length} group messages as seen in Firestore');
      }
    } catch (e) {
      log('❌ Error batch marking group messages seen in Firestore: $e');
    }

    // 3. Update Hive cache
    await _markGroupSeenInHive(groupId, currentUserId);
  }

  Future<void> _markGroupSeenInHive(String groupId, String currentUserId) async {
    try {
      final box = Hive.isBoxOpen('messages')
          ? Hive.box('messages')
          : await Hive.openBox('messages');

      final cachedData = box.get(groupId, defaultValue: []);
      if (cachedData is List) {
        final messages = cachedData.cast<GroupChatMessageModel>();
        bool changed = false;
        final updated = messages.map((m) {
          if (m.senderId != currentUserId && (!m.isSeen || !m.isDelivered)) {
            changed = true;
            return m.copyWith(isSeen: true, isDelivered: true);
          }
          return m;
        }).toList();

        if (changed) {
          await box.put(groupId, updated);
          log('✅ Hive cache updated: all messages marked seen for group $groupId');
        }
      }
    } catch (e) {
      log('❌ Error updating Hive cache for seen group: $e');
    }
  }

  // ✅ Awaitable Hive update (was fire-and-forget before)
  Future<void> _updateSeenInHive(String groupId, String messageId) async {
    try {
      final box = Hive.isBoxOpen('messages')
          ? Hive.box('messages')
          : await Hive.openBox('messages');

      final cachedData = box.get(groupId, defaultValue: []);
      if (cachedData is List) {
        final messages = cachedData.cast<GroupChatMessageModel>();
        final updated = messages.map((m) {
          return m.messageId == messageId ? m.copyWith(isSeen: true, isDelivered: true) : m;
        }).toList();
        await box.put(groupId, updated);
        log('💾 Updated message $messageId as seen in Hive');
      }
    } catch (e) {
      log('❌ Error updating Hive: $e');
    }
  }

  void _saveMessageToMessageSubcollection({
    required List<String> receiverIds,
    required String groupId,
    required String text,
    required DateTime timeSent,
    required String messageId,
    required String username,
    required String name,
    required String messageType,
    String? fileMessageData,
    required MessageReply? messageReply,
    required String senderUsername,
    required String? receiverUserName,
    required String messageReplyType,
    required List<String> fcmToken,
    required String groupName,
  }) async {
    final message = GroupChatMessageModel(
      senderId: auth.currentUser!.uid,
      groupId: groupId,
      receiverIds: receiverIds,
      text: text,
      messageType: messageType,
      timeSent: timeSent,
      messageId: messageId,
      isSeen: false,
      fileMessageData: fileMessageData,
      repliedMessage: messageReply == null
          ? ''
          : messageReply.messageType == 'text'
          ? messageReply.message
          : messageReply.fileMessageData,
      repliedTo: messageReply == null
          ? ''
          : messageReply.isMe
          ? senderUsername
          : receiverUserName ?? '',
      repliedMessageType: messageReplyType,
    );

    try {
      await firestore
          .collection('groups')
          .doc(groupId)
          .collection('chats')
          .doc(messageId)
          .set(message.toMap());

      _sendGroupNotificationAsync(
        fcmToken: fcmToken,
        name: name,
        groupName: groupName,
        groupId: groupId,
        messageType: messageType,
        text: text,
        messageReply: messageReply,
      );
    } catch (e) {
      log('❌ Error saving message: $e');
    }
  }

  void _sendGroupNotificationAsync({
    required List<String> fcmToken,
    required String name,
    required String groupName,
    required String groupId,
    required String messageType,
    required String text,
    required MessageReply? messageReply,
  }) {
    Future.microtask(() async {
      try {
        log('📢 _sendGroupNotificationAsync called with ${fcmToken.length} candidate tokens for group "$groupName" ($groupId)');
        final currentUserToken = await FirebaseMessaging.instance.getToken();

        List<String> validTokens = fcmToken
            .where((token) => token.isNotEmpty && token != currentUserToken)
            .toSet()
            .toList();

        // If candidate tokens empty, attempt emergency fallback from group document in Firestore
        if (validTokens.isEmpty) {
          log('⚠️ Candidate tokens empty/filtered, checking group document in Firestore as emergency fallback...');
          try {
            final groupDoc =
                await firestore.collection('groups').doc(groupId).get();
            if (groupDoc.exists && groupDoc.data() != null) {
              final storedTokens =
                  List<String>.from(groupDoc.data()!['fcmTokens'] ?? []);
              validTokens = storedTokens
                  .where((t) => t.isNotEmpty && t != currentUserToken)
                  .toSet()
                  .toList();
              log('🔄 Fallback found ${validTokens.length} stored tokens from group doc');
            }
          } catch (e) {
            log('❌ Fallback failed: $e');
          }
        }

        if (validTokens.isEmpty) {
          log('⚠️ No recipient tokens found for group $groupId. Skipping notification.');
          return;
        }

        log('🚀 Sending group notification to ${validTokens.length} recipients for group: "$groupName"');

        String body;
        if (messageReply != null) {
          switch (messageReply.messageType) {
            case 'text':
              body = 'Replying to: "${messageReply.message}"';
              break;
            case 'image':
              body = '📷 Replying to an image';
              break;
            case 'video':
              body = '🎥 Replying to a video';
              break;
            case 'gif':
              body = '🎞️ Replying to a GIF';
              break;
            default:
              body = '↩️ Replying to a message';
          }
        } else {
          switch (messageType) {
            case 'text':
              body = text;
              break;
            case 'image':
              body = '📷 Photo';
              break;
            case 'video':
              body = '🎥 Video';
              break;
            case 'gif':
              body = '🎞️ GIF';
              break;
            default:
              body = '📎 Media message';
          }
        }

        await sendMultipleNotification(
          validTokens,
          groupName,
          "$name: $body",
          data: {
            'type': 'group',
            'groupId': groupId,
            'groupName': groupName,
            'tag': groupId,
          },
        );
      } catch (e) {
        log("❌ Error in _sendGroupNotificationAsync: $e");
      }
    });
  }

  void _saveDataToContactsSubCollection(
    UserModel senderUserData,
    String text,
    DateTime timeSent,
    String groupId,
    String messageType,
    List<String> token,
  ) async {
    try {
      String lastMessage;
      switch (messageType) {
        case "image":
          lastMessage = "📷 Photo";
          break;
        case "video":
          lastMessage = "📽️ Video";
          break;
        case "gif":
          lastMessage = "🎮 Gif";
          break;
        default:
          lastMessage = text;
      }

      final currentUserId = auth.currentUser?.uid;
      if (currentUserId == null) return;

      final groupDoc = await firestore.collection('groups').doc(groupId).get();
      if (!groupDoc.exists) return;

      final groupData = groupDoc.data()!;
      final membersUid = List<String>.from(groupData['membersUid'] ?? []);

      final tokenFutures = membersUid.map((uid) async {
        try {
          final userDoc = await firestore.collection('users').doc(uid).get();
          if (userDoc.exists) {
            final token = userDoc.data()?['fcmToken'];
            if (token != null && token.isNotEmpty) return token as String;
          }
        } catch (e) {
          log('❌ Error fetching token for user $uid: $e');
        }
        return null;
      }).toList();

      final tokenResults = await Future.wait(tokenFutures);
      final freshFcmTokens = tokenResults
          .where((token) => token != null)
          .cast<String>()
          .toList();

      final currentStoredTokens =
          List<String>.from(groupData['fcmTokens'] ?? []);
      final updatedFcmTokens =
          freshFcmTokens.isNotEmpty ? freshFcmTokens : currentStoredTokens;

      Map<String, bool> unseenMessages = {};
      for (var uid in membersUid) {
        unseenMessages[uid] = (uid != currentUserId);
      }

      await firestore.collection('groups').doc(groupId).update({
        'senderId': currentUserId,
        'lastMessage': lastMessage,
        'timeSent': DateTime.now().millisecondsSinceEpoch,
        'unseenMessages': unseenMessages,
        'fcmTokens': updatedFcmTokens,
      });
    } catch (e) {
      log('❌ Error updating group: $e');
    }
  }

  void sendTextMessage({
    required BuildContext context,
    required String text,
    required List<String> receiverIds,
    required String groupId,
    required UserModel senderUser,
    required String messageType,
    required MessageReply? messageReply,
    required List<String> fcmToken,
    required String groupName,
    required String type,
    dynamic file,
  }) async {
    try {
      String? fileData;
      var timeSent = DateTime.now();
      var messageId = const Uuid().v1();

      final currentUserId = auth.currentUser?.uid ?? senderUser.uid ?? '';
      if (currentUserId.isEmpty) {
        log('❌ Error: currentUserId is empty');
        return;
      }
      final senderName = senderUser.name ?? senderUser.userName ?? 'User';
      final senderUsername = senderUser.userName ?? senderUser.name ?? 'User';

      final optimisticMessage = GroupChatMessageModel(
        senderId: currentUserId,
        receiverIds: receiverIds,
        groupId: groupId,
        text: text,
        messageType: messageType,
        timeSent: timeSent,
        messageId: messageId,
        isSeen: false,
        isDelivered: false,
        isSending: true,
        fileMessageData: file is File ? file.path : (file is String ? file : null),
        repliedMessage: messageReply == null
            ? ''
            : messageReply.messageType == 'text'
            ? messageReply.message
            : messageReply.fileMessageData,
        repliedTo: messageReply == null
            ? ''
            : messageReply.isMe
            ? senderName
            : '',
        repliedMessageType: messageReply == null ? 'text' : messageReply.messageType,
      );
      _saveOptimisticGroupMessageToHive(groupId, optimisticMessage);

      if (messageType == "image" && file != null) {
        fileData = await uploadImageToCloudinary(file, type);
        if (file is File && fileData != null && fileData.isNotEmpty) {
          MediaCacheService().registerLocalMapping(fileData, file.path);
        }
      } else if (messageType == "video" && file != null) {
        fileData = await uploadVideoToCloudinary(file, type);
        if (file is File && fileData != null && fileData.isNotEmpty) {
          MediaCacheService().registerLocalMapping(fileData, file.path);
        }
      } else if (messageType == "url" && file != null) {
        fileData = file;
      }

      List<String> freshFcmTokens = await FCMTokenManager.getGroupMemberTokens(
        groupId,
      );

      // Fall back to passed fcmToken from widget if fresh lookup returned empty
      if (freshFcmTokens.isEmpty && fcmToken.isNotEmpty) {
        log('⚠️ freshFcmTokens was empty in sendTextMessage, using passed fcmToken (${fcmToken.length} tokens)');
        freshFcmTokens = List<String>.from(fcmToken);
      }

      Future.microtask(() {
        _saveDataToContactsSubCollection(
          senderUser,
          text,
          timeSent,
          groupId,
          messageType,
          freshFcmTokens,
        );
      });

      _saveMessageToMessageSubcollection(
        groupId: groupId,
        text: text,
        timeSent: timeSent,
        messageType: messageType,
        messageId: messageId,
        name: senderName,
        username: senderUsername,
        fileMessageData: fileData,
        receiverUserName: "",
        senderUsername: senderName,
        messageReplyType: messageReply == null
            ? "text"
            : messageReply.messageType,
        messageReply: messageReply,
        fcmToken: freshFcmTokens,
        receiverIds: receiverIds,
        groupName: groupName,
      );
    } catch (e) {
      log("❌ Error sending message: $e");
      _removeOptimisticGroupMessageFromHive(groupId);
      showSnackBar(context: context, content: e.toString());
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
        messages = cachedData.cast<GroupChatMessageModel>().toList();
      }
      final existingIndex = messages.indexWhere((m) => m.messageId == message.messageId);
      if (existingIndex >= 0) {
        messages[existingIndex] = message;
      } else {
        messages.add(message);
      }
      await box.put(groupId, messages);
      log('🕒 Saved optimistic sending group message to Hive: ${message.messageId}');
    } catch (e) {
      log('❌ Error saving optimistic group message to Hive: $e');
    }
  }

  void _removeOptimisticGroupMessageFromHive(String groupId) async {
    try {
      if (Hive.isBoxOpen('messages')) {
        final box = Hive.box('messages');
        final cachedData = box.get(groupId, defaultValue: []);
        if (cachedData is List) {
          final messages = cachedData.cast<GroupChatMessageModel>().toList();
          messages.removeWhere((m) => m.isSending);
          await box.put(groupId, messages);
        }
      }
    } catch (_) {}
  }

  Future<List<GroupChatMessageModel>> getSharedGroupMedia(
    String groupId,
  ) async {
    final List<GroupChatMessageModel> allMedia = [];
    final Set<String> seenIds = {};

    // Step 1: Load from Hive (contains all seen/deleted messages)
    try {
      final box = Hive.isBoxOpen('messages')
          ? Hive.box('messages')
          : await Hive.openBox('messages');

      final cachedData = box.get(groupId, defaultValue: []);
      if (cachedData is List) {
        final messages = cachedData.cast<GroupChatMessageModel>();
        for (var m in messages) {
          if (['image', 'video', 'gif'].contains(m.messageType) &&
              m.fileMessageData != null &&
              m.fileMessageData!.isNotEmpty) {
            allMedia.add(m);
            seenIds.add(m.messageId);
          }
        }
      }
      log('📦 Hive group media count: ${allMedia.length}');
    } catch (e) {
      log('❌ Hive group media error: $e');
    }

    // Step 2: Fetch from Firestore (recent unseen messages)
    try {
      final snapshot = await firestore
          .collection('groups')
          .doc(groupId)
          .collection('chats')
          .where('messageType', whereIn: ['image', 'video', 'gif'])
          .orderBy('timeSent', descending: true)
          .get();

      for (var doc in snapshot.docs) {
        final data = doc.data();
        data['isSeen'] = data['isSeen'] ?? false;
        final msg = GroupChatMessageModel.fromMap(data);
        if (!seenIds.contains(msg.messageId) &&
            msg.fileMessageData != null &&
            msg.fileMessageData!.isNotEmpty) {
          allMedia.add(msg);
        }
      }
      log('🔥 Total group media after merge: ${allMedia.length}');
    } catch (e) {
      log('❌ Firestore group media error: $e');
    }

    allMedia.sort((a, b) => b.timeSent.compareTo(a.timeSent));
    return allMedia;
  }

  Future<List<GroupChatMessageModel>> getSharedGroupLinks(
    String groupId,
  ) async {
    final List<GroupChatMessageModel> allLinks = [];
    final Set<String> seenIds = {};

    // Step 1: Load from Hive
    try {
      final box = Hive.isBoxOpen('messages')
          ? Hive.box('messages')
          : await Hive.openBox('messages');

      final cachedData = box.get(groupId, defaultValue: []);
      if (cachedData is List) {
        final messages = cachedData.cast<GroupChatMessageModel>();
        for (var m in messages) {
          if (m.messageType == 'text' && _containsUrl(m.text)) {
            allLinks.add(m);
            seenIds.add(m.messageId);
          }
        }
      }
      log('📦 Hive group links count: ${allLinks.length}');
    } catch (e) {
      log('❌ Hive group links error: $e');
    }

    // Step 2: Fetch from Firestore
    try {
      final snapshot = await firestore
          .collection('groups')
          .doc(groupId)
          .collection('chats')
          .where('messageType', isEqualTo: 'text')
          .orderBy('timeSent', descending: true)
          .get();

      for (var doc in snapshot.docs) {
        final data = doc.data();
        data['isSeen'] = data['isSeen'] ?? false;
        final msg = GroupChatMessageModel.fromMap(data);
        if (!seenIds.contains(msg.messageId) && _containsUrl(msg.text)) {
          allLinks.add(msg);
        }
      }
      log('🔥 Total group links after merge: ${allLinks.length}');
    } catch (e) {
      log('❌ Firestore group links error: $e');
    }

    allLinks.sort((a, b) => b.timeSent.compareTo(a.timeSent));
    return allLinks;
  }

  bool _containsUrl(String text) {
    return RegExp(r'https?://[^\s]+', caseSensitive: false).hasMatch(text);
  }
}
