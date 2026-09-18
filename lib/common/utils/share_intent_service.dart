import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_handler/share_handler.dart';

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

List<File> extractImageFiles(SharedMedia media) {
  if (media.attachments == null) return [];
  return media.attachments!
      .where(
        (a) =>
            a != null &&
            (a.type == SharedAttachmentType.image ||
                a.path.toLowerCase().endsWith('.jpg') ||
                a.path.toLowerCase().endsWith('.jpeg') ||
                a.path.toLowerCase().endsWith('.png')),
      )
      .map((a) => File(a!.path))
      .toList();
}
