import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/utils/share_intent_service.dart';
import 'package:worship_chat/common/widgets/loader.dart';
import 'package:worship_chat/features/auth/controller/auth_controller.dart';
import 'package:worship_chat/features/chat/controller/chat_controller.dart';
import 'package:worship_chat/features/group/controller/group_controller.dart';
import 'package:worship_chat/features/group/controller/group_gallery_controller.dart';
import 'package:worship_chat/models/chat_contact.dart';
import 'package:worship_chat/models/group.dart';

enum _ShareTarget { gallery, groupChat, directChat }

// ── Unified selection: either a group or a 1-to-1 contact ────────────────────

class _Selection {
  final GroupModel? group;
  final ChatContact? contact;

  const _Selection.group(GroupModel g) : group = g, contact = null;
  const _Selection.contact(ChatContact c) : contact = c, group = null;

  bool get isGroup => group != null;
  String get name => group?.name ?? contact?.name ?? '';
  String get pic => group?.groupPic ?? contact?.profilePic ?? '';
  String get id => group?.groupId ?? contact?.uid ?? '';
}

class ShareUploadScreen extends ConsumerStatefulWidget {
  final List<File> files;
  const ShareUploadScreen({super.key, required this.files});

  @override
  ConsumerState<ShareUploadScreen> createState() => _ShareUploadScreenState();
}

