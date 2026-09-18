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
import 'package:worship_chat/common/utils/file_messages.dart';
import 'package:worship_chat/common/utils/utils.dart';
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

class _GroupChatScreenState extends ConsumerState<GroupChatScreen> {
  late List<String> receiverIds;

  @override
  void initState() {
    super.initState();
    displayOrHideImage();
    String? currentUserUid = FirebaseAuth.instance.currentUser?.uid;
    receiverIds = widget.membersUid
        .where((uid) => uid != currentUserUid)
        .toList();
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

  String _formatTypingUsers(Map<String, String> typingUsers) {
    if (typingUsers.isEmpty) return '';

    final names = typingUsers.values.toList();
    if (names.length == 1) {
      return '${names[0]} is typing';
    } else if (names.length == 2) {
      return '${names[0]} and ${names[1]} are typing';
    } else {
      return '${names[0]} and ${names.length - 1} others are typing';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        toolbarHeight: 100,
        backgroundColor: widget.color != null
            ? widget.color!.withAlpha(90)
            : appBarColor,
        elevation: 0,
        leadingWidth: 0,
        automaticallyImplyLeading: false,
        title: GestureDetector(
          onTap: _openGroupInfo,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 0, horizontal: 0),
            child: Row(
              spacing: 0,
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                IconButton(
                  alignment: Alignment.centerLeft,
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(CupertinoIcons.back),
                  padding: EdgeInsets.zero,
                ),
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
                  child: widget.groupPic != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            widget.groupPic!,
                            width: 70,
                            height: 70,
                            fit: BoxFit.cover,
                          ),
                        )
                      : CircleAvatar(
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
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 900,
                        child: Text(
                          widget.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.1,
                          ),
                          overflow: TextOverflow.visible,
                          softWrap: true,
                        ),
                      ),
                      // Typing indicator
                      StreamBuilder<Map<String, String>>(
                        stream: ref
                            .watch(groupControllerProvider)
                            .getGroupTypingStatus(widget.groupId),
                        builder: (context, typingSnapshot) {
                          final typingUsers = typingSnapshot.data ?? {};

                          if (typingUsers.isNotEmpty) {
                            return Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    _formatTypingUsers(typingUsers),
                                    style: TextStyle(
                                      fontWeight: FontWeight.normal,
                                      fontSize: 12,
                                      color: Colors.green.shade300,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                SizedBox(
                                  width: 20,
                                  height: 12,
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

                          // Show member count when no one is typing
                          return Text(
                            '${widget.membersUid.length} members',
                            style: const TextStyle(
                              fontWeight: FontWeight.normal,
                              fontSize: 12,
                            ),
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
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.photo_library_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => GroupGalleryScreen(
                  groupId: widget.groupId,
                  groupName: widget.name,
                  accentColor: widget.color!,
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

// Animated typing dot widget
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
      if (mounted) {
        _controller.repeat(reverse: true);
      }
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
      builder: (context, child) {
        return Container(
          width: 4,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.green.shade300.withOpacity(
              0.3 + (_animation.value * 0.7),
            ),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
}
