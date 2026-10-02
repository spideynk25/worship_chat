import 'dart:developer';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:worship_chat/features/group/controller/group_controller.dart';
import 'package:worship_chat/features/group/screens/group_chat_screen.dart';
import 'package:worship_chat/models/group.dart';

/// Helper to navigate directly to a Queendom group chat
Future<void> navigateToQueendomGroup(
  BuildContext context, {
  required String groupId,
  required String name,
  String? groupPic,
  String? queendom,
  String? wish,
}) async {
  HapticFeedback.selectionClick();

  String type = "others";
  Color? accentColor;
  if (queendom == 'Queen Pooja') {
    type = "queenPooja";
    accentColor = const Color(0xFFFFD700);
  } else if (queendom == 'Queen Rashmika') {
    type = "queenRashmika";
    accentColor = const Color(0xFFFF4081);
  }

  // Try fetching complete group model from Firestore
  try {
    final doc = await FirebaseFirestore.instance
        .collection('groups')
        .doc(groupId)
        .get();
    if (doc.exists && doc.data() != null && context.mounted) {
      final group = GroupModel.fromMap(doc.data()!);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => GroupChatScreen(
            groupPic: group.groupPic,
            chatBackgroundUrl: group.chatBackgroundUrl,
            name: group.name,
            groupId: group.groupId,
            fcmToken: List<String>.from(group.fcmTokens),
            membersUid: List<String>.from(group.membersUid),
            wish: group.wish,
            queendom: group.queendom,
            color: accentColor,
            type: type,
          ),
        ),
      );
      return;
    }
  } catch (e) {
    log('Error fetching group details: $e');
  }

  // Fallback if fetch fails
  if (context.mounted) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GroupChatScreen(
          groupPic: groupPic,
          chatBackgroundUrl: null,
          name: name,
          groupId: groupId,
          fcmToken: const [],
          membersUid: const [],
          wish: wish,
          queendom: queendom,
          color: accentColor,
          type: type,
        ),
      ),
    );
  }
}

/// Opens an interactive modal to pick ONLY Queen Pooja or Queen Rashmika groups
Future<GroupModel?> showQueendomGroupPicker(
  BuildContext context, {
  required WidgetRef ref,
  String? currentSelectedGroupId,
}) async {
  HapticFeedback.lightImpact();
  final groupCtrl = ref.read(groupControllerProvider);
  final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

  // Cached groups
  final cachedPooja = groupCtrl.getCachedGroups('groups_pooja_$currentUserId');
  final cachedRashmika =
      groupCtrl.getCachedGroups('groups_rashmika_$currentUserId');

  return showModalBottomSheet<GroupModel?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return _QueendomGroupPickerSheet(
        groupCtrl: groupCtrl,
        cachedPooja: cachedPooja,
        cachedRashmika: cachedRashmika,
        currentSelectedGroupId: currentSelectedGroupId,
      );
    },
  );
}

class _QueendomGroupPickerSheet extends StatefulWidget {
  final GroupController groupCtrl;
  final List<GroupModel> cachedPooja;
  final List<GroupModel> cachedRashmika;
  final String? currentSelectedGroupId;

  const _QueendomGroupPickerSheet({
    required this.groupCtrl,
    required this.cachedPooja,
    required this.cachedRashmika,
    this.currentSelectedGroupId,
  });

  @override
  State<_QueendomGroupPickerSheet> createState() =>
      _QueendomGroupPickerSheetState();
}

