import 'dart:developer';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:rxdart/rxdart.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/features/group/controller/group_controller.dart';
import 'package:worship_chat/features/group/screens/group_chat_screen.dart';
import 'package:worship_chat/models/group.dart';

/// A sleek, modern grid of group chat shortcuts for the Dashboard.
///
/// Features:
/// - Displays ONLY group profile pictures (no names in the grid).
/// - Long-press & drag to reorder shortcuts directly on the grid.
/// - Tap to immediately open the group chat.
/// - Unread message indicators with vibrant glow.
/// - Modal sheet to select, manage, and toggle group shortcuts.
/// - Persistent ordering & selection saved to Hive.
class GroupShortcutsGrid extends ConsumerStatefulWidget {
  final String currentUserId;

  const GroupShortcutsGrid({super.key, required this.currentUserId});

  @override
  ConsumerState<GroupShortcutsGrid> createState() => _GroupShortcutsGridState();
}

class _GroupShortcutsGridState extends ConsumerState<GroupShortcutsGrid> {
  static const String _hiveKey = 'dashboard_group_shortcuts_order';
  List<String> _shortcutIds = [];
  bool _hasLoadedFromStorage = false;

  @override
  void initState() {
    super.initState();
    _loadSavedShortcuts();
  }

  Box? _getGroupsBox() {
    try {
      if (Hive.isBoxOpen('groups_cache')) {
        return Hive.box('groups_cache');
      }
    } catch (e) {
      log('Error accessing groups_cache box: $e');
    }
    return null;
  }

  void _loadSavedShortcuts() {
    final box = _getGroupsBox();
    if (box != null && box.containsKey(_hiveKey)) {
      final saved = box.get(_hiveKey);
      if (saved is List) {
        _shortcutIds = List<String>.from(saved);
        _hasLoadedFromStorage = true;
      }
    }
  }

  Future<void> _saveShortcuts() async {
    final box = _getGroupsBox();
    if (box != null) {
      await box.put(_hiveKey, _shortcutIds);
    }
  }

  void _onReorder(int oldIndex, int newIndex) {
    if (oldIndex == newIndex ||
        oldIndex < 0 ||
        oldIndex >= _shortcutIds.length ||
        newIndex < 0 ||
        newIndex >= _shortcutIds.length) {
      return;
    }

    setState(() {
      final item = _shortcutIds.removeAt(oldIndex);
      _shortcutIds.insert(newIndex, item);
    });
    _saveShortcuts();
    HapticFeedback.lightImpact();
  }

  void _navigateToGroup(BuildContext context, GroupModel group) {
    HapticFeedback.selectionClick();
    String type = "others";
    Color? accentColor;
    if (group.queendom == 'Queen Pooja') {
      type = "queenPooja";
      accentColor = const Color(0xFFFFD700);
    } else if (group.queendom == 'Queen Rashmika') {
      type = "queenRashmika";
      accentColor = const Color(0xFFFF4081);
    }

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
  }

