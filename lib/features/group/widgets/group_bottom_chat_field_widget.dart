import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/providers/message_reply_provider.dart';
import 'package:worship_chat/common/providers/message_edit_provider.dart';
import 'package:worship_chat/common/utils/utils.dart';
import 'package:worship_chat/common/widgets/camera_screen.dart';
import 'package:worship_chat/features/chat/widgets/camera_permission_handler.dart';
import 'package:worship_chat/features/chat/widgets/message_reply_preview.dart';
import 'package:worship_chat/features/chat/widgets/message_edit_preview.dart';
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

  // Multi-file media group (images or videos)
  List<File> _mediaFiles = [];
  String _mediaGroupType = ''; // 'image' or 'video'

  Timer? _typingTimer;
  bool _isTyping = false;
  bool _hasText = false;
  bool _isSendPressed = false;
  late final GroupController _groupController;
  late final StateController<MessageEdit?> _messageEditController;

  @override
  void initState() {
    super.initState();
    _groupController = ref.read(groupControllerProvider);
    _messageEditController = ref.read(messageEditProvider.notifier);
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
      _groupController.setGroupTypingStatus(widget.groupId, false);
    }
    if (_messageEditController.mounted) {
      final currentEdit = _messageEditController.state;
      if (currentEdit != null &&
          currentEdit.chatType == 'group' &&
          currentEdit.groupId == widget.groupId) {
        Future<void>.microtask(() {
          if (!_messageEditController.mounted) return;
          if (identical(_messageEditController.state, currentEdit)) {
            _messageEditController.state = null;
          }
        });
      }
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
      _groupController.setGroupTypingStatus(widget.groupId, true);
    }

    // Cancel existing timer
    _typingTimer?.cancel();

    // Set new timer - if user stops typing for 2 seconds, set typing to false
    _typingTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      if (_isTyping) {
        _isTyping = false;
        _groupController.setGroupTypingStatus(widget.groupId, false);
      }
    });

    // If text is empty, immediately set typing to false
    if (text.isEmpty && _isTyping) {
      _isTyping = false;
      _typingTimer?.cancel();
      _groupController.setGroupTypingStatus(widget.groupId, false);
    }
  }

  void sendTextMessage() async {
    final hasMedia = _mediaFiles.isNotEmpty || imageFile != null;
    if (_messageController.text.trim().isEmpty && !hasMedia) {
      return;
    }

    // Stop typing indicator
    if (_isTyping) {
      _isTyping = false;
      _typingTimer?.cancel();
      ref
          .read(groupControllerProvider)
          .setGroupTypingStatus(widget.groupId, false);
    }

    final messageText = _messageController.text.trim();
    final currentImageFile = imageFile;
    var currentMessageType = messageType;
    final currentMediaFiles = List<File>.from(_mediaFiles);
    final currentMediaGroupType = _mediaGroupType;

    if (messageText.isEmpty && currentImageFile == null && currentMediaFiles.isEmpty) {
      return;
    }

    var textToSend = messageText;
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
      if (currentMediaFiles.isNotEmpty) {
        final mediaGroupId = const Uuid().v1();
        for (int i = 0; i < currentMediaFiles.length; i++) {
          await ref.read(groupControllerProvider).sendTextMessage(
                context,
                i == 0 ? messageText : '',
                widget.groupId,
                currentMediaGroupType,
                currentMediaFiles[i],
                widget.fcmToken,
                widget.receiverIds,
                widget.groupName,
                widget.type,
                mediaGroupId: mediaGroupId,
              );
        }
      } else {
        await ref.read(groupControllerProvider).sendTextMessage(
              context,
              textToSend,
              widget.groupId,
              currentMessageType,
              currentImageFile,
              widget.fcmToken,
              widget.receiverIds,
              widget.groupName,
              widget.type,
            );
      }
    } catch (e) {
      log("Error sending group message: $e");
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
        _mediaFiles = [];
        _mediaGroupType = '';
        _hasText = false;
        _messageController.clear();
      });
    }
  }

  void selectImage() async {
    final files = await pickMultipleImagesFromGallery(context);
    if (files.isNotEmpty) {
      setState(() {
        if (files.length == 1) {
          imageFile = files.first;
          messageType = "image";
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

  void selectVideo() async {
    final files = await pickMultipleVideosFromGallery(context);
    if (files.isNotEmpty) {
      setState(() {
        if (files.length == 1) {
          imageFile = files.first;
          messageType = "video";
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

  void selectDocument() async {
    final doc = await pickDocumentFile(context);
    if (doc != null) {
      setState(() {
        imageFile = doc;
        messageType = "document";
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
                const SizedBox(width: 56),
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

  Widget _buildSendButton({
    required bool isEditing,
    MessageEdit? messageEdit,
  }) {
    final hasContent = _hasText || imageFile != null || _mediaFiles.isNotEmpty || isEditing;

    return GestureDetector(
      onTapDown: (_) => setState(() => _isSendPressed = true),
      onTapUp: (_) => setState(() => _isSendPressed = false),
      onTapCancel: () => setState(() => _isSendPressed = false),
      onTap: () {
        HapticFeedback.lightImpact();
        if (isEditing && messageEdit != null) {
          final updatedText = _messageController.text.trim();
          if (updatedText.isNotEmpty) {
            ref.read(groupControllerProvider).editGroupMessage(
              groupId: widget.groupId,
              messageId: messageEdit.messageId,
              newText: updatedText,
            );
          }
          ref.read(messageEditProvider.notifier).state = null;
          _messageController.clear();
          _focusNode.unfocus();
          return;
        }
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
              colors: isEditing
                  ? const [Color(0xFF00C853), Color(0xFF64DD17)]
                  : (hasContent
                      ? const [tabColor, accentOrange]
                      : [
                          tabColor.withValues(alpha: 0.55),
                          accentOrange.withValues(alpha: 0.55),
                        ]),
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: hasContent
                ? [
                    BoxShadow(
                      color: (isEditing ? const Color(0xFF00C853) : tabColor).withValues(alpha: 0.45),
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
                isEditing ? Icons.check_rounded : Icons.send_rounded,
                key: ValueKey<String>(isEditing ? 'edit_check' : hasContent.toString()),
                color: Colors.white,
                size: isEditing ? 24 : 21,
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
    final messageEdit = ref.watch(messageEditProvider);
    final isEditing = messageEdit != null &&
        messageEdit.chatType == 'group' &&
        messageEdit.groupId == widget.groupId;

    ref.listen<MessageEdit?>(messageEditProvider, (previous, next) {
      if (next != null &&
          next.chatType == 'group' &&
          next.groupId == widget.groupId) {
        _messageController.text = next.text;
        _messageController.selection = TextSelection.fromPosition(
          TextPosition(offset: _messageController.text.length),
        );
        _focusNode.requestFocus();
      }
    });

    final messageReply = ref.watch(messageReplyProvider);
    final isShowMessageReply = messageReply != null;

    return SafeArea(
      top: false,
      bottom: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isEditing)
            MessageEditPreview(
              text: messageEdit.text,
              onCancel: () {
                ref.read(messageEditProvider.notifier).state = null;
                _messageController.clear();
                _focusNode.unfocus();
              },
            )
          else if (isShowMessageReply)
            const MessageReplyPreview(),
          if (!isEditing) _buildAttachedMediaPreview(),
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
                              hintText: isEditing
                                  ? 'Edit message...'
                                  : ((imageFile != null || _mediaFiles.isNotEmpty)
                                      ? 'Add a caption...'
                                      : 'Type a message...'),
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
                        if (!isEditing) ...[
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
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _buildSendButton(
                  isEditing: isEditing,
                  messageEdit: messageEdit,
                ),
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
