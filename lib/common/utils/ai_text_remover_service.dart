import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:worship_chat/common/utils/ai_inpainting_service.dart';

class DetectedTextBlock {
  final String text;
  final Rect boundingBox;

  DetectedTextBlock({required this.text, required this.boundingBox});
}

/// 100% Free, On-Device, Open-Source Text Detection and Removal Service
class AiTextRemoverService {
  AiTextRemoverService._();
  static final AiTextRemoverService instance = AiTextRemoverService._();

  TextRecognizer? _textRecognizer;

  TextRecognizer get _getRecognizer {
    _textRecognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
    return _textRecognizer!;
  }

  /// Scans the image on-device using ML Kit OCR and returns detected text bounding boxes
  Future<List<DetectedTextBlock>> detectText(File sourceImage) async {
    final inputImage = InputImage.fromFile(sourceImage);
    final RecognizedText recognizedText = await _getRecognizer.processImage(inputImage);

    final List<DetectedTextBlock> blocks = [];
    for (final block in recognizedText.blocks) {
      for (final line in block.lines) {
        blocks.add(
          DetectedTextBlock(
            text: line.text,
            boundingBox: line.boundingBox,
          ),
        );
      }
    }
    return blocks;
  }

  /// Automatically erases all detected text blocks from the source image.
  Future<File> eraseDetectedText({
    required File sourceImage,
    required List<Rect> textRects,
    required String outputPath,
  }) async {
    final imageBytes = await sourceImage.readAsBytes();
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) return sourceImage;

    final imgW = decoded.width;
    final imgH = decoded.height;

    // Generate binary mask for all text rects
    final maskBytes = Uint8List(imgW * imgH);

    for (final rect in textRects) {
      const pad = 6;
      final left = (rect.left - pad).floor().clamp(0, imgW - 1);
      final top = (rect.top - pad).floor().clamp(0, imgH - 1);
      final right = (rect.right + pad).ceil().clamp(0, imgW - 1);
      final bottom = (rect.bottom + pad).ceil().clamp(0, imgH - 1);

      for (int y = top; y <= bottom; y++) {
        final row = y * imgW;
        for (int x = left; x <= right; x++) {
          maskBytes[row + x] = 255;
        }
      }
    }

    // Run inpainting on the text mask
    return AiInpaintingService.instance.inpaintImage(
      sourceImage: sourceImage,
      maskBytes: maskBytes,
      maskWidth: imgW,
      maskHeight: imgH,
      outputPath: outputPath,
      patchRadius: 5,
    );
  }

  void dispose() {
    _textRecognizer?.close();
    _textRecognizer = null;
  }
}
