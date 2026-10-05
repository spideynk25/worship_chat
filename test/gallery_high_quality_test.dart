import 'package:flutter_test/flutter_test.dart';
import 'package:worship_chat/common/utils/utils.dart';

void main() {
  group('Gallery High Quality URL and Extension Tests', () {
    test('getOriginalHighQualityImageUrl strips Cloudinary lossy transformations before version tag', () {
      const transformedUrl =
          'https://res.cloudinary.com/debeuo9x0/image/upload/f_auto,q_auto,w_1080/v1742410000/gallery/sample.jpg';
      final clean = getOriginalHighQualityImageUrl(transformedUrl);
      expect(
        clean,
        equals(
          'https://res.cloudinary.com/debeuo9x0/image/upload/v1742410000/gallery/sample.jpg',
        ),
      );
    });

    test('getOriginalHighQualityImageUrl preserves already pristine Cloudinary URL with version tag', () {
      const pristineUrl =
          'https://res.cloudinary.com/debeuo9x0/image/upload/v1742410000/gallery/sample.jpg';
      final clean = getOriginalHighQualityImageUrl(pristineUrl);
      expect(clean, equals(pristineUrl));
    });

    test('getOriginalHighQualityImageUrl strips transformations when no version tag is present', () {
      const transformedUrl =
          'https://res.cloudinary.com/debeuo9x0/image/upload/w_1200,c_scale/gallery/sample.png';
      final clean = getOriginalHighQualityImageUrl(transformedUrl);
      expect(
        clean,
        equals(
          'https://res.cloudinary.com/debeuo9x0/image/upload/gallery/sample.png',
        ),
      );
    });

    test('getOriginalHighQualityImageUrl upgrades insecure http to https', () {
      const httpUrl =
          'http://res.cloudinary.com/debeuo9x0/image/upload/v12345/pic.jpg';
      final clean = getOriginalHighQualityImageUrl(httpUrl);
      expect(
        clean,
        equals(
          'https://res.cloudinary.com/debeuo9x0/image/upload/v12345/pic.jpg',
        ),
      );
    });

    test('getOriginalHighQualityImageUrl handles non-Cloudinary URLs safely', () {
      const standardUrl = 'https://images.unsplash.com/photo-12345678.jpg';
      final clean = getOriginalHighQualityImageUrl(standardUrl);
      expect(clean, equals(standardUrl));
    });

    test('getImageExtensionFromUrl detects standard extensions correctly', () {
      expect(
        getImageExtensionFromUrl('https://example.com/images/cat.png'),
        equals('png'),
      );
      expect(
        getImageExtensionFromUrl('https://example.com/images/dog.jpeg'),
        equals('jpeg'),
      );
      expect(
        getImageExtensionFromUrl('https://example.com/images/photo.webp'),
        equals('webp'),
      );
      expect(
        getImageExtensionFromUrl('https://res.cloudinary.com/test/image/upload/v1/pic.jpg'),
        equals('jpg'),
      );
    });

    test('getImageExtensionFromUrl falls back to defaultExt for URLs without extension', () {
      expect(
        getImageExtensionFromUrl('https://example.com/api/image/raw_id'),
        equals('jpg'),
      );
      expect(
        getImageExtensionFromUrl(
          'https://example.com/api/image/raw_id',
          defaultExt: 'png',
        ),
        equals('png'),
      );
    });
  });
}