class _QueendomGroupPickerSheetState extends State<_QueendomGroupPickerSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);

    return Container(
      height: mediaQuery.size.height * 0.75,
      decoration: const BoxDecoration(
        color: Color(0xFF161324),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFD700), Color(0xFFFF4081)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text('👑', style: TextStyle(fontSize: 18)),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Connect to Queendom Group',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Only Queen Pooja & Queen Rashmika groups',
                        style: TextStyle(fontSize: 11.5, color: Colors.white54),
                      ),
                    ],
                  ),
                ),
                // Disconnect / Clear button
                if (widget.currentSelectedGroupId != null)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: () {
                      Navigator.pop(context, null); // Return null to disconnect
                    },
                    icon: const Icon(Icons.link_off, size: 16),
                    label: const Text('Clear', style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ),

          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Container(
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFF201B34),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: TextField(
                style: const TextStyle(color: Colors.white, fontSize: 13.5),
                onChanged: (val) => setState(() => _searchQuery = val.trim()),
                decoration: const InputDecoration(
                  hintText: 'Search Queendom group...',
                  hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                  prefixIcon: Icon(Icons.search, color: Colors.white38, size: 18),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),

          // Tab Bar (Pooja vs Rashmika)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF201B34),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: LinearGradient(
                  colors: _tabController.index == 0
                      ? const [Color(0xFFFFD700), Color(0xFFFF9E00)]
                      : const [Color(0xFFFF4081), Color(0xFFFF007A)],
                ),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelColor: Colors.black,
              unselectedLabelColor: Colors.white70,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
              onTap: (_) => setState(() {}),
              tabs: const [
                Tab(text: '👑 Queen Pooja'),
                Tab(text: '👑 Queen Rashmika'),
              ],
            ),
          ),

          // Tab Views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildGroupList(
                  stream: widget.groupCtrl.getQueenPoojaStream(),
                  cached: widget.cachedPooja,
                  queendomName: 'Queen Pooja',
                  accentColor: const Color(0xFFFFD700),
                ),
                _buildGroupList(
                  stream: widget.groupCtrl.getQueenRashmikaStream(),
                  cached: widget.cachedRashmika,
                  queendomName: 'Queen Rashmika',
                  accentColor: const Color(0xFFFF4081),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupList({
    required Stream<List<GroupModel>> stream,
    required List<GroupModel> cached,
    required String queendomName,
    required Color accentColor,
  }) {
    return StreamBuilder<List<GroupModel>>(
      initialData: cached.isNotEmpty ? cached : null,
      stream: stream,
      builder: (context, snapshot) {
        final groups = (snapshot.data ?? cached)
            .where((g) =>
                g.queendom == queendomName &&
                (_searchQuery.isEmpty ||
                    g.name.toLowerCase().contains(_searchQuery.toLowerCase())))
            .toList();

        if (groups.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.group_outlined, size: 40, color: Colors.white24),
                const SizedBox(height: 8),
                Text(
                  _searchQuery.isEmpty
                      ? 'No $queendomName groups found'
                      : 'No groups match "$_searchQuery"',
                  style: const TextStyle(color: Colors.white38, fontSize: 13),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: groups.length,
          separatorBuilder: (_, __) =>
              Divider(color: Colors.white.withValues(alpha: 0.05), height: 1),
          itemBuilder: (context, index) {
            final group = groups[index];
            final isSelected = widget.currentSelectedGroupId == group.groupId;

            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                HapticFeedback.mediumImpact();
                Navigator.pop(context, group);
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? accentColor.withValues(alpha: 0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: isSelected
                      ? Border.all(color: accentColor.withValues(alpha: 0.4))
                      : null,
                ),
                child: Row(
                  children: [
                    // Group Avatar with Queendom ring
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? accentColor : Colors.white24,
                          width: 1.5,
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 20,
                        backgroundColor: const Color(0xFF221E36),
                        backgroundImage: group.groupPic.isNotEmpty
                            ? CachedNetworkImageProvider(group.groupPic)
                            : null,
                        child: group.groupPic.isEmpty
                            ? Text(
                                group.name.isNotEmpty
                                    ? group.name[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Details
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  group.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isSelected) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 1.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: accentColor.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'CONNECTED',
                                    style: TextStyle(
                                      color: accentColor,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            group.family != null && group.family != 'None'
                                ? '${group.family} • ${group.position ?? queendomName}'
                                : queendomName,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Selection radio/check
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSelected
                            ? accentColor
                            : Colors.white.withValues(alpha: 0.08),
                        border: Border.all(
                          color: isSelected
                              ? accentColor
                              : Colors.white.withValues(alpha: 0.2),
                        ),
                      ),
                      child: isSelected
                          ? const Icon(Icons.check, size: 16, color: Colors.black)
                          : null,
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
