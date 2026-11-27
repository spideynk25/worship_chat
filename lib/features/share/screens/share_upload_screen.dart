import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:worship_chat/common/utils/app_capabilities.dart';
import 'package:worship_chat/common/utils/utils.dart';
import 'package:worship_chat/common/utils/share_intent_service.dart';
import 'package:worship_chat/common/widgets/skeleton_loader.dart';
import 'package:worship_chat/features/auth/controller/auth_controller.dart';
import 'package:worship_chat/features/chat/controller/chat_controller.dart';
import 'package:worship_chat/features/chat/screens/one_to_one_chat_screen.dart';
import 'package:worship_chat/features/group/controller/group_controller.dart';
import 'package:worship_chat/features/group/controller/group_gallery_controller.dart';
import 'package:worship_chat/features/group/screens/group_chat_screen.dart';
import 'package:worship_chat/features/group/screens/group_gallery_screen.dart';
import 'package:worship_chat/features/group/screens/recent_gallery_photos_screen.dart';
import 'package:worship_chat/features/group/utils/queendom_emblem_helper.dart';
import 'package:worship_chat/features/home/screens/home_screen.dart';
import 'package:worship_chat/features/settings/providers/queendom_customization_provider.dart';
import 'package:worship_chat/models/chat_contact.dart';
import 'package:worship_chat/models/group.dart';
import 'package:worship_chat/models/user_model.dart';

enum _ShareTarget { gallery, groupChat, directChat }

class ShareUploadScreen extends ConsumerStatefulWidget {
  final List<File>? files;
  final SharedPayload? payload;

  /// Optional test screen builders so navigation tests can verify destination
  /// routing and Back-to-Home behavior without Firebase initialization.
  @visibleForTesting
  final Widget Function()? homeScreenBuilder;

  @visibleForTesting
  final Widget Function(ChatContact contact)? directChatScreenBuilder;

  @visibleForTesting
  final Widget Function(GroupModel group, Color accentColor, String type)?
      groupChatScreenBuilder;

  @visibleForTesting
  final Widget Function(GroupModel group, Color accentColor)?
      groupGalleryScreenBuilder;

  const ShareUploadScreen({
    super.key,
    this.files,
    this.payload,
    this.homeScreenBuilder,
    this.directChatScreenBuilder,
    this.groupChatScreenBuilder,
    this.groupGalleryScreenBuilder,
  });

  @override
  ConsumerState<ShareUploadScreen> createState() => _ShareUploadScreenState();
}

