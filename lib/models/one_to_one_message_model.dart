import 'package:hive/hive.dart';

part 'one_to_one_message_model.g.dart';

@HiveType(typeId: 1)
class OneToOneMessageModel {
  @HiveField(0)
  final String senderId;

  @HiveField(1)
  final String receiverId;

  @HiveField(2)
  final String text;

  @HiveField(3)
  final String messageType;

  @HiveField(4)
  final DateTime timeSent;

  @HiveField(5)
  final String messageId;

  @HiveField(6)
  final bool isSeen;

  @HiveField(7)
  String? fileMessageData;

  @HiveField(8)
  final String repliedMessage;

  @HiveField(9)
  final String repliedTo;

  @HiveField(10)
  final String repliedMessageType;

  OneToOneMessageModel({
    required this.senderId,
    required this.receiverId,
    required this.text,
    required this.messageType,
    required this.timeSent,
    required this.messageId,
    required this.isSeen,
    this.fileMessageData,
    required this.repliedMessage,
    required this.repliedTo,
    required this.repliedMessageType,
  });

  // ✅ Added copyWith - no HiveField changes so no regeneration needed
  OneToOneMessageModel copyWith({
    String? senderId,
    String? receiverId,
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
    return OneToOneMessageModel(
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
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

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'senderId': senderId,
      'receiverId': receiverId,
      'text': text,
      'messageType': messageType,
      'timeSent': timeSent.millisecondsSinceEpoch,
      'messageId': messageId,
      'isSeen': isSeen,
      'fileMessageData': fileMessageData,
      'repliedMessage': repliedMessage,
      'repliedTo': repliedTo,
      'repliedMessageType': repliedMessageType,
    };
  }

  factory OneToOneMessageModel.fromMap(Map<String, dynamic> map) {
    return OneToOneMessageModel(
      senderId: map['senderId'] as String,
      receiverId: map['receiverId'] as String,
      text: map['text'] as String,
      messageType: map['messageType'] ?? "text",
      timeSent: DateTime.fromMillisecondsSinceEpoch(map['timeSent'] as int),
      messageId: map['messageId'] as String,
      isSeen: map['isSeen'] as bool,
      fileMessageData: map['fileMessageData'],
      repliedMessage: map['repliedMessage'] ?? '',
      repliedTo: map['repliedTo'] ?? '',
      repliedMessageType: map['repliedMessageType'] ?? 'text',
    );
  }
}