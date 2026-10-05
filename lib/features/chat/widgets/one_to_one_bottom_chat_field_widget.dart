import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/providers/message_reply_provider.dart';
import 'package:worship_chat/common/utils/utils.dart';
import 'package:worship_chat/common/widgets/camera_screen.dart';
import 'package:worship_chat/features/chat/controller/chat_controller.dart';
import 'package:worship_chat/features/chat/widgets/camera_permission_handler.dart';
import 'package:worship_chat/features/chat/widgets/location_picker_sheet.dart';
import 'package:worship_chat/features/chat/widgets/message_reply_preview.dart';

class OneToOneBottomChatFieldWidget extends ConsumerStatefulWidget {
  final String receiverUserId;
  final String fcmToken;
  final bool? unseenCount;
  final String? chatBackgroundUrl;

  const OneToOneBottomChatFieldWidget({
    super.key,
    required this.receiverUserId,
    required this.fcmToken,
    required this.unseenCount,
    required this.chatBackgroundUrl,
  });

  @override
  ConsumerState<OneToOneBottomChatFieldWidget> createState() =>
      _BottomChatFieldState();
}

class _BottomChatFieldState
    extends ConsumerState<OneToOneBottomChatFieldWidget> {
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  // Single attachment (document / gif / camera result)
  dynamic imageFile;
  String messageType = "text";

  // Multi-file media group (images or videos)
  List<File> _mediaFiles = [];
  String _mediaGroupType = ''; // 'image' or 'video'

  Timer? _typingTimer;
  bool _isTyping = false;
  bool _hasText = false;
  bool _isSendPressed = false;

  @override
  void initState() {
    super.initState();
    _messageController.addListener(_onTextChanged);
    _focusNode.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _messageController.removeListener(_onTextChanged);
    _messageController.dispose();
    _focusNode.dispose();
    _typingTimer?.cancel();
    // Set typing to false when leaving chat
    if (_isTyping) {
      ref
          .read(chatControllerProvider)
          .setTypingStatus(widget.receiverUserId, false);
    }
    super.dispose();
  }

  void _onTextChanged() {
    final text = _messageController.text.trim();
    final hasText = text.isNotEmpty;
    if (hasText != _hasText) {
      setState(() {
        _hasText = hasText;
      });
    }

    if (text.isNotEmpty && !_isTyping) {
      // User started typing
      _isTyping = true;
      ref
          .read(chatControllerProvider)
          .setTypingStatus(widget.receiverUserId, true);
    }

    // Cancel existing timer
    _typingTimer?.cancel();

    // Set new timer - if user stops typing for 2 seconds, set typing to false
    _typingTimer = Timer(const Duration(seconds: 2), () {
      if (_isTyping) {
        _isTyping = false;
        ref
            .read(chatControllerProvider)
            .setTypingStatus(widget.receiverUserId, false);
      }
    });

    // If text is empty, immediately set typing to false
    if (text.isEmpty && _isTyping) {
      _isTyping = false;
      _typingTimer?.cancel();
      ref
          .read(chatControllerProvider)
          .setTypingStatus(widget.receiverUserId, false);
    }
  }

  void sendTextMessage() async {
    final hasMedia = _mediaFiles.isNotEmpty || imageFile != null;
    if (_messageController.text.trim().isEmpty && !hasMedia) {
      return;
    }

    if (widget.receiverUserId.trim().isEmpty) {
      log("❌ Cannot send message: receiverUserId is empty");
      AppSnackBar.error(
        context,
        'Cannot send message: invalid contact. Please go back and re-open the chat.',
      );
      return;
    }

    log("Sending message - Type: $messageType, HasFile: ${imageFile != null}");

    // Capture current values
    final messageText = _messageController.text.trim();
    final currentImageFile = imageFile;
    final currentMessageType = messageType;
    final currentMediaFiles = List<File>.from(_mediaFiles);
    final currentMediaGroupType = _mediaGroupType;

    // Validate that there is something to send
    if (messageText.isEmpty && currentImageFile == null && currentMediaFiles.isEmpty) {
      return;
    }

    // Stop typing indicator
    if (_isTyping) {
      _isTyping = false;
      _typingTimer?.cancel();
      ref
          .read(chatControllerProvider)
          .setTypingStatus(widget.receiverUserId, false);
    }

    // For document messages, default text to file name if caption is empty
    String textToSend = messageText;
    if (currentMessageType == 'document' &&
        textToSend.isEmpty &&
        currentImageFile is File) {
      textToSend = currentImageFile.path.split(Platform.pathSeparator).last;
    }

    // Clear UI immediately
    setState(() {
      messageType = "text";
      imageFile = null;
      _mediaFiles = [];
      _mediaGroupType = '';
      _hasText = false;
    });
    _messageController.clear();

    try {
      // ── Multi-file media group (images or videos sent together) ───────────
      if (currentMediaFiles.isNotEmpty) {
        final groupId = const Uuid().v1(); // shared group ID
        for (int i = 0; i < currentMediaFiles.length; i++) {
          await ref.read(chatControllerProvider).sendTextMessage(
                context,
                // Only attach caption to the first item so it appears once
                i == 0 ? messageText : '',
                widget.receiverUserId,
                currentMediaGroupType,
                currentMediaFiles[i],
                widget.fcmToken,
                widget.unseenCount,
                widget.chatBackgroundUrl,
                'others',
                groupId: groupId,
              );
        }
      } else {
        // ── Single attachment ────────────────────────────────────────────────
        await ref.read(chatControllerProvider).sendTextMessage(
              context,
              textToSend,
              widget.receiverUserId,
              currentMessageType,
              currentImageFile,
              widget.fcmToken,
              widget.unseenCount,
              widget.chatBackgroundUrl,
              'others',
            );
      }

      log('✅ Message sent successfully');
    } catch (e) {
      log('❌ Error sending message: $e');

      // Show error notice
      if (mounted) {
        AppSnackBar.error(context, 'Failed to send: ${e.toString()}');
      }
    }
  }

  void selectDocument() async {
    final doc = await pickDocumentFile(context);
    if (doc != null) {
      setState(() {
        imageFile = doc;
        messageType = "document";
      });
    }
  }

  void openLocationPicker() async {
    final result = await LocationPickerSheet.show(context);
    if (result == null || !mounted) return;

    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (result.type == LocationShareType.current) {
      final locData = jsonEncode({
        'latitude': result.latitude,
        'longitude': result.longitude,
        'isLive': false,
        'accuracy': result.accuracy,
      });

      ref.read(chatControllerProvider).sendTextMessage(
            context,
            'Current Location',
            widget.receiverUserId,
            'location',
            locData,
            widget.fcmToken,
            widget.unseenCount,
            widget.chatBackgroundUrl,
            'others',
          );
    } else {
      final duration = result.duration ?? const Duration(hours: 1);
      final liveUntil = DateTime.now().add(duration).millisecondsSinceEpoch;
      final liveData = jsonEncode({
        'latitude': result.latitude,
        'longitude': result.longitude,
        'isLive': true,
        'liveUntil': liveUntil,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
        'sharerId': currentUserId,
      });

      ref.read(chatControllerProvider).sendTextMessage(
            context,
            'Live Location',
            widget.receiverUserId,
            'live_location',
            liveData,
            widget.fcmToken,
            widget.unseenCount,
            widget.chatBackgroundUrl,
            'others',
          );
    }
  }

  /// Pick multiple images – replaces single image selection.
  void selectImage() async {
    final files = await pickMultipleImagesFromGallery(context);
    if (files.isNotEmpty) {
      setState(() {
        if (files.length == 1) {
          // Single pick → keep legacy single-file path for simplicity
          imageFile = files.first;
          messageType = 'image';
          _mediaFiles = [];
          _mediaGroupType = '';
        } else {
          _mediaFiles = files;
          _mediaGroupType = 'image';
          imageFile = null;
          messageType = 'text';
        }
      });
    }
  }

  /// Pick multiple videos.
  void selectVideo() async {
    final files = await pickMultipleVideosFromGallery(context);
    if (files.isNotEmpty) {
      setState(() {
        if (files.length == 1) {
          imageFile = files.first;
          messageType = 'video';
          _mediaFiles = [];
          _mediaGroupType = '';
        } else {
          _mediaFiles = files;
          _mediaGroupType = 'video';
          imageFile = null;
          messageType = 'text';
        }
      });
    }
  }

  void openCamera() async {
    // Request camera permission first
    final hasPermission = await CameraPermissionHandler.requestCameraPermission(
      context,
    );

    if (!hasPermission) {
      return; // Permission denied, don't open camera
    }

    if (!mounted) return;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const CameraScreen()),
    );

    if (result != null && result is Map<String, dynamic>) {
      setState(() {
        imageFile = result['file'];
        messageType = result['type']; // 'image' or 'video'
      });
    }
  }

  void showMediaOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFF161524),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
            // Drag handle pill
            Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Share Content',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 16.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: greyColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMediaOptionItem(
                  title: 'Document',
                  icon: Icons.insert_drive_file_rounded,
                  gradient: const [Color(0xFF2979FF), Color(0xFF1565C0)],
                  onTap: () {
                    Navigator.pop(context);
                    selectDocument();
                  },
                ),
                _buildMediaOptionItem(
                  title: 'Camera',
                  icon: Icons.camera_alt_rounded,
                  gradient: const [Color(0xFFFF6B2D), Color(0xFFFF8E53)],
                  onTap: () {
                    Navigator.pop(context);
                    openCamera();
                  },
                ),
                _buildMediaOptionItem(
                  title: 'Gallery',
                  icon: Icons.photo_library_rounded,
                  gradient: const [Color(0xFFFF2D78), Color(0xFFE02070)],
                  onTap: () {
                    Navigator.pop(context);
                    selectImage();
                  },
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMediaOptionItem(
                  title: 'Video',
                  icon: Icons.videocam_rounded,
                  gradient: const [Color(0xFF7C4DFF), Color(0xFF651FFF)],
                  onTap: () {
                    Navigator.pop(context);
                    selectVideo();
                  },
                ),
                _buildMediaOptionItem(
                  title: 'Location',
                  icon: Icons.location_on_rounded,
                  gradient: const [Color(0xFF00E676), Color(0xFF00B074)],
                  onTap: () {
                    Navigator.pop(context);
                    openLocationPicker();
                  },
                ),
                // Empty placeholder to keep 3-column symmetry
                const SizedBox(width: 56),
              ],
            ),
          ],
        ),
      ),
    ),
  ),
);
  }

  Widget _buildMediaOptionItem({
    required String title,
    required IconData icon,
    required List<Color> gradient,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: gradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: gradient.first.withValues(alpha: 0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              color: textColor,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttachedMediaPreview() {
    // ── Multi-file grid preview ───────────────────────────────────────────────
    if (_mediaFiles.isNotEmpty) {
      return Container(
        margin: const EdgeInsets.only(left: 10, right: 10, bottom: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF161524),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _mediaGroupType == 'video'
                      ? Icons.videocam_rounded
                      : Icons.photo_library_rounded,
                  color: tabColor,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text(
                  '${_mediaFiles.length} ${_mediaGroupType == 'video' ? 'videos' : 'photos'} selected',
                  style: const TextStyle(
                    color: textColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => setState(() {
                    _mediaFiles = [];
                    _mediaGroupType = '';
                  }),
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: greyColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _mediaFiles.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (context, idx) {
                  final file = _mediaFiles[idx];
                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 72,
                          height: 72,
                          child: _mediaGroupType == 'image'
                              ? Image.file(file, fit: BoxFit.cover)
                              : Container(
                                  color: const Color(0xFF222034),
                                  child: const Icon(
                                    Icons.videocam_rounded,
                                    color: greyColor,
                                    size: 28,
                                  ),
                                ),
                        ),
                      ),
                      if (_mediaGroupType == 'video')
                        const Positioned(
                          bottom: 4,
                          right: 4,
                          child: Icon(
                            Icons.play_circle_filled,
                            color: Colors.white70,
                            size: 18,
                          ),
                        ),
                      // Remove individual file button
                      Positioned(
                        top: 2,
                        right: 2,
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _mediaFiles.removeAt(idx);
                              if (_mediaFiles.isEmpty) _mediaGroupType = '';
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              size: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      );
    }

    // ── Single file preview (original) ───────────────────────────────────────
    if (imageFile == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(left: 10, right: 10, bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF161524),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: _buildMediaThumbnail(),
                ),
              ),
              if (messageType == 'video')
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              if (messageType == 'gif')
                Positioned(
                  bottom: 2,
                  left: 2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'GIF',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  messageType == 'document'
                      ? (imageFile is File
                          ? (imageFile as File).path.split(Platform.pathSeparator).last
                          : 'Document attached')
                      : messageType == 'image'
                          ? 'Photo attached'
                          : messageType == 'video'
                              ? 'Video attached'
                              : 'GIF attached',
                  style: const TextStyle(
                    color: textColor,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Type a caption below or tap send',
                  style: TextStyle(
                    color: greyColor.withValues(alpha: 0.7),
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                setState(() {
                  imageFile = null;
                  messageType = "text";
                });
              },
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: greyColor,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaThumbnail() {
    if (messageType == 'image' && imageFile is File) {
      return Image.file(imageFile as File, fit: BoxFit.cover);
    }
    if (messageType == 'document') {
      return Container(
        color: const Color(0xFF222034),
        child: const Icon(Icons.description_rounded, color: Color(0xFF42A5F5), size: 28),
      );
    }
    if (messageType == 'video' && imageFile is File) {
      return Container(
        color: const Color(0xFF222034),
        child: const Icon(Icons.videocam_rounded, color: greyColor, size: 28),
      );
    }
    if (messageType == 'gif') {
      if (imageFile is File) {
        return Image.file(imageFile as File, fit: BoxFit.cover);
      }
      if (imageFile is String && (imageFile as String).startsWith('http')) {
        return CachedNetworkImage(
          imageUrl: imageFile as String,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(color: const Color(0xFF222034)),
          errorWidget: (_, __, ___) =>
              const Icon(Icons.gif_rounded, color: greyColor),
        );
      }
    }
    return Container(
      color: const Color(0xFF222034),
      child: const Icon(Icons.attachment_rounded, color: greyColor),
    );
  }

  Widget _buildSendButton() {
    final hasContent = _hasText || imageFile != null || _mediaFiles.isNotEmpty;

    return GestureDetector(
      onTapDown: (_) => setState(() => _isSendPressed = true),
      onTapUp: (_) => setState(() => _isSendPressed = false),
      onTapCancel: () => setState(() => _isSendPressed = false),
      onTap: () {
        HapticFeedback.lightImpact();
        sendTextMessage();
      },
      child: AnimatedScale(
        scale: _isSendPressed ? 0.88 : (hasContent ? 1.0 : 0.94),
        duration: const Duration(milliseconds: 120),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: hasContent
                  ? const [tabColor, accentOrange]
                  : [
                      tabColor.withValues(alpha: 0.55),
                      accentOrange.withValues(alpha: 0.55),
                    ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: hasContent
                ? [
                    BoxShadow(
                      color: tabColor.withValues(alpha: 0.45),
                      blurRadius: 12,
                      spreadRadius: 1,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) =>
                  ScaleTransition(scale: animation, child: child),
              child: Icon(
                Icons.send_rounded,
                key: ValueKey<bool>(hasContent),
                color: Colors.white,
                size: 21,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    log("checking token id in bottom field ${widget.fcmToken}");
    final messageReply = ref.watch(messageReplyProvider);
    final isShowMessageReply = messageReply != null;

    return SafeArea(
      top: false,
      bottom: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isShowMessageReply) const MessageReplyPreview(),
          _buildAttachedMediaPreview(),
          Padding(
            padding: const EdgeInsets.only(
              left: 10,
              right: 10,
              bottom: 8,
              top: 4,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161524),
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(
                        color: _focusNode.hasFocus
                            ? tabColor.withValues(alpha: 0.5)
                            : Colors.white.withValues(alpha: 0.08),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _focusNode.hasFocus
                              ? tabColor.withValues(alpha: 0.12)
                              : Colors.black.withValues(alpha: 0.25),
                          blurRadius: _focusNode.hasFocus ? 10 : 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _messageController,
                            focusNode: _focusNode,
                            minLines: 1,
                            maxLines: 5,
                            style: const TextStyle(
                              color: textColor,
                              fontSize: 15,
                              height: 1.35,
                              letterSpacing: 0.1,
                            ),
                            cursorColor: tabColor,
                            cursorWidth: 2.0,
                            cursorRadius: const Radius.circular(2),
                            decoration: InputDecoration(
                              hintText: imageFile != null
                                  ? 'Add a caption...'
                                  : 'Type a message...',
                              hintStyle: TextStyle(
                                color: greyColor.withValues(alpha: 0.5),
                                fontSize: 15,
                              ),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              disabledBorder: InputBorder.none,
                              errorBorder: InputBorder.none,
                              focusedErrorBorder: InputBorder.none,
                              isCollapsed: true,
                              contentPadding: const EdgeInsets.only(
                                left: 14,
                                right: 8,
                                top: 10,
                                bottom: 10,
                              ),
                            ),
                            contentInsertionConfiguration:
                                ContentInsertionConfiguration(
                                  onContentInserted:
                                      (KeyboardInsertedContent content) {
                                    _handleContentInsertion(content);
                                  },
                                  allowedMimeTypes: const [
                                    'image/gif',
                                    'image/png',
                                    'image/jpeg',
                                    'image/webp',
                                  ],
                                ),
                          ),
                        ),
                        // Attachment button
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: showMediaOptions,
                            borderRadius: BorderRadius.circular(20),
                            child: Padding(
                              padding: const EdgeInsets.all(7),
                              child: Icon(
                                Icons.attach_file_rounded,
                                color: _focusNode.hasFocus
                                    ? tabColor.withValues(alpha: 0.85)
                                    : greyColor,
                                size: 21,
                              ),
                            ),
                          ),
                        ),
                        // Direct camera shortcut
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: openCamera,
                            borderRadius: BorderRadius.circular(20),
                            child: const Padding(
                              padding: EdgeInsets.all(7),
                              child: Icon(
                                Icons.camera_alt_rounded,
                                color: greyColor,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _buildSendButton(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleContentInsertion(KeyboardInsertedContent content) async {
    try {
      final file = await getFileFromKeyboardInsertedContent(content);
      if (file != null && await file.exists()) {
        final isGif = content.mimeType.toLowerCase().contains('gif') ||
            file.path.toLowerCase().endsWith('.gif');
        setState(() {
          imageFile = file;
          messageType = isGif ? 'gif' : 'image';
        });
      } else {
        throw Exception('Could not process inserted media');
      }
    } catch (e) {
      log('Error handling content insertion: $e');
      if (mounted) {
        AppSnackBar.error(context, 'Error adding media: $e');
      }
    }
  }
}
