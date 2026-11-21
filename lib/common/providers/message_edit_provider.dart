import 'package:flutter_riverpod/flutter_riverpod.dart';

class MessageEdit {
  final String messageId;
  final String text;
  final String chatType; // 'one_to_one' or 'group'
  final String? receiverUserId;
  final String? groupId;
  final String messageType;

  MessageEdit({
    required this.messageId,
    required this.text,
    required this.chatType,
    this.receiverUserId,
    this.groupId,
    this.messageType = 'text',
  });
}

final messageEditProvider = StateProvider<MessageEdit?>((ref) => null);

