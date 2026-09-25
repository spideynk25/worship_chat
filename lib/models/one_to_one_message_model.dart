import 'package:cloud_firestore/cloud_firestore.dart';
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
  final bool? _isSeen;
  bool get isSeen => _isSeen ?? false;

  @HiveField(7)
  String? fileMessageData;

  @HiveField(8)
  final String repliedMessage;

  @HiveField(9)
  final String repliedTo;

  @HiveField(10)
  final String repliedMessageType;

  @HiveField(11)
  final bool? _isDelivered;
  bool get isDelivered => _isDelivered ?? false;

  final bool? _isSending;
  bool get isSending => _isSending ?? false;

  OneToOneMessageModel({
    required this.senderId,
    required this.receiverId,
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
  })  : _isSeen = isSeen ?? false,
        _isDelivered = isDelivered ?? false,
        _isSending = isSending ?? false;

  // ✅ Added copyWith - no HiveField changes so no regeneration needed
  OneToOneMessageModel copyWith({
    String? senderId,
    String? receiverId,
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
    return OneToOneMessageModel(
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
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

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'senderId': senderId,
      'receiverId': receiverId,
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
    };
  }

  factory OneToOneMessageModel.fromMap(Map<String, dynamic> map) {
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

    return OneToOneMessageModel(
      senderId: map['senderId']?.toString() ?? '',
      receiverId: map['receiverId']?.toString() ?? '',
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
    );
  }
}