import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('convert crown assets to transparent PNG', () async {
    final frontFile = File('/Users/nandhakumar/.gemini/antigravity/brain/9d8e4d9b-b461-4a7b-96a6-6e732447b51f/aura_elixiria_front_1794743129657.jpg');
    final backFile = File('/Users/nandhakumar/.gemini/antigravity/brain/9d8e4d9b-b461-4a7b-96a6-6e732447b51f/aura_elixiria_back_1794743159548.jpg');
    final profileFile = File('/Users/nandhakumar/.gemini/antigravity/brain/9d8e4d9b-b461-4a7b-96a6-6e732447b51f/aura_elixiria_profile_1794743495796.jpg');

    Future<void> processImage(File inputFile, String outputRelativePath) async {
      final bytes = inputFile.readAsBytesSync();
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

          // Distance from pure white
          final minC = r < g ? (r < b ? r : b) : (g < b ? g : b);
          final diffFromWhite = 255 - minC;

          if (diffFromWhite <= 2) {
            // Pure white background -> completely transparent
            outPixels[idx + 3] = 0;
          } else if (diffFromWhite < 18) {
            // Anti-aliased boundary: smooth transition and de-saturate background white
            final alphaFraction = diffFromWhite / 18.0;
            outPixels[idx + 3] = (alphaFraction * 255).round().clamp(0, 255);
            // Color de-fringing: remove the white contribution
            final rOrig = ((r - 255 * (1.0 - alphaFraction)) / alphaFraction).round().clamp(0, 255);
            final gOrig = ((g - 255 * (1.0 - alphaFraction)) / alphaFraction).round().clamp(0, 255);
            final bOrig = ((b - 255 * (1.0 - alphaFraction)) / alphaFraction).round().clamp(0, 255);
            outPixels[idx] = rOrig;
            outPixels[idx + 1] = gOrig;
            outPixels[idx + 2] = bOrig;
          } else {
            // Solid foreground
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
      final outFile = File(outputRelativePath);
      outFile.writeAsBytesSync(pngBytes!.buffer.asUint8List());
      print('Saved: ${outFile.path} (${outImage.width}x${outImage.height})');
    }

    // Process front, rear and profile
    await processImage(frontFile, 'assets/emojis/aura_elixiria.png');
    await processImage(backFile, 'assets/emojis/aura_elixiria_rear.png');
    await processImage(profileFile, 'assets/emojis/aura_elixiria_profile.png');
  });
}
