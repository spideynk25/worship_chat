import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('convert queen rear and profile to transparent PNG', () async {
    Future<void> convertToTransparentPng(File inFile, String outPath) async {
      final bytes = inFile.readAsBytesSync();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final raw = byteData!.buffer.asUint8List();

      final width = image.width;
      final height = image.height;
      final outPixels = List<int>.from(raw);

      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final idx = (y * width + x) * 4;
          final r = raw[idx];
          final g = raw[idx + 1];
          final b = raw[idx + 2];

          final minC = r < g ? (r < b ? r : b) : (g < b ? g : b);
          final diffFromWhite = 255 - minC;

          if (diffFromWhite <= 3) {
            outPixels[idx + 3] = 0;
          } else if (diffFromWhite < 25) {
            final alphaFraction = diffFromWhite / 25.0;
            outPixels[idx + 3] = (alphaFraction * 255).round().clamp(0, 255);
            final rOrig = ((r - 255 * (1.0 - alphaFraction)) / alphaFraction).round().clamp(0, 255);
            final gOrig = ((g - 255 * (1.0 - alphaFraction)) / alphaFraction).round().clamp(0, 255);
            final bOrig = ((b - 255 * (1.0 - alphaFraction)) / alphaFraction).round().clamp(0, 255);
            outPixels[idx] = rOrig;
            outPixels[idx + 1] = gOrig;
            outPixels[idx + 2] = bOrig;
          } else {
            outPixels[idx + 3] = 255;
          }
        }
      }

      final outBuffer = await ui.ImmutableBuffer.fromUint8List(Uint8List.fromList(outPixels));
      final descriptor = ui.ImageDescriptor.raw(
        outBuffer,
        width: width,
        height: height,
        pixelFormat: ui.PixelFormat.rgba8888,
      );
      final outCodec = await descriptor.instantiateCodec();
      final outFrame = await outCodec.getNextFrame();
      final outImage = outFrame.image;

      final pngBytes = await outImage.toByteData(format: ui.ImageByteFormat.png);
      final outFile = File(outPath);
      outFile.writeAsBytesSync(pngBytes!.buffer.asUint8List());
      print('Saved: $outPath (${outImage.width}x${outImage.height})');
    }

    await convertToTransparentPng(
      File('/Users/nandhakumar/.gemini/antigravity/brain/9d8e4d9b-b461-4a7b-96a6-6e732447b51f/queen_rear_1794761238731.jpg'),
      'assets/emojis/queen_rear.png',
    );
    await convertToTransparentPng(
      File('/Users/nandhakumar/.gemini/antigravity/brain/9d8e4d9b-b461-4a7b-96a6-6e732447b51f/queen_profile_v2_1794761304320.jpg'),
      'assets/emojis/queen_profile.png',
    );
  });
}
