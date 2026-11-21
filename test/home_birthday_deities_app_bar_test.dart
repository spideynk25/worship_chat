import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_chat/features/dashboard/widgets/today_birthdays_slideshow_widget.dart';
import 'package:worship_chat/features/home/widgets/home_birthday_deities_app_bar_bottom.dart';
import 'package:worship_chat/models/event.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final celebrant1 = Event(
    id: 'bday_priyanka',
    title: "Shrine of Eternal Enchantress Priyanka Jawalkar's Birthday",
    description: 'Annual Royal Birthday celebration',
    date: DateTime.now(),
    time: const TimeOfDay(hour: 0, minute: 0),
    createdBy: 'admin',
    userId: 'admin',
    isRecurring: true,
    connectedGroupId: 'group_priyanka',
    connectedGroupName: 'Shrine of Eternal Enchantress Priyanka Jawalkar',
    connectedGroupPic: 'assets/auth_images/queen_priyanka.png',
    connectedQueendom: 'Queen Priyanka',
  );

  group('Home Birthday Deities Avatar Display Tests', () {
    testWidgets('Renders profile pic of birthday deities under the titles without name or wishing text',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              toolbarHeight: 90,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Worship Chat',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text('Subtitle text', style: TextStyle(fontSize: 11.5)),
                  const SizedBox(height: 3),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Birthday deity profile picture
                      GestureDetector(
                        onTap: () {},
                        child: Container(
                          margin: const EdgeInsets.only(right: 6),
                          child: Stack(
                            clipBehavior: Clip.none,
                            alignment: Alignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(1.5),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: const Color(0xFFFFD700),
                                    width: 1.5,
                                  ),
                                ),
                                child: const CircleAvatar(
                                  radius: 13,
                                  backgroundImage: AssetImage('assets/auth_images/queen_priyanka.png'),
                                ),
                              ),
                              Positioned(
                                bottom: -2,
                                right: -2,
                                child: Container(
                                  padding: const EdgeInsets.all(1.0),
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Color(0xFF140E20),
                                  ),
                                  child: const Text('🎂', style: TextStyle(fontSize: 8)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Profile avatar exists with mini cake badge
      expect(find.byType(CircleAvatar), findsOneWidget);
      expect(find.text('🎂'), findsOneWidget);

      // App title and subtitle exist
      expect(find.text('Worship Chat'), findsOneWidget);
      expect(find.text('Subtitle text'), findsOneWidget);

      // Verify profile avatar is positioned UNDER the titles (y coordinate is strictly greater)
      final titleBottom = tester.getBottomLeft(find.text('Worship Chat')).dy;
      final subtitleBottom = tester.getBottomLeft(find.text('Subtitle text')).dy;
      final avatarTop = tester.getTopLeft(find.byType(CircleAvatar)).dy;

      expect(avatarTop, greaterThan(titleBottom));
      expect(avatarTop, greaterThan(subtitleBottom));

      // NO celebrant name or wishing text rendered in the header
      expect(find.textContaining('Priyanka'), findsNothing);
      expect(find.textContaining('Happy Birthday'), findsNothing);
      expect(find.textContaining('Celebrate'), findsNothing);
    });

    test('TodayBirthdaysSlideshowWidget isToday and isBirthday identification', () {
      final now = DateTime.now();
      expect(TodayBirthdaysSlideshowWidget.isToday(celebrant1, now), isTrue);
      expect(TodayBirthdaysSlideshowWidget.isBirthday(celebrant1), isTrue);

      final pastNonBirthdayEvent = Event(
        id: 'past_meeting',
        title: 'Project Standup',
        description: 'Meeting',
        date: DateTime(2020, 1, 1),
        time: const TimeOfDay(hour: 10, minute: 0),
        createdBy: 'user',
        userId: 'user',
        isRecurring: false,
      );

      expect(TodayBirthdaysSlideshowWidget.isToday(pastNonBirthdayEvent, now), isFalse);
      expect(TodayBirthdaysSlideshowWidget.isBirthday(pastNonBirthdayEvent), isFalse);
    });

    test('resolveCelebrantPic returns connectedGroupPic or fallback asset', () {
      final pic1 = HomeBirthdayDeitiesAppBarBottom.resolveCelebrantPic(celebrant1);
      expect(pic1, 'assets/auth_images/queen_priyanka.png');

      final eventWithoutPic = Event(
        id: 'bday_pooja_fallback',
        title: 'Happy Birthday Queen Pooja',
        description: 'Bday',
        date: DateTime.now(),
        time: const TimeOfDay(hour: 0, minute: 0),
        createdBy: 'user',
        userId: 'user',
        isRecurring: true,
        connectedQueendom: 'Queen Pooja',
      );

      final pic2 = HomeBirthdayDeitiesAppBarBottom.resolveCelebrantPic(eventWithoutPic);
      expect(pic2, contains('queen_pooja'));
    });
  });
}
