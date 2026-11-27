import 'dart:developer';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/features/group/controller/group_gallery_controller.dart';
import 'package:worship_chat/features/group/screens/multi_gallery_shuffled_screen.dart';
import 'package:worship_chat/features/group/utils/multi_gallery_shuffler_helper.dart';
import 'package:worship_chat/models/group.dart';
import 'package:worship_chat/models/group_gallery_image.dart';

/// Modal bottom sheet allowing users to select multiple group galleries and launch a unified shuffled view or slideshow.
class MultiGalleryShuffleSheet extends ConsumerStatefulWidget {
  final String? initialGroupId;
  final List<GroupModel>? availableGroups;
  final Color accentColor;

  const MultiGalleryShuffleSheet({
    super.key,
    this.initialGroupId,
    this.availableGroups,
    this.accentColor = tabColor,
  });

  static Future<void> show(
    BuildContext context, {
    String? initialGroupId,
    List<GroupModel>? availableGroups,
    Color accentColor = tabColor,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MultiGalleryShuffleSheet(
        initialGroupId: initialGroupId,
        availableGroups: availableGroups,
        accentColor: accentColor,
      ),
    );
  }

  @override
  ConsumerState<MultiGalleryShuffleSheet> createState() =>
      _MultiGalleryShuffleSheetState();
}