class _ShareUploadScreenState extends ConsumerState<ShareUploadScreen>
    with SingleTickerProviderStateMixin {
  _Selection? _selection;
  _ShareTarget _target = _ShareTarget.gallery;
  bool _isUploading = false;
  int _uploaded = 0;
  late TabController _tabController;

  // Tab indices: 0 = My Groups, 1 = Queen Pooja, 2 = Queen Rashmika, 3 = Direct
  static const int _kDirectTabIndex = 3;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      setState(() {
        if (_tabController.index == _kDirectTabIndex) {
          _target = _ShareTarget.directChat;
        } else {
          if (_target == _ShareTarget.directChat) {
            _target = _ShareTarget.gallery;
          }
        }
        _selection = null;
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _selectGroup(GroupModel group) {
    setState(() {
      _selection = _Selection.group(group);
      if (_target == _ShareTarget.directChat) _target = _ShareTarget.gallery;
    });
  }

  void _selectContact(ChatContact contact) {
    setState(() {
      _selection = _Selection.contact(contact);
      _target = _ShareTarget.directChat;
    });
  }

  String _groupType(GroupModel group) {
    if (group.queendom == 'Queen Pooja') return 'queenPooja';
    if (group.queendom == 'Queen Rashmika') return 'queenRashmika';
    return 'group';
  }

  // ── Upload to gallery ─────────────────────────────────────────────────────

  Future<void> _uploadToGallery() async {
    final group = _selection?.group;
    if (group == null) return;
    final userData = await ref.read(userDataAuthProvider.future);
    if (userData == null) return;

    setState(() {
      _isUploading = true;
      _uploaded = 0;
    });

    final count = await ref
        .read(groupGalleryControllerProvider)
        .uploadImages(
          groupId: group.groupId,
          imageFiles: widget.files,
          uploaderName: userData.name ?? 'Unknown',
          caption: null,
          onProgress: (uploaded, _) => setState(() => _uploaded = uploaded),
        );

    if (mounted) {
      ref.read(sharedFilesProvider.notifier).clear();
      _snack(
        count > 0
            ? '✅ $count photo${count == 1 ? '' : 's'} added to ${group.name} gallery'
            : '⚠️ Upload failed',
        count > 0,
      );
      Navigator.pop(context);
    }
  }

  // ── Send to group chat ────────────────────────────────────────────────────

  Future<void> _sendToGroupChat() async {
    final group = _selection?.group;
    if (group == null) return;
    final userData = await ref.read(userDataAuthProvider.future);
    if (userData == null) return;

    setState(() {
      _isUploading = true;
      _uploaded = 0;
    });

    final receiverIds = group.membersUid
        .where((uid) => uid != userData.uid)
        .toList();

    for (int i = 0; i < widget.files.length; i++) {
      await ref
          .read(groupControllerProvider)
          .sendTextMessage(
            context,
            '',
            group.groupId,
            'image',
            widget.files[i],
            List<String>.from(group.fcmTokens ?? []),
            receiverIds,
            group.name,
            _groupType(group),
          );
      if (mounted) setState(() => _uploaded = i + 1);
    }

    if (mounted) {
      ref.read(sharedFilesProvider.notifier).clear();
      _snack(
        '✅ ${widget.files.length} photo${widget.files.length == 1 ? '' : 's'} sent to ${group.name}',
        true,
      );
      Navigator.pop(context);
    }
  }

  // ── Send to 1-to-1 chat ───────────────────────────────────────────────────

  Future<void> _sendToDirectChat() async {
    final contact = _selection?.contact;
    if (contact == null) return;
    final userData = await ref.read(userDataAuthProvider.future);
    if (userData == null) return;

    setState(() {
      _isUploading = true;
      _uploaded = 0;
    });

    for (int i = 0; i < widget.files.length; i++) {
      await ref
          .read(chatControllerProvider)
          .sendTextMessage(
            context,
            '',
            contact.uid,
            'image',
            widget.files[i],
            contact.fcmToken ?? '',
            null,
            null,
            'others',
          );
      if (mounted) setState(() => _uploaded = i + 1);
    }

    if (mounted) {
      ref.read(sharedFilesProvider.notifier).clear();
      _snack(
        '✅ ${widget.files.length} photo${widget.files.length == 1 ? '' : 's'} sent to ${contact.name}',
        true,
      );
      Navigator.pop(context);
    }
  }

  Future<void> _submit() async {
    switch (_target) {
      case _ShareTarget.gallery:
        await _uploadToGallery();
        break;
      case _ShareTarget.groupChat:
        await _sendToGroupChat();
        break;
      case _ShareTarget.directChat:
        await _sendToDirectChat();
        break;
    }
  }

  void _snack(String msg, bool success) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: success ? Colors.green[700] : Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── Derived helpers ───────────────────────────────────────────────────────

  bool get _isDirectTab => _tabController.index == _kDirectTabIndex;

  String get _submitLabel {
    if (_isUploading) {
      final verb = _target == _ShareTarget.gallery ? 'Uploading' : 'Sending';
      return '$verb $_uploaded / ${widget.files.length}...';
    }
    if (_selection == null) return 'Select a destination first';
    final count = widget.files.length;
    final plural = count == 1 ? '' : 's';
    switch (_target) {
      case _ShareTarget.gallery:
        return 'Upload $count photo$plural to Gallery';
      case _ShareTarget.groupChat:
        return 'Send $count photo$plural to Chat';
      case _ShareTarget.directChat:
        return 'Send $count photo$plural to ${_selection!.name}';
    }
  }

  Color get _submitColor {
    switch (_target) {
      case _ShareTarget.gallery:
        return tabColor;
      case _ShareTarget.groupChat:
        return Colors.blueAccent;
      case _ShareTarget.directChat:
        return Colors.purpleAccent;
    }
  }

  IconData get _submitIcon {
    switch (_target) {
      case _ShareTarget.gallery:
        return Icons.cloud_upload_outlined;
      case _ShareTarget.groupChat:
      case _ShareTarget.directChat:
        return Icons.send;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Key fix: read keyboard height via viewInsets
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      // resizeToAvoidBottomInset: false lets us manually control layout
      // so the button stays anchored and the list shrinks properly
      resizeToAvoidBottomInset: false,
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: appBarColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            ref.read(sharedFilesProvider.notifier).clear();
            Navigator.pop(context);
          },
        ),
        title: const Text(
          'Share to Worship Chat',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: tabColor,
          labelColor: tabColor,
          unselectedLabelColor: Colors.grey,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'My Groups'),
            Tab(text: 'Queen Pooja'),
            Tab(text: 'Queen Rashmika'),
            Tab(text: 'Direct'),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── Image previews ──────────────────────────────────────────
            Container(
              height: 100,
              color: Colors.black,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(10),
                itemCount: widget.files.length,
                itemBuilder: (_, i) => Stack(
                  children: [
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(
                          widget.files[i],
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    if (widget.files.length > 1)
                      Positioned(
                        top: 4,
                        left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // ── Share target toggle (hidden on Direct tab) ──────────────
            if (!_isDirectTab)
              Container(
                color: Colors.grey[900],
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Text(
                      'Share to:',
                      style: TextStyle(color: Colors.grey[400], fontSize: 13),
                    ),
                    const SizedBox(width: 12),
                    _TargetChip(
                      label: 'Gallery',
                      icon: Icons.photo_library_outlined,
                      selected: _target == _ShareTarget.gallery,
                      color: tabColor,
                      onTap: () =>
                          setState(() => _target = _ShareTarget.gallery),
                    ),
                    const SizedBox(width: 8),
                    _TargetChip(
                      label: 'Chat',
                      icon: Icons.chat_bubble_outline,
                      selected: _target == _ShareTarget.groupChat,
                      color: Colors.blueAccent,
                      onTap: () =>
                          setState(() => _target = _ShareTarget.groupChat),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey[800],
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${widget.files.length} photo${widget.files.length == 1 ? '' : 's'}',
                        style: TextStyle(color: Colors.grey[400], fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),

            // ── Direct tab header strip ─────────────────────────────────
            if (_isDirectTab)
              Container(
                color: Colors.grey[900],
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.person_outline,
                      size: 15,
                      color: Colors.purpleAccent,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Send directly to a person',
                      style: TextStyle(color: Colors.grey[400], fontSize: 13),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey[800],
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${widget.files.length} photo${widget.files.length == 1 ? '' : 's'}',
                        style: TextStyle(color: Colors.grey[400], fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),

            // ── Selected destination strip ──────────────────────────────
            if (_selection != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                color: _submitColor.withOpacity(0.1),
                child: Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: _submitColor, width: 1.5),
                      ),
                      child: CircleAvatar(
                        backgroundImage: NetworkImage(_selection!.pic),
                        radius: 14,
                        backgroundColor: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selection!.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            _target == _ShareTarget.gallery
                                ? 'Will be uploaded to gallery'
                                : _target == _ShareTarget.directChat
                                ? 'Will be sent as direct message${widget.files.length > 1 ? 's' : ''}'
                                : 'Will be sent as chat message${widget.files.length > 1 ? 's' : ''}',
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close,
                        size: 16,
                        color: Colors.grey,
                      ),
                      onPressed: () => setState(() => _selection = null),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),

            // ── Tab content — Expanded so it takes remaining space ──────
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // My Groups
                  _SearchableGroupTab(
                    stream: ref.watch(groupControllerProvider).chatGroups(),
                    selectedGroup: _selection?.group,
                    onSelect: _selectGroup,
                    emptyLabel: 'No groups available',
                  ),
                  // Queen Pooja
                  _SearchableGroupTab(
                    stream: ref
                        .watch(groupControllerProvider)
                        .getQueenPoojaStream(),
                    selectedGroup: _selection?.group,
                    onSelect: _selectGroup,
                    emptyLabel: 'No Queen Pooja groups',
                  ),
                  // Queen Rashmika
                  _SearchableGroupTab(
                    stream: ref
                        .watch(groupControllerProvider)
                        .getQueenRashmikaStream(),
                    selectedGroup: _selection?.group,
                    onSelect: _selectGroup,
                    emptyLabel: 'No Queen Rashmika groups',
                  ),
                  // Direct Messages
                  _SearchableContactTab(
                    stream: ref.watch(chatControllerProvider).chatContacts(),
                    selectedContact: _selection?.contact,
                    onSelect: _selectContact,
                    emptyLabel: 'No conversations yet',
                  ),
                ],
              ),
            ),

            // ── Upload progress bar ─────────────────────────────────────
            if (_isUploading)
              LinearProgressIndicator(
                value: widget.files.isNotEmpty
                    ? _uploaded / widget.files.length
                    : null,
                backgroundColor: Colors.grey[800],
                valueColor: AlwaysStoppedAnimation<Color>(_submitColor),
                minHeight: 3,
              ),

            // ── Submit button — animates up with keyboard ───────────────
            AnimatedPadding(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                keyboardHeight > 0 ? keyboardHeight + 8 : 24,
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _selection == null || _isUploading
                      ? null
                      : _submit,
                  icon: _isUploading
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                            value: widget.files.isNotEmpty
                                ? _uploaded / widget.files.length
                                : null,
                          ),
                        )
                      : Icon(_submitIcon),
                  label: Text(_submitLabel),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _submitColor,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey[800],
                    disabledForegroundColor: Colors.grey[500],
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Per-tab group search wrapper ──────────────────────────────────────────────

class _SearchableGroupTab extends StatefulWidget {
  final Stream<List<GroupModel>> stream;
  final GroupModel? selectedGroup;
  final ValueChanged<GroupModel> onSelect;
  final String emptyLabel;

  const _SearchableGroupTab({
    required this.stream,
    required this.selectedGroup,
    required this.onSelect,
    required this.emptyLabel,
  });

  @override
  State<_SearchableGroupTab> createState() => _SearchableGroupTabState();
}

class _SearchableGroupTabState extends State<_SearchableGroupTab>
    with AutomaticKeepAliveClientMixin<_SearchableGroupTab> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        _SearchBar(
          controller: _searchController,
          query: _searchQuery,
          onChanged: (val) => setState(() => _searchQuery = val.trim()),
          onClear: () {
            _searchController.clear();
            setState(() => _searchQuery = '');
          },
        ),
        Expanded(
          child: _GroupList(
            stream: widget.stream,
            selectedGroup: widget.selectedGroup,
            searchQuery: _searchQuery,
            onSelect: widget.onSelect,
            emptyLabel: widget.emptyLabel,
          ),
        ),
      ],
    );
  }
}

// ── Per-tab contact search wrapper ────────────────────────────────────────────

class _SearchableContactTab extends StatefulWidget {
  final Stream<List<ChatContact>> stream;
  final ChatContact? selectedContact;
  final ValueChanged<ChatContact> onSelect;
  final String emptyLabel;

  const _SearchableContactTab({
    required this.stream,
    required this.selectedContact,
    required this.onSelect,
    required this.emptyLabel,
  });

  @override
  State<_SearchableContactTab> createState() => _SearchableContactTabState();
}

class _SearchableContactTabState extends State<_SearchableContactTab>
    with AutomaticKeepAliveClientMixin<_SearchableContactTab> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        _SearchBar(
          controller: _searchController,
          query: _searchQuery,
          onChanged: (val) => setState(() => _searchQuery = val.trim()),
          onClear: () {
            _searchController.clear();
            setState(() => _searchQuery = '');
          },
        ),
        Expanded(
          child: _ContactList(
            stream: widget.stream,
            selectedContact: widget.selectedContact,
            searchQuery: _searchQuery,
            onSelect: widget.onSelect,
            emptyLabel: widget.emptyLabel,
          ),
        ),
      ],
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
      color: Colors.grey[900],
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Search...',
          hintStyle: TextStyle(color: Colors.grey[500], fontSize: 14),
          prefixIcon: Icon(Icons.search, color: Colors.grey[500], size: 20),
          suffixIcon: query.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear, color: Colors.grey[500], size: 18),
                  onPressed: onClear,
                )
              : null,
          filled: true,
          fillColor: Colors.grey[850],
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 10,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

