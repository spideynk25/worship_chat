import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_chat/common/enums/message_status_enum.dart';
import 'package:worship_chat/models/user_model.dart';
import 'package:worship_chat/features/settings/models/queendom_customization_model.dart';

void main() {
  group('Chat System Integrity & Status Checks', () {
    test('MessageDeliveryStatus.fromFlags progresses through 4 stages correctly', () {
      // Stage 1: Sending (in-flight)
      final statusSending = MessageDeliveryStatus.fromFlags(
        isSending: true,
        isDelivered: false,
        isSeen: false,
      );
      expect(statusSending, MessageDeliveryStatus.sending);

      // Stage 2: Sent (single grey tick)
      final statusSent = MessageDeliveryStatus.fromFlags(
        isSending: false,
        isDelivered: false,
        isSeen: false,
      );
      expect(statusSent, MessageDeliveryStatus.sent);

      // Stage 3: Delivered (double grey tick)
      final statusDelivered = MessageDeliveryStatus.fromFlags(
        isSending: false,
        isDelivered: true,
        isSeen: false,
      );
      expect(statusDelivered, MessageDeliveryStatus.delivered);

      // Stage 4: Seen (double cyan-blue tick)
      final statusSeen = MessageDeliveryStatus.fromFlags(
        isSending: false,
        isDelivered: true,
        isSeen: true,
      );
      expect(statusSeen, MessageDeliveryStatus.seen);
    });

    test('UserModel.fromMap parses fcmToken from fcmToken, token, or pushToken', () {
      final userWithFcm = UserModel.fromMap({
        'uid': 'user_1',
        'fcmToken': 'token_fcm_123',
      });
      expect(userWithFcm.fcmToken, 'token_fcm_123');

      final userWithLegacyToken = UserModel.fromMap({
        'uid': 'user_2',
        'token': 'token_legacy_456',
      });
      expect(userWithLegacyToken.fcmToken, 'token_legacy_456');

      final userWithPushToken = UserModel.fromMap({
        'uid': 'user_3',
        'pushToken': 'token_push_789',
      });
      expect(userWithPushToken.fcmToken, 'token_push_789');
    });

    test('MessageStatusIcon provides correct keys and cyan color for seen status', () {
      const iconSeen = MessageStatusIcon(status: MessageDeliveryStatus.seen);
      expect(iconSeen.status, MessageDeliveryStatus.seen);

      const iconDelivered = MessageStatusIcon(status: MessageDeliveryStatus.delivered);
      expect(iconDelivered.status, MessageDeliveryStatus.delivered);

      const iconSent = MessageStatusIcon(status: MessageDeliveryStatus.sent);
      expect(iconSent.status, MessageDeliveryStatus.sent);

      const iconSending = MessageStatusIcon(status: MessageDeliveryStatus.sending);
      expect(iconSending.status, MessageDeliveryStatus.sending);
    });

    test('QueendomCategory resolves position colors reliably', () {
      final category = QueendomCategory(
        title: 'Fuck Toy',
        position: 'Fuck Toy',
        color: const Color(0xFFE040FB),
        emoji: '💜',
      );
      expect(category.color, const Color(0xFFE040FB));
      expect(category.position.toLowerCase(), 'fuck toy');
    });
  });
}
