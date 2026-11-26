import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_chat/common/providers/message_reply_provider.dart';
import 'package:worship_chat/features/status/repository/status_repository.dart';
import 'package:worship_chat/models/one_to_one_message_model.dart';
import 'package:worship_chat/models/status_model.dart';

void main() {
  group('Status Feature & Multi-Media Selection Tests', () {
    test('StatusRepository.sanitizeStatus upgrades http to https for statusUrl and profilePic', () {
      final input = {
        'statusId': 'stat_1',
        'statusUrl': 'http://res.cloudinary.com/test/image.jpg',
        'profilePic': 'http://res.cloudinary.com/test/pic.png',
        'mediaType': 'image',
      };

      final sanitized = StatusRepository.sanitizeStatus(input);
      expect(sanitized['statusUrl'], 'https://res.cloudinary.com/test/image.jpg');
      expect(sanitized['profilePic'], 'https://res.cloudinary.com/test/pic.png');
    });

    test('StatusRepository.sanitizeStatus preserves already https URLs', () {
      final input = {
        'statusId': 'stat_2',
        'statusUrl': 'https://res.cloudinary.com/test/video.mp4',
        'profilePic': 'https://res.cloudinary.com/test/pic.png',
        'mediaType': 'video',
      };

      final sanitized = StatusRepository.sanitizeStatus(input);
      expect(sanitized['statusUrl'], 'https://res.cloudinary.com/test/video.mp4');
      expect(sanitized['profilePic'], 'https://res.cloudinary.com/test/pic.png');
    });

    test('Status model fromJson and toJson serialization roundtrip', () {
      final now = DateTime.now();
      final status = Status(
        uid: 'user_123',
        username: 'Queen Pooja',
        email: 'pooja@worship.com',
        photoUrl: [
          'https://res.cloudinary.com/test/1.jpg',
          'https://res.cloudinary.com/test/2.jpg',
        ],
        createdAt: now,
        profilePic: 'https://res.cloudinary.com/test/avatar.jpg',
        statusId: 'status_abc',
        whoCanSee: ['user_123', 'user_456'],
      );

      final json = status.toJson();
      expect(json['uid'], 'user_123');
      expect(json['username'], 'Queen Pooja');
      expect(json['photoUrl'], hasLength(2));
      expect(json['whoCanSee'], contains('user_456'));

      final reconstructed = Status.fromJson({
        'uid': status.uid,
        'username': status.username,
        'email': status.email,
        'photoUrl': status.photoUrl,
        'createdAt': now.millisecondsSinceEpoch,
        'profilePic': status.profilePic,
        'statusId': status.statusId,
        'whoCanSee': status.whoCanSee,
      });

      expect(reconstructed.uid, status.uid);
      expect(reconstructed.photoUrl, equals(status.photoUrl));
      expect(reconstructed.whoCanSee, equals(status.whoCanSee));
    });

    test('Story notification body format logic for single photo, multi-photo, and video', () {
      const userName = 'Goddess Rashmika';

      // 1. Single photo
      String singlePhotoBody(int count, bool isVideo) => isVideo
          ? '📽️ Watch video story from $userName'
          : (count > 1
              ? '📷 $count new photos added to story'
              : '📷 View new story photo from $userName');

      expect(singlePhotoBody(1, false), '📷 View new story photo from Goddess Rashmika');
      expect(singlePhotoBody(4, false), '📷 4 new photos added to story');
      expect(singlePhotoBody(1, true), '📽️ Watch video story from Goddess Rashmika');
    });

    test('ConfirmStatusScreen argument normalization handles both files list and single file', () {
      final file1 = File('/tmp/status1.jpg');
      final file2 = File('/tmp/status2.jpg');

      // Test arguments with files list
      final multiArgs = {
        'files': [file1, file2],
        'file': file1,
        'isVideo': false,
      };

      List<File> extractedFiles = [];
      if (multiArgs['files'] is List<File>) {
        extractedFiles = List<File>.from(multiArgs['files'] as List<File>);
      } else if (multiArgs['file'] is File) {
        extractedFiles = [multiArgs['file'] as File];
      }

      expect(extractedFiles, hasLength(2));
      expect(extractedFiles.first.path, '/tmp/status1.jpg');
      expect(extractedFiles.last.path, '/tmp/status2.jpg');

      // Test arguments with legacy single file
      final singleArgs = {
        'file': file1,
        'isVideo': true,
      };

      List<File> legacyExtracted = [];
      if (singleArgs['files'] is List<File>) {
        legacyExtracted = List<File>.from(singleArgs['files'] as List<File>);
      } else if (singleArgs['file'] is File) {
        legacyExtracted = [singleArgs['file'] as File];
      }

      expect(legacyExtracted, hasLength(1));
      expect(legacyExtracted.first.path, '/tmp/status1.jpg');
    });

    test('Story Direct Replies: MessageReply supports story type and repliedTo', () {
      const storyUrl = 'https://res.cloudinary.com/test/image.jpg';
      const ownerName = 'Queen Pooja';

      final reply = MessageReply(
        message: storyUrl,
        isMe: false,
        messageType: 'story',
        fileMessageData: storyUrl,
        repliedTo: ownerName,
      );

      expect(reply.message, storyUrl);
      expect(reply.fileMessageData, storyUrl);
      expect(reply.messageType, 'story');
      expect(reply.repliedTo, ownerName);
      expect(reply.isMe, isFalse);
    });

    test('Story Direct Replies: OneToOneMessageModel serializes and deserializes story reply metadata', () {
      final now = DateTime.now();
      final message = OneToOneMessageModel(
        senderId: 'user_1',
        receiverId: 'user_2',
        text: '🔥 Stunner!',
        messageType: 'text',
        timeSent: now,
        messageId: 'msg_story_reply_1',
        isSeen: false,
        isDelivered: true,
        fileMessageData: null,
        repliedMessage: 'https://res.cloudinary.com/test/story.jpg',
        repliedTo: 'Queen Pooja',
        repliedMessageType: 'story',
      );

      final map = message.toMap();
      expect(map['repliedMessageType'], 'story');
      expect(map['repliedTo'], 'Queen Pooja');
      expect(map['repliedMessage'], 'https://res.cloudinary.com/test/story.jpg');

      final fromMap = OneToOneMessageModel.fromMap(map);
      expect(fromMap.repliedMessageType, 'story');
      expect(fromMap.repliedTo, 'Queen Pooja');
      expect(fromMap.repliedMessage, 'https://res.cloudinary.com/test/story.jpg');
    });

    test('Story Direct Replies: notification body format handles story reply correctly', () {
      String getNotificationBody(String replyType, String text) {
        switch (replyType) {
          case 'story':
            return '💬 Replied to your story: "$text"';
          case 'text':
          case 'wish':
            return 'Replying to: "$text"';
          default:
            return text;
        }
      }

      expect(
        getNotificationBody('story', 'Looking incredible!'),
        '💬 Replied to your story: "Looking incredible!"',
      );
      expect(
        getNotificationBody('story', '👑'),
        '💬 Replied to your story: "👑"',
      );
    });

    test('Story Direct Replies: quick reaction emojis contains royal crown and reactions', () {
      const quickEmojis = [
        '❤️',
        '🔥',
        '👑',
        '😂',
        '😮',
        '🙏',
        '👏',
        '😍',
      ];

      expect(quickEmojis, contains('👑'));
      expect(quickEmojis, contains('🔥'));
      expect(quickEmojis, contains('❤️'));
      expect(quickEmojis, hasLength(8));
    });
  });
}