// ── Group list ────────────────────────────────────────────────────────────────

class _GroupList extends StatelessWidget {
  final Stream<List<GroupModel>> stream;
  final GroupModel? selectedGroup;
  final String searchQuery;
  final ValueChanged<GroupModel> onSelect;
  final String emptyLabel;

  const _GroupList({
    required this.stream,
    required this.selectedGroup,
    required this.searchQuery,
    required this.onSelect,
    required this.emptyLabel,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<GroupModel>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Loader();
        }

        final all = snapshot.data ?? [];
        final groups = searchQuery.isEmpty
            ? all
            : all
                  .where(
                    (g) =>
                        g.name.toLowerCase().contains(
                          searchQuery.toLowerCase(),
                        ) ||
                        (g.family ?? '').toLowerCase().contains(
                          searchQuery.toLowerCase(),
                        ),
                  )
                  .toList();

        if (all.isEmpty) {
          return Center(
            child: Text(emptyLabel, style: TextStyle(color: Colors.grey[500])),
          );
        }

        if (groups.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.search_off, size: 40, color: Colors.grey[700]),
                const SizedBox(height: 12),
                Text(
                  'No results for "$searchQuery"',
                  style: TextStyle(color: Colors.grey[500], fontSize: 14),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          // ── FIX: dismiss keyboard when user scrolls the list ──
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: groups.length,
          separatorBuilder: (_, __) =>
              Divider(color: Colors.grey[800], height: 1),
          itemBuilder: (context, index) {
            final group = groups[index];
            final isSelected = selectedGroup?.groupId == group.groupId;

            return ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 6,
              ),
              leading: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? tabColor : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: CircleAvatar(
                  backgroundImage: NetworkImage(group.groupPic),
                  radius: 24,
                  backgroundColor: Colors.grey[800],
                ),
              ),
              title: _HighlightedText(text: group.name, query: searchQuery),
              subtitle:
                  group.family != null &&
                      group.family!.isNotEmpty &&
                      group.family != 'None'
                  ? _HighlightedText(
                      text: '${group.family} Family',
                      query: searchQuery,
                      baseStyle: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 11,
                      ),
                    )
                  : Text(
                      '${group.membersUid.length} members',
                      style: TextStyle(color: Colors.grey[500], fontSize: 11),
                    ),
              trailing: isSelected
                  ? Icon(Icons.check_circle, color: tabColor)
                  : Icon(Icons.radio_button_unchecked, color: Colors.grey[600]),
              onTap: () => onSelect(group),
            );
          },
        );
      },
    );
  }
}

