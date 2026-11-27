import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:gallery_saver_plus/gallery_saver.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:worship_chat/common/utils/app_capabilities.dart';
import 'package:worship_chat/common/utils/background_task_service.dart';
import 'package:worship_chat/common/utils/utils.dart';
import 'package:worship_chat/models/group_gallery_image.dart';

enum GallerySaveResult { saved, cancelled, failed }

enum GalleryZipStatus { saved, cancelled, failed }

class GalleryZipProgress {
  final int completed;
  final int total;
  final String status;
  final double progress;

  const GalleryZipProgress({
    required this.completed,
    required this.total,
    required this.status,
    required this.progress,
  });
}

class GalleryZipResult {
  final GalleryZipStatus status;
  final String? filePath;
  final String? displayLocation;
  final String? errorMessage;
  final int totalCount;

  const GalleryZipResult({
    required this.status,
    this.filePath,
    this.displayLocation,
    this.errorMessage,
    this.totalCount = 0,
  });
}

/// Uses photo libraries on phones/tablets and native file dialogs on desktops.
class GalleryMediaService {
  final bool isDesktop;
  final Future<void> Function(String url, String path) _download;
  final Future<Directory> Function() _temporaryDirectory;
  final Future<Uri?> Function(String fileName, Uint8List bytes) _saveFile;
  final Future<bool?> Function(String filePath) _saveToAlbum;
  final Future<Uint8List> Function(String url) _fetchBytes;
  final Future<Directory?> Function() _downloadsDirectory;
  final Future<Directory> Function() _documentsDirectory;
  final Future<Uri?> Function(String fileName, Uint8List bytes)? _saveZipFile;

  GalleryMediaService({
    bool? isDesktop,
    Future<void> Function(String url, String path)? download,
    Future<Directory> Function()? temporaryDirectory,
    Future<Uri?> Function(String fileName, Uint8List bytes)? saveFile,
    Future<bool?> Function(String filePath)? saveToAlbum,
    Future<Uint8List> Function(String url)? fetchBytes,
    Future<Directory?> Function()? downloadsDirectory,
    Future<Directory> Function()? documentsDirectory,
    Future<Uri?> Function(String fileName, Uint8List bytes)? saveZipFile,
  }) : isDesktop = isDesktop ?? AppCapabilities.current.isDesktop,
       _download = download ?? _downloadImage,
       _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory,
       _saveFile = saveFile ?? _saveDesktopImage,
       _saveToAlbum = saveToAlbum ?? _saveMobileImage,
       _fetchBytes = fetchBytes ?? _defaultFetchBytes,
       _downloadsDirectory = downloadsDirectory ?? getDownloadsDirectory,
       _documentsDirectory = documentsDirectory ?? getApplicationDocumentsDirectory,
       _saveZipFile = saveZipFile;

  Future<List<File>> pickImages() async {
    if (isDesktop) {
      final picked = await FilePicker.pickFiles(
        dialogTitle: 'Add photos to gallery',
        type: FileType.image,
      );
      return picked
          .map((image) => image.path)
          .whereType<String>()
          .map(File.new)
          .toList();
    }

    final picked = await ImagePicker().pickMultiImage();
    return picked.map((image) => File(image.path)).toList();
  }

  Future<List<File>> pickVideos() async {
    if (isDesktop) {
      final picked = await FilePicker.pickFiles(
        dialogTitle: 'Add videos to gallery',
        type: FileType.video,
      );
      return picked
          .map((video) => video.path)
          .whereType<String>()
          .map(File.new)
          .toList();
    }

    try {
      final picked = await ImagePicker().pickMultipleMedia();
      final videoExtensions = {
        '.mp4',
        '.mov',
        '.avi',
        '.mkv',
        '.webm',
        '.m4v',
        '.3gp',
      };
      final videoFiles = picked
          .where((file) {
            final ext = p.extension(file.path).toLowerCase();
            return videoExtensions.contains(ext);
          })
          .map((f) => File(f.path))
          .toList();

      if (videoFiles.isNotEmpty) return videoFiles;
    } catch (_) {}

    final singleVideo =
        await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (singleVideo != null) {
      return [File(singleVideo.path)];
    }
    return [];
  }

