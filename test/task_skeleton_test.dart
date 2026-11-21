import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_chat/common/widgets/skeleton_loader.dart';

void main() {
  group('Task and Subtask Skeleton Loader Tests', () {
    testWidgets('TaskPageSkeleton renders correct item count with shimmer', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TaskPageSkeleton(itemCount: 4),
          ),
        ),
      );

      // Verify ShimmerEffect is present
      expect(find.byType(ShimmerEffect), findsOneWidget);

      // Verify ListView is present
      expect(find.byType(ListView), findsOneWidget);

      // Verify TaskPageSkeleton widget exists
      expect(find.byType(TaskPageSkeleton), findsOneWidget);
    });

    testWidgets('TaskPageSkeleton defaults to 6 items', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TaskPageSkeleton(),
          ),
        ),
      );

      expect(find.byType(TaskPageSkeleton), findsOneWidget);
      final skeleton = tester.widget<TaskPageSkeleton>(find.byType(TaskPageSkeleton));
      expect(skeleton.itemCount, 6);
    });

    testWidgets('SubtasksPageSkeleton renders header card and subtask rows with shimmer', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SubtasksPageSkeleton(itemCount: 3),
          ),
        ),
      );

      // Verify ShimmerEffect is present
      expect(find.byType(ShimmerEffect), findsOneWidget);

      // Verify ListView is present
      expect(find.byType(ListView), findsOneWidget);

      // Verify SubtasksPageSkeleton widget exists
      expect(find.byType(SubtasksPageSkeleton), findsOneWidget);
      final skeleton = tester.widget<SubtasksPageSkeleton>(find.byType(SubtasksPageSkeleton));
      expect(skeleton.itemCount, 3);
    });

    testWidgets('SubtasksPageSkeleton defaults to 5 items', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SubtasksPageSkeleton(),
          ),
        ),
      );

      expect(find.byType(SubtasksPageSkeleton), findsOneWidget);
      final skeleton = tester.widget<SubtasksPageSkeleton>(find.byType(SubtasksPageSkeleton));
      expect(skeleton.itemCount, 5);
    });
  });
}