class _ShareUploadScreenState extends ConsumerState<ShareUploadScreen>
    with SingleTickerProviderStateMixin {
  late final SharedPayload _payload;

  // Selected destinations: supports multiple groups or a single direct contact
  final Map<String, GroupModel> _selectedGroups = {};
  ChatContact? _selectedContact;

  // Unified persistent search
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  _ShareTarget _target = _ShareTarget.gallery;
  bool _isUploading = false;
  int _uploaded = 0;
  int _currentUploadingGroupIndex = 0;
  late TabController _tabController;

  // Cached streams to prevent stream recreation and UI rebuilding on progress updates
  late final Stream<List<GroupModel>> _poojaGroupsStream;
  late final Stream<List<GroupModel>> _rashmikaGroupsStream;
  late final Stream<List<ChatContact>> _directContactsStream;

  // Tab indices: 0 = Direct Message, 1 = Queen Pooja, 2 = Queen Rashmika
  static const int _kDirectTabIndex = 0;

  @override
  void initState() {
    super.initState();

    // Resolve payload
    _payload = widget.payload ??
        SharedPayload(
          files: widget.files ?? const [],
          type: SharedPayloadType.image,
        );

    // Initial target: since Direct Message is tab 0, start in directChat mode
    _target = _ShareTarget.directChat;

    // Initialize stable streams once in initState so setState() doesn't recreate them
    _poojaGroupsStream = ref.read(groupControllerProvider).getQueenPoojaStream();
    _rashmikaGroupsStream =
        ref.read(groupControllerProvider).getQueenRashmikaStream();
    _directContactsStream = ref.read(chatControllerProvider).chatContacts();

    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      setState(() {
        if (_tabController.index == _kDirectTabIndex) {
          if (_selectedContact != null || _selectedGroups.isEmpty) {
            _target = _ShareTarget.directChat;
          }
        } else {
          if (_target == _ShareTarget.directChat) {
            _target = _payload.canUploadToGallery
                ? _ShareTarget.gallery
                : _ShareTarget.groupChat;
          }
        }
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _safeExit() {
    ref.read(sharedFilesProvider.notifier).clear();
    ref.read(sharedPayloadProvider.notifier).clear();
    if (!mounted) return;
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    } else {
      nav.pushReplacement(
        MaterialPageRoute(
          settings: const RouteSettings(name: HomeScreen.routeName),
          builder: (_) => _buildHomeScreen(),
        ),
      );
    }
  }

  Widget _buildHomeScreen() {
    return widget.homeScreenBuilder?.call() ?? const HomeScreen();
  }

  Widget _buildDirectChatDestination(ChatContact contact) {
    if (widget.directChatScreenBuilder != null) {
      return widget.directChatScreenBuilder!(contact);
    }
    return OneToOneChatScreen(
      name: contact.name,
      uid: contact.uid,
      fcmToken: contact.fcmToken ?? '',
      unseenCount: contact.unseenCount,
      profilePic: contact.profilePic,
      chatBackgroundUrl: contact.chatBackgroundUrl,
    );
  }

  Widget _buildGroupGalleryDestination(GroupModel group) {
    final customization = ref.read(queendomCustomizationProvider);
    final accent = resolveGroupAccentColor(group, customization);
    if (widget.groupGalleryScreenBuilder != null) {
      return widget.groupGalleryScreenBuilder!(group, accent);
    }
    return GroupGalleryScreen(
      groupId: group.groupId,
      groupName: group.nameWithPosition,
      accentColor: accent,
    );
  }

  Widget _buildGroupChatDestination(GroupModel group) {
    final customization = ref.read(queendomCustomizationProvider);
    final accent = resolveGroupAccentColor(group, customization);
    final type = _groupType(group);
    if (widget.groupChatScreenBuilder != null) {
      return widget.groupChatScreenBuilder!(group, accent, type);
    }
    if (!AppCapabilities.current.chatEnabled) {
      return _buildGroupGalleryDestination(group);
    }
    return GroupChatScreen(
      groupPic: group.groupPic,
      chatBackgroundUrl: group.chatBackgroundUrl,
      name: group.nameWithPosition,
      groupId: group.groupId,
      fcmToken: List<String>.from(group.fcmTokens),
      membersUid: List<String>.from(group.membersUid),
      wish: group.wish,
      queendom: group.queendom,
      color: accent,
      type: type,
    );
  }

  void _finishAndExit(
    String message, {
    bool success = true,
    Widget? destinationScreen,
  }) {
    if (!mounted) return;

    if (!success) {
      setState(() => _isUploading = false);
      _snack(message, false);
      return;
    }

    _snack(message, true);
    ref.read(sharedFilesProvider.notifier).clear();
    ref.read(sharedPayloadProvider.notifier).clear();

    final hasCustomBuilders = widget.homeScreenBuilder != null ||
        widget.directChatScreenBuilder != null ||
        widget.groupChatScreenBuilder != null ||
        widget.groupGalleryScreenBuilder != null;

    if (!hasCustomBuilders && Firebase.apps.isEmpty) {
      _safeExit();
      return;
    }

    final nav = Navigator.of(context);
    final hasLiveHome = widget.homeScreenBuilder == null &&
        HomeScreen.isMountedInTree &&
        nav.canPop();

    if (hasLiveHome) {
      // Clear ShareUploadScreen and any intermediate screens above the live HomeScreen.
      nav.popUntil(
        (route) =>
            route.settings.name == HomeScreen.routeName || route.isFirst,
      );
    } else {
      // Ensure HomeScreen is ALWAYS the base route so pressing Back navigates to Home.
      nav.pushAndRemoveUntil(
        MaterialPageRoute(
          settings: const RouteSettings(name: HomeScreen.routeName),
          builder: (_) => _buildHomeScreen(),
        ),
        (route) => false,
      );
    }

    if (destinationScreen != null) {
      nav.push(
        MaterialPageRoute(builder: (_) => destinationScreen),
      );
    }
  }

  void _toggleGroup(GroupModel group) {
    setState(() {
      _selectedContact = null;
      if (_selectedGroups.containsKey(group.groupId)) {
        _selectedGroups.remove(group.groupId);
      } else {
        _selectedGroups[group.groupId] = group;
      }
      if (_target == _ShareTarget.directChat) {
        _target = _payload.canUploadToGallery
            ? _ShareTarget.gallery
            : _ShareTarget.groupChat;
      }
    });
  }

  void _selectContact(ChatContact contact) {
    setState(() {
      _selectedGroups.clear();
      _selectedContact = contact;
      _target = _ShareTarget.directChat;
    });
  }

  String _groupType(GroupModel group) {
    if (group.queendom == 'Queen Pooja') return 'queenPooja';
    if (group.queendom == 'Queen Rashmika') return 'queenRashmika';
    return 'group';
  }

  // ── Fast synchronous-first user data resolution ────────────────────────────

  Future<UserModel?> _getUserDataFast() async {
    UserModel? user;
    if (Hive.isBoxOpen('userBox')) {
      user = Hive.box<UserModel>('userBox').get('currentUser');
    }
    user ??= ref.read(userDataAuthProvider).asData?.value;
    if (user != null) return user;

    try {
      final authUser = FirebaseAuth.instance.currentUser;
      if (authUser != null) {
        user = UserModel(
          name: authUser.displayName ?? 'User',
          userName: authUser.displayName ?? 'User',
          uid: authUser.uid,
          profilePic: authUser.photoURL ?? '',
          isOnline: true,
          email: authUser.email ?? '',
          groupId: [],
          fcmToken: null,
        );
      }
    } catch (_) {}
    if (user != null) return user;

    try {
      return await ref.read(userDataAuthProvider.future).timeout(
        const Duration(seconds: 2),
        onTimeout: () => null,
      );
    } catch (_) {
      return null;
    }
  }

  // ── Upload to gallery ─────────────────────────────────────────────────────

  Future<void> _uploadToGallery() async {
    if (_selectedGroups.isEmpty || !_payload.canUploadToGallery) return;

    final userData = await _getUserDataFast();
    if (userData == null) {
      _snack('⚠️ Unable to verify user session', false);
      return;
    }

    setState(() {
      _isUploading = true;
      _uploaded = 0;
      _currentUploadingGroupIndex = 0;
    });

    final groupsList = _selectedGroups.values.toList();
    int totalSuccessCount = 0;
    int groupsUploaded = 0;
    final isVideo = _payload.type == SharedPayloadType.video;

    for (int g = 0; g < groupsList.length; g++) {
      final group = groupsList[g];
      if (mounted) {
        setState(() {
          _currentUploadingGroupIndex = g + 1;
          _uploaded = 0;
        });
      }

      final count = isVideo
          ? await ref
              .read(groupGalleryControllerProvider)
              .uploadVideos(
                groupId: group.groupId,
                videoFiles: _payload.files,
                uploaderName: userData.name ?? 'Unknown',
                caption: _payload.text,
                onProgress: (uploaded, _) {
                  if (mounted) setState(() => _uploaded = uploaded);
                },
              )
          : await ref
              .read(groupGalleryControllerProvider)
              .uploadImages(
                groupId: group.groupId,
                imageFiles: _payload.files,
                uploaderName: userData.name ?? 'Unknown',
                caption: _payload.text,
                onProgress: (uploaded, _) {
                  if (mounted) setState(() => _uploaded = uploaded);
                },
              );

      if (count > 0) {
        totalSuccessCount += count;
        groupsUploaded++;
      }
    }

    if (groupsList.length == 1) {
      final targetGroup = groupsList.first;
      _finishAndExit(
        totalSuccessCount > 0
            ? '✅ $totalSuccessCount ${isVideo ? "video" : "photo"}${totalSuccessCount == 1 ? '' : 's'} added to ${targetGroup.nameWithPosition} gallery'
            : '⚠️ Upload failed',
        success: totalSuccessCount > 0,
        destinationScreen: totalSuccessCount > 0
            ? _buildGroupGalleryDestination(targetGroup)
            : null,
      );
    } else {
      _finishAndExit(
        groupsUploaded > 0
            ? '✅ Added ${_payload.files.length} ${isVideo ? "video" : "photo"}${_payload.files.length == 1 ? '' : 's'} to $groupsUploaded of ${groupsList.length} galleries'
            : '⚠️ Upload failed',
        success: groupsUploaded > 0,
      );
    }
  }

  String _fileMessageType(File file) {
    final lower = file.path.toLowerCase();
    if (lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.3gp')) {
      return 'video';
    }
    return 'image';
  }

  // ── Send to group chat ────────────────────────────────────────────────────

  Future<void> _sendToGroupChat() async {
    if (_selectedGroups.isEmpty) return;

    final userData = await _getUserDataFast();
    if (userData == null) {
      _snack('⚠️ Unable to verify user session', false);
      return;
    }

    setState(() {
      _isUploading = true;
      _uploaded = 0;
      _currentUploadingGroupIndex = 0;
    });

    final groupsList = _selectedGroups.values.toList();
    final files = _payload.files;
    final isVideo = _payload.type == SharedPayloadType.video;

    for (int g = 0; g < groupsList.length; g++) {
      final group = groupsList[g];
      if (mounted) {
        setState(() {
          _currentUploadingGroupIndex = g + 1;
        });
      }

      final receiverIds = group.membersUid
          .where((uid) => uid != userData.uid)
          .toList();

      if (_payload.isTextOnly) {
        if (!mounted) return;
        await ref
            .read(groupControllerProvider)
            .sendTextMessage(
              context,
              _payload.text ?? '',
              group.groupId,
              'text',
              null,
              List<String>.from(group.fcmTokens),
              receiverIds,
              group.nameWithPosition,
              _groupType(group),
            );
      } else {
        // Media files sharing
        final mediaGroupId = files.length > 1 ? const Uuid().v1() : null;

        for (int i = 0; i < files.length; i++) {
          final file = files[i];
          final messageType = _fileMessageType(file);
          if (!mounted) return;
          await ref
              .read(groupControllerProvider)
              .sendTextMessage(
                context,
                i == 0 && _payload.text != null ? _payload.text! : '',
                group.groupId,
                messageType,
                file,
                List<String>.from(group.fcmTokens),
                receiverIds,
                group.nameWithPosition,
                _groupType(group),
                mediaGroupId: mediaGroupId,
              );
          if (mounted) setState(() => _uploaded = i + 1);
        }
      }
    }

    if (groupsList.length == 1) {
      final targetGroup = groupsList.first;
      final groupDest = _buildGroupChatDestination(targetGroup);
      if (_payload.isTextOnly) {
        _finishAndExit(
          '✅ Sent to ${targetGroup.nameWithPosition}',
          destinationScreen: groupDest,
        );
      } else {
        _finishAndExit(
          '✅ ${files.length} ${isVideo ? "video" : "photo"}${files.length == 1 ? '' : 's'} sent to ${targetGroup.nameWithPosition}',
          destinationScreen: groupDest,
        );
      }
    } else {
      if (_payload.isTextOnly) {
        _finishAndExit('✅ Sent message to ${groupsList.length} groups');
      } else {
        _finishAndExit(
          '✅ ${files.length} ${isVideo ? "video" : "photo"}${files.length == 1 ? '' : 's'} sent to ${groupsList.length} groups',
        );
      }
    }
  }

  // ── Send to 1-to-1 chat ───────────────────────────────────────────────────

  Future<void> _sendToDirectChat() async {
    final contact = _selectedContact;
    if (contact == null) return;

    final userData = await _getUserDataFast();
    if (userData == null) {
      _snack('⚠️ Unable to verify user session', false);
      return;
    }

    setState(() {
      _isUploading = true;
      _uploaded = 0;
    });

    if (_payload.isTextOnly) {
      if (!mounted) return;
      await ref
          .read(chatControllerProvider)
          .sendTextMessage(
            context,
            _payload.text ?? '',
            contact.uid,
            'text',
            null,
            contact.fcmToken ?? '',
            null,
            null,
            'others',
          );

      _finishAndExit(
        '✅ Sent to ${contact.name}',
        destinationScreen: _buildDirectChatDestination(contact),
      );
      return;
    }

    // Media files sharing
    final files = _payload.files;
    final isVideo = _payload.type == SharedPayloadType.video;
    final mediaGroupId = files.length > 1 ? const Uuid().v1() : null;

    for (int i = 0; i < files.length; i++) {
      final file = files[i];
      final messageType = _fileMessageType(file);
      if (!mounted) return;
      await ref
          .read(chatControllerProvider)
          .sendTextMessage(
            context,
            i == 0 && _payload.text != null ? _payload.text! : '',
            contact.uid,
            messageType,
            file,
            contact.fcmToken ?? '',
            null,
            null,
            'others',
            groupId: mediaGroupId,
          );
      if (mounted) setState(() => _uploaded = i + 1);
    }

    _finishAndExit(
      '✅ ${files.length} ${isVideo ? "video" : "photo"}${files.length == 1 ? '' : 's'} sent to ${contact.name}',
      destinationScreen: _buildDirectChatDestination(contact),
    );
  }

  Future<void> _submit() async {
    if (_selectedContact != null) {
      await _sendToDirectChat();
    } else if (_selectedGroups.isNotEmpty) {
      if (_target == _ShareTarget.gallery) {
        await _uploadToGallery();
      } else {
        await _sendToGroupChat();
      }
    }
  }

  void _snack(String msg, bool success) {
    if (!mounted) return;
    if (success) {
      AppSnackBar.success(context, msg);
    } else {
      AppSnackBar.error(context, msg);
    }
  }

  // ── Derived helpers ───────────────────────────────────────────────────────

  bool get _isDirectTab => _tabController.index == _kDirectTabIndex;
  bool get _hasSelection =>
      _selectedContact != null || _selectedGroups.isNotEmpty;

  String get _submitLabel {
    final count = _payload.isTextOnly ? 1 : _payload.files.length;
    final plural = count == 1 ? '' : 's';
    final typeName = _payload.isTextOnly
        ? (_payload.isYouTube
            ? 'YouTube link'
            : _payload.isXTwitter
                ? 'post'
                : 'message')
        : (_payload.type == SharedPayloadType.video ? 'video' : 'photo');

    if (_isUploading) {
      final verb = _target == _ShareTarget.gallery ? 'Uploading' : 'Sending';
      if (_selectedGroups.length > 1) {
        return '$verb to Group $_currentUploadingGroupIndex/${_selectedGroups.length}...';
      }
      if (_payload.isTextOnly) return '$verb...';
      return '$verb $_uploaded / $count...';
    }

    if (!_hasSelection) return 'Select a destination first';

    if (_selectedContact != null) {
      return 'Send $count $typeName$plural to ${_selectedContact!.name}';
    }

    final numGroups = _selectedGroups.length;
    if (numGroups == 1) {
      final group = _selectedGroups.values.first;
      switch (_target) {
        case _ShareTarget.gallery:
          return 'Upload $count $typeName$plural to Gallery';
        case _ShareTarget.groupChat:
        case _ShareTarget.directChat:
          return 'Send $count $typeName$plural to ${group.nameWithPosition}';
      }
    }

    switch (_target) {
      case _ShareTarget.gallery:
        return 'Upload $count $typeName$plural to $numGroups Galleries';
      case _ShareTarget.groupChat:
      case _ShareTarget.directChat:
        return 'Send $count $typeName$plural to $numGroups Groups';
    }
  }

  Color get _submitColor {
    switch (_target) {
      case _ShareTarget.gallery:
        return const Color(0xFFFFD700); // Royal Gold
      case _ShareTarget.groupChat:
        return const Color(0xFF9D4EDD); // Royal Purple
      case _ShareTarget.directChat:
        return const Color(0xFFC77DFF); // Lavender accent
    }
  }

  IconData get _submitIcon {
    switch (_target) {
      case _ShareTarget.gallery:
        return Icons.cloud_upload_rounded;
      case _ShareTarget.groupChat:
      case _ShareTarget.directChat:
        return Icons.send_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _safeExit();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: const Color(0xFF0A0912),
        appBar: AppBar(
          backgroundColor: const Color(0xFF120E1E),
          elevation: 0,
          leading: IconButton(
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, color: Colors.white70, size: 18),
            ),
            onPressed: _safeExit,
          ),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.auto_awesome, color: Color(0xFFFFD700), size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [
                      Color(0xFFFFDF7D),
                      Color(0xFFFFB300),
                      Color(0xFFFFA000),
                    ],
                  ).createShader(bounds),
                  child: const Text(
                    'QUEENDOM SHARE',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ],
          ),
          centerTitle: true,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF14121F),
                border: Border(
                  bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
                ),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorColor: const Color(0xFFFFD700),
                indicatorWeight: 3,
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: const Color(0xFFFFD700),
                unselectedLabelColor: Colors.grey[400],
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  letterSpacing: 0.2,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.normal,
                  fontSize: 13,
                ),
                isScrollable: false,
                tabAlignment: TabAlignment.fill,
                labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                tabs: const [
                  Tab(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Direct Message',
                        maxLines: 1,
                        softWrap: false,
                      ),
                    ),
                  ),
                  Tab(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Queen Pooja',
                        maxLines: 1,
                        softWrap: false,
                      ),
                    ),
                  ),
                  Tab(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Queen Rashmika',
                        maxLines: 1,
                        softWrap: false,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              // ── Preview Section ───────────────────────────────────────────
              _buildContentPreview(),

              // ── Share target toggle (only when gallery is available) ──────
              if (!_isDirectTab && _payload.canUploadToGallery)
                _buildTargetToggleBar(),

              // ── Text / Direct header info banner ──────────────────────────
              if (_isDirectTab || !_payload.canUploadToGallery)
                _buildModeInfoBanner(),

              // ── Selected destination banner ───────────────────────────────
              if (_hasSelection) _buildSelectedDestinationBanner(),

              // ── Unified Search Bar (persists across all tabs) ─────────────
              _SearchBar(
                controller: _searchController,
                query: _searchQuery,
                onChanged: (val) => setState(() => _searchQuery = val.trim()),
                onClear: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
              ),

              // ── Tab views with cached streams ─────────────────────────────
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // Direct Messages (Tab 0)
                    _ContactList(
                      stream: _directContactsStream,
                      selectedContact: _selectedContact,
                      searchQuery: _searchQuery,
                      onSelect: _selectContact,
                      emptyLabel: 'No conversations yet',
                    ),
                    // Queen Pooja (Tab 1)
                    _GroupList(
                      stream: _poojaGroupsStream,
                      selectedGroupIds: _selectedGroups.keys.toSet(),
                      searchQuery: _searchQuery,
                      onToggleGroup: _toggleGroup,
                      emptyLabel: 'No Queen Pooja groups available',
                    ),
                    // Queen Rashmika (Tab 2)
                    _GroupList(
                      stream: _rashmikaGroupsStream,
                      selectedGroupIds: _selectedGroups.keys.toSet(),
                      searchQuery: _searchQuery,
                      onToggleGroup: _toggleGroup,
                      emptyLabel: 'No Queen Rashmika groups available',
                    ),
                  ],
                ),
              ),

              // ── Upload progress indicator ─────────────────────────────────
              if (_isUploading)
                LinearProgressIndicator(
                  value: _payload.files.isNotEmpty
                      ? (((_currentUploadingGroupIndex > 0 ? (_currentUploadingGroupIndex - 1) : 0) * _payload.files.length + _uploaded) /
                          ((_selectedGroups.isNotEmpty ? _selectedGroups.length : 1) * _payload.files.length)).clamp(0.0, 1.0)
                      : null,
                  backgroundColor: const Color(0xFF1E1A2E),
                  valueColor: AlwaysStoppedAnimation<Color>(_submitColor),
                  minHeight: 4,
                ),

              // ── Submit Action Button ──────────────────────────────────────
              AnimatedPadding(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  keyboardHeight > 0 ? keyboardHeight + 8 : 16,
                ),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: !_hasSelection || _isUploading
                        ? null
                        : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _submitColor,
                      foregroundColor: _target == _ShareTarget.gallery
                          ? const Color(0xFF0E0B16)
                          : Colors.white,
                      disabledBackgroundColor: const Color(0xFF221E30),
                      disabledForegroundColor: Colors.grey[600],
                      elevation: _hasSelection ? 6 : 0,
                      shadowColor: _submitColor.withValues(alpha: 0.4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _isUploading
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: _target == _ShareTarget.gallery
                                      ? const Color(0xFF0E0B16)
                                      : Colors.white,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Flexible(
                                child: Text(
                                  _submitLabel,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(_submitIcon, size: 20),
                              const SizedBox(width: 10),
                              Flexible(
                                child: Text(
                                  _submitLabel,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Preview Widget Builder ────────────────────────────────────────────────

  Widget _buildContentPreview() {
    if (_payload.isTextOnly) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF141122),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _payload.isYouTube
                ? const Color(0xFFFF334B).withValues(alpha: 0.3)
                : _payload.isXTwitter
                    ? const Color(0xFF1DA1F2).withValues(alpha: 0.3)
                    : const Color(0xFFFFD700).withValues(alpha: 0.2),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildPlatformBadge(),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: _payload.text ?? ''));
                    AppSnackBar.success(context, 'Copied link to clipboard');
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.copy_rounded, size: 12, color: Colors.white70),
                        SizedBox(width: 4),
                        Text(
                          'Copy',
                          style: TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _payload.text ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ],
        ),
      );
    }

    if (_payload.type == SharedPayloadType.video) {
      return Container(
        height: 86,
        margin: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF141122),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFFFF9100).withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: const Color(0xFFFF9100).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.play_circle_fill_rounded,
                color: Color(0xFFFF9100),
                size: 32,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF9100).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'VIDEO',
                          style: TextStyle(
                            color: Color(0xFFFF9100),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          '${_payload.files.length} file${_payload.files.length == 1 ? '' : 's'}',
                          style: TextStyle(color: Colors.grey[400], fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _payload.files.first.path.split('/').last,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Photo carousel preview
    return Container(
      height: 86,
      margin: const EdgeInsets.only(top: 6, bottom: 2),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _payload.files.length,
        itemBuilder: (_, i) => Stack(
          children: [
            Container(
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.15),
                  width: 1.2,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: Image.file(
                  _payload.files[i],
                  width: 74,
                  height: 74,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 74,
                    height: 74,
                    color: const Color(0xFF1E1A2E),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.photo_rounded,
                      color: Colors.white.withValues(alpha: 0.45),
                      size: 26,
                    ),
                  ),
                ),
              ),
            ),
            if (_payload.files.length > 1)
              Positioned(
                top: 4,
                left: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlatformBadge() {
    if (_payload.isYouTube) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFFF0000).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: const Color(0xFFFF334B).withValues(alpha: 0.4),
          ),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.play_circle_fill, color: Color(0xFFFF334B), size: 14),
            SizedBox(width: 5),
            Text(
              'YOUTUBE',
              style: TextStyle(
                color: Color(0xFFFF334B),
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      );
    }

    if (_payload.isXTwitter) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFF1DA1F2).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: const Color(0xFF1DA1F2).withValues(alpha: 0.4),
          ),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tag_rounded, color: Color(0xFF1DA1F2), size: 14),
            SizedBox(width: 5),
            Text(
              'X / TWITTER',
              style: TextStyle(
                color: Color(0xFF1DA1F2),
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      );
    }

    if (_payload.isWebLink) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFF00C853).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: const Color(0xFF00E676).withValues(alpha: 0.4),
          ),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.link_rounded, color: Color(0xFF00E676), size: 14),
            SizedBox(width: 5),
            Text(
              'WEB LINK',
              style: TextStyle(
                color: Color(0xFF00E676),
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF9D4EDD).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFF9D4EDD).withValues(alpha: 0.4),
        ),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.notes_rounded, color: Color(0xFFC77DFF), size: 14),
          SizedBox(width: 5),
          Text(
            'SHARED TEXT',
            style: TextStyle(
              color: Color(0xFFC77DFF),
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPayloadCountBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        style: const TextStyle(
          color: Color(0xFFFFD700),
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildTargetToggleBar() {
    final photoCount = _payload.files.length;
    final countLabel = '$photoCount photo${photoCount == 1 ? '' : 's'}';
    final galleryChip = _TargetChip(
      label: 'Gallery',
      icon: Icons.photo_library_rounded,
      selected: _target == _ShareTarget.gallery,
      color: const Color(0xFFFFD700),
      onTap: () => setState(() => _target = _ShareTarget.gallery),
    );
    final chatChip = _TargetChip(
      label: 'Chat',
      icon: Icons.chat_bubble_rounded,
      selected: _target == _ShareTarget.groupChat,
      color: const Color(0xFF9D4EDD),
      onTap: () => setState(() => _target = _ShareTarget.groupChat),
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF141122),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final textScale = MediaQuery.textScalerOf(context).scale(1.0);
          final fitsSingleRow = constraints.maxWidth >= (348 * textScale);

          if (fitsSingleRow) {
            return Row(
              children: [
                Text(
                  'Share Destination:',
                  style: TextStyle(color: Colors.grey[400], fontSize: 12),
                ),
                const SizedBox(width: 10),
                galleryChip,
                const SizedBox(width: 8),
                chatChip,
                const Spacer(),
                _buildPayloadCountBadge(countLabel),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Share Destination:',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildPayloadCountBadge(countLabel),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: galleryChip),
                  const SizedBox(width: 10),
                  Expanded(child: chatChip),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildModeInfoBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF141122),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Row(
        children: [
          Icon(
            _isDirectTab ? Icons.person_rounded : Icons.chat_rounded,
            size: 16,
            color: const Color(0xFFC77DFF),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _isDirectTab
                  ? 'Select a contact for direct message'
                  : 'Select a group to send message',
              style: TextStyle(color: Colors.grey[300], fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          _buildPayloadCountBadge(_payload.displayTitle),
        ],
      ),
    );
  }

  Widget _buildSelectedDestinationBanner() {
    if (_selectedContact != null) {
      final contact = _selectedContact!;
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: _submitColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _submitColor.withValues(alpha: 0.4),
            width: 1.2,
          ),
        ),
        child: Row(
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: _submitColor, width: 1.5),
              ),
              child: CircleAvatar(
                backgroundImage: contact.profilePic != null &&
                        contact.profilePic!.isNotEmpty
                    ? NetworkImage(contact.profilePic!)
                    : null,
                radius: 15,
                backgroundColor: const Color(0xFF1E1A2E),
                onBackgroundImageError: (contact.profilePic != null &&
                        contact.profilePic!.isNotEmpty)
                    ? (_, __) {}
                    : null,
                child: contact.profilePic == null || contact.profilePic!.isEmpty
                    ? const Icon(Icons.person, size: 14, color: Colors.white54)
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    contact.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Will be sent as chat message',
                    style: TextStyle(
                      color: Colors.grey[300],
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(
                Icons.close_rounded,
                size: 18,
                color: Colors.white70,
              ),
              onPressed: () => setState(() => _selectedContact = null),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      );
    }

    if (_selectedGroups.length == 1) {
      final group = _selectedGroups.values.first;
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: _submitColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _submitColor.withValues(alpha: 0.4),
            width: 1.2,
          ),
        ),
        child: Row(
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: _submitColor, width: 1.5),
              ),
              child: CircleAvatar(
                backgroundImage: group.groupPic.isNotEmpty
                    ? NetworkImage(group.groupPic)
                    : null,
                radius: 15,
                backgroundColor: const Color(0xFF1E1A2E),
                onBackgroundImageError:
                    group.groupPic.isNotEmpty ? (_, __) {} : null,
                child: group.groupPic.isEmpty
                    ? const Icon(Icons.group, size: 14, color: Colors.white54)
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  QueendomEmblemHelper.buildRichTitle(
                    title: group.nameWithPosition,
                    family: group.family,
                    fallbackFamily: 'Main',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    _target == _ShareTarget.gallery
                        ? 'Will be uploaded to gallery'
                        : 'Will be sent as chat message',
                    style: TextStyle(
                      color: Colors.grey[300],
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(
                Icons.close_rounded,
                size: 18,
                color: Colors.white70,
              ),
              onPressed: () => setState(() => _selectedGroups.clear()),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      );
    }

    // Multiple groups selected
    final numGroups = _selectedGroups.length;
    final groupsList = _selectedGroups.values.toList();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: _submitColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _submitColor.withValues(alpha: 0.4),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _submitColor.withValues(alpha: 0.2),
                  border: Border.all(color: _submitColor, width: 1.5),
                ),
                child: Icon(
                  Icons.groups_rounded,
                  size: 18,
                  color: _submitColor,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$numGroups Groups Selected',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      _target == _ShareTarget.gallery
                          ? 'Will be uploaded to $numGroups galleries'
                          : 'Will be sent to $numGroups group chats',
                      style: TextStyle(
                        color: Colors.grey[300],
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _selectedGroups.clear()),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Clear all',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 28,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: groupsList.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final g = groupsList[index];
                return GestureDetector(
                  key: ValueKey('chip_${g.groupId}'),
                  onTap: () => setState(() => _selectedGroups.remove(g.groupId)),
                  child: Container(
                    padding: const EdgeInsets.only(left: 4, right: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _submitColor.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 9,
                          backgroundImage: g.groupPic.isNotEmpty
                              ? NetworkImage(g.groupPic)
                              : null,
                          backgroundColor: const Color(0xFF1E1A2E),
                          child: g.groupPic.isEmpty
                              ? const Icon(Icons.group, size: 10, color: Colors.white54)
                              : null,
                        ),
                        const SizedBox(width: 4),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 190),
                          child: Text(
                            g.nameWithPosition.isNotEmpty
                                ? g.nameWithPosition
                                : g.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 2),
                        const Icon(
                          Icons.close,
                          size: 14,
                          color: Colors.white70,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared search bar ─────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final String query;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _SearchBar({
    required this.controller,
    required this.query,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.transparent,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Search groups, families or contacts...',
          hintStyle: TextStyle(color: Colors.grey[500], fontSize: 13),
          prefixIcon: Icon(Icons.search_rounded, color: Colors.grey[400], size: 20),
          suffixIcon: query.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear_rounded, color: Colors.grey[400], size: 18),
                  onPressed: onClear,
                )
              : null,
          filled: true,
          fillColor: const Color(0xFF141122),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 10,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFFFD700), width: 1.2),
          ),
        ),
      ),
    );
  }
}

