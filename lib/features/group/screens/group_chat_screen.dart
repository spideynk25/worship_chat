import 'dart:developer';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/utils/active_chat_notifier.dart';
import 'package:worship_chat/common/utils/file_messages.dart';
import 'package:worship_chat/common/utils/firebase_notification_service.dart';
import 'package:worship_chat/common/utils/utils.dart';
import 'package:worship_chat/common/widgets/chat_status_indicator.dart';
import 'package:worship_chat/features/chat/screens/one_to_one_chat_screen.dart';
import 'package:worship_chat/features/group/controller/group_controller.dart';
import 'package:worship_chat/features/group/screens/edit_group_screen.dart';
import 'package:worship_chat/features/group/screens/group_gallery_screen.dart';
import 'package:worship_chat/features/group/screens/group_info_screen.dart';
import 'package:worship_chat/features/group/widgets/group_bottom_chat_field_widget.dart';
import 'package:worship_chat/features/group/widgets/group_chat_list_widget.dart';
import 'package:worship_chat/models/group.dart';

class GroupChatScreen extends ConsumerStatefulWidget {
  final String name;
  final String groupId;
  final List<String> fcmToken;
  final List<String> membersUid;
  final String? chatBackgroundUrl;
  final String? groupPic;
  final String? wish;
  final String? queendom;
  final Color? color;
  final String type;

  const GroupChatScreen({
    super.key,
    required this.name,
    required this.groupId,
    required this.fcmToken,
    required this.membersUid,
    required this.chatBackgroundUrl,
    required this.groupPic,
    required this.wish,
    required this.queendom,
    required this.color,
    required this.type,
  });

  @override
  ConsumerState<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends ConsumerState<GroupChatScreen>
    with WidgetsBindingObserver {
  late List<String> receiverIds;

  Color get _accentColor {
    if (widget.color != null) {
      final hsl = HSLColor.fromColor(widget.color!);
      if (hsl.lightness < 0.25) {
        return hsl.withLightness(0.55).withSaturation(0.7).toColor();
      }
      return widget.color!;
    }
    if (widget.queendom == 'Queen Pooja') {
      return const Color(0xFFFFD700);
    } else if (widget.queendom == 'Queen Rashmika') {
      return const Color(0xFFFF4081);
    }
    return tabColor;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ActiveChatNotifier.instance.enter(widget.groupId, chatName: widget.name);
    FirebaseNotificationService.cancelNotificationsForChat(
      widget.groupId,
      chatName: widget.name,
    );
    displayOrHideImage();
    String? currentUserUid = FirebaseAuth.instance.currentUser?.uid;
    receiverIds = widget.membersUid
        .where((uid) => uid != currentUserUid)
        .toList();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(groupControllerProvider).markGroupAsSeen(widget.groupId);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      ActiveChatNotifier.instance.enter(widget.groupId, chatName: widget.name);
      FirebaseNotificationService.cancelNotificationsForChat(
        widget.groupId,
        chatName: widget.name,
      );
      if (mounted) {
        ref.read(groupControllerProvider).markGroupAsSeen(widget.groupId);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ActiveChatNotifier.instance.leave();
    super.dispose();
  }

  void _openGroupInfo() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupInfoScreen(
          groupId: widget.groupId,
          groupPic: widget.groupPic ?? '',
          name: widget.name,
          wish: widget.wish,
          queendom: widget.queendom,
          color: widget.color,
        ),
      ),
    );
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
      // Get screen dimensions to calculate aspect ratio
      // Account for safe area (status bar, navigation bar, app bar, bottom chat field)
      final screenSize = MediaQuery.of(context).size;
      final padding = MediaQuery.of(context).padding;
      final appBarHeight = 100.0; // Your toolbar height
      final bottomChatHeight = 70.0; // Approximate bottom chat field height

      // Calculate usable height for background
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
            hideBottomControls:
                true, // Changed to true to avoid navigation bar overlap
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

      if (croppedFile != null) {
        return File(croppedFile.path);
      }
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

    // Crop the image
    File? croppedImage = await _cropImage(image);

    if (croppedImage == null) {
      // User cancelled cropping
      return;
    }

