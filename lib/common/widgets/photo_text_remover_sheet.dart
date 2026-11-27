import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/utils/file_messages.dart';
import 'package:worship_chat/common/utils/phone_wallpaper_service.dart';
import 'package:worship_chat/common/utils/utils.dart';
import 'package:worship_chat/common/widgets/set_as_profile_pic_sheet.dart';
import 'package:worship_chat/common/widgets/wallpaper_widget_sheet.dart';
import 'package:worship_chat/features/bookmark/controller/bookmark_controller.dart';
import 'package:worship_chat/features/chat/screens/ai_magic_studio_screen.dart';
import 'package:worship_chat/features/group/controller/group_gallery_controller.dart';
import 'package:worship_chat/features/group/services/gallery_media_service.dart';
import 'package:worship_chat/models/user_model.dart';

enum PhotoTextRemoverOrigin {
  groupGallery,
  localGallery,
  bookmarks,
  bookmarkCollection,
  slideshow,
}

enum _PostEditChoice {
  done,
  reEdit,
  setProfilePic,
  setWallpaper,
}

class _PostEditResult {
  final _PostEditChoice choice;
  final String? snackbarMessage;

  const _PostEditResult(this.choice, [this.snackbarMessage]);
}

/// Shared launcher and save-options sheet for running [AiMagicStudioScreen]
/// ("Remove Text") on photos in Gallery and Bookmarks.
class PhotoTextRemoverSheet {
  PhotoTextRemoverSheet._();

  static Future<File?> open(
    BuildContext context, {
    required PhotoTextRemoverOrigin origin,
    String? imageUrl,
    String? localPath,
    String? groupId,
    String? groupName,
    String? sourceImageId,
    String? sourceBookmarkId,
    String? sourceCollectionId,
    bool isOwner = false,
    String title = '',
    void Function(File updatedFile)? onLocalFileUpdated,
    void Function(String newImageUrl)? onRemoteImageUpdated,
    @visibleForTesting Future<File?> Function()? resolveFileOverride,
    @visibleForTesting Widget Function(File initialImage)? studioBuilderOverride,
    @visibleForTesting GalleryMediaService? galleryMediaServiceOverride,
    @visibleForTesting
    Future<bool> Function(File cleanedFile)? saveToGroupOverride,
    @visibleForTesting
    Future<bool> Function(File cleanedFile)? saveToBookmarksOverride,
  }) async {
    final sourceFile = await _resolveSourceFile(
      context,
      imageUrl: imageUrl,
      localPath: localPath,
      resolveFileOverride: resolveFileOverride,
    );
    if (sourceFile == null || !context.mounted) {
      if (context.mounted) {
        AppSnackBar.show(
          context,
          message: '⚠️ Could not load this photo for Text Remover',
        );
      }
      return null;
    }

    File studioInput = sourceFile;
    File? latestCleaned;

    while (true) {
      if (!context.mounted) return latestCleaned;
      final edited = await Navigator.push<File>(
        context,
        MaterialPageRoute(
          builder: (_) =>
              studioBuilderOverride?.call(studioInput) ??
              AiMagicStudioScreen(initialImage: studioInput),
        ),
      );

      if (!context.mounted) return latestCleaned;
      if (edited == null) return latestCleaned;

      if (edited.path == studioInput.path && latestCleaned == null) {
        AppSnackBar.show(
          context,
          message: 'Select text or paint over it and tap Remove Text first.',
        );
        return null;
      }

      latestCleaned = edited;

      final result = await showModalBottomSheet<_PostEditResult>(
        context: context,
        backgroundColor: const Color(0xFF161426),
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        builder: (_) => _CleanedPhotoResultSheet(
          cleanedFile: edited,
          origin: origin,
          localPath: localPath,
          groupId: groupId,
          groupName: groupName,
          sourceImageId: sourceImageId,
          sourceBookmarkId: sourceBookmarkId,
          sourceCollectionId: sourceCollectionId,
          isOwner: isOwner,
          title: title,
          galleryMediaService: galleryMediaServiceOverride,
          onLocalFileUpdated: onLocalFileUpdated,
          onRemoteImageUpdated: onRemoteImageUpdated,
          saveToGroupOverride: saveToGroupOverride,
          saveToBookmarksOverride: saveToBookmarksOverride,
        ),
      );

      if (!context.mounted) return edited;

      if (result?.snackbarMessage != null &&
          result!.snackbarMessage!.isNotEmpty) {
        AppSnackBar.show(context, message: result.snackbarMessage!);
      }

      if (result?.choice == _PostEditChoice.reEdit) {
        studioInput = edited;
        continue;
      }

      if (result?.choice == _PostEditChoice.setProfilePic) {
        await SetAsProfilePicSheet.show(
          context,
          localPath: edited.path,
          sourceGroupId: groupId,
          sourceGroupName: groupName,
          title: title,
        );
      } else if (result?.choice == _PostEditChoice.setWallpaper) {
        await WallpaperAndWidgetSheet.show(
          context,
          photoId: 'cleaned_${DateTime.now().millisecondsSinceEpoch}',
          localPath: edited.path,
          title: title.isNotEmpty ? title : 'Cleaned Photo',
          subtitle: 'Text Remover',
        );
      }
      return edited;
    }
  }

