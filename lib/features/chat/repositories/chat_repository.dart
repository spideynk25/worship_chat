import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/adapters.dart';
import 'package:uuid/uuid.dart';
import 'package:worship_chat/common/providers/message_reply_provider.dart';
import 'package:worship_chat/common/utils/background_task_service.dart';
import 'package:worship_chat/common/utils/file_messages.dart';
import 'package:worship_chat/common/utils/firebase_notification_service.dart';
import 'package:worship_chat/common/utils/location_service.dart';
import 'package:worship_chat/common/utils/media_cache_service.dart';
import 'package:worship_chat/common/utils/utils.dart';
import 'package:worship_chat/common/utils/wish_helper.dart';
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
    try {
      await user.reload().timeout(const Duration(milliseconds: 500));
    } catch (_) {}
    return FirebaseAuth.instance.currentUser;
  }
  return null;
});

class ChatRepository {
  final FirebaseFirestore fireStore;
  final FirebaseAuth auth;
  static final Map<String, List<void Function(List<OneToOneMessageModel>)>> _activeChatListeners = {};

  static void notifyChatListeners(String localKey, List<OneToOneMessageModel> messages) {
    final listeners = _activeChatListeners[localKey];
    if (listeners != null) {
      final msgsCopy = List<OneToOneMessageModel>.from(messages);
      for (final listener in List.from(listeners)) {
        try {
          listener(msgsCopy);
        } catch (_) {}
      }
    }
  }

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

  String? _getEffectiveUserId() {
    final authUid = auth.currentUser?.uid;
    if (authUid != null && authUid.isNotEmpty) return authUid;
    return safeCurrentUserId();
  }

