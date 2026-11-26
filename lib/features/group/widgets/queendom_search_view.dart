import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:worship_chat/common/utils/utils.dart';
import 'package:worship_chat/features/group/utils/queendom_emblem_helper.dart';
import 'package:worship_chat/features/settings/models/queendom_customization_model.dart';
import 'package:worship_chat/features/settings/providers/queendom_customization_provider.dart';
import 'package:worship_chat/models/group.dart';
export 'package:worship_chat/features/settings/models/queendom_customization_model.dart';

/// A world-class, full-screen royal search suite for Queendom screens.
class QueendomSearchView extends StatefulWidget {
  final String realmName; // e.g. "Queen Pooja" or "Queen Rashmika"
  final Color realmThemeColor; // e.g. Golden or Ruby
  final List<GroupModel> allGroups;
  final VoidCallback onClose;
  final int initialCategoryIndex;
  final Widget Function(
    BuildContext context,
    GroupModel group,
    Color accentColor,
    bool hasUnseen,
    List<GroupModel> subGroups,
    String? matchedSubGroupInfo,
  ) cardBuilder;

  const QueendomSearchView({
    super.key,
    required this.realmName,
    required this.realmThemeColor,
    required this.allGroups,
    required this.onClose,
    this.initialCategoryIndex = 0,
    required this.cardBuilder,
  });

  @override
  State<QueendomSearchView> createState() => _QueendomSearchViewState();
}

