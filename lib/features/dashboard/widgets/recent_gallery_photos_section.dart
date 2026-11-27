import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/utils/utils.dart';
import 'package:worship_chat/features/group/controller/group_controller.dart';
import 'package:worship_chat/features/group/controller/group_gallery_controller.dart';
import 'package:worship_chat/features/group/screens/group_gallery_screen.dart';
import 'package:worship_chat/features/group/screens/recent_gallery_photos_screen.dart';
import 'package:worship_chat/features/settings/models/queendom_customization_model.dart';
import 'package:worship_chat/features/settings/providers/queendom_customization_provider.dart';
import 'package:worship_chat/models/group.dart';
import 'package:worship_chat/models/group_gallery_image.dart';
import 'package:worship_chat/models/user_model.dart';

/// Displays an interactive strip of recently added photos across the user's
/// group galleries directly beneath Group Shortcuts on the Chats screen.
class RecentGalleryPhotosSection extends ConsumerStatefulWidget {
  final String currentUserId;

  /// Optional test overrides to inject groups/photos without touching Firestore.
  @visibleForTesting
  final List<GroupModel>? overrideGroups;

  @visibleForTesting
  final List<GroupGalleryImage>? overrideImages;

  const RecentGalleryPhotosSection({
    super.key,
    required this.currentUserId,
    this.overrideGroups,
    this.overrideImages,
  });

  @override
  RecentGalleryPhotosSectionState createState() =>
      RecentGalleryPhotosSectionState();
}