  Future<GallerySaveResult> saveImage({
    required String imageUrl,
    required String imageId,
    bool isVideo = false,
  }) async {
    final isVid = isVideo ||
        imageUrl.contains('/video/upload') ||
        imageUrl.toLowerCase().endsWith('.mp4') ||
        imageUrl.toLowerCase().endsWith('.mov') ||
        imageUrl.toLowerCase().endsWith('.webm') ||
        imageUrl.toLowerCase().endsWith('.m4v');

    return await BackgroundTaskService.instance.runWithBackgroundTask<GallerySaveResult>(
      title: isVid ? 'Downloading Video' : 'Downloading Image',
      initialMessage: isVid ? 'Saving video to device...' : 'Saving image to device...',
      successMessage: isVid ? 'Video saved to gallery' : 'Image saved to gallery',
      task: (_) async {
        final originalUrl = isVid ? imageUrl : getOriginalHighQualityImageUrl(imageUrl);
        final extension = isVid
            ? (p.extension(originalUrl).isNotEmpty
                ? p.extension(originalUrl).replaceFirst('.', '')
                : 'mp4')
            : getImageExtensionFromUrl(originalUrl);
        final safeId = imageId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
        final fileName = '$safeId.$extension';
        final directory = await _temporaryDirectory();
        final temporaryFile = File(
          '${directory.path}/${safeId}_${DateTime.now().microsecondsSinceEpoch}.$extension',
        );

        try {
          await _download(originalUrl, temporaryFile.path);
          if (isDesktop) {
            final destination = await _saveFile(
              fileName,
              await temporaryFile.readAsBytes(),
            );
            return destination == null
                ? GallerySaveResult.cancelled
                : GallerySaveResult.saved;
          }

          return await _saveToAlbum(temporaryFile.path) == true
              ? GallerySaveResult.saved
              : GallerySaveResult.failed;
        } finally {
          if (await temporaryFile.exists()) await temporaryFile.delete();
        }
      },
    );
  }

  /// Saves an already-materialized local image file (for example an edited
  /// Text Remover output) to the user's device album or desktop save picker.
  Future<GallerySaveResult> saveLocalImageFile({
    required File imageFile,
    String? fileName,
  }) async {
    if (!await imageFile.exists()) {
      return GallerySaveResult.failed;
    }

    final resolvedName = (fileName != null && fileName.trim().isNotEmpty)
        ? fileName.trim()
        : p.basename(imageFile.path);

    return await BackgroundTaskService.instance.runWithBackgroundTask<GallerySaveResult>(
      title: 'Saving Cleaned Photo',
      initialMessage: 'Saving photo to device...',
      successMessage: 'Saved cleaned photo to device',
      task: (_) async {
        if (isDesktop) {
          final bytes = await imageFile.readAsBytes();
          final destination = await _saveFile(resolvedName, bytes);
          return destination == null
              ? GallerySaveResult.cancelled
              : GallerySaveResult.saved;
        }

        return await _saveToAlbum(imageFile.path) == true
            ? GallerySaveResult.saved
            : GallerySaveResult.failed;
      },
    );
  }

