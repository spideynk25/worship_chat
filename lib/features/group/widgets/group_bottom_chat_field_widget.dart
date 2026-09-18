import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'package:flutter/material.dart';
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
  dynamic imageFile;
  String messageType = "text";
  Timer? _typingTimer;
  bool _isTyping = false;

  @override
  void initState() {
    super.initState();
    _messageController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _messageController.removeListener(_onTextChanged);
    _messageController.dispose();
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
      backgroundColor: mobileChatBoxColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: tabColor.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.camera_alt, color: tabColor),
              ),
              title: const Text('Camera'),
              onTap: () {
                Navigator.pop(context);
                openCamera();
              },
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: tabColor.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.photo_library, color: tabColor),
              ),
              title: const Text('Gallery'),
              onTap: () {
                Navigator.pop(context);
                selectImage();
              },
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: tabColor.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.videocam, color: tabColor),
              ),
              title: const Text('Video'),
              onTap: () {
                Navigator.pop(context);
                selectVideo();
              },
            ),
          ],
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: mobileChatBoxColor,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: imageFile != null
                        ? Row(
                            children: [
                              if (messageType == 'image' && imageFile is File)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.file(
                                    imageFile,
                                    width: 100,
                                    height: 100,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              if (messageType == 'video' && imageFile is File)
                                Container(
                                  width: 100,
                                  height: 100,
                                  decoration: BoxDecoration(
                                    color: Colors.black26,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Center(
                                    child: Icon(
                                      Icons.videocam,
                                      color: Colors.white,
                                      size: 40,
                                    ),
                                  ),
                                ),
                              if (messageType == 'gif' && imageFile is String)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    imageFile,
                                    width: 100,
                                    height: 100,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              const SizedBox(width: 10),
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    imageFile = null;
                                    messageType = "text";
                                  });
                                },
                                child: const Icon(
                                  Icons.close,
                                  color: Colors.red,
                                ),
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.gif, color: Colors.grey),
                                onPressed: selectGif,
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                              ),
                              Expanded(
                                child: TextField(
                                  controller: _messageController,
                                  minLines: 1,
                                  maxLines: 5,
                                  decoration: const InputDecoration(
                                    hintText: 'Type a message...',
                                    border: InputBorder.none,
                                    isCollapsed: true,
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 10,
                                    ),
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.attach_file,
                                  color: Colors.grey,
                                ),
                                onPressed: showMediaOptions,
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                              ),
                              if (widget.wish != null &&
                                  widget.wish!.trim().isNotEmpty)
                                ElevatedButton(
                                  style: IconButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    backgroundColor: Colors.deepOrangeAccent,
                                  ),
                                  onPressed: _sendWish,
                                  child: const Text("🙇🏻‍♂️"),
                                ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: sendTextMessage,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(
                      color: tabColor,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.send, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
