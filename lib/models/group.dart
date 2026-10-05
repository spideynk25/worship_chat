// Complete GroupModel class with the hasUnseenForUser method

import 'package:worship_chat/features/group/utils/group_template_helper.dart';

class GroupModel {
  final String senderId;
  final String name;
  final String groupId;
  final String lastMessage;
  final String groupPic;
  final List<String> membersUid;
  final DateTime? timeSent;
  final List<String> fcmTokens;
  final Map<String, dynamic> unseenMessages;
  final String? queendom;
  final int? order;
  final int? priority;
  final String? family;
  final String? position;
  final String? chatBackgroundUrl;
  final String? wish;
  final String? livingPlace;
  final int galleryCount;
  final String? parentGroupId;
  final String? parentGroupName;
  final bool isSubGroup;
  final String? subGroupType;

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
    this.priority,
    this.chatBackgroundUrl,
    this.wish,
    this.livingPlace,
    this.galleryCount = 0,
    this.parentGroupId,
    this.parentGroupName,
    this.isSubGroup = false,
    this.subGroupType,
  });

  /// Helper getter to get living place or fallback to name
  String get effectiveLivingPlace =>
      (livingPlace != null && livingPlace!.trim().isNotEmpty)
          ? livingPlace!
          : name;

  /// Helper getter to get deity/member name with position (e.g. Queen Pooja, Princess Krithi, Wife of Queen Pooja - Samantha, Fuck Toy of Queen Pooja - Samantha)
  String get nameWithPosition => GroupTemplateHelper.getNameWithPosition(
        name: name,
        position: position,
        family: family,
        isSubGroup: isSubGroup,
        parentGroupName: parentGroupName,
        subGroupType: subGroupType,
      );

  bool get isFuckToySubGroup =>
      isSubGroup &&
      (subGroupType == 'fuckToy' ||
          subGroupType == 'fuck_toy' ||
          subGroupType == 'fuck toy');

  bool get isWifeSubGroup => isSubGroup && !isFuckToySubGroup;

  String get subGroupDisplayCategory =>
      isFuckToySubGroup ? 'Fuck Toy' : 'Wife';

  // Helper method to check if a specific user has unseen messages
  bool hasUnseenForUser(String userId) {
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
      'order': priority ?? order,
      'priority': priority ?? order,
      'family': family,
      'position': position,
      'chatBackgroundUrl': chatBackgroundUrl,
      'wish': wish,
      'livingPlace': livingPlace,
      'galleryCount': galleryCount,
      'parentGroupId': parentGroupId,
      'parentGroupName': parentGroupName,
      'isSubGroup': isSubGroup,
      'subGroupType': subGroupType,
    };
  }

  @override
  String toString() {
    return lastMessage;
  }

  GroupModel copyWith({
    String? senderId,
    String? name,
    String? groupId,
    String? lastMessage,
    String? groupPic,
    List<String>? membersUid,
    DateTime? timeSent,
    List<String>? fcmTokens,
    Map<String, dynamic>? unseenMessages,
    String? queendom,
    int? order,
    int? priority,
    String? family,
    String? position,
    String? chatBackgroundUrl,
    String? wish,
    String? livingPlace,
    int? galleryCount,
    String? parentGroupId,
    String? parentGroupName,
    bool? isSubGroup,
    String? subGroupType,
  }) {
    return GroupModel(
      senderId: senderId ?? this.senderId,
      name: name ?? this.name,
      groupId: groupId ?? this.groupId,
      lastMessage: lastMessage ?? this.lastMessage,
      groupPic: groupPic ?? this.groupPic,
      membersUid: membersUid ?? this.membersUid,
      timeSent: timeSent ?? this.timeSent,
      fcmTokens: fcmTokens ?? this.fcmTokens,
      unseenMessages: unseenMessages ?? this.unseenMessages,
      queendom: queendom ?? this.queendom,
      order: order ?? this.order,
      priority: priority ?? this.priority,
      family: family ?? this.family,
      position: position ?? this.position,
      chatBackgroundUrl: chatBackgroundUrl ?? this.chatBackgroundUrl,
      wish: wish ?? this.wish,
      livingPlace: livingPlace ?? this.livingPlace,
      galleryCount: galleryCount ?? this.galleryCount,
      parentGroupId: parentGroupId ?? this.parentGroupId,
      parentGroupName: parentGroupName ?? this.parentGroupName,
      isSubGroup: isSubGroup ?? this.isSubGroup,
      subGroupType: subGroupType ?? this.subGroupType,
    );
  }

  factory GroupModel.fromMap(Map<String, dynamic> map) {
    // Handle backward compatibility
    Map<String, dynamic> unseenMap = {};

    if (map.containsKey('unseenMessages') && map['unseenMessages'] != null) {
      unseenMap = Map<String, dynamic>.from(map['unseenMessages']);
    } else if (map.containsKey('unseenCount')) {
      final bool oldUnseenCount = map['unseenCount'] as bool? ?? false;
      final senderId = map['senderId'] as String?;
      final members = map['membersUid'] != null
          ? List<String>.from(map['membersUid'])
          : <String>[];

      for (var uid in members) {
        if (uid != senderId) {
          unseenMap[uid] = oldUnseenCount;
        } else {
          unseenMap[uid] = false;
        }
      }
    }

    final priorityVal =
        (map['priority'] as num?)?.toInt() ?? (map['order'] as num?)?.toInt();

    final parentGrpId = map['parentGroupId'] as String?;
    final isSubGrp = (map['isSubGroup'] as bool?) ??
        (parentGrpId != null && parentGrpId.isNotEmpty);

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
      order: priorityVal,
      priority: priorityVal,
      family: map['family'],
      position: map['position'],
      chatBackgroundUrl: map['chatBackgroundUrl'],
      wish: map['wish'],
      livingPlace: map['livingPlace'] as String?,
      galleryCount: (map['galleryCount'] as num?)?.toInt() ?? 0,
      parentGroupId: parentGrpId,
      parentGroupName: map['parentGroupName'] as String?,
      isSubGroup: isSubGrp,
      subGroupType: map['subGroupType'] as String?,
    );
  }
}
