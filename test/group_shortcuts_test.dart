import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Group Shortcuts Reordering & Selection Logic Tests', () {
    test('Reordering moves items from oldIndex to newIndex correctly', () {
      final shortcutIds = ['group_1', 'group_2', 'group_3', 'group_4'];

      // Move group_1 to index 2 (between group_2 and group_3)
      final fromIndex = 0;
      final toIndex = 2;
      final item = shortcutIds.removeAt(fromIndex);
      shortcutIds.insert(toIndex, item);

      expect(shortcutIds, ['group_2', 'group_3', 'group_1', 'group_4']);

      // Move group_4 to the beginning (index 0)
      final item4 = shortcutIds.removeAt(3);
      shortcutIds.insert(0, item4);

      expect(shortcutIds, ['group_4', 'group_2', 'group_3', 'group_1']);
    });

    test('Selection preserves existing ordering and appends newly selected groups', () {
      final initialOrderedIds = ['group_B', 'group_A', 'group_C'];
      final newlySelectedIds = {'group_C', 'group_B', 'group_D'}; // Removed A, added D

      final List<String> result = [];

      // Preserve order of previously selected
      for (var id in initialOrderedIds) {
        if (newlySelectedIds.contains(id)) {
          result.add(id);
        }
      }
      // Append newly added
      for (var id in newlySelectedIds) {
        if (!result.contains(id)) {
          result.add(id);
        }
      }

      // group_B and group_C should retain relative order [B, C], and group_D appended
      expect(result, ['group_B', 'group_C', 'group_D']);
      expect(result.contains('group_A'), false);
    });

    test('Bound checks prevent out-of-range reorder errors', () {
      final list = ['g1', 'g2'];

      bool canReorder(int oldIndex, int newIndex, int length) {
        if (oldIndex == newIndex ||
            oldIndex < 0 ||
            oldIndex >= length ||
            newIndex < 0 ||
            newIndex >= length) {
          return false;
        }
        return true;
      }

      expect(canReorder(0, 1, list.length), true);
      expect(canReorder(1, 0, list.length), true);
      expect(canReorder(0, 0, list.length), false);
      expect(canReorder(-1, 0, list.length), false);
      expect(canReorder(0, 2, list.length), false);
    });
  });
}
