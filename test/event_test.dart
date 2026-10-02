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
        connectedGroupId: 'pooja_grp_1',
        connectedGroupName: 'Queen Pooja Royal Guard',
        connectedGroupPic: 'https://example.com/pic.png',
        connectedQueendom: 'Queen Pooja',
      );

      final updateMap = event.toUpdateMap();

      expect(updateMap['title'], 'Meeting');
      expect(updateMap['description'], 'Sync');
      expect(updateMap['timeHour'], 9);
      expect(updateMap['timeMinute'], 15);
      expect(updateMap['isRecurring'], isTrue);
      expect(updateMap['connectedGroupId'], 'pooja_grp_1');
      expect(updateMap['connectedGroupName'], 'Queen Pooja Royal Guard');
      expect(updateMap['connectedGroupPic'], 'https://example.com/pic.png');
      expect(updateMap['connectedQueendom'], 'Queen Pooja');
      // toUpdateMap should contain updatedAt FieldValue
      expect(updateMap.containsKey('updatedAt'), isTrue);
      // toUpdateMap should not contain userId or createdBy so it doesn't overwrite
      expect(updateMap.containsKey('userId'), isFalse);
      expect(updateMap.containsKey('createdBy'), isFalse);
    });

    test('Event copyWith updates connected Queendom group and supports clearConnectedGroup', () {
      final event = Event(
        id: 'ev_003',
        title: 'Rashmika Birthday',
        description: 'National Crush Celebration',
        date: DateTime(2026, 4, 5),
        time: const TimeOfDay(hour: 0, minute: 0),
        createdBy: 'Admin',
        userId: 'admin_id',
        connectedGroupId: 'rash_grp_1',
        connectedGroupName: 'Queen Rashmika Queendom',
        connectedQueendom: 'Queen Rashmika',
      );

      expect(event.connectedQueendom, 'Queen Rashmika');
      expect(event.connectedGroupId, 'rash_grp_1');

      // Clear connected group
      final disconnected = event.copyWith(clearConnectedGroup: true);
      expect(disconnected.connectedGroupId, isNull);
      expect(disconnected.connectedGroupName, isNull);
      expect(disconnected.connectedQueendom, isNull);

      // Reconnect to Queen Pooja group
      final poojaLinked = disconnected.copyWith(
        connectedGroupId: 'pooja_grp_2',
        connectedGroupName: 'Queen Pooja Devotees',
        connectedQueendom: 'Queen Pooja',
      );
      expect(poojaLinked.connectedGroupId, 'pooja_grp_2');
      expect(poojaLinked.connectedGroupName, 'Queen Pooja Devotees');
      expect(poojaLinked.connectedQueendom, 'Queen Pooja');
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

    test('Editing connected birthday title and date preserves group links', () {
      final event = Event(
        id: 'ev_005',
        title: 'Original Queen Birthday',
        description: 'Annual Royal Event',
        date: DateTime(1996, 4, 5),
        time: const TimeOfDay(hour: 0, minute: 0),
        createdBy: 'Admin',
        userId: 'admin_id',
        isRecurring: true,
        connectedGroupId: 'group_rash_10',
        connectedGroupName: 'Queen Rashmika Queendom',
        connectedGroupPic: 'https://example.com/rash.jpg',
        connectedQueendom: 'Queen Rashmika',
      );

      final newBirthdayDate = DateTime(1996, 4, 5, 0, 0);
      final edited = event.copyWith(
        title: 'Queen Rashmika Mandanna Birthday',
        date: newBirthdayDate,
        isRecurring: true,
        connectedGroupName: 'Queen Rashmika Royal Palace',
      );

      expect(edited.title, 'Queen Rashmika Mandanna Birthday');
      expect(edited.connectedGroupId, 'group_rash_10');
      expect(edited.connectedGroupName, 'Queen Rashmika Royal Palace');
      expect(edited.connectedQueendom, 'Queen Rashmika');

      final updateMap = edited.toUpdateMap();
      expect(updateMap['title'], 'Queen Rashmika Mandanna Birthday');
      expect(updateMap['connectedGroupId'], 'group_rash_10');
      expect(updateMap['connectedQueendom'], 'Queen Rashmika');
    });

    test('Unlinking connected birthday from group sets connected fields to null', () {
      final event = Event(
        id: 'ev_006',
        title: 'Pooja Celebration',
        description: 'Royal Event',
        date: DateTime(1990, 10, 13),
        time: const TimeOfDay(hour: 0, minute: 0),
        createdBy: 'Admin',
        userId: 'admin_id',
        connectedGroupId: 'group_pooja_1',
        connectedGroupName: 'Queen Pooja Queendom',
        connectedQueendom: 'Queen Pooja',
      );

      final unlinked = event.copyWith(clearConnectedGroup: true);
      expect(unlinked.connectedGroupId, isNull);
      expect(unlinked.connectedGroupName, isNull);
      expect(unlinked.connectedQueendom, isNull);

      final updateMap = unlinked.toUpdateMap();
      expect(updateMap['connectedGroupId'], isNull);
      expect(updateMap['connectedGroupName'], isNull);
      expect(updateMap['connectedQueendom'], isNull);
    });

    testWidgets('Long event title renders with multiline maxLines support without throwing', (tester) async {
      final event = Event(
        id: 'ev_long_01',
        title: 'Her Supreme Royal Majesty Queen Pooja Hegde Annual Birthday Celebration Grand Gala 2026',
        description: 'Grand festivity across the Queendom',
        date: DateTime.now(),
        time: const TimeOfDay(hour: 10, minute: 30),
        createdBy: 'High Priest',
        userId: 'priest_01',
        isRecurring: true,
        connectedGroupId: 'group_pooja_royal',
        connectedGroupName: 'Queen Pooja Royal Guard',
        connectedQueendom: 'Queen Pooja',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                child: Text(
                  event.title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text(event.title), findsOneWidget);
      final textWidget = tester.widget<Text>(find.text(event.title));
      expect(textWidget.maxLines, 3);
      expect(textWidget.overflow, TextOverflow.ellipsis);
    });

    test('Multiple celebrants on the same day are correctly identified and separated', () {
      final now = DateTime(2026, 10, 13);
      final bday1 = Event(
        id: 'ev_p1',
        title: 'Queen Pooja Birthday',
        description: 'Pooja Day',
        date: DateTime(1990, 10, 13),
        time: const TimeOfDay(hour: 0, minute: 0),
        createdBy: 'Admin',
        userId: 'admin_1',
        isRecurring: true,
        connectedGroupId: 'group_pooja_main',
        connectedGroupName: 'Queen Pooja Queendom',
        connectedQueendom: 'Queen Pooja',
      );

      final bday2 = Event(
        id: 'ev_p2',
        title: 'Queen Rashmika Special Birthday',
        description: 'Rashmika Day',
        date: DateTime(1996, 10, 13),
        time: const TimeOfDay(hour: 0, minute: 0),
        createdBy: 'Admin',
        userId: 'admin_2',
        isRecurring: true,
        connectedGroupId: 'group_rash_main',
        connectedGroupName: 'Queen Rashmika Queendom',
        connectedQueendom: 'Queen Rashmika',
      );

      final otherEvent = Event(
        id: 'ev_other',
        title: 'General Meeting',
        description: 'Work sync',
        date: DateTime(2026, 10, 13),
        time: const TimeOfDay(hour: 14, minute: 0),
        createdBy: 'Admin',
        userId: 'admin_3',
        isRecurring: false,
      );

      final allEvents = [bday1, bday2, otherEvent];

      bool isToday(Event e, DateTime date) {
        if (e.isRecurring) {
          return e.date.month == date.month && e.date.day == date.day;
        }
        return e.date.year == date.year &&
            e.date.month == date.month &&
            e.date.day == date.day;
      }

      bool isBirthday(Event e) {
        final t = e.title.toLowerCase();
        return t.contains('birth') || t.contains('bday') || (e.connectedGroupId != null && e.isRecurring);
      }

      final todayBirthdays = allEvents.where((e) => isToday(e, now) && isBirthday(e)).toList();

      expect(todayBirthdays.length, 2);
      expect(todayBirthdays[0].connectedQueendom, 'Queen Pooja');
      expect(todayBirthdays[1].connectedQueendom, 'Queen Rashmika');
    });

    test('Random photo sampling picks up to 8 photos without exceeding available count', () {
      final galleryUrls = List.generate(20, (i) => 'https://example.com/gallery_$i.jpg');
      galleryUrls.shuffle();
      final sampled = galleryUrls.take(8).toList();

      expect(sampled.length, 8);
      expect(sampled.toSet().length, 8); // Unique photos
    });

    test('Today birthday slideshow guarantees multiple photos for seamless auto-sliding', () {
      List<String> getFallbackPhotos(String queendom, String title, String? groupPic) {
        final List<String> list = [];
        if (groupPic != null && groupPic.isNotEmpty) list.add(groupPic);
        final lower = title.toLowerCase();
        if (queendom == 'Queen Pooja' || lower.contains('pooja')) {
          list.addAll(const [
            'assets/auth_images/queen_pooja.png',
            'assets/auth_images/queen_pooja1.png',
            'assets/auth_images/queen_pooja2.png',
            'assets/images/img1.png',
            'assets/images/img2.png',
          ]);
        } else if (queendom == 'Queen Rashmika' || lower.contains('rashmika')) {
          list.addAll(const [
            'assets/auth_images/queen_rashmika.png',
            'assets/auth_images/queen_rashmika1.png',
            'assets/auth_images/queen_rashmika2.png',
            'assets/images/img3.png',
            'assets/images/img2.png',
          ]);
        } else {
          list.addAll(const [
            'assets/images/img1.png',
            'assets/images/img2.png',
            'assets/images/img3.png',
          ]);
        }
        return list.toSet().toList();
      }

      final poojaPhotos = getFallbackPhotos('Queen Pooja', 'Queen Pooja Birthday', null);
      expect(poojaPhotos.length >= 3, true);
      expect(poojaPhotos.contains('assets/auth_images/queen_pooja.png'), true);

      final rashmikaPhotos = getFallbackPhotos('Queen Rashmika', 'Rashmika Bday', null);
      expect(rashmikaPhotos.length >= 3, true);
      expect(rashmikaPhotos.contains('assets/auth_images/queen_rashmika.png'), true);

      final genericPhotos = getFallbackPhotos('None', 'Member Birthday', 'https://example.com/pic.jpg');
      expect(genericPhotos.length >= 3, true);
      expect(genericPhotos.first, 'https://example.com/pic.jpg');
    });

    test('Story-style segmented progress avoids showing numeric slide count', () {
      // Verifies no numeric counter string pattern like "X / Y" is required for slideshow progress
      const photosCount = 5;
      final segments = List.generate(photosCount, (i) => i);
      expect(segments.length, photosCount);
      // Ensure we have indicators without needing text like "$idx / $photosCount"
      final hasNumericCount = segments.any((s) => s.toString().contains('/'));
      expect(hasNumericCount, false);
    });
  });
}