class _MultiGalleryShuffleSheetState
    extends ConsumerState<MultiGalleryShuffleSheet> {
  final Set<String> _selectedGroupIds = {};
  List<GroupModel> _allGroups = [];
  bool _isLoadingGroups = true;
  bool _isLoadingImages = false;
  String _search = '';
  String _selectedCategory = 'All';

  @override
  void initState() {
    super.initState();
    if (widget.initialGroupId != null) {
      _selectedGroupIds.add(widget.initialGroupId!);
    }
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    if (widget.availableGroups != null && widget.availableGroups!.isNotEmpty) {
      setState(() {
        _allGroups = List.from(widget.availableGroups!);
        _isLoadingGroups = false;
      });
      return;
    }

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        setState(() => _isLoadingGroups = false);
        return;
      }

      final snapshot = await FirebaseFirestore.instance
          .collection('groups')
          .where('membersUid', arrayContains: uid)
          .get();

      final groups = snapshot.docs.map((doc) {
        return GroupModel.fromMap({...doc.data(), 'groupId': doc.id});
      }).toList();

      groups.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      setState(() {
        _allGroups = groups;
        _isLoadingGroups = false;
        // If no group was selected initially, select all
        if (_selectedGroupIds.isEmpty && groups.isNotEmpty) {
          _selectedGroupIds.addAll(groups.map((g) => g.groupId));
        }
      });
    } catch (e) {
      log('Error loading groups for multi-shuffle: $e');
      setState(() => _isLoadingGroups = false);
    }
  }

  List<GroupModel> get _filteredGroups {
    return _allGroups.where((g) {
      final matchesCategory = _selectedCategory == 'All' || g.queendom == _selectedCategory;
      final query = _search.trim().toLowerCase();
      final matchesSearch = query.isEmpty ||
          '${g.nameWithPosition} ${g.name} ${g.effectiveLivingPlace} ${g.queendom ?? ''}'
              .toLowerCase()
              .contains(query);
      return matchesCategory && matchesSearch;
    }).toList();
  }

  Future<List<GroupGalleryImage>> _fetchShuffledImages() async {
    setState(() => _isLoadingImages = true);
    final groupIds = _selectedGroupIds.toList();

    try {
      final images = await ref
          .read(groupGalleryControllerProvider)
          .getMultiGalleryImages(groupIds);

      final shuffled = alternatePhotosAcrossGroups(images);
      return shuffled;
    } finally {
      if (mounted) setState(() => _isLoadingImages = false);
    }
  }

  void _launchGrid() async {
    if (_selectedGroupIds.isEmpty) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final images = await _fetchShuffledImages();
    if (!mounted) return;

    if (images.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No photos found in selected galleries')),
      );
      return;
    }

    final namesMap = <String, String>{};
    for (final g in _allGroups) {
      if (_selectedGroupIds.contains(g.groupId)) {
        namesMap[g.groupId] = g.nameWithPosition;
      }
    }

    navigator.pop(); // close sheet
    navigator.push(
      MaterialPageRoute(
        builder: (_) => MultiGalleryShuffledScreen(
          images: images,
          groupNamesMap: namesMap,
          accentColor: widget.accentColor,
          title: 'Multi-Gallery (${_selectedGroupIds.length} Groups)',
          initialMode: MultiGalleryMode.alternate,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredGroups;
    final totalPhotosSelected = _allGroups
        .where((g) => _selectedGroupIds.contains(g.groupId))
        .fold<int>(0, (total, g) => total + g.galleryCount);

    final isAllFilteredSelected = filtered.isNotEmpty &&
        filtered.every((g) => _selectedGroupIds.contains(g.groupId));

    final sheetHeight = MediaQuery.sizeOf(context).height * 0.85;

    return Container(
      height: sheetHeight,
      decoration: BoxDecoration(
        color: const Color(0xFF141124),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.14),
            width: 1.2,
          ),
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 24,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        bottom: true,
        child: Column(
          children: [
            // Drag handle pill
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 12),
                width: 42,
                height: 4.5,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),

            // Header Row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          widget.accentColor.withValues(alpha: 0.3),
                          widget.accentColor.withValues(alpha: 0.08),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: widget.accentColor.withValues(alpha: 0.45),
                        width: 1.2,
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.auto_awesome_motion_rounded,
                        color: widget.accentColor,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Multi-Gallery Shuffle',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.2,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Combine & shuffle photos across multiple groups',
                          style: TextStyle(
                            color: Colors.white60,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      setState(() {
                        if (isAllFilteredSelected) {
                          for (final g in filtered) {
                            _selectedGroupIds.remove(g.groupId);
                          }
                        } else {
                          for (final g in filtered) {
                            _selectedGroupIds.add(g.groupId);
                          }
                        }
                      });
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6.5,
                      ),
                      decoration: BoxDecoration(
                        color: widget.accentColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: widget.accentColor.withValues(alpha: 0.45),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        isAllFilteredSelected ? 'Deselect All' : 'Select All',
                        style: TextStyle(
                          color: widget.accentColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                    width: 1,
                  ),
                ),
                child: TextField(
                  onChanged: (val) => setState(() => _search = val),
                  style: const TextStyle(color: Colors.white, fontSize: 13.5),
                  decoration: InputDecoration(
                    hintText: 'Search galleries to shuffle...',
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.35),
                      fontSize: 13,
                    ),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      size: 20,
                      color: widget.accentColor.withValues(alpha: 0.8),
                    ),
                    suffixIcon: _search.isNotEmpty
                        ? IconButton(
                            icon: const Icon(
                              Icons.clear_rounded,
                              size: 18,
                              color: Colors.white54,
                            ),
                            onPressed: () => setState(() => _search = ''),
                          )
                        : null,
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Category Filter Chips
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                children: [
                  ('All', Icons.apps_rounded, null),
                  ('Queen Pooja', Icons.star_rounded, const Color(0xFFFFD700)),
                  ('Queen Rashmika', Icons.favorite_rounded, const Color(0xFFFF4081)),
                ].map((item) {
                  final label = item.$1;
                  final icon = item.$2;
                  final tint = item.$3 ?? widget.accentColor;
                  final isSelected = _selectedCategory == label;

                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _selectedCategory = label);
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          gradient: isSelected
                              ? LinearGradient(
                                  colors: [
                                    tint.withValues(alpha: 0.35),
                                    tint.withValues(alpha: 0.15),
                                  ],
                                )
                              : null,
                          color: isSelected
                              ? null
                              : Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected
                                ? tint.withValues(alpha: 0.8)
                                : Colors.white.withValues(alpha: 0.1),
                            width: isSelected ? 1.4 : 1,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: tint.withValues(alpha: 0.25),
                                    blurRadius: 8,
                                    spreadRadius: 0.5,
                                  ),
                                ]
                              : null,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              icon,
                              size: 14,
                              color: isSelected ? tint : Colors.white54,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              label,
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : Colors.white70,
                                fontSize: 12,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 8),

            // Divider
            Divider(
              color: Colors.white.withValues(alpha: 0.08),
              height: 1,
            ),

            // Groups List
            Expanded(
              child: _isLoadingGroups
                  ? Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: widget.accentColor,
                      ),
                    )
                  : filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.search_off_rounded,
                                size: 40,
                                color: Colors.white.withValues(alpha: 0.25),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'No matching galleries found',
                                style: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          itemCount: filtered.length,
                          itemBuilder: (_, index) {
                            final g = filtered[index];
                            final isSelected =
                                _selectedGroupIds.contains(g.groupId);

                            return Container(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 2,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? widget.accentColor.withValues(alpha: 0.12)
                                    : Colors.white.withValues(alpha: 0.035),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isSelected
                                      ? widget.accentColor.withValues(alpha: 0.6)
                                      : Colors.white.withValues(alpha: 0.06),
                                  width: isSelected ? 1.3 : 1,
                                ),
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: widget.accentColor
                                              .withValues(alpha: 0.15),
                                          blurRadius: 10,
                                          spreadRadius: 0.5,
                                        ),
                                      ]
                                    : null,
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  setState(() {
                                    if (isSelected) {
                                      _selectedGroupIds.remove(g.groupId);
                                    } else {
                                      _selectedGroupIds.add(g.groupId);
                                    }
                                  });
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 9,
                                  ),
                                  child: Row(
                                    children: [
                                      // Group Avatar
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: Container(
                                          width: 44,
                                          height: 44,
                                          decoration: BoxDecoration(
                                            color: Colors.white
                                                .withValues(alpha: 0.05),
                                            border: Border.all(
                                              color: isSelected
                                                  ? widget.accentColor
                                                      .withValues(alpha: 0.5)
                                                  : Colors.white
                                                      .withValues(alpha: 0.1),
                                              width: 1,
                                            ),
                                          ),
                                          child: g.groupPic.isNotEmpty
                                              ? CachedNetworkImage(
                                                  imageUrl: g.groupPic,
                                                  fit: BoxFit.cover,
                                                  errorWidget:
                                                      (_, __, ___) => Icon(
                                                    Icons.group,
                                                    size: 22,
                                                    color: Colors.white38,
                                                  ),
                                                )
                                              : Icon(
                                                  Icons.group,
                                                  size: 22,
                                                  color: Colors.white38,
                                                ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      // Title & metadata
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              g.nameWithPosition,
                                              style: TextStyle(
                                                color: isSelected
                                                    ? Colors.white
                                                    : Colors.white
                                                        .withValues(alpha: 0.9),
                                                fontSize: 13.5,
                                                fontWeight: isSelected
                                                    ? FontWeight.w700
                                                    : FontWeight.w600,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 3),
                                            Row(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 6,
                                                    vertical: 1.5,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white
                                                        .withValues(alpha: 0.08),
                                                    borderRadius:
                                                        BorderRadius.circular(6),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      const Icon(
                                                        Icons.photo_outlined,
                                                        size: 10,
                                                        color: Colors.white60,
                                                      ),
                                                      const SizedBox(width: 3),
                                                      Text(
                                                        '${g.galleryCount} photos',
                                                        style: const TextStyle(
                                                          color: Colors.white70,
                                                          fontSize: 10.5,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                if (g.queendom != null &&
                                                    g.queendom != 'None' &&
                                                    g.queendom!.isNotEmpty) ...[
                                                  const SizedBox(width: 6),
                                                  Flexible(
                                                    child: Text(
                                                      '• ${g.queendom}',
                                                      style: TextStyle(
                                                        color: Colors.grey[400],
                                                        fontSize: 11,
                                                      ),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      // Custom Checkbox circle
                                      AnimatedContainer(
                                        duration:
                                            const Duration(milliseconds: 180),
                                        width: 24,
                                        height: 24,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: isSelected
                                              ? widget.accentColor
                                              : Colors.transparent,
                                          border: Border.all(
                                            color: isSelected
                                                ? widget.accentColor
                                                : Colors.white.withValues(
                                                    alpha: 0.35),
                                            width: isSelected ? 2 : 1.5,
                                          ),
                                          boxShadow: isSelected
                                              ? [
                                                  BoxShadow(
                                                    color: widget.accentColor
                                                        .withValues(alpha: 0.4),
                                                    blurRadius: 6,
                                                  ),
                                                ]
                                              : null,
                                        ),
                                        child: isSelected
                                            ? const Center(
                                                child: Icon(
                                                  Icons.check_rounded,
                                                  size: 15,
                                                  color: Colors.white,
                                                ),
                                              )
                                            : null,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),

            // Bottom Floating Glass Action Bar
            if (_isLoadingImages) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: widget.accentColor,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Preparing shuffled pool...',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF110E20),
                  border: Border(
                    top: BorderSide(
                      color: Colors.white.withValues(alpha: 0.08),
                      width: 1,
                    ),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Actions Row
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${_selectedGroupIds.length} ${_selectedGroupIds.length == 1 ? 'group' : 'groups'} selected',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                '$totalPhotosSelected photos in combined pool',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.55),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed:
                              _selectedGroupIds.isEmpty ? null : _launchGrid,
                          icon: const Icon(Icons.grid_view_rounded, size: 17),
                          label: const Text(
                            'Browse Grid',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.2,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: widget.accentColor,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor:
                                Colors.white.withValues(alpha: 0.08),
                            disabledForegroundColor: Colors.white38,
                            elevation: 4,
                            shadowColor:
                                widget.accentColor.withValues(alpha: 0.4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
