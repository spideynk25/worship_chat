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
import 'package:worship_chat/common/utils/media_cache_service.dart';
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

  List<ChatContact> getCachedContacts({required bool isAllChats}) {
    final currentUserId = auth.currentUser?.uid;
    if (currentUserId == null) return [];
    try {
      if (Hive.isBoxOpen('contacts_cache')) {
        final box = Hive.box('contacts_cache');
        final key = isAllChats ? 'all_contacts' : 'user_chats_$currentUserId';
        final cachedRaw = box.get(key, defaultValue: []);
        if (cachedRaw is List && cachedRaw.isNotEmpty) {
          return cachedRaw
              .map((item) =>
                  ChatContact.fromMap(Map<String, dynamic>.from(item as Map)))
              .toList();
        }
      }
    } catch (e) {
      log('Error reading cached contacts: $e');
    }
    return [];
  }

  Stream<List<ChatContact>> fetchAllContacts() async* {
    final currentUserId = auth.currentUser?.uid;

    // 1. Immediately emit cached contacts from Hive (0ms)
    final cached = getCachedContacts(isAllChats: true);
    if (cached.isNotEmpty) {
      log('⚡ [Instant Cache] Emitted ${cached.length} all_contacts from Hive');
      yield cached;
    }

    // 2. Stream from Firestore and update Hive
    yield* fireStore.collection('users').snapshots().map((event) {
      log("Snapshot received - Doc count: ${event.docs.length}");

      List<ChatContact> contacts = [];
      for (var document in event.docs) {
        try {
          final data = document.data();
          final uid = data['uid'] as String? ?? document.id;
          if (uid == currentUserId) continue;

          final name = data['name'] as String? ?? 'User';
          final profilePic = data['profilePic'] as String?;
          final fcmToken = data['fcmToken'] as String? ?? '';

          contacts.add(
            ChatContact(
              name: name,
              profilePic: profilePic,
              uid: uid,
              timeSent: DateTime.now(),
              lastMessage: '',
              fcmToken: fcmToken,
              unseenCount: false,
              chatBackgroundUrl: '',
            ),
          );
        } catch (e) {
          log("Error processing all_contact doc: $e");
        }
      }

      // Persist to Hive for next instant launch
      try {
        if (Hive.isBoxOpen('contacts_cache')) {
          Hive.box('contacts_cache').put(
            'all_contacts',
            contacts.map((c) => c.toMap()).toList(),
          );
        }
      } catch (e) {
        log('Error saving all_contacts to Hive: $e');
      }

      return contacts;
    });
  }

  Stream<List<ChatContact>> getChatContact() async* {
    final currentUserId = auth.currentUser?.uid;
    if (currentUserId == null) {
      yield [];
      return;
    }

    // 1. Immediately emit cached chat contacts from Hive (0ms)
    final cached = getCachedContacts(isAllChats: false);
    if (cached.isNotEmpty) {
      log('⚡ [Instant Cache] Emitted ${cached.length} chat contacts from Hive');
      yield cached;
    }

    // 2. Stream from Firestore and update Hive
    yield* fireStore
        .collection('users')
        .doc(currentUserId)
        .collection("chats")
        .snapshots()
        .asyncMap((event) async {
          List<ChatContact> contacts = [];
          for (var document in event.docs) {
            try {
              final docData = document.data();
              // ALWAYS resolve the UID: try docData['uid'], then docData['contactId'], then document.id
              final targetUid = (docData['uid'] as String?)?.trim().isNotEmpty == true
                  ? (docData['uid'] as String).trim()
                  : (docData['contactId'] as String?)?.trim().isNotEmpty == true
                      ? (docData['contactId'] as String).trim()
                      : document.id.trim();

              if (targetUid.isEmpty || targetUid == currentUserId) {
                continue;
              }

              var chatContact = ChatContact.fromMap(docData, documentId: targetUid);
              try {
                var userData = await fireStore
                    .collection('users')
                    .doc(targetUid)
                    .get();

                if (userData.data() != null) {
                  var user = UserModel.fromMap(userData.data()!);
                  final freshToken = (user.fcmToken != null && user.fcmToken!.isNotEmpty)
                      ? user.fcmToken!
                      : (chatContact.fcmToken ?? '');
                  contacts.add(
                    ChatContact(
                      name: (user.name != null && user.name!.isNotEmpty)
                          ? user.name!
                          : chatContact.name,
                      profilePic: user.profilePic ?? chatContact.profilePic,
                      uid: targetUid,
                      timeSent: chatContact.timeSent,
                      lastMessage: chatContact.lastMessage,
                      fcmToken: freshToken,
                      unseenCount: chatContact.unseenCount,
                      chatBackgroundUrl: chatContact.chatBackgroundUrl,
                    ),
                  );
                } else {
                  contacts.add(
                    ChatContact(
                      name: chatContact.name,
                      profilePic: chatContact.profilePic,
                      uid: targetUid,
                      timeSent: chatContact.timeSent,
                      lastMessage: chatContact.lastMessage,
                      fcmToken: chatContact.fcmToken,
                      unseenCount: chatContact.unseenCount,
                      chatBackgroundUrl: chatContact.chatBackgroundUrl,
                    ),
                  );
                }
              } catch (e) {
                contacts.add(
                  ChatContact(
                    name: chatContact.name,
                    profilePic: chatContact.profilePic,
                    uid: targetUid,
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

          final filtered = contacts
              .where((chatContact) =>
                  chatContact.uid.isNotEmpty && chatContact.uid != currentUserId)
              .toList();

          // Sort by timeSent descending so the most recent conversation is on top
          filtered.sort((a, b) {
            if (a.timeSent == null && b.timeSent == null) return 0;
            if (a.timeSent == null) return 1;
            if (b.timeSent == null) return -1;
            return b.timeSent!.compareTo(a.timeSent!);
          });

          // Persist to Hive for next instant launch
          try {
            if (Hive.isBoxOpen('contacts_cache')) {
              await Hive.box('contacts_cache').put(
                'user_chats_$currentUserId',
                filtered.map((c) => c.toMap()).toList(),
              );
            }
          } catch (e) {
            log('Error saving user_chats to Hive: $e');
          }

          return filtered;
        });
  }

  Stream<List<OneToOneMessageModel>> getChatStream(
      String receiverUserId) async* {
    final currentUserId = auth.currentUser?.uid;
    if (currentUserId == null) {
      yield [];
      return;
    }

    final localKey = '${currentUserId}_$receiverUserId';

    // 1. Immediately emit cached messages from Hive (0ms)
    try {
      if (Hive.isBoxOpen('messages')) {
        final box = Hive.box('messages');
        final cachedData = box.get(localKey, defaultValue: []);
        if (cachedData is List && cachedData.isNotEmpty) {
          final cachedMessages = cachedData.cast<OneToOneMessageModel>();
          log('⚡ [Instant Cache] Emitted ${cachedMessages.length} cached 1-to-1 messages for $receiverUserId');
          yield cachedMessages;
        }
      }
    } catch (e) {
      log('❌ Error emitting cached 1-to-1 messages: $e');
    }

    // 2. Stream updates from Firestore and keep Hive in sync
    yield* fireStore
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
                prev[i].isDelivered != next[i].isDelivered ||
                prev[i].isSending != next[i].isSending ||
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
    final currentUid = auth.currentUser?.uid;
    if (currentUid == null) return [];
    final localKey = '${currentUid}_$receiverUserId';

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

    // Firestore is source of truth - parse individually to prevent single doc failure
    List<OneToOneMessageModel> firestoreMessages = [];
    for (var doc in snapshot.docs) {
      try {
        final data = doc.data();
        data['isSeen'] = data['isSeen'] ?? false;
        firestoreMessages.add(OneToOneMessageModel.fromMap(data));
      } catch (e) {
        log('❌ Error parsing message ${doc.id}: $e');
      }
    }

    log('🔥 Loaded ${firestoreMessages.length} messages from Firestore');

    // Auto-acknowledge delivery for messages received by the current user
    for (var m in firestoreMessages) {
      if (m.receiverId == currentUid && !m.isDelivered && !m.isSeen) {
        _markMessageAsDelivered(m.senderId, currentUid, m.messageId);
      }
    }

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

    // Save merged list to Hive, then batch clean seen/old messages from Firestore
    _saveToHiveAsync(box, localKey, allMessages, receiverUserId, firestoreMessages);

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
    String receiverUserId,
    List<OneToOneMessageModel> firestoreMessages,
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

  void _markMessageAsDelivered(
    String senderId,
    String receiverId,
    String messageId,
  ) async {
    try {
      await fireStore
          .collection('users')
          .doc(receiverId)
          .collection('chats')
          .doc(senderId)
          .collection('messages')
          .doc(messageId)
          .update({'isDelivered': true});
    } catch (_) {}

    try {
      await fireStore
          .collection('users')
          .doc(senderId)
          .collection('chats')
          .doc(receiverId)
          .collection('messages')
          .doc(messageId)
          .update({'isDelivered': true});
    } catch (_) {}
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

  Future<void> _saveDataToContactsSubCollection({
    required UserModel senderUserData,
    required UserModel? receiverUserData,
    required String text,
    required DateTime timeSent,
    required String receiverUserId,
    required String messageType,
    required String fcmToken,
    required bool? unseenCount,
    required String? chatBackgroundUrl,
  }) async {
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
        lastMessage = text.trim().isNotEmpty ? text.trim() : "New message";
    }

    final currentUserId = auth.currentUser?.uid;
    if (currentUserId == null) return;

    try {
      final myToken = await FirebaseMessaging.instance.getToken() ?? '';

      var receiverChatContact = ChatContact(
        name: senderUserData.name ?? 'User',
        profilePic: senderUserData.profilePic,
        uid: currentUserId,
        timeSent: timeSent,
        lastMessage: lastMessage,
        fcmToken: myToken,
        unseenCount: true,
        chatBackgroundUrl: chatBackgroundUrl ?? "",
      );

      await fireStore
          .collection('users')
          .doc(receiverUserId)
          .collection('chats')
          .doc(currentUserId)
          .set(receiverChatContact.toMap(), SetOptions(merge: true));

      var senderChatContact = ChatContact(
        name: receiverUserData?.name ?? 'User',
        profilePic: receiverUserData?.profilePic,
        uid: receiverUserId,
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
          .set(senderChatContact.toMap(), SetOptions(merge: true));
    } catch (e) {
      log('Error saving to contacts: $e');
    }
  }

  Future<void> _saveMessageToMessageSubcollection({
    required String receiverUserId,
    required String text,
    required DateTime timeSent,
    required String messageId,
    required String username,
    required String name,
    required dynamic receiverUsername,
    required dynamic receiverName,
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
      } else {
        log('⚠️ [Notification] Cannot send notification: recipient fcmToken is empty for receiver $receiverUserId');
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
              body = text.trim().isNotEmpty ? text.trim() : 'New message';
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

        final safeName = name.trim().isNotEmpty ? name.trim() : 'New Message';

        await sendNotification(
          fcmToken,
          safeName,
          body,
          data: {
            'type': 'chat',
            'senderUid': senderUid,
            'name': safeName,
            'profilePic': senderProfilePic,
            'tag': senderUid,
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
      final currentUserId = auth.currentUser?.uid;
      if (currentUserId == null) {
        throw Exception('User not authenticated');
      }

      var messageId = const Uuid().v1();
      var timeSent = DateTime.now();

      // Immediately save optimistic message to local Hive with isSending: true (clock icon)
      final optimisticMessage = OneToOneMessageModel(
        senderId: currentUserId,
        receiverId: receiverUserId,
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
            ? (senderUser.name ?? 'User')
            : '',
        repliedMessageType: messageReply == null ? 'text' : messageReply.messageType,
      );
      _saveOptimisticMessageToHive(currentUserId, receiverUserId, optimisticMessage);

      String? fileData;

      if (messageType == "image" && file != null) {
        log("📤 Uploading image for message: $messageId");
        fileData = await uploadImageToCloudinary(file, type);
        log("✅ Image uploaded: $fileData");
        if (file is File && fileData != null && fileData.isNotEmpty) {
          MediaCacheService().registerLocalMapping(fileData, file.path);
        }
      } else if (messageType == "video" && file != null) {
        log("📤 Uploading video for message: $messageId");
        fileData = await uploadVideoToCloudinary(file, type);
        log("✅ Video uploaded: $fileData");
        if (file is File && fileData != null && fileData.isNotEmpty) {
          MediaCacheService().registerLocalMapping(fileData, file.path);
        }
      } else if (messageType == "gif" && file != null) {
        fileData = file;
      }

      // Fetch fresh receiver data to get latest FCM token (server-first with cache fallback)
      UserModel? receiverUserData;
      try {
        DocumentSnapshot<Map<String, dynamic>> userDataMap;
        try {
          userDataMap = await fireStore
              .collection('users')
              .doc(receiverUserId)
              .get(const GetOptions(source: Source.server))
              .timeout(const Duration(seconds: 3));
        } catch (_) {
          userDataMap = await fireStore
              .collection('users')
              .doc(receiverUserId)
              .get();
        }

        if (userDataMap.exists && userDataMap.data() != null) {
          receiverUserData = UserModel.fromMap(userDataMap.data()!);
        }
      } catch (e) {
        log('Warning: could not fetch receiverUserData: $e');
      }

      // Priority: fresh token from receiver's Firestore doc, fallback to passed token
      final recipientFcmToken = (receiverUserData?.fcmToken != null &&
              receiverUserData!.fcmToken!.isNotEmpty)
          ? receiverUserData.fcmToken!
          : fcmToken;

      log("token sendTextMessage: recipientFcmToken length=${recipientFcmToken.length}");

      final safeSenderName = senderUser.name ?? 'User';
      final safeSenderUsername = senderUser.userName ?? 'User';
      final safeReceiverName = receiverUserData?.name ?? 'User';
      final safeReceiverUsername = receiverUserData?.userName ?? 'User';

      await Future.wait([
        _saveDataToContactsSubCollection(
          senderUserData: senderUser,
          receiverUserData: receiverUserData,
          text: text,
          timeSent: timeSent,
          receiverUserId: receiverUserId,
          messageType: messageType,
          fcmToken: recipientFcmToken,
          unseenCount: unseenCount,
          chatBackgroundUrl: chatBackgroundUrl,
        ),
        _saveMessageToMessageSubcollection(
          receiverUserId: receiverUserId,
          text: text,
          timeSent: timeSent,
          messageType: messageType,
          messageId: messageId,
          receiverUsername: safeReceiverUsername,
          receiverName: safeReceiverName,
          name: safeSenderName,
          username: safeSenderUsername,
          fileMessageData: fileData,
          receiverUserName: safeReceiverName,
          senderUsername: safeSenderName,
          messageReplyType: messageReply == null
              ? "text"
              : messageReply.messageType,
          messageReply: messageReply,
          fcmToken: recipientFcmToken,
          senderUid: currentUserId,
          senderProfilePic: senderUser.profilePic ?? '',
        ),
      ]);

      log('✅ Message saved with ID: $messageId');
    } catch (e) {
      log('❌ Error sending message: $e');
      final currentUserId = auth.currentUser?.uid;
      if (currentUserId != null) {
        _removeOptimisticMessageFromHive(currentUserId, receiverUserId);
      }
      if (context.mounted) {
        showSnackBar(context: context, content: e.toString());
      }
      rethrow;
    }
  }

  void _saveOptimisticMessageToHive(
    String currentUserId,
    String receiverUserId,
    OneToOneMessageModel message,
  ) async {
    final localKey = '${currentUserId}_$receiverUserId';
    try {
      final box = Hive.isBoxOpen('messages')
          ? Hive.box('messages')
          : await Hive.openBox('messages');

      final cachedData = box.get(localKey, defaultValue: []);
      List<OneToOneMessageModel> messages = [];
      if (cachedData is List) {
        messages = cachedData.cast<OneToOneMessageModel>().toList();
      }
      final existingIndex = messages.indexWhere((m) => m.messageId == message.messageId);
      if (existingIndex >= 0) {
        messages[existingIndex] = message;
      } else {
        messages.add(message);
      }
      await box.put(localKey, messages);
      log('🕒 Saved optimistic sending message to Hive: ${message.messageId}');
    } catch (e) {
      log('❌ Error saving optimistic message to Hive: $e');
    }
  }

  void _removeOptimisticMessageFromHive(
    String currentUserId,
    String receiverUserId,
  ) async {
    final localKey = '${currentUserId}_$receiverUserId';
    try {
      if (Hive.isBoxOpen('messages')) {
        final box = Hive.box('messages');
        final cachedData = box.get(localKey, defaultValue: []);
        if (cachedData is List) {
          final messages = cachedData.cast<OneToOneMessageModel>().toList();
          messages.removeWhere((m) => m.isSending);
          await box.put(localKey, messages);
        }
      }
    } catch (_) {}
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

      // Update current user's copy
      try {
        await fireStore
            .collection('users')
            .doc(currentUserId)
            .collection('chats')
            .doc(receiverUserId)
            .collection('messages')
            .doc(messageId)
            .update({'isSeen': true, 'isDelivered': true});
      } catch (e) {
        log('Note: could not update seen on current user doc: $e');
      }

      // Update partner's copy
      try {
        await fireStore
            .collection('users')
            .doc(receiverUserId)
            .collection('chats')
            .doc(currentUserId)
            .collection('messages')
            .doc(messageId)
            .update({'isSeen': true, 'isDelivered': true});
      } catch (e) {
        log('Note: could not update seen on receiver doc: $e');
      }

      // ✅ Update Hive cache immediately so UI reflects change
      await _updateSeenInHive(currentUserId, receiverUserId, messageId);

      // ✅ Update unseen count
      try {
        await fireStore
            .collection('users')
            .doc(currentUserId)
            .collection('chats')
            .doc(receiverUserId)
            .update({'unseenCount': false});
      } catch (e) {
        log('Note: could not update unseenCount: $e');
      }

      log('✅ Message marked as seen');
    } catch (e) {
      log('❌ Error in setChatMessageSeen: $e');
    }
  }

  /// Mark all unread messages in the chat as seen and clear the unseen badge
  Future<void> markChatAsSeen(String partnerUserId) async {
    final currentUserId = auth.currentUser?.uid;
    if (currentUserId == null || partnerUserId.isEmpty) return;

    // 1. Immediately clear contact unseenCount for current user
    try {
      await fireStore
          .collection('users')
          .doc(currentUserId)
          .collection('chats')
          .doc(partnerUserId)
          .update({'unseenCount': false});
      log('✅ Contact unseenCount reset to false for $partnerUserId');
    } catch (e) {
      log('Note: could not update contact unseenCount: $e');
    }

    // 2. Query all unread messages received by current user in this chat
    try {
      final unreadDocs = await fireStore
          .collection('users')
          .doc(currentUserId)
          .collection('chats')
          .doc(partnerUserId)
          .collection('messages')
          .where('receiverId', isEqualTo: currentUserId)
          .where('isSeen', isEqualTo: false)
          .get();

      if (unreadDocs.docs.isNotEmpty) {
        log('👁️ Found ${unreadDocs.docs.length} unread messages to mark as seen');
        final batch = fireStore.batch();
        for (var doc in unreadDocs.docs) {
          final messageId = doc.id;
          // Receiver's doc
          batch.update(doc.reference, {'isSeen': true, 'isDelivered': true});

          // Sender's doc
          final senderMessageRef = fireStore
              .collection('users')
              .doc(partnerUserId)
              .collection('chats')
              .doc(currentUserId)
              .collection('messages')
              .doc(messageId);
          batch.update(senderMessageRef, {'isSeen': true, 'isDelivered': true});
        }
        await batch.commit();
        log('✅ Batch marked ${unreadDocs.docs.length} messages as seen in Firestore');
      }
    } catch (e) {
      log('❌ Error batch marking messages as seen in Firestore: $e');
    }

    // 3. Immediately update Hive cache
    await _markChatSeenInHive(currentUserId, partnerUserId);
  }

  Future<void> _markChatSeenInHive(String currentUserId, String partnerUserId) async {
    final localKey = '${currentUserId}_$partnerUserId';
    try {
      final box = Hive.isBoxOpen('messages')
          ? Hive.box('messages')
          : await Hive.openBox('messages');

      final cachedData = box.get(localKey, defaultValue: []);
      if (cachedData is List) {
        final messages = cachedData.cast<OneToOneMessageModel>();
        bool changed = false;
        final updated = messages.map((m) {
          if (m.receiverId == currentUserId && (!m.isSeen || !m.isDelivered)) {
            changed = true;
            return m.copyWith(isSeen: true, isDelivered: true);
          }
          return m;
        }).toList();

        if (changed) {
          await box.put(localKey, updated);
          log('✅ Hive cache updated: all messages marked seen for chat $partnerUserId');
        }
      }
    } catch (e) {
      log('❌ Error updating Hive cache for seen chat: $e');
    }
  }

  // ✅ Update a single message's isSeen in Hive immediately
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
          return m.messageId == messageId ? m.copyWith(isSeen: true, isDelivered: true) : m;
        }).toList();
        await box.put(localKey, updated);
        log('✅ Hive cache updated: message $messageId marked seen');
      }
    } catch (e) {
      log('❌ Error updating Hive for seen message: $e');
    }
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
