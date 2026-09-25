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
  })  : _isSeen = isSeen ?? false,
        _isDelivered = isDelivered ?? false,
        _isSending = isSending ?? false;

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
    };
  }

  factory GroupChatMessageModel.fromMap(Map<String, dynamic> map) {
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
    );
  }
}