  /// Downloads all images from a gallery, compresses them into a ZIP archive,
  /// and saves the archive to the platform's destination.
  Future<GalleryZipResult> downloadGalleryAsZip({
    required String groupName,
    required List<GroupGalleryImage> images,
    void Function(GalleryZipProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (images.isEmpty) {
      return const GalleryZipResult(
        status: GalleryZipStatus.failed,
        errorMessage: 'Gallery has no photos to download.',
      );
    }

    if (isCancelled?.call() == true) {
      return const GalleryZipResult(status: GalleryZipStatus.cancelled);
    }

    return await BackgroundTaskService.instance.runWithBackgroundTask<GalleryZipResult>(
      title: 'Downloading Gallery ZIP',
      initialMessage: 'Preparing download of ${images.length} photos...',
      successMessage: 'Saved ${images.length} photos to Downloads',
      task: (updateNotificationProgress) async {
        onProgress?.call(const GalleryZipProgress(
          completed: 0,
          total: 0,
          status: 'Preparing download...',
          progress: 0.0,
        ));

        final archive = Archive();
        final safeGroup = groupName
            .trim()
            .replaceAll(RegExp(r'[^\w\s-]'), '')
            .replaceAll(RegExp(r'\s+'), '_');
        final prefix = safeGroup.isEmpty ? 'gallery' : safeGroup;

        int successCount = 0;

        for (int i = 0; i < images.length; i++) {
          if (isCancelled?.call() == true) {
            return const GalleryZipResult(status: GalleryZipStatus.cancelled);
          }

          final statusStr = 'Downloading photo ${i + 1} of ${images.length}...';
          onProgress?.call(GalleryZipProgress(
            completed: i,
            total: images.length,
            status: statusStr,
            progress: (i / images.length) * 0.85,
          ));
          updateNotificationProgress(
            statusStr,
            progress: i,
            maxProgress: images.length,
          );

          try {
            final img = images[i];
            final originalUrl = getOriginalHighQualityImageUrl(img.imageUrl);
            final extension = getImageExtensionFromUrl(originalUrl);
            final fileName =
                '${prefix}_${(i + 1).toString().padLeft(3, '0')}.$extension';

            final bytes = await _fetchBytes(originalUrl);
            if (bytes.isNotEmpty) {
              archive.addFile(ArchiveFile(fileName, bytes.length, bytes));
              successCount++;
            }
          } catch (e) {
            log('Error downloading gallery image $i: $e');
          }
        }

        if (isCancelled?.call() == true) {
          return const GalleryZipResult(status: GalleryZipStatus.cancelled);
        }

        if (successCount == 0 || archive.isEmpty) {
          return const GalleryZipResult(
            status: GalleryZipStatus.failed,
            errorMessage: 'Could not download photos from gallery.',
          );
        }

        onProgress?.call(GalleryZipProgress(
          completed: images.length,
          total: images.length,
          status: 'Compressing $successCount photos into ZIP...',
          progress: 0.90,
        ));
        updateNotificationProgress(
          'Compressing $successCount photos into ZIP...',
          progress: images.length,
          maxProgress: images.length,
        );

        final zipBytes = ZipEncoder().encode(archive);
        if (zipBytes.isEmpty) {
          return const GalleryZipResult(
            status: GalleryZipStatus.failed,
            errorMessage: 'Failed to compress gallery into ZIP.',
          );
        }

        if (isCancelled?.call() == true) {
          return const GalleryZipResult(status: GalleryZipStatus.cancelled);
        }

        onProgress?.call(GalleryZipProgress(
          completed: images.length,
          total: images.length,
          status: 'Saving ZIP archive...',
          progress: 0.96,
        ));
        updateNotificationProgress('Saving ZIP archive...');

        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final zipFileName = '${prefix}_gallery_$timestamp.zip';
        final byteData = Uint8List.fromList(zipBytes);

        if (isDesktop) {
          final saveMethod = _saveZipFile ?? _saveDesktopZip;
          final uri = await saveMethod(zipFileName, byteData);
          if (uri == null) {
            return const GalleryZipResult(status: GalleryZipStatus.cancelled);
          }
          String path;
          try {
            path = uri.isScheme('file') ? uri.toFilePath() : uri.path;
          } catch (_) {
            path = uri.path;
          }
          return GalleryZipResult(
            status: GalleryZipStatus.saved,
            filePath: path,
            displayLocation: path,
            totalCount: successCount,
          );
        }

        // Mobile / Tablet platforms
        Directory? targetDir;
        String displayLoc;

        if (Platform.isAndroid) {
          try {
            final status = await Permission.storage.status;
            if (!status.isGranted) {
              await Permission.storage.request();
            }
          } catch (_) {}

          final publicDownload =
              Directory('/storage/emulated/0/Download/WorshipChat');
          bool canUsePublic = false;
          try {
            if (!await publicDownload.exists()) {
              await publicDownload.create(recursive: true);
            }
            canUsePublic = await publicDownload.exists();
          } catch (_) {
            canUsePublic = false;
          }

          if (canUsePublic) {
            targetDir = publicDownload;
            displayLoc = 'Downloads/WorshipChat';
          } else {
            final extDir = await getExternalStorageDirectory();
            if (extDir != null) {
              final worshipDir = Directory('${extDir.path}/WorshipChat');
              if (!await worshipDir.exists()) {
                await worshipDir.create(recursive: true);
              }
              targetDir = worshipDir;
              displayLoc = 'External Storage/WorshipChat';
            } else {
              targetDir = await _documentsDirectory();
              displayLoc = 'App Documents';
            }
          }
        } else if (Platform.isIOS) {
          final docDir = await _documentsDirectory();
          final worshipDir = Directory('${docDir.path}/WorshipChat');
          if (!await worshipDir.exists()) {
            await worshipDir.create(recursive: true);
          }
          targetDir = worshipDir;
          displayLoc = 'Files/WorshipChat';
        } else {
          final downloads = await _downloadsDirectory();
          targetDir = downloads ?? await _documentsDirectory();
          displayLoc = targetDir.path;
        }

        if (!await targetDir.exists()) {
          await targetDir.create(recursive: true);
        }

        final savedFile = File('${targetDir.path}/$zipFileName');
        await savedFile.writeAsBytes(byteData);

        return GalleryZipResult(
          status: GalleryZipStatus.saved,
          filePath: savedFile.path,
          displayLocation: displayLoc,
          totalCount: successCount,
        );
      },
    );
  }

  /// Downloads all images from a gallery, scales them smoothly, compiles them into
  /// an animated GIF loop, and saves the file to the user's gallery / downloads.
  Future<GallerySaveResult> downloadGalleryAsGif({
    required String groupName,
    required List<GroupGalleryImage> images,
    void Function(String status, double progress)? onProgress,
    bool Function()? isCancelled,
    int delayHundredths = 65, // ~650ms per frame
    int targetSize = 480,
  }) async {
    if (images.isEmpty) {
      return GallerySaveResult.failed;
    }

    if (isCancelled?.call() == true) {
      return GallerySaveResult.cancelled;
    }

    return await BackgroundTaskService.instance.runWithBackgroundTask<GallerySaveResult>(
      title: 'Creating Gallery GIF',
      initialMessage: 'Preparing ${images.length} photos for animated GIF...',
      successMessage: 'Animated GIF saved to gallery',
      task: (updateNotificationProgress) async {
        final safeGroup = groupName
            .trim()
            .replaceAll(RegExp(r'[^\w\s-]'), '')
            .replaceAll(RegExp(r'\s+'), '_');
        final prefix = safeGroup.isEmpty ? 'gallery' : safeGroup;

        final encoder = img.GifEncoder(
          delay: delayHundredths,
          repeat: 0, // loop indefinitely
          samplingFactor: 10,
        );

        int processedFrames = 0;

        for (int i = 0; i < images.length; i++) {
          if (isCancelled?.call() == true) {
            return GallerySaveResult.cancelled;
          }

          final statusStr = 'Adding photo ${i + 1} of ${images.length} to GIF...';
          onProgress?.call(statusStr, (i / images.length) * 0.85);
          updateNotificationProgress(
            statusStr,
            progress: i,
            maxProgress: images.length,
          );

          try {
            final imgItem = images[i];
            final originalUrl = getOriginalHighQualityImageUrl(imgItem.imageUrl);
            final bytes = await _fetchBytes(originalUrl);
            if (bytes.isNotEmpty) {
              final decoded = img.decodeImage(bytes);
              if (decoded != null) {
                final int width;
                final int? height;
                if (decoded.width >= decoded.height) {
                  width = targetSize;
                  height = null;
                } else {
                  width = (targetSize * (decoded.width / decoded.height)).round();
                  height = targetSize;
                }
                final resized = img.copyResize(
                  decoded,
                  width: width,
                  height: height,
                  interpolation: img.Interpolation.linear,
                );
                encoder.addFrame(resized);
                processedFrames++;
              }
            }
          } catch (e) {
            log('Error processing image $i for GIF: $e');
          }
        }

        if (isCancelled?.call() == true) {
          return GallerySaveResult.cancelled;
        }

        if (processedFrames == 0) {
          return GallerySaveResult.failed;
        }

        onProgress?.call('Encoding animated GIF loop...', 0.90);
        updateNotificationProgress(
          'Encoding animated GIF loop...',
          progress: images.length,
          maxProgress: images.length,
        );

        final gifData = encoder.finish();
        if (gifData == null || gifData.isEmpty) {
          return GallerySaveResult.failed;
        }

        final gifBytes = Uint8List.fromList(gifData);
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final gifFileName = '${prefix}_gallery_$timestamp.gif';

        if (isDesktop) {
          final uri = await FilePicker.saveFile(
            dialogTitle: 'Save Gallery Animated GIF',
            fileName: gifFileName,
            bytes: gifBytes,
            type: FileType.custom,
            allowedExtensions: ['gif'],
          );
          return uri == null
              ? GallerySaveResult.cancelled
              : GallerySaveResult.saved;
        }

        // Mobile / Tablet: save to temp file then to device album
        final tempDir = await _temporaryDirectory();
        final tempFile = File('${tempDir.path}/$gifFileName');
        await tempFile.writeAsBytes(gifBytes);

        // Also save copy to Download/WorshipChat on Android for easy file access
        if (Platform.isAndroid) {
          try {
            final publicDir = Directory('/storage/emulated/0/Download/WorshipChat');
            if (!await publicDir.exists()) {
              await publicDir.create(recursive: true);
            }
            if (await publicDir.exists()) {
              final pubFile = File('${publicDir.path}/$gifFileName');
              await pubFile.writeAsBytes(gifBytes);
            }
          } catch (_) {}
        }

        final saved = await _saveToAlbum(tempFile.path);
        if (await tempFile.exists()) {
          try {
            await tempFile.delete();
          } catch (_) {}
        }

        return saved == true ? GallerySaveResult.saved : GallerySaveResult.failed;
      },
    );
  }

  static Future<void> _downloadImage(String url, String path) async {
    await Dio().download(
      url,
      path,
      options: Options(responseType: ResponseType.bytes, followRedirects: true),
    );
  }

  static Future<Uint8List> _defaultFetchBytes(String url) async {
    final response = await Dio().get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes, followRedirects: true),
    );
    final data = response.data;
    if (data == null) throw StateError('Empty response from $url');
    return Uint8List.fromList(data);
  }