// ── Contact list ──────────────────────────────────────────────────────────────

class _ContactList extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return StreamBuilder<List<ChatContact>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Loader();
        }

        final all = snapshot.data ?? [];
        final contacts = searchQuery.isEmpty
            ? all
            : all
                  .where(
                    (c) => c.name.toLowerCase().contains(
                      searchQuery.toLowerCase(),
                    ),
                  )
                  .toList();

        if (all.isEmpty) {
          return Center(
            child: Text(emptyLabel, style: TextStyle(color: Colors.grey[500])),
          );
        }

        if (contacts.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.search_off, size: 40, color: Colors.grey[700]),
                const SizedBox(height: 12),
                Text(
                  'No results for "$searchQuery"',
                  style: TextStyle(color: Colors.grey[500], fontSize: 14),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          // ── FIX: dismiss keyboard when user scrolls the list ──
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: contacts.length,
          separatorBuilder: (_, __) =>
              Divider(color: Colors.grey[800], height: 1),
          itemBuilder: (context, index) {
            final contact = contacts[index];
            final isSelected = selectedContact?.uid == contact.uid;

            return ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 6,
              ),
              leading: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? Colors.purpleAccent
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: CircleAvatar(
                  backgroundImage:
                      contact.profilePic != null &&
                          contact.profilePic!.isNotEmpty
                      ? NetworkImage(contact.profilePic!)
                      : null,
                  radius: 24,
                  backgroundColor: Colors.grey[800],
                  child:
                      contact.profilePic == null || contact.profilePic!.isEmpty
                      ? Text(
                          contact.name.isNotEmpty
                              ? contact.name[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
                ),
              ),
              title: _HighlightedText(text: contact.name, query: searchQuery),
              subtitle: Text(
                contact.lastMessage != null && contact.lastMessage!.isNotEmpty
                    ? contact.lastMessage!
                    : 'No messages yet',
                style: TextStyle(color: Colors.grey[500], fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
              trailing: isSelected
                  ? const Icon(Icons.check_circle, color: Colors.purpleAccent)
                  : Icon(Icons.radio_button_unchecked, color: Colors.grey[600]),
              onTap: () => onSelect(contact),
            );
          },
        );
      },
    );
  }
}

// ── Highlighted search text ───────────────────────────────────────────────────

class _HighlightedText extends StatelessWidget {
  final String text;
  final String query;
  final TextStyle? baseStyle;

  const _HighlightedText({
    required this.text,
    required this.query,
    this.baseStyle,
  });

  @override
  Widget build(BuildContext context) {
    final style =
        baseStyle ??
        const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
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
              color: tabColor,
              fontWeight: FontWeight.bold,
              backgroundColor: tabColor.withOpacity(0.15),
            ),
          ),
          TextSpan(text: text.substring(index + query.length), style: style),
        ],
      ),
    );
  }
}

// ── Target chip ───────────────────────────────────────────────────────────────

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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.15) : Colors.grey[800],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : Colors.grey[700]!,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: selected ? color : Colors.grey),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected ? color : Colors.grey,
                fontSize: 13,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
