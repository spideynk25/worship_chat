import 'dart:developer';
import 'dart:io';
import 'package:cloudinary_flutter/cloudinary_context.dart';
import 'package:cloudinary_url_gen/cloudinary.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

final Dio _uploadDio = Dio(
  BaseOptions(
    connectTimeout: const Duration(seconds: 45),
    receiveTimeout: const Duration(seconds: 120),
    sendTimeout: const Duration(seconds: 120),
  ),
);

Future<String?> uploadImageToCloudinary(
  File file,
  String type, {
  void Function(int sent, int total)? onProgress,
}) async {
  int attempts = 0;
  while (attempts < 3) {
    attempts++;
    try {
      log("reached image cloudinary (attempt $attempts)");
      CloudinaryContext.cloudinary = Cloudinary.fromCloudName(
        cloudName: type == "queenPooja"
            ? "debeuo9x0"
            : type == "queenRashmika"
            ? "dnc00qjvj"
            : "djr22nlx9",
      );
      const url = 'https://api.cloudinary.com/v1_1/debeuo9x0/upload';

      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(file.path),
        'upload_preset': 'ml_default',
      });

      final response = await _uploadDio.post(
        url,
        data: formData,
        onSendProgress: onProgress,
      );
      log("image response $response");
      if (response.statusCode == 200) {
        final raw = response.data["secure_url"] as String? ??
            response.data["url"] as String? ??
            '';
        final cleanUrl = raw.startsWith('http://')
            ? raw.replaceFirst('http://', 'https://')
            : raw;
        log("Image url $cleanUrl");
        return cleanUrl;
      } else {
        throw Exception('Failed to upload image: ${response.data}');
      }
    } catch (e) {
      debugPrint('Error uploading image (attempt $attempts): $e');
      if (attempts >= 3) return null;
      await Future.delayed(Duration(milliseconds: 1000 * attempts));
    }
  }
  return null;
}

Future<String?> uploadVideoToCloudinary(
  File file,
  String type, {
  void Function(int sent, int total)? onProgress,
}) async {
  int attempts = 0;
  while (attempts < 3) {
    attempts++;
    try {
      CloudinaryContext.cloudinary = Cloudinary.fromCloudName(
        cloudName: type == "queenPooja"
            ? "debeuo9x0"
            : type == "queenRashmika"
            ? "dnc00qjvj"
            : "djr22nlx9",
      );
      const url = 'https://api.cloudinary.com/v1_1/debeuo9x0/auto/upload';

      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(file.path),
        'upload_preset': 'ml_default',
      });

      final response = await _uploadDio.post(
        url,
        data: formData,
        onSendProgress: onProgress,
      );
      log("Upload response $response");
      if (response.statusCode == 200) {
        log("Media URL: ${response.data["secure_url"]}");
        return response.data["secure_url"];
      } else {
        throw Exception('Failed to upload: ${response.data}');
      }
    } catch (e) {
      debugPrint('Error uploading media (attempt $attempts): $e');
      if (attempts >= 3) return null;
      await Future.delayed(Duration(milliseconds: 1000 * attempts));
    }
  }
  return null;
}

Future<String?> uploadDocumentToCloudinary(
  File file,
  String type, {
  void Function(int sent, int total)? onProgress,
}) async {
  int attempts = 0;
  while (attempts < 3) {
    attempts++;
    try {
      CloudinaryContext.cloudinary = Cloudinary.fromCloudName(
        cloudName: type == "queenPooja"
            ? "debeuo9x0"
            : type == "queenRashmika"
            ? "dnc00qjvj"
            : "djr22nlx9",
      );
      const url = 'https://api.cloudinary.com/v1_1/debeuo9x0/auto/upload';

      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(file.path),
        'upload_preset': 'ml_default',
      });

      final response = await _uploadDio.post(
        url,
        data: formData,
        onSendProgress: onProgress,
      );
      log("Document upload response $response");
      if (response.statusCode == 200) {
        final raw = response.data["secure_url"] as String? ??
            response.data["url"] as String? ??
            '';
        final cleanUrl = raw.startsWith('http://')
            ? raw.replaceFirst('http://', 'https://')
            : raw;
        log("Document URL: $cleanUrl");
        return cleanUrl;
      } else {
        throw Exception('Failed to upload document: ${response.data}');
      }
    } catch (e) {
      debugPrint('Error uploading document (attempt $attempts): $e');
      if (attempts >= 3) return null;
      await Future.delayed(Duration(milliseconds: 1000 * attempts));
    }
  }
  return null;
}