  void _showManageShortcutsSheet(BuildContext context, List<GroupModel> allGroups) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _ManageShortcutsSheet(
        allGroups: allGroups,
        initialSelectedIds: _shortcutIds,
        onSaved: (updatedIds) {
          setState(() {
            _shortcutIds = updatedIds;
          });
          _saveShortcuts();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Merge cached Pooja + Rashmika groups for instant initial display
    final controller = ref.watch(groupControllerProvider);
    final cachedPooja = controller.getCachedGroups('groups_pooja');
    final cachedRashmika = controller.getCachedGroups('groups_rashmika');
    final cachedGroups = [...cachedPooja, ...cachedRashmika];

    // Merge both queendom streams — excludes queendom:None (chat/suggestion groups)
    final mergedStream = Rx.combineLatest2<List<GroupModel>, List<GroupModel>, List<GroupModel>>(
      controller.getQueenPoojaStream(),
      controller.getQueenRashmikaStream(),
      (poojaGroups, rashmikaGroups) => [...poojaGroups, ...rashmikaGroups],
    );

    return StreamBuilder<List<GroupModel>>(
      initialData: cachedGroups.isNotEmpty ? cachedGroups : null,
      stream: mergedStream,
      builder: (context, snapshot) {
        final allGroups = snapshot.data ?? cachedGroups;

        // If no groups at all for the user
        if (allGroups.isEmpty) {
          return const SizedBox.shrink();
        }

        // Initialize defaults if first time (no saved shortcuts)
        if (!_hasLoadedFromStorage && _shortcutIds.isEmpty) {
          final defaultCount = allGroups.length > 8 ? 8 : allGroups.length;
          _shortcutIds = allGroups.take(defaultCount).map((g) => g.groupId).toList();
          _hasLoadedFromStorage = true;
          _saveShortcuts();
        }

        // Filter and arrange groups according to stored shortcut IDs
        final groupMap = {for (var g in allGroups) g.groupId: g};
        final List<GroupModel> activeShortcuts = [];
        for (var id in _shortcutIds) {
          final g = groupMap[id];
          if (g != null) {
            activeShortcuts.add(g);
          }
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header Row ──────────────────────────────────────────
              Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: tabColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.bolt_rounded,
                      color: tabColor,
                      size: 13,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'GROUP SHORTCUTS',
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  if (activeShortcuts.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${activeShortcuts.length}',
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  GestureDetector(
                    onTap: () => _showManageShortcutsSheet(context, allGroups),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Manage',
                          style: TextStyle(
                            color: tabColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 3),
                        const Icon(
                          Icons.tune_rounded,
                          color: tabColor,
                          size: 13,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ── Content: Empty state or Grid ────────────────────────
              if (activeShortcuts.isEmpty)
                _buildEmptyState(context, allGroups)
              else
                _buildShortcutsGrid(context, activeShortcuts, allGroups),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context, List<GroupModel> allGroups) {
    return GestureDetector(
      onTap: () => _showManageShortcutsSheet(context, allGroups),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: BoxDecoration(
          color: mobileChatBoxColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: dividerColor),
        ),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: tabColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.add_rounded,
                color: tabColor,
                size: 24,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Add Group Shortcuts',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Select groups for fast 1-tap access on your dashboard',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShortcutsGrid(
    BuildContext context,
    List<GroupModel> shortcuts,
    List<GroupModel> allGroups,
  ) {
    const crossAxisCount = 4;
    const spacing = 12.0;
    final totalItems = shortcuts.length + 1; // +1 for the Add tile at the end

    return LayoutBuilder(
      builder: (context, constraints) {
        final itemSize = (constraints.maxWidth - (spacing * (crossAxisCount - 1))) / crossAxisCount;

        return GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: totalItems,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            childAspectRatio: 1.0,
          ),
          itemBuilder: (context, index) {
            // Last item is the "+" Add / Manage shortcut button
            if (index == shortcuts.length) {
              return _buildAddButtonTile(context, allGroups, shortcuts.length);
            }

            final group = shortcuts[index];
            final hasUnseen = group.hasUnseenForUser(widget.currentUserId);

            return DragTarget<int>(
              onWillAcceptWithDetails: (details) => details.data != index,
              onAcceptWithDetails: (details) => _onReorder(details.data, index),
              builder: (context, candidateData, rejectedData) {
                final isHovered = candidateData.isNotEmpty;

                return LongPressDraggable<int>(
                  data: index,
                  delay: const Duration(milliseconds: 180),
                  dragAnchorStrategy: childDragAnchorStrategy,
                  onDragStarted: () => HapticFeedback.mediumImpact(),
                  feedback: Material(
                    color: Colors.transparent,
                    child: SizedBox(
                      width: itemSize,
                      height: itemSize,
                      child: Transform.scale(
                        scale: 1.14,
                        child: _buildItemCard(
                          group: group,
                          hasUnseen: hasUnseen,
                          isHovered: false,
                          isDragging: true,
                        ),
                      ),
                    ),
                  ),
                  childWhenDragging: Opacity(
                    opacity: 0.25,
                    child: _buildItemCard(
                      group: group,
                      hasUnseen: hasUnseen,
                      isHovered: false,
                      isGhost: true,
                    ),
                  ),
                  child: GestureDetector(
                    onTap: () => _navigateToGroup(context, group),
                    child: _buildItemCard(
                      group: group,
                      hasUnseen: hasUnseen,
                      isHovered: isHovered,
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildItemCard({
    required GroupModel group,
    required bool hasUnseen,
    required bool isHovered,
    bool isDragging = false,
    bool isGhost = false,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: mobileChatBoxColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isHovered
              ? accentOrange
              : hasUnseen
                  ? tabColor
                  : isDragging
                      ? tabColor
                      : dividerColor,
          width: isHovered || isDragging
              ? 2.5
              : hasUnseen
                  ? 2.0
                  : 1.2,
        ),
        boxShadow: isDragging
            ? [
                BoxShadow(
                  color: tabColor.withValues(alpha: 0.55),
                  blurRadius: 18,
                  spreadRadius: 3,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.6),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ]
            : isHovered
                ? [
                    BoxShadow(
                      color: accentOrange.withValues(alpha: 0.5),
                      blurRadius: 14,
                      spreadRadius: 2,
                    ),
                  ]
                : hasUnseen
                    ? [
                        BoxShadow(
                          color: tabColor.withValues(alpha: 0.35),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Profile picture filling the entire squircle
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: group.groupPic.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: group.groupPic,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                      color: const Color(0xFF1F1F2E),
                      child: Center(
                        child: Icon(
                          Icons.groups_rounded,
                          color: Colors.grey[700],
                          size: 26,
                        ),
                      ),
                    ),
                    errorWidget: (_, __, ___) => _buildFallbackAvatar(group),
                  )
                : _buildFallbackAvatar(group),
          ),

          // Unread indicator dot (top-right corner)
          if (hasUnseen && !isGhost)
            Positioned(
              top: 5,
              right: 5,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: tabColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: backgroundColor, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: tabColor.withValues(alpha: 0.8),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFallbackAvatar(GroupModel group) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2E243A), Color(0xFF161522)],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.groups_rounded,
          color: tabColor.withValues(alpha: 0.8),
          size: 26,
        ),
      ),
    );
  }

  Widget _buildAddButtonTile(
    BuildContext context,
    List<GroupModel> allGroups,
    int shortcutsLength,
  ) {
    return DragTarget<int>(
      onWillAcceptWithDetails: (details) => true,
      onAcceptWithDetails: (details) => _onReorder(details.data, shortcutsLength - 1),
      builder: (context, candidateData, rejectedData) {
        final isHovered = candidateData.isNotEmpty;

        return GestureDetector(
          onTap: () => _showManageShortcutsSheet(context, allGroups),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              color: mobileChatBoxColor.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isHovered ? tabColor : dividerColor,
                width: isHovered ? 2.0 : 1.5,
              ),
            ),
            child: Center(
              child: Icon(
                Icons.add_rounded,
                color: isHovered ? tabColor : greyColor,
                size: 28,
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom Sheet to Select & Manage Shortcuts
// ─────────────────────────────────────────────────────────────────────────────

class _ManageShortcutsSheet extends StatefulWidget {
  final List<GroupModel> allGroups;
  final List<String> initialSelectedIds;
  final ValueChanged<List<String>> onSaved;

  const _ManageShortcutsSheet({
    required this.allGroups,
    required this.initialSelectedIds,
    required this.onSaved,
  });

  @override
  State<_ManageShortcutsSheet> createState() => _ManageShortcutsSheetState();
}

class _ManageShortcutsSheetState extends State<_ManageShortcutsSheet> {
  late final Set<String> _selectedIds;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedIds = Set<String>.from(widget.initialSelectedIds);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleGroup(String groupId) {
    setState(() {
      if (_selectedIds.contains(groupId)) {
        _selectedIds.remove(groupId);
      } else {
        _selectedIds.add(groupId);
      }
    });
    HapticFeedback.selectionClick();
  }

  void _save() {
    // Preserve initial ordering for items that were already selected,
    // and append newly selected groups at the end
    final List<String> result = [];

    for (var id in widget.initialSelectedIds) {
      if (_selectedIds.contains(id)) {
        result.add(id);
      }
    }
    for (var id in _selectedIds) {
      if (!result.contains(id)) {
        result.add(id);
      }
    }

    widget.onSaved(result);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final filteredGroups = widget.allGroups.where((g) {
      if (_searchQuery.trim().isEmpty) return true;
      return g.name.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      decoration: const BoxDecoration(
        color: Color(0xFF14141E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // ── Drag Handle ─────────────────────────────────────────────
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── Sheet Header ────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Select Group Shortcuts',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_selectedIds.length} of ${widget.allGroups.length} selected • Drag to reorder on dashboard',
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: _save,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: tabColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Done',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ── Search Bar ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              height: 42,
              decoration: BoxDecoration(
                color: mobileChatBoxColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: dividerColor),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (val) => setState(() => _searchQuery = val),
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: Colors.grey[500],
                    size: 20,
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? GestureDetector(
                          onTap: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                          child: Icon(
                            Icons.close_rounded,
                            color: Colors.grey[500],
                            size: 18,
                          ),
                        )
                      : null,
                  hintText: 'Search groups...',
                  hintStyle: TextStyle(color: Colors.grey[500], fontSize: 13),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // ── Quick Select All / Clear ────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () {
                    setState(() {
                      if (_selectedIds.length == widget.allGroups.length) {
                        _selectedIds.clear();
                      } else {
                        _selectedIds.addAll(widget.allGroups.map((g) => g.groupId));
                      }
                    });
                  },
                  child: Text(
                    _selectedIds.length == widget.allGroups.length
                        ? 'Deselect All'
                        : 'Select All',
                    style: TextStyle(
                      color: tabColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  'Tap to toggle shortcut',
                  style: TextStyle(color: Colors.grey[600], fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          const Divider(color: dividerColor),

          // ── Groups List ─────────────────────────────────────────────
          Expanded(
            child: filteredGroups.isEmpty
                ? Center(
                    child: Text(
                      'No groups found',
                      style: TextStyle(color: Colors.grey[500]),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    itemCount: filteredGroups.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final group = filteredGroups[index];
                      final isSelected = _selectedIds.contains(group.groupId);

                      return GestureDetector(
                        onTap: () => _toggleGroup(group.groupId),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? tabColor.withValues(alpha: 0.08)
                                : mobileChatBoxColor.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected
                                  ? tabColor.withValues(alpha: 0.5)
                                  : dividerColor,
                              width: isSelected ? 1.5 : 1.0,
                            ),
                          ),
                          child: Row(
                            children: [
                              // Group Profile Pic
                              ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: group.groupPic.isNotEmpty
                                    ? CachedNetworkImage(
                                        imageUrl: group.groupPic,
                                        width: 44,
                                        height: 44,
                                        fit: BoxFit.cover,
                                        errorWidget: (_, __, ___) =>
                                            _buildGroupPlaceholder(),
                                      )
                                    : _buildGroupPlaceholder(),
                              ),
                              const SizedBox(width: 14),

                              // Group Name & Details
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      group.name,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.w500,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${group.membersUid.length} members',
                                      style: TextStyle(
                                        color: Colors.grey[500],
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Selection Checkbox Indicator
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: isSelected ? tabColor : Colors.transparent,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected ? tabColor : Colors.grey[600]!,
                                    width: 2,
                                  ),
                                ),
                                child: isSelected
                                    ? const Icon(
                                        Icons.check_rounded,
                                        color: Colors.white,
                                        size: 16,
                                      )
                                    : null,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // ── Bottom Save Action Bar ──────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            decoration: const BoxDecoration(
              color: Color(0xFF101018),
              border: Border(top: BorderSide(color: dividerColor)),
            ),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: tabColor,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  'Save Shortcuts (${_selectedIds.length})',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupPlaceholder() {
    return Container(
      width: 44,
      height: 44,
      color: const Color(0xFF262636),
      child: const Icon(
        Icons.groups_rounded,
        color: Colors.white54,
        size: 22,
      ),
    );
  }
}
