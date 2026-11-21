import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_handler/share_handler.dart';

enum SharedPayloadType {
  image,
  video,
  text,
  file,
}

class SharedPayload {
  final List<File> files;
  final String? text;
  final SharedPayloadType type;

  const SharedPayload({
    this.files = const [],
    this.text,
    required this.type,
  });

  bool get isEmpty =>
      files.isEmpty && (text == null || text!.trim().isEmpty);
  bool get isNotEmpty => !isEmpty;
  bool get isTextOnly =>
      (type == SharedPayloadType.text) ||
      (files.isEmpty && text != null && text!.trim().isNotEmpty);
  bool get isMedia => files.isNotEmpty;
  bool get canUploadToGallery =>
      type == SharedPayloadType.image && files.isNotEmpty;

  bool get isYouTube {
    if (text == null) return false;
    final lower = text!.toLowerCase();
    return lower.contains('youtube.com') || lower.contains('youtu.be');
  }

  bool get isXTwitter {
    if (text == null) return false;
    final lower = text!.toLowerCase();
    return lower.contains('twitter.com') || lower.contains('x.com');
  }

  bool get isWebLink {
    if (text == null) return false;
    final lower = text!.trim().toLowerCase();
    return lower.startsWith('http://') || lower.startsWith('https://');
  }

  String get displayTitle {
    if (isYouTube) return 'YouTube Link';
    if (isXTwitter) return 'X / Twitter Post';
    if (isWebLink) return 'Web Link';
    if (isTextOnly) return 'Shared Text';
    if (type == SharedPayloadType.video) {
      return files.length == 1 ? '1 Video' : '${files.length} Videos';
    }
    if (type == SharedPayloadType.image) {
      return files.length == 1 ? '1 Photo' : '${files.length} Photos';
    }
    return files.length == 1 ? '1 File' : '${files.length} Files';
  }
}

final sharedFilesProvider =
    StateNotifierProvider<SharedFilesNotifier, List<File>>((ref) {
      return SharedFilesNotifier();
    });

class SharedFilesNotifier extends StateNotifier<List<File>> {
  SharedFilesNotifier() : super([]);

  void setFiles(List<File> files) => state = files;

  void clear() {
    state = [];
    // Reset the native intent so it doesn't replay on next app restart
    ShareHandler.instance.resetInitialSharedMedia();
  }
}

final sharedPayloadProvider =
    StateNotifierProvider<SharedPayloadNotifier, SharedPayload?>((ref) {
      return SharedPayloadNotifier();
    });

class SharedPayloadNotifier extends StateNotifier<SharedPayload?> {
  SharedPayloadNotifier() : super(null);

  void setPayload(SharedPayload payload) => state = payload;

  void clear() {
    state = null;
    ShareHandler.instance.resetInitialSharedMedia();
  }
}

SharedPayload extractSharedPayload(SharedMedia media) {
  final content = media.content?.trim();
  final attachments =
      media.attachments?.whereType<SharedAttachment>().toList() ?? [];

  final List<File> files = [];
  SharedPayloadType type = SharedPayloadType.text;

  if (attachments.isNotEmpty) {
    bool hasVideo = false;
    bool hasImage = false;
    bool hasFile = false;

    for (final a in attachments) {
      final path = a.path;
      if (path.isEmpty) continue;
      final file = File(path);
      files.add(file);

      final lower = path.toLowerCase();
      if (a.type == SharedAttachmentType.video ||
          lower.endsWith('.mp4') ||
          lower.endsWith('.mov') ||
          lower.endsWith('.mkv') ||
          lower.endsWith('.avi') ||
          lower.endsWith('.webm') ||
          lower.endsWith('.3gp')) {
        hasVideo = true;
      } else if (a.type == SharedAttachmentType.image ||
          lower.endsWith('.jpg') ||
          lower.endsWith('.jpeg') ||
          lower.endsWith('.png') ||
          lower.endsWith('.webp') ||
          lower.endsWith('.gif') ||
          lower.endsWith('.heic') ||
          lower.endsWith('.bmp')) {
        hasImage = true;
      } else {
        hasFile = true;
      }
    }

    if (hasVideo) {
      type = SharedPayloadType.video;
    } else if (hasImage) {
      type = SharedPayloadType.image;
    } else if (hasFile) {
      type = SharedPayloadType.file;
    }
  }

  if (files.isEmpty && content != null && content.isNotEmpty) {
    type = SharedPayloadType.text;
  }

  return SharedPayload(
    files: files,
    text: (content != null && content.isNotEmpty) ? content : null,
    type: type,
  );
}

List<File> extractImageFiles(SharedMedia media) {
  if (media.attachments == null) return [];
  return media.attachments!
      .where(
        (a) =>
            a != null &&
            (a.type == SharedAttachmentType.image ||
                a.path.toLowerCase().endsWith('.jpg') ||
                a.path.toLowerCase().endsWith('.jpeg') ||
                a.path.toLowerCase().endsWith('.png') ||
                a.path.toLowerCase().endsWith('.webp') ||
                a.path.toLowerCase().endsWith('.gif')),
      )
      .map((a) => File(a!.path))
      .toList();
}
