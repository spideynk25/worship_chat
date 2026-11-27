import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_chat/features/group/widgets/royal_3d_crown_widget.dart';

void main() {
  test('dump rear image', () async {
    final img = RearCrownGenerator.getOrCreate(accentColor: const Color(0xFFE5A93C));
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    final buffer = byteData!.buffer.asUint8List();
    File('/Users/nandhakumar/.gemini/antigravity/brain/9d8e4d9b-b461-4a7b-96a6-6e732447b51f/rear_crown_generated.png')
        .writeAsBytesSync(buffer);
    print('Saved rear image');
  });
}
