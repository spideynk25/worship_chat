import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/providers/message_reply_provider.dart';
import 'package:worship_chat/common/utils/utils.dart';
import 'package:worship_chat/common/widgets/camera_screen.dart';
import 'package:worship_chat/features/chat/widgets/camera_permission_handler.dart';
import 'package:worship_chat/features/chat/widgets/message_reply_preview.dart';
import 'package:worship_chat/features/group/controller/group_controller.dart';

class GroupBottomChatFieldWidget extends ConsumerStatefulWidget {
  final String groupId;
  final List<String> fcmToken;
  final List<String> receiverIds;
  final String groupName;
  final String? wish;
  final String? queendom;
  final String type;

  const GroupBottomChatFieldWidget({
    super.key,
    required this.groupId,
    required this.receiverIds,
    required this.fcmToken,
    required this.groupName,
    required this.wish,
    required this.queendom,
    required this.type
  });

  @override
  ConsumerState<GroupBottomChatFieldWidget> createState() =>
      _BottomChatFieldState();
}

class _BottomChatFieldState extends ConsumerState<GroupBottomChatFieldWidget> {
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  dynamic imageFile;
  String messageType = "text";
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
    // Set typing to false when leaving group chat
    if (_isTyping) {
      ref
          .read(groupControllerProvider)
          .setGroupTypingStatus(widget.groupId, false);
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
          .read(groupControllerProvider)
          .setGroupTypingStatus(widget.groupId, true);
    }

    // Cancel existing timer
    _typingTimer?.cancel();

    // Set new timer - if user stops typing for 2 seconds, set typing to false
    _typingTimer = Timer(const Duration(seconds: 2), () {
      if (_isTyping) {
        _isTyping = false;
        ref
            .read(groupControllerProvider)
            .setGroupTypingStatus(widget.groupId, false);
      }
    });

    // If text is empty, immediately set typing to false
    if (text.isEmpty && _isTyping) {
      _isTyping = false;
      _typingTimer?.cancel();
      ref
          .read(groupControllerProvider)
          .setGroupTypingStatus(widget.groupId, false);
    }
  }

  void sendTextMessage() {
    if (_messageController.text.trim().isNotEmpty || imageFile != null) {
      log(_messageController.text.trim());

      // Stop typing indicator
      if (_isTyping) {
        _isTyping = false;
        _typingTimer?.cancel();
        ref
            .read(groupControllerProvider)
            .setGroupTypingStatus(widget.groupId, false);
      }

      ref
          .read(groupControllerProvider)
          .sendTextMessage(
            context,
            _messageController.text.trim(),
            widget.groupId,
            messageType,
            imageFile,
            widget.fcmToken,
            widget.receiverIds,
            widget.groupName,
            widget.type
          );
      setState(() {
        messageType = "text";
        imageFile = null;
        _hasText = false;
        _messageController.clear();
      });
    }
  }

  void _sendWish() {
    if (widget.wish != null && widget.wish!.trim().isNotEmpty) {
      // Stop typing indicator
      if (_isTyping) {
        _isTyping = false;
        _typingTimer?.cancel();
        ref
            .read(groupControllerProvider)
            .setGroupTypingStatus(widget.groupId, false);
      }

      ref
          .read(groupControllerProvider)
          .sendTextMessage(
            context,
            widget.wish!.trim(),
            widget.groupId,
            messageType,
            imageFile,
            widget.fcmToken,
            widget.receiverIds,
            widget.groupName,
            widget.type
          );
      setState(() {
        messageType = "text";
        imageFile = null;
        _hasText = false;
        _messageController.clear();
      });
    }
  }

  void selectImage() async {
    File? image = await pickImageFromGallery(context);
    if (image != null) {
      setState(() {
        imageFile = image;
        messageType = "image";
      });
    }
  }

  void selectVideo() async {
    File? video = await pickVideoFromGallery(context);
    if (video != null) {
      setState(() {
        imageFile = video;
        messageType = "video";
      });
    }
  }

  void selectGif() async {
    final gif = await pickGif(context);
    if (gif != null) {
      setState(() {
        imageFile = gif.url;
        messageType = "gif";
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
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
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
                  title: 'GIF',
                  icon: Icons.gif_box_rounded,
                  gradient: const [Color(0xFF00CEC9), Color(0xFF00B894)],
                  onTap: () {
                    Navigator.pop(context);
                    selectGif();
                  },
                ),
              ],
            ),
          ],
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
                  messageType == 'image'
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
    if (messageType == 'video' && imageFile is File) {
      return Container(
        color: const Color(0xFF222034),
        child: const Icon(Icons.videocam_rounded, color: greyColor, size: 28),
      );
    }
    if (messageType == 'gif') {
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
    final hasContent = _hasText || imageFile != null;

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
                        // GIF chip
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: selectGif,
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 4,
                              ),
                              margin: const EdgeInsets.only(left: 4, right: 2),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.07),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  width: 0.8,
                                ),
                              ),
                              child: const Text(
                                'GIF',
                                style: TextStyle(
                                  color: greyColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),
                        ),
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
                              isCollapsed: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 10,
                              ),
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
                        // Quick wish button if applicable
                        if (widget.wish != null &&
                            widget.wish!.trim().isNotEmpty)
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () {
                                HapticFeedback.lightImpact();
                                _sendWish();
                              },
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 5,
                                ),
                                margin: const EdgeInsets.only(left: 3, right: 3),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFFFF9F43),
                                      Color(0xFFFF6B2D),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(
                                        0xFFFF6B2D,
                                      ).withValues(alpha: 0.35),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: const Text(
                                  "🙇🏻‍♂️",
                                  style: TextStyle(fontSize: 16),
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
}
