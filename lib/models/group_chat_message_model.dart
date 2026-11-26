// ignore_for_file: public_member_api_docs, sort_constructors_first

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';

part 'group_chat_message_model.g.dart';

@HiveType(typeId: 2)
class GroupChatMessageModel {
  @HiveField(0)
  final String senderId;
  
  @HiveField(1)
  final List<String> receiverIds;
  
  @HiveField(2)
  final String groupId;
  
  @HiveField(3)
  final String text;
  
  @HiveField(4)
  final String messageType;
  
  @HiveField(5)
  final DateTime timeSent;
  
  @HiveField(6)
  final String messageId;
  
  @HiveField(7)
  final bool? _isSeen;
  bool get isSeen => _isSeen ?? false;
  
  @HiveField(8)
  String? fileMessageData;
  
  @HiveField(9)
  final String repliedMessage;
  
  @HiveField(10)
  final String repliedTo;
  
  @HiveField(11)
  final String repliedMessageType;

  @HiveField(12)
  final bool? _isDelivered;
  bool get isDelivered => _isDelivered ?? false;

  final bool? _isSending;
  bool get isSending => _isSending ?? false;

  @HiveField(13)
  final Map<String, String> reactions; // userId -> emoji

  @HiveField(14)
  final bool? _isEdited;
  bool get isEdited => _isEdited ?? false;

  @HiveField(15)
  final bool? _isDeleted;
  bool get isDeleted => _isDeleted ?? false;

  @HiveField(16)
  final List<String>? _deletedFor;
  List<String> get deletedFor => _deletedFor ?? const [];

  @HiveField(17)
  final bool? _isPinned;
  bool get isPinned => _isPinned ?? false;

  @HiveField(18)
  final DateTime? pinnedAt;

  @HiveField(19)
  final String? pinnedBy;

  GroupChatMessageModel({
    required this.senderId,
    required this.receiverIds,
    required this.text,
    required this.messageType,
    required this.timeSent,
    required this.messageId,
    bool? isSeen,
    bool? isDelivered,
    bool? isSending,
    this.fileMessageData,
    required this.repliedMessage,
    required this.repliedTo,
    required this.repliedMessageType,
    required this.groupId,
    Map<String, String>? reactions,
    bool? isEdited,
    bool? isDeleted,
    List<String>? deletedFor,
    bool? isPinned,
    this.pinnedAt,
    this.pinnedBy,
  })  : _isSeen = isSeen ?? false,
        _isDelivered = isDelivered ?? false,
        _isSending = isSending ?? false,
        reactions = reactions ?? const {},
        _isEdited = isEdited ?? false,
        _isDeleted = isDeleted ?? false,
        _deletedFor = deletedFor ?? const [],
        _isPinned = isPinned ?? false;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'senderId': senderId,
      'receiverIds': receiverIds,
      'text': text,
      'messageType': messageType,
      'timeSent': timeSent.millisecondsSinceEpoch,
      'messageId': messageId,
      'isSeen': isSeen,
      'isDelivered': isDelivered,
      'fileMessageData': fileMessageData,
      'repliedMessage': repliedMessage,
      'repliedTo': repliedTo,
      'repliedMessageType': repliedMessageType,
      'groupId': groupId,
      'reactions': reactions,
      'isEdited': isEdited,
      'isDeleted': isDeleted,
      'deletedFor': deletedFor,
      'isPinned': isPinned,
      'pinnedAt': pinnedAt?.millisecondsSinceEpoch,
      'pinnedBy': pinnedBy,
    };
  }

  static DateTime? _parseOptionalTime(dynamic rawTime) {
    if (rawTime == null) return null;
    if (rawTime is int) return DateTime.fromMillisecondsSinceEpoch(rawTime);
    if (rawTime is Timestamp) return rawTime.toDate();
    if (rawTime is String) {
      final asInt = int.tryParse(rawTime);
      return asInt != null
          ? DateTime.fromMillisecondsSinceEpoch(asInt)
          : DateTime.tryParse(rawTime);
    }
    return null;
  }

  factory GroupChatMessageModel.fromMap(Map<String, dynamic> map) {
    final parsedTime = _parseOptionalTime(map['timeSent']) ?? DateTime.now();

    Map<String, String> parsedReactions = {};
    if (map['reactions'] is Map) {
      (map['reactions'] as Map).forEach((k, v) {
        if (k != null && v != null) {
          parsedReactions[k.toString()] = v.toString();
        }
      });
    }

    return GroupChatMessageModel(
      senderId: map['senderId']?.toString() ?? '',
      receiverIds: (map['receiverIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      text: map['text']?.toString() ?? '',
      messageType: map['messageType']?.toString() ?? "text",
      timeSent: parsedTime,
      messageId: map['messageId']?.toString() ?? '',
      isSeen: map['isSeen'] as bool? ?? false,
      isDelivered: map['isDelivered'] as bool? ?? (map['isSeen'] as bool? ?? false),
      isSending: false,
      fileMessageData: map['fileMessageData']?.toString(),
      repliedMessage: map['repliedMessage']?.toString() ?? '',
      repliedTo: map['repliedTo']?.toString() ?? '',
      repliedMessageType: map['repliedMessageType']?.toString() ?? 'text',
      groupId: map['groupId']?.toString() ?? '',
      reactions: parsedReactions,
      isEdited: map['isEdited'] as bool? ?? false,
      isDeleted: map['isDeleted'] as bool? ?? false,
      deletedFor: (map['deletedFor'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      isPinned: map['isPinned'] as bool? ?? false,
      pinnedAt: _parseOptionalTime(map['pinnedAt']),
      pinnedBy: map['pinnedBy']?.toString(),
    );
  }

  // Helper method to update isSeen status
  GroupChatMessageModel copyWith({
    String? senderId,
    List<String>? receiverIds,
    String? groupId,
    String? text,
    String? messageType,
    DateTime? timeSent,
    String? messageId,
    bool? isSeen,
    bool? isDelivered,
    bool? isSending,
    String? fileMessageData,
    String? repliedMessage,
    String? repliedTo,
    String? repliedMessageType,
    Map<String, String>? reactions,
    bool? isEdited,
    bool? isDeleted,
    List<String>? deletedFor,
    bool? isPinned,
    DateTime? pinnedAt,
    String? pinnedBy,
    bool clearPin = false,
  }) {
    return GroupChatMessageModel(
      senderId: senderId ?? this.senderId,
      receiverIds: receiverIds ?? this.receiverIds,
      groupId: groupId ?? this.groupId,
      text: text ?? this.text,
      messageType: messageType ?? this.messageType,
      timeSent: timeSent ?? this.timeSent,
      messageId: messageId ?? this.messageId,
      isSeen: isSeen ?? this.isSeen,
      isDelivered: isDelivered ?? this.isDelivered,
      isSending: isSending ?? this.isSending,
      fileMessageData: fileMessageData ?? this.fileMessageData,
      repliedMessage: repliedMessage ?? this.repliedMessage,
      repliedTo: repliedTo ?? this.repliedTo,
      repliedMessageType: repliedMessageType ?? this.repliedMessageType,
      reactions: reactions ?? this.reactions,
      isEdited: isEdited ?? this.isEdited,
      isDeleted: isDeleted ?? this.isDeleted,
      deletedFor: deletedFor ?? this.deletedFor,
      isPinned: clearPin ? false : (isPinned ?? this.isPinned),
      pinnedAt: clearPin ? null : (pinnedAt ?? this.pinnedAt),
      pinnedBy: clearPin ? null : (pinnedBy ?? this.pinnedBy),
    );
  }
}