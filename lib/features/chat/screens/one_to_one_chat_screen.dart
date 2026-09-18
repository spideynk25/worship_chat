import 'dart:developer';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/adapters.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/utils/file_messages.dart';
import 'package:worship_chat/common/utils/utils.dart';
import 'package:worship_chat/common/widgets/loader.dart';
import 'package:worship_chat/common/widgets/user_avatar.dart';
import 'package:worship_chat/features/auth/controller/auth_controller.dart';
import 'package:worship_chat/features/chat/controller/chat_controller.dart';
import 'package:worship_chat/features/chat/screens/user_info_screen.dart';
import 'package:worship_chat/features/chat/widgets/one_to_one_bottom_chat_field_widget.dart';
import 'package:worship_chat/models/user_model.dart';
import 'package:worship_chat/features/chat/widgets/one_to_one_chat_list_widget.dart';

final displayImageProvider = StateProvider<bool>((ref) => false);

class OneToOneChatScreen extends ConsumerStatefulWidget {
  static const String routeName = '/mobile-chat-screen';
  final String name;
  final String uid;
  final String fcmToken;
  final String? profilePic;
  final bool? unseenCount;
  final String? chatBackgroundUrl;

  const OneToOneChatScreen({
    super.key,
    required this.name,
    required this.uid,
    required this.fcmToken,
    required this.unseenCount,
    required this.profilePic,
    required this.chatBackgroundUrl,
  });

  @override
  ConsumerState<ConsumerStatefulWidget> createState() =>
      _OneToOneChatScreenState();
}

class _OneToOneChatScreenState extends ConsumerState<OneToOneChatScreen> {
  @override
  void initState() {
    super.initState();
    displayOrHideImage();
  }

  Future<void> displayOrHideImage() async {
    Box displayImageBox;
    if (!Hive.isBoxOpen('displayImage')) {
      displayImageBox = await Hive.openBox('displayImage');
    } else {
      displayImageBox = Hive.box('displayImage');
    }
    final displayImage = displayImageBox.get('displayImage') ?? true;
    ref.read(displayImageProvider.notifier).state = displayImage;
  }

  Future<File?> _cropImage(File imageFile) async {
    try {
      final screenSize = MediaQuery.of(context).size;
      final padding = MediaQuery.of(context).padding;
      const appBarHeight = kToolbarHeight;
      const bottomChatHeight = 70.0;

      final usableHeight =
          screenSize.height -
          padding.top -
          padding.bottom -
          appBarHeight -
          bottomChatHeight;
      final usableWidth = screenSize.width;
      final aspectRatio = usableWidth / usableHeight;

      CroppedFile? croppedFile = await ImageCropper().cropImage(
        sourcePath: imageFile.path,
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 100,
        aspectRatio: CropAspectRatio(ratioX: aspectRatio, ratioY: 1),
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Background Image',
            toolbarColor: appBarColor,
            toolbarWidgetColor: Colors.white,
            backgroundColor: Colors.black,
            activeControlsWidgetColor: tabColor,
            initAspectRatio: CropAspectRatioPreset.original,
            lockAspectRatio: false,
            hideBottomControls: true,
            showCropGrid: true,
            statusBarColor: appBarColor,
            dimmedLayerColor: Colors.black.withOpacity(0.8),
            cropFrameColor: Colors.white,
            cropGridColor: Colors.white.withOpacity(0.5),
            cropFrameStrokeWidth: 2,
            cropGridRowCount: 3,
            cropGridColumnCount: 3,
          ),
          IOSUiSettings(
            title: 'Crop Background Image',
            doneButtonTitle: 'Done',
            cancelButtonTitle: 'Cancel',
            aspectRatioLockEnabled: false,
            resetAspectRatioEnabled: true,
            aspectRatioPickerButtonHidden: false,
          ),
        ],
      );

