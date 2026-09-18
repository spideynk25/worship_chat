// ignore_for_file: public_member_api_docs, sort_constructors_first

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
  final bool isSeen;
  
  @HiveField(8)
  String? fileMessageData;
  
  @HiveField(9)
  final String repliedMessage;
  
  @HiveField(10)
  final String repliedTo;
  
  @HiveField(11)
  final String repliedMessageType;

  GroupChatMessageModel({
    required this.senderId,
    required this.receiverIds,
    required this.text,
    required this.messageType,
    required this.timeSent,
    required this.messageId,
    required this.isSeen,
    this.fileMessageData,
    required this.repliedMessage,
    required this.repliedTo,
    required this.repliedMessageType,
    required this.groupId,
  });

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'senderId': senderId,
      'receiverIds': receiverIds,
      'text': text,
      'messageType': messageType,
      'timeSent': timeSent.millisecondsSinceEpoch,
      'messageId': messageId,
      'isSeen': isSeen,
      'fileMessageData': fileMessageData,
      'repliedMessage': repliedMessage,
      'repliedTo': repliedTo,
      'repliedMessageType': repliedMessageType,
      'groupId': groupId,
    };
  }

  factory GroupChatMessageModel.fromMap(Map<String, dynamic> map) {
    return GroupChatMessageModel(
      senderId: map['senderId'] as String,
      receiverIds: (map['receiverIds'] as List<dynamic>).cast<String>(),
      text: map['text'] as String,
      messageType: map['messageType'] ?? "text",
      timeSent: DateTime.fromMillisecondsSinceEpoch(map['timeSent'] as int),
      messageId: map['messageId'] as String,
      isSeen: map['isSeen'] as bool,
      fileMessageData: map['fileMessageData'],
      repliedMessage: map['repliedMessage'],
      repliedTo: map['repliedTo'],
      repliedMessageType: map['repliedMessageType'],
      groupId: map['groupId'],
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
      fileMessageData: fileMessageData ?? this.fileMessageData,
      repliedMessage: repliedMessage ?? this.repliedMessage,
      repliedTo: repliedTo ?? this.repliedTo,
      repliedMessageType: repliedMessageType ?? this.repliedMessageType,
    );
  }
}