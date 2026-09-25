import 'dart:developer';
import 'dart:io';
import 'package:cloudinary_flutter/cloudinary_context.dart';
import 'package:cloudinary_url_gen/cloudinary.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

Future<String?> uploadImageToCloudinary(File file, String type) async {
  try {
    log("reached image cloundinary");
    CloudinaryContext.cloudinary = Cloudinary.fromCloudName(
      cloudName: type == "queenPooja"
          ? "debeuo9x0"
          : type == "queenRashmika"
          ? "dnc00qjvj"
          : "djr22nlx9",
    );
    final dio = Dio();
    const url = 'https://api.cloudinary.com/v1_1/debeuo9x0/upload';

    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(file.path),
      'upload_preset': 'ml_default',
    });

    final response = await dio.post(url, data: formData);
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
    debugPrint('Error uploading image: $e');
    return null;
  }
}

Future<String?> uploadVideoToCloudinary(File file, String type) async {
  try {
    CloudinaryContext.cloudinary = Cloudinary.fromCloudName(
      cloudName: type == "queenPooja"
          ? "debeuo9x0"
          : type == "queenRashmika"
          ? "dnc00qjvj"
          : "djr22nlx9",
    );
    final dio = Dio();
    const url = 'https://api.cloudinary.com/v1_1/debeuo9x0/auto/upload';

    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(file.path),
      'upload_preset': 'ml_default',
    });

    final response = await dio.post(url, data: formData);
    log("Upload response $response");
    if (response.statusCode == 200) {
      log("Media URL: ${response.data["secure_url"]}");
      return response.data["secure_url"];
    } else {
      throw Exception('Failed to upload: ${response.data}');
    }
  } catch (e) {
    debugPrint('Error uploading media: $e');
    return null;
  }
}