      if (croppedFile != null) return File(croppedFile.path);
      return null;
    } catch (e) {
      log('Error cropping image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error cropping image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return null;
    }
  }

  Future<void> selectImageForBackground(
    WidgetRef ref,
    BuildContext context,
  ) async {
    File? image = await pickImageFromGallery(context);
    if (image == null) return;

    File? croppedImage = await _cropImage(image);
    if (croppedImage == null) return;

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );
    }

    try {
      String? imageUrl = await uploadImageToCloudinary(croppedImage, "others");
      if (mounted) Navigator.pop(context);

      if (imageUrl != null) {
        await ref
            .read(chatControllerProvider)
            .updateChatBackground(widget.uid, imageUrl);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Background updated successfully!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to upload image'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error uploading image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      log('Error uploading cropped image: $e');
    }
  }

  Future<void> showOrHideChatBackgroundImage() async {
    Box displayImageBox;
    if (!Hive.isBoxOpen('displayImage')) {
      displayImageBox = await Hive.openBox('displayImage');
    } else {
      displayImageBox = Hive.box('displayImage');
    }
    final currentDisplayImage = ref.read(displayImageProvider);
    await displayImageBox.put('displayImage', !currentDisplayImage);
    ref.read(displayImageProvider.notifier).state = !currentDisplayImage;
  }

  // ✅ Navigate to user info screen
  void _openUserInfo() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserInfoScreen(
          userId: widget.uid,
          profilePic: widget.profilePic ?? '',
          name: widget.name,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actionsPadding: const EdgeInsets.only(left: 0),
        leading: IconButton(
          padding: const EdgeInsets.only(left: 12),
          onPressed: () => Navigator.pop(context),
          icon: const Icon(CupertinoIcons.back),
        ),
        leadingWidth: 20,
        backgroundColor: appBarColor,
        title: StreamBuilder<UserModel>(
          stream: ref.watch(authControllerProvider).userDataById(widget.uid),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Loader();
            }
            // ✅ Wrap entire title in GestureDetector to open user info
            return GestureDetector(
              onTap: _openUserInfo,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  UserAvatar(url: widget.profilePic, radius: 20),
                  const SizedBox(width: 10),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.name, style: const TextStyle(fontSize: 16)),
                      StreamBuilder<bool>(
                        stream: ref
                            .watch(chatControllerProvider)
                            .getTypingStatus(widget.uid),
                        builder: (context, typingSnapshot) {
                          final isTyping = typingSnapshot.data ?? false;
                          if (isTyping) {
                            return Row(
                              children: [
                                Text(
                                  'typing',
                                  style: TextStyle(
                                    fontWeight: FontWeight.normal,
                                    fontSize: 13,
                                    color: Colors.green.shade300,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                SizedBox(
                                  width: 20,
                                  height: 13,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      _TypingDot(delay: 0),
                                      const SizedBox(width: 2),
                                      _TypingDot(delay: 200),
                                      const SizedBox(width: 2),
                                      _TypingDot(delay: 400),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          }
                          return Text(
                            snapshot.data?.isOnline == true
                                ? 'online'
                                : 'offline',
                            style: const TextStyle(
                              fontWeight: FontWeight.normal,
                              fontSize: 13,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
        actions: [
          IconButton(
            onPressed: () => selectImageForBackground(ref, context),
            icon: const Icon(CupertinoIcons.photo),
          ),
          IconButton(
            onPressed: showOrHideChatBackgroundImage,
            icon: const Icon(Icons.hide_image),
          ),
        ],
      ),
      body: Stack(
        children: [
          Consumer(
            builder: (context, ref, child) {
              final displayImage = ref.watch(displayImageProvider);
              return widget.chatBackgroundUrl != null && displayImage
                  ? Container(
                      width: double.infinity,
                      height: double.infinity,
                      decoration: BoxDecoration(
                        image: DecorationImage(
                          image: NetworkImage(widget.chatBackgroundUrl!),
                          fit: BoxFit.cover,
                        ),
                      ),
                    )
                  : const SizedBox.shrink();
            },
          ),
          Column(
            children: [
              Expanded(
                child: OneToOneChatListWidget(
                  receiverUserId: widget.uid,
                  profilePic: widget.profilePic ?? "",
                ),
              ),
              OneToOneBottomChatFieldWidget(
                receiverUserId: widget.uid,
                fcmToken: widget.fcmToken,
                unseenCount: widget.unseenCount,
                chatBackgroundUrl: widget.chatBackgroundUrl,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Animated typing dot ──────────────────────────────────────────────────────

class _TypingDot extends StatefulWidget {
  final int delay;
  const _TypingDot({required this.delay});

  @override
  State<_TypingDot> createState() => _TypingDotState();
}

class _TypingDotState extends State<_TypingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _animation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _controller.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) => Container(
        width: 4,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.green.shade300.withOpacity(
            0.3 + (_animation.value * 0.7),
          ),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
