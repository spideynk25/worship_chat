// Complete GroupModel class with the hasUnseenForUser method

class GroupModel {
  final String senderId;
  final String name;
  final String groupId;
  final String lastMessage;
  final String groupPic;
  final List<String> membersUid;
  final DateTime? timeSent;
  final List<String> fcmTokens;
  final Map<String, dynamic>
  unseenMessages; // Changed to dynamic for flexibility
  final String? queendom;
  final int? order;
  final String? family;
  final String? position;
  final String? chatBackgroundUrl;
  final String? wish;

  GroupModel({
    required this.senderId,
    required this.name,
    required this.groupId,
    required this.lastMessage,
    required this.groupPic,
    required this.membersUid,
    this.timeSent,
    required this.fcmTokens,
    required this.unseenMessages,
    this.queendom,
    this.family,
    this.position,
    this.order,
    this.chatBackgroundUrl,
    this.wish,
  });

  // Helper method to check if a specific user has unseen messages
  bool hasUnseenForUser(String userId) {
    // Check if the user has unseen messages (true) or not
    return unseenMessages[userId] == true;
  }

  Map<String, dynamic> toMap() {
    return {
      'senderId': senderId,
      'name': name,
      'groupId': groupId,
      'lastMessage': lastMessage,
      'groupPic': groupPic,
      'membersUid': membersUid,
      'timeSent': timeSent?.millisecondsSinceEpoch,
      'fcmTokens': fcmTokens,
      'unseenMessages': unseenMessages,
      'queendom': queendom,
      'order': order,
      'family': family,
      'position': position,
      'chatBackgroundUrl': chatBackgroundUrl,
      'wish': wish,
    };
  }

  @override
  String toString() {
    return "$lastMessage";
  }

  factory GroupModel.fromMap(Map<String, dynamic> map) {
    // Handle backward compatibility
    Map<String, dynamic> unseenMap = {};

    if (map.containsKey('unseenMessages') && map['unseenMessages'] != null) {
      // New format - directly use the map
      unseenMap = Map<String, dynamic>.from(map['unseenMessages']);
    } else if (map.containsKey('unseenCount')) {
      // Old format (boolean) - convert to map format
      final bool oldUnseenCount = map['unseenCount'] as bool? ?? false;
      final senderId = map['senderId'] as String?;
      final members = map['membersUid'] != null
          ? List<String>.from(map['membersUid'])
          : <String>[];

      // Set unseen for all members except sender
      for (var uid in members) {
        if (uid != senderId) {
          unseenMap[uid] = oldUnseenCount;
        } else {
          unseenMap[uid] = false;
        }
      }
    }

    return GroupModel(
      senderId: map['senderId'] ?? '',
      name: map['name'] ?? '',
      groupId: map['groupId'] ?? '',
      lastMessage: map['lastMessage'] ?? '',
      groupPic: map['groupPic'] ?? '',
      membersUid: map['membersUid'] != null
          ? List<String>.from(map['membersUid'])
          : [],
      timeSent: map['timeSent'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['timeSent'])
          : null,
      fcmTokens: map['fcmTokens'] != null
          ? List<String>.from(map['fcmTokens'])
          : [],
      unseenMessages: unseenMap,
      queendom: map['queendom'],
      order: map['order'],
      family: map['family'],
      position: map['position'],
      chatBackgroundUrl: map['chatBackgroundUrl'],
      wish: map['wish'],
    );
  }
}