    // Show loading indicator
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );
    }

    try {
      // Upload cropped image
      String? imageUrl = await uploadImageToCloudinary(
        croppedImage,
        widget.type,
      );

      if (mounted) {
        Navigator.pop(context); // Dismiss loading dialog
      }

      if (imageUrl != null) {
        await ref
            .read(groupControllerProvider)
            .updateChatBackground(widget.groupId, imageUrl);

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
        Navigator.pop(context); // Dismiss loading dialog
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        toolbarHeight: 105,
        backgroundColor: widget.color != null
            ? widget.color!.withAlpha(90)
            : appBarColor,
        elevation: 0,
        leadingWidth: 0,
        automaticallyImplyLeading: false,
        title: Padding(
          padding: const EdgeInsets.only(left: 4, right: 4),
          child: Row(
            children: [
              IconButton(
                alignment: Alignment.centerLeft,
                onPressed: () => Navigator.pop(context),
                icon: const Icon(CupertinoIcons.back),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 36),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: _openGroupInfo,
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: widget.color != null
                                ? widget.color!
                                : Colors.white.withOpacity(0.3),
                            width: 2,
                          ),
                        ),
                        child:
                            widget.groupPic != null &&
                                widget.groupPic!.isNotEmpty
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  widget.groupPic!,
                                  width: 70,
                                  height: 70,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => CircleAvatar(
                                    radius: 35,
                                    backgroundColor: Theme.of(
                                      context,
                                    ).colorScheme.primaryContainer,
                                    child: Icon(
                                      Icons.group,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onPrimaryContainer,
                                    ),
                                  ),
                                ),
                              )
                            : CircleAvatar(
                                radius: 35,
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.primaryContainer,
                                child: Icon(
                                  Icons.group,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onPrimaryContainer,
                                ),
                              ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.name,
                              style: const TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.1,
                                height: 1.15,
                              ),
                              softWrap: true,
                              maxLines: null,
                              overflow: TextOverflow.visible,
                            ),
                            const SizedBox(height: 2),
                            // Typing & members indicator
                            StreamBuilder<Map<String, String>>(
                              stream: ref
                                  .watch(groupControllerProvider)
                                  .getGroupTypingStatus(widget.groupId),
                              builder: (context, typingSnapshot) {
                                final typingUsers = typingSnapshot.data ?? {};
                                return GroupAppBarStatusSubtitle(
                                  typingUsers: typingUsers,
                                  memberCount: widget.membersUid.length,
                                  accentColor: _accentColor,
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.photo_library_outlined),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 40),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => GroupGalleryScreen(
                  groupId: widget.groupId,
                  groupName: widget.name,
                  accentColor: _accentColor,
                ),
              ),
            ),
          ),
          StreamBuilder<GroupModel>(
            stream: FirebaseFirestore.instance
                .collection('groups')
                .doc(widget.groupId)
                .snapshots()
                .map((doc) => GroupModel.fromMap(doc.data()!)),
            builder: (context, snapshot) {
              return PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                padding: const EdgeInsets.only(left: 2, right: 8),
                constraints: const BoxConstraints(minWidth: 36, minHeight: 40),
                tooltip: 'More options',
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                offset: const Offset(0, 50),
                itemBuilder: (BuildContext context) {
                  List<PopupMenuEntry<String>> menuItems = [
                    PopupMenuItem<String>(
                      value: 'change_background',
                      child: Row(
                        children: [
                          Icon(
                            CupertinoIcons.photo,
                            size: 20,
                            color: Theme.of(context).iconTheme.color,
                          ),
                          const SizedBox(width: 12),
                          const Text('Change Background'),
                        ],
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'toggle_background',
                      child: Row(
                        children: [
                          Icon(
                            Icons.hide_image_outlined,
                            size: 20,
                            color: Theme.of(context).iconTheme.color,
                          ),
                          const SizedBox(width: 12),
                          const Text('Toggle Background'),
                        ],
                      ),
                    ),
                  ];

                  // Add edit option only for group creator
                  if (snapshot.hasData) {
                    menuItems.add(
                      PopupMenuItem<String>(
                        value: 'edit_group',
                        child: Row(
                          children: [
                            Icon(
                              Icons.edit_outlined,
                              size: 20,
                              color: Theme.of(context).iconTheme.color,
                            ),
                            const SizedBox(width: 12),
                            const Text('Edit Group'),
                          ],
                        ),
                      ),
                    );
                  }

                  return menuItems;
                },
                onSelected: (String value) {
                  switch (value) {
                    case 'change_background':
                      selectImageForBackground(ref, context);
                      break;
                    case 'toggle_background':
                      showOrHideChatBackgroundImage();
                      break;
                    case 'edit_group':
                      // Get the group data for navigation
                      FirebaseFirestore.instance
                          .collection('groups')
                          .doc(widget.groupId)
                          .get()
                          .then((doc) {
                            if (doc.exists) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => EditGroupScreen(
                                    group: GroupModel.fromMap(doc.data()!),
                                    type: widget.type,
                                  ),
                                ),
                              );
                            }
                          });
                      break;
                  }
                },
              );
            },
          ),
          const SizedBox(width: 4),
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
              Expanded(child: GroupChatListWidget(groupId: widget.groupId)),
              // Floating in-chat typing bubble for groups
              StreamBuilder<Map<String, String>>(
                stream: ref
                    .watch(groupControllerProvider)
                    .getGroupTypingStatus(widget.groupId),
                builder: (context, snapshot) {
                  final typingUsers = snapshot.data ?? {};
                  if (typingUsers.isEmpty) return const SizedBox.shrink();
                  final names = typingUsers.values.toList();
                  final text = names.length == 1
                      ? names[0]
                      : names.length == 2
                      ? '${names[0]} & ${names[1]}'
                      : '${names[0]} & ${names.length - 1} others';
                  return InChatTypingBubble(
                    isTyping: true,
                    userName: text,
                    accentColor: _accentColor,
                  );
                },
              ),
              GroupBottomChatFieldWidget(
                groupId: widget.groupId,
                fcmToken: widget.fcmToken,
                receiverIds: receiverIds,
                groupName: widget.name,
                wish: widget.wish,
                queendom: widget.queendom,
                type: widget.type,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
