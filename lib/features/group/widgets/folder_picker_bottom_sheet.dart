import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/features/group/screens/folder_gallery_screen.dart';
import 'package:worship_chat/features/group/services/recent_folders_service.dart';

/// Interactive bottom sheet allowing users to decide whether to open a standard
/// device folder or a ZIP archive, as well as pick from recently opened items.
class FolderPickerBottomSheet extends StatefulWidget {
  final Color accentColor;

  const FolderPickerBottomSheet({
    super.key,
    this.accentColor = tabColor,
  });

  /// Displays the [FolderPickerBottomSheet] as a modal bottom sheet.
  static Future<void> show(
    BuildContext context, {
    Color accentColor = tabColor,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FolderPickerBottomSheet(accentColor: accentColor),
    );
  }

  @override
  State<FolderPickerBottomSheet> createState() =>
      _FolderPickerBottomSheetState();
}

class _FolderPickerBottomSheetState extends State<FolderPickerBottomSheet> {
  List<RecentFolderItem> _recentFolders = [];
  bool _isLoadingRecents = true;

  @override
  void initState() {
    super.initState();
    _loadRecents();
  }

  Future<void> _loadRecents() async {
    final items = await RecentFoldersService.getRecentFolders();
    if (mounted) {
      setState(() {
        _recentFolders = items;
        _isLoadingRecents = false;
      });
    }
  }

  void _openFolder() {
    HapticFeedback.lightImpact();
    Navigator.pop(context);
    FolderGalleryScreen.openFolder(context, accentColor: widget.accentColor);
  }

  void _openZipArchive() {
    HapticFeedback.lightImpact();
    Navigator.pop(context);
    FolderGalleryScreen.openZipArchive(context, accentColor: widget.accentColor);
  }

  void _openRecent(RecentFolderItem item) {
    HapticFeedback.lightImpact();
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FolderGalleryScreen(
          initialFolderPath: item.path,
          accentColor: widget.accentColor,
        ),
      ),
    );
  }

  void _openGalleryHub() {
    HapticFeedback.lightImpact();
    Navigator.pop(context);
    FolderGalleryScreen.open(context, accentColor: widget.accentColor);
  }

  Future<void> _removeRecent(String path) async {
    HapticFeedback.selectionClick();
    await RecentFoldersService.removeRecentFolder(path);
    await _loadRecents();
  }

  Future<void> _clearAllRecents() async {
    HapticFeedback.mediumImpact();
    await RecentFoldersService.clearRecentFolders();
    await _loadRecents();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final maxHeight = mediaQuery.size.height * 0.85;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: const Color(0xFF161524),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Drag Handle Pill ──────────────────────────────────────────
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // ── Header Row ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 16, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: widget.accentColor.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.photo_library_rounded,
                      size: 20,
                      color: widget.accentColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Local Gallery Storage',
                          style: TextStyle(
                            color: textColor,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                        SizedBox(height: 1),
                        Text(
                          'Choose whether to browse a folder or a ZIP file',
                          style: TextStyle(
                            color: greyColor,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: greyColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const Divider(color: Colors.white10, height: 1),

            // ── Scrollable Body ───────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Primary Action Options (Folder vs ZIP) ────────────
                    _buildOptionCard(
                      icon: Icons.folder_open_rounded,
                      iconGradient: const [
                        Color(0xFF2979FF),
                        Color(0xFF00B0FF),
                      ],
                      title: 'Open Device Folder',
                      subtitle: 'Browse uncompressed photos directory on your storage',
                      badge: 'Folder',
                      badgeColor: const Color(0xFF2979FF),
                      onTap: _openFolder,
                    ),
                    const SizedBox(height: 12),
                    _buildOptionCard(
                      icon: Icons.folder_zip_rounded,
                      iconGradient: const [
                        Color(0xFF9C27B0),
                        Color(0xFFFF2D78),
                      ],
                      title: 'Open ZIP Archive',
                      subtitle: 'Directly extract & view photos from a .zip file',
                      badge: 'ZIP',
                      badgeColor: const Color(0xFFFF2D78),
                      onTap: _openZipArchive,
                    ),

                    const SizedBox(height: 24),

                    // ── Recently Opened Section ───────────────────────────
                    Row(
                      children: [
                        Icon(
                          Icons.history_rounded,
                          size: 18,
                          color: widget.accentColor,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _recentFolders.isNotEmpty
                              ? 'Recently Opened (${_recentFolders.length})'
                              : 'Recently Opened',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        if (_recentFolders.isNotEmpty)
                          GestureDetector(
                            onTap: _clearAllRecents,
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 4,
                              ),
                              child: Text(
                                'Clear all',
                                style: TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    if (_isLoadingRecents)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          ),
                        ),
                      )
                    else if (_recentFolders.isEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 20,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.06),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.folder_outlined,
                              size: 28,
                              color: Colors.white.withValues(alpha: 0.3),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'No recent folders yet',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.8),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Folders & ZIPs you open will appear here for 1-tap access.',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.45),
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _recentFolders.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = _recentFolders[index];
                          return _buildRecentItemTile(item);
                        },
                      ),

                    const SizedBox(height: 18),

                    // ── Open Hub Button ───────────────────────────────────
                    OutlinedButton.icon(
                      onPressed: _openGalleryHub,
                      icon: Icon(
                        Icons.dashboard_customize_rounded,
                        size: 17,
                        color: widget.accentColor,
                      ),
                      label: Text(
                        'Open Gallery Hub & Multi-Shuffle',
                        style: TextStyle(
                          color: widget.accentColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: widget.accentColor.withValues(alpha: 0.35),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionCard({
    required IconData icon,
    required List<Color> iconGradient,
    required String title,
    required String subtitle,
    required String badge,
    required Color badgeColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1A2E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: iconGradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: iconGradient.first.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(
                  icon,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: badgeColor.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: badgeColor.withValues(alpha: 0.4),
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            badge,
                            style: TextStyle(
                              color: badgeColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: Colors.white.withValues(alpha: 0.3),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentItemTile(RecentFolderItem item) {
    final isZip = item.isZip;
    final itemColor = isZip ? const Color(0xFFE040FB) : const Color(0xFF64B5F6);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openRecent(item),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF1B1728),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.06),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: itemColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: itemColor.withValues(alpha: 0.3),
                    width: 0.8,
                  ),
                ),
                child: Icon(
                  isZip ? Icons.folder_zip_rounded : Icons.folder_rounded,
                  color: itemColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            item.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isZip) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE040FB).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'ZIP',
                              style: TextStyle(
                                color: Color(0xFFE040FB),
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.path,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: Colors.white38,
                ),
                tooltip: 'Remove from recents',
                splashRadius: 18,
                onPressed: () => _removeRecent(item.path),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
