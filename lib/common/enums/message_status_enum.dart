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
    Widget icon;
    switch (status) {
      case MessageDeliveryStatus.sending:
        icon = Icon(
          Icons.access_time_rounded,
          key: const ValueKey('status_sending'),
          size: size - 2,
          color: color ?? Colors.white60,
        );
        break;
      case MessageDeliveryStatus.sent:
        icon = Icon(
          Icons.done_rounded,
          key: const ValueKey('status_sent'),
          size: size,
          color: color ?? Colors.white70,
        );
        break;
      case MessageDeliveryStatus.delivered:
        icon = Icon(
          Icons.done_all_rounded,
          key: const ValueKey('status_delivered'),
          size: size + 1,
          color: color ?? Colors.white70,
        );
        break;
      case MessageDeliveryStatus.seen:
        icon = Icon(
          Icons.done_all_rounded,
          key: const ValueKey('status_seen'),
          size: size + 1,
          color: const Color(0xFF38B6FF), // Iconic WhatsApp Cyan-Blue
        );
        break;
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => ScaleTransition(
        scale: animation,
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: icon,
    );
  }
}
