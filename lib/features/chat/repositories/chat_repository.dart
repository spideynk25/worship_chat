import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/adapters.dart';
import 'package:uuid/uuid.dart';
import 'package:worship_chat/common/providers/message_reply_provider.dart';
import 'package:worship_chat/common/utils/file_messages.dart';
import 'package:worship_chat/common/utils/firebase_notification_service.dart';
import 'package:worship_chat/common/utils/utils.dart';
import 'package:worship_chat/models/chat_contact.dart';
import 'package:worship_chat/models/one_to_one_message_model.dart';
import 'package:worship_chat/models/user_model.dart';

final chatRepositoryProvider = Provider(
  (ref) => ChatRepository(
    fireStore: FirebaseFirestore.instance,
    auth: FirebaseAuth.instance,
  ),
);

final currentUserProvider = FutureProvider<User?>((ref) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user != null) {
    await user.reload();
    return FirebaseAuth.instance.currentUser;
  }
  return null;
});

class ChatRepository {
  final FirebaseFirestore fireStore;
  final FirebaseAuth auth;

  ChatRepository({required this.fireStore, required this.auth});

  final Map<String, Set<String>> _deletionQueue = {};

  Stream<bool> getTypingStatus(String otherUserId) {
    return fireStore
        .collection('users')
        .doc(otherUserId)
        .collection('typing')
        .doc('status')
        .snapshots()
        .map((snapshot) {
          if (snapshot.exists && snapshot.data() != null) {
            final data = snapshot.data()!;
            final isTyping = data['isTyping'] ?? false;
            final timestamp = (data['timestamp'] as Timestamp?)?.toDate();
            final typingTo = data['typingTo'] ?? '';

            if (timestamp != null &&
                isTyping &&
                typingTo == auth.currentUser!.uid) {
              final difference = DateTime.now().difference(timestamp);
              return difference.inSeconds < 5;
            }
            return false;
          }
          return false;
        });
  }

