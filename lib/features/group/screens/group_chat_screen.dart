import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:math' hide log;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/utils/active_chat_notifier.dart';
import 'package:worship_chat/common/utils/file_messages.dart';
import 'package:worship_chat/common/utils/firebase_notification_service.dart';
import 'package:worship_chat/common/utils/utils.dart';
import 'package:worship_chat/common/widgets/chat_status_indicator.dart';
import 'package:worship_chat/features/chat/screens/one_to_one_chat_screen.dart';
import 'package:worship_chat/features/chat/widgets/chat_power_ups.dart';
import 'package:worship_chat/features/group/controller/group_controller.dart';
import 'package:worship_chat/features/group/screens/edit_group_screen.dart';
import 'package:worship_chat/features/group/screens/group_gallery_screen.dart';
import 'package:worship_chat/features/group/screens/group_info_screen.dart';
import 'package:worship_chat/features/group/services/roleplay_service.dart';
import 'package:worship_chat/features/dashboard/repositories/event_repository.dart';
import 'package:worship_chat/features/group/widgets/group_bottom_chat_field_widget.dart';
import 'package:worship_chat/features/group/widgets/group_chat_list_widget.dart';
import 'package:worship_chat/features/settings/providers/queendom_customization_provider.dart';
import 'package:worship_chat/features/home/screens/home_screen.dart';
import 'package:worship_chat/features/settings/models/queendom_customization_model.dart';
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
  late final Stream<Map<String, String>> _groupTypingStream;
  GroupModel? _currentGroup;
  StreamSubscription<GroupModel>? _groupSubscription;
  String? _currentChatBackgroundUrl;
  final ChatPowerUpController _powerUpController = ChatPowerUpController();
  bool get _isRoleplayMode =>
      RoleplayService.instance.isRoleplayActive(widget.groupId);
  bool get _isManualRoleplay =>
      RoleplayService.instance.isManualRoleplay(widget.groupId);
  int get _roleplayIntervalSeconds =>
      RoleplayService.instance.getInterval(widget.groupId);
  bool _isSendingManualPhoto = false;

  void _onRoleplayServiceUpdated() {
    if (mounted) setState(() {});
  }

  Future<void> _saveRoleplayInterval(int seconds) async {
    await RoleplayService.instance.setInterval(widget.groupId, seconds);
    if (mounted) setState(() {});
  }

  void _showRoleplayIntervalPicker() {
    int tempSeconds = _roleplayIntervalSeconds;
    final accent = _accentColor;
    final presets = [5, 10, 15, 20, 30, 45, 60, 90, 120];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              decoration: BoxDecoration(
                color: const Color(0xFF1B192A),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border.all(
                  color: accent.withValues(alpha: 0.35),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.6),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Handle
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),

                    // Title
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.timer_outlined,
                            size: 20,
                            color: accent,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Roleplay Image Interval',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                'Set seconds between random photos',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withValues(alpha: 0.6),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Big current display with - and +
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.25),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            color: tempSeconds > 3 ? accent : Colors.white24,
                            onPressed: tempSeconds > 3
                                ? () {
                                    setModalState(() {
                                      tempSeconds = max(3, tempSeconds - 1);
                                    });
                                  }
                                : null,
                          ),
                          Column(
                            children: [
                              Text(
                                '$tempSeconds',
                                style: TextStyle(
                                  fontSize: 34,
                                  fontWeight: FontWeight.bold,
                                  color: accent,
                                  letterSpacing: -1,
                                ),
                              ),
                              Text(
                                'seconds',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            color: tempSeconds < 300 ? accent : Colors.white24,
                            onPressed: tempSeconds < 300
                                ? () {
                                    setModalState(() {
                                      tempSeconds = min(300, tempSeconds + 1);
                                    });
                                  }
                                : null,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Slider
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: accent,
                        inactiveTrackColor: Colors.white12,
                        thumbColor: accent,
                        overlayColor: accent.withValues(alpha: 0.2),
                        trackHeight: 4,
                      ),
                      child: Slider(
                        value: tempSeconds.toDouble().clamp(3.0, 120.0),
                        min: 3.0,
                        max: 120.0,
                        divisions: 117,
                        onChanged: (val) {
                          setModalState(() {
                            tempSeconds = val.round();
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Preset Chips
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Quick Presets:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: presets.map((sec) {
                        final isSelected = tempSeconds == sec;
                        return ChoiceChip(
                          label: Text(
                            '${sec}s',
                            style: TextStyle(
                              color: isSelected ? Colors.black : Colors.white,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              fontSize: 12,
                            ),
                          ),
                          selected: isSelected,
                          selectedColor: accent,
                          backgroundColor:
                              Colors.white.withValues(alpha: 0.08),
                          showCheckmark: false,
                          onSelected: (selected) {
                            if (selected) {
                              setModalState(() {
                                tempSeconds = sec;
                              });
                            }
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 22),

                    // Apply Button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _saveRoleplayInterval(tempSeconds);
                          AppSnackBar.success(
                            context,
                            '⏱ Roleplay interval fixed to ${tempSeconds}s',
                          );
                        },
                        child: Text(
                          'Save & Fix to ${tempSeconds}s',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  bool _checkIsQueendom([GroupModel? group]) {
    final q = group?.queendom ?? widget.queendom;
    final t = widget.type;
    return q == 'Queen Pooja' ||
        q == 'Queen Rashmika' ||
        t == 'queenPooja' ||
        t == 'queenRashmika';
  }

  String _getQueendomDisplayName([GroupModel? group]) {
    final q = group?.queendom ?? widget.queendom;
    final t = widget.type;
    if (q == 'Queen Pooja' || t == 'queenPooja') return 'Queen Pooja';
    if (q == 'Queen Rashmika' || t == 'queenRashmika') return 'Queen Rashmika';
    return q ?? 'Queendom';
  }

  Future<void> _toggleRoleplayMode([bool? isCurrentlyRunning]) async {
    final running = isCurrentlyRunning ?? _isRoleplayMode;
    if (running) {
      await _stopRoleplayMode();
    } else {
      await _startRoleplayMode(mode: RoleplayModeType.automatic);
    }
  }

  Future<void> _stopRoleplayMode() async {
    await RoleplayService.instance.stopRoleplay(widget.groupId);
    if (mounted) {
      AppSnackBar.info(context, '🎭 Roleplay mode deactivated');
    }
  }

  Future<void> _startRoleplayMode({
    RoleplayModeType mode = RoleplayModeType.automatic,
  }) async {
    final success = await RoleplayService.instance.startRoleplay(
      groupId: widget.groupId,
      queendom: _getQueendomDisplayName(),
      groupName: widget.name,
      receiverIds: receiverIds,
      chatBackgroundUrl: _currentChatBackgroundUrl ?? widget.chatBackgroundUrl,
      groupPic: widget.groupPic,
      intervalSeconds: _roleplayIntervalSeconds,
      mode: mode,
    );

    if (!success) {
      if (mounted) {
        AppSnackBar.warning(
          context,
          'No photos found in gallery for roleplay mode',
        );
      }
      return;
    }

    if (mounted) {
      if (mode == RoleplayModeType.automatic) {
        AppSnackBar.success(
          context,
          '🎭 Roleplay mode activated (Automatic)! Random photo every ${_roleplayIntervalSeconds}s',
        );
      } else {
        AppSnackBar.success(
          context,
          '🎭 Roleplay mode activated (Manual)! Tap the top-left button to send random photos.',
        );
      }
    }
  }

  Future<void> _switchRoleplayMode(RoleplayModeType newMode) async {
    await RoleplayService.instance.switchRoleplayMode(widget.groupId, newMode);
    if (mounted) {
      if (newMode == RoleplayModeType.manual) {
        AppSnackBar.info(
          context,
          'Switched to Manual Roleplay. Tap the floating button to send photos.',
        );
      } else {
        AppSnackBar.info(
          context,
          'Switched to Automatic Roleplay (${_roleplayIntervalSeconds}s).',
        );
      }
    }
  }

  Future<void> _sendManualRoleplayPhoto() async {
    if (_isSendingManualPhoto) return;
    HapticFeedback.lightImpact();
    setState(() {
      _isSendingManualPhoto = true;
    });

    try {
      final success = await RoleplayService.instance.postSingleRoleplayPhoto(
        widget.groupId,
        queendom: _getQueendomDisplayName(),
        groupName: widget.name,
        receiverIds: receiverIds,
        chatBackgroundUrl:
            _currentChatBackgroundUrl ?? widget.chatBackgroundUrl,
        groupPic: widget.groupPic,
      );
      if (!success && mounted) {
        AppSnackBar.warning(
          context,
          'No photos found in gallery to send',
        );
      }
    } catch (e) {
      log('Error sending manual roleplay photo: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSendingManualPhoto = false;
        });
      }
    }
  }

  Widget _buildManualRoleplayFloatingButtonContent() {
    final accent = _accentColor;
    return SafeArea(
      top: false,
      bottom: false,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const Key('manual_roleplay_floating_button'),
          onTap: _isSendingManualPhoto ? null : _sendManualRoleplayPhoto,
          borderRadius: BorderRadius.circular(24),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  accent.withValues(alpha: 0.95),
                  accent.withValues(alpha: 0.8),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.45),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
                BoxShadow(
                  color: accent.withValues(alpha: 0.35),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isSendingManualPhoto)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                else
                  const Icon(
                    Icons.casino_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                const SizedBox(width: 7),
                Text(
                  _isSendingManualPhoto ? 'Sending...' : 'Random Photo',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handleBack() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
  }

  Color get _accentColor {
    if (widget.color != null &&
        widget.color != const Color(0xFFFFD700) &&
        widget.color != const Color(0xFFFF4081)) {
      final hsl = HSLColor.fromColor(widget.color!);
      if (hsl.lightness < 0.25) {
        return hsl.withLightness(0.55).withSaturation(0.7).toColor();
      }
      return widget.color!;
    }
    final pos = _currentGroup?.position;
    if (pos != null && pos.isNotEmpty && pos != 'None') {
      try {
        final categories = ref.read(queendomCustomizationProvider).allCategories;
        final match = categories.firstWhere(
          (c) => c.position.toLowerCase() == pos.toLowerCase(),
          orElse: () => QueendomCategory(
            title: '',
            position: '',
            color: widget.queendom == 'Queen Rashmika'
                ? const Color(0xFFFF4081)
                : const Color(0xFFFFD700),
            emoji: '',
          ),
        );
        final hsl = HSLColor.fromColor(match.color);
        if (hsl.lightness < 0.25) {
          return hsl.withLightness(0.55).withSaturation(0.7).toColor();
        }
        return match.color;
      } catch (_) {}
    }
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
    try {
      if (Hive.isBoxOpen('groupsBox')) {
        _currentGroup = Hive.box<GroupModel>('groupsBox').get(widget.groupId);
      }
    } catch (_) {}
    _currentChatBackgroundUrl = widget.chatBackgroundUrl;
    _loadCachedBackground();
    _groupTypingStream =
        ref.read(groupControllerProvider).getGroupTypingStatus(widget.groupId);
    WidgetsBinding.instance.addObserver(this);
    RoleplayService.instance.addListener(_onRoleplayServiceUpdated);
    _groupStream = FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.groupId)
        .snapshots()
        .map((doc) => (doc.exists && doc.data() != null)
            ? GroupModel.fromMap(doc.data()!)
            : null)
        .where((g) => g != null)
        .cast<GroupModel>();
    _groupSubscription = _groupStream.listen((group) {
      if (mounted) {
        if (_currentGroup?.name != group.name ||
            _currentGroup?.groupPic != group.groupPic ||
            _currentGroup?.chatBackgroundUrl != group.chatBackgroundUrl ||
            _currentGroup?.position != group.position ||
            _currentGroup?.queendom != group.queendom ||
            _currentGroup?.wish != group.wish ||
            _currentGroup?.roleplayIntervalSeconds != group.roleplayIntervalSeconds ||
            !listEquals(_currentGroup?.membersUid, group.membersUid)) {
          setState(() {
            _currentGroup = group;
          });
        }
      }
    });
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

  Future<void> _loadCachedBackground() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedBg = prefs.getString('group_bg_${widget.groupId}');
      if (cachedBg != null && cachedBg.isNotEmpty && mounted) {
        if (_currentChatBackgroundUrl != cachedBg) {
          setState(() {
            _currentChatBackgroundUrl = cachedBg;
          });
        }
      } else if (widget.chatBackgroundUrl != null && widget.chatBackgroundUrl!.isNotEmpty) {
        prefs.setString('group_bg_${widget.groupId}', widget.chatBackgroundUrl!);
      }
    } catch (e) {
      log('Error loading cached group background: $e');
    }
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
    _powerUpController.dispose();
    _groupSubscription?.cancel();
    RoleplayService.instance.removeListener(_onRoleplayServiceUpdated);
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

  void _openGroupGallery() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupGalleryScreen(
          groupId: widget.groupId,
          groupName: widget.name,
          accentColor: _accentColor,
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
            dimmedLayerColor: Colors.black.withValues(alpha: 0.8),
            cropFrameColor: Colors.white,
            cropGridColor: Colors.white.withValues(alpha: 0.5),
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
        setState(() {
          _currentChatBackgroundUrl = imageUrl;
        });
        SharedPreferences.getInstance().then((prefs) {
          prefs.setString('group_bg_${widget.groupId}', imageUrl);
        }).catchError((_) {});

        // Automatically ensure background is visible when user sets a new wallpaper
        if (!ref.read(displayImageProvider)) {
          Box displayImageBox = Hive.isBoxOpen('displayImage')
              ? Hive.box('displayImage')
              : await Hive.openBox('displayImage');
          await displayImageBox.put('displayImage', true);
          ref.read(displayImageProvider.notifier).state = true;
        }

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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          toolbarHeight: 76,
          backgroundColor: _accentColor.withAlpha(90),
          elevation: 0,
          scrolledUnderElevation: 0,
          leadingWidth: 0,
          automaticallyImplyLeading: false,
          title: Padding(
            padding: const EdgeInsets.only(left: 4, right: 4),
            child: Row(
              children: [
                IconButton(
                  alignment: Alignment.centerLeft,
                  onPressed: _handleBack,
                  icon: const Icon(CupertinoIcons.back, size: 24),
                  padding: const EdgeInsets.only(left: 6, right: 4),
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 48),
                  tooltip: 'Back',
                ),
              Expanded(
                child: GestureDetector(
                  onTap: _openGroupInfo,
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    children: [
                      StreamBuilder<GroupModel>(
                        stream: _groupStream,
                        initialData: _currentGroup,
                        builder: (context, snapshot) {
                          final group = snapshot.data ?? _currentGroup;
                          final pic = (group?.groupPic.isNotEmpty ?? false)
                              ? group!.groupPic
                              : (widget.groupPic ?? '');
                          return GestureDetector(
                            onTap: _openGroupInfo,
                            onLongPress: () {
                              HapticFeedback.mediumImpact();
                              _openGroupGallery();
                            },
                            child: RoyalAvatarDecoration(
                              avatarRadius: 21,
                              crownSize: 24,
                              crownTopOffset: -3.0,
                              perchOutside: true,
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
                                size: 13.5,
                              ),
                              badgeBottomOffset: 0,
                              badgeRightOffset: 0,
                              child: CircleAvatar(
                                radius: 21,
                                backgroundImage:
                                    pic.isNotEmpty ? NetworkImage(pic) : null,
                                backgroundColor: Colors.grey[850],
                                child: pic.isEmpty
                                    ? const Icon(
                                        Icons.group,
                                        color: Colors.white,
                                        size: 21,
                                      )
                                    : null,
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: StreamBuilder<GroupModel>(
                          stream: _groupStream,
                          initialData: _currentGroup,
                          builder: (context, snapshot) {
                            final group = snapshot.data ?? _currentGroup;
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

                            final family = group?.family;
                            final hasFamily = family != null &&
                                family.isNotEmpty &&
                                family != 'None';

                            // Robustly resolve and clean living place name
                            String livingPlace = '';
                            if (group?.livingPlace != null &&
                                group!.livingPlace!.trim().isNotEmpty) {
                              livingPlace = GroupTemplateHelper.cleanLivingPlace(
                                group.livingPlace!.trim(),
                                position: position,
                                family: family,
                              );
                            } else if (group != null &&
                                group.effectiveLivingPlace.trim().isNotEmpty &&
                                group.effectiveLivingPlace.trim().toLowerCase() !=
                                    group.name.trim().toLowerCase() &&
                                group.effectiveLivingPlace.trim().toLowerCase() !=
                                    widget.name.trim().toLowerCase()) {
                              livingPlace = GroupTemplateHelper.cleanLivingPlace(
                                group.effectiveLivingPlace.trim(),
                                position: position,
                                family: family,
                              );
                            } else if (position != null &&
                                position.isNotEmpty &&
                                position != 'None') {
                              final template =
                                  GroupTemplateHelper.generateTemplate(
                                position: position,
                                name: group?.name ?? widget.name,
                                family: family ?? 'Main',
                              );
                              if (template.livingPlace.isNotEmpty) {
                                livingPlace = template.livingPlace;
                              }
                            }

                            final cleanPlace =
                                GroupTemplateHelper.formatSanctuarySubtitle(
                              livingPlace: livingPlace,
                              deityName: group?.name ?? widget.name,
                            );

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                QueendomEmblemHelper.buildRichTitle(
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
                                    fontSize: 14.0,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.1,
                                    height: 1.15,
                                    color: Colors.white,
                                  ),
                                  emblemSize: 15.0,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (hasFamily) ...[
                                  const SizedBox(height: 2.0),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5.0,
                                      vertical: 1.0,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _accentColor
                                          .withValues(alpha: 0.2),
                                      borderRadius:
                                          BorderRadius.circular(4),
                                      border: Border.all(
                                        color: _accentColor
                                            .withValues(alpha: 0.5),
                                        width: 0.6,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        QueendomFamilyEmblemWidget(
                                          family: family,
                                          size: 10,
                                        ),
                                        const SizedBox(width: 3.0),
                                        Text(
                                          '$family Family',
                                          style: TextStyle(
                                            fontSize: 9.0,
                                            color: Colors.white
                                                .withValues(alpha: 0.9),
                                            fontWeight: FontWeight.w600,
                                          ),
                                          maxLines: 1,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                if (cleanPlace.isNotEmpty) ...[
                                  const SizedBox(height: 2.5),
                                  Text(
                                    cleanPlace,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 10.0,
                                      fontWeight: FontWeight.w500,
                                      color: _accentColor,
                                      letterSpacing: 0.15,
                                    ),
                                  ),
                                ],
                              ],
                            );
                          },
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
          StreamBuilder<GroupModel>(
            stream: _groupStream,
            builder: (context, snapshot) {
              return PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 22),
                padding: const EdgeInsets.only(left: 0, right: 6),
                constraints: const BoxConstraints(minWidth: 36, minHeight: 48),
                tooltip: 'More options',
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                offset: const Offset(0, 50),
                itemBuilder: (BuildContext context) {
                  final isQueendom = _checkIsQueendom(snapshot.data);
                  final isRoleplayRunning =
                      (snapshot.data?.isRoleplayActive == true) || _isRoleplayMode;
                  final currentMode = snapshot.data?.roleplayMode ??
                      RoleplayService.instance
                          .getRoleplayMode(widget.groupId)
                          .name;
                  final isManual = currentMode == 'manual';

                  List<PopupMenuEntry<String>> menuItems = [
                    PopupMenuItem<String>(
                      value: 'search_messages',
                      child: Row(
                        children: [
                          Icon(
                            _powerUpController.searchOpenNotifier.value
                                ? Icons.search_off_rounded
                                : Icons.search_rounded,
                            size: 20,
                            color: _powerUpController.searchOpenNotifier.value
                                ? _accentColor
                                : Theme.of(context).iconTheme.color,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            _powerUpController.searchOpenNotifier.value
                                ? 'Close Search'
                                : 'Search Messages',
                          ),
                        ],
                      ),
                    ),
                    const PopupMenuItem<String>(
                      value: 'pinned_messages',
                      child: Row(
                        children: [
                          Icon(
                            Icons.push_pin_outlined,
                            size: 20,
                            color: Color(0xFFFFD700),
                          ),
                          SizedBox(width: 12),
                          Text('Pinned Messages'),
                        ],
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'gallery',
                      child: Row(
                        children: [
                          Icon(
                            Icons.photo_library_outlined,
                            size: 20,
                            color: Theme.of(context).iconTheme.color,
                          ),
                          const SizedBox(width: 12),
                          const Text('Gallery'),
                        ],
                      ),
                    ),
                    if (isQueendom) ...[
                      if (isRoleplayRunning) ...[
                        PopupMenuItem<String>(
                          value: 'stop_roleplay',
                          child: Row(
                            children: const [
                              Icon(
                                Icons.stop_circle_outlined,
                                size: 20,
                                color: Color(0xFFFF5252),
                              ),
                              SizedBox(width: 12),
                              Text(
                                'Stop Roleplay Mode',
                                style: TextStyle(
                                  color: Color(0xFFFF5252),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isManual)
                          PopupMenuItem<String>(
                            value: 'switch_roleplay_auto',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.autorenew_rounded,
                                  size: 20,
                                  color: Theme.of(context).iconTheme.color,
                                ),
                                const SizedBox(width: 12),
                                const Text('Switch to Automatic Mode'),
                              ],
                            ),
                          )
                        else ...[
                          PopupMenuItem<String>(
                            value: 'switch_roleplay_manual',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.touch_app_outlined,
                                  size: 20,
                                  color: Theme.of(context).iconTheme.color,
                                ),
                                const SizedBox(width: 12),
                                const Text('Switch to Manual Mode'),
                              ],
                            ),
                          ),
                          PopupMenuItem<String>(
                            value: 'roleplay_interval',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.timer_outlined,
                                  size: 20,
                                  color: Theme.of(context).iconTheme.color,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Roleplay Interval (${_roleplayIntervalSeconds}s)',
                                ),
                              ],
                            ),
                          ),
                        ],
                      ] else ...[
                        PopupMenuItem<String>(
                          value: 'start_roleplay_auto',
                          child: Row(
                            children: [
                              Icon(
                                Icons.autorenew_rounded,
                                size: 20,
                                color: Theme.of(context).iconTheme.color,
                              ),
                              const SizedBox(width: 12),
                              const Text('Start Roleplay (Automatic)'),
                            ],
                          ),
                        ),
                        PopupMenuItem<String>(
                          value: 'start_roleplay_manual',
                          child: Row(
                            children: [
                              Icon(
                                Icons.touch_app_outlined,
                                size: 20,
                                color: Theme.of(context).iconTheme.color,
                              ),
                              const SizedBox(width: 12),
                              const Text('Start Roleplay (Manual)'),
                            ],
                          ),
                        ),
                        PopupMenuItem<String>(
                          value: 'roleplay_interval',
                          child: Row(
                            children: [
                              Icon(
                                Icons.timer_outlined,
                                size: 20,
                                color: Theme.of(context).iconTheme.color,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Roleplay Interval (${_roleplayIntervalSeconds}s)',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
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
                    case 'search_messages':
                      _powerUpController.toggleSearch();
                      break;
                    case 'pinned_messages':
                      PinnedMessagesBanner.showPinnedMessagesSheet(
                        context,
                        controller: _powerUpController,
                        accentColor: _accentColor,
                        onUnpin: (id) async {
                          ref
                              .read(groupControllerProvider)
                              .togglePinGroupMessage(
                                groupId: widget.groupId,
                                messageId: id,
                                pin: false,
                              );
                        },
                      );
                      break;
                    case 'gallery':
                      _openGroupGallery();
                      break;
                    case 'start_roleplay_auto':
                    case 'start_roleplay':
                      _startRoleplayMode(mode: RoleplayModeType.automatic);
                      break;
                    case 'start_roleplay_manual':
                      _startRoleplayMode(mode: RoleplayModeType.manual);
                      break;
                    case 'switch_roleplay_auto':
                      _switchRoleplayMode(RoleplayModeType.automatic);
                      break;
                    case 'switch_roleplay_manual':
                      _switchRoleplayMode(RoleplayModeType.manual);
                      break;
                    case 'stop_roleplay':
                      _stopRoleplayMode();
                      break;
                    case 'toggle_roleplay':
                      _toggleRoleplayMode();
                      break;
                    case 'roleplay_interval':
                      _showRoleplayIntervalPicker();
                      break;
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
                            if (doc.exists && mounted) {
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
          StreamBuilder<GroupModel>(
            stream: _groupStream,
            builder: (context, snapshot) {
              final streamBg = snapshot.data?.chatBackgroundUrl;
              if (streamBg != null && streamBg.isNotEmpty) {
                SharedPreferences.getInstance().then((prefs) {
                  prefs.setString('group_bg_${widget.groupId}', streamBg);
                }).catchError((_) {});
              }
              final effectiveBg = (streamBg != null && streamBg.isNotEmpty)
                  ? streamBg
                  : (_currentChatBackgroundUrl ?? widget.chatBackgroundUrl);
              return Consumer(
                builder: (context, ref, child) {
                  final displayImage = ref.watch(displayImageProvider);
                  return effectiveBg != null &&
                          effectiveBg.isNotEmpty &&
                          displayImage
                      ? Container(
                          width: double.infinity,
                          height: double.infinity,
                          decoration: BoxDecoration(
                            image: DecorationImage(
                              image: CachedNetworkImageProvider(effectiveBg),
                              fit: BoxFit.cover,
                            ),
                          ),
                        )
                      : const SizedBox.shrink();
                },
              );
            },
          ),
          Column(
            children: [
              _buildGroupBirthdayMention(),
              ChatSearchToolbar(
                controller: _powerUpController,
                accentColor: _accentColor,
              ),
              PinnedMessagesBanner(
                controller: _powerUpController,
                accentColor: _accentColor,
                onUnpin: (id) async {
                  ref.read(groupControllerProvider).togglePinGroupMessage(
                        groupId: widget.groupId,
                        messageId: id,
                        pin: false,
                      );
                },
              ),
              Expanded(
                child: GroupChatListWidget(
                  groupId: widget.groupId,
                  accentColor: _accentColor,
                  queendom: widget.queendom,
                  powerUpController: _powerUpController,
                ),
              ),

              // Floating in-chat typing bubble for groups
              StreamBuilder<Map<String, String>>(
                stream: _groupTypingStream,
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
          // Floating button for Manual Roleplay Mode: Top Left & down the AppBar
          Positioned(
            top: 10,
            left: 14,
            child: StreamBuilder<GroupModel>(
              stream: _groupStream,
              builder: (context, snapshot) {
                final isRunning =
                    (snapshot.data?.isRoleplayActive == true) || _isRoleplayMode;
                final mode = snapshot.data?.roleplayMode ??
                    RoleplayService.instance
                        .getRoleplayMode(widget.groupId)
                        .name;
                final isManual = mode == 'manual' || _isManualRoleplay;

                if (!isRunning || !isManual) {
                  return const SizedBox.shrink();
                }
                return _buildManualRoleplayFloatingButtonContent();
              },
            ),
          ),
        ],
      ),
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

}

class RoyalSanctuaryAppBarBottom extends StatelessWidget
    implements PreferredSizeWidget {
  final Stream<GroupModel>? stream;
  final GroupModel? initialGroup;
  final String? fallbackWish;
  final String? fallbackName;
  final Color accentColor;
  final VoidCallback? onTap;

  const RoyalSanctuaryAppBarBottom({
    super.key,
    this.stream,
    this.initialGroup,
    this.fallbackWish,
    this.fallbackName,
    required this.accentColor,
    this.onTap,
  });

  @override
  Size get preferredSize => const Size.fromHeight(32.0);

  @override
  Widget build(BuildContext context) {
    if (stream != null) {
      return StreamBuilder<GroupModel>(
        stream: stream,
        initialData: initialGroup,
        builder: (context, snapshot) {
          final group = snapshot.data ?? initialGroup;
          return _buildContent(context, group);
        },
      );
    }
    return _buildContent(context, initialGroup);
  }

  Widget _buildContent(BuildContext context, GroupModel? group) {
    if (group == null && (fallbackName == null || fallbackName!.isEmpty)) {
      return const SizedBox.shrink();
    }

    final position = group?.position;
    final family = group?.family;
    final livingPlace = group?.effectiveLivingPlace ?? fallbackName ?? '';

    final hasPosition =
        position != null && position.isNotEmpty && position != 'None';
    final hasFamily =
        family != null && family.isNotEmpty && family != 'None';
    final hasLivingPlace = livingPlace.isNotEmpty;

    if (!hasPosition && !hasFamily && !hasLivingPlace) {
      return const SizedBox.shrink();
    }

    final bannerColor = accentColor;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 32,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.18),
          border: Border(
            top: BorderSide(
              color: bannerColor.withValues(alpha: 0.28),
              width: 0.6,
            ),
            bottom: BorderSide(
              color: bannerColor.withValues(alpha: 0.2),
              width: 0.6,
            ),
          ),
        ),
        child: Row(
          children: [
            if (hasPosition) ...[
              QueendomEmblemWidget(
                position: position,
                size: 20,
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: livingPlace.isNotEmpty
                  ? QueendomEmblemHelper.buildRichTitle(
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  : const SizedBox.shrink(),
            ),
            if (hasFamily) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: '$family Family',
                child: QueendomFamilyEmblemWidget(
                  family: family,
                  size: 18,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

