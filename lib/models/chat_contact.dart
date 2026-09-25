import 'package:cloud_firestore/cloud_firestore.dart';

// ignore_for_file: public_member_api_docs, sort_constructors_first
class ChatContact {
  final String name;
  final String? profilePic;
  final String uid;
  final DateTime? timeSent;
  final String? lastMessage;
  final String? fcmToken;
  final bool? unseenCount;
  final String? chatBackgroundUrl;

  ChatContact({
    required this.name,
    required this.profilePic,
    required this.uid,
    required this.timeSent,
    required this.lastMessage,
    required this.fcmToken,
    required this.unseenCount,
    required this.chatBackgroundUrl
  });

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'name': name,
      'profilePic': profilePic,
      'uid': uid,
      'timeSent': timeSent?.millisecondsSinceEpoch,
      'lastMessage': lastMessage,
      'fcmToken': fcmToken,
      'unseenCount': unseenCount,
      'chatBackgroundUrl': chatBackgroundUrl,
    };
  }

  factory ChatContact.fromMap(Map<String, dynamic> map, {String? documentId}) {
    DateTime parsedTime;
    final rawTime = map['timeSent'];
    if (rawTime is int) {
      parsedTime = DateTime.fromMillisecondsSinceEpoch(rawTime);
    } else if (rawTime is Timestamp) {
      parsedTime = rawTime.toDate();
    } else if (rawTime is String) {
      final asInt = int.tryParse(rawTime);
      if (asInt != null) {
        parsedTime = DateTime.fromMillisecondsSinceEpoch(asInt);
      } else {
        parsedTime = DateTime.tryParse(rawTime) ?? DateTime.now();
      }
    } else {
      parsedTime = DateTime.now();
    }

    final rawUid = (map['uid'] != null && map['uid'].toString().trim().isNotEmpty)
        ? map['uid'].toString().trim()
        : (map['contactId'] != null && map['contactId'].toString().trim().isNotEmpty)
            ? map['contactId'].toString().trim()
            : (documentId != null && documentId.trim().isNotEmpty)
                ? documentId.trim()
                : "";

    return ChatContact(
      name: map['name']?.toString() ?? 'User',
      profilePic: map['profilePic']?.toString() ?? "",
      uid: rawUid,
      timeSent: parsedTime,
      lastMessage: map['lastMessage']?.toString() ?? "",
      fcmToken: map['fcmToken']?.toString() ?? "",
      unseenCount: map['unseenCount'] as bool? ?? false,
      chatBackgroundUrl: map['chatBackgroundUrl']?.toString() ?? "",
    );
  }
}