class RecentGalleryPhotosSectionState
    extends ConsumerState<RecentGalleryPhotosSection> {
  static const int _stripLimit = 18;
  static const String _prefExpandedPrefix =
      'show_recent_gallery_under_shortcuts_v1_';

  List<GroupGalleryImage> _photos = const [];
  bool _isExpanded = true;
  bool _isLoading = false;
  bool _hasFetchedOnce = false;
  String _lastGallerySignature = '';
  List<GroupModel> _latestGroups = const [];

  String get _effectiveUid {
    if (widget.currentUserId.trim().isNotEmpty) {
      return widget.currentUserId.trim();
    }
    try {
      final authUid = FirebaseAuth.instance.currentUser?.uid;
      if (authUid != null && authUid.isNotEmpty) return authUid;
    } catch (_) {}
    try {
      if (Hive.isBoxOpen('userBox')) {
        final user = Hive.box<UserModel>('userBox').get('currentUser');
        if (user?.uid != null && user!.uid!.isNotEmpty) {
          return user.uid!;
        }
      }
    } catch (_) {}
    return '';
  }

  String get _expandedPrefKey {
    final uid = _effectiveUid;
    return uid.isNotEmpty
        ? '$_prefExpandedPrefix$uid'
        : '${_prefExpandedPrefix}default';
  }

  @override
  void initState() {
    super.initState();
    if (widget.overrideImages != null) {
      _photos = List<GroupGalleryImage>.of(widget.overrideImages!);
      _hasFetchedOnce = true;
    } else {
      _loadLocalPreferencesAndCache();
    }
  }

  @override
  void didUpdateWidget(covariant RecentGalleryPhotosSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.overrideImages != null &&
        widget.overrideImages != oldWidget.overrideImages) {
      setState(() {
        _photos = List<GroupGalleryImage>.of(widget.overrideImages!);
        _hasFetchedOnce = true;
      });
    } else if (oldWidget.currentUserId != widget.currentUserId &&
        widget.overrideImages == null) {
      _lastGallerySignature = '';
      _loadLocalPreferencesAndCache();
    }
  }

  Future<void> _loadLocalPreferencesAndCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedExpanded = prefs.getBool(_expandedPrefKey);
      if (mounted && savedExpanded != null) {
        setState(() => _isExpanded = savedExpanded);
      }
    } catch (_) {}

    if (widget.overrideImages != null) return;
    final uid = _effectiveUid;
    if (uid.isEmpty) return;

    final cached = await ref
        .read(groupGalleryControllerProvider)
        .getCachedRecentGalleryPhotos(uid);
    if (!mounted) return;
    if (cached.isNotEmpty && _photos.isEmpty) {
      setState(() => _photos = cached.take(_stripLimit).toList());
    }
  }

  Future<void> _toggleExpanded() async {
    HapticFeedback.selectionClick();
    final next = !_isExpanded;
    setState(() => _isExpanded = next);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_expandedPrefKey, next);
    } catch (_) {}
    if (next && _latestGroups.isNotEmpty && !_hasFetchedOnce) {
      _fetchRecentPhotos(_latestGroups);
    }
  }

  String _computeSignature(List<GroupModel> groups) {
    final items = groups
        .where((g) => g.groupId.isNotEmpty)
        .map(
          (g) =>
              '${g.groupId}:${g.galleryCount}:${g.lastGalleryUpdate?.millisecondsSinceEpoch ?? 0}',
        )
        .toList()
      ..sort();
    return items.join('|');
  }

  void _scheduleSyncForGroups(List<GroupModel> groups) {
    _latestGroups = groups;
    if (widget.overrideImages != null || groups.isEmpty) return;
    final sig = _computeSignature(groups);
    if (sig == _lastGallerySignature && _hasFetchedOnce) return;
    _lastGallerySignature = sig;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _fetchRecentPhotos(groups);
      }
    });
  }

  /// Triggers a fresh fetch of recent gallery photos for pull-to-refresh.
  Future<void> refresh() => _fetchRecentPhotos(_latestGroups);

  Future<void> _fetchRecentPhotos(List<GroupModel> groups) async {
    if (_isLoading || widget.overrideImages != null || groups.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      final fetched = await ref
          .read(groupGalleryControllerProvider)
          .getRecentGalleryPhotos(
            groups: groups,
            limit: _stripLimit,
            limitPerGroup: 6,
            maxGroupsToQuery: 16,
            photosOnly: true,
            saveCache: true,
          );
      if (!mounted) return;
      setState(() {
        _photos = fetched;
        _hasFetchedOnce = true;
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _openPhotoViewer(int index, List<GroupModel> groups) {
    final groupsById = <String, GroupModel>{
      for (final g in groups)
        if (g.groupId.isNotEmpty) g.groupId: g,
    };
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RecentPhotoViewerScreen(
          images: _photos,
          initialIndex: index,
          groupsById: groupsById,
        ),
      ),
    );
  }

  void _openOriginGroupGallery(
    GroupModel group,
    QueendomCustomizationState? customization,
  ) {
    final accent = resolveGroupAccentColor(group, customization);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupGalleryScreen(
          groupId: group.groupId,
          groupName: group.nameWithPosition,
          accentColor: accent,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.overrideGroups != null) {
      final groups = widget.overrideGroups!;
      _latestGroups = groups;
      return _buildSection(context, groups, null);
    }

    final controller = ref.watch(groupControllerProvider);
    final customization = ref.watch(queendomCustomizationProvider);
    final cachedPooja = controller.getCachedGroups('groups_pooja');
    final cachedRashmika = controller.getCachedGroups('groups_rashmika');
    final cachedGroups = [...cachedPooja, ...cachedRashmika];

    final mergedStream =
        Rx.combineLatest2<List<GroupModel>, List<GroupModel>, List<GroupModel>>(
      controller.getQueenPoojaStream(),
      controller.getQueenRashmikaStream(),
      (poojaGroups, rashmikaGroups) => [...poojaGroups, ...rashmikaGroups],
    );

    return StreamBuilder<List<GroupModel>>(
      initialData: cachedGroups.isNotEmpty ? cachedGroups : null,
      stream: mergedStream,
      builder: (context, snapshot) {
        final groups = snapshot.data ?? cachedGroups;
        if (groups.isEmpty) {
          return const SizedBox.shrink();
        }
        _scheduleSyncForGroups(groups);
        return _buildSection(context, groups, customization);
      },
    );
  }

  Widget _buildSection(
    BuildContext context,
    List<GroupModel> groups,
    QueendomCustomizationState? customization,
  ) {
    final groupsById = <String, GroupModel>{
      for (final g in groups)
        if (g.groupId.isNotEmpty) g.groupId: g,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header Row ─────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: _toggleExpanded,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: const Color(0xFF00E5FF)
                                  .withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(
                              Icons.photo_library_rounded,
                              color: Color(0xFF00E5FF),
                              size: 13,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'RECENT GALLERY PHOTOS',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ),
                          if (_photos.isNotEmpty) ...[
                            const SizedBox(width: 6),
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
                                '${_photos.length}',
                                style: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(width: 2),
                          Icon(
                            _isExpanded
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.keyboard_arrow_down_rounded,
                            color: Colors.grey[500],
                            size: 16,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Refresh recent photos',
                onPressed: _isLoading
                    ? null
                    : () {
                        HapticFeedback.selectionClick();
                        _fetchRecentPhotos(groups);
                      },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                icon: _isLoading
                    ? const SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.8,
                          color: Color(0xFF00E5FF),
                        ),
                      )
                    : Icon(
                        Icons.refresh_rounded,
                        color: Colors.grey[400],
                        size: 16,
                      ),
              ),
            ],
          ),

          if (!_isExpanded) ...[
            const SizedBox(height: 6),
            Material(
              color: mobileChatBoxColor,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _toggleExpanded,
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: dividerColor),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.photo_library_outlined,
                        color: Color(0xFF00E5FF),
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _photos.isNotEmpty
                              ? 'Tap to view ${_photos.length} recently added gallery photos'
                              : 'Tap to expand recently added gallery photos',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.expand_more_rounded,
                        color: Colors.white54,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 10),
            if (_isLoading && _photos.isEmpty)
              _buildLoadingStrip()
            else if (_photos.isEmpty)
              _buildEmptyCard(groups)
            else
              _buildPhotosStrip(context, groups, groupsById, customization),
          ],
        ],
      ),
    );
  }

  Widget _buildLoadingStrip() {
    return SizedBox(
      height: 144,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: 4,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, __) => Container(
          width: 110,
          decoration: BoxDecoration(
            color: mobileChatBoxColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: dividerColor),
          ),
          child: Center(
            child: Icon(
              Icons.image_outlined,
              color: Colors.grey[700],
              size: 24,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyCard(List<GroupModel> groups) {
    return GestureDetector(
      onTap: () => _fetchRecentPhotos(groups),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
        decoration: BoxDecoration(
          color: mobileChatBoxColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: dividerColor),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF00E5FF).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.photo_library_outlined,
                color: Color(0xFF00E5FF),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'No recent gallery photos yet',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'New photos added to group galleries appear here',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey[500], fontSize: 11.5),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.refresh_rounded,
              color: Colors.grey[500],
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotosStrip(
    BuildContext context,
    List<GroupModel> groups,
    Map<String, GroupModel> groupsById,
    QueendomCustomizationState? customization,
  ) {
    return SizedBox(
      height: 148,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _photos.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final photo = _photos[index];
          final group = groupsById[photo.groupId];
          final accent = resolveGroupAccentColor(group, customization);
          final thumbUrl = getOptimizedRoleplayImageUrl(
            photo.imageUrl,
            width: 340,
          );

          return GestureDetector(
            onTap: () => _openPhotoViewer(index, groups),
            onLongPress: group != null
                ? () {
                    HapticFeedback.mediumImpact();
                    _openOriginGroupGallery(group, customization);
                  }
                : null,
            child: Container(
              width: 110,
              decoration: BoxDecoration(
                color: mobileChatBoxColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: accent.withValues(alpha: 0.35),
                  width: 1.1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.32),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Hero(
                      tag: 'recent_gallery_${photo.imageId}',
                      child: CachedNetworkImage(
                        imageUrl: thumbUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          color: const Color(0xFF1F1F2E),
                          child: Center(
                            child: Icon(
                              Icons.image_outlined,
                              color: Colors.grey[700],
                              size: 22,
                            ),
                          ),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          color: const Color(0xFF1F1F2E),
                          child: const Icon(
                            Icons.broken_image_outlined,
                            color: Colors.white38,
                          ),
                        ),
                      ),
                    ),

                    // Relative time pill (top-left)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.68),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          formatRecentGalleryTimeAgo(photo.uploadedAt),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),

                    // Optional small circular group badge bottom-right (no name text)
                    if (group != null && group.groupPic.trim().isNotEmpty)
                      Positioned(
                        bottom: 6,
                        right: 6,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _openOriginGroupGallery(
                            group,
                            customization,
                          ),
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: accent,
                                width: 1.2,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black54,
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: CachedNetworkImage(
                                imageUrl: group.groupPic,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => Container(
                                  color: accent.withValues(alpha: 0.3),
                                ),
                              ),
                            ),
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
}