  static Future<Uri?> _saveDesktopImage(String fileName, Uint8List bytes) {
    final ext = p.extension(fileName).toLowerCase();
    final isVideo = ext == '.mp4' ||
        ext == '.mov' ||
        ext == '.avi' ||
        ext == '.mkv' ||
        ext == '.webm' ||
        ext == '.m4v' ||
        ext == '.3gp';
    return FilePicker.saveFile(
      dialogTitle: isVideo ? 'Save video' : 'Save photo',
      fileName: fileName,
      bytes: bytes,
      type: isVideo ? FileType.video : FileType.image,
    );
  }

  static Future<Uri?> _saveDesktopZip(String fileName, Uint8List bytes) {
    return FilePicker.saveFile(
      dialogTitle: 'Save Gallery ZIP',
      fileName: fileName,
      bytes: bytes,
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
  }

  static Future<bool?> _saveMobileImage(String filePath) {
    final ext = p.extension(filePath).toLowerCase();
    final isVideo = ext == '.mp4' ||
        ext == '.mov' ||
        ext == '.avi' ||
        ext == '.mkv' ||
        ext == '.webm' ||
        ext == '.m4v' ||
        ext == '.3gp';
    if (isVideo) {
      return GallerySaver.saveVideo(
        filePath,
        albumName: 'Worship Chat',
        toDcim: false,
      );
    }
    return GallerySaver.saveImage(
      filePath,
      albumName: 'Worship Chat',
      toDcim: false,
    );
  }
}
