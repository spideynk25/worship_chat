import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/utils/utils.dart';
import 'package:worship_chat/models/bookmark_collection_model.dart';

/// An Instagram-style collection card widget showing a collage of bookmarked photos,
/// collection name, item count, and an options menu.
class BookmarkCollectionCard extends StatelessWidget {
  final BookmarkCollectionModel? collection;
  final String title;
  final int count;
  final List<String> previewImageUrls;
  final VoidCallback onTap;
  final bool isAllBookmarks;
  final bool canManage;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  const BookmarkCollectionCard({
    super.key,
    this.collection,
    required this.title,
    required this.count,
    required this.previewImageUrls,
    required this.onTap,
    this.isAllBookmarks = false,
    this.canManage = false,
    this.onRename,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1B1728),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Instagram-Style Collage Cover ──
            Expanded(
              child: _buildCollageCover(),
            ),

            // ── Title & Meta Info ──
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            if (isAllBookmarks) ...[
                              const Icon(
                                Icons.bookmark_rounded,
                                size: 14,
                                color: tabColor,
                              ),
                              const SizedBox(width: 4),
                            ] else ...[
                              const Icon(
                                Icons.folder_rounded,
                                size: 14,
                                color: accentOrange,
                              ),
                              const SizedBox(width: 4),
                            ],
                            Expanded(
                              child: Text(
                                title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                maxLines: 1,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$count item${count == 1 ? '' : 's'}',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (canManage && !isAllBookmarks)
                    PopupMenuButton<String>(
                      icon: const Icon(
                        Icons.more_vert_rounded,
                        color: Colors.white70,
                        size: 18,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      color: const Color(0xFF242036),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      onSelected: (val) {
                        if (val == 'rename') onRename?.call();
                        if (val == 'delete') onDelete?.call();
                      },
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(
                          value: 'rename',
                          child: Row(
                            children: [
                              Icon(Icons.edit_rounded,
                                  color: Colors.white, size: 16),
                              SizedBox(width: 8),
                              Text('Edit Name',
                                  style: TextStyle(color: Colors.white, fontSize: 13)),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline_rounded,
                                  color: Colors.redAccent, size: 16),
                              SizedBox(width: 8),
                              Text('Delete Collection',
                                  style: TextStyle(
                                      color: Colors.redAccent, fontSize: 13)),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCollageCover() {
    final images = previewImageUrls.take(3).toList();

    if (images.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              tabColor.withValues(alpha: 0.25),
              const Color(0xFF171324),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Icon(
            isAllBookmarks
                ? Icons.bookmark_border_rounded
                : Icons.folder_open_rounded,
            size: 42,
            color: Colors.white24,
          ),
        ),
      );
    }

    if (images.length == 1) {
      return _buildImage(images[0]);
    }

    if (images.length == 2) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _buildImage(images[0])),
          const SizedBox(width: 1.5),
          Expanded(child: _buildImage(images[1])),
        ],
      );
    }

    // 3 or more: Signature Instagram layout (60% large left, 40% stacked right)
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 6,
          child: _buildImage(images[0]),
        ),
        const SizedBox(width: 1.5),
        Expanded(
          flex: 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _buildImage(images[1])),
              const SizedBox(height: 1.5),
              Expanded(child: _buildImage(images[2])),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildImage(String url) {
    return CachedNetworkImage(
      imageUrl: getOriginalHighQualityImageUrl(url),
      fit: BoxFit.cover,
      placeholder: (_, __) => Container(color: Colors.black26),
      errorWidget: (_, __, ___) => Container(
        color: Colors.black38,
        child: const Icon(Icons.broken_image_rounded, color: Colors.white24, size: 20),
      ),
    );
  }
}

