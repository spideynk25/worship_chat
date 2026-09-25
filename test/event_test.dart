import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_chat/common/widgets/skeleton_loader.dart';
import 'package:worship_chat/models/event.dart';

void main() {
  group('Event Model Tests', () {
    test('Event copyWith updates fields correctly', () {
      final initialDate = DateTime(2026, 9, 25);
      final event = Event(
        id: 'ev_001',
        title: 'Original Title',
        description: 'Original Description',
        date: initialDate,
        time: const TimeOfDay(hour: 10, minute: 30),
        createdBy: 'Alice',
        userId: 'user_123',
        isRecurring: false,
      );

      final newDate = DateTime(2026, 10, 15);
      final updated = event.copyWith(
        title: 'Updated Title',
        description: 'Updated Description',
        date: newDate,
        time: const TimeOfDay(hour: 14, minute: 0),
        isRecurring: true,
      );

      expect(updated.id, 'ev_001');
      expect(updated.title, 'Updated Title');
      expect(updated.description, 'Updated Description');
      expect(updated.date, newDate);
      expect(updated.time.hour, 14);
      expect(updated.time.minute, 0);
      expect(updated.isRecurring, isTrue);
      expect(updated.createdBy, 'Alice');
      expect(updated.userId, 'user_123');
    });

    test('Event toUpdateMap exports editable fields and preserves user and doc identity', () {
      final event = Event(
        id: 'ev_002',
        title: 'Meeting',
        description: 'Sync',
        date: DateTime(2026, 5, 10),
        time: const TimeOfDay(hour: 9, minute: 15),
        createdBy: 'Bob',
        userId: 'user_456',
        isRecurring: true,
      );

      final updateMap = event.toUpdateMap();

      expect(updateMap['title'], 'Meeting');
      expect(updateMap['description'], 'Sync');
      expect(updateMap['timeHour'], 9);
      expect(updateMap['timeMinute'], 15);
      expect(updateMap['isRecurring'], isTrue);
      // toUpdateMap should contain updatedAt FieldValue
      expect(updateMap.containsKey('updatedAt'), isTrue);
      // toUpdateMap should not contain userId or createdBy so it doesn't overwrite
      expect(updateMap.containsKey('userId'), isFalse);
      expect(updateMap.containsKey('createdBy'), isFalse);
    });

    test('Event occurrence calculation handles recurring yearly events correctly', () {
      final now = DateTime(2026, 9, 25);
      
      // Past birthday this year: May 10 -> Next occurrence should be 2027
      final pastBirthday = Event(
        id: 'ev_past',
        title: 'Pooja Birthday',
        description: 'Celebration',
        date: DateTime(2026, 5, 10),
        time: const TimeOfDay(hour: 0, minute: 0),
        createdBy: 'Admin',
        userId: 'admin_id',
        isRecurring: true,
      );

      final thisYearDate = DateTime(now.year, pastBirthday.date.month, pastBirthday.date.day);
      final today = DateTime(now.year, now.month, now.day);
      final nextOccur = thisYearDate.isBefore(today)
          ? DateTime(now.year + 1, pastBirthday.date.month, pastBirthday.date.day)
          : thisYearDate;

      expect(nextOccur.year, 2027);
      expect(nextOccur.month, 5);
      expect(nextOccur.day, 10);

      // Upcoming birthday this week: September 28 -> Occur this year, within 7 days
      final upcomingBirthday = Event(
        id: 'ev_up',
        title: 'Rashmika Birthday',
        description: 'Celebration',
        date: DateTime(2024, 9, 28),
        time: const TimeOfDay(hour: 0, minute: 0),
        createdBy: 'Admin',
        userId: 'admin_id',
        isRecurring: true,
      );

      final thisYearUpcoming = DateTime(now.year, upcomingBirthday.date.month, upcomingBirthday.date.day);
      final nextUpcomingOccur = thisYearUpcoming.isBefore(today)
          ? DateTime(now.year + 1, upcomingBirthday.date.month, upcomingBirthday.date.day)
          : thisYearUpcoming;

      expect(nextUpcomingOccur.year, 2026);
      expect(nextUpcomingOccur.difference(today).inDays, 3);
      expect(nextUpcomingOccur.difference(today).inDays <= 7, isTrue);
    });

    testWidgets('CalendarPageSkeleton renders without error', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CalendarPageSkeleton(),
          ),
        ),
      );
      expect(find.byType(CalendarPageSkeleton), findsOneWidget);
    });
  });
}
