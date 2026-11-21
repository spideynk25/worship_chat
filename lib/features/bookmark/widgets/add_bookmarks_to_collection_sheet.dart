import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/utils/utils.dart';
import 'package:worship_chat/features/bookmark/controller/bookmark_controller.dart';
import 'package:worship_chat/models/bookmark_collection_model.dart';
import 'package:worship_chat/models/bookmark_model.dart';

/// Multi-select sheet to add existing bookmarks into a collection (Instagram style).
class AddBookmarksToCollectionSheet extends ConsumerStatefulWidget {
  final BookmarkCollectionModel collection;
  final List<BookmarkModel> allBookmarks;

  const AddBookmarksToCollectionSheet({
    super.key,
    required this.collection,
    required this.allBookmarks,
  });

  static Future<void> show({
    required BuildContext context,
    required BookmarkCollectionModel collection,
    required List<BookmarkModel> allBookmarks,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddBookmarksToCollectionSheet(
        collection: collection,
        allBookmarks: allBookmarks,
      ),
    );
  }

  @override
  ConsumerState<AddBookmarksToCollectionSheet> createState() =>
      _AddBookmarksToCollectionSheetState();
}

class _AddBookmarksToCollectionSheetState
    extends ConsumerState<AddBookmarksToCollectionSheet> {
  late Set<String> _selectedIds;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedIds = Set.from(widget.collection.bookmarkIds);
  }

  Future<void> _saveSelection() async {
    setState(() => _isSaving = true);
    final addedIds = _selectedIds
        .where((id) => !widget.collection.bookmarkIds.contains(id))
        .toList();
    final removedIds = widget.collection.bookmarkIds
        .where((id) => !_selectedIds.contains(id))
        .toList();

    for (final id in addedIds) {
      await ref.read(bookmarkControllerProvider).addBookmarkToCollection(
            collectionId: widget.collection.id,
            bookmarkId: id,
          );
    }
    for (final id in removedIds) {
      await ref.read(bookmarkControllerProvider).removeBookmarkFromCollection(
            collectionId: widget.collection.id,
            bookmarkId: id,
          );
    }

    if (mounted) {
      Navigator.pop(context);
      AppSnackBar.show(context, message: 'Updated collection items');
    }
  }

  @override
  Widget build(BuildContext context) {
    final newlySelectedCount = _selectedIds.length;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF161322),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Add to "${widget.collection.name}"',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$newlySelectedCount items selected',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: _isSaving ? null : _saveSelection,
                    child: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: tabColor,
                            ),
                          )
                        : const Text(
                            'Done',
                            style: TextStyle(
                              color: tabColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                  ),
                ],
              ),
            ),

            const Divider(color: Colors.white12, height: 1),

            // Bookmarks Grid
            Expanded(
              child: widget.allBookmarks.isEmpty
                  ? const Center(
                      child: Text(
                        'No bookmarks available',
                        style: TextStyle(color: Colors.white54),
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(4),
                      gridDelegate:
                          SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount:
                            (MediaQuery.sizeOf(context).width / 130)
                                .floor()
                                .clamp(3, 8),
                        crossAxisSpacing: 3,
                        mainAxisSpacing: 3,
                      ),
                      itemCount: widget.allBookmarks.length,
                      itemBuilder: (context, index) {
                        final bm = widget.allBookmarks[index];
                        final isSelected =
                            _selectedIds.contains(bm.bookmarkId);

                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              if (isSelected) {
                                _selectedIds.remove(bm.bookmarkId);
                              } else {
                                _selectedIds.add(bm.bookmarkId);
                              }
                            });
                          },
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              CachedNetworkImage(
                                imageUrl: getOriginalHighQualityImageUrl(
                                    bm.imageUrl),
                                fit: BoxFit.cover,
                              ),
                              if (isSelected)
                                Container(
                                  color: tabColor.withValues(alpha: 0.35),
                                ),
                              Positioned(
                                top: 6,
                                right: 6,
                                child: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isSelected
                                        ? tabColor
                                        : Colors.black45,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 1.5,
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
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