class _QueendomSearchViewState extends State<QueendomSearchView> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  String _searchQuery = '';
  int? _selectedCategoryIndex; // null = All Categories
  String? _selectedFamily; // null = All Families
  bool _unseenOnly = false;
  bool _hasSubGroupsOnly = false;

  List<QueendomCategory> get categories =>
      QueendomCustomizationService.instance.state.allCategories;
  List<String> get familyOrder =>
      QueendomCustomizationService.instance.state.familyOrder;

  @override
  void initState() {
    super.initState();
    // Default to All Categories for broad, intuitive search, but if user explicitly
    // opened from a category, they can easily switch with the top pills carousel.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Color _getCategoryColor(String? position, Color fallback) {
    if (position == null || position.isEmpty) return fallback;
    for (final cat in categories) {
      if (cat.position.toLowerCase() == position.toLowerCase()) {
        return cat.color;
      }
    }
    return fallback;
  }

  int _getFamilyOrderIndex(String? family) {
    if (family == null || family.isEmpty || family == 'None') {
      return familyOrder.length;
    }
    final index = familyOrder.indexOf(family);
    return index == -1 ? familyOrder.length : index;
  }

  int _getCategoryOrderIndex(String? position) {
    if (position == null || position.isEmpty) return categories.length;
    final idx = categories.indexWhere(
      (c) => c.position.toLowerCase() == position.toLowerCase(),
    );
    return idx == -1 ? categories.length : idx;
  }

  bool _matchesGroup(
    GroupModel group,
    List<GroupModel> allGroups,
    String query,
  ) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase().trim();
    final words = q.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return true;

    final subGroups = allGroups.where((g) => g.parentGroupId == group.groupId);
    final buffer = StringBuffer();
    buffer.write('${group.name} ');
    buffer.write('${group.effectiveLivingPlace} ');
    if (group.livingPlace != null) buffer.write('${group.livingPlace} ');
    if (group.family != null) buffer.write('${group.family} ');
    if (group.position != null) buffer.write('${group.position} ');
    buffer.write('${group.nameWithPosition} ');
    for (final sg in subGroups) {
      buffer.write('${sg.name} ');
      buffer.write('${sg.effectiveLivingPlace} ');
      if (sg.livingPlace != null) buffer.write('${sg.livingPlace} ');
      if (sg.family != null) buffer.write('${sg.family} ');
      buffer.write('${sg.subGroupDisplayCategory} ');
      buffer.write(sg.isFuckToySubGroup ? 'fucktoy fuck toy ' : 'wife ');
    }
    final searchableText = buffer.toString().toLowerCase();

    return words.every((word) => searchableText.contains(word));
  }

  String? _getMatchedSubGroupInfo(
    GroupModel group,
    List<GroupModel> allGroups,
    String query,
  ) {
    if (query.trim().isEmpty) return null;
    final q = query.toLowerCase().trim();
    final words = q.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return null;

    final subGroups = allGroups.where((g) => g.parentGroupId == group.groupId);
    for (final sg in subGroups) {
      final sgText = '${sg.name} ${sg.effectiveLivingPlace} ${sg.subGroupDisplayCategory}'
          .toLowerCase();
      if (words.any((w) => sgText.contains(w))) {
        final role = sg.isFuckToySubGroup ? 'Fuck Toy' : 'Wife';
        return 'Matched Sub-group: ${sg.name} ($role)';
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = safeCurrentUserId();
    final allNonSubGroups =
        widget.allGroups.where((g) => !g.isSubGroup).toList();

    // 1. Text filter
    final textMatchingGroups = allNonSubGroups
        .where((g) => _matchesGroup(g, widget.allGroups, _searchQuery))
        .toList();

    // 2. Filter by Category
    List<GroupModel> categoryFiltered = textMatchingGroups;
    if (_selectedCategoryIndex != null) {
      final targetPosition = categories[_selectedCategoryIndex!].position;
      categoryFiltered = categoryFiltered
          .where((g) => g.position?.toLowerCase() == targetPosition.toLowerCase())
          .toList();
    }

    // 3. Filter by Family
    List<GroupModel> familyFiltered = categoryFiltered;
    if (_selectedFamily != null) {
      familyFiltered = familyFiltered
          .where((g) => g.family?.toLowerCase() == _selectedFamily!.toLowerCase())
          .toList();
    }

    // 4. Quick flags
    List<GroupModel> finalResults = familyFiltered;
    if (_unseenOnly && currentUserId != null) {
      finalResults = finalResults
          .where((g) => g.hasUnseenForUser(currentUserId))
          .toList();
    }
    if (_hasSubGroupsOnly) {
      finalResults = finalResults.where((g) {
        return widget.allGroups.any((sg) => sg.parentGroupId == g.groupId);
      }).toList();
    }

    // Sort final results
    final sortedResults = List<GroupModel>.from(finalResults);
    sortedResults.sort((a, b) {
      final q = _searchQuery.toLowerCase().trim();
      if (q.isNotEmpty) {
        final aExact = a.name.toLowerCase().startsWith(q) ||
            a.effectiveLivingPlace.toLowerCase().startsWith(q);
        final bExact = b.name.toLowerCase().startsWith(q) ||
            b.effectiveLivingPlace.toLowerCase().startsWith(q);
        if (aExact && !bExact) return -1;
        if (!aExact && bExact) return 1;
      }

      // Category order
      final aCatIdx = _getCategoryOrderIndex(a.position);
      final bCatIdx = _getCategoryOrderIndex(b.position);
      if (aCatIdx != bCatIdx) return aCatIdx.compareTo(bCatIdx);

      // Family order
      final aFamilyIdx = _getFamilyOrderIndex(a.family);
      final bFamilyIdx = _getFamilyOrderIndex(b.family);
      if (aFamilyIdx != bFamilyIdx) return aFamilyIdx.compareTo(bFamilyIdx);

      return a.name.compareTo(b.name);
    });

    final themeColor = widget.realmThemeColor;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _focusNode.unfocus();
          widget.onClose();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0C0910),
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // ── Royal Glassmorphic Top Search Header ─────────────────────
              _buildTopHeader(themeColor),

              // ── Category Scope Carousel ──────────────────────────────────
              _buildCategoryCarousel(textMatchingGroups),

              // ── Quick Family & Special Filter Carousel ───────────────────
              _buildFilterRow(textMatchingGroups, currentUserId),

              // ── Status Bar with Match Insights ───────────────────────────
              _buildResultsStatusBar(sortedResults.length, textMatchingGroups.length),

              // ── Search Body: Zero-Query Discovery, Empty State, or List ──
              Expanded(
                child: sortedResults.isEmpty
                    ? _buildEmptyState(themeColor)
                    : _buildResultsList(sortedResults, currentUserId),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Top Bar with Back, Search Field, Clear Button, and Realm Badge ─────────
  Widget _buildTopHeader(Color themeColor) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 14, 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color.lerp(themeColor, Colors.black, 0.75)!,
            const Color(0xFF130D18),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: themeColor.withValues(alpha: 0.18),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // Glass Back Button
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(22),
                  onTap: () {
                    HapticFeedback.lightImpact();
                    _focusNode.unfocus();
                    widget.onClose();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.35),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.22),
                        width: 1.1,
                      ),
                    ),
                    child: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Search Text Field Container
              Expanded(
                child: Container(
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: _focusNode.hasFocus
                          ? themeColor.withValues(alpha: 0.8)
                          : Colors.white.withValues(alpha: 0.22),
                      width: _focusNode.hasFocus ? 1.5 : 1.1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _focusNode.hasFocus
                            ? themeColor.withValues(alpha: 0.25)
                            : Colors.black.withValues(alpha: 0.2),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 12, right: 8),
                        child: Icon(
                          Icons.search_rounded,
                          color: _focusNode.hasFocus
                              ? themeColor
                              : Colors.white.withValues(alpha: 0.65),
                          size: 20,
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          focusNode: _focusNode,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w500,
                          ),
                          cursorColor: themeColor,
                          cursorWidth: 2,
                          textInputAction: TextInputAction.search,
                          onChanged: (val) {
                            setState(() {
                              _searchQuery = val.trim();
                            });
                          },
                          decoration: InputDecoration(
                            hintText: 'Search ${widget.realmName} mistresses, sanctums…',
                            hintStyle: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4),
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      if (_searchQuery.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close_rounded,
                                color: Colors.white,
                                size: 14,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Realm Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: themeColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: themeColor.withValues(alpha: 0.45),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/emojis/queen.png',
                      width: 13,
                      height: 13,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      widget.realmName.replaceAll('Queen ', ''),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: themeColor,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Category Carousel Filter Strip ─────────────────────────────────────────
  Widget _buildCategoryCarousel(List<GroupModel> textMatchingGroups) {
    final allCount = textMatchingGroups.length;

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF110B17),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.05),
            width: 1,
          ),
        ),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        itemCount: categories.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            // "All Categories" chip
            final isSelected = _selectedCategoryIndex == null;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _selectedCategoryIndex = null);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: isSelected
                        ? LinearGradient(
                            colors: [
                              widget.realmThemeColor,
                              Color.lerp(widget.realmThemeColor, Colors.black, 0.3)!,
                            ],
                          )
                        : null,
                    color: isSelected ? null : Colors.white.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected
                          ? widget.realmThemeColor
                          : Colors.white.withValues(alpha: 0.15),
                      width: isSelected ? 1.3 : 0.9,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: widget.realmThemeColor.withValues(alpha: 0.4),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : [],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.auto_awesome,
                        size: 13,
                        color: isSelected ? Colors.white : Colors.white70,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'All Mistresses',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected ? Colors.white : Colors.white70,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.black.withValues(alpha: 0.25)
                              : Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$allCount',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? Colors.white : Colors.white60,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          final catIndex = index - 1;
          final cat = categories[catIndex];
          final isSelected = _selectedCategoryIndex == catIndex;
          final count = textMatchingGroups
              .where((g) => g.position?.toLowerCase() == cat.position.toLowerCase())
              .length;

          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  if (_selectedCategoryIndex == catIndex) {
                    _selectedCategoryIndex = null; // Toggle back to all
                  } else {
                    _selectedCategoryIndex = catIndex;
                  }
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  gradient: isSelected
                      ? LinearGradient(
                          colors: [
                            cat.color,
                            Color.lerp(cat.color, Colors.black, 0.35)!,
                          ],
                        )
                      : null,
                  color: isSelected ? null : Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected
                        ? cat.color
                        : cat.color.withValues(alpha: count > 0 ? 0.35 : 0.12),
                    width: isSelected ? 1.3 : 0.8,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: cat.color.withValues(alpha: 0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : [],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    QueendomEmblemWidget(
                      position: cat.position,
                      emoji: cat.emoji,
                      size: 14,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      cat.title,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        color: isSelected
                            ? Colors.white
                            : (count > 0
                                ? Colors.white.withValues(alpha: 0.85)
                                : Colors.white.withValues(alpha: 0.45)),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.black.withValues(alpha: 0.25)
                            : (count > 0
                                ? cat.color.withValues(alpha: 0.2)
                                : Colors.white.withValues(alpha: 0.08)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          color: isSelected
                              ? Colors.white
                              : (count > 0 ? cat.color : Colors.white38),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Quick Family & Special Filter Carousel ─────────────────────────────────
  Widget _buildFilterRow(List<GroupModel> textMatchingGroups, String? currentUserId) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0814),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.04),
            width: 1,
          ),
        ),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        children: [
          // Filter label icon
          Padding(
            padding: const EdgeInsets.only(right: 8, left: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.tune_rounded,
                  size: 13,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 4),
                Text(
                  'Filters:',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),

          // Unread toggle chip
          _buildToggleChip(
            label: 'Has Unseen',
            icon: Icons.mark_chat_unread_rounded,
            isActive: _unseenOnly,
            activeColor: Colors.redAccent,
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _unseenOnly = !_unseenOnly);
            },
          ),

          // Has sub-groups toggle chip
          _buildToggleChip(
            label: 'With Sub-groups',
            icon: Icons.family_restroom_rounded,
            isActive: _hasSubGroupsOnly,
            activeColor: const Color(0xFFE040FB),
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _hasSubGroupsOnly = !_hasSubGroupsOnly);
            },
          ),

          // Family separator
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            width: 1,
            color: Colors.white.withValues(alpha: 0.12),
          ),

          // All Families reset
          if (_selectedFamily != null)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: () => setState(() => _selectedFamily = null),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.5),
                      width: 0.8,
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.close, size: 11, color: Colors.white),
                      SizedBox(width: 3),
                      Text(
                        'Clear Family',
                        style: TextStyle(fontSize: 10, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Family chips
          ...familyOrder.map((fam) {
            final isFamActive = _selectedFamily == fam;
            final count = textMatchingGroups.where((g) => g.family == fam).length;
            if (count == 0 && !isFamActive) return const SizedBox.shrink();

            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _selectedFamily = isFamActive ? null : fam;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: isFamActive
                        ? widget.realmThemeColor.withValues(alpha: 0.3)
                        : Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isFamActive
                          ? widget.realmThemeColor
                          : Colors.white.withValues(alpha: 0.12),
                      width: isFamActive ? 1.1 : 0.7,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      QueendomFamilyEmblemWidget(family: fam, size: 11),
                      const SizedBox(width: 4),
                      Text(
                        fam,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: isFamActive ? FontWeight.bold : FontWeight.w500,
                          color: isFamActive
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.75),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: isFamActive
                              ? widget.realmThemeColor
                              : Colors.white.withValues(alpha: 0.45),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildToggleChip({
    required String label,
    required IconData icon,
    required bool isActive,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: isActive
                ? activeColor.withValues(alpha: 0.25)
                : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isActive
                  ? activeColor
                  : Colors.white.withValues(alpha: 0.12),
              width: isActive ? 1.1 : 0.7,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 11,
                color: isActive ? activeColor : Colors.white60,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                  color: isActive ? Colors.white : Colors.white60,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Results Status Bar ─────────────────────────────────────────────────────
  Widget _buildResultsStatusBar(int matchCount, int totalTextMatches) {
    final hasFilters = _selectedCategoryIndex != null ||
        _selectedFamily != null ||
        _unseenOnly ||
        _hasSubGroupsOnly;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.04),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.auto_awesome_rounded,
            size: 13,
            color: widget.realmThemeColor,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: const TextStyle(fontSize: 11.5, color: Colors.white70),
                children: [
                  TextSpan(
                    text: '$matchCount ${matchCount == 1 ? 'mistress' : 'mistresses'} found',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  if (_searchQuery.isNotEmpty) ...[
                    const TextSpan(text: ' matching "'),
                    TextSpan(
                      text: _searchQuery,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: widget.realmThemeColor,
                      ),
                    ),
                    const TextSpan(text: '"'),
                  ],
                  if (_selectedCategoryIndex != null)
                    TextSpan(
                      text: ' in ${categories[_selectedCategoryIndex!].title}',
                      style: TextStyle(
                        color: categories[_selectedCategoryIndex!].color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  if (_selectedFamily != null)
                    TextSpan(
                      text: ' • ${_selectedFamily!} Family',
                      style: const TextStyle(
                        color: Colors.amberAccent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (hasFilters)
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _selectedCategoryIndex = null;
                  _selectedFamily = null;
                  _unseenOnly = false;
                  _hasSubGroupsOnly = false;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Reset Filters',
                  style: TextStyle(fontSize: 10, color: Colors.white70),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Results List ───────────────────────────────────────────────────────────
  Widget _buildResultsList(List<GroupModel> results, String? currentUserId) {
    return ListView.builder(
      controller: _scrollController,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 30),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final group = results[index];
        final subGroups = widget.allGroups
            .where((g) => g.parentGroupId == group.groupId)
            .toList();
        final hasUnseen =
            currentUserId != null && group.hasUnseenForUser(currentUserId);
        final cardColor =
            _getCategoryColor(group.position, widget.realmThemeColor);
        final matchedSubGroupInfo =
            _getMatchedSubGroupInfo(group, widget.allGroups, _searchQuery);

        return widget.cardBuilder(
          context,
          group,
          cardColor,
          hasUnseen,
          subGroups,
          matchedSubGroupInfo,
        );
      },
    );
  }

  // ── Empty State ────────────────────────────────────────────────────────────
  Widget _buildEmptyState(Color themeColor) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: themeColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(
                  color: themeColor.withValues(alpha: 0.4),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: themeColor.withValues(alpha: 0.25),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Icon(
                Icons.search_off_rounded,
                size: 48,
                color: themeColor,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No Mistresses Found in ${widget.realmName}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No mistresses matching "$_searchQuery" were found with the active filters.'
                  : 'No mistresses match the selected filters.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.7),
                height: 1.35,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_searchQuery.isNotEmpty)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: themeColor,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      elevation: 4,
                    ),
                    icon: const Icon(Icons.clear_all_rounded, size: 16),
                    label: const Text(
                      'Clear Query',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  ),
                if (_searchQuery.isNotEmpty) const SizedBox(width: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text(
                    'Reset All Filters',
                    style: TextStyle(fontSize: 12),
                  ),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                      _selectedCategoryIndex = null;
                      _selectedFamily = null;
                      _unseenOnly = false;
                      _hasSubGroupsOnly = false;
                    });
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
