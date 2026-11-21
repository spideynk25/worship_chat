import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:worship_chat/common/utils/app_capabilities.dart';
import 'package:worship_chat/features/group/services/gallery_media_service.dart';
import 'package:worship_chat/models/group_gallery_image.dart';

void main() {
  late Directory temporaryDirectory;
  final imageBytes = Uint8List.fromList([255, 216, 255, 217]);
  const imageUrl =
      'https://res.cloudinary.com/example/image/upload/f_auto,q_auto,w_800/v1/photo.jpeg';
  const originalUrl =
      'https://res.cloudinary.com/example/image/upload/v1/photo.jpeg';

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('gallery_test_');
  });

  tearDown(() async {
    AppCapabilities.debugOverride = null;
    await temporaryDirectory.delete(recursive: true);
  });

  for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
    test(
      '$platform exports original image bytes using the save dialog',
      () async {
        AppCapabilities.debugOverride = AppCapabilities(
          platform: platform,
          isTablet: false,
        );
        final savedFile = File('${temporaryDirectory.path}/exported.jpeg');
        final service = GalleryMediaService(
          temporaryDirectory: () async => temporaryDirectory,
          download: (url, path) async {
            expect(url, originalUrl);
            await File(path).writeAsBytes(imageBytes);
          },
          saveFile: (name, bytes) async {
            expect(name, 'photo.jpeg');
            expect(bytes, imageBytes);
            await savedFile.writeAsBytes(bytes);
            return savedFile.uri;
          },
          saveToAlbum: (_) async =>
              throw StateError('Desktop used mobile album'),
        );

        expect(
          await service.saveImage(imageUrl: imageUrl, imageId: 'photo'),
          GallerySaveResult.saved,
        );
        expect(await savedFile.readAsBytes(), imageBytes);
        expect(await temporaryDirectory.list().length, 1);
      },
    );
  }

  test(
    'cancelling a desktop export is silent and removes the download',
    () async {
      final service = GalleryMediaService(
        isDesktop: true,
        temporaryDirectory: () async => temporaryDirectory,
        download: (_, path) async => File(path).writeAsBytes(imageBytes),
        saveFile: (_, _) async => null,
        saveToAlbum: (_) async => throw StateError('Desktop used mobile album'),
      );

      expect(
        await service.saveImage(imageUrl: imageUrl, imageId: 'photo'),
        GallerySaveResult.cancelled,
      );
      expect(await temporaryDirectory.list().isEmpty, isTrue);
    },
  );

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    test('$platform tablets keep photo album saving available', () async {
      AppCapabilities.debugOverride = AppCapabilities(
        platform: platform,
        isTablet: true,
      );
      var albumCalls = 0;
      final service = GalleryMediaService(
        temporaryDirectory: () async => temporaryDirectory,
        download: (_, path) async => File(path).writeAsBytes(imageBytes),
        saveFile: (_, _) async =>
            throw StateError('Tablet used desktop dialog'),
        saveToAlbum: (path) async {
          albumCalls++;
          expect(await File(path).readAsBytes(), imageBytes);
          return true;
        },
      );

      expect(
        await service.saveImage(imageUrl: imageUrl, imageId: 'photo'),
        GallerySaveResult.saved,
      );
      expect(albumCalls, 1);
      expect(await temporaryDirectory.list().isEmpty, isTrue);
    });
  }

  test('failed downloads remove partial files', () async {
    final service = GalleryMediaService(
      isDesktop: true,
      temporaryDirectory: () async => temporaryDirectory,
      download: (_, path) async {
        await File(path).writeAsBytes(imageBytes);
        throw const SocketException('Connection lost');
      },
      saveFile: (_, _) async =>
          throw StateError('Incomplete image was exported'),
    );

    await expectLater(
      service.saveImage(imageUrl: imageUrl, imageId: 'photo'),
      throwsA(isA<SocketException>()),
    );
    expect(await temporaryDirectory.list().isEmpty, isTrue);
  });

  group('downloadGalleryAsZip', () {
    final sampleImages = [
      GroupGalleryImage(
        imageId: 'img_1',
        groupId: 'grp_1',
        imageUrl:
            'https://res.cloudinary.com/example/image/upload/f_auto,q_auto/v1/pic1.jpg',
        uploadedBy: 'u1',
        uploadedByName: 'Alice',
        uploadedAt: DateTime(2026, 1, 1),
      ),
      GroupGalleryImage(
        imageId: 'img_2',
        groupId: 'grp_1',
        imageUrl:
            'https://res.cloudinary.com/example/image/upload/f_auto,q_auto/v1/pic2.png',
        uploadedBy: 'u2',
        uploadedByName: 'Bob',
        uploadedAt: DateTime(2026, 1, 2),
      ),
    ];

    test('fails gracefully when image list is empty', () async {
      final service = GalleryMediaService();
      final result = await service.downloadGalleryAsZip(
        groupName: 'Queen Pooja',
        images: [],
      );

      expect(result.status, GalleryZipStatus.failed);
      expect(result.errorMessage, contains('no photos'));
    });

    test('exports gallery images to ZIP on desktop with high quality URLs',
        () async {
      final requestedUrls = <String>[];
      final savedZipFile = File('${temporaryDirectory.path}/exported.zip');

      final service = GalleryMediaService(
        isDesktop: true,
        fetchBytes: (url) async {
          requestedUrls.add(url);
          return imageBytes;
        },
        saveZipFile: (fileName, bytes) async {
          expect(fileName, startsWith('Queen_Pooja_gallery_'));
          expect(fileName, endsWith('.zip'));
          await savedZipFile.writeAsBytes(bytes);
          return savedZipFile.uri;
        },
      );

      final progressUpdates = <GalleryZipProgress>[];
      final result = await service.downloadGalleryAsZip(
        groupName: 'Queen Pooja',
        images: sampleImages,
        onProgress: (p) => progressUpdates.add(p),
      );

      expect(result.status, GalleryZipStatus.saved);
      expect(result.totalCount, 2);
      expect(result.filePath, savedZipFile.path);

      // Verify original pristine URLs were requested (stripped of f_auto,q_auto)
      expect(requestedUrls, [
        'https://res.cloudinary.com/example/image/upload/v1/pic1.jpg',
        'https://res.cloudinary.com/example/image/upload/v1/pic2.png',
      ]);

      // Decode the generated ZIP and inspect archive entries
      final zipBytes = await savedZipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(zipBytes);
      expect(archive.length, 2);
      expect(archive[0].name, 'Queen_Pooja_001.jpg');
      expect(archive[1].name, 'Queen_Pooja_002.png');
      expect(archive[0].content, imageBytes);
      expect(archive[1].content, imageBytes);

      // Verify progress notifications
      expect(progressUpdates.isNotEmpty, isTrue);
      expect(progressUpdates.last.progress, greaterThanOrEqualTo(0.9));
    });

    test('desktop cancelling save dialog returns cancelled status', () async {
      final service = GalleryMediaService(
        isDesktop: true,
        fetchBytes: (_) async => imageBytes,
        saveZipFile: (_, __) async => null,
      );

      final result = await service.downloadGalleryAsZip(
        groupName: 'Queen Rashmika',
        images: sampleImages,
      );

      expect(result.status, GalleryZipStatus.cancelled);
      expect(result.filePath, isNull);
    });

    test('cancelling midway aborts download without creating ZIP', () async {
      var fetchCount = 0;
      var shouldCancel = false;

      final service = GalleryMediaService(
        isDesktop: true,
        fetchBytes: (_) async {
          fetchCount++;
          shouldCancel = true; // cancel after first download
          return imageBytes;
        },
        saveZipFile: (_, __) async =>
            throw StateError('Should not be called when cancelled'),
      );

      final result = await service.downloadGalleryAsZip(
        groupName: 'Fortress',
        images: sampleImages,
        isCancelled: () => shouldCancel,
      );

      expect(result.status, GalleryZipStatus.cancelled);
      expect(fetchCount, 1);
    });

    test('mobile saves ZIP to target downloads/documents folder', () async {
      final mobileDir = Directory('${temporaryDirectory.path}/downloads');
      await mobileDir.create();

      final service = GalleryMediaService(
        isDesktop: false,
        fetchBytes: (_) async => imageBytes,
        downloadsDirectory: () async => mobileDir,
        documentsDirectory: () async => mobileDir,
      );

      final result = await service.downloadGalleryAsZip(
        groupName: 'Royal Queendom',
        images: sampleImages,
      );

      expect(result.status, GalleryZipStatus.saved);
      expect(result.totalCount, 2);
      expect(result.filePath, isNotNull);
      expect(File(result.filePath!).existsSync(), isTrue);

      final zipBytes = await File(result.filePath!).readAsBytes();
      final archive = ZipDecoder().decodeBytes(zipBytes);
      expect(archive.length, 2);
      expect(archive[0].name, 'Royal_Queendom_001.jpg');
      expect(archive[1].name, 'Royal_Queendom_002.png');
    });

    test('downloadGalleryAsGif decodes images and generates animated GIF', () async {
      final imgObj = img.Image(width: 4, height: 4);
      final validPngBytes = Uint8List.fromList(img.encodePng(imgObj));
      String? savedGifPath;

      final service = GalleryMediaService(
        isDesktop: false,
        fetchBytes: (_) async => validPngBytes,
        temporaryDirectory: () async => temporaryDirectory,
        saveToAlbum: (path) async {
          savedGifPath = path;
          return true;
        },
      );

      final result = await service.downloadGalleryAsGif(
        groupName: 'Shrine',
        images: sampleImages,
      );

      expect(result, GallerySaveResult.saved);
      expect(savedGifPath, isNotNull);
    });
  });
}
