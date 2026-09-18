import 'dart:developer';

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

  factory ChatContact.fromMap(Map<String, dynamic> map) {
    log("map $map");
    return ChatContact(
      name: map['name'] as String,
      profilePic: map['profilePic'] ?? "",
      uid: map['uid'] as String,
      timeSent: map.containsKey('timeSent')
          ? DateTime.fromMillisecondsSinceEpoch(map['timeSent'])
          : DateTime.now(),
      lastMessage: map['lastMessage'] ?? " ",
      fcmToken: map['fcmToken'] ?? "",
      unseenCount: map['unseenCount'] ?? false,
      chatBackgroundUrl: map['chatBackgroundUrl'] ?? "",
    );
  }
}
