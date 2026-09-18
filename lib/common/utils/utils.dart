import 'dart:developer';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:giphy_picker/giphy_picker.dart';
import 'package:image_picker/image_picker.dart';

void showSnackBar({required BuildContext context, required String content}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(content)));
}

Future<File?> pickImageFromGallery(BuildContext context) async {
  File? image;
  try {
    final pickedImage = await ImagePicker().pickImage(
      source: ImageSource.gallery,
    );
    if (pickedImage != null) {
      image = File(pickedImage.path);
    }
    return image;
  } catch (e) {
    log("$e");
    showSnackBar(context: context, content: e.toString());
  }
  return null;
}

Future<File?> pickVideoFromGallery(BuildContext context) async {
  File? video;
  try {
    final pickedVideo = await ImagePicker().pickVideo(
      source: ImageSource.gallery,
    );
    if (pickedVideo != null) {
      video = File(pickedVideo.path);
    }
    return video;
  } catch (e) {
    log("$e");
    showSnackBar(context: context, content: e.toString());
  }
  return null;
}

Future<GiphyGif?> pickGif(BuildContext context) async {
  final Future<GiphyGif?> giphy;
  try {
    giphy = GiphyPicker.pickGif(
      context: context,
      fullScreenDialog: false,
      apiKey: 'IoSdm6GnFNpQM19f0HOGhhxiwLkvY1Ki',
    );
  } catch (e) {
    debugPrint('GIF selection failed: $e');
    return null;
  }
  return giphy;
}
