import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/utils/utils.dart';
import 'package:worship_chat/features/bookmark/controller/bookmark_controller.dart';
import 'package:worship_chat/models/bookmark_collection_model.dart';

/// Modal bottom sheet to save/organize a bookmark into collections (Instagram style).
class SaveToCollectionSheet extends ConsumerStatefulWidget {
  final String bookmarkId;
  final String imageUrl;
  final String userId;

  const SaveToCollectionSheet({
    super.key,
    required this.bookmarkId,
    required this.imageUrl,
    required this.userId,
  });

  static Future<void> show({
    required BuildContext context,
    required String bookmarkId,
    required String imageUrl,
    required String userId,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SaveToCollectionSheet(
        bookmarkId: bookmarkId,
        imageUrl: imageUrl,
        userId: userId,
      ),
    );
  }

  @override
  ConsumerState<SaveToCollectionSheet> createState() =>
      _SaveToCollectionSheetState();
}

class _SaveToCollectionSheetState extends ConsumerState<SaveToCollectionSheet> {
  final TextEditingController _newCollectionCtrl = TextEditingController();
  bool _isCreating = false;

  @override
  void dispose() {
    _newCollectionCtrl.dispose();
    super.dispose();
  }

  Future<void> _createNewCollection() async {
    final name = _newCollectionCtrl.text.trim();
    if (name.isEmpty) return;

    setState(() => _isCreating = true);
    final col = await ref.read(bookmarkControllerProvider).createCollection(
          name: name,
          initialBookmarkIds: [widget.bookmarkId],
          coverImageUrl: widget.imageUrl,
        );
    if (mounted) {
      setState(() {
        _isCreating = false;
        _newCollectionCtrl.clear();
      });
      if (col != null) {
        AppSnackBar.show(context, message: 'Created collection "${col.name}"');
      }
    }
  }

  void _showCreateDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1A2D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'New Collection',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: _newCollectionCtrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Collection name',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: tabColor, width: 2),
            ),
          ),
          onSubmitted: (_) {
            Navigator.pop(ctx);
            _createNewCollection();
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: tabColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _createNewCollection();
            },
            child: const Text('Create', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF161322),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl:
                          getOriginalHighQualityImageUrl(widget.imageUrl),
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Save to Collection',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Tap to add or remove from folders',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            const Divider(color: Colors.white12, height: 1),

            // "+ New Collection" Button Row
            ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: tabColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: tabColor.withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                ),
                child: const Icon(Icons.add_rounded, color: tabColor, size: 24),
              ),
              title: const Text(
                'New Collection',
                style: TextStyle(
                  color: tabColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              subtitle: const Text(
                'Create a new folder for this photo',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
              trailing: _isCreating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: tabColor,
                      ),
                    )
                  : null,
              onTap: _isCreating ? null : _showCreateDialog,
            ),

            const Divider(color: Colors.white10, height: 1),

            // Collections List
            Flexible(
              child: StreamBuilder<List<BookmarkCollectionModel>>(
                stream: ref
                    .watch(bookmarkControllerProvider)
                    .collectionsForUser(widget.userId),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(color: tabColor),
                      ),
                    );
                  }

                  final collections = snapshot.data ?? [];

                  if (collections.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.folder_open_rounded,
                            size: 48,
                            color: Colors.white.withValues(alpha: 0.3),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'No collections yet',
                            style: TextStyle(color: Colors.white70, fontSize: 14),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Tap "New Collection" above to create your first folder.',
                            style: TextStyle(color: Colors.white38, fontSize: 12),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: collections.length,
                    itemBuilder: (context, index) {
                      final col = collections[index];
                      final isSelected =
                          col.containsBookmark(widget.bookmarkId);

                      return ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFF242036),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.1),
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: col.coverImageUrl != null &&
                                  col.coverImageUrl!.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: getOriginalHighQualityImageUrl(
                                      col.coverImageUrl!),
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) => const Icon(
                                    Icons.folder_rounded,
                                    color: accentOrange,
                                    size: 20,
                                  ),
                                )
                              : const Icon(
                                  Icons.folder_rounded,
                                  color: accentOrange,
                                  size: 20,
                                ),
                        ),
                        title: Text(
                          col.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          '${col.count} item${col.count == 1 ? '' : 's'}',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                        ),
                        trailing: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSelected ? tabColor : Colors.transparent,
                            border: Border.all(
                              color: isSelected
                                  ? tabColor
                                  : Colors.white.withValues(alpha: 0.3),
                              width: 2,
                            ),
                          ),
                          child: isSelected
                              ? const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 16,
                                )
                              : null,
                        ),
                        onTap: () async {
                          await ref
                              .read(bookmarkControllerProvider)
                              .toggleBookmarkInCollection(
                                collectionId: col.id,
                                bookmarkId: widget.bookmarkId,
                                isInCollection: isSelected,
                              );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }
}