  List<ChatContact> getCachedContacts({required bool isAllChats}) {
    final currentUserId = _getEffectiveUserId();
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
    final currentUserId = _getEffectiveUserId();

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
    final currentUserId = _getEffectiveUserId();
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

              var chatContact =
                  ChatContact.fromMap(docData, documentId: targetUid);

              // Check if Hive messages cache has a newer message for accurate last message display
              String effectiveLastMessage = chatContact.lastMessage ?? '';
              DateTime? effectiveTimeSent = chatContact.timeSent;
              bool? effectiveUnseen = chatContact.unseenCount;

              try {
                if (Hive.isBoxOpen('messages')) {
                  final msgsBox = Hive.box('messages');
                  final cachedMsgs = msgsBox.get('${currentUserId}_$targetUid');
                  if (cachedMsgs is List && cachedMsgs.isNotEmpty) {
                    final lastItem = cachedMsgs.last;
                    OneToOneMessageModel? parsedLast;
                    if (lastItem is OneToOneMessageModel) {
                      parsedLast = lastItem;
                    } else if (lastItem is Map) {
                      parsedLast = OneToOneMessageModel.fromMap(
                          Map<String, dynamic>.from(lastItem));
                    }
                    if (parsedLast != null) {
                      if (effectiveTimeSent == null ||
                          parsedLast.timeSent.isAfter(effectiveTimeSent)) {
                        effectiveTimeSent = parsedLast.timeSent;
                        switch (parsedLast.messageType) {
                          case 'image':
                            effectiveLastMessage = '📷 Photo';
                            break;
                          case 'video':
                            effectiveLastMessage = '🎥 Video';
                            break;
                          case 'gif':
                            effectiveLastMessage = '🎮 Gif';
                            break;
                          case 'document':
                            effectiveLastMessage =
                                '📄 ${parsedLast.text.isNotEmpty ? parsedLast.text : 'Document'}';
                            break;
                          case 'location':
                            effectiveLastMessage = '📍 Location';
                            break;
                          case 'live_location':
                            effectiveLastMessage = '📡 Live Location';
                            break;
                          default:
                            effectiveLastMessage =
                                parsedLast.text.trim().isNotEmpty
                                    ? parsedLast.text.trim()
                                    : 'New message';
                        }
                        if (parsedLast.receiverId == currentUserId &&
                            !parsedLast.isSeen) {
                          effectiveUnseen = true;
                        }
                      }
                    }
                  }
                }
              } catch (_) {}

              try {
                var userData = await fireStore
                    .collection('users')
                    .doc(targetUid)
                    .get();

                if (userData.data() != null) {
                  var user = UserModel.fromMap(userData.data()!);
                  final freshToken = (user.fcmToken != null &&
                          user.fcmToken!.isNotEmpty)
                      ? user.fcmToken!
                      : (chatContact.fcmToken ?? '');
                  contacts.add(
                    ChatContact(
                      name: (user.name != null && user.name!.isNotEmpty)
                          ? user.name!
                          : chatContact.name,
                      profilePic: user.profilePic ?? chatContact.profilePic,
                      uid: targetUid,
                      timeSent: effectiveTimeSent,
                      lastMessage: effectiveLastMessage,
                      fcmToken: freshToken,
                      unseenCount: effectiveUnseen,
                      chatBackgroundUrl: chatContact.chatBackgroundUrl,
                    ),
                  );
                } else {
                  contacts.add(
                    ChatContact(
                      name: chatContact.name,
                      profilePic: chatContact.profilePic,
                      uid: targetUid,
                      timeSent: effectiveTimeSent,
                      lastMessage: effectiveLastMessage,
                      fcmToken: chatContact.fcmToken,
                      unseenCount: effectiveUnseen,
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
                    timeSent: effectiveTimeSent,
                    lastMessage: effectiveLastMessage,
                    fcmToken: chatContact.fcmToken,
                    unseenCount: effectiveUnseen,
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

  Stream<List<OneToOneMessageModel>> getChatStream(String receiverUserId) {
    final currentUserId = auth.currentUser?.uid;
    debugPrint(
        '🔍 [getChatStream] currentUserId: $currentUserId, receiverUserId: $receiverUserId');

    if (currentUserId == null) {
      return Stream.value([]);
    }

    final localKey = '${currentUserId}_$receiverUserId';

    // Try to get cached messages for immediate display (synchronous)
    List<OneToOneMessageModel> cachedMessages = [];
    try {
      if (Hive.isBoxOpen('messages')) {
        final box = Hive.box('messages');
        final cachedData = box.get(localKey, defaultValue: []);
        cachedMessages = _safeCastMessages(cachedData);
        if (cachedMessages.isNotEmpty) {
          // Optimistically mark incoming messages as seen in cachedMessages
          // so the initial emission matches what the screen pre-seeds
          cachedMessages = cachedMessages.map((m) {
            if (m.receiverId == currentUserId && (!m.isSeen || !m.isDelivered)) {
              return m.copyWith(isSeen: true, isDelivered: true);
            }
            return m;
          }).toList();
          debugPrint(
              '⚡ [Instant Cache] Found ${cachedMessages.length} cached messages for $receiverUserId');
        }
      }
    } catch (e) {
      debugPrint('❌ Error reading cached 1-to-1 messages: $e');
    }

    // Sync any pending background notification replies into Hive
    FirebaseNotificationService.syncPendingBackgroundRepliesToHive(
      specificChatId: localKey,
    );

    final controller = StreamController<List<OneToOneMessageModel>>();

    bool areMessagesEqual(
      List<OneToOneMessageModel> prev,
      List<OneToOneMessageModel> next,
    ) {
      if (identical(prev, next)) return true;
      if (prev.length != next.length) return false;
      for (int i = 0; i < prev.length; i++) {
        final p = prev[i];
        final n = next[i];
        if (p.messageId != n.messageId ||
            p.messageType != n.messageType ||
            p.text != n.text ||
            p.isEdited != n.isEdited ||
            p.isDeleted != n.isDeleted ||
            p.isPinned != n.isPinned ||
            p.pinnedAt != n.pinnedAt ||
            p.pinnedBy != n.pinnedBy ||
            p.fileMessageData != n.fileMessageData ||
            !mapEquals(p.reactions, n.reactions)) {
          return false;
        }
        if (p.isSeen != n.isSeen ||
            p.isDelivered != n.isDelivered ||
            p.isSending != n.isSending) {
          return false;
        }
      }
      return true;
    }

    List<OneToOneMessageModel>? lastEmitted;

    void emitIfChanged(List<OneToOneMessageModel> msgs) {
      if (controller.isClosed) return;
      if (lastEmitted != null && areMessagesEqual(lastEmitted!, msgs)) {
        return; // identical — skip duplicate initial build
      }
      lastEmitted = msgs;
      controller.add(msgs);
    }

    // Emit cached messages immediately if we have them
    if (cachedMessages.isNotEmpty) {
      emitIfChanged(cachedMessages);
    }

    // Subscribe to Firestore and forward only changed events
    final firestoreSubscription = fireStore
        .collection('users')
        .doc(currentUserId)
        .collection('chats')
        .doc(receiverUserId)
        .collection('messages')
        .snapshots()
        .asyncMap((event) async {
          try {
            debugPrint('🔥 [getChatStream] Firestore doc count: ${event.docs.length}');
            return await _processMessages(event, receiverUserId);
          } catch (e) {
            debugPrint('❌ Error processing messages: $e');
            return <OneToOneMessageModel>[];
          }
        })
        .listen(
          (messages) {
            emitIfChanged(messages);
            // Fire-and-forget delivery acknowledgment — done AFTER emitting
            // to UI so it doesn't block the stream or trigger re-emission loops.
            _acknowledgeDelivery(messages, currentUserId);
          },
          onError: (e) {
            if (!controller.isClosed) controller.addError(e);
          },
          onDone: () {
            if (!controller.isClosed) controller.close();
          },
        );

    // Register listener for instantaneous optimistic message dispatch
    _activeChatListeners.putIfAbsent(localKey, () => []).add(emitIfChanged);

    controller.onCancel = () {
      _activeChatListeners[localKey]?.remove(emitIfChanged);
      if (_activeChatListeners[localKey]?.isEmpty ?? false) {
        _activeChatListeners.remove(localKey);
      }
      firestoreSubscription.cancel();
    };

    return controller.stream;
  }


  List<OneToOneMessageModel> _safeCastMessages(dynamic cachedData) {
    if (cachedData is! List) return [];
    final List<OneToOneMessageModel> result = [];
    for (var item in cachedData) {
      if (item is OneToOneMessageModel) {
        result.add(item);
      } else if (item is Map) {
        try {
          result.add(
            OneToOneMessageModel.fromMap(Map<String, dynamic>.from(item)),
          );
        } catch (e) {
          log('❌ Error parsing message map from Hive: $e');
        }
      }
    }
    return result;
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
    final Set<String> firestoreIds = {};
    for (var doc in snapshot.docs) {
      try {
        final data = doc.data();
        data['isSeen'] = data['isSeen'] ?? false;
        final msg = OneToOneMessageModel.fromMap(data);
        firestoreMessages.add(msg);
        firestoreIds.add(msg.messageId);
      } catch (e) {
        log('❌ Error parsing message ${doc.id}: $e');
      }
    }

    log('🔥 Loaded ${firestoreMessages.length} messages from Firestore');

    // NOTE: Delivery acknowledgment is handled outside of _processMessages
    // to avoid triggering a Firestore write → new snapshot → infinite loop.

    // Load cached messages safely
    List<OneToOneMessageModel> cachedMessages = [];
    try {
      final cachedData = box.get(localKey, defaultValue: []);
      cachedMessages = _safeCastMessages(cachedData);
      log('📦 Loaded ${cachedMessages.length} messages from Hive cache');
    } catch (e) {
      log('❌ Error loading from Hive: $e');
    }

    // Merge: Firestore is authoritative ground truth
    final Map<String, OneToOneMessageModel> messagesMap = {};
    final Map<String, OneToOneMessageModel> cachedMap = {
      for (var m in cachedMessages) m.messageId: m,
    };

    if (firestoreMessages.isNotEmpty) {
      // 1. Keep cached outgoing messages that are still sending or recent (<5min)
      for (var m in cachedMessages) {
        if (m.deletedFor.contains(currentUid)) continue;
        if (m.senderId == currentUid &&
            (m.isSending || !firestoreIds.contains(m.messageId))) {
          if (DateTime.now().difference(m.timeSent).inMinutes < 5) {
            messagesMap[m.messageId] = m;
          }
        }
      }
      // 2. Add all Firestore messages (they overwrite any cache, but preserve local delivery confirmation & seen state)
      for (var m in firestoreMessages) {
        if (m.deletedFor.contains(currentUid)) continue;
        final cached = cachedMap[m.messageId];
        final bool isSeen = m.isSeen || (cached?.isSeen ?? false);
        final bool isDelivered =
            isSeen || m.isDelivered || (cached?.isDelivered ?? false);
        if (isSeen != m.isSeen || isDelivered != m.isDelivered) {
          messagesMap[m.messageId] = m.copyWith(
            isSeen: isSeen,
            isDelivered: isDelivered,
          );
        } else {
          messagesMap[m.messageId] = m;
        }
      }
    } else {
      // If Firestore returned 0 docs (offline or brand new chat), use cache
      for (var m in cachedMessages) {
        if (m.deletedFor.contains(currentUid)) continue;
        messagesMap[m.messageId] = m;
      }
    }

    final rawMerged = messagesMap.values.toList()
      ..sort((a, b) => a.timeSent.compareTo(b.timeSent));

    // Deduplicate any consecutive phantom duplicates (same sender, same text or fake media text card within 60s)
    final List<OneToOneMessageModel> allMessages = [];
    for (final msg in rawMerged) {
      if (allMessages.isEmpty) {
        allMessages.add(msg);
        continue;
      }
      final prev = allMessages.last;
      final isSameSender = prev.senderId == msg.senderId;
      final timeDiffSec =
          msg.timeSent.difference(prev.timeSent).inSeconds.abs();

      // Case A: Identical non-empty text from same sender within 60s
      final isIdenticalText = isSameSender &&
          prev.text.trim() == msg.text.trim() &&
          prev.text.trim().isNotEmpty &&
          timeDiffSec <= 60;

      // Case B: Phantom media text card ("📷 Photo" / "🎥 Video") alongside a real media message
      final isPhantomMediaMsg = isSameSender &&
          timeDiffSec <= 60 &&
          ((prev.messageType == 'image' && msg.text == '📷 Photo') ||
              (prev.messageType == 'video' && msg.text == '🎥 Video'));

      final isPhantomMediaPrev = isSameSender &&
          timeDiffSec <= 60 &&
          ((msg.messageType == 'image' && prev.text == '📷 Photo') ||
              (msg.messageType == 'video' && prev.text == '🎥 Video'));

      if (isIdenticalText || isPhantomMediaMsg) {
        continue;
      }
      if (isPhantomMediaPrev) {
        allMessages.removeLast();
        allMessages.add(msg);
        continue;
      }

      allMessages.add(msg);
    }

    log('📊 Total unique messages: ${allMessages.length}');

    // Save cleaned list to Hive
    _saveToHiveAsync(
        box, localKey, allMessages, receiverUserId, firestoreMessages);

    // Sync contact's lastMessage in Firestore and Hive
    if (allMessages.isNotEmpty) {
      _syncContactLastMessage(
        currentUid: currentUid,
        receiverUserId: receiverUserId,
        lastMsg: allMessages.last,
        hasUnseen:
            allMessages.any((m) => m.receiverId == currentUid && !m.isSeen),
      );
    }

    return allMessages;
  }

  void _syncContactLastMessage({
    required String currentUid,
    required String receiverUserId,
    required OneToOneMessageModel lastMsg,
    required bool hasUnseen,
  }) {
    String formatted;
    switch (lastMsg.messageType) {
      case "image":
        formatted = "📷 Photo";
        break;
      case "video":
        formatted = "🎥 Video";
        break;
      case "gif":
        formatted = "🎮 Gif";
        break;
      case "document":
        formatted =
            "📄 ${lastMsg.text.isNotEmpty ? lastMsg.text : 'Document'}";
        break;
      case "location":
        formatted = "📍 Location";
        break;
      case "live_location":
        formatted = "📡 Live Location";
        break;
      default:
        formatted = lastMsg.text.trim().isNotEmpty
            ? lastMsg.text.trim()
            : "New message";
    }

    // 1. Update Firestore contact doc for current user (best effort)
    fireStore
        .collection('users')
        .doc(currentUid)
        .collection('chats')
        .doc(receiverUserId)
        .set({
      'lastMessage': formatted,
      'timeSent': lastMsg.timeSent.millisecondsSinceEpoch,
      'unseenCount': hasUnseen,
    }, SetOptions(merge: true)).catchError((e) {
      log('Note: Error updating contact lastMessage in Firestore: $e');
    });

    // 2. Update local Hive contacts_cache
    try {
      if (Hive.isBoxOpen('contacts_cache')) {
        final contactsBox = Hive.box('contacts_cache');
        final cacheKey = 'user_chats_$currentUid';
        final cachedRaw = contactsBox.get(cacheKey, defaultValue: []);
        if (cachedRaw is List) {
          final List<Map<String, dynamic>> contactMaps = [];
          for (final item in cachedRaw) {
            if (item is Map) {
              contactMaps.add(Map<String, dynamic>.from(item));
            }
          }
          final idx =
              contactMaps.indexWhere((c) => c['uid'] == receiverUserId);
          if (idx >= 0) {
            contactMaps[idx]['lastMessage'] = formatted;
            contactMaps[idx]['timeSent'] =
                lastMsg.timeSent.millisecondsSinceEpoch;
            contactMaps[idx]['unseenCount'] = hasUnseen;
            contactMaps.sort((a, b) {
              final tA = a['timeSent'] as int? ?? 0;
              final tB = b['timeSent'] as int? ?? 0;
              return tB.compareTo(tA);
            });
            contactsBox.put(cacheKey, contactMaps);
          }
        }
      }
    } catch (_) {}
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

  /// Fire-and-forget: marks undelivered incoming messages as delivered.
  /// Runs via microtask so it does NOT block stream emission or cause
  /// the stream to re-trigger from the resulting Firestore writes.
  void _acknowledgeDelivery(
    List<OneToOneMessageModel> messages,
    String currentUserId,
  ) {
    final undelivered = messages
        .where((m) => m.receiverId == currentUserId && !m.isDelivered && !m.isSeen)
        .toList();
    if (undelivered.isEmpty) return;
    Future.microtask(() async {
      for (final m in undelivered) {
        _markMessageAsDelivered(m.senderId, currentUserId, m.messageId);
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
          .set({'chatBackgroundUrl': backgroundUrl}, SetOptions(merge: true));

      await fireStore
          .collection('users')
          .doc(receiverUserId)
          .collection('chats')
          .doc(currentUserId)
          .set({'chatBackgroundUrl': backgroundUrl}, SetOptions(merge: true));
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
      case "document":
        lastMessage = "📄 ${text.isNotEmpty ? text : 'Document'}";
        break;
      case "location":
        lastMessage = "📍 Location";
        break;
      case "live_location":
        lastMessage = "📡 Live Location";
        break;
      default:
        lastMessage = text.trim().isNotEmpty ? text.trim() : "New message";
    }

    final currentUserId = auth.currentUser?.uid;
    if (currentUserId == null) return;

    try {
      final myToken = await FirebaseMessaging.instance.getToken() ?? '';

      // The receiver's contact entry on the receiver's device should keep their own wallpaper.
      // Passing null ensures toMap() omits chatBackgroundUrl so merge: true never overwrites it.
      var receiverChatContact = ChatContact(
        name: senderUserData.name ?? 'User',
        profilePic: senderUserData.profilePic,
        uid: currentUserId,
        timeSent: timeSent,
        lastMessage: lastMessage,
        fcmToken: myToken,
        unseenCount: true,
        chatBackgroundUrl: null,
      );

      await fireStore
          .collection('users')
          .doc(receiverUserId)
          .collection('chats')
          .doc(currentUserId)
          .set(receiverChatContact.toMap(), SetOptions(merge: true));

      // The sender's contact entry updates chatBackgroundUrl only if non-null and non-empty.
      final validBg = (chatBackgroundUrl != null && chatBackgroundUrl.trim().isNotEmpty)
          ? chatBackgroundUrl.trim()
          : null;

      var senderChatContact = ChatContact(
        name: receiverUserData?.name ?? 'User',
        profilePic: receiverUserData?.profilePic,
        uid: receiverUserId,
        timeSent: timeSent,
        lastMessage: lastMessage,
        fcmToken: fcmToken,
        unseenCount: false,
        chatBackgroundUrl: validBg,
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
          : (messageReply.messageType == 'text' || messageReply.messageType == 'wish')
          ? messageReply.message
          : (messageReply.message.isNotEmpty && messageReply.fileMessageData.isEmpty)
          ? messageReply.message
          : messageReply.fileMessageData,
      repliedTo: messageReply == null
          ? ''
          : (messageReply.repliedTo != null && messageReply.repliedTo!.isNotEmpty)
          ? messageReply.repliedTo!
          : messageReply.isMe
          ? senderUsername
          : receiverUserName ?? '',
      repliedMessageType: messageReplyType,
    );

    try {
      final senderMessageRef = fireStore
          .collection('users')
          .doc(currentUserId)
          .collection('chats')
          .doc(receiverUserId)
          .collection('messages')
          .doc(messageId);

      final receiverMessageRef = fireStore
          .collection('users')
          .doc(receiverUserId)
          .collection('chats')
          .doc(currentUserId)
          .collection('messages')
          .doc(messageId);

      // Save sender message first so sender's own chat is 100% saved
      await senderMessageRef.set(message.toMap());

      // Then save receiver message
      try {
        await receiverMessageRef.set(message.toMap());
      } catch (e) {
        log('⚠️ Could not save message to receiver chats (rules/cloud function): $e');
      }

      log('✅ Message saved successfully');

      if (fcmToken.isNotEmpty) {
        _sendNotificationAsync(
          fcmToken: fcmToken,
          name: name,
          messageType: messageType,
          text: text,
          messageReply: messageReply,
          senderUid: senderUid,
          senderProfilePic: senderProfilePic,
          messageId: messageId,
          timeSent: timeSent,
          receiverUserId: receiverUserId,
          fileMessageData: fileMessageData,
          senderUsername: senderUsername,
          receiverUserName: receiverUserName,
          messageReplyType: messageReplyType,
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
    required String messageId,
    required DateTime timeSent,
    required String receiverUserId,
    String? fileMessageData,
    String? senderUsername,
    String? receiverUserName,
    String? messageReplyType,
  }) {
    Future.microtask(() async {
      try {
        String body;

        if (messageReply != null) {
          switch (messageReply.messageType) {
            case 'story':
              body = '💬 Replied to your story: "$text"';
              break;
            case 'text':
            case 'wish':
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
            case 'document':
              body = '📄 ${text.isNotEmpty ? text : 'Document'}';
              break;
            case 'location':
              body = '📍 Location';
              break;
            case 'live_location':
              body = '📡 Live Location';
              break;
            default:
              body = '📎 Media message';
          }
        }

        final isWish = messageReply == null &&
            WishHelper.isWish(messageType: messageType, text: text);

        final safeName = name.trim().isNotEmpty ? name.trim() : 'New Message';

        final String finalTitle = isWish
            ? WishHelper.getNotificationTitle(senderName: safeName, text: text)
            : safeName;

        final String finalBody = isWish
            ? WishHelper.getNotificationBody(senderName: safeName, text: text)
            : body;

        await sendNotification(
          fcmToken,
          finalTitle,
          finalBody,
          data: {
            'type': 'chat',
            'senderUid': senderUid,
            'receiverId': receiverUserId,
            'name': safeName,
            'profilePic': senderProfilePic,
            'tag': senderUid,
            'messageId': messageId,
            'messageType': messageType,
            'text': text,
            'timeSent': timeSent.toIso8601String(),
            if (fileMessageData != null && fileMessageData.isNotEmpty)
              'fileMessageData': fileMessageData,
            if (messageReply != null) ...{
              'repliedMessage': messageReply.message,
              'repliedTo': (messageReply.repliedTo != null && messageReply.repliedTo!.isNotEmpty)
                  ? messageReply.repliedTo!
                  : messageReply.isMe
                  ? (senderUsername ?? '')
                  : (receiverUserName ?? ''),
              'repliedMessageType':
                  messageReplyType ?? messageReply.messageType,
            },
            if (isWish) 'isWish': 'true',
            if (isWish) 'wishCategory': WishHelper.getWishCategory(text).name,
          },
        );
        log('✅ Notification sent successfully (isWish: $isWish)');
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
    String? groupId,
  }) async {
    try {
      final currentUserId = auth.currentUser?.uid;
      if (currentUserId == null) {
        throw Exception('User not authenticated');
      }

      var messageId = const Uuid().v1();
      var timeSent = DateTime.now();

      // Immediately save optimistic message to local Hive with isSending: true (clock icon)
      String? optimisticFileData;
      if (groupId != null && groupId.isNotEmpty && file is File) {
        optimisticFileData = jsonEncode({'url': file.path, 'groupId': groupId});
      } else if (file is File) {
        optimisticFileData = file.path;
      } else if (file is String) {
        optimisticFileData = file;
      }

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
        fileMessageData: optimisticFileData,
        repliedMessage: messageReply == null
            ? ''
            : (messageReply.messageType == 'text' || messageReply.messageType == 'wish')
            ? messageReply.message
            : (messageReply.message.isNotEmpty && messageReply.fileMessageData.isEmpty)
            ? messageReply.message
            : messageReply.fileMessageData,
        repliedTo: messageReply == null
            ? ''
            : (messageReply.repliedTo != null && messageReply.repliedTo!.isNotEmpty)
            ? messageReply.repliedTo!
            : messageReply.isMe
            ? 'You'
            : '',
        repliedMessageType: messageReply == null ? 'text' : messageReply.messageType,
      );
      _saveOptimisticMessageToHive(currentUserId, receiverUserId, optimisticMessage);


      String? fileData;

      Future<void> performSend(
        void Function(String message, {int? progress, int? maxProgress}) updateProgress,
      ) async {
        if (messageType == "image" && file != null) {
          if (file is File) {
            log("📤 Uploading image for message: $messageId");
            fileData = await uploadImageToCloudinary(
              file,
              type,
              onProgress: (sent, total) {
                final pct = total > 0 ? (sent / total * 100).toInt() : 0;
                updateProgress('Uploading image ($pct%)...', progress: sent, maxProgress: total);
              },
            );
            log("✅ Image uploaded: $fileData");
            if (fileData != null && fileData!.isNotEmpty) {
              MediaCacheService().registerLocalMapping(fileData!, file.path);
            }
          } else if (file is String) {
            fileData = file;
          }
        } else if (messageType == "video" && file != null) {
          if (file is File) {
            log("📤 Uploading video for message: $messageId");
            fileData = await uploadVideoToCloudinary(
              file,
              type,
              onProgress: (sent, total) {
                final pct = total > 0 ? (sent / total * 100).toInt() : 0;
                updateProgress('Uploading video ($pct%)...', progress: sent, maxProgress: total);
              },
            );
            log("✅ Video uploaded: $fileData");
            if (fileData != null && fileData!.isNotEmpty) {
              MediaCacheService().registerLocalMapping(fileData!, file.path);
            }
          } else if (file is String) {
            fileData = file;
          }
        } else if (messageType == "gif" && file != null) {
          if (file is File) {
            log("📤 Uploading GIF for message: $messageId");
            fileData = await uploadImageToCloudinary(
              file,
              type,
              onProgress: (sent, total) {
                final pct = total > 0 ? (sent / total * 100).toInt() : 0;
                updateProgress('Uploading GIF ($pct%)...', progress: sent, maxProgress: total);
              },
            );
            log("✅ GIF uploaded: $fileData");
            if (fileData != null && fileData!.isNotEmpty) {
              MediaCacheService().registerLocalMapping(fileData!, file.path);
            }
          } else if (file is String) {
            fileData = file;
          }
        } else if (messageType == "document" && file != null) {
          if (file is File) {
            log("📤 Uploading document for message: $messageId");
            fileData = await uploadDocumentToCloudinary(
              file,
              type,
              onProgress: (sent, total) {
                final pct = total > 0 ? (sent / total * 100).toInt() : 0;
                updateProgress('Uploading document ($pct%)...', progress: sent, maxProgress: total);
              },
            );
            log("✅ Document uploaded: $fileData");
            if (fileData != null && fileData!.isNotEmpty) {
              MediaCacheService().registerLocalMapping(fileData!, file.path);
            }
          } else if (file is String) {
            fileData = file;
          }
        } else if (messageType == "location" || messageType == "live_location") {
          if (file is String) {
            fileData = file;
          }
        } else if (file is String) {
          fileData = file;
        }

        // Embed groupId into fileMessageData for grouped-media support
        if (groupId != null && groupId.isNotEmpty && fileData != null) {
          try {
            // fileData is already a URL string for image/video/gif
            // Wrap it in JSON: {"url": "...", "groupId": "..."}
            final existing = jsonDecode(fileData!);
            if (existing is Map) {
              // Already JSON (e.g. location), just add groupId
              final map = Map<String, dynamic>.from(existing);
              map['groupId'] = groupId;
              fileData = jsonEncode(map);
            }
          } catch (_) {
            // Plain URL string – wrap it
            fileData = jsonEncode({'url': fileData, 'groupId': groupId});
          }
        } else if (groupId != null && groupId.isNotEmpty && file is File) {
          // Still uploading – local path fallback with groupId
          fileData = jsonEncode({'url': file.path, 'groupId': groupId});
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

        updateProgress('Saving message...');

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
      }

      final isMediaUpload = file is File;
      if (isMediaUpload) {
        await BackgroundTaskService.instance.runWithBackgroundTask(
          title: 'Sending $messageType',
          initialMessage: 'Uploading $messageType...',
          successMessage: '${messageType[0].toUpperCase()}${messageType.substring(1)} sent',
          task: (updateProgress) => performSend(updateProgress),
        );
      } else {
        await performSend((_, {progress, maxProgress}) {});
      }

      log('✅ Message saved with ID: $messageId');

      if (messageType == 'live_location' && fileData != null) {
        try {
          final liveMap = jsonDecode(fileData!) as Map<String, dynamic>;
          final liveUntil = liveMap['liveUntil'] as int?;
          if (liveUntil != null) {
            final durationMs = liveUntil - DateTime.now().millisecondsSinceEpoch;
            if (durationMs > 0) {
              LocationService.instance.startLiveLocationTracking(
                messageId: messageId,
                currentUserId: currentUserId,
                receiverId: receiverUserId,
                duration: Duration(milliseconds: durationMs),
              );
            }
          }
        } catch (e) {
          log('Error starting live tracking: $e');
        }
      }
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
      final messages = _safeCastMessages(cachedData);
      final existingIndex = messages.indexWhere((m) => m.messageId == message.messageId);
      if (existingIndex >= 0) {
        messages[existingIndex] = message;
      } else {
        messages.add(message);
      }
      await box.put(localKey, messages);
      log('🕒 Saved optimistic sending message to Hive: ${message.messageId}');

      // Immediately notify active chat listeners so the bubble appears in 0ms!
      final listeners = _activeChatListeners[localKey];
      if (listeners != null) {
        final msgsCopy = List<OneToOneMessageModel>.from(messages);
        for (final listener in List.from(listeners)) {
          listener(msgsCopy);
        }
      }
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
        final messages = _safeCastMessages(cachedData);
        messages.removeWhere((m) => m.isSending);
        await box.put(localKey, messages);

        final listeners = _activeChatListeners[localKey];
        if (listeners != null) {
          final msgsCopy = List<OneToOneMessageModel>.from(messages);
          for (final listener in List.from(listeners)) {
            listener(msgsCopy);
          }
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

      // ✅ Dismiss any notification for this chat
      FirebaseNotificationService.cancelNotificationsForChat(receiverUserId);

      log('✅ Message marked as seen');
    } catch (e) {
      log('❌ Error in setChatMessageSeen: $e');
    }
  }

  /// Mark all unread messages in the chat as seen and clear the unseen badge
  Future<void> markChatAsSeen(String partnerUserId) async {
    final currentUserId = auth.currentUser?.uid;
    if (currentUserId == null || partnerUserId.isEmpty) return;

    FirebaseNotificationService.cancelNotificationsForChat(partnerUserId);

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

  Future<void> toggleReaction({
    required String messageId,
    required String receiverUserId,
    required String emoji,
  }) async {
    final currentUserId = auth.currentUser?.uid;
    if (currentUserId == null) return;

    final localKey = '${currentUserId}_$receiverUserId';

    // 1. Optimistically update local Hive cache for instant 0ms feedback
    try {
      if (Hive.isBoxOpen('messages')) {
        final box = Hive.box('messages');
        final cachedData = box.get(localKey, defaultValue: []);
        final messages = _safeCastMessages(cachedData);
        final idx = messages.indexWhere((m) => m.messageId == messageId);
        if (idx >= 0) {
          final oldMsg = messages[idx];
          final updatedReactions = Map<String, String>.from(oldMsg.reactions);
          if (updatedReactions[currentUserId] == emoji) {
            updatedReactions.remove(currentUserId);
          } else {
            updatedReactions[currentUserId] = emoji;
          }
          messages[idx] = oldMsg.copyWith(reactions: updatedReactions);
          await box.put(localKey, messages);
        }
      }
    } catch (e) {
      log('Error optimistically updating reaction in Hive: $e');
    }

    // 2. Persist to Firestore
    try {
      final senderMsgRef = fireStore
          .collection('users')
          .doc(currentUserId)
          .collection('chats')
          .doc(receiverUserId)
          .collection('messages')
          .doc(messageId);

      final receiverMsgRef = fireStore
          .collection('users')
          .doc(receiverUserId)
          .collection('chats')
          .doc(currentUserId)
          .collection('messages')
          .doc(messageId);

      final snapshot = await senderMsgRef.get();
      if (!snapshot.exists) return;

      final data = snapshot.data();
      final reactions = (data?['reactions'] is Map)
          ? Map<String, dynamic>.from(data!['reactions'] as Map)
          : <String, dynamic>{};

      final isRemoving = reactions[currentUserId] == emoji;

      // Update sender doc first (always has permissions)
      try {
        if (isRemoving) {
          await senderMsgRef.update({'reactions.$currentUserId': FieldValue.delete()});
        } else {
          await senderMsgRef.update({'reactions.$currentUserId': emoji});
        }
      } catch (e) {
        log('❌ Error updating sender reaction: $e');
      }

      // Update receiver doc (best effort in case rules or network prevent cross-user write)
      try {
        if (isRemoving) {
          await receiverMsgRef.update({'reactions.$currentUserId': FieldValue.delete()});
        } else {
          await receiverMsgRef.update({'reactions.$currentUserId': emoji});
        }
      } catch (e) {
        log('⚠️ Notice updating receiver reaction: $e');
      }

      log('✅ Reaction updated: $emoji on message $messageId');
    } catch (e) {
      log('❌ Error toggling reaction: $e');
    }
  }

  Future<void> editMessage({
    required String messageId,
    required String receiverUserId,
    required String newText,
  }) async {
    final currentUserId = auth.currentUser?.uid;
    if (currentUserId == null || newText.trim().isEmpty) return;

    final trimmedText = newText.trim();
    final localKey = '${currentUserId}_$receiverUserId';

    // 1. Optimistically update local Hive cache (0ms)
    try {
      if (Hive.isBoxOpen('messages')) {
        final box = Hive.box('messages');
        final cachedData = box.get(localKey, defaultValue: []);
        final messages = _safeCastMessages(cachedData);
        final idx = messages.indexWhere((m) => m.messageId == messageId);
        if (idx >= 0) {
          messages[idx] = messages[idx].copyWith(
            text: trimmedText,
            isEdited: true,
          );
          await box.put(localKey, messages);
          notifyChatListeners(localKey, messages);
        }
      }
    } catch (e) {
      log('❌ Error updating Hive cache for edited message: $e');
    }

    // 2. Persist to Firestore
    try {
      final senderMsgRef = fireStore
          .collection('users')
          .doc(currentUserId)
          .collection('chats')
          .doc(receiverUserId)
          .collection('messages')
          .doc(messageId);

      final receiverMsgRef = fireStore
          .collection('users')
          .doc(receiverUserId)
          .collection('chats')
          .doc(currentUserId)
          .collection('messages')
          .doc(messageId);

      await senderMsgRef.update({
        'text': trimmedText,
        'isEdited': true,
      });

      try {
        await receiverMsgRef.update({
          'text': trimmedText,
          'isEdited': true,
        });
      } catch (e) {
        log('⚠️ Notice updating receiver doc for edit: $e');
      }
    } catch (e) {
      log('❌ Error editing message in Firestore: $e');
    }
  }

  Future<void> togglePinMessage({
    required String messageId,
    required String receiverUserId,
    required bool pin,
  }) async {
    final currentUserId = auth.currentUser?.uid;
    if (currentUserId == null) return;

    final now = DateTime.now();
    final localKey = '${currentUserId}_$receiverUserId';

    // 1. Optimistically update local Hive cache for instant banner/badge feedback
    try {
      if (Hive.isBoxOpen('messages')) {
        final box = Hive.box('messages');
        final cachedData = box.get(localKey, defaultValue: []);
        final messages = _safeCastMessages(cachedData);
        final idx = messages.indexWhere((m) => m.messageId == messageId);
        if (idx >= 0) {
          messages[idx] = pin
              ? messages[idx].copyWith(
                  isPinned: true,
                  pinnedAt: now,
                  pinnedBy: currentUserId,
                )
              : messages[idx].copyWith(clearPin: true);
          await box.put(localKey, messages);
          notifyChatListeners(localKey, messages);
        }
      }
    } catch (e) {
      log('❌ Error updating Hive cache for pinned message: $e');
    }

    // 2. Persist to Firestore
    final payload = <String, dynamic>{
      'isPinned': pin,
      'pinnedAt': pin ? now.millisecondsSinceEpoch : null,
      'pinnedBy': pin ? currentUserId : null,
    };

    try {
      final senderMsgRef = fireStore
          .collection('users')
          .doc(currentUserId)
          .collection('chats')
          .doc(receiverUserId)
          .collection('messages')
          .doc(messageId);
      await senderMsgRef.update(payload);

      try {
        final receiverMsgRef = fireStore
            .collection('users')
            .doc(receiverUserId)
            .collection('chats')
            .doc(currentUserId)
            .collection('messages')
            .doc(messageId);
        await receiverMsgRef.update(payload);
      } catch (e) {
        log('⚠️ Notice updating receiver doc for pin: $e');
      }
    } catch (e) {
      log('❌ Error updating pin state in Firestore: $e');
    }
  }

  Future<void> deleteMessageForMe({
    required String messageId,
    required String receiverUserId,
  }) async {
    final currentUserId = auth.currentUser?.uid;
    if (currentUserId == null) return;

    final localKey = '${currentUserId}_$receiverUserId';

    // 1. Optimistically remove from local Hive cache (0ms)
    try {
      if (Hive.isBoxOpen('messages')) {
        final box = Hive.box('messages');
        final cachedData = box.get(localKey, defaultValue: []);
        final messages = _safeCastMessages(cachedData);
        messages.removeWhere((m) => m.messageId == messageId);
        await box.put(localKey, messages);
        notifyChatListeners(localKey, messages);
      }
    } catch (e) {
      log('❌ Error removing from Hive cache for deleteForMe: $e');
    }

    // 2. Add currentUserId to deletedFor in Firestore
    try {
      final senderMsgRef = fireStore
          .collection('users')
          .doc(currentUserId)
          .collection('chats')
          .doc(receiverUserId)
          .collection('messages')
          .doc(messageId);

      await senderMsgRef.update({
        'deletedFor': FieldValue.arrayUnion([currentUserId]),
      });
    } catch (e) {
      log('❌ Error updating deletedFor in Firestore: $e');
    }
  }

  Future<void> deleteMessageForEveryone({
    required String messageId,
    required String receiverUserId,
  }) async {
    final currentUserId = auth.currentUser?.uid;
    if (currentUserId == null) return;

    final localKey = '${currentUserId}_$receiverUserId';

    // 1. Optimistically update local Hive cache (0ms)
    try {
      if (Hive.isBoxOpen('messages')) {
        final box = Hive.box('messages');
        final cachedData = box.get(localKey, defaultValue: []);
        final messages = _safeCastMessages(cachedData);
        final idx = messages.indexWhere((m) => m.messageId == messageId);
        if (idx >= 0) {
          messages[idx] = messages[idx].copyWith(
            text: 'This message was deleted',
            isDeleted: true,
            reactions: {},
          );
          await box.put(localKey, messages);
          notifyChatListeners(localKey, messages);
        }
      }
    } catch (e) {
      log('❌ Error updating Hive cache for deleteForEveryone: $e');
    }

    // 2. Persist to Firestore
    try {
      final senderMsgRef = fireStore
          .collection('users')
          .doc(currentUserId)
          .collection('chats')
          .doc(receiverUserId)
          .collection('messages')
          .doc(messageId);

      final receiverMsgRef = fireStore
          .collection('users')
          .doc(receiverUserId)
          .collection('chats')
          .doc(currentUserId)
          .collection('messages')
          .doc(messageId);

      final deleteData = {
        'text': 'This message was deleted',
        'isDeleted': true,
        'reactions': {},
        'fileMessageData': null,
      };

      await senderMsgRef.update(deleteData);

      try {
        await receiverMsgRef.update(deleteData);
      } catch (e) {
        log('⚠️ Notice updating receiver doc for deleteForEveryone: $e');
      }
    } catch (e) {
      log('❌ Error updating deleteForEveryone in Firestore: $e');
    }
  }
}
