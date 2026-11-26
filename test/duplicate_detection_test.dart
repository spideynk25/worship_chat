import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:image/image.dart' as img;
import 'package:worship_chat/features/group/services/duplicate_detection_service.dart';
import 'package:worship_chat/features/group/widgets/duplicate_comparison_sheet.dart';
import 'package:worship_chat/models/group_gallery_image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dup_detect_test_');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('DuplicateDetectionService URL Normalization Tests', () {
    test('Normalizes Cloudinary URLs by stripping transformations and version tags', () {
      const url1 =
          'https://res.cloudinary.com/worship/image/upload/v1699999999/pooja_sacred_temple.jpg';
      const url2 =
          'https://res.cloudinary.com/worship/image/upload/w_500,c_scale,q_auto/v1700000000/pooja_sacred_temple.jpg';
      const url3 =
          'https://res.cloudinary.com/worship/image/upload/f_auto,q_auto/pooja_sacred_temple.webp';

      final norm1 = DuplicateDetectionService.normalizeUrl(url1);
      final norm2 = DuplicateDetectionService.normalizeUrl(url2);
      final norm3 = DuplicateDetectionService.normalizeUrl(url3);

      expect(norm1, 'cloudinary:pooja_sacred_temple');
      expect(norm2, 'cloudinary:pooja_sacred_temple');
      expect(norm3, 'cloudinary:pooja_sacred_temple');
      expect(norm1, equals(norm2));
      expect(norm2, equals(norm3));
    });

    test('Normalizes Firebase Storage URLs by stripping tokens and query params', () {
      const url1 =
          'https://firebasestorage.googleapis.com/v0/b/worship.appspot.com/o/rashmika%2Froyal_darbar.jpg?alt=media&token=abc-123';
      const url2 =
          'https://firebasestorage.googleapis.com/v0/b/worship.appspot.com/o/rashmika%2Froyal_darbar.jpg?alt=media&token=xyz-789';

      final norm1 = DuplicateDetectionService.normalizeUrl(url1);
      final norm2 = DuplicateDetectionService.normalizeUrl(url2);

      expect(norm1, equals(norm2));
      expect(norm1.startsWith('firebase:'), isTrue);
    });

    test('Normalizes generic URLs by stripping query strings and protocol', () {
      const url1 = 'https://example.com/images/darshan.jpg?size=large&v=1';
      const url2 = 'http://example.com/images/darshan.jpg';

      final norm1 = DuplicateDetectionService.normalizeUrl(url1);
      final norm2 = DuplicateDetectionService.normalizeUrl(url2);

      expect(norm1, equals(norm2));
      expect(norm1, 'example.com/images/darshan.jpg');
    });
  });

  group('Perceptual Difference Hash (dHash) & Hamming Distance Tests', () {
    test('Calculates 16-character hex dHash correctly for synthetic images', () {
      final image = img.Image(width: 9, height: 8);
      // Create a gradient pattern: pixel[x+1] > pixel[x]
      for (int y = 0; y < 8; y++) {
        for (int x = 0; x < 9; x++) {
          image.setPixelRgb(x, y, x * 25, x * 25, x * 25);
        }
      }

      final hash = DuplicateDetectionService.computeDHashFromImage(image);
      expect(hash.length, 16);
      expect(RegExp(r'^[0-9a-f]{16}$').hasMatch(hash), isTrue);
    });

    test('Identical images yield Hamming distance of 0 and 100% similarity', () {
      const hash1 = 'a1b2c3d4e5f60718';
      const hash2 = 'a1b2c3d4e5f60718';

      final distance = DuplicateDetectionService.hammingDistance(hash1, hash2);
      final similarity = DuplicateDetectionService.similarityFromDistance(distance);

      expect(distance, 0);
      expect(similarity, 1.0);
    });

    test('Computes accurate Hamming distance for bit differences', () {
      // Differing by 1 bit in last char: '8' (1000) vs '9' (1001)
      const hashA = 'a1b2c3d4e5f60718';
      const hashB = 'a1b2c3d4e5f60719';

      final distance = DuplicateDetectionService.hammingDistance(hashA, hashB);
      expect(distance, 1);
      // (64 - 1) / 64 = 0.984375 (~98.4%)
      final similarity = DuplicateDetectionService.similarityFromDistance(distance);
      expect(similarity, closeTo(0.984, 0.001));
    });

    test('Near-duplicate images (subtle brightness variation) preserve low Hamming distance', () {
      final imgA = img.Image(width: 100, height: 100);
      final imgB = img.Image(width: 100, height: 100);

      for (int y = 0; y < 100; y++) {
        for (int x = 0; x < 100; x++) {
          final val = (x * 2 + y) % 255;
          imgA.setPixelRgb(x, y, val, val, val);
          // Slight compression/noise artifact (+3 to luminance)
          final valB = (val + 3).clamp(0, 255);
          imgB.setPixelRgb(x, y, valB, valB, valB);
        }
      }

      final hashA = DuplicateDetectionService.computeDHashFromImage(imgA);
      final hashB = DuplicateDetectionService.computeDHashFromImage(imgB);

      final distance = DuplicateDetectionService.hammingDistance(hashA, hashB);
      final similarity = DuplicateDetectionService.similarityFromDistance(distance);

      expect(distance, lessThanOrEqualTo(2));
      expect(similarity, greaterThanOrEqualTo(0.96));
    });
  });

  group('Duplicate Clustering & Detection Scan Tests', () {
    test('Clusters exact and normalized URL duplicates together, picking earliest as canonical', () async {
      final t0 = DateTime(2026, 10, 1, 12, 0);
      final t1 = DateTime(2026, 10, 5, 15, 0);
      final t2 = DateTime(2026, 10, 10, 18, 0);

      final images = [
        GroupGalleryImage(
          imageId: 'img_later_1',
          groupId: 'grp_pooja',
          imageUrl:
              'https://res.cloudinary.com/worship/image/upload/w_400/v1/pooja_crown.jpg',
          uploadedBy: 'user_1',
          uploadedByName: 'Pooja Devotee',
          uploadedAt: t1,
        ),
        GroupGalleryImage(
          imageId: 'img_earliest_canonical',
          groupId: 'grp_pooja',
          imageUrl:
              'https://res.cloudinary.com/worship/image/upload/v1/pooja_crown.jpg',
          uploadedBy: 'user_1',
          uploadedByName: 'Pooja Devotee',
          uploadedAt: t0, // Earliest!
        ),
        GroupGalleryImage(
          imageId: 'img_later_2',
          groupId: 'grp_rashmika',
          imageUrl:
              'https://res.cloudinary.com/worship/image/upload/q_auto/v2/pooja_crown.webp',
          uploadedBy: 'user_2',
          uploadedByName: 'Rashmika Devotee',
          uploadedAt: t2,
        ),
        GroupGalleryImage(
          imageId: 'img_unique_different',
          groupId: 'grp_pooja',
          imageUrl:
              'https://res.cloudinary.com/worship/image/upload/v1/unique_temple_shrine.jpg',
          uploadedBy: 'user_1',
          uploadedByName: 'Pooja Devotee',
          uploadedAt: t0,
        ),
      ];

      final clusters = await DuplicateDetectionService.scanForDuplicates(
        images: images,
        deepPerceptualScan: false, // Fast URL test
      );

      expect(clusters.length, 1);
      final cluster = clusters.first;
      expect(cluster.canonical.imageId, 'img_earliest_canonical');
      expect(cluster.duplicates.length, 2);
      expect(cluster.totalImages, 3);
      expect(cluster.hasExactMatch, isTrue);

      final duplicateIds = cluster.duplicates.map((d) => d.image.imageId).toList();
      expect(duplicateIds.contains('img_later_1'), isTrue);
      expect(duplicateIds.contains('img_later_2'), isTrue);
      expect(duplicateIds.contains('img_unique_different'), isFalse);
    });

    test('Identifies perceptual near-duplicates via synthetic dHash matching', () async {
      // Simulate images that have cached dHashes
      final imgA = GroupGalleryImage(
        imageId: 'hash_test_A',
        groupId: 'grp_pooja',
        imageUrl: 'https://example.com/photoA.jpg',
        uploadedBy: 'u1',
        uploadedByName: 'Alice',
        uploadedAt: DateTime(2026, 11, 1),
      );
      final imgB = GroupGalleryImage(
        imageId: 'hash_test_B',
        groupId: 'grp_pooja',
        imageUrl: 'https://example.com/photoB_slightly_different.jpg',
        uploadedBy: 'u2',
        uploadedByName: 'Bob',
        uploadedAt: DateTime(2026, 11, 2),
      );

      // Pre-seed hashes: differing by 2 bits (similarity 62/64 = 0.96875)
      await DuplicateDetectionService.cacheHash('hash_test_A', '1111222233334444');
      await DuplicateDetectionService.cacheHash('hash_test_B', '1111222233334445'); // 1 bit diff

      final clusters = await DuplicateDetectionService.scanForDuplicates(
        images: [imgA, imgB],
        deepPerceptualScan: true,
        maxHammingDistance: 6,
      );

      expect(clusters.length, 1);
      expect(clusters.first.canonical.imageId, 'hash_test_A');
      expect(clusters.first.duplicates.length, 1);
      expect(clusters.first.duplicates.first.image.imageId, 'hash_test_B');
      expect(clusters.first.duplicates.first.matchType, DuplicateMatchType.nearDuplicate);
      expect(clusters.first.duplicates.first.similarity, greaterThan(0.95));
    });
  });

  group('DuplicateComparisonSheet Widget Tests', () {
    testWidgets('Renders Canonical Keeper and Duplicate images with metadata and action buttons', (tester) async {
      final canonical = GroupGalleryImage(
        imageId: 'c1',
        groupId: 'grp_1',
        imageUrl: 'https://example.com/canonical.jpg',
        uploadedBy: 'u1',
        uploadedByName: 'Royal Priest',
        uploadedAt: DateTime(2026, 10, 10, 14, 30),
      );

      final duplicateItem = DuplicateItem(
        image: GroupGalleryImage(
          imageId: 'd1',
          groupId: 'grp_1',
          imageUrl: 'https://example.com/duplicate.jpg',
          uploadedBy: 'u2',
          uploadedByName: 'Temple Worshipper',
          uploadedAt: DateTime(2026, 10, 15, 18, 0),
        ),
        matchType: DuplicateMatchType.exactUrl,
        similarity: 1.0,
        hammingDistance: 0,
        groupName: 'Queen Pooja Fortress',
      );

      bool deletePressed = false;
      bool keepBothPressed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DuplicateComparisonSheet(
              canonical: canonical,
              duplicateItem: duplicateItem,
              canonicalGroupName: 'Queen Pooja Fortress',
              onDeleteDuplicate: () => deletePressed = true,
              onKeepBoth: () => keepBothPressed = true,
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.text('Compare Duplicate'), findsOneWidget);
      expect(find.text('👑 Original / Keeper'), findsOneWidget);
      expect(find.text('⚠️ Duplicate'), findsOneWidget);
      expect(find.text('Exact URL (100%)'), findsOneWidget);
      expect(find.text('Keep Both'), findsOneWidget);
      expect(find.text('Delete Duplicate'), findsOneWidget);

      // Tap Delete Duplicate
      await tester.tap(find.text('Delete Duplicate'));
      await tester.pump();
      expect(deletePressed, isTrue);
    });
  });
}
