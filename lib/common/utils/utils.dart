import 'dart:developer';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'package:worship_chat/common/widgets/custom_snackbar.dart';

export 'package:worship_chat/common/widgets/custom_snackbar.dart';

void showSnackBar({
  required BuildContext context,
  required String content,
  String? title,
  SnackBarType? type,
  Duration duration = const Duration(milliseconds: 3200),
  String? actionLabel,
  VoidCallback? onAction,
  IconData? customIcon,
}) {
  AppSnackBar.show(
    context,
    message: content,
    title: title,
    type: type,
    duration: duration,
    actionLabel: actionLabel,
    onAction: onAction,
    customIcon: customIcon,
  );
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

/// Pick multiple images from the gallery (returns a list, possibly empty).
Future<List<File>> pickMultipleImagesFromGallery(BuildContext context) async {
  try {
    final pickedImages = await ImagePicker().pickMultiImage();
    if (pickedImages.isNotEmpty) {
      return pickedImages.map((x) => File(x.path)).toList();
    }
  } catch (e) {
    log('pickMultipleImagesFromGallery: $e');
    showSnackBar(context: context, content: e.toString());
  }
  return [];
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

/// Pick multiple videos from the gallery using FilePicker (returns a list).
Future<List<File>> pickMultipleVideosFromGallery(BuildContext context) async {
  try {
    // FilePicker.pickFiles() in v13 always returns List<PlatformFile>
    // and natively supports multi-pick.
    final files = await FilePicker.pickFiles(type: FileType.video);
    if (files.isNotEmpty) {
      return files
          .where((pf) => pf.path != null)
          .map((pf) => File(pf.path!))
          .toList();
    }
  } catch (e) {
    log('pickMultipleVideosFromGallery: $e');
    showSnackBar(context: context, content: e.toString());
  }
  return [];
}

/// Converts keyboard-inserted content (e.g. GIFs/stickers chosen from Gboard/keyboard)
/// into a local File suitable for preview and Cloudinary upload.
Future<File?> getFileFromKeyboardInsertedContent(
  KeyboardInsertedContent content, [
  Directory? targetDir,
]) async {
  try {
    String ext = 'gif';
    final mime = content.mimeType.toLowerCase();
    if (mime.contains('png')) {
      ext = 'png';
    } else if (mime.contains('jpeg') || mime.contains('jpg')) {
      ext = 'jpg';
    } else if (mime.contains('webp')) {
      ext = 'webp';
    } else if (mime.contains('gif')) {
      ext = 'gif';
    } else if (content.uri.contains('.')) {
      final uriExt = content.uri.split('.').last.split('?').first.toLowerCase();
      if (['gif', 'png', 'jpg', 'jpeg', 'webp'].contains(uriExt)) {
        ext = uriExt;
      }
    }

    final dir = targetDir ?? await getTemporaryDirectory();
    final tempFilePath =
        '${dir.path}/kb_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final tempFile = File(tempFilePath);

    // 1. Direct inline data
    if (content.data != null && content.data!.isNotEmpty) {
      await tempFile.writeAsBytes(content.data!);
      log('✅ Saved keyboard content directly from bytes (${content.data!.length} bytes) to $tempFilePath');
      return tempFile;
    }

    final uriStr = content.uri.trim();
    if (uriStr.isEmpty) return null;

    // 2. Android content:// URI
    if (uriStr.startsWith('content://')) {
      const platform = MethodChannel('my.app/accounts');
      try {
        final dynamic pathResult = await platform.invokeMethod('getFilePath', {
          'uri': uriStr,
        });
        if (pathResult != null &&
            pathResult is String &&
            pathResult.isNotEmpty) {
          final f = File(pathResult);
          if (await f.exists()) {
            log('✅ Retrieved file path from platform channel: $pathResult');
            return f;
          }
        }
      } catch (e) {
        log('Warning: getFilePath platform call failed: $e');
      }

      try {
        final dynamic rawBytes = await platform.invokeMethod('readContentUri', {
          'uri': uriStr,
        });
        if (rawBytes != null) {
          final bytes = Uint8List.fromList(List<int>.from(rawBytes));
          if (bytes.isNotEmpty) {
            await tempFile.writeAsBytes(bytes);
            log('✅ Read bytes from content URI via platform channel (${bytes.length} bytes)');
            return tempFile;
          }
        }
      } catch (e) {
        log('Warning: readContentUri platform call failed: $e');
      }
    }

    // 3. file:// URI or local file path
    if (uriStr.startsWith('file://')) {
      final f = File(uriStr.replaceFirst('file://', ''));
      if (await f.exists()) return f;
    } else if (!uriStr.startsWith('http://') && !uriStr.startsWith('https://')) {
      final f = File(uriStr);
      if (await f.exists()) return f;
    }

    // 4. Remote network URL (some keyboards provide http/https URLs)
    if (uriStr.startsWith('http://') || uriStr.startsWith('https://')) {
      final dio = Dio();
      final response = await dio.get<List<int>>(
        uriStr,
        options: Options(responseType: ResponseType.bytes),
      );
      if (response.statusCode == 200 && response.data != null) {
        await tempFile.writeAsBytes(response.data!);
        log('✅ Downloaded keyboard content from URL to $tempFilePath');
        return tempFile;
      }
    }
  } catch (e) {
    log('❌ Error processing keyboard inserted content: $e');
  }
  return null;
}

/// Pick any file / document (.pdf, .zip, .mp3, .apk, .docx, etc.)
Future<File?> pickDocumentFile(BuildContext context) async {
  try {
    final result = await FilePicker.pickFiles(
      type: FileType.any,
    );
    if (result.isNotEmpty && result.first.path != null) {
      final pickedPath = result.first.path!;
      final file = File(pickedPath);
      if (await file.exists()) {
        final length = await file.length();
        log('✅ Selected document: ${result.first.name} ($length bytes)');
        return file;
      }
    }
  } catch (e) {
    log('❌ Error picking document: $e');
    showSnackBar(context: context, content: 'Could not select file: $e');
  }
  return null;
}

/// Ensures the given image URL points to the pristine, uncompressed, highest-quality original.
/// If it's a Cloudinary URL that contains transformation parameters (e.g. `f_auto`, `q_auto`,
/// `w_1080`, `c_scale`), those transforms are stripped so the original full-resolution asset
/// is fetched.
String getOriginalHighQualityImageUrl(String url) {
  if (url.trim().isEmpty) return url;
  var cleaned = url.trim().replaceFirst('http://', 'https://');

  // Cloudinary URL cleaning
  const uploadToken = '/upload/';
  final uploadIdx = cleaned.indexOf(uploadToken);
  if (uploadIdx != -1) {
    final afterUpload = cleaned.substring(uploadIdx + uploadToken.length);

    // If there is a version prefix (v1234567/...), everything before it is transformation parameters
    final versionRegex = RegExp(r'^(?:[^\/]+\/)*(v\d+\/.+)$');
    final match = versionRegex.firstMatch(afterUpload);
    if (match != null) {
      cleaned = cleaned.substring(0, uploadIdx + uploadToken.length) + match.group(1)!;
    } else {
      // If there is no version prefix, check if the first path segment is a transformation segment
      final slashIdx = afterUpload.indexOf('/');
      if (slashIdx != -1) {
        final firstSegment = afterUpload.substring(0, slashIdx);
        // Typical Cloudinary transforms contain commas or underscore tags (w_, h_, q_, f_, c_, etc.)
        if (firstSegment.contains(',') ||
            RegExp(r'^(?:[a-z]{1,3}_[a-zA-Z0-9_:\.-]+)+$').hasMatch(firstSegment)) {
          cleaned = cleaned.substring(0, uploadIdx + uploadToken.length) +
              afterUpload.substring(slashIdx + 1);
        }
      }
    }
  }

  return cleaned;
}

/// Extracts a clean file extension from a media URL (e.g. 'jpg', 'png', 'webp', 'gif').
/// Defaults to [defaultExt] (e.g. 'jpg') if none can be identified.
String getImageExtensionFromUrl(String url, {String defaultExt = 'jpg'}) {
  try {
    final uri = Uri.parse(url);
    final path = uri.path;
    final lastDot = path.lastIndexOf('.');
    if (lastDot != -1 && lastDot < path.length - 1) {
      final ext = path.substring(lastDot + 1).toLowerCase();
      if (['jpg', 'jpeg', 'png', 'webp', 'heic', 'gif', 'bmp'].contains(ext)) {
        return ext;
      }
    }
  } catch (_) {}
  return defaultExt;
}

