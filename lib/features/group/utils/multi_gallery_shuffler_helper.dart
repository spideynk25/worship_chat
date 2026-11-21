import 'dart:math';
import 'package:worship_chat/models/group_gallery_image.dart';

/// Viewing / slideshow mode for multi-gallery browsing.
enum MultiGalleryMode {
  /// Photos strictly alternate across selected galleries one-by-one.
  alternate,

  /// Each slide / view presents one photo from every selected gallery together.
  sameSlide,
}

/// A synchronized set of photos for a single slide in [MultiGalleryMode.sameSlide],
/// containing exactly one photo from each selected group gallery.
class MultiGallerySlideSet {
  final int slideIndex;
  final List<GroupGalleryImage> photos;

  const MultiGallerySlideSet({
    required this.slideIndex,
    required this.photos,
  });

  /// Quick map of groupId -> GroupGalleryImage for this slide.
  Map<String, GroupGalleryImage> get photosByGroup => {
        for (final p in photos) p.groupId: p,
      };
}

/// Builds synchronized slide sets where each slide contains one photo from
/// every active group gallery.
///
/// If groups have unequal numbers of photos, smaller groups cycle their photos
/// so every slide has a photo from every group without empty slots.
/// Total slides = max(photo count across groups).
List<MultiGallerySlideSet> buildMultiGallerySlideSets({
  required List<GroupGalleryImage> images,
  List<String>? groupOrder,
  Random? random,
}) {
  if (images.isEmpty) return const [];

  final rng = random ?? Random();

  // 1. Group images by their groupId
  final Map<String, List<GroupGalleryImage>> grouped = {};
  for (final img in images) {
    grouped.putIfAbsent(img.groupId, () => []).add(img);
  }

  if (grouped.isEmpty) return const [];

  // 2. Shuffle each group's photos internally so slide order is varied
  final Map<String, List<GroupGalleryImage>> shuffledGrouped = {};
  for (final entry in grouped.entries) {
    final list = List<GroupGalleryImage>.of(entry.value)..shuffle(rng);
    shuffledGrouped[entry.key] = list;
  }

  // 3. Determine group presentation order
  final List<String> activeGroups;
  if (groupOrder != null && groupOrder.isNotEmpty) {
    activeGroups = groupOrder.where((id) => shuffledGrouped.containsKey(id)).toList();
    for (final id in shuffledGrouped.keys) {
      if (!activeGroups.contains(id)) {
        activeGroups.add(id);
      }
    }
  } else {
    activeGroups = shuffledGrouped.keys.toList();
  }

  if (activeGroups.isEmpty) return const [];

  // 4. Max photo count determines the total number of slides
  int maxCount = 0;
  for (final id in activeGroups) {
    final count = shuffledGrouped[id]!.length;
    if (count > maxCount) {
      maxCount = count;
    }
  }

  if (maxCount == 0) return const [];

  // 5. Construct slide sets: each slide takes 1 photo from each group (cycling if needed)
  final List<MultiGallerySlideSet> slideSets = [];
  for (int s = 0; s < maxCount; s++) {
    final List<GroupGalleryImage> slidePhotos = [];
    for (final groupId in activeGroups) {
      final list = shuffledGrouped[groupId]!;
      final photo = list[s % list.length];
      slidePhotos.add(photo);
    }
    slideSets.add(MultiGallerySlideSet(slideIndex: s, photos: slidePhotos));
  }

  return slideSets;
}

/// Shuffles and interleaves photos from multiple group galleries so that photos
/// strictly alternate across the selected profiles/groups instead of showing
/// consecutive sequences of images from the same group.
List<GroupGalleryImage> alternatePhotosAcrossGroups(
  List<GroupGalleryImage> images, [
  Random? random,
]) {
  if (images.length <= 1) {
    return List<GroupGalleryImage>.of(images);
  }

  final rng = random ?? Random();

  // 1. Group images by their groupId
  final Map<String, List<GroupGalleryImage>> grouped = {};
  for (final img in images) {
    grouped.putIfAbsent(img.groupId, () => []).add(img);
  }

  // If all images belong to a single group, perform standard shuffle
  if (grouped.length <= 1) {
    return List<GroupGalleryImage>.of(images)..shuffle(rng);
  }

  // 2. Shuffle each individual group's photos internally
  for (final list in grouped.values) {
    list.shuffle(rng);
  }

  // 3. Randomize the initial group order for this shuffle pass
  final List<String> activeGroupKeys = grouped.keys.toList()..shuffle(rng);
  final Map<String, int> groupIndices = {
    for (final key in activeGroupKeys) key: 0,
  };

  final List<GroupGalleryImage> result = [];
  String? lastGroupId;

  // 4. Interleave photos round-robin across groups
  while (activeGroupKeys.isNotEmpty) {
    // Pick the next group. If more than one active group remains,
    // guarantee that the selected group is different from the last one.
    int chosenIndex = -1;
    for (int i = 0; i < activeGroupKeys.length; i++) {
      final key = activeGroupKeys[i];
      if (activeGroupKeys.length == 1 || key != lastGroupId) {
        chosenIndex = i;
        break;
      }
    }

    if (chosenIndex == -1) {
      chosenIndex = 0;
    }

    final chosenKey = activeGroupKeys[chosenIndex];
    final list = grouped[chosenKey]!;
    final imgIndex = groupIndices[chosenKey]!;

    result.add(list[imgIndex]);
    lastGroupId = chosenKey;

    groupIndices[chosenKey] = imgIndex + 1;
    if (groupIndices[chosenKey]! >= list.length) {
      activeGroupKeys.removeAt(chosenIndex);
    } else {
      // Move this group to the end of the queue for fair round-robin cycling
      activeGroupKeys.removeAt(chosenIndex);
      activeGroupKeys.add(chosenKey);
    }
  }

  return result;
}

