import 'package:flutter/material.dart';

/// WhatsApp-style 4-stage message delivery lifecycle status:
/// 1. [sending] - Clock icon (In-flight / Uploading media)
/// 2. [sent] - Single grey tick (Server acknowledged)
/// 3. [delivered] - Double grey ticks (Recipient device received)
/// 4. [seen] - Double cyan-blue ticks (Recipient opened & read)
enum MessageDeliveryStatus {
  sending,
  sent,
  delivered,
  seen;

  static MessageDeliveryStatus fromFlags({
    bool? isSeen,
    bool? isDelivered,
    bool? isSending,
  }) {
    if (isSending == true) return MessageDeliveryStatus.sending;
    if (isSeen == true) return MessageDeliveryStatus.seen;
    if (isDelivered == true) return MessageDeliveryStatus.delivered;
    return MessageDeliveryStatus.sent;
  }
}

/// A compact status icon representing the 4-stage message lifecycle.
class MessageStatusIcon extends StatelessWidget {
  final MessageDeliveryStatus status;
  final double size;
  final Color? color;

  const MessageStatusIcon({
    super.key,
    required this.status,
    this.size = 15,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case MessageDeliveryStatus.sending:
        return Icon(
          Icons.access_time_rounded,
          size: size - 2,
          color: color ?? Colors.white60,
        );
      case MessageDeliveryStatus.sent:
        return Icon(
          Icons.done_rounded,
          size: size,
          color: color ?? Colors.white70,
        );
      case MessageDeliveryStatus.delivered:
        return Icon(
          Icons.done_all_rounded,
          size: size + 1,
          color: color ?? Colors.white70,
        );
      case MessageDeliveryStatus.seen:
        return Icon(
          Icons.done_all_rounded,
          size: size + 1,
          color: const Color(0xFF38B6FF), // Iconic WhatsApp Cyan-Blue
        );
    }
  }
}
