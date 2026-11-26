import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/widgets/user_avatar.dart';
import 'package:worship_chat/features/group/screens/duplicate_finder_screen.dart';
import 'package:worship_chat/features/group/screens/group_gallery_screen.dart';
import 'package:worship_chat/features/home/screens/gallery_home_screen.dart';
import 'package:worship_chat/models/group.dart';

/// Dedicated, sleek mobile screen for displaying sanctuary photo counts
/// with royal analytics, filtering, sorting, and direct gallery navigation.
class PhotoCountScreen extends ConsumerStatefulWidget {
  static const String routeName = '/photo-counts';

  const PhotoCountScreen({super.key});

  @override
  ConsumerState<PhotoCountScreen> createState() => _PhotoCountScreenState();
}

class _PhotoCountScreenState extends ConsumerState<PhotoCountScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedCategory = 'All'; // 'All', 'Queen Pooja', 'Queen Rashmika', 'Wife', 'Fuck Toy'
  String _sortBy = 'Most Photos'; // 'Most Photos', 'Least Photos', 'Name (A-Z)', 'Name (Z-A)'
  bool _onlyWithPhotos = false;
  bool _isGridMode = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(galleryGroupsProvider);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: appBarColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Photo Counts',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 19,
          ),
        ),
        actions: [
          // View Mode Toggle (List vs Grid)
          IconButton(
            icon: Icon(
              _isGridMode ? Icons.view_list_rounded : Icons.grid_view_rounded,
              color: Colors.white70,
              size: 20,
            ),
            tooltip: _isGridMode ? 'List View' : 'Grid View',
            onPressed: () {
              HapticFeedback.lightImpact();
              setState(() => _isGridMode = !_isGridMode);
            },
          ),
          // Duplicate Finder Shortcut
          IconButton(
            icon: const Icon(
              Icons.copy_rounded,
              color: tabColor,
              size: 20,
            ),
            tooltip: 'Find Duplicates',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const DuplicateFinderScreen(
                    accentColor: tabColor,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: groupsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: tabColor),
        ),
        error: (error, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 36),
              const SizedBox(height: 10),
              const Text('Unable to load photo counts.'),
              TextButton(
                onPressed: () => ref.invalidate(galleryGroupsProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (allGroups) {
          // Calculate global metrics
          final totalPhotos = allGroups.fold<int>(0, (sum, g) => sum + g.galleryCount);
          final poojaPhotos = allGroups
              .where((g) => g.queendom == 'Queen Pooja')
              .fold<int>(0, (sum, g) => sum + g.galleryCount);
          final rashmikaPhotos = allGroups
              .where((g) => g.queendom == 'Queen Rashmika')
              .fold<int>(0, (sum, g) => sum + g.galleryCount);

          // Apply filters
          final filtered = allGroups.where((group) {
            // Category filter
            if (_selectedCategory == 'Queen Pooja' && group.queendom != 'Queen Pooja') {
              return false;
            }
            if (_selectedCategory == 'Queen Rashmika' && group.queendom != 'Queen Rashmika') {
              return false;
            }
            if (_selectedCategory == 'Wife' && !group.isWifeSubGroup) {
              return false;
            }
            if (_selectedCategory == 'Fuck Toy' && !group.isFuckToySubGroup) {
              return false;
            }

            // Photos only filter
            if (_onlyWithPhotos && group.galleryCount <= 0) {
              return false;
            }

            // Search query filter
            if (_searchQuery.isNotEmpty) {
              final query = _searchQuery.toLowerCase();
              final match = group.name.toLowerCase().contains(query) ||
                  group.nameWithPosition.toLowerCase().contains(query) ||
                  (group.queendom?.toLowerCase().contains(query) ?? false) ||
                  group.subGroupDisplayCategory.toLowerCase().contains(query) ||
                  (group.parentGroupName?.toLowerCase().contains(query) ?? false);
              if (!match) return false;
            }

            return true;
          }).toList();

          // Apply sorting
          if (_sortBy == 'Most Photos') {
            filtered.sort((a, b) {
              final countDiff = b.galleryCount.compareTo(a.galleryCount);
              if (countDiff != 0) return countDiff;
              return a.name.toLowerCase().compareTo(b.name.toLowerCase());
            });
          } else if (_sortBy == 'Least Photos') {
            filtered.sort((a, b) {
              final countDiff = a.galleryCount.compareTo(b.galleryCount);
              if (countDiff != 0) return countDiff;
              return a.name.toLowerCase().compareTo(b.name.toLowerCase());
            });
          } else if (_sortBy == 'Name (A-Z)') {
            filtered.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
          } else if (_sortBy == 'Name (Z-A)') {
            filtered.sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
          }

          final totalFilteredPhotos = filtered.fold<int>(0, (sum, g) => sum + g.galleryCount);

          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // ── Top Hero Analytics Header ──────────────────────────
              SliverToBoxAdapter(
                child: _buildHeroAnalyticsCard(
                  totalPhotos: totalPhotos,
                  poojaPhotos: poojaPhotos,
                  rashmikaPhotos: rashmikaPhotos,
                  allGroupsCount: allGroups.length,
                ),
              ),

              // ── Search & Filter Controls ───────────────────────────
              SliverToBoxAdapter(
                child: _buildControlsSection(
                  totalFilteredPhotos: totalFilteredPhotos,
                  filteredCount: filtered.length,
                  allCount: allGroups.length,
                ),
              ),

              // ── Sanctuaries List / Grid ────────────────────────────
              if (filtered.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildEmptyState(),
                )
              else if (_isGridMode)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.88,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        return _buildSanctuaryGridCard(
                          group: filtered[index],
                          totalFilteredPhotos: totalFilteredPhotos,
                          rank: index + 1,
                        );
                      },
                      childCount: filtered.length,
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        return _buildSanctuaryListTile(
                          group: filtered[index],
                          totalFilteredPhotos: totalFilteredPhotos,
                          rank: index + 1,
                        );
                      },
                      childCount: filtered.length,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // ── Hero Analytics Card ───────────────────────────────────────────────────

  Widget _buildHeroAnalyticsCard({
    required int totalPhotos,
    required int poojaPhotos,
    required int rashmikaPhotos,
    required int allGroupsCount,
  }) {
    final poojaFraction = totalPhotos > 0 ? (poojaPhotos / totalPhotos).clamp(0.0, 1.0) : 0.5;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1827),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: tabColor.withValues(alpha: 0.25),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: tabColor.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Total Sanctuary Count Row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      tabColor.withValues(alpha: 0.3),
                      tabColor.withValues(alpha: 0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.photo_library_rounded,
                  color: tabColor,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'TOTAL SANCTUARY PHOTOS',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 10,
                        letterSpacing: 1.0,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '$totalPhotos Total Photos',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$allGroupsCount Sanctuaries',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Proportional Split Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 6,
              child: Row(
                children: [
                  Expanded(
                    flex: (poojaFraction * 1000).toInt(),
                    child: Container(color: const Color(0xFFFFB300)), // Gold for Queen Pooja
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    flex: ((1.0 - poojaFraction) * 1000).toInt(),
                    child: Container(color: const Color(0xFFE91E63)), // Magenta for Queen Rashmika
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 8),

          // Queendom Stats Split Row
          Row(
            children: [
              // Queen Pooja
              Expanded(
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFFB300),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        'Pooja: $poojaPhotos (${(poojaFraction * 100).toStringAsFixed(0)}%)',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

              Container(width: 1, height: 16, color: Colors.white12),

              // Queen Rashmika
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFFE91E63),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          'Rashmika: $rashmikaPhotos (${((1.0 - poojaFraction) * 100).toStringAsFixed(0)}%)',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Search & Filter Controls ──────────────────────────────────────────────

  Widget _buildControlsSection({
    required int totalFilteredPhotos,
    required int filteredCount,
    required int allCount,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search Field
          Container(
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFF161322),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
                width: 1,
              ),
            ),
            child: TextField(
              controller: _searchController,
              textAlignVertical: TextAlignVertical.center,
              onChanged: (val) => setState(() => _searchQuery = val.trim()),
              style: const TextStyle(color: Colors.white, fontSize: 13.5),
              decoration: InputDecoration(
                hintText: 'Search sanctuary, queen, wife, fuck toy...',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 12.5),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: Colors.white54,
                  size: 19,
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 40,
                  minHeight: 42,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 16, color: Colors.white54),
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

          const SizedBox(height: 8),

          // Horizontal Filter Chips including >0 photos toggle
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                _buildCategoryChip('All'),
                const SizedBox(width: 6),
                _buildCategoryChip('Queen Pooja'),
                const SizedBox(width: 6),
                _buildCategoryChip('Queen Rashmika'),
                const SizedBox(width: 6),
                _buildCategoryChip('Wife'),
                const SizedBox(width: 6),
                _buildCategoryChip('Fuck Toy'),
                const SizedBox(width: 6),
                _buildOnlyWithPhotosChip(),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Header count & Sort Selector Row (Guaranteed No Overflow)
          Row(
            children: [
              // Photos header pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                decoration: BoxDecoration(
                  color: tabColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: tabColor.withValues(alpha: 0.35),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  '$totalFilteredPhotos Photos',
                  style: const TextStyle(
                    color: tabColor,
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'across $filteredCount ${filteredCount == 1 ? 'sanctuary' : 'sanctuaries'}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              // Sort Menu Button
              PopupMenuButton<String>(
                color: const Color(0xFF1F1B2E),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: Colors.white.withValues(alpha: 0.1),
                    width: 0.8,
                  ),
                ),
                onSelected: (val) => setState(() => _sortBy = val),
                itemBuilder: (context) => [
                  _buildSortMenuItem('Most Photos', Icons.arrow_downward_rounded),
                  _buildSortMenuItem('Least Photos', Icons.arrow_upward_rounded),
                  _buildSortMenuItem('Name (A-Z)', Icons.sort_by_alpha_rounded),
                  _buildSortMenuItem('Name (Z-A)', Icons.sort_by_alpha_rounded),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.swap_vert_rounded, size: 13, color: tabColor),
                      const SizedBox(width: 3),
                      Text(
                        _sortBy,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildOnlyWithPhotosChip() {
    return FilterChip(
      label: const Text('> 0 Photos'),
      selected: _onlyWithPhotos,
      onSelected: (val) => setState(() => _onlyWithPhotos = val),
      selectedColor: tabColor.withValues(alpha: 0.22),
      backgroundColor: Colors.white.withValues(alpha: 0.05),
      labelStyle: TextStyle(
        color: _onlyWithPhotos ? tabColor : Colors.white60,
        fontSize: 12,
        fontWeight: _onlyWithPhotos ? FontWeight.bold : FontWeight.normal,
      ),
      side: BorderSide(
        color: _onlyWithPhotos ? tabColor : Colors.white.withValues(alpha: 0.1),
        width: 1,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      showCheckmark: false,
    );
  }

  Widget _buildCategoryChip(String category) {
    final isSelected = _selectedCategory == category;
    return ChoiceChip(
      label: Text(category),
      selected: isSelected,
      onSelected: (_) => setState(() => _selectedCategory = category),
      selectedColor: tabColor.withValues(alpha: 0.22),
      backgroundColor: Colors.white.withValues(alpha: 0.05),
      labelStyle: TextStyle(
        color: isSelected ? tabColor : Colors.white70,
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      side: BorderSide(
        color: isSelected ? tabColor : Colors.white.withValues(alpha: 0.1),
        width: 1,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      showCheckmark: false,
    );
  }

  PopupMenuItem<String> _buildSortMenuItem(String title, IconData icon) {
    final isSelected = _sortBy == title;
    return PopupMenuItem<String>(
      value: title,
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: isSelected ? tabColor : Colors.white54,
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              color: isSelected ? tabColor : Colors.white,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  // ── Sanctuary List Tile ───────────────────────────────────────────────────

  Widget _buildSanctuaryListTile({
    required GroupModel group,
    required int totalFilteredPhotos,
    required int rank,
  }) {
    final count = group.galleryCount;
    final percent = totalFilteredPhotos > 0
        ? (count / totalFilteredPhotos * 100).toStringAsFixed(1)
        : '0.0';

    final isPooja = group.queendom == 'Queen Pooja';
    final queendomColor = isPooja ? const Color(0xFFFFB300) : const Color(0xFFE91E63);

    return InkWell(
      onTap: () => _openGroupGallery(group),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1B1827),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: count > 0
                ? queendomColor.withValues(alpha: 0.22)
                : Colors.white.withValues(alpha: 0.05),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            // Rank badge
            _buildRankBadge(rank),

            const SizedBox(width: 8),

            // Group Avatar
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: queendomColor.withValues(alpha: 0.6),
                  width: 1.5,
                ),
              ),
              child: UserAvatar(
                url: group.groupPic,
                radius: 20,
              ),
            ),

            const SizedBox(width: 10),

            // Sanctuary Name & Tags
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    group.nameWithPosition.isNotEmpty
                        ? group.nameWithPosition
                        : group.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      height: 1.25,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Queendom tag
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: queendomColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          group.queendom ?? 'Sanctuary',
                          style: TextStyle(
                            color: queendomColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      // Sub-group tag
                      if (group.isSubGroup) ...[
                        const SizedBox(width: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: Colors.purple.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            group.subGroupDisplayCategory,
                            style: const TextStyle(
                              color: Colors.purpleAccent,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(width: 8),

            // Prominent Photo Count Badge
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: count > 0
                          ? [
                              queendomColor.withValues(alpha: 0.25),
                              queendomColor.withValues(alpha: 0.1),
                            ]
                          : [
                              Colors.white.withValues(alpha: 0.08),
                              Colors.white.withValues(alpha: 0.04),
                            ],
                    ),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: count > 0
                          ? queendomColor.withValues(alpha: 0.4)
                          : Colors.white12,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    '$count photos',
                    style: TextStyle(
                      color: count > 0 ? Colors.white : Colors.white38,
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (count > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    '$percent%',
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),

            const SizedBox(width: 4),

            const Icon(
              Icons.chevron_right_rounded,
              color: Colors.white24,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  // ── Sanctuary Grid Card ───────────────────────────────────────────────────

  Widget _buildSanctuaryGridCard({
    required GroupModel group,
    required int totalFilteredPhotos,
    required int rank,
  }) {
    final count = group.galleryCount;
    final isPooja = group.queendom == 'Queen Pooja';
    final queendomColor = isPooja ? const Color(0xFFFFB300) : const Color(0xFFE91E63);

    return InkWell(
      onTap: () => _openGroupGallery(group),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1B1827),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: count > 0
                ? queendomColor.withValues(alpha: 0.28)
                : Colors.white.withValues(alpha: 0.06),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildRankBadge(rank),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: queendomColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    isPooja ? 'Pooja' : 'Rashmika',
                    style: TextStyle(
                      color: queendomColor,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Center(
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: queendomColor.withValues(alpha: 0.6),
                    width: 1.5,
                  ),
                ),
                child: UserAvatar(
                  url: group.groupPic,
                  radius: 26,
                ),
              ),
            ),
            const Spacer(),
            Text(
              group.nameWithPosition.isNotEmpty
                  ? group.nameWithPosition
                  : group.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.photo_library_outlined, size: 12, color: queendomColor),
                const SizedBox(width: 4),
                Text(
                  '$count photos',
                  style: TextStyle(
                    color: count > 0 ? Colors.white : Colors.white38,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRankBadge(int rank) {
    Color badgeColor = Colors.white24;
    Color textColor = Colors.white54;

    if (rank == 1) {
      badgeColor = const Color(0xFFFFD700); // Gold
      textColor = Colors.black;
    } else if (rank == 2) {
      badgeColor = const Color(0xFFC0C0C0); // Silver
      textColor = Colors.black;
    } else if (rank == 3) {
      badgeColor = const Color(0xFFCD7F32); // Bronze
      textColor = Colors.white;
    }

    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: badgeColor,
        shape: BoxShape.circle,
      ),
      child: Text(
        '$rank',
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.search_off_rounded,
                size: 40,
                color: Colors.white38,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'No Sanctuaries Match',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Try adjusting your search terms or filters.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _openGroupGallery(GroupModel group) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupGalleryScreen(
          groupId: group.groupId,
          groupName: group.nameWithPosition.isNotEmpty
              ? group.nameWithPosition
              : group.name,
          accentColor: group.queendom == 'Queen Pooja'
              ? const Color(0xFFFFB300)
              : tabColor,
        ),
      ),
    );
  }
}
