import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class CameraPermissionHandler {
  static Future<bool> requestCameraPermission(BuildContext context) async {
    final cameraStatus = await Permission.camera.status;
    final microphoneStatus = await Permission.microphone.status;

    if (cameraStatus.isGranted && microphoneStatus.isGranted) {
      return true;
    }

    // Request permissions
    Map<Permission, PermissionStatus> statuses = await [
      Permission.camera,
      Permission.microphone,
    ].request();

    final cameraGranted = statuses[Permission.camera]?.isGranted ?? false;
    final microphoneGranted = statuses[Permission.microphone]?.isGranted ?? false;

    if (cameraGranted && microphoneGranted) {
      return true;
    }

    // Check if permanently denied
    if (statuses[Permission.camera]?.isPermanentlyDenied ?? false ||
        statuses[Permission.microphone]!.isPermanentlyDenied ?? false) {
      if (context.mounted) {
        _showPermissionDeniedDialog(context);
      }
      return false;
    }

    // Permission denied
    if (context.mounted) {
      _showPermissionRequiredSnackbar(context);
    }
    return false;
  }

  static void _showPermissionDeniedDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Camera Permission Required'),
        content: const Text(
          'Camera and microphone permissions are required to take photos and videos. '
          'Please enable them in your device settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  static void _showPermissionRequiredSnackbar(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Camera and microphone permissions are required'),
        duration: Duration(seconds: 3),
      ),
    );
  }
}