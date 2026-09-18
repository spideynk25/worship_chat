import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/providers/message_reply_provider.dart';
import 'package:worship_chat/common/utils/utils.dart';
import 'package:worship_chat/common/widgets/camera_screen.dart';
import 'package:worship_chat/features/chat/controller/chat_controller.dart';
import 'package:worship_chat/features/chat/widgets/camera_permission_handler.dart';
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
  dynamic imageFile;
  String messageType = "text";
  Timer? _typingTimer;
  bool _isTyping = false;
  bool _isGifLoading = false;
  List<Uint8List> _selectedGifs = [];

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
    if (_messageController.text.trim().isEmpty && imageFile == null) {
      return;
    }

    log("Sending message - Type: $messageType, HasFile: ${imageFile != null}");

    // Capture current values
    final messageText = _messageController.text.trim();
    final currentImageFile = imageFile;
    final currentMessageType = messageType;

    // Stop typing indicator
    if (_isTyping) {
      _isTyping = false;
      _typingTimer?.cancel();
      ref
          .read(chatControllerProvider)
          .setTypingStatus(widget.receiverUserId, false);
    }

    // Show loading indicator for media uploads
    bool showingLoader = false;
    if ((currentMessageType == 'image' || currentMessageType == 'video') &&
        currentImageFile != null) {
      showingLoader = true;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => WillPopScope(
          onWillPop: () async => false,
          child: Center(
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: 16),
                  Text(
                    currentMessageType == 'image'
                        ? 'Uploading image...'
                        : 'Uploading video...',
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Clear UI immediately
    setState(() {
      messageType = "text";
      imageFile = null;
    });
    _messageController.clear();

    try {
      // Send message (upload happens inside)
      await ref
          .read(chatControllerProvider)
          .sendTextMessage(
            context,
            messageText,
            widget.receiverUserId,
            currentMessageType,
            currentImageFile,
            widget.fcmToken,
            widget.unseenCount,
            widget.chatBackgroundUrl,
            "others",
          );

      log('✅ Message sent successfully');

      // Dismiss loader
      if (showingLoader && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    } catch (e) {
      log('❌ Error sending message: $e');

      // Dismiss loader
      if (showingLoader && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      // Show error and restore message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () {
                setState(() {
                  _messageController.text = messageText;
                  imageFile = currentImageFile;
                  messageType = currentMessageType;
                });
              },
            ),
          ),
        );
      }
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
                                  contentInsertionConfiguration:
                                      ContentInsertionConfiguration(
                                        onContentInserted:
                                            (KeyboardInsertedContent content) {
                                              _handleContentInsertion(content);
                                            },
                                        allowedMimeTypes: const [
                                          'image/gif',
                                          'image/*',
                                        ],
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

  Future<void> _handleContentInsertion(KeyboardInsertedContent content) async {
    setState(() {
      _isGifLoading = true;
    });

    try {
      Uint8List? gifData;

      if (content.data != null) {
        // Direct inline data
        gifData = content.data;
      } else if (content.uri != null) {
        // Content URI - need to read from it
        gifData = await _readContentUri(content.uri!);
      }

      log("test gif ${content.data.toString()}");

      if (gifData != null) {
        setState(() {
          messageType = "gif";
          imageFile = content.data.toString();
          _selectedGifs.add(gifData!);
          _isGifLoading = false;
        });
        //  sendTextMessage();

        // ScaffoldMessenger.of(context).showSnackBar(
        //   const SnackBar(
        //     content: Text('GIF added successfully!'),
        //     duration: Duration(seconds: 1),
        //     backgroundColor: Colors.green,
        //   ),
        // );
      } else {
        throw Exception('No data available');
      }
    } catch (e) {
      setState(() {
        _isGifLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading GIF: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<Uint8List?> _readContentUri(String uri) async {
    try {
      // Use platform channel to read content URI
      const platform = MethodChannel('my.app/accounts');
      final result = await platform.invokeMethod('readContentUri', {
        'uri': uri,
      });

      if (result != null) {
        return Uint8List.fromList(List<int>.from(result));
      }
    } catch (e) {
      print('Error reading content URI: $e');

      // Fallback: Try to read as file if it's a file:// URI
      if (uri.startsWith('file://')) {
        final filePath = uri.replaceFirst('file://', '');
        final file = File(filePath);
        if (await file.exists()) {
          return await file.readAsBytes();
        }
      }
    }

    return null;
  }
}
