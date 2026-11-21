import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_chat/features/chat/screens/one_to_one_chat_screen.dart';
import 'package:worship_chat/models/chat_contact.dart';
import 'package:worship_chat/models/group.dart';

void main() {
  group('Chat Background Persistence & Non-Destructive Merging Tests', () {
    test('ChatContact.toMap omits chatBackgroundUrl when null', () {
      final contact = ChatContact(
        name: 'Goddess Rashmika',
        profilePic: 'https://example.com/pic.jpg',
        uid: 'user_123',
        timeSent: DateTime(2026, 10, 29, 12, 0),
        lastMessage: 'Hello!',
        fcmToken: 'fcm_123',
        unseenCount: false,
        chatBackgroundUrl: null,
      );

      final map = contact.toMap();
      expect(map.containsKey('chatBackgroundUrl'), isFalse,
          reason: 'toMap() must omit chatBackgroundUrl when null so Firestore merge: true never overwrites existing wallpaper');
    });

    test('ChatContact.toMap omits chatBackgroundUrl when empty or whitespace', () {
      final contact = ChatContact(
        name: 'Goddess Pooja',
        profilePic: 'https://example.com/pic2.jpg',
        uid: 'user_456',
        timeSent: DateTime(2026, 10, 29, 12, 0),
        lastMessage: 'Hi!',
        fcmToken: 'fcm_456',
        unseenCount: true,
        chatBackgroundUrl: '   ',
      );

      final map = contact.toMap();
      expect(map.containsKey('chatBackgroundUrl'), isFalse,
          reason: 'toMap() must omit chatBackgroundUrl when whitespace so Firestore merge: true preserves wallpaper');
    });

    test('ChatContact.toMap includes chatBackgroundUrl when valid URL is provided', () {
      const wallpaperUrl = 'https://res.cloudinary.com/test/image/upload/v1/wallpaper.jpg';
      final contact = ChatContact(
        name: 'Goddess Pooja',
        profilePic: 'https://example.com/pic2.jpg',
        uid: 'user_456',
        timeSent: DateTime(2026, 10, 29, 12, 0),
        lastMessage: 'Hi!',
        fcmToken: 'fcm_456',
        unseenCount: true,
        chatBackgroundUrl: wallpaperUrl,
      );

      final map = contact.toMap();
      expect(map.containsKey('chatBackgroundUrl'), isTrue);
      expect(map['chatBackgroundUrl'], wallpaperUrl);
    });

    test('GroupModel.toMap omits chatBackgroundUrl when null or empty', () {
      final groupWithoutBg = GroupModel(
        senderId: 'user_1',
        name: 'Palace of Devotion',
        groupId: 'grp_001',
        lastMessage: 'Welcome',
        groupPic: 'https://example.com/group.jpg',
        membersUid: ['user_1', 'user_2'],
        timeSent: DateTime(2026, 10, 29, 10, 0),
        fcmTokens: [],
        unseenMessages: {},
        chatBackgroundUrl: null,
      );

      final map = groupWithoutBg.toMap();
      expect(map.containsKey('chatBackgroundUrl'), isFalse,
          reason: 'GroupModel.toMap() must omit chatBackgroundUrl when null');

      const groupWallpaper = 'https://res.cloudinary.com/test/image/upload/v1/group_bg.jpg';
      final groupWithBg = groupWithoutBg.copyWith(chatBackgroundUrl: groupWallpaper);
      final mapWithBg = groupWithBg.toMap();
      expect(mapWithBg.containsKey('chatBackgroundUrl'), isTrue);
      expect(mapWithBg['chatBackgroundUrl'], groupWallpaper);
    });

    test('displayImageProvider defaults to true so chat wallpaper is visible immediately', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final isVisible = container.read(displayImageProvider);
      expect(isVisible, isTrue,
          reason: 'displayImageProvider must default to true so wallpaper is not hidden on screen open');
    });
  });
}

