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
  // Cache the typing stream once so ref.watch is never called inside build().
  // Calling ref.watch(chatControllerProvider) in build() re-runs the full
  // build whenever a message is sent, causing the whole screen to blink.
  Stream<bool> _typingStream = Stream.value(false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ActiveChatNotifier.instance.enter(widget.uid, chatName: widget.name);
    FirebaseNotificationService.cancelNotificationsForChat(
      widget.uid,
      chatName: widget.name,
    );
    // Initialise typing stream directly (ref is available in initState for
    // ConsumerStatefulWidget). Using ref.read (not watch) means
    // chatControllerProvider notifications will NOT trigger build().
    _typingStream = ref.read(chatControllerProvider).getTypingStatus(widget.uid);
    displayOrHideImage();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FirebaseNotificationService.cancelNotificationsForChat(
        widget.uid,
        chatName: widget.name,
      );
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
    FirebaseNotificationService.cancelNotificationsForChat(
      widget.uid,
      chatName: widget.name,
    );
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
        AppSnackBar.error(context, 'Error cropping image: $e');
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
          AppSnackBar.success(
            context,
            'Background updated successfully!',
          );
        }
      } else {
        if (mounted) {
          AppSnackBar.error(context, 'Failed to upload image');
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        AppSnackBar.error(context, 'Error uploading image: $e');
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
  void _openUserInfo({String? name, String? pic}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserInfoScreen(
          userId: widget.uid,
          profilePic: pic ?? widget.profilePic ?? '',
          name: name ?? widget.name,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: appBarColor,
        automaticallyImplyLeading: false,
        leadingWidth: 0,
        titleSpacing: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.6),
          child: Container(
            color: dividerColor.withValues(alpha: 0.5),
            height: 0.6,
          ),
        ),
        title: Padding(
          padding: const EdgeInsets.only(left: 4, right: 4),
          child: Row(
            children: [
              IconButton(
                alignment: Alignment.centerLeft,
                onPressed: () => Navigator.pop(context),
                icon: const Icon(CupertinoIcons.back, size: 24),
                padding: const EdgeInsets.only(left: 6, right: 4),
                constraints: const BoxConstraints(minWidth: 36, minHeight: 44),
                tooltip: 'Back',
              ),
              Expanded(
                child: StreamBuilder<UserModel>(
                  stream:
                      ref.read(authControllerProvider).userDataById(widget.uid),
                  builder: (context, snapshot) {
                    final user = snapshot.data;
                    final displayName =
                        (user?.name != null && user!.name!.isNotEmpty)
                            ? user.name!
                            : widget.name;
                    final displayPic =
                        (user?.profilePic != null && user!.profilePic!.isNotEmpty)
                            ? user.profilePic
                            : widget.profilePic;

                    // Show skeleton only if both display name and profile are empty while connecting
                    if (displayName.isEmpty &&
                        (displayPic == null || displayPic.isEmpty) &&
                        snapshot.connectionState == ConnectionState.waiting) {
                      return const ChatAppBarSkeleton();
                    }

                    return GestureDetector(
                      onTap: () => _openUserInfo(
                        name: displayName,
                        pic: displayPic,
                      ),
                      behavior: HitTestBehavior.opaque,
                      child: Row(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: user?.isOnline == true
                                    ? const Color(0xFF00E676)
                                        .withValues(alpha: 0.5)
                                    : Colors.white.withValues(alpha: 0.14),
                                width: 1.5,
                              ),
                              boxShadow: user?.isOnline == true
                                  ? [
                                      BoxShadow(
                                        color: const Color(0xFF00E676)
                                            .withValues(alpha: 0.22),
                                        blurRadius: 6,
                                        spreadRadius: 0.5,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: UserAvatar(
                              url: displayPic,
                              radius: 20,
                              isOnline: user?.isOnline,
                              showOnlineIndicator: user?.isOnline == true,
                              borderColor: appBarColor,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  displayName,
                                  style: const TextStyle(
                                    fontSize: 16.0,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.15,
                                    color: Colors.white,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                StreamBuilder<bool>(
                                  stream: _typingStream,
                                  builder: (context, typingSnapshot) {
                                    final isTyping =
                                        typingSnapshot.data ?? false;

                                    if (!snapshot.hasData && user == null) {
                                      return ShimmerEffect(
                                        child: Container(
                                          width: 44,
                                          height: 9,
                                          margin: const EdgeInsets.only(top: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.white24,
                                            borderRadius:
                                                BorderRadius.circular(4),
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
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.photo),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 40),
            tooltip: 'Change Background',
            onPressed: () => selectImageForBackground(ref, context),
          ),
          Consumer(
            builder: (context, ref, _) {
              final displayImage = ref.watch(displayImageProvider);
              return PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                padding: const EdgeInsets.only(left: 2, right: 8),
                constraints: const BoxConstraints(minWidth: 36, minHeight: 40),
                tooltip: 'More options',
                color: const Color(0xFF161622),
                elevation: 8,
                offset: const Offset(0, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: Colors.white.withValues(alpha: 0.12),
                    width: 0.8,
                  ),
                ),
                onSelected: (value) {
                  switch (value) {
                    case 'view_profile':
                    case 'media_links':
                      _openUserInfo();
                      break;
                    case 'change_background':
                      selectImageForBackground(ref, context);
                      break;
                    case 'toggle_background':
                      showOrHideChatBackgroundImage();
                      break;
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem<String>(
                    value: 'view_profile',
                    height: 42,
                    child: Row(
                      children: [
                        Icon(
                          CupertinoIcons.person_crop_circle,
                          size: 19,
                          color: tabColor,
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'View Profile',
                          style: TextStyle(
                            fontSize: 13.5,
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'media_links',
                    height: 42,
                    child: Row(
                      children: [
                        const Icon(
                          CupertinoIcons.square_stack_3d_up,
                          size: 19,
                          color: Colors.white70,
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Media, Links & Docs',
                          style: TextStyle(
                            fontSize: 13.5,
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'change_background',
                    height: 42,
                    child: Row(
                      children: [
                        const Icon(
                          CupertinoIcons.photo_on_rectangle,
                          size: 19,
                          color: Colors.white70,
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Change Background',
                          style: TextStyle(
                            fontSize: 13.5,
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'toggle_background',
                    height: 42,
                    child: Row(
                      children: [
                        Icon(
                          displayImage
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 19,
                          color: Colors.white70,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          displayImage
                              ? 'Hide Background'
                              : 'Show Background',
                          style: const TextStyle(
                            fontSize: 13.5,
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
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
                stream: _typingStream,
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
