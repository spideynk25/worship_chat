import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/features/group/screens/slide_show_screen.dart';
import 'package:worship_chat/features/group/utils/multi_gallery_shuffler_helper.dart';
import 'package:worship_chat/models/group_gallery_image.dart';

/// Screen displaying a combined multi-gallery feed from multiple groups.
///
/// Supports 2 distinct viewing modes:
/// 1. [MultiGalleryMode.alternate]: Single photos strictly alternating across galleries.
/// 2. [MultiGalleryMode.sameSlide]: Displays one photo from every selected gallery together in the same slide.
class MultiGalleryShuffledScreen extends StatefulWidget {
  final List<GroupGalleryImage> images;
  final Map<String, String> groupNamesMap;
  final Color accentColor;
  final String title;
  final MultiGalleryMode initialMode;

  const MultiGalleryShuffledScreen({
    super.key,
    required this.images,
    required this.groupNamesMap,
    this.accentColor = tabColor,
    this.title = 'Multi-Gallery Shuffle',
    this.initialMode = MultiGalleryMode.alternate,
  });

  @override
  State<MultiGalleryShuffledScreen> createState() =>
      _MultiGalleryShuffledScreenState();
}

class _MultiGalleryShuffledScreenState
    extends State<MultiGalleryShuffledScreen> {
  late List<GroupGalleryImage> _shuffledImages;
  late List<MultiGallerySlideSet> _slideSets;
  late MultiGalleryMode _mode;
  String? _filterGroupId;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _shuffledImages = List.of(widget.images);
    _recomputeSlideSets();
  }

  void _recomputeSlideSets() {
    _slideSets = buildMultiGallerySlideSets(
      images: _shuffledImages,
      groupOrder: widget.groupNamesMap.keys.toList(),
    );
  }

  void _reshuffle() {
    HapticFeedback.lightImpact();
    setState(() {
      _shuffledImages = alternatePhotosAcrossGroups(_shuffledImages);
      _recomputeSlideSets();
    });
  }

  void _startSlideshow({int initialIndex = 0, MultiGalleryMode? mode}) {
    final targetMode = mode ?? _mode;
    final active = _activeImages;
    if (active.isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SlideshowScreen(
          images: active,
          initialIndex: initialIndex,
          accentColor: widget.accentColor,
          groupName: '${widget.title} (${active.length} Photos)',
          mode: targetMode,
          slideSets: _slideSets,
          groupNamesMap: widget.groupNamesMap,
        ),
      ),
    );
  }

  List<GroupGalleryImage> get _activeImages {
    if (_filterGroupId == null) return _shuffledImages;
    return _shuffledImages
        .where((img) => img.groupId == _filterGroupId)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final active = _activeImages;
    final totalGroups = widget.groupNamesMap.length;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0E17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161426),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16.5,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: widget.accentColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: widget.accentColor.withValues(alpha: 0.4),
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    '$totalGroups Groups',
                    style: TextStyle(
                      color: widget.accentColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '${active.length} photos • Alternate feed',
              style: TextStyle(color: Colors.grey[400], fontSize: 11.5),
            ),
          ],
        ),
        actions: const [],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44.0),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Reshuffle action
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.14),
                      width: 1,
                    ),
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.shuffle_rounded,
                        color: Colors.white, size: 20),
                    tooltip: 'Shuffle again (multi-shuffle)',
                    padding: EdgeInsets.zero,
                    onPressed: _reshuffle,
                  ),
                ),
                const SizedBox(width: 20),
                // Slideshow action
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.14),
                      width: 1,
                    ),
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.slideshow_rounded,
                        color: Colors.white, size: 20),
                    tooltip: 'Start slideshow',
                    padding: EdgeInsets.zero,
                    onPressed: () =>
                        _startSlideshow(mode: MultiGalleryMode.alternate),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // ── Filter by group chips ──
          if (widget.groupNamesMap.length > 1) ...[
            Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              color: const Color(0xFF161426),
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text('All (${_shuffledImages.length})'),
                      selected: _filterGroupId == null,
                      selectedColor: widget.accentColor.withValues(alpha: 0.25),
                      labelStyle: TextStyle(
                        color: _filterGroupId == null
                            ? widget.accentColor
                            : Colors.white60,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                      onSelected: (_) => setState(() => _filterGroupId = null),
                    ),
                  ),
                  ...widget.groupNamesMap.entries.map((entry) {
                    final isSelected = _filterGroupId == entry.key;
                    final groupCount = _shuffledImages
                        .where((img) => img.groupId == entry.key)
                        .length;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text('${entry.value} ($groupCount)'),
                        selected: isSelected,
                        selectedColor:
                            widget.accentColor.withValues(alpha: 0.25),
                        labelStyle: TextStyle(
                          color: isSelected
                              ? widget.accentColor
                              : Colors.white60,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                        onSelected: (_) =>
                            setState(() => _filterGroupId = entry.key),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],

          // ── Main Body: Clean Alternate Images Grid ──
          Expanded(
            child: _buildAlternateGridView(active),
          ),
        ],
      ),
    );
  }

  // ── 3-column Alternate Grid ───────────────────────────────────────────────

  Widget _buildAlternateGridView(List<GroupGalleryImage> active) {
    if (active.isEmpty) {
      return const Center(
        child: Text(
          'No photos found in selected multi-gallery',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
      ),
      itemCount: active.length,
      itemBuilder: (context, index) {
        final item = active[index];
        final groupName = widget.groupNamesMap[item.groupId] ?? '';

        return GestureDetector(
          onTap: () => _startSlideshow(
            initialIndex: index,
            mode: MultiGalleryMode.alternate,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              fit: StackFit.expand,
              children: [
                CachedNetworkImage(
                  imageUrl: item.imageUrl,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(
                    color: Colors.white10,
                    child: const Icon(Icons.broken_image,
                        color: Colors.white38),
                  ),
                ),
                if (groupName.isNotEmpty)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 2),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.black87,
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: Text(
                        groupName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
