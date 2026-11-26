import 'package:flutter_riverpod/flutter_riverpod.dart';

class MessageReply {
  final String message;
  final bool isMe;
  final String messageType;
  final String fileMessageData;
  final String? repliedTo;

  MessageReply({
    required this.message,
    required this.isMe,
    required this.messageType,
    required this.fileMessageData,
    this.repliedTo,
  });
}

final messageReplyProvider = StateProvider<MessageReply?>((ref) => null);