  void setTypingStatus(String receiverUserId, bool isTyping) {
    try {
      final currentUserId = auth.currentUser?.uid;
      if (currentUserId == null) return;

      fireStore
          .collection('users')
          .doc(currentUserId)
          .collection('typing')
          .doc('status')
          .set({
            'isTyping': isTyping,
            'typingTo': isTyping ? receiverUserId : '',
            'timestamp': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      log('Typing status updated: $isTyping to user: $receiverUserId');
    } catch (e) {
      log('Error updating typing status: $e');
    }
  }

  Stream<List<ChatContact>> fetchAllContacts() {
    return fireStore.collection('users').snapshots().asyncMap((event) async {
      log("Snapshot received - Doc count: ${event.docs.length}");

      List<ChatContact> contacts = [];
      for (var document in event.docs) {
        try {
          var chatContact = ChatContact.fromMap(document.data());
          var userData = await fireStore
              .collection('users')
              .doc(chatContact.uid)
              .get();

          if (userData.data() != null) {
            var user = UserModel.fromMap(userData.data()!);
            contacts.add(
              ChatContact(
                name: user.name!,
                profilePic: user.profilePic,
                uid: chatContact.uid,
                timeSent: chatContact.timeSent,
                lastMessage: chatContact.lastMessage,
                fcmToken: chatContact.fcmToken,
                unseenCount: chatContact.unseenCount,
                chatBackgroundUrl: chatContact.chatBackgroundUrl,
              ),
            );
          }
        } catch (e) {
          log("Error processing contact: $e");
          continue;
        }
      }

      final currentUserId = auth.currentUser?.uid;
      return contacts
          .where((chatContact) => chatContact.uid != currentUserId)
          .toList();
    });
  }

  Stream<List<ChatContact>> getChatContact() {
    return fireStore
        .collection('users')
        .doc(auth.currentUser!.uid)
        .collection("chats")
        .snapshots()
        .asyncMap((event) async {
          List<ChatContact> contacts = [];
          for (var document in event.docs) {
            try {
              var chatContact = ChatContact.fromMap(document.data());
              var userData = await fireStore
                  .collection('users')
                  .doc(chatContact.uid)
                  .get();

              if (userData.data() != null) {
                var user = UserModel.fromMap(userData.data()!);
                contacts.add(
                  ChatContact(
                    name: user.name!,
                    profilePic: user.profilePic,
                    uid: chatContact.uid,
                    timeSent: chatContact.timeSent,
                    lastMessage: chatContact.lastMessage,
                    fcmToken: chatContact.fcmToken,
                    unseenCount: chatContact.unseenCount,
                    chatBackgroundUrl: chatContact.chatBackgroundUrl,
                  ),
                );
              }
            } catch (e) {
              log("Error processing contact: $e");
              continue;
            }
          }

          final currentUserId = auth.currentUser?.uid;
          return contacts
              .where((chatContact) => chatContact.uid != currentUserId)
              .toList();
        });
  }

  Stream<List<OneToOneMessageModel>> getChatStream(String receiverUserId) {
    final currentUserId = auth.currentUser?.uid;
    if (currentUserId == null) {
      return Stream.value([]);
    }

    return fireStore
        .collection('users')
        .doc(currentUserId)
        .collection('chats')
        .doc(receiverUserId)
        .collection('messages')
        .orderBy('timeSent')
        .snapshots()
        .asyncMap((event) async {
          try {
            return await _processMessages(event, receiverUserId);
          } catch (e) {
            log('❌ Error processing messages: $e');
            return <OneToOneMessageModel>[];
          }
        })
        .distinct((prev, next) {
          if (prev.length != next.length) return false;
          for (int i = 0; i < prev.length; i++) {
            if (prev[i].messageId != next[i].messageId ||
                prev[i].isSeen != next[i].isSeen ||
                prev[i].text != next[i].text) {
              return false;
            }
          }
          return true;
        });
  }

  Future<List<OneToOneMessageModel>> _processMessages(
    QuerySnapshot<Map<String, dynamic>> snapshot,
    String receiverUserId,
  ) async {
    final localKey = '${auth.currentUser!.uid}_$receiverUserId';

    Box box;
    try {
      if (Hive.isBoxOpen('messages')) {
        box = Hive.box('messages');
      } else {
        box = await Hive.openBox('messages');
      }
    } catch (e) {
      log('❌ Error opening Hive box: $e');
      return _processFirestoreOnly(snapshot);
    }

    // Firestore is source of truth
    List<OneToOneMessageModel> firestoreMessages = snapshot.docs.map((doc) {
      final data = doc.data();
      data['isSeen'] = data['isSeen'] ?? false;
      return OneToOneMessageModel.fromMap(data);
    }).toList();

    log('🔥 Loaded ${firestoreMessages.length} messages from Firestore');

    // Load cached messages
    List<OneToOneMessageModel> cachedMessages = [];
    try {
      final cachedData = box.get(localKey, defaultValue: []);
      if (cachedData is List) {
        cachedMessages = cachedData.cast<OneToOneMessageModel>();
      }
      log('📦 Loaded ${cachedMessages.length} messages from Hive cache');
    } catch (e) {
      log('❌ Error loading from Hive: $e');
    }

    // Merge: Firestore wins on conflict
    final Map<String, OneToOneMessageModel> messagesMap = {};
    for (var m in cachedMessages) {
      messagesMap[m.messageId] = m;
    }
    for (var m in firestoreMessages) {
      messagesMap[m.messageId] = m;
    }

    final allMessages = messagesMap.values.toList()
      ..sort((a, b) => a.timeSent.compareTo(b.timeSent));

    log('📊 Total unique messages: ${allMessages.length}');

    // Save merged list to Hive
    _saveToHiveAsync(box, localKey, allMessages);

    // ✅ REMOVED: _deleteSeenMessagesAsync from stream processing
    // Deletion is now only triggered from setChatMessageSeen
    // to avoid race conditions with the seen status update

    return allMessages;
  }

  List<OneToOneMessageModel> _processFirestoreOnly(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final messages = snapshot.docs.map((doc) {
      final data = doc.data();
      data['isSeen'] = data['isSeen'] ?? false;
      return OneToOneMessageModel.fromMap(data);
    }).toList();

    messages.sort((a, b) => a.timeSent.compareTo(b.timeSent));
    return messages;
  }

  void _saveToHiveAsync(
    Box box,
    String key,
    List<OneToOneMessageModel> messages,
  ) {
    Future.microtask(() async {
      try {
        await box.put(key, messages);
        log('💾 Saved ${messages.length} messages to Hive');
      } catch (e) {
        log('❌ Error saving to Hive: $e');
      }
    });
  }

  // ✅ Now called only from setChatMessageSeen, not from stream
  void _deleteSeenMessagesAsync(
    String receiverUserId,
    List<OneToOneMessageModel> seenMessages,
  ) {
    final currentUserId = auth.currentUser?.uid;
    if (currentUserId == null) return;

    final queueKey = '${currentUserId}_$receiverUserId';
    _deletionQueue[queueKey] ??= {};

    final messagesToDelete = seenMessages
        .where((m) => !_deletionQueue[queueKey]!.contains(m.messageId))
        .toList();

    if (messagesToDelete.isEmpty) return;

    for (var msg in messagesToDelete) {
      _deletionQueue[queueKey]!.add(msg.messageId);
    }

    Future.microtask(() async {
      try {
        final messagesRef = fireStore
            .collection('users')
            .doc(currentUserId)
            .collection('chats')
            .doc(receiverUserId)
            .collection('messages');

        const batchSize = 100;
        int totalDeleted = 0;

        for (int i = 0; i < messagesToDelete.length; i += batchSize) {
          final batch = fireStore.batch();
          final end = (i + batchSize < messagesToDelete.length)
              ? i + batchSize
              : messagesToDelete.length;

          for (int j = i; j < end; j++) {
            batch.delete(messagesRef.doc(messagesToDelete[j].messageId));
          }

          await batch.commit();
          totalDeleted += (end - i);
          log('🗑️ Deleted batch: $totalDeleted/${messagesToDelete.length}');

          if (i + batchSize < messagesToDelete.length) {
            await Future.delayed(const Duration(milliseconds: 100));
          }
        }

        log('✅ Deleted $totalDeleted seen messages from Firestore');

        Future.delayed(const Duration(seconds: 5), () {
          for (var msg in messagesToDelete) {
            _deletionQueue[queueKey]?.remove(msg.messageId);
          }
        });
      } catch (e) {
        log('❌ Error deleting from Firestore: $e');
        for (var msg in messagesToDelete) {
          _deletionQueue[queueKey]?.remove(msg.messageId);
        }
      }
    });
  }

  void updateChatBackground(String receiverUserId, String backgroundUrl) async {
    final currentUserId = auth.currentUser?.uid;
    if (currentUserId == null) return;

    try {
      await fireStore
          .collection('users')
          .doc(currentUserId)
          .collection('chats')
          .doc(receiverUserId)
          .update({'chatBackgroundUrl': backgroundUrl});

      await fireStore
          .collection('users')
          .doc(receiverUserId)
          .collection('chats')
          .doc(currentUserId)
          .update({'chatBackgroundUrl': backgroundUrl});
    } catch (e) {
      log('Error updating chat background: $e');
    }
  }

  void _saveDataToContactsSubCollection(
    UserModel senderUserData,
    UserModel? receiverUserData,
    String text,
    DateTime timeSent,
    String receiverUserId,
    String messageType,
    String fcmToken,
    bool? unseenCount,
    String? chatBackgroundUrl,
  ) async {
    log("_saveDataToContactsSubCollection $fcmToken");

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

    try {
      var receiverChatContact = ChatContact(
        name: senderUserData.name!,
        profilePic: senderUserData.profilePic,
        uid: senderUserData.uid!,
        timeSent: timeSent,
        lastMessage: lastMessage,
        fcmToken: await FirebaseMessaging.instance.getToken() ?? '',
        unseenCount: true,
        chatBackgroundUrl: chatBackgroundUrl ?? "",
      );

      await fireStore
          .collection('users')
          .doc(receiverUserId)
          .collection('chats')
          .doc(currentUserId)
          .set(receiverChatContact.toMap());

      var senderChatContact = ChatContact(
        name: receiverUserData!.name!,
        profilePic: receiverUserData.profilePic,
        uid: receiverUserData.uid!,
        timeSent: timeSent,
        lastMessage: lastMessage,
        fcmToken: fcmToken,
        unseenCount: false,
        chatBackgroundUrl: chatBackgroundUrl ?? "",
      );

      await fireStore
          .collection('users')
          .doc(currentUserId)
          .collection('chats')
          .doc(receiverUserId)
          .set(senderChatContact.toMap());
    } catch (e) {
      log('Error saving to contacts: $e');
    }
  }

  void _saveMessageToMessageSubcollection({
    required String receiverUserId,
    required String text,
    required DateTime timeSent,
    required String messageId,
    required String username,
    required String name,
    required receiverUsername,
    required receiverName,
    required String messageType,
    String? fileMessageData,
    required MessageReply? messageReply,
    required String senderUsername,
    required String? receiverUserName,
    required String messageReplyType,
    required String fcmToken,
    required String senderUid,
    required String senderProfilePic,
  }) async {
    log(
      "_saveMessageToMessageSubcollection - Type: $messageType, HasFile: ${fileMessageData != null}",
    );

    final currentUserId = auth.currentUser?.uid;
    if (currentUserId == null) return;

    final message = OneToOneMessageModel(
      senderId: currentUserId,
      receiverId: receiverUserId,
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
      final batch = fireStore.batch();

      final receiverMessageRef = fireStore
          .collection('users')
          .doc(receiverUserId)
          .collection('chats')
          .doc(currentUserId)
          .collection('messages')
          .doc(messageId);

      final senderMessageRef = fireStore
          .collection('users')
          .doc(currentUserId)
          .collection('chats')
          .doc(receiverUserId)
          .collection('messages')
          .doc(messageId);

      batch.set(receiverMessageRef, message.toMap());
      batch.set(senderMessageRef, message.toMap());

      await batch.commit();
      log('✅ Message saved atomically to both users');

      if (fcmToken.isNotEmpty) {
        _sendNotificationAsync(
          fcmToken: fcmToken,
          name: name,
          messageType: messageType,
          text: text,
          messageReply: messageReply,
          senderUid: senderUid,
          senderProfilePic: senderProfilePic,
        );
      }
    } catch (e) {
      log('❌ Error saving message: $e');
      rethrow;
    }
  }

  void _sendNotificationAsync({
    required String fcmToken,
    required String name,
    required String messageType,
    required String text,
    required MessageReply? messageReply,
    required String senderUid,
    required String senderProfilePic,
  }) {
    Future.microtask(() async {
      try {
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

        await sendNotification(
          fcmToken,
          name,
          body,
          data: {
            'type': 'chat',
            'senderUid': senderUid,
            'name': name,
            'profilePic': senderProfilePic,
          },
        );
        log('✅ Notification sent successfully');
      } catch (e) {
        log('❌ Error sending notification: $e');
      }
    });
  }

  Future<void> sendTextMessage({
    required BuildContext context,
    required String text,
    required String receiverUserId,
    required UserModel senderUser,
    required String messageType,
    required MessageReply? messageReply,
    required bool? unseenCount,
    required String fcmToken,
    required String? chatBackgroundUrl,
    dynamic file,
    required String type,
  }) async {
    try {
      log("token sendTextMessage: $fcmToken");

      var messageId = const Uuid().v1();
      var timeSent = DateTime.now();

      String? fileData;

      if (messageType == "image" && file != null) {
        log("📤 Uploading image for message: $messageId");
        fileData = await uploadImageToCloudinary(file, type);
        log("✅ Image uploaded: $fileData");
      } else if (messageType == "video" && file != null) {
        log("📤 Uploading video for message: $messageId");
        fileData = await uploadVideoToCloudinary(file, type);
        log("✅ Video uploaded: $fileData");
      } else if (messageType == "gif" && file != null) {
        fileData = file;
      }

      var userDataMap = await fireStore
          .collection('users')
          .doc(receiverUserId)
          .get();

      if (!userDataMap.exists || userDataMap.data() == null) {
        throw Exception('Receiver user not found');
      }

      UserModel? receiverUserData = UserModel.fromMap(userDataMap.data()!);

      await Future.wait([
        Future.microtask(
          () => _saveDataToContactsSubCollection(
            senderUser,
            receiverUserData,
            text,
            timeSent,
            receiverUserId,
            messageType,
            fcmToken,
            unseenCount,
            chatBackgroundUrl,
          ),
        ),
        Future.microtask(
          () => _saveMessageToMessageSubcollection(
            receiverUserId: receiverUserId,
            text: text,
            timeSent: timeSent,
            messageType: messageType,
            messageId: messageId,
            receiverUsername: receiverUserData.userName,
            receiverName: receiverUserData.name,
            name: senderUser.name!,
            username: senderUser.userName!,
            fileMessageData: fileData,
            receiverUserName: receiverUserData.name,
            senderUsername: senderUser.name!,
            messageReplyType: messageReply == null
                ? "text"
                : messageReply.messageType,
            messageReply: messageReply,
            fcmToken: fcmToken,
            senderUid: senderUser.uid ?? '',
            senderProfilePic: senderUser.profilePic ?? '',
          ),
        ),
      ]);

      log('✅ Message saved with ID: $messageId');
    } catch (e) {
      log('❌ Error sending message: $e');
      showSnackBar(context: context, content: e.toString());
      rethrow;
    }
  }

  Future<void> setChatMessageSeen(
    BuildContext context,
    String receiverUserId,
    String messageId,
  ) async {
    try {
      final currentUserId = auth.currentUser?.uid;
      if (currentUserId == null) return;

      log('👁️ Marking message as seen: $messageId');

      // ✅ Update isSeen in both users' Firestore collections atomically
      await Future.wait([
        fireStore
            .collection('users')
            .doc(receiverUserId)
            .collection('chats')
            .doc(currentUserId)
            .collection('messages')
            .doc(messageId)
            .update({'isSeen': true}),
        fireStore
            .collection('users')
            .doc(currentUserId)
            .collection('chats')
            .doc(receiverUserId)
            .collection('messages')
            .doc(messageId)
            .update({'isSeen': true}),
      ]);

      // ✅ Update Hive cache immediately so UI reflects change
      // without waiting for the next Firestore snapshot
      await _updateSeenInHive(currentUserId, receiverUserId, messageId);

      // ✅ Update unseen count
      await fireStore
          .collection('users')
          .doc(currentUserId)
          .collection('chats')
          .doc(receiverUserId)
          .update({'unseenCount': false});

      log('✅ Message marked as seen');

      // ✅ Now safe to delete from Firestore since isSeen is committed
      _scheduleSeenMessageDeletion(currentUserId, receiverUserId, messageId);
    } catch (e) {
      log('❌ Error in setChatMessageSeen: $e');
    }
  }

  // ✅ NEW: Update a single message's isSeen in Hive immediately
  Future<void> _updateSeenInHive(
    String currentUserId,
    String receiverUserId,
    String messageId,
  ) async {
    final localKey = '${currentUserId}_$receiverUserId';
    try {
      final box = Hive.isBoxOpen('messages')
          ? Hive.box('messages')
          : await Hive.openBox('messages');

      final cachedData = box.get(localKey, defaultValue: []);
      if (cachedData is List) {
        final messages = cachedData.cast<OneToOneMessageModel>();
        final updated = messages.map((m) {
          return m.messageId == messageId ? m.copyWith(isSeen: true) : m;
        }).toList();
        await box.put(localKey, updated);
        log('✅ Hive cache updated: message $messageId marked seen');
      }
    } catch (e) {
      log('❌ Error updating Hive for seen message: $e');
    }
  }

  // ✅ NEW: Delete a single seen message from Firestore after seen is confirmed
  void _scheduleSeenMessageDeletion(
    String currentUserId,
    String receiverUserId,
    String messageId,
  ) {
    final queueKey = '${currentUserId}_$receiverUserId';
    _deletionQueue[queueKey] ??= {};

    if (_deletionQueue[queueKey]!.contains(messageId)) return;
    _deletionQueue[queueKey]!.add(messageId);

    Future.delayed(const Duration(seconds: 2), () async {
      try {
        final batch = fireStore.batch();

        // Delete from current user's collection
        batch.delete(
          fireStore
              .collection('users')
              .doc(currentUserId)
              .collection('chats')
              .doc(receiverUserId)
              .collection('messages')
              .doc(messageId),
        );

        await batch.commit();
        log('🗑️ Deleted seen message $messageId from Firestore');

        // Clean up queue after delay
        Future.delayed(const Duration(seconds: 5), () {
          _deletionQueue[queueKey]?.remove(messageId);
        });
      } catch (e) {
        log('❌ Error deleting seen message: $e');
        _deletionQueue[queueKey]?.remove(messageId);
      }
    });
  }

  // ── Add these two methods to ChatRepository ──────────────────────────────────

  Future<List<OneToOneMessageModel>> getSharedMedia(
    String receiverUserId,
  ) async {
    final currentUserId = auth.currentUser?.uid;
    if (currentUserId == null) return [];

    final localKey = '${currentUserId}_$receiverUserId';
    final Set<String> seenIds = {};
    final List<OneToOneMessageModel> allMedia = [];

    // Step 1: Load from Hive (contains all seen/deleted messages)
    try {
      final box = Hive.isBoxOpen('messages')
          ? Hive.box('messages')
          : await Hive.openBox('messages');

      final cachedData = box.get(localKey, defaultValue: []);
      if (cachedData is List) {
        final messages = cachedData.cast<OneToOneMessageModel>();
        for (var m in messages) {
          if (['image', 'video', 'gif'].contains(m.messageType) &&
              m.fileMessageData != null &&
              m.fileMessageData!.isNotEmpty) {
            allMedia.add(m);
            seenIds.add(m.messageId);
          }
        }
      }
      log('📦 Hive media count: ${allMedia.length}');
    } catch (e) {
      log('❌ Hive media error: $e');
    }

    // Step 2: Fetch from Firestore (recent unseen messages)
    try {
      final snapshot = await fireStore
          .collection('users')
          .doc(currentUserId)
          .collection('chats')
          .doc(receiverUserId)
          .collection('messages')
          .where('messageType', whereIn: ['image', 'video', 'gif'])
          .orderBy('timeSent', descending: true)
          .get();

      for (var doc in snapshot.docs) {
        final data = doc.data();
        data['isSeen'] = data['isSeen'] ?? false;
        final msg = OneToOneMessageModel.fromMap(data);
        if (!seenIds.contains(msg.messageId) &&
            msg.fileMessageData != null &&
            msg.fileMessageData!.isNotEmpty) {
          allMedia.add(msg);
        }
      }
      log('🔥 Total media after merge: ${allMedia.length}');
    } catch (e) {
      log('❌ Firestore media error: $e');
    }

    allMedia.sort((a, b) => b.timeSent.compareTo(a.timeSent));
    return allMedia;
  }

  Future<List<OneToOneMessageModel>> getSharedLinks(
    String receiverUserId,
  ) async {
    final currentUserId = auth.currentUser?.uid;
    if (currentUserId == null) return [];

    final localKey = '${currentUserId}_$receiverUserId';
    final Set<String> seenIds = {};
    final List<OneToOneMessageModel> allLinks = [];

    // Step 1: Load from Hive
    try {
      final box = Hive.isBoxOpen('messages')
          ? Hive.box('messages')
          : await Hive.openBox('messages');

      final cachedData = box.get(localKey, defaultValue: []);
      if (cachedData is List) {
        final messages = cachedData.cast<OneToOneMessageModel>();
        for (var m in messages) {
          if (m.messageType == 'text' && _containsUrl(m.text)) {
            allLinks.add(m);
            seenIds.add(m.messageId);
          }
        }
      }
      log('📦 Hive links count: ${allLinks.length}');
    } catch (e) {
      log('❌ Hive links error: $e');
    }

    // Step 2: Fetch from Firestore
    try {
      final snapshot = await fireStore
          .collection('users')
          .doc(currentUserId)
          .collection('chats')
          .doc(receiverUserId)
          .collection('messages')
          .where('messageType', isEqualTo: 'text')
          .orderBy('timeSent', descending: true)
          .get();

      for (var doc in snapshot.docs) {
        final data = doc.data();
        data['isSeen'] = data['isSeen'] ?? false;
        final msg = OneToOneMessageModel.fromMap(data);
        if (!seenIds.contains(msg.messageId) && _containsUrl(msg.text)) {
          allLinks.add(msg);
        }
      }
      log('🔥 Total links after merge: ${allLinks.length}');
    } catch (e) {
      log('❌ Firestore links error: $e');
    }

    allLinks.sort((a, b) => b.timeSent.compareTo(a.timeSent));
    return allLinks;
  }

  bool _containsUrl(String text) {
    return RegExp(r'https?://[^\s]+', caseSensitive: false).hasMatch(text);
  }
}
