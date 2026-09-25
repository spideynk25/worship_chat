import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/features/dashboard/controller/event_controller.dart';
import 'package:worship_chat/features/dashboard/screens/event_calender_page.dart';
import 'package:worship_chat/models/event.dart';

enum _BirthdayFilter { today, weekly, monthly }

class EventShortcutsWidget extends ConsumerStatefulWidget {
  const EventShortcutsWidget({super.key});

  @override
  ConsumerState<EventShortcutsWidget> createState() =>
      _EventShortcutsWidgetState();
}

class _EventShortcutsWidgetState extends ConsumerState<EventShortcutsWidget> {
  _BirthdayFilter _activeFilter = _BirthdayFilter.today;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(eventControllerProvider.notifier).loadEvents();
    });
  }

  /// Calculates upcoming occurrence for a recurring or one-time event
  DateTime _getEventOccurrence(Event event, DateTime now) {
    if (event.isRecurring) {
      final thisYearDate =
          DateTime(now.year, event.date.month, event.date.day);
      final today = DateTime(now.year, now.month, now.day);
      if (thisYearDate.isBefore(today)) {
        return DateTime(now.year + 1, event.date.month, event.date.day);
      }
      return thisYearDate;
    }
    return DateTime(event.date.year, event.date.month, event.date.day);
  }

  bool _isToday(Event event, DateTime now) {
    if (event.isRecurring) {
      if (event.date.month == now.month && event.date.day == now.day) {
        return true;
      }
    } else {
      if (event.date.year == now.year &&
          event.date.month == now.month &&
          event.date.day == now.day) {
        return true;
      }
    }
    final lowerTitle = event.title.toLowerCase();
    if (lowerTitle.contains('monthly') && event.date.day == now.day) {
      return true;
    }
    if (lowerTitle.contains('weekly') && event.date.weekday == now.weekday) {
      return true;
    }
    return false;
  }

  bool _isWeekly(Event event, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final occurrence = _getEventOccurrence(event, now);
    final diff = occurrence.difference(today).inDays;
    if (diff >= 0 && diff <= 7) return true;

    final lowerTitle = event.title.toLowerCase();
    if (lowerTitle.contains('weekly')) return true;

    return false;
  }

  bool _isMonthly(Event event, DateTime now) {
    if (event.isRecurring) {
      if (event.date.month == now.month) return true;
    } else {
      if (event.date.year == now.year && event.date.month == now.month) {
        return true;
      }
    }
    final lowerTitle = event.title.toLowerCase();
    if (lowerTitle.contains('monthly')) return true;

    return false;
  }

  void _navigateToCalendar(DateTime? date) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EventsCalendarPage(initialSelectedDay: date),
      ),
    );
  }

  void _showAddEventDialog() {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    DateTime selectedDate = DateTime.now();
    TimeOfDay selectedTime = TimeOfDay.now();
    bool isRecurring = true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.grey[900],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: tabColor.withValues(alpha: 0.3)),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: tabColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.cake_outlined,
                  color: tabColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Add Birthday / Event',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Event Title (e.g. Pooja Birthday)',
                    labelStyle: TextStyle(color: Colors.grey[400]),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey[700]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: tabColor),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: descriptionController,
                  style: const TextStyle(color: Colors.white),
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Description (Optional)',
                    labelStyle: TextStyle(color: Colors.grey[400]),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey[700]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: tabColor),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Event Date',
                    style: TextStyle(color: Colors.grey[400]),
                  ),
                  subtitle: Text(
                    DateFormat('MMM dd, yyyy').format(selectedDate),
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  trailing: const Icon(Icons.calendar_today, color: tabColor),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035),
                      builder: (context, child) => Theme(
                        data: Theme.of(context).copyWith(
                          colorScheme: const ColorScheme.dark(
                            primary: tabColor,
                            onPrimary: Colors.white,
                            surface: Colors.grey,
                            onSurface: Colors.white,
                          ),
                        ),
                        child: child!,
                      ),
                    );
                    if (picked != null) {
                      setDialogState(() => selectedDate = picked);
                    }
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Event Time',
                    style: TextStyle(color: Colors.grey[400]),
                  ),
                  subtitle: Text(
                    selectedTime.format(context),
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  trailing: const Icon(Icons.access_time, color: tabColor),
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: selectedTime,
                    );
                    if (picked != null) {
                      setDialogState(() => selectedTime = picked);
                    }
                  },
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Repeat Every Year',
                    style: TextStyle(color: Colors.grey[400]),
                  ),
                  subtitle: Text(
                    'Perfect for birthdays & anniversaries',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                  value: isRecurring,
                  activeColor: tabColor,
                  checkColor: Colors.white,
                  onChanged: (val) {
                    setDialogState(() => isRecurring = val ?? true);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: Colors.grey[400])),
            ),
            ElevatedButton(
              onPressed: () async {
                final title = titleController.text.trim();
                if (title.isNotEmpty) {
                  final messenger = ScaffoldMessenger.of(context);
                  Navigator.pop(context);
                  try {
                    await ref
                        .read(eventControllerProvider.notifier)
                        .createEvent(
                          title: title,
                          description: descriptionController.text.trim(),
                          date: selectedDate,
                          time: selectedTime,
                          isRecurring: isRecurring,
                        );
                    if (mounted) {
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('Event created successfully!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text('Error: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: tabColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Create', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final eventState = ref.watch(eventControllerProvider);
    final allEvents =
        eventState.events.values.expand((list) => list).toSet().toList();

    final now = DateTime.now();

    final todayEvents = allEvents.where((e) => _isToday(e, now)).toList();
    final weeklyEvents = allEvents.where((e) => _isWeekly(e, now)).toList();
    final monthlyEvents = allEvents.where((e) => _isMonthly(e, now)).toList();

    weeklyEvents.sort((a, b) => _getEventOccurrence(a, now).compareTo(
          _getEventOccurrence(b, now),
        ));
    monthlyEvents.sort((a, b) => _getEventOccurrence(a, now).compareTo(
          _getEventOccurrence(b, now),
        ));

    List<Event> currentList;
    switch (_activeFilter) {
      case _BirthdayFilter.today:
        currentList = todayEvents;
        break;
      case _BirthdayFilter.weekly:
        currentList = weeklyEvents;
        break;
      case _BirthdayFilter.monthly:
        currentList = monthlyEvents;
        break;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1E1428),
            mobileChatBoxColor,
            const Color(0xFF1B1424),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: tabColor.withValues(alpha: 0.28),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: tabColor.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Royal Header featuring img3 (Pooja) and img2 (Rashmika) ─────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                // ── Queen Pooja Portrait (img3) ──
                _buildQueenAvatar(
                  imagePath: 'assets/images/img3.png',
                  name: 'Pooja',
                  crownColor: const Color(0xFFFFD700), // Gold
                  angle: -0.05,
                  onTap: () => _navigateToCalendar(null),
                ),

                // ── Center Title & Action ──
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('🎉', style: TextStyle(fontSize: 16)),
                            const SizedBox(width: 6),
                            ShaderMask(
                              shaderCallback: (bounds) => const LinearGradient(
                                colors: [Color(0xFFFF5288), Color(0xFFFF9E68)],
                              ).createShader(bounds),
                              child: const Text(
                                'BIRTHDAYS & EVENTS',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Royal Celebrations & Days',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[400],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: () => _navigateToCalendar(null),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: tabColor.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: tabColor.withValues(alpha: 0.4),
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.calendar_month,
                                  size: 12,
                                  color: tabColor,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Open Calendar',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: tabColor,
                                  ),
                                ),
                                SizedBox(width: 2),
                                Icon(
                                  Icons.arrow_forward_ios,
                                  size: 9,
                                  color: tabColor,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Queen Rashmika Portrait (img2) ──
                _buildQueenAvatar(
                  imagePath: 'assets/images/img2.png',
                  name: 'Rashmika',
                  crownColor: const Color(0xFFFF4081), // Rose Pink
                  angle: 0.05,
                  onTap: () => _navigateToCalendar(null),
                ),
              ],
            ),
          ),

          const Divider(color: dividerColor, height: 1),
          const SizedBox(height: 12),

          // ── 3 Shortcut Tabs (Today, Weekly, Monthly) ─────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _buildShortcutPill(
                  filter: _BirthdayFilter.today,
                  emoji: '🎂',
                  title: "Today's",
                  count: todayEvents.length,
                  isHighlight: todayEvents.isNotEmpty,
                ),
                const SizedBox(width: 8),
                _buildShortcutPill(
                  filter: _BirthdayFilter.weekly,
                  emoji: '📅',
                  title: 'Weekly',
                  count: weeklyEvents.length,
                ),
                const SizedBox(width: 8),
                _buildShortcutPill(
                  filter: _BirthdayFilter.monthly,
                  emoji: '🗓️',
                  title: 'Monthly',
                  count: monthlyEvents.length,
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ── Events List or Empty State ───────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: currentList.isEmpty
                  ? _buildEmptyState()
                  : Column(
                      children: currentList
                          .map((event) => _buildEventCard(event, now))
                          .toList(),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQueenAvatar({
    required String imagePath,
    required String name,
    required Color crownColor,
    required double angle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Transform.rotate(
            angle: angle,
            child: Container(
              width: 58,
              height: 72,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: crownColor.withValues(alpha: 0.7),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: crownColor.withValues(alpha: 0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(
                      imagePath,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.high,
                      errorBuilder: (_, __, ___) => Container(
                        color: Colors.grey[850],
                        child: Icon(Icons.person, color: crownColor),
                      ),
                    ),
                    // Subtle bottom gradient
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      height: 24,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.8),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Crown icon at top corner
                    Positioned(
                      top: 3,
                      right: 3,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.workspace_premium,
                          color: crownColor,
                          size: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                style: TextStyle(
                  color: crownColor,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildShortcutPill({
    required _BirthdayFilter filter,
    required String emoji,
    required String title,
    required int count,
    bool isHighlight = false,
  }) {
    final isSelected = _activeFilter == filter;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _activeFilter = filter;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? tabColor.withValues(alpha: 0.22)
                : const Color(0xFF14121E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? tabColor
                  : (isHighlight
                      ? Colors.amber.withValues(alpha: 0.5)
                      : dividerColor),
              width: isSelected ? 1.5 : 1.0,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: tabColor.withValues(alpha: 0.22),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 13)),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.w600,
                        color: isSelected ? Colors.white : Colors.grey[400],
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
                decoration: BoxDecoration(
                  color: isSelected
                      ? tabColor
                      : (count > 0
                          ? (isHighlight
                              ? Colors.amber.withValues(alpha: 0.25)
                              : Colors.grey[800])
                          : Colors.transparent),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  count > 0 ? '$count' : '0',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isSelected
                        ? Colors.white
                        : (isHighlight && count > 0
                            ? Colors.amber
                            : Colors.grey[500]),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEventCard(Event event, DateTime now) {
    final occurrence = _getEventOccurrence(event, now);
    final today = DateTime(now.year, now.month, now.day);
    final diffDays = occurrence.difference(today).inDays;

    String countdownText;
    Color badgeColor;
    if (diffDays == 0) {
      countdownText = '🎉 TODAY!';
      badgeColor = Colors.amber;
    } else if (diffDays == 1) {
      countdownText = 'Tomorrow';
      badgeColor = const Color(0xFF00E5FF);
    } else if (diffDays > 1 && diffDays <= 7) {
      countdownText = 'In $diffDays days';
      badgeColor = tabColor;
    } else {
      countdownText = DateFormat('MMM dd').format(occurrence);
      badgeColor = accentOrange;
    }

    final isBirthday = event.title.toLowerCase().contains('birth') ||
        event.title.toLowerCase().contains('bday');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF14121E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: diffDays == 0
              ? Colors.amber.withValues(alpha: 0.5)
              : dividerColor,
          width: diffDays == 0 ? 1.4 : 1.0,
        ),
        boxShadow: diffDays == 0
            ? [
                BoxShadow(
                  color: Colors.amber.withValues(alpha: 0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _navigateToCalendar(occurrence),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                // Icon Avatar
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isBirthday
                          ? [
                              const Color(0xFFFF2D78),
                              const Color(0xFFFF8E53),
                            ]
                          : [
                              const Color(0xFF7928CA),
                              const Color(0xFFFF0080),
                            ],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Icon(
                      isBirthday ? Icons.cake : Icons.celebration,
                      color: Colors.white,
                      size: 19,
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // Title & Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              event.title,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (event.isRecurring)
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: accentOrange.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: const Text(
                                'YEARLY',
                                style: TextStyle(
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.bold,
                                  color: accentOrange,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time,
                            size: 11,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(width: 3),
                          Text(
                            event.time.format(context),
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[400],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.calendar_today,
                            size: 11,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(width: 3),
                          Text(
                            DateFormat('MMM dd').format(occurrence),
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[400],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // Countdown badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: badgeColor.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    countdownText,
                    style: TextStyle(
                      color: badgeColor,
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    String titleText;
    String subtitleText;
    switch (_activeFilter) {
      case _BirthdayFilter.today:
        titleText = 'No Birthdays Today';
        subtitleText = "Check weekly or monthly tabs for upcoming events";
        break;
      case _BirthdayFilter.weekly:
        titleText = 'No Birthdays This Week';
        subtitleText = "No celebrations coming up in the next 7 days";
        break;
      case _BirthdayFilter.monthly:
        titleText = 'No Birthdays This Month';
        subtitleText = "No events scheduled for the current month";
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF14121E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: dividerColor),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: tabColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.cake_outlined,
              color: tabColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titleText,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitleText,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _showAddEventDialog,
            icon: const Icon(Icons.add, size: 13, color: Colors.white),
            label: const Text(
              'Add',
              style: TextStyle(fontSize: 11, color: Colors.white),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: tabColor,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