// ── Group List ────────────────────────────────────────────────────────────────

class _GroupList extends StatefulWidget {
  final Stream<List<GroupModel>> stream;
  final Set<String> selectedGroupIds;
  final String searchQuery;
  final ValueChanged<GroupModel> onToggleGroup;
  final String emptyLabel;

  const _GroupList({
    required this.stream,
    required this.selectedGroupIds,
    required this.searchQuery,
    required this.onToggleGroup,
    required this.emptyLabel,
  });

  @override
  State<_GroupList> createState() => _GroupListState();
}

class _GroupListState extends State<_GroupList>
    with AutomaticKeepAliveClientMixin<_GroupList> {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final query = widget.searchQuery;
    return StreamBuilder<List<GroupModel>>(
      stream: widget.stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const ContactListSkeleton(isGroup: true);
        }

        final all = snapshot.data ?? [];
        final groups = query.isEmpty
            ? all
            : all
                .where(
                  (g) =>
                      g.nameWithPosition.toLowerCase().contains(
                            query.toLowerCase(),
                          ) ||
                      g.name.toLowerCase().contains(
                            query.toLowerCase(),
                          ) ||
                      (g.family ?? '').toLowerCase().contains(
                            query.toLowerCase(),
                          ) ||
                      (g.position ?? '').toLowerCase().contains(
                            query.toLowerCase(),
                          ),
                )
                .toList();

        if (all.isEmpty) {
          return Center(
            child: Text(widget.emptyLabel, style: TextStyle(color: Colors.grey[500])),
          );
        }

        if (groups.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.search_off_rounded, size: 40, color: Colors.grey[700]),
                const SizedBox(height: 12),
                Text(
                  'No results for "$query"',
                  style: TextStyle(color: Colors.grey[400], fontSize: 14),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          itemCount: groups.length,
          separatorBuilder: (_, __) => Divider(
            color: Colors.white.withValues(alpha: 0.05),
            height: 1,
          ),
          itemBuilder: (context, index) {
            final group = groups[index];
            final isSelected = widget.selectedGroupIds.contains(group.groupId);

            return InkWell(
              key: ValueKey('group_tile_${group.groupId}'),
              onTap: () => widget.onToggleGroup(group),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 2),
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFFFFD700).withValues(alpha: 0.08)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFFFFD700).withValues(alpha: 0.5)
                        : Colors.transparent,
                    width: 1.2,
                  ),
                ),
                child: Row(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFFFFD700)
                                  : Colors.white.withValues(alpha: 0.15),
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: CircleAvatar(
                            backgroundImage: group.groupPic.isNotEmpty
                                ? NetworkImage(group.groupPic)
                                : null,
                            radius: 22,
                            backgroundColor: const Color(0xFF1E1A2E),
                            onBackgroundImageError:
                                group.groupPic.isNotEmpty ? (_, __) {} : null,
                            child: group.groupPic.isEmpty
                                ? const Icon(Icons.group, color: Colors.white54)
                                : null,
                          ),
                        ),
                        if (group.position != null &&
                            group.position!.isNotEmpty &&
                            group.position != 'None')
                          Positioned(
                            bottom: -2,
                            right: -2,
                            child: QueendomEmblemWidget(
                              position: group.position,
                              size: 16,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: query.isEmpty
                                    ? QueendomEmblemHelper.buildRichTitle(
                                        title: group.nameWithPosition,
                                        family: group.family,
                                        fallbackFamily: 'Main',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      )
                                    : _HighlightedText(
                                        text: group.nameWithPosition,
                                        query: query,
                                      ),
                              ),
                              if (group.position != null &&
                                  group.position!.isNotEmpty &&
                                  group.position != 'None' &&
                                  !group.nameWithPosition.toLowerCase().contains(group.position!.toLowerCase())) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF281E40),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: const Color(0xFF5D438A),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Text(
                                    group.position!,
                                    style: const TextStyle(
                                      color: Color(0xFFFFD700),
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              if (group.family != null &&
                                  group.family!.isNotEmpty &&
                                  group.family != 'None') ...[
                                Text(
                                  '${group.family} Family',
                                  style: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 11,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '•',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 11,
                                  ),
                                ),
                                const SizedBox(width: 6),
                              ],
                              Text(
                                '${group.membersUid.length} members',
                                style: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    isSelected
                        ? const Icon(
                            Icons.check_circle_rounded,
                            color: Color(0xFFFFD700),
                            size: 22,
                          )
                        : Icon(
                            Icons.circle_outlined,
                            color: Colors.grey[700],
                            size: 22,
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
}

// ── Contact List ──────────────────────────────────────────────────────────────

class _ContactList extends StatefulWidget {
  final Stream<List<ChatContact>> stream;
  final ChatContact? selectedContact;
  final String searchQuery;
  final ValueChanged<ChatContact> onSelect;
  final String emptyLabel;

  const _ContactList({
    required this.stream,
    required this.selectedContact,
    required this.searchQuery,
    required this.onSelect,
    required this.emptyLabel,
  });

  @override
  State<_ContactList> createState() => _ContactListState();
}

class _ContactListState extends State<_ContactList>
    with AutomaticKeepAliveClientMixin<_ContactList> {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final query = widget.searchQuery;
    return StreamBuilder<List<ChatContact>>(
      stream: widget.stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const ContactListSkeleton();
        }

        final all = snapshot.data ?? [];
        final contacts = query.isEmpty
            ? all
            : all
                .where(
                  (c) => c.name.toLowerCase().contains(
                        query.toLowerCase(),
                      ),
                )
                .toList();

        if (all.isEmpty) {
          return Center(
            child: Text(widget.emptyLabel, style: TextStyle(color: Colors.grey[500])),
          );
        }

        if (contacts.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.search_off_rounded, size: 40, color: Colors.grey[700]),
                const SizedBox(height: 12),
                Text(
                  'No results for "$query"',
                  style: TextStyle(color: Colors.grey[400], fontSize: 14),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          itemCount: contacts.length,
          separatorBuilder: (_, __) => Divider(
            color: Colors.white.withValues(alpha: 0.05),
            height: 1,
          ),
          itemBuilder: (context, index) {
            final contact = contacts[index];
            final isSelected = widget.selectedContact?.uid == contact.uid;

            return InkWell(
              onTap: () => widget.onSelect(contact),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 2),
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF9D4EDD).withValues(alpha: 0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFFC77DFF).withValues(alpha: 0.6)
                        : Colors.transparent,
                    width: 1.2,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFFC77DFF)
                              : Colors.white.withValues(alpha: 0.15),
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: CircleAvatar(
                        backgroundImage: contact.profilePic != null &&
                                contact.profilePic!.isNotEmpty
                            ? NetworkImage(contact.profilePic!)
                            : null,
                        radius: 22,
                        backgroundColor: const Color(0xFF1E1A2E),
                        onBackgroundImageError: (contact.profilePic != null &&
                                contact.profilePic!.isNotEmpty)
                            ? (_, __) {}
                            : null,
                        child: contact.profilePic == null ||
                                contact.profilePic!.isEmpty
                            ? const Icon(Icons.person, color: Colors.white54)
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _HighlightedText(
                            text: contact.name,
                            query: query,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            (contact.lastMessage != null &&
                                    contact.lastMessage!.isNotEmpty)
                                ? contact.lastMessage!
                                : 'Tap to select contact',
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    isSelected
                        ? const Icon(
                            Icons.check_circle_rounded,
                            color: Color(0xFFC77DFF),
                            size: 22,
                          )
                        : Icon(
                            Icons.radio_button_unchecked_rounded,
                            color: Colors.grey[700],
                            size: 22,
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
}

// ── Highlighted Search Text ───────────────────────────────────────────────────

class _HighlightedText extends StatelessWidget {
  final String text;
  final String query;

  const _HighlightedText({
    required this.text,
    required this.query,
  });

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      color: Colors.white,
      fontSize: 14,
      fontWeight: FontWeight.w600,
    );

    if (query.isEmpty) return Text(text, style: style);

    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final index = lowerText.indexOf(lowerQuery);

    if (index == -1) return Text(text, style: style);

    return RichText(
      text: TextSpan(
        children: [
          TextSpan(text: text.substring(0, index), style: style),
          TextSpan(
            text: text.substring(index, index + query.length),
            style: style.copyWith(
              color: const Color(0xFFFFD700),
              fontWeight: FontWeight.bold,
              backgroundColor: const Color(0xFFFFD700).withValues(alpha: 0.2),
            ),
          ),
          TextSpan(text: text.substring(index + query.length), style: style),
        ],
      ),
    );
  }
}

// ── Target Chip ───────────────────────────────────────────────────────────────

class _TargetChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _TargetChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? color : Colors.white.withValues(alpha: 0.1),
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: selected ? color : Colors.grey[400]),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? color : Colors.grey[400],
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
