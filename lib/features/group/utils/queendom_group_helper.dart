import 'dart:developer';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:worship_chat/common/utils/background_task_service.dart';
import 'package:worship_chat/common/utils/utils.dart';
import 'package:worship_chat/features/group/controller/group_controller.dart';
import 'package:worship_chat/features/group/screens/group_chat_screen.dart';
import 'package:worship_chat/features/group/utils/group_template_helper.dart';
import 'package:worship_chat/features/group/utils/queendom_emblem_helper.dart';
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
            name: group.nameWithPosition,
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
          name: GroupTemplateHelper.getNameWithPosition(name: name),
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
  String currentUserId = '';
  try {
    currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
  } catch (_) {}

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
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _searchController.dispose();
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
      child: SafeArea(
        top: false,
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
                  child: const QueendomEmblemWidget(position: 'Queen', size: 22),
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
                controller: _searchController,
                textAlignVertical: TextAlignVertical.center,
                style: const TextStyle(color: Colors.white, fontSize: 13.5),
                onChanged: (val) => setState(() => _searchQuery = val.trim()),
                decoration: InputDecoration(
                  hintText: 'Search Queendom group...',
                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                  prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 18),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 42,
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(
                            Icons.clear,
                            color: Colors.white54,
                            size: 16,
                          ),
                          splashRadius: 16,
                          padding: EdgeInsets.zero,
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  suffixIconConstraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 42,
                  ),
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
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
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      QueendomEmblemWidget(position: 'Queen', size: 16),
                      SizedBox(width: 6),
                      Text('Queen Pooja'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      QueendomEmblemWidget(position: 'Queen', size: 16),
                      SizedBox(width: 6),
                      Text('Queen Rashmika'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Tab Views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _QueendomGroupListView(
                  streamBuilder: () => widget.groupCtrl.getQueenPoojaStream(),
                  cached: widget.cachedPooja,
                  queendomName: 'Queen Pooja',
                  accentColor: const Color(0xFFFFD700),
                  searchQuery: _searchQuery,
                  currentSelectedGroupId: widget.currentSelectedGroupId,
                ),
                _QueendomGroupListView(
                  streamBuilder: () => widget.groupCtrl.getQueenRashmikaStream(),
                  cached: widget.cachedRashmika,
                  queendomName: 'Queen Rashmika',
                  accentColor: const Color(0xFFFF4081),
                  searchQuery: _searchQuery,
                  currentSelectedGroupId: widget.currentSelectedGroupId,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  }
}

class _QueendomGroupListView extends StatefulWidget {
  final Stream<List<GroupModel>> Function() streamBuilder;
  final List<GroupModel> cached;
  final String queendomName;
  final Color accentColor;
  final String searchQuery;
  final String? currentSelectedGroupId;

  const _QueendomGroupListView({
    required this.streamBuilder,
    required this.cached,
    required this.queendomName,
    required this.accentColor,
    required this.searchQuery,
    this.currentSelectedGroupId,
  });

  @override
  State<_QueendomGroupListView> createState() => _QueendomGroupListViewState();
}

class _QueendomGroupListViewState extends State<_QueendomGroupListView>
    with AutomaticKeepAliveClientMixin {
  late final Stream<List<GroupModel>> _stream;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _stream = widget.streamBuilder();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final query = widget.searchQuery.toLowerCase();
    final queendomName = widget.queendomName;
    final accentColor = widget.accentColor;

    return StreamBuilder<List<GroupModel>>(
      initialData: widget.cached.isNotEmpty ? widget.cached : null,
      stream: _stream,
      builder: (context, snapshot) {
        final groups = (snapshot.data ?? widget.cached)
            .where((g) =>
                g.queendom == queendomName &&
                (query.isEmpty ||
                    g.nameWithPosition.toLowerCase().contains(query) ||
                    g.name.toLowerCase().contains(query) ||
                    g.effectiveLivingPlace.toLowerCase().contains(query)))
            .toList();

        if (groups.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.group_outlined, size: 40, color: Colors.white24),
                const SizedBox(height: 8),
                Text(
                  widget.searchQuery.isEmpty
                      ? 'No $queendomName groups found'
                      : 'No groups match "${widget.searchQuery}"',
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
                                child: QueendomEmblemHelper.buildRichTitle(
                                  title: group.effectiveLivingPlace,
                                  family: group.family,
                                  fallbackFamily: 'Main',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  emblemSize: 18,
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

/// Resolves the devotion wish message for a group, falling back to position template.
String resolveQueendomGroupWish(GroupModel group) {
  if (group.wish != null && group.wish!.trim().isNotEmpty) {
    return group.wish!.trim();
  }
  final template = GroupTemplateHelper.generateTemplate(
    position: group.position ?? '',
    name: group.name,
    family: group.family ?? '',
  );
  if (template.wish.trim().isNotEmpty) {
    return template.wish.trim();
  }
  final fullName = group.nameWithPosition.trim().isNotEmpty
      ? group.nameWithPosition.trim()
      : group.name.trim();
  return '🙇‍♀️🙇‍♀️ Praise $fullName 🙇‍♀️🙇‍♀️';
}

/// Confirms and sends wishes to all [groupsToWish] inside [BackgroundTaskService],
/// persisting finalized wish messages in local Hive storage and Firestore even if
/// the user navigates away before completion.
Future<void> confirmAndWishCategoryGroups({
  required BuildContext context,
  required WidgetRef ref,
  required String categoryTitle,
  required Color accentColor,
  required String queendomType,
  required List<GroupModel> groupsToWish,
  required ValueNotifier<bool> isWishingNotifier,
  required bool Function() isMounted,
  VoidCallback? onComplete,
}) async {
  if (groupsToWish.isEmpty) {
    if (context.mounted) {
      showSnackBar(
        context: context,
        content: 'No mistresses found in $categoryTitle',
      );
    }
    return;
  }

  HapticFeedback.lightImpact();

  final count = groupsToWish.length;
  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1E1A2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Text('🙇🏻‍♂️', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Wish All $categoryTitle?',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: Text(
        'Send royal devotion wishes to all $count ${count == 1 ? 'mistress' : 'mistresses'} in $categoryTitle?',
        style: const TextStyle(color: Colors.white70, fontSize: 13),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: accentColor,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text(
            'Wish All 🙇🏻‍♂️',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    ),
  );

  if (confirm != true || !isMounted()) return;

  HapticFeedback.mediumImpact();
  isWishingNotifier.value = true;

  // Capture controller and snapshot list before running so background completion
  // never touches a disposed WidgetRef or aborts when navigating away.
  final controller = ref.read(groupControllerProvider);
  final snapshotGroups = List<GroupModel>.from(groupsToWish);

  try {
    final sentCount =
        await BackgroundTaskService.instance.runWithBackgroundTask<int>(
      title: 'Wishing $categoryTitle',
      initialMessage:
          'Sending wishes to ${snapshotGroups.length} ${snapshotGroups.length == 1 ? 'mistress' : 'mistresses'}...',
      successMessage: 'Sent royal wishes to $categoryTitle',
      task: (updateProgress) async {
        int sent = 0;
        final total = snapshotGroups.length;
        for (final group in snapshotGroups) {
          final wishText = resolveQueendomGroupWish(group);
          if (wishText.isEmpty) continue;

          final displayName = group.nameWithPosition.trim().isNotEmpty
              ? group.nameWithPosition.trim()
              : group.name;
          updateProgress(
            'Wishing $displayName (${sent + 1}/$total)...',
            progress: sent,
            maxProgress: total,
          );

          await controller.sendTextMessage(
            // Intentionally keep caller context for signature compatibility;
            // GroupRepository checks context.mounted so unmounting never aborts.
            // ignore: use_build_context_synchronously
            context,
            wishText,
            group.groupId,
            'wish',
            null,
            List<String>.from(group.fcmTokens),
            List<String>.from(group.membersUid),
            group.nameWithPosition,
            queendomType,
            clearReply: true,
          );
          sent++;

          updateProgress(
            'Saved & wished $sent/$total',
            progress: sent,
            maxProgress: total,
          );
          await Future.delayed(const Duration(milliseconds: 30));
        }
        return sent;
      },
    );

    if (context.mounted) {
      showSnackBar(
        context: context,
        content:
            'Sent royal wishes to $sentCount ${sentCount == 1 ? 'mistress' : 'mistresses'} in $categoryTitle! 🙇🏻‍♂️✨',
      );
    }
  } catch (e) {
    log('❌ Error wishing category: $e');
    if (context.mounted) {
      showSnackBar(
        context: context,
        content: 'Failed to send wishes: $e',
      );
    }
  } finally {
    if (isMounted()) {
      isWishingNotifier.value = false;
      onComplete?.call();
    }
  }
}
