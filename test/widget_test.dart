import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_chat/common/utils/active_chat_notifier.dart';
import 'package:worship_chat/models/group.dart';

void main() {
  group('ActiveChatNotifier Tests', () {
    final notifier = ActiveChatNotifier.instance;

    setUp(() {
      notifier.leave();
    });

    test('Initial active chat should be null', () {
      expect(notifier.activeChatUid, isNull);
      expect(notifier.isChatActive('user123'), isFalse);
    });

    test('Entering chat sets activeChatUid and suppresses notification', () {
      notifier.enter('user123');
      expect(notifier.activeChatUid, 'user123');
      expect(notifier.isChatActive('user123'), isTrue);
      expect(notifier.isChatActive('user456'), isFalse);
    });

    test('Leaving chat clears activeChatUid', () {
      notifier.enter('user123');
      expect(notifier.isChatActive('user123'), isTrue);

      notifier.leave();
      expect(notifier.activeChatUid, isNull);
      expect(notifier.isChatActive('user123'), isFalse);
    });

    test('Entering chat triggers onChatEntered callback with chatId and chatName', () {
      String? enteredId;
      String? enteredName;
      notifier.onChatEntered = (id, name) {
        enteredId = id;
        enteredName = name;
      };

      notifier.enter('user_alice', chatName: 'Alice');
      expect(enteredId, 'user_alice');
      expect(enteredName, 'Alice');

      notifier.onChatEntered = null;
    });

    test('FlutterLocalNotificationsPlugin cancel and getActiveNotifications API verification', () {
      final plugin = FlutterLocalNotificationsPlugin();
      expect(plugin.cancel, isNotNull);
      expect(plugin.getActiveNotifications, isNotNull);

      // Verify ActiveNotification fields
      const active = ActiveNotification(
        id: 1,
        tag: 'chat123',
        title: 'Alice',
        body: 'Hello',
        payload: '{"senderUid":"chat123"}',
      );
      expect(active.id, 1);
      expect(active.tag, 'chat123');
      expect(active.payload, contains('chat123'));
    });
  });

  group('GroupModel Fallback Robustness Tests', () {
    test('GroupModel fallback initializes safely with all required fields', () {
      final fallback = GroupModel(
        senderId: '',
        name: 'Test Group',
        groupId: 'grp_001',
        lastMessage: '',
        groupPic: '',
        membersUid: [],
        timeSent: DateTime.now(),
        fcmTokens: [],
        unseenMessages: {},
        chatBackgroundUrl: null,
        wish: null,
        queendom: null,
      );

      expect(fallback.groupId, 'grp_001');
      expect(fallback.name, 'Test Group');
      expect(fallback.hasUnseenForUser('any_user'), isFalse);
      expect(fallback.fcmTokens, isEmpty);
    });
  });
}
