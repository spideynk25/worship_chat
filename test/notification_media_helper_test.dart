import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:image/image.dart' as img;
import 'package:worship_chat/common/utils/notification_media_helper.dart';

class _FakeHttpClientAdapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions options) onFetch;
  final List<String> requestedUrls = [];

  _FakeHttpClientAdapter(this.onFetch);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestedUrls.add(options.uri.toString());
    return onFetch(options);
  }

  @override
  void close({bool force = false}) {}
}

Uint8List _createSamplePngBytes({
  int width = 120,
  int height = 80,
  int r = 220,
  int g = 40,
  int b = 40,
}) {
  final image = img.Image(width: width, height: height, numChannels: 4);
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      image.setPixelRgba(x, y, r, g, b, 255);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

Uint8List _createSampleJpgBytes({
  int width = 160,
  int height = 100,
  int r = 30,
  int g = 140,
  int b = 230,
}) {
  final image = img.Image(width: width, height: height);
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      image.setPixelRgba(x, y, r, g, b, 255);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 90));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('notif_media_test_');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('NotificationMediaHelper URL parsing & transforms', () {
    test('extractMediaUrl handles plain HTTP/HTTPS and grouped JSON', () {
      expect(
        NotificationMediaHelper.extractMediaUrl(
          'http://res.cloudinary.com/demo/image/upload/v1/sample.jpg',
        ),
        'https://res.cloudinary.com/demo/image/upload/v1/sample.jpg',
      );

      final groupedJson = jsonEncode({
        'url': 'https://res.cloudinary.com/demo/image/upload/v2/photo.png',
        'groupId': 'media_group_1',
      });
      expect(
        NotificationMediaHelper.extractMediaUrl(groupedJson),
        'https://res.cloudinary.com/demo/image/upload/v2/photo.png',
      );

      expect(NotificationMediaHelper.extractMediaUrl(''), isNull);
      expect(NotificationMediaHelper.extractMediaUrl('not-a-url'), isNull);
      expect(NotificationMediaHelper.extractMediaUrl('{bad-json'), isNull);
    });

    test('supportsPhotoPreview detects image, gif, and photo stories', () {
      expect(
        NotificationMediaHelper.supportsPhotoPreview(
          messageType: 'image',
          notificationType: 'chat',
          rawFileData: 'https://cdn.example.com/pic.jpg',
        ),
        isTrue,
      );
      expect(
        NotificationMediaHelper.supportsPhotoPreview(
          messageType: 'gif',
          notificationType: 'group',
          rawFileData: 'https://cdn.example.com/anim.gif',
        ),
        isTrue,
      );
      expect(
        NotificationMediaHelper.supportsPhotoPreview(
          messageType: 'video',
          notificationType: 'chat',
          rawFileData: 'https://cdn.example.com/clip.mp4',
        ),
        isFalse,
      );
      expect(
        NotificationMediaHelper.supportsPhotoPreview(
          messageType: 'text',
          notificationType: 'story',
          statusUrl: 'https://cdn.example.com/story.jpg',
        ),
        isTrue,
      );
      expect(
        NotificationMediaHelper.supportsPhotoPreview(
          messageType: 'video',
          notificationType: 'story',
          statusUrl: 'https://cdn.example.com/story.mp4',
        ),
        isFalse,
      );
    });

    test('buildPreviewUrl and buildAvatarUrl apply Cloudinary transforms once', () {
      expect(
        NotificationMediaHelper.buildPreviewUrl(
          'http://res.cloudinary.com/demo/image/upload/v123/pic.jpg',
        ),
        'https://res.cloudinary.com/demo/image/upload/w_900,c_limit,q_auto,f_jpg/v123/pic.jpg',
      );
      expect(
        NotificationMediaHelper.buildPreviewUrl(
          'https://res.cloudinary.com/demo/image/upload/v123/anim.gif',
          isGif: true,
        ),
        'https://res.cloudinary.com/demo/image/upload/w_900,c_limit,q_auto,f_jpg,pg_1/v123/anim.gif',
      );
      expect(
        NotificationMediaHelper.buildPreviewUrl(
          'https://res.cloudinary.com/demo/image/upload/w_400,c_fill/v123/pic.jpg',
        ),
        'https://res.cloudinary.com/demo/image/upload/w_400,c_fill/v123/pic.jpg',
      );
      expect(
        NotificationMediaHelper.buildAvatarUrl(
          'https://res.cloudinary.com/demo/image/upload/v123/avatar.jpg',
        ),
        'https://res.cloudinary.com/demo/image/upload/w_256,h_256,c_fill,g_face,q_auto,f_png/v123/avatar.jpg',
      );
      expect(
        NotificationMediaHelper.buildAvatarUrl(
          'http://example.com/static/avatar.png',
        ),
        'https://example.com/static/avatar.png',
      );
    });
  });

  group('NotificationMediaHelper download & circular avatar rendering', () {
    test('downloadPreviewImage saves photo preview and reuses disk cache', () async {
      final jpgBytes = _createSampleJpgBytes();
      final adapter = _FakeHttpClientAdapter((options) async {
        return ResponseBody.fromBytes(jpgBytes, 200);
      });
      final dio = Dio()..httpClientAdapter = adapter;

      final first = await NotificationMediaHelper.downloadPreviewImage(
        url: jsonEncode({
          'url': 'https://cdn.example.com/chat/photo.jpg',
          'groupId': 'g1',
        }),
        dioOverride: dio,
        cacheDirOverride: tempDir,
      );

      expect(first, isNotNull);
      expect(first!.existsSync(), isTrue);
      expect(first.path.endsWith('.jpg'), isTrue);
      expect(adapter.requestedUrls.length, 1);

      final second = await NotificationMediaHelper.downloadPreviewImage(
        url: 'https://cdn.example.com/chat/photo.jpg',
        dioOverride: dio,
        cacheDirOverride: tempDir,
      );

      expect(second?.path, first.path);
      expect(adapter.requestedUrls.length, 1);
    });

    test('downloadCircularAvatar crops square, masks circle with transparent corners, and caches', () async {
      final pngBytes = _createSamplePngBytes(
        width: 120,
        height: 80,
        r: 210,
        g: 30,
        b: 45,
      );
      final adapter = _FakeHttpClientAdapter((options) async {
        return ResponseBody.fromBytes(pngBytes, 200);
      });
      final dio = Dio()..httpClientAdapter = adapter;

      final avatarFile = await NotificationMediaHelper.downloadCircularAvatar(
        url: 'https://cdn.example.com/users/pooja.png',
        sizePx: 64,
        dioOverride: dio,
        cacheDirOverride: tempDir,
      );

      expect(avatarFile, isNotNull);
      expect(avatarFile!.existsSync(), isTrue);
      expect(avatarFile.path.endsWith('.png'), isTrue);

      final decoded = img.decodePng(avatarFile.readAsBytesSync());
      expect(decoded, isNotNull);
      expect(decoded!.width, 64);
      expect(decoded.height, 64);

      // Outside circle corner is fully transparent.
      final corner = decoded.getPixel(0, 0);
      expect(corner.a.toInt(), 0);

      // Center of circle preserves avatar color and full opacity.
      final center = decoded.getPixel(32, 32);
      expect(center.a.toInt(), 255);
      expect(center.r.toInt(), greaterThan(180));
      expect(center.g.toInt(), lessThan(50));

      // Second call uses cached PNG on disk without issuing network request.
      final cached = await NotificationMediaHelper.downloadCircularAvatar(
        url: 'https://cdn.example.com/users/pooja.png',
        sizePx: 64,
        dioOverride: dio,
        cacheDirOverride: tempDir,
      );
      expect(cached?.path, avatarFile.path);
      expect(adapter.requestedUrls.length, 1);
    });

    test('downloadCircularAvatar falls back to original URL when CDN crop fails', () async {
      final pngBytes = _createSamplePngBytes(r: 20, g: 180, b: 90);
      final adapter = _FakeHttpClientAdapter((options) async {
        if (options.uri.toString().contains('w_256,h_256')) {
          return ResponseBody.fromString('bad transform', 404);
        }
        return ResponseBody.fromBytes(pngBytes, 200);
      });
      final dio = Dio()..httpClientAdapter = adapter;

      final file = await NotificationMediaHelper.downloadCircularAvatar(
        url: 'https://res.cloudinary.com/demo/image/upload/v1/user.png',
        sizePx: 64,
        dioOverride: dio,
        cacheDirOverride: tempDir,
      );

      expect(file, isNotNull);
      expect(adapter.requestedUrls.length, 2);
      expect(
        adapter.requestedUrls.last,
        'https://res.cloudinary.com/demo/image/upload/v1/user.png',
      );
    });

    test('fetchNotificationAssets handles partial failures and distinct group vs sender avatars', () async {
      final groupPng = _createSamplePngBytes(r: 240, g: 190, b: 20);
      final senderPng = _createSamplePngBytes(r: 40, g: 90, b: 230);
      final photoJpg = _createSampleJpgBytes();

      final adapter = _FakeHttpClientAdapter((options) async {
        final u = options.uri.toString();
        if (u.contains('group.png')) {
          return ResponseBody.fromBytes(groupPng, 200);
        }
        if (u.contains('sender.png')) {
          return ResponseBody.fromBytes(senderPng, 200);
        }
        if (u.contains('photo.jpg')) {
          return ResponseBody.fromBytes(photoJpg, 200);
        }
        return ResponseBody.fromString('not found', 404);
      });
      final dio = Dio()..httpClientAdapter = adapter;

      final assets = await NotificationMediaHelper.fetchNotificationAssets(
        primaryAvatarUrl: 'https://cdn.example.com/group.png',
        senderAvatarUrl: 'https://cdn.example.com/sender.png',
        mediaPreviewUrl: 'https://cdn.example.com/photo.jpg',
        dioOverride: dio,
        cacheDirOverride: tempDir,
      );

      expect(assets.primaryAvatarFile, isNotNull);
      expect(assets.senderAvatarFile, isNotNull);
      expect(assets.mediaPreviewFile, isNotNull);
      expect(assets.primaryAvatarFile!.path, isNot(assets.senderAvatarFile!.path));

      final missingAvatarOnly =
          await NotificationMediaHelper.fetchNotificationAssets(
        primaryAvatarUrl: 'https://cdn.example.com/missing.png',
        mediaPreviewUrl: 'https://cdn.example.com/photo.jpg',
        dioOverride: dio,
        cacheDirOverride: tempDir,
      );
      expect(missingAvatarOnly.primaryAvatarFile, isNull);
      expect(missingAvatarOnly.mediaPreviewFile, isNotNull);
    });
  });

  group('NotificationMediaHelper Hive avatar resolution', () {
    test('resolves groupPic from Hive groups_cache list schema', () async {
      final groupsBox = await Hive.openBox('groups_cache');
      await groupsBox.put('groups_pooja_me', [
        {
          'groupId': 'grp_royal_1',
          'name': 'Royal Court',
          'groupPic': 'http://cdn.example.com/groups/royal.png',
        },
      ]);

      final fromHive = await NotificationMediaHelper.resolveGroupAvatarUrl(
        groupId: 'grp_royal_1',
      );
      expect(fromHive, 'https://cdn.example.com/groups/royal.png');

      final directOverridesHive =
          await NotificationMediaHelper.resolveGroupAvatarUrl(
        directGroupPic: 'https://cdn.example.com/groups/override.png',
        groupId: 'grp_royal_1',
      );
      expect(
        directOverridesHive,
        'https://cdn.example.com/groups/override.png',
      );
    });

    test('resolves user profilePic from Hive contacts_cache list schema', () async {
      final contactsBox = await Hive.openBox('contacts_cache');
      await contactsBox.put('user_chats_me', [
        {
          'uid': 'user_krithi_2',
          'name': 'Krithi',
          'profilePic': 'http://cdn.example.com/users/krithi.jpg',
        },
      ]);

      final fromHive = await NotificationMediaHelper.resolveUserAvatarUrl(
        uid: 'user_krithi_2',
      );
      expect(fromHive, 'https://cdn.example.com/users/krithi.jpg');

      final directOverridesHive =
          await NotificationMediaHelper.resolveUserAvatarUrl(
        directProfilePic: 'https://cdn.example.com/users/fresh.jpg',
        uid: 'user_krithi_2',
      );
      expect(
        directOverridesHive,
        'https://cdn.example.com/users/fresh.jpg',
      );
    });
  });
}
