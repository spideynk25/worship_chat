import 'dart:developer';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/utils/utils.dart';
import 'package:worship_chat/features/group/controller/group_controller.dart';
import 'package:worship_chat/features/group/repository/group_gallery_repository.dart';
import 'package:worship_chat/features/group/services/duplicate_detection_service.dart';
import 'package:worship_chat/features/group/widgets/duplicate_comparison_sheet.dart';
import 'package:worship_chat/models/group_gallery_image.dart';

class DuplicateFinderScreen extends ConsumerStatefulWidget {
  static const String routeName = '/duplicate-finder';

  final List<GroupGalleryImage>? initialImages;
  final String? groupId;
  final String? groupName;
  final Color accentColor;

  const DuplicateFinderScreen({
    super.key,
    this.initialImages,
    this.groupId,
    this.groupName,
    this.accentColor = tabColor,
  });

  @override
  ConsumerState<DuplicateFinderScreen> createState() =>
      _DuplicateFinderScreenState();
}

class _DuplicateFinderScreenState extends ConsumerState<DuplicateFinderScreen> {
  bool _isScanning = false;
  final ValueNotifier<DuplicateScanProgress?> _progressNotifier =
      ValueNotifier<DuplicateScanProgress?>(null);
  List<DuplicateCluster> _clusters = [];
  final Set<String> _selectedImageIds = {};
  String _activeFilter = 'All'; // 'All', 'Exact', 'Near'
  double _minSimilarity = 0.88;
  int _maxHammingDistance = 6;
  bool _deepPerceptualScan = true;
  final Map<String, String> _groupNames = {};

  final DateFormat _dateFormat = DateFormat('d MMM y, HH:mm');

