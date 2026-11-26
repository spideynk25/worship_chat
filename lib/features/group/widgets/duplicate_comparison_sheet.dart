import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/features/group/services/duplicate_detection_service.dart';
import 'package:worship_chat/models/group_gallery_image.dart';

class DuplicateComparisonSheet extends StatelessWidget {
  final GroupGalleryImage canonical;
  final DuplicateItem duplicateItem;
  final String? canonicalGroupName;
  final VoidCallback? onDeleteDuplicate;
  final VoidCallback? onKeepBoth;

  const DuplicateComparisonSheet({
    super.key,
    required this.canonical,
    required this.duplicateItem,
    this.canonicalGroupName,
    this.onDeleteDuplicate,
    this.onKeepBoth,
  });

  static Future<void> show({
    required BuildContext context,
    required GroupGalleryImage canonical,
    required DuplicateItem duplicateItem,
    String? canonicalGroupName,
    VoidCallback? onDeleteDuplicate,
    VoidCallback? onKeepBoth,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DuplicateComparisonSheet(
        canonical: canonical,
        duplicateItem: duplicateItem,
        canonicalGroupName: canonicalGroupName,
        onDeleteDuplicate: onDeleteDuplicate,
        onKeepBoth: onKeepBoth,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('d MMM y, HH:mm');
    final duplicate = duplicateItem.image;

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: const BoxDecoration(
        color: Color(0xFF13111C),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: tabColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.compare_rounded, color: tabColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Compare Duplicate',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: duplicateItem.isExact
                                  ? Colors.green.withValues(alpha: 0.2)
                                  : Colors.orange.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: duplicateItem.isExact
                                    ? Colors.green.withValues(alpha: 0.5)
                                    : Colors.orange.withValues(alpha: 0.5),
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              duplicateItem.matchLabel,
                              style: TextStyle(
                                color: duplicateItem.isExact
                                    ? Colors.greenAccent
                                    : Colors.orangeAccent,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (duplicateItem.hammingDistance > 0) ...[
                            const SizedBox(width: 8),
                            Text(
                              'dHash diff: ${duplicateItem.hammingDistance} bits',
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white54),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          const Divider(color: Colors.white12, height: 1),

          // Side-by-side or stacked image preview
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Side-by-Side Images
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left: Canonical (Keeper)
                      Expanded(
                        child: _buildImageCard(
                          context: context,
                          title: '👑 Original / Keeper',
                          titleColor: tabColor,
                          image: canonical,
                          groupName: canonicalGroupName,
                          dateFormat: dateFormat,
                          isCanonical: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Right: Duplicate (Candidate)
                      Expanded(
                        child: _buildImageCard(
                          context: context,
                          title: '⚠️ Duplicate',
                          titleColor: Colors.redAccent,
                          image: duplicate,
                          groupName: duplicateItem.groupName,
                          dateFormat: dateFormat,
                          isCanonical: false,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Metadata comparison table
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B1827),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Comparison Details',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _buildComparisonRow(
                          label: 'Uploaded Date',
                          valA: dateFormat.format(canonical.uploadedAt),
                          valB: dateFormat.format(duplicate.uploadedAt),
                        ),
                        _buildComparisonRow(
                          label: 'Uploaded By',
                          valA: canonical.uploadedByName.isNotEmpty
                              ? canonical.uploadedByName
                              : 'Unknown',
                          valB: duplicate.uploadedByName.isNotEmpty
                              ? duplicate.uploadedByName
                              : 'Unknown',
                        ),
                        _buildComparisonRow(
                          label: 'Group / Location',
                          valA: canonicalGroupName ?? canonical.groupId,
                          valB: duplicateItem.groupName ?? duplicate.groupId,
                        ),
                        _buildComparisonRow(
                          label: 'Media Type',
                          valA: canonical.mediaType.toUpperCase(),
                          valB: duplicate.mediaType.toUpperCase(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom Action Bar
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            decoration: const BoxDecoration(
              color: Color(0xFF181523),
              border: Border(top: BorderSide(color: Colors.white12, width: 0.8)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      onKeepBoth?.call();
                    },
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Keep Both',
                      style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      onDeleteDuplicate?.call();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text(
                      'Delete Duplicate',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageCard({
    required BuildContext context,
    required String title,
    required Color titleColor,
    required GroupGalleryImage image,
    required String? groupName,
    required DateFormat dateFormat,
    required bool isCanonical,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1B1827),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCanonical
              ? tabColor.withValues(alpha: 0.4)
              : Colors.redAccent.withValues(alpha: 0.4),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: titleColor.withValues(alpha: 0.12),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Text(
              title,
              style: TextStyle(
                color: titleColor,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Image preview with zoom
          ClipRRect(
            child: SizedBox(
              height: 200,
              child: InteractiveViewer(
                clipBehavior: Clip.hardEdge,
                minScale: 1.0,
                maxScale: 3.0,
                child: CachedNetworkImage(
                  imageUrl: image.imageUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(
                    color: Colors.black26,
                    child: const Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: tabColor,
                      ),
                    ),
                  ),
                  errorWidget: (_, __, ___) => const Center(
                    child: Icon(Icons.broken_image, color: Colors.white30),
                  ),
                ),
              ),
            ),
          ),

          // Quick info footer
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (groupName != null && groupName.isNotEmpty) ...[
                  Text(
                    groupName,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  dateFormat.format(image.uploadedAt),
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonRow({
    required String label,
    required String valA,
    required String valB,
  }) {
    final isIdentical = valA == valB;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: Text(
                  valA,
                  style: TextStyle(
                    color: isIdentical ? Colors.white70 : tabColor,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.arrow_forward_rounded, size: 12, color: Colors.white24),
              ),
              Expanded(
                child: Text(
                  valB,
                  style: TextStyle(
                    color: isIdentical ? Colors.white70 : Colors.redAccent,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