  static Future<File?> _resolveSourceFile(
    BuildContext context, {
    String? imageUrl,
    String? localPath,
    Future<File?> Function()? resolveFileOverride,
  }) async {
    final cleanLocal = localPath?.trim().replaceFirst('file://', '');
    if (cleanLocal != null && cleanLocal.isNotEmpty) {
      final file = File(cleanLocal);
      if (file.existsSync() && file.lengthSync() > 0) {
        return file;
      }
    }

    if (resolveFileOverride != null) {
      return await resolveFileOverride();
    }

    final cleanUrl = imageUrl?.trim();
    if (cleanUrl == null || cleanUrl.isEmpty) {
      return null;
    }

    var dialogVisible = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(
          child: Card(
            color: Color(0xFF1E1C2E),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Color(0xFF00E5FF)),
                  SizedBox(height: 14),
                  Text(
                    'Preparing photo for Text Remover...',
                    style: TextStyle(color: Colors.white, fontSize: 13.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ).whenComplete(() => dialogVisible = false);

    try {
      return await PhoneWallpaperService.instance.resolveImageFile(
        imageUrl: cleanUrl,
      );
    } finally {
      if (dialogVisible && context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }
}

class _CleanedPhotoResultSheet extends ConsumerStatefulWidget {
  final File cleanedFile;
  final PhotoTextRemoverOrigin origin;
  final String? localPath;
  final String? groupId;
  final String? groupName;
  final String? sourceImageId;
  final String? sourceBookmarkId;
  final String? sourceCollectionId;
  final bool isOwner;
  final String title;
  final GalleryMediaService? galleryMediaService;
  final void Function(File updatedFile)? onLocalFileUpdated;
  final void Function(String newImageUrl)? onRemoteImageUpdated;
  final Future<bool> Function(File cleanedFile)? saveToGroupOverride;
  final Future<bool> Function(File cleanedFile)? saveToBookmarksOverride;

  const _CleanedPhotoResultSheet({
    required this.cleanedFile,
    required this.origin,
    this.localPath,
    this.groupId,
    this.groupName,
    this.sourceImageId,
    this.sourceBookmarkId,
    this.sourceCollectionId,
    required this.isOwner,
    required this.title,
    this.galleryMediaService,
    this.onLocalFileUpdated,
    this.onRemoteImageUpdated,
    this.saveToGroupOverride,
    this.saveToBookmarksOverride,
  });

  @override
  ConsumerState<_CleanedPhotoResultSheet> createState() =>
      _CleanedPhotoResultSheetState();
}

class _CleanedPhotoResultSheetState
    extends ConsumerState<_CleanedPhotoResultSheet> {
  static const Color _accentCyan = Color(0xFF00E5FF);

  bool _isBusy = false;
  String _busyText = '';

  bool get _hasSignedInUser {
    try {
      return FirebaseAuth.instance.currentUser != null;
    } catch (_) {
      return false;
    }
  }

  bool get _canWriteOriginalLocalFile {
    final clean = widget.localPath?.trim().replaceFirst('file://', '');
    if (clean == null || clean.isEmpty) return false;
    if (clean.contains('/zip_') || clean.contains('\\zip_')) return false;
    return File(clean).existsSync();
  }

  bool get _canSaveToGroup =>
      widget.groupId != null &&
      widget.groupId!.trim().isNotEmpty &&
      !widget.groupId!.startsWith('local_') &&
      (widget.saveToGroupOverride != null || _hasSignedInUser);

  bool get _canReplaceInGroup =>
      _canSaveToGroup &&
      widget.sourceImageId != null &&
      widget.sourceImageId!.trim().isNotEmpty &&
      widget.origin == PhotoTextRemoverOrigin.groupGallery;

  bool get _canSaveToBookmarks =>
      widget.saveToBookmarksOverride != null || _hasSignedInUser;

  bool get _canReplaceBookmark =>
      _canSaveToBookmarks &&
      widget.isOwner &&
      widget.sourceBookmarkId != null &&
      widget.sourceBookmarkId!.trim().isNotEmpty &&
      (widget.origin == PhotoTextRemoverOrigin.bookmarks ||
          widget.origin == PhotoTextRemoverOrigin.bookmarkCollection);

  ({String name, String profilePic}) _readCurrentUserMeta() {
    String name = '';
    String pic = '';
    try {
      if (Hive.isBoxOpen('userBox')) {
        final user = Hive.box<UserModel>('userBox').get('currentUser');
        if (user != null) {
          name = (user.name ?? user.userName ?? '').trim();
          pic = (user.profilePic ?? '').trim();
        }
      }
    } catch (_) {}

    if (name.isEmpty) {
      try {
        name = FirebaseAuth.instance.currentUser?.displayName?.trim() ?? '';
      } catch (_) {}
    }
    return (name: name.isNotEmpty ? name : 'Devotee', profilePic: pic);
  }

  Future<void> _saveToDevice() async {
    setState(() {
      _isBusy = true;
      _busyText = 'Saving to device...';
    });
    try {
      final media = widget.galleryMediaService ?? GalleryMediaService();
      final baseName = widget.title.trim().isNotEmpty
          ? widget.title.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')
          : 'cleaned_photo';
      final result = await media.saveLocalImageFile(
        imageFile: widget.cleanedFile,
        fileName: '${baseName}_cleaned.jpg',
      );
      if (!mounted) return;
      if (result == GallerySaveResult.saved) {
        Navigator.pop(
          context,
          _PostEditResult(
            _PostEditChoice.done,
            media.isDesktop
                ? '✅ Saved cleaned photo in high quality'
                : '✅ Saved cleaned photo to Worship Chat album',
          ),
        );
      } else if (result == GallerySaveResult.cancelled) {
        setState(() => _isBusy = false);
      } else {
        setState(() => _isBusy = false);
        AppSnackBar.show(context, message: '⚠️ Could not save cleaned photo');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isBusy = false);
        AppSnackBar.show(context, message: '⚠️ Save failed: $e');
      }
    }
  }

  Future<void> _overwriteLocalFile() async {
    final targetPath = widget.localPath?.trim().replaceFirst('file://', '');
    if (targetPath == null || targetPath.isEmpty) return;

    setState(() {
      _isBusy = true;
      _busyText = 'Updating original photo...';
    });
    try {
      final bytes = await widget.cleanedFile.readAsBytes();
      final targetFile = File(targetPath);
      await targetFile.writeAsBytes(bytes, flush: true);
      imageCache.evict(FileImage(targetFile));
      widget.onLocalFileUpdated?.call(targetFile);
      if (!mounted) return;
      Navigator.pop(
        context,
        const _PostEditResult(
          _PostEditChoice.done,
          '✅ Updated original photo cleanly',
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isBusy = false);
        AppSnackBar.show(context, message: '⚠️ Could not update file: $e');
      }
    }
  }

  Future<void> _saveCopyInLocalFolder() async {
    final targetPath = widget.localPath?.trim().replaceFirst('file://', '');
    if (targetPath == null || targetPath.isEmpty) return;

    setState(() {
      _isBusy = true;
      _busyText = 'Saving copy in folder...';
    });
    try {
      final dir = p.dirname(targetPath);
      final stem = p.basenameWithoutExtension(targetPath);
      final copyFile = File(
        p.join(
          dir,
          '${stem}_cleaned_${DateTime.now().millisecondsSinceEpoch}.jpg',
        ),
      );
      await copyFile.writeAsBytes(
        await widget.cleanedFile.readAsBytes(),
        flush: true,
      );
      widget.onLocalFileUpdated?.call(copyFile);
      if (!mounted) return;
      Navigator.pop(
        context,
        _PostEditResult(
          _PostEditChoice.done,
          '✅ Saved copy: ${p.basename(copyFile.path)}',
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isBusy = false);
        AppSnackBar.show(context, message: '⚠️ Could not save folder copy: $e');
      }
    }
  }

  Future<void> _saveToGroupGallery({required bool replaceOriginal}) async {
    final groupId = widget.groupId?.trim();
    if (groupId == null || groupId.isEmpty) return;

    setState(() {
      _isBusy = true;
      _busyText = replaceOriginal
          ? 'Replacing gallery photo...'
          : 'Uploading to gallery...';
    });
    try {
      if (widget.saveToGroupOverride != null) {
        final ok = await widget.saveToGroupOverride!(widget.cleanedFile);
        if (!mounted) return;
        if (ok) {
          Navigator.pop(
            context,
            const _PostEditResult(
              _PostEditChoice.done,
              '✅ Saved cleaned photo to Gallery',
            ),
          );
        } else {
          setState(() => _isBusy = false);
          AppSnackBar.show(context, message: '⚠️ Gallery upload failed');
        }
        return;
      }

      final meta = _readCurrentUserMeta();
      final controller = ref.read(groupGalleryControllerProvider);
      final uploaded = await controller.uploadImages(
        groupId: groupId,
        imageFiles: [widget.cleanedFile],
        uploaderName: meta.name,
        caption: widget.title.trim().isNotEmpty ? widget.title.trim() : null,
      );

      if (uploaded <= 0) {
        if (mounted) {
          setState(() => _isBusy = false);
          AppSnackBar.show(context, message: '⚠️ Could not upload to gallery');
        }
        return;
      }

      if (replaceOriginal &&
          widget.sourceImageId != null &&
          widget.sourceImageId!.isNotEmpty) {
        await controller.deleteImage(groupId, widget.sourceImageId!);
      }

      if (!mounted) return;
      Navigator.pop(
        context,
        _PostEditResult(
          _PostEditChoice.done,
          replaceOriginal
              ? '✅ Replaced original photo in Gallery'
              : '✅ Added cleaned photo to Gallery',
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isBusy = false);
        AppSnackBar.show(context, message: '⚠️ Gallery save failed: $e');
      }
    }
  }

  Future<void> _saveToBookmarks({required bool replaceOriginal}) async {
    setState(() {
      _isBusy = true;
      _busyText = replaceOriginal
          ? 'Updating bookmark...'
          : 'Saving to Bookmarks...';
    });
    try {
      if (widget.saveToBookmarksOverride != null) {
        final ok = await widget.saveToBookmarksOverride!(widget.cleanedFile);
        if (!mounted) return;
        if (ok) {
          Navigator.pop(
            context,
            const _PostEditResult(
              _PostEditChoice.done,
              '✅ Saved to Bookmarks',
            ),
          );
        } else {
          setState(() => _isBusy = false);
          AppSnackBar.show(context, message: '⚠️ Bookmark save failed');
        }
        return;
      }

      final uploadedUrl = await uploadImageToCloudinary(
        widget.cleanedFile,
        'bookmarks',
      );
      if (uploadedUrl == null || uploadedUrl.trim().isEmpty) {
        if (mounted) {
          setState(() => _isBusy = false);
          AppSnackBar.show(
            context,
            message: '⚠️ Failed to upload cleaned photo',
          );
        }
        return;
      }

      final bookmarkCtrl = ref.read(bookmarkControllerProvider);
      if (replaceOriginal &&
          widget.sourceBookmarkId != null &&
          widget.sourceBookmarkId!.isNotEmpty) {
        final ok = await bookmarkCtrl.replaceBookmarkImage(
          bookmarkId: widget.sourceBookmarkId!,
          newImageUrl: uploadedUrl,
        );
        if (!mounted) return;
        if (ok) {
          widget.onRemoteImageUpdated?.call(uploadedUrl);
          Navigator.pop(
            context,
            const _PostEditResult(
              _PostEditChoice.done,
              '✅ Bookmark updated with cleaned photo',
            ),
          );
        } else {
          setState(() => _isBusy = false);
          AppSnackBar.show(context, message: '⚠️ Could not update bookmark');
        }
        return;
      }

      final meta = _readCurrentUserMeta();
      final newBookmarkId = await bookmarkCtrl.ensureBookmarked(
        imageUrl: uploadedUrl,
        groupId: widget.groupId ?? '',
        groupName: widget.groupName?.trim().isNotEmpty == true
            ? widget.groupName!.trim()
            : 'Cleaned Photos',
        userName: meta.name,
        userProfilePic: meta.profilePic,
      );

      if (newBookmarkId != null &&
          widget.sourceCollectionId != null &&
          widget.sourceCollectionId!.isNotEmpty) {
        await bookmarkCtrl.addBookmarkToCollection(
          collectionId: widget.sourceCollectionId!,
          bookmarkId: newBookmarkId,
        );
      }

      if (!mounted) return;
      if (newBookmarkId != null) {
        Navigator.pop(
          context,
          _PostEditResult(
            _PostEditChoice.done,
            widget.sourceCollectionId != null
                ? '✅ Saved cleaned photo to Bookmarks & Collection'
                : '✅ Saved cleaned photo to Bookmarks',
          ),
        );
      } else {
        setState(() => _isBusy = false);
        AppSnackBar.show(context, message: '⚠️ Could not save bookmark');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isBusy = false);
        AppSnackBar.show(context, message: '⚠️ Bookmark save failed: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isBookmarksFlow =
        widget.origin == PhotoTextRemoverOrigin.bookmarks ||
        widget.origin == PhotoTextRemoverOrigin.bookmarkCollection;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom + 14,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 10),
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      widget.cleanedFile,
                      width: 62,
                      height: 62,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: _accentCyan.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _accentCyan.withValues(alpha: 0.5),
                                ),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.text_fields_rounded,
                                    color: _accentCyan,
                                    size: 13,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'Text Removed',
                                    style: TextStyle(
                                      color: _accentCyan,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Save cleaned photo',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _isBusy
                        ? null
                        : () => Navigator.pop(
                              context,
                              const _PostEditResult(_PostEditChoice.reEdit),
                            ),
                    icon: const Icon(Icons.tune_rounded, size: 16),
                    label: const Text('Edit Again'),
                    style: TextButton.styleFrom(foregroundColor: _accentCyan),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (_isBusy)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Column(
                  children: [
                    const CircularProgressIndicator(color: _accentCyan),
                    const SizedBox(height: 12),
                    Text(
                      _busyText,
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              )
            else ...[
              ListTile(
                leading: const Icon(Icons.download_rounded, color: _accentCyan),
                title: const Text(
                  'Save to Device',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Download cleaned copy in high quality',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                onTap: _saveToDevice,
              ),
              if (_canWriteOriginalLocalFile) ...[
                ListTile(
                  leading: const Icon(
                    Icons.save_as_rounded,
                    color: Colors.greenAccent,
                  ),
                  title: const Text(
                    'Overwrite Original File',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: const Text(
                    'Replace the photo in this folder',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  onTap: _overwriteLocalFile,
                ),
                ListTile(
                  leading: const Icon(
                    Icons.file_copy_outlined,
                    color: Colors.white70,
                  ),
                  title: const Text(
                    'Save Copy in Folder',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: const Text(
                    'Keep original and add cleaned copy next to it',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  onTap: _saveCopyInLocalFolder,
                ),
              ],
              if (!isBookmarksFlow && _canSaveToGroup) ...[
                ListTile(
                  leading: const Icon(
                    Icons.add_photo_alternate_outlined,
                    color: tabColor,
                  ),
                  title: const Text(
                    'Save as New Photo in Gallery',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    widget.groupName?.isNotEmpty == true
                        ? 'Upload cleaned photo to ${widget.groupName}'
                        : 'Upload cleaned photo to gallery',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  onTap: () => _saveToGroupGallery(replaceOriginal: false),
                ),
                if (_canReplaceInGroup)
                  ListTile(
                    leading: const Icon(
                      Icons.published_with_changes_rounded,
                      color: Colors.greenAccent,
                    ),
                    title: const Text(
                      'Replace Original in Gallery',
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: const Text(
                      'Upload cleaned photo and remove original',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    onTap: () => _saveToGroupGallery(replaceOriginal: true),
                  ),
              ],
              if (_canSaveToBookmarks) ...[
                ListTile(
                  leading: const Icon(
                    Icons.bookmark_add_outlined,
                    color: Colors.amber,
                  ),
                  title: Text(
                    widget.sourceCollectionId != null
                        ? 'Save as New Bookmark in Collection'
                        : 'Save to Bookmarks',
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: const Text(
                    'Keep a clean bookmarked copy',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  onTap: () => _saveToBookmarks(replaceOriginal: false),
                ),
                if (_canReplaceBookmark)
                  ListTile(
                    leading: const Icon(
                      Icons.published_with_changes_rounded,
                      color: Colors.greenAccent,
                    ),
                    title: const Text(
                      'Replace Original Bookmark',
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: const Text(
                      'Update bookmark photo cleanly',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    onTap: () => _saveToBookmarks(replaceOriginal: true),
                  ),
              ],
              ListTile(
                leading: const Icon(
                  Icons.account_circle_outlined,
                  color: Colors.white70,
                ),
                title: const Text(
                  'Set as Profile Pic',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () => Navigator.pop(
                  context,
                  const _PostEditResult(_PostEditChoice.setProfilePic),
                ),
              ),
              ListTile(
                leading: const Icon(
                  Icons.wallpaper_rounded,
                  color: Color(0xFFFFD700),
                ),
                title: const Text(
                  'Wallpaper & Home Widget',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () => Navigator.pop(
                  context,
                  const _PostEditResult(_PostEditChoice.setWallpaper),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
