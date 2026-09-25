import 'dart:developer';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/adapters.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/utils/active_chat_notifier.dart';
import 'package:worship_chat/common/utils/file_messages.dart';
import 'package:worship_chat/common/utils/firebase_notification_service.dart';
import 'package:worship_chat/common/utils/utils.dart';
import 'package:worship_chat/common/widgets/chat_status_indicator.dart';
import 'package:worship_chat/common/widgets/skeleton_loader.dart';
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

class _OneToOneChatScreenState extends ConsumerState<OneToOneChatScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ActiveChatNotifier.instance.enter(widget.uid, chatName: widget.name);
    FirebaseNotificationService.cancelNotificationsForChat(
      widget.uid,
      chatName: widget.name,
    );
    displayOrHideImage();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(chatControllerProvider).markChatAsSeen(widget.uid);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      ActiveChatNotifier.instance.enter(widget.uid, chatName: widget.name);
      FirebaseNotificationService.cancelNotificationsForChat(
        widget.uid,
        chatName: widget.name,
      );
      if (mounted) {
        ref.read(chatControllerProvider).markChatAsSeen(widget.uid);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ActiveChatNotifier.instance.leave();
    super.dispose();
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
            final user = snapshot.data;
            final displayName = (user?.name != null && user!.name!.isNotEmpty)
                ? user.name!
                : widget.name;
            final displayPic = (user?.profilePic != null && user!.profilePic!.isNotEmpty)
                ? user.profilePic
                : widget.profilePic;

            // Show skeleton only if both display name and profile are empty while connecting
            if (displayName.isEmpty && (displayPic == null || displayPic.isEmpty) && snapshot.connectionState == ConnectionState.waiting) {
              return const ChatAppBarSkeleton();
            }
            // ✅ Wrap entire title in GestureDetector to open user info
            return GestureDetector(
              onTap: _openUserInfo,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  UserAvatar(
                    url: displayPic,
                    radius: 20,
                    isOnline: user?.isOnline,
                    showOnlineIndicator: user != null,
                    borderColor: appBarColor,
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.1,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        StreamBuilder<bool>(
                          stream: ref
                              .watch(chatControllerProvider)
                              .getTypingStatus(widget.uid),
                          builder: (context, typingSnapshot) {
                            final isTyping = typingSnapshot.data ?? false;

                            // If snapshot is still connecting and has no user data yet
                            if (!snapshot.hasData && user == null) {
                              return ShimmerEffect(
                                child: Container(
                                  width: 44,
                                  height: 9,
                                  margin: const EdgeInsets.only(top: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.white24,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              );
                            }

                            return AppBarStatusSubtitle(
                              isTyping: isTyping,
                              isOnline: user?.isOnline == true,
                              accentColor: tabColor,
                            );
                          },
                        ),
                      ],
                    ),
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
              // Floating in-chat typing bubble
              StreamBuilder<bool>(
                stream: ref
                    .watch(chatControllerProvider)
                    .getTypingStatus(widget.uid),
                builder: (context, snapshot) {
                  final isTyping = snapshot.data ?? false;
                  return InChatTypingBubble(
                    isTyping: isTyping,
                    userName: widget.name,
                    profilePic: widget.profilePic,
                    accentColor: tabColor,
                  );
                },
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