  @override
  void dispose() {
    _progressNotifier.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startScan();
    });
  }

  Future<void> _startScan() async {
    if (_isScanning) return;

    _progressNotifier.value = const DuplicateScanProgress(
      phase: DuplicateScanPhase.preparing,
      current: 0,
      total: 0,
      clustersFound: 0,
      message: 'Initializing gallery scan...',
    );

    setState(() {
      _isScanning = true;
      _selectedImageIds.clear();
      _clusters.clear();
    });

    try {
      List<GroupGalleryImage> imagesToScan = [];

      if (widget.initialImages != null && widget.initialImages!.isNotEmpty) {
        imagesToScan = List.of(widget.initialImages!);
        if (widget.groupId != null && widget.groupName != null) {
          _groupNames[widget.groupId!] = widget.groupName!;
        }
      } else {
        // Fetch all user groups
        final groups = await ref.read(groupControllerProvider).getAllUserGroups().first;
        final groupIds = <String>[];
        for (final g in groups) {
          groupIds.add(g.groupId);
          _groupNames[g.groupId] = g.nameWithPosition;
        }

        if (groupIds.isNotEmpty) {
          final galleryRepo = ref.read(groupGalleryRepositoryProvider);
          imagesToScan = await galleryRepo.getMultiGalleryImages(groupIds);
        }
      }

      final clusters = await DuplicateDetectionService.scanForDuplicates(
        images: imagesToScan,
        minSimilarity: _minSimilarity,
        maxHammingDistance: _maxHammingDistance,
        deepPerceptualScan: _deepPerceptualScan,
        groupNames: _groupNames,
        onProgress: (p) {
          _progressNotifier.value = p;
        },
      );

      if (mounted) {
        setState(() {
          _clusters = clusters;
          _isScanning = false;
        });

        // Auto-select exact duplicates by default for easy review
        _autoSelectDuplicates(onlyExact: true);
      }
    } catch (e) {
      log('Error during duplicate scan: $e');
      if (mounted) {
        setState(() => _isScanning = false);
        showSnackBar(
          context: context,
          content: 'Scan encountered an issue: $e',
        );
      }
    }
  }

  void _autoSelectDuplicates({bool onlyExact = false}) {
    setState(() {
      _selectedImageIds.clear();
      for (final cluster in _clusters) {
        for (final dup in cluster.duplicates) {
          if (!onlyExact || dup.isExact) {
            _selectedImageIds.add(dup.image.imageId);
          }
        }
      }
    });
    HapticFeedback.lightImpact();
  }

  void _toggleSelectAllDuplicates() {
    setState(() {
      final allDuplicateIds = _clusters
          .expand((c) => c.duplicates.map((d) => d.image.imageId))
          .toSet();

      if (_selectedImageIds.containsAll(allDuplicateIds)) {
        _selectedImageIds.clear();
      } else {
        _selectedImageIds.addAll(allDuplicateIds);
      }
    });
    HapticFeedback.lightImpact();
  }

  List<DuplicateCluster> get _filteredClusters {
    if (_activeFilter == 'Exact') {
      return _clusters.where((c) => c.hasExactMatch).toList();
    } else if (_activeFilter == 'Near') {
      return _clusters.where((c) => !c.hasExactMatch).toList();
    }
    return _clusters;
  }

  int get _totalDuplicatesCount {
    return _clusters.fold<int>(0, (sum, c) => sum + c.duplicates.length);
  }

  int get _exactDuplicatesCount {
    return _clusters.fold<int>(
      0,
      (sum, c) => sum + c.duplicates.where((d) => d.isExact).length,
    );
  }

  int get _nearDuplicatesCount {
    return _clusters.fold<int>(
      0,
      (sum, c) => sum + c.duplicates.where((d) => !d.isExact).length,
    );
  }

  Future<void> _deleteSelectedDuplicates() async {
    if (_selectedImageIds.isEmpty) return;

    final count = _selectedImageIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B1827),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: widget.accentColor.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        title: Row(
          children: [
            const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent),
            const SizedBox(width: 10),
            Text('Delete $count Duplicates?'),
          ],
        ),
        content: Text(
          'This will permanently remove $count duplicate photo(s) from their respective galleries.\n\nThe original keeper photos will not be touched.',
          style: const TextStyle(color: Colors.white70, fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final toDelete = Set<String>.of(_selectedImageIds);
    final repo = ref.read(groupGalleryRepositoryProvider);

    int deletedCount = 0;
    // Map imageId -> groupId
    final imageToGroup = <String, String>{};
    for (final cluster in _clusters) {
      for (final dup in cluster.duplicates) {
        imageToGroup[dup.image.imageId] = dup.image.groupId;
      }
    }

    setState(() => _isScanning = true);

    for (final imgId in toDelete) {
      final gId = imageToGroup[imgId];
      if (gId != null) {
        try {
          await repo.deleteImage(gId, imgId);
          deletedCount++;
        } catch (e) {
          log('Error deleting duplicate $imgId: $e');
        }
      }
    }

    if (mounted) {
      setState(() {
        _selectedImageIds.clear();
        // Remove deleted items from clusters
        _clusters = _clusters
            .map((c) {
              final remainingDups =
                  c.duplicates.where((d) => !toDelete.contains(d.image.imageId)).toList();
              return DuplicateCluster(
                clusterId: c.clusterId,
                canonical: c.canonical,
                duplicates: remainingDups,
                canonicalGroupName: c.canonicalGroupName,
              );
            })
            .where((c) => c.duplicates.isNotEmpty)
            .toList();
        _isScanning = false;
      });

      showSnackBar(
        context: context,
        content: '✅ Removed $deletedCount duplicate photo(s).',
      );
    }
  }

  void _openComparison(GroupGalleryImage canonical, DuplicateItem item, String? canonicalGroup) {
    DuplicateComparisonSheet.show(
      context: context,
      canonical: canonical,
      duplicateItem: item,
      canonicalGroupName: canonicalGroup,
      onDeleteDuplicate: () async {
        final repo = ref.read(groupGalleryRepositoryProvider);
        await repo.deleteImage(item.image.groupId, item.image.imageId);
        if (mounted) {
          setState(() {
            _selectedImageIds.remove(item.image.imageId);
            _clusters = _clusters
                .map((c) {
                  return DuplicateCluster(
                    clusterId: c.clusterId,
                    canonical: c.canonical,
                    duplicates: c.duplicates
                        .where((d) => d.image.imageId != item.image.imageId)
                        .toList(),
                    canonicalGroupName: c.canonicalGroupName,
                  );
                })
                .where((c) => c.duplicates.isNotEmpty)
                .toList();
          });
          showSnackBar(context: context, content: '✅ Duplicate photo removed.');
        }
      },
      onKeepBoth: () {
        setState(() {
          _selectedImageIds.remove(item.image.imageId);
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.groupName != null
        ? '${widget.groupName} Duplicates'
        : 'Smart Duplicate Finder';

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: appBarColor,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(
                color: widget.accentColor,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              _isScanning
                  ? 'Scanning in progress...'
                  : '$_totalDuplicatesCount duplicate(s) in ${_clusters.length} sets',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Rescan',
            onPressed: _isScanning ? null : _startScan,
          ),
          IconButton(
            icon: const Icon(Icons.tune_rounded),
            tooltip: 'Detection Settings',
            onPressed: _showSettingsDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Progress Header ──────────────────────────────────────────────
          if (_isScanning)
            _buildScanningHeader()
          else
            _buildSummaryHeader(),

          // ── Filter Chips Bar ─────────────────────────────────────────────
          if (!_isScanning && _clusters.isNotEmpty)
            _buildFilterBar(),

          // ── Cluster List or Empty State ──────────────────────────────────
          Expanded(
            child: _isScanning && _clusters.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(color: tabColor),
                  )
                : _filteredClusters.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                        itemCount: _filteredClusters.length,
                        itemBuilder: (context, index) {
                          return _buildClusterCard(_filteredClusters[index]);
                        },
                      ),
          ),
        ],
      ),
      bottomNavigationBar: (!_isScanning && _clusters.isNotEmpty)
          ? _buildBottomActionBar()
          : null,
    );
  }

  Widget _buildScanningHeader() {
    return ValueListenableBuilder<DuplicateScanProgress?>(
      valueListenable: _progressNotifier,
      builder: (context, progress, _) {
        final fraction = progress?.fraction ?? 0.0;
        final message = progress?.message ?? 'Scanning...';

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1B1827),
            border: Border(
              bottom: BorderSide(
                color: widget.accentColor.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: widget.accentColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${(fraction * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      color: widget.accentColor,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: fraction > 0 ? fraction : null,
                  backgroundColor: Colors.white12,
                  color: widget.accentColor,
                  minHeight: 4,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSummaryHeader() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1827),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.accentColor.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem(
            label: 'Duplicate Sets',
            val: '${_clusters.length}',
            icon: Icons.copy_rounded,
            color: widget.accentColor,
          ),
          Container(width: 1, height: 32, color: Colors.white12),
          _buildStatItem(
            label: 'Exact (100%)',
            val: '$_exactDuplicatesCount',
            icon: Icons.check_circle_outline_rounded,
            color: Colors.greenAccent,
          ),
          Container(width: 1, height: 32, color: Colors.white12),
          _buildStatItem(
            label: 'Near (dHash)',
            val: '$_nearDuplicatesCount',
            icon: Icons.auto_awesome_rounded,
            color: Colors.orangeAccent,
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required String label,
    required String val,
    required IconData icon,
    required Color color,
  }) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              val,
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _buildFilterChip('All', _clusters.length),
          const SizedBox(width: 8),
          _buildFilterChip('Exact', _clusters.where((c) => c.hasExactMatch).length),
          const SizedBox(width: 8),
          _buildFilterChip('Near', _clusters.where((c) => !c.hasExactMatch).length),
          const Spacer(),
          TextButton.icon(
            onPressed: _toggleSelectAllDuplicates,
            icon: Icon(
              _selectedImageIds.isEmpty
                  ? Icons.select_all_rounded
                  : Icons.deselect_rounded,
              size: 16,
              color: widget.accentColor,
            ),
            label: Text(
              _selectedImageIds.isEmpty ? 'Select All' : 'Clear',
              style: TextStyle(
                color: widget.accentColor,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String filter, int count) {
    final isSelected = _activeFilter == filter;
    return InkWell(
      onTap: () => setState(() => _activeFilter = filter),
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? widget.accentColor.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? widget.accentColor
                : Colors.white.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
        child: Text(
          '$filter ($count)',
          style: TextStyle(
            color: isSelected ? widget.accentColor : Colors.white70,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildClusterCard(DuplicateCluster cluster) {
    final canonical = cluster.canonical;
    final duplicates = cluster.duplicates;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1827),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cluster.hasExactMatch
              ? Colors.green.withValues(alpha: 0.3)
              : Colors.orange.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Cluster Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: cluster.hasExactMatch
                  ? Colors.green.withValues(alpha: 0.08)
                  : Colors.orange.withValues(alpha: 0.08),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(15)),
            ),
            child: Row(
              children: [
                Icon(
                  cluster.hasExactMatch
                      ? Icons.check_circle_rounded
                      : Icons.auto_awesome_rounded,
                  size: 15,
                  color: cluster.hasExactMatch
                      ? Colors.greenAccent
                      : Colors.orangeAccent,
                ),
                const SizedBox(width: 8),
                Text(
                  cluster.hasExactMatch
                      ? 'Exact Match (100%)'
                      : 'Visual Match (${(cluster.highestSimilarity * 100).toStringAsFixed(0)}%)',
                  style: TextStyle(
                    color: cluster.hasExactMatch
                        ? Colors.greenAccent
                        : Colors.orangeAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  '${cluster.totalImages} photos',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Canonical "Keeper" row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: CachedNetworkImage(
                            imageUrl: canonical.imageUrl,
                            width: 72,
                            height: 72,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(
                              width: 72,
                              height: 72,
                              color: Colors.black26,
                            ),
                          ),
                        ),
                        Positioned(
                          top: 4,
                          left: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: tabColor,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              '👑 Keeper',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            cluster.canonicalGroupName ?? 'Original Photo',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Uploaded ${_dateFormat.format(canonical.uploadedAt)}',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                          if (canonical.uploadedByName.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              'By ${canonical.uploadedByName}',
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),

                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Divider(color: Colors.white10, height: 1),
                ),

                const Text(
                  'Duplicates in this set:',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),

                // Duplicates list
                for (final dup in duplicates) ...[
                  _buildDuplicateItemRow(cluster.canonical, dup, cluster.canonicalGroupName),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDuplicateItemRow(
    GroupGalleryImage canonical,
    DuplicateItem dup,
    String? canonicalGroup,
  ) {
    final isSelected = _selectedImageIds.contains(dup.image.imageId);

    return InkWell(
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedImageIds.remove(dup.image.imageId);
          } else {
            _selectedImageIds.add(dup.image.imageId);
          }
        });
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.redAccent.withValues(alpha: 0.1)
              : Colors.black26,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? Colors.redAccent.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.05),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Checkbox(
              value: isSelected,
              activeColor: Colors.redAccent,
              checkColor: Colors.white,
              onChanged: (val) {
                setState(() {
                  if (val == true) {
                    _selectedImageIds.add(dup.image.imageId);
                  } else {
                    _selectedImageIds.remove(dup.image.imageId);
                  }
                });
              },
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: dup.image.imageUrl,
                width: 52,
                height: 52,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  width: 52,
                  height: 52,
                  color: Colors.black26,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: dup.isExact
                              ? Colors.green.withValues(alpha: 0.15)
                              : Colors.orange.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          dup.matchLabel,
                          style: TextStyle(
                            color: dup.isExact
                                ? Colors.greenAccent
                                : Colors.orangeAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    dup.groupName ?? _dateFormat.format(dup.image.uploadedAt),
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.compare_rounded, size: 18, color: tabColor),
              tooltip: 'Compare side-by-side',
              onPressed: () => _openComparison(canonical, dup, canonicalGroup),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_outline_rounded,
              size: 48,
              color: Colors.greenAccent,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'No Duplicates Found',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Your gallery is completely clean with no identical or visual clone photos.',
              style: TextStyle(color: Colors.white54, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomActionBar() {
    final count = _selectedImageIds.length;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: const BoxDecoration(
        color: Color(0xFF13111C),
        border: Border(top: BorderSide(color: Colors.white12, width: 0.8)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => _autoSelectDuplicates(onlyExact: false),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: widget.accentColor.withValues(alpha: 0.4)),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Auto-Select All',
                style: TextStyle(
                  color: widget.accentColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: count > 0 ? _deleteSelectedDuplicates : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent.shade700,
                disabledBackgroundColor: Colors.white12,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.delete_sweep_rounded, size: 18),
              label: Text(
                count > 0 ? 'Delete ($count)' : 'Delete (0)',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1B1827),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              color: widget.accentColor.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          title: const Text('Duplicate Detection Sensitivity'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Visual Similarity Threshold:',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Slider(
                value: _minSimilarity,
                min: 0.80,
                max: 0.98,
                divisions: 9,
                activeColor: widget.accentColor,
                label: '${(_minSimilarity * 100).toStringAsFixed(0)}%',
                onChanged: (val) {
                  setDialogState(() {
                    _minSimilarity = val;
                    _maxHammingDistance = ((1.0 - val) * 64).round();
                  });
                  setState(() {});
                },
              ),
              Center(
                child: Text(
                  '${(_minSimilarity * 100).toStringAsFixed(0)}% Visual Match (dHash diff: <= $_maxHammingDistance bits)',
                  style: TextStyle(
                    color: widget.accentColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeTrackColor: widget.accentColor.withValues(alpha: 0.5),
                title: const Text(
                  'Deep Perceptual Scan',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
                subtitle: const Text(
                  'Computes visual 64-bit dHash on non-exact images',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
                value: _deepPerceptualScan,
                onChanged: (val) {
                  setDialogState(() => _deepPerceptualScan = val);
                  setState(() {});
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _startScan();
              },
              child: const Text('Apply & Rescan'),
            ),
          ],
        ),
      ),
    );
  }
}
