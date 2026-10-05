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
import 'package:worship_chat/features/dashboard/repositories/event_repository.dart';
import 'package:worship_chat/features/group/widgets/group_bottom_chat_field_widget.dart';
import 'package:worship_chat/features/group/widgets/group_chat_list_widget.dart';
import 'package:worship_chat/models/event.dart';
import 'package:worship_chat/models/group.dart';
import 'package:worship_chat/features/group/utils/group_template_helper.dart';
import 'package:worship_chat/features/group/utils/queendom_emblem_helper.dart';
import 'package:worship_chat/features/group/widgets/royal_avatar_decoration.dart';

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
  final Set<String> _dismissedBannerEventIds = {};
  late final Stream<GroupModel> _groupStream;

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
    _groupStream = FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.groupId)
        .snapshots()
        .map((doc) => GroupModel.fromMap(doc.data()!));
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
      FirebaseNotificationService.cancelNotificationsForChat(
        widget.groupId,
        chatName: widget.name,
      );
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
    FirebaseNotificationService.cancelNotificationsForChat(
      widget.groupId,
      chatName: widget.name,
    );
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
          AppSnackBar.success(context, 'Background updated successfully!');
        }
      } else {
        if (mounted) {
          AppSnackBar.error(context, 'Failed to upload image');
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Dismiss loading dialog
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        toolbarHeight: 114,
        backgroundColor: widget.color != null
            ? widget.color!.withAlpha(90)
            : appBarColor,
        elevation: 0,
        leadingWidth: 0,
        automaticallyImplyLeading: false,
        title: Padding(
          padding: const EdgeInsets.only(left: 4, right: 4, top: 12),
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
                      StreamBuilder<GroupModel>(
                        stream: _groupStream,
                        builder: (context, snapshot) {
                          final group = snapshot.data;
                          final pic = (group?.groupPic.isNotEmpty ?? false)
                              ? group!.groupPic
                              : (widget.groupPic ?? '');
                          return RoyalAvatarDecoration(
                            avatarRadius: 28,
                            position: group?.position,
                            livingPlace:
                                group?.effectiveLivingPlace ?? widget.name,
                            accentColor: _accentColor,
                            badge:
                                QueendomFamilyEmblemHelper.buildFamilyEmblemBadge(
                              family: group?.family,
                              fallbackText:
                                  group?.effectiveLivingPlace ?? widget.name,
                              accentColor: _accentColor,
                              size: 16.0,
                            ),
                            badgeBottomOffset: 0,
                            badgeRightOffset: 0,
                            child: CircleAvatar(
                              radius: 28,
                              backgroundImage:
                                  pic.isNotEmpty ? NetworkImage(pic) : null,
                              backgroundColor: Colors.grey[850],
                              child: pic.isEmpty
                                  ? const Icon(
                                      Icons.group,
                                      color: Colors.white,
                                      size: 26,
                                    )
                                  : null,
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            StreamBuilder<GroupModel>(
                              stream: _groupStream,
                              builder: (context, snapshot) {
                                final group = snapshot.data;
                                final title = group?.nameWithPosition ??
                                    GroupTemplateHelper.getNameWithPosition(
                                      name: widget.name,
                                      position: group?.position,
                                      family: group?.family,
                                    );
                                final position = group?.position;
                                final hasLivingPlaceEmblem =
                                    QueendomEmblemHelper.getAssetFromLivingPlace(
                                            title) !=
                                        null;

                                return QueendomEmblemHelper.buildRichTitle(
                                  title: title,
                                  family: group?.family,
                                  fallbackFamily: 'Main',
                                  leadingPosition: (!hasLivingPlaceEmblem &&
                                          position != null &&
                                          position.isNotEmpty &&
                                          position != 'None')
                                      ? position
                                      : null,
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.1,
                                    height: 1.15,
                                  ),
                                  emblemSize: 16.5,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                );
                              },
                            ),
                            const SizedBox(height: 2),
                            // Family Crest Badge & Typing/Members indicator
                            StreamBuilder<GroupModel>(
                              stream: _groupStream,
                              builder: (context, groupSnapshot) {
                                final family = groupSnapshot.data?.family;
                                final hasFamily = family != null &&
                                    family.isNotEmpty &&
                                    family != 'None';

                                return Row(
                                  children: [
                                    if (hasFamily) ...[
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4.5,
                                          vertical: 1,
                                        ),
                                        margin: const EdgeInsets.only(right: 5),
                                        decoration: BoxDecoration(
                                          color: _accentColor
                                              .withOpacity(0.2),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          border: Border.all(
                                            color: _accentColor
                                                .withOpacity(0.5),
                                            width: 0.6,
                                          ),
                                        ),

                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            QueendomFamilyEmblemWidget(
                                              family: family,
                                              size: 11,
                                            ),
                                            const SizedBox(width: 3),
                                            Text(
                                              '$family Family',
                                              style: TextStyle(
                                                fontSize: 9.5,
                                                color: Colors.white
                                                    .withOpacity(0.9),
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                    Expanded(
                                      child: StreamBuilder<Map<String, String>>(
                                        stream: ref
                                            .watch(groupControllerProvider)
                                            .getGroupTypingStatus(widget.groupId),
                                        builder: (context, typingSnapshot) {
                                          final typingUsers =
                                              typingSnapshot.data ?? {};
                                          return GroupAppBarStatusSubtitle(
                                            typingUsers: typingUsers,
                                            memberCount: widget.membersUid.length,
                                            accentColor: _accentColor,
                                          );
                                        },
                                      ),
                                    ),
                                  ],
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
            padding: const EdgeInsets.symmetric(horizontal: 2),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 40),
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
            stream: _groupStream,
            builder: (context, snapshot) {
              return PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                padding: const EdgeInsets.only(left: 0, right: 6),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 40),
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
              _buildGroupBirthdayMention(),
              _buildRoyalSanctuaryBanner(),
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

  Widget _buildGroupBirthdayMention() {
    return StreamBuilder<List<Event>>(
      stream: ref.watch(eventRepositoryProvider).eventsStream(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data == null) {
          return const SizedBox.shrink();
        }

        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);

        // Filter events strictly connected to THIS specific group
        final matchingEvents = snapshot.data!.where((event) {
          if (_dismissedBannerEventIds.contains(event.id)) return false;
          return event.connectedGroupId == widget.groupId;
        }).toList();

        if (matchingEvents.isEmpty) return const SizedBox.shrink();

        // Calculate occurrences
        Event? activeEvent;
        int lowestDiff = 999;

        for (final event in matchingEvents) {
          DateTime occurrence;
          if (event.isRecurring) {
            final thisYear = DateTime(
              now.year,
              event.date.month,
              event.date.day,
            );
            if (thisYear.isBefore(today)) {
              occurrence = DateTime(
                now.year + 1,
                event.date.month,
                event.date.day,
              );
            } else {
              occurrence = thisYear;
            }
          } else {
            occurrence = DateTime(
              event.date.year,
              event.date.month,
              event.date.day,
            );
          }

          final diff = occurrence.difference(today).inDays;
          if (diff >= 0 && diff <= 7 && diff < lowestDiff) {
            lowestDiff = diff;
            activeEvent = event;
          }
        }

        if (activeEvent == null) return const SizedBox.shrink();

        final isToday = lowestDiff == 0;
        final accent = _accentColor;

        return Center(
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1C2E).withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isToday
                    ? const Color(0xFFFFD700).withValues(alpha: 0.6)
                    : Colors.white.withValues(alpha: 0.15),
                width: isToday ? 1.2 : 0.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cake_rounded,
                  size: 14,
                  color: isToday ? const Color(0xFFFFD700) : accent,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    isToday
                        ? 'Birthday: ${activeEvent.title} (Today)'
                        : 'Birthday: ${activeEvent.title} (in $lowestDiff day${lowestDiff > 1 ? 's' : ''})',
                    style: TextStyle(
                      color: isToday ? const Color(0xFFFFD700) : Colors.white70,
                      fontSize: 11.5,
                      fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                      letterSpacing: 0.1,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isToday) ...[
                  const SizedBox(width: 4),
                  const Text('✨', style: TextStyle(fontSize: 10)),
                ],
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _dismissedBannerEventIds.add(activeEvent!.id);
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 12,
                      color: Colors.white60,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _isSanctuaryBannerDismissed = false;


  Widget _buildRoyalSanctuaryBanner() {
    if (_isSanctuaryBannerDismissed) return const SizedBox.shrink();

    return StreamBuilder<GroupModel>(
      stream: _groupStream,
      builder: (context, snapshot) {
        final group = snapshot.data;
        if (group == null) return const SizedBox.shrink();

        final position = group.position;
        final family = group.family;
        final wish = group.wish ?? widget.wish;
        final livingPlace = group.effectiveLivingPlace;

        final hasPosition =
            position != null && position.isNotEmpty && position != 'None';
        final hasFamily =
            family != null && family.isNotEmpty && family != 'None';
        final hasWish = wish != null && wish.isNotEmpty;

        if (!hasPosition && !hasFamily && !hasWish) {
          return const SizedBox.shrink();
        }

        final bannerColor = _accentColor;

        return Center(
          child: Container(
            margin: const EdgeInsets.fromLTRB(14, 2, 14, 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF141322).withOpacity(0.85),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: bannerColor.withOpacity(0.4),
                width: 0.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: bannerColor.withOpacity(0.12),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Row(
              children: [
                if (hasPosition) ...[
                  QueendomEmblemWidget(
                    position: position,
                    size: 26,
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (livingPlace.isNotEmpty)
                        QueendomEmblemHelper.buildRichTitle(
                          title: livingPlace,
                          family: family,
                          fallbackFamily: 'Main',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: bannerColor,
                            letterSpacing: 0.2,
                          ),
                          emblemSize: 13,
                        ),
                      if (hasWish)
                        Padding(
                          padding: const EdgeInsets.only(top: 1.5),
                          child: Text(
                            wish,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.white.withOpacity(0.85),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (hasFamily) ...[
                  const SizedBox(width: 6),
                  Tooltip(
                    message: '$family Family',
                    child: QueendomFamilyEmblemWidget(
                      family: family,
                      size: 22,
                    ),
                  ),
                ],
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _isSanctuaryBannerDismissed = true;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 12,
                      color: Colors.white60,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

