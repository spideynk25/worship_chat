import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/widgets/skeleton_loader.dart';
import 'package:worship_chat/features/dashboard/controller/event_controller.dart';
import 'package:worship_chat/models/event.dart';

class EventsCalendarPage extends ConsumerStatefulWidget {
  static const String routeName = '/events-calendar-page';
  final DateTime? initialSelectedDay;
  const EventsCalendarPage({super.key, this.initialSelectedDay});

  @override
  ConsumerState<EventsCalendarPage> createState() => _EventsCalendarPageState();
}

class _EventsCalendarPageState extends ConsumerState<EventsCalendarPage> {
  CalendarFormat _calendarFormat = CalendarFormat.month;
  late DateTime _focusedDay;
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    _focusedDay = widget.initialSelectedDay ?? DateTime.now();
    _selectedDay = _focusedDay;
    // Load events when widget initializes
    Future.microtask(() {
      ref.read(eventControllerProvider.notifier).loadEvents();
    });
  }

  List<Event> _getEventsForDay(DateTime day) {
    final controller = ref.read(eventControllerProvider.notifier);
    return controller.getEventsForDay(day);
  }

  void _jumpToToday() {
    final now = DateTime.now();
    setState(() {
      _selectedDay = now;
      _focusedDay = now;
    });
  }

  void _showCreateEventDialog() {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    DateTime selectedDate = _selectedDay ?? DateTime.now();
    TimeOfDay selectedTime = TimeOfDay.now();
    bool isRecurring = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1B1528),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: tabColor.withValues(alpha: 0.35)),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF2D78), Color(0xFFFF8E53)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.cake_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Create Event',
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
                    prefixIcon: const Icon(Icons.title, color: tabColor, size: 20),
                    filled: true,
                    fillColor: const Color(0xFF120E1C),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: tabColor, width: 1.5),
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
                    prefixIcon: const Icon(Icons.notes, color: tabColor, size: 20),
                    filled: true,
                    fillColor: const Color(0xFF120E1C),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: tabColor, width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF120E1C),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: tabColor.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.calendar_month, color: tabColor, size: 18),
                    ),
                    title: Text(
                      'Date',
                      style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    ),
                    subtitle: Text(
                      DateFormat('EEE, MMM dd, yyyy').format(selectedDate),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    trailing: const Icon(Icons.edit_calendar, color: tabColor, size: 18),
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
                              surface: Color(0xFF1B1528),
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
                ),
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF120E1C),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: accentOrange.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.access_time, color: accentOrange, size: 18),
                    ),
                    title: Text(
                      'Time',
                      style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    ),
                    subtitle: Text(
                      selectedTime.format(context),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    trailing: const Icon(Icons.arrow_drop_down, color: accentOrange),
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: selectedTime,
                        builder: (context, child) => Theme(
                          data: Theme.of(context).copyWith(
                            colorScheme: const ColorScheme.dark(
                              primary: tabColor,
                              onPrimary: Colors.white,
                              surface: Color(0xFF1B1528),
                              onSurface: Colors.white,
                            ),
                          ),
                          child: child!,
                        ),
                      );
                      if (picked != null) {
                        setDialogState(() => selectedTime = picked);
                      }
                    },
                  ),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Repeat Every Year',
                    style: TextStyle(color: Colors.white, fontSize: 14),
                  ),
                  subtitle: Text(
                    'Repeats annually on ${DateFormat('MMM dd').format(selectedDate)} (Birthdays/Anniversaries)',
                    style: TextStyle(color: Colors.grey[500], fontSize: 11),
                  ),
                  value: isRecurring,
                  activeColor: tabColor,
                  checkColor: Colors.white,
                  onChanged: (val) {
                    setDialogState(() => isRecurring = val ?? false);
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
              onPressed: () {
                final title = titleController.text.trim();
                if (title.isNotEmpty) {
                  _createEvent(
                    title: title,
                    description: descriptionController.text.trim(),
                    date: selectedDate,
                    time: selectedTime,
                    isRecurring: isRecurring,
                  );
                  Navigator.pop(context);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: tabColor,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 3,
              ),
              child: const Text(
                'Create',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditEventDialog(Event event) {
    final titleController = TextEditingController(text: event.title);
    final descriptionController = TextEditingController(text: event.description);
    DateTime selectedDate = event.date;
    TimeOfDay selectedTime = event.time;
    bool isRecurring = event.isRecurring;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1B1528),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: tabColor.withValues(alpha: 0.35)),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF2D78), Color(0xFFFF8E53)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.edit_calendar,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Edit Event',
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
                    labelText: 'Event Title',
                    labelStyle: TextStyle(color: Colors.grey[400]),
                    prefixIcon: const Icon(Icons.title, color: tabColor, size: 20),
                    filled: true,
                    fillColor: const Color(0xFF120E1C),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: tabColor, width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: descriptionController,
                  style: const TextStyle(color: Colors.white),
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Description',
                    labelStyle: TextStyle(color: Colors.grey[400]),
                    prefixIcon: const Icon(Icons.notes, color: tabColor, size: 20),
                    filled: true,
                    fillColor: const Color(0xFF120E1C),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: tabColor, width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF120E1C),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: tabColor.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.calendar_month, color: tabColor, size: 18),
                    ),
                    title: Text(
                      'Date',
                      style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    ),
                    subtitle: Text(
                      DateFormat('EEE, MMM dd, yyyy').format(selectedDate),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    trailing: const Icon(Icons.edit_calendar, color: tabColor, size: 18),
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
                              surface: Color(0xFF1B1528),
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
                ),
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF120E1C),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: accentOrange.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.access_time, color: accentOrange, size: 18),
                    ),
                    title: Text(
                      'Time',
                      style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    ),
                    subtitle: Text(
                      selectedTime.format(context),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    trailing: const Icon(Icons.arrow_drop_down, color: accentOrange),
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: selectedTime,
                        builder: (context, child) => Theme(
                          data: Theme.of(context).copyWith(
                            colorScheme: const ColorScheme.dark(
                              primary: tabColor,
                              onPrimary: Colors.white,
                              surface: Color(0xFF1B1528),
                              onSurface: Colors.white,
                            ),
                          ),
                          child: child!,
                        ),
                      );
                      if (picked != null) {
                        setDialogState(() => selectedTime = picked);
                      }
                    },
                  ),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Repeat Every Year',
                    style: TextStyle(color: Colors.white, fontSize: 14),
                  ),
                  subtitle: Text(
                    'Repeats annually on ${DateFormat('MMM dd').format(selectedDate)} (Birthdays/Anniversaries)',
                    style: TextStyle(color: Colors.grey[500], fontSize: 11),
                  ),
                  value: isRecurring,
                  activeColor: tabColor,
                  checkColor: Colors.white,
                  onChanged: (val) {
                    setDialogState(() => isRecurring = val ?? false);
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
              onPressed: () {
                final title = titleController.text.trim();
                if (title.isNotEmpty) {
                  _updateEvent(
                    event: event,
                    title: title,
                    description: descriptionController.text.trim(),
                    date: selectedDate,
                    time: selectedTime,
                    isRecurring: isRecurring,
                  );
                  Navigator.pop(context);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: tabColor,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 3,
              ),
              child: const Text(
                'Save Changes',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createEvent({
    required String title,
    required String description,
    required DateTime date,
    required TimeOfDay time,
    required bool isRecurring,
  }) async {
    try {
      await ref.read(eventControllerProvider.notifier).createEvent(
            title: title,
            description: description,
            date: date,
            time: time,
            isRecurring: isRecurring,
          );

      if (mounted) {
        setState(() {
          _selectedDay = date;
          _focusedDay = date;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isRecurring
                  ? '🎉 Recurring event created! Will appear every year on ${DateFormat('MMM dd').format(date)}'
                  : 'Event created successfully!',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _updateEvent({
    required Event event,
    required String title,
    required String description,
    required DateTime date,
    required TimeOfDay time,
    required bool isRecurring,
  }) async {
    try {
      final updatedEvent = event.copyWith(
        title: title,
        description: description,
        date: date,
        time: time,
        isRecurring: isRecurring,
      );

      await ref.read(eventControllerProvider.notifier).updateEvent(updatedEvent);

      if (mounted) {
        setState(() {
          _selectedDay = date;
          _focusedDay = date;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isRecurring
                  ? 'Event updated! Will appear every year on ${DateFormat('MMM dd').format(date)}'
                  : 'Event updated successfully!',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _confirmDeleteEvent(Event event) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1B1528),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.3)),
        ),
        title: const Row(
          children: [
            Icon(Icons.delete_outline, color: Colors.redAccent, size: 22),
            SizedBox(width: 8),
            Text(
              'Delete Event',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          event.isRecurring
              ? 'Are you sure you want to delete this recurring celebration ("${event.title}")? It will be removed from all years.'
              : 'Are you sure you want to delete "${event.title}"?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[400])),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteEvent(event);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteEvent(Event event) async {
    try {
      await ref.read(eventControllerProvider.notifier).deleteEvent(event);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Event deleted successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final eventState = ref.watch(eventControllerProvider);
    final controller = ref.watch(eventControllerProvider.notifier);

    // Show error if any
    ref.listen<EventState>(eventControllerProvider, (previous, next) {
      if (next.error != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.error!), backgroundColor: Colors.red),
        );
      }
    });

    final isSelectedToday = isSameDay(_selectedDay, DateTime.now());

    return Scaffold(
      backgroundColor: const Color(0xFF0F0C18),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161224),
        elevation: 0,
        centerTitle: false,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF2D78), Color(0xFFFF8E53)],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.calendar_month_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Events Calendar',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 0.3,
                  ),
                ),
                Text(
                  'Royal celebrations & reminders',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: Colors.grey,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          // "Today" quick jump button
          if (!isSelectedToday)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 11),
              child: TextButton.icon(
                onPressed: _jumpToToday,
                icon: const Icon(Icons.today_rounded, size: 14, color: tabColor),
                label: const Text(
                  'Today',
                  style: TextStyle(
                    color: tabColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                style: TextButton.styleFrom(
                  backgroundColor: tabColor.withValues(alpha: 0.12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: tabColor.withValues(alpha: 0.35)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Refresh events',
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            onPressed: () => ref.read(eventControllerProvider.notifier).loadEvents(),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: eventState.isLoading
          ? const CalendarPageSkeleton()
          : RefreshIndicator(
              color: tabColor,
              backgroundColor: const Color(0xFF1B1528),
              onRefresh: () async {
                await ref.read(eventControllerProvider.notifier).loadEvents();
              },
              child: Column(
                children: [
                  // ── Calendar Card Container ─────────────────────────
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFF1B1528),
                          mobileChatBoxColor,
                          const Color(0xFF161222),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: tabColor.withValues(alpha: 0.26),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.45),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                        BoxShadow(
                          color: tabColor.withValues(alpha: 0.08),
                          blurRadius: 22,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                    child: TableCalendar(
                      firstDay: DateTime.utc(2020, 1, 1),
                      lastDay: DateTime.utc(2035, 12, 31),
                      focusedDay: _focusedDay,
                      calendarFormat: _calendarFormat,
                      selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                      onDaySelected: (selectedDay, focusedDay) {
                        setState(() {
                          _selectedDay = selectedDay;
                          _focusedDay = focusedDay;
                        });
                      },
                      onFormatChanged: (format) {
                        setState(() {
                          _calendarFormat = format;
                        });
                      },
                      onPageChanged: (focusedDay) {
                        _focusedDay = focusedDay;
                      },
                      eventLoader: _getEventsForDay,
                      calendarStyle: const CalendarStyle(
                        outsideDaysVisible: true,
                        defaultTextStyle: TextStyle(color: Colors.white, fontSize: 13),
                        weekendTextStyle: TextStyle(color: Color(0xFFFF8DA1), fontSize: 13),
                      ),
                      headerStyle: HeaderStyle(
                        formatButtonVisible: true,
                        titleCentered: true,
                        formatButtonShowsNext: false,
                        formatButtonDecoration: BoxDecoration(
                          color: tabColor.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: tabColor.withValues(alpha: 0.45)),
                        ),
                        formatButtonTextStyle: const TextStyle(
                          color: tabColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                        leftChevronIcon: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.07),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.chevron_left_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                        rightChevronIcon: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.07),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.chevron_right_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                        titleTextStyle: const TextStyle(
                          color: Colors.white,
                          fontSize: 16.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.4,
                        ),
                      ),
                      daysOfWeekStyle: DaysOfWeekStyle(
                        weekdayStyle: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                        weekendStyle: const TextStyle(
                          color: Color(0xFFFF6090),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      calendarBuilders: CalendarBuilders(
                        // Custom Marker Builder
                        markerBuilder: (context, date, events) {
                          if (events.isEmpty) return null;
                          final eventList = events.cast<Event>();
                          return Positioned(
                            bottom: 2,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: eventList.take(3).map((event) {
                                final isBday = event.title.toLowerCase().contains('birth') ||
                                    event.title.toLowerCase().contains('bday');
                                Color dotColor = tabColor;
                                if (isBday) {
                                  dotColor = const Color(0xFFFF2D78); // Pink
                                } else if (event.isRecurring) {
                                  dotColor = const Color(0xFFFFD700); // Gold
                                } else {
                                  dotColor = const Color(0xFF00E5FF); // Cyan
                                }
                                return Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 1.2),
                                  width: 5,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: dotColor,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: dotColor.withValues(alpha: 0.7),
                                        blurRadius: 3,
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          );
                        },

                        // Custom Selected Day Builder
                        selectedBuilder: (context, date, focusedDay) {
                          return Center(
                            child: Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [tabColor, Color(0xFFFF4081)],
                                ),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: tabColor.withValues(alpha: 0.45),
                                    blurRadius: 9,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '${date.day}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          );
                        },

                        // Custom Today Builder
                        todayBuilder: (context, date, focusedDay) {
                          final isSelected = isSameDay(_selectedDay, date);
                          if (isSelected) return null;
                          return Center(
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.amber,
                                  width: 1.6,
                                ),
                                color: Colors.amber.withValues(alpha: 0.14),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '${date.day}',
                                style: const TextStyle(
                                  color: Colors.amber,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          );
                        },

                        // Custom Outside Days Builder
                        outsideBuilder: (context, date, focusedDay) {
                          return Center(
                            child: Text(
                              '${date.day}',
                              style: TextStyle(
                                color: Colors.grey[700],
                                fontSize: 12.5,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                  // ── Selected Date Header & Quick Action ───────────────
                  Consumer(
                    builder: (context, ref, child) {
                      final selectedDate = _selectedDay ?? DateTime.now();
                      final eventsForDay = _getEventsForDay(selectedDate);
                      final isToday = isSameDay(selectedDate, DateTime.now());
                      final isTomorrow = isSameDay(
                        selectedDate,
                        DateTime.now().add(const Duration(days: 1)),
                      );

                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF1E172B), Color(0xFF161222)],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isToday
                                ? Colors.amber.withValues(alpha: 0.45)
                                : tabColor.withValues(alpha: 0.22),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: isToday
                                    ? Colors.amber.withValues(alpha: 0.18)
                                    : tabColor.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                isToday ? Icons.stars_rounded : Icons.event_available,
                                color: isToday ? Colors.amber : tabColor,
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        DateFormat('EEE, MMM dd, yyyy').format(selectedDate),
                                        style: const TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                      if (isToday) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: Colors.amber.withValues(alpha: 0.25),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: const Text(
                                            'TODAY',
                                            style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.w900,
                                              color: Colors.amber,
                                            ),
                                          ),
                                        ),
                                      ] else if (isTomorrow) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF00E5FF).withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: const Text(
                                            'TOMORROW',
                                            style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.w900,
                                              color: Color(0xFF00E5FF),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    eventsForDay.isEmpty
                                        ? 'No celebrations scheduled'
                                        : '${eventsForDay.length} celebration${eventsForDay.length > 1 ? 's' : ''}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey[400],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Mini Quick "+ Add" Button
                            GestureDetector(
                              onTap: _showCreateEventDialog,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5.5),
                                decoration: BoxDecoration(
                                  color: tabColor,
                                  borderRadius: BorderRadius.circular(10),
                                  boxShadow: [
                                    BoxShadow(
                                      color: tabColor.withValues(alpha: 0.35),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.add, size: 13, color: Colors.white),
                                    SizedBox(width: 3),
                                    Text(
                                      'Add',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 10),

                  // ── Events List or Empty State ───────────────────────
                  Expanded(
                    child: Consumer(
                      builder: (context, ref, child) {
                        final selectedDate = _selectedDay ?? DateTime.now();
                        final eventsForDay = _getEventsForDay(selectedDate);

                        if (eventsForDay.isEmpty) {
                          return _buildEmptyState();
                        }

                        return ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 2, 16, 80),
                          physics: const BouncingScrollPhysics(),
                          itemCount: eventsForDay.length,
                          itemBuilder: (context, index) {
                            final event = eventsForDay[index];
                            return _buildEventCard(event, controller);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateEventDialog,
        backgroundColor: tabColor,
        elevation: 6,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text(
          'Add Event',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    tabColor.withValues(alpha: 0.20),
                    const Color(0xFF7928CA).withValues(alpha: 0.14),
                  ],
                ),
                border: Border.all(
                  color: tabColor.withValues(alpha: 0.4),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: tabColor.withValues(alpha: 0.15),
                    blurRadius: 16,
                  ),
                ],
              ),
              child: const Center(
                child: Icon(
                  Icons.cake_outlined,
                  size: 38,
                  color: tabColor,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No Events on This Day',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Add a royal celebration, queen birthday, anniversary, or reminder.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: Colors.grey[400],
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: _showCreateEventDialog,
              icon: const Icon(Icons.add_circle_outline, size: 16, color: Colors.white),
              label: const Text(
                'Create Event',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: tabColor,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 4,
                shadowColor: tabColor.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventCard(Event event, EventController controller) {
    final isBirthday = event.title.toLowerCase().contains('birth') ||
        event.title.toLowerCase().contains('bday');

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final eventDay = DateTime(event.date.year, event.date.month, event.date.day);
    final diffDays = eventDay.difference(today).inDays;

    String? statusBadge;
    Color statusBadgeColor = tabColor;
    if (diffDays == 0) {
      statusBadge = '🎉 TODAY!';
      statusBadgeColor = Colors.amber;
    } else if (diffDays == 1) {
      statusBadge = 'Tomorrow';
      statusBadgeColor = const Color(0xFF00E5FF);
    } else if (diffDays > 1 && diffDays <= 7) {
      statusBadge = 'In $diffDays days';
      statusBadgeColor = tabColor;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A1528), Color(0xFF13101E)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: diffDays == 0
              ? Colors.amber.withValues(alpha: 0.5)
              : tabColor.withValues(alpha: 0.24),
          width: diffDays == 0 ? 1.4 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: diffDays == 0
                ? Colors.amber.withValues(alpha: 0.12)
                : Colors.black.withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showEditEventDialog(event),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row: Avatar icon + Title + Status + Action buttons
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Icon Box
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: isBirthday
                              ? [const Color(0xFFFF2D78), const Color(0xFFFF8E53)]
                              : (event.isRecurring
                                  ? [const Color(0xFFFFB300), const Color(0xFFFF7043)]
                                  : [const Color(0xFF7928CA), const Color(0xFFFF0080)]),
                        ),
                        borderRadius: BorderRadius.circular(11),
                        boxShadow: [
                          BoxShadow(
                            color: (isBirthday ? const Color(0xFFFF2D78) : tabColor)
                                .withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        isBirthday
                            ? Icons.cake_rounded
                            : (event.isRecurring
                                ? Icons.auto_awesome_rounded
                                : Icons.event_note_rounded),
                        color: Colors.white,
                        size: 21,
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Title & Time & Recurring tag
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
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (event.isRecurring) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: accentOrange.withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: accentOrange.withValues(alpha: 0.5),
                                    ),
                                  ),
                                  child: const Text(
                                    '🔁 YEARLY',
                                    style: TextStyle(
                                      color: accentOrange,
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.access_time_rounded,
                                size: 12.5,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                event.time.format(context),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[400],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (statusBadge != null) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: statusBadgeColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    statusBadge,
                                    style: TextStyle(
                                      color: statusBadgeColor,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Quick Action Buttons (Edit & Delete)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          color: tabColor,
                          padding: const EdgeInsets.all(6),
                          constraints: const BoxConstraints(),
                          tooltip: 'Edit Event',
                          onPressed: () => _showEditEventDialog(event),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          color: Colors.redAccent,
                          padding: const EdgeInsets.all(6),
                          constraints: const BoxConstraints(),
                          tooltip: 'Delete Event',
                          onPressed: () => _confirmDeleteEvent(event),
                        ),
                      ],
                    ),
                  ],
                ),

                // Description (if present)
                if (event.description.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      event.description,
                      style: TextStyle(fontSize: 12.5, color: Colors.grey[300]),
                    ),
                  ),
                ],

                const SizedBox(height: 10),
                Divider(color: Colors.white.withValues(alpha: 0.07), height: 1),
                const SizedBox(height: 8),

                // Footer attribution & action badges
                Row(
                  children: [
                    Icon(Icons.person_outline, size: 13, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Created by ${event.createdBy}',
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    InkWell(
                      onTap: () => _showEditEventDialog(event),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: tabColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: tabColor.withValues(alpha: 0.35)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.edit, size: 11, color: tabColor),
                            SizedBox(width: 3),
                            Text(
                              'Edit',
                              style: TextStyle(
                                color: tabColor,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: () => _confirmDeleteEvent(event),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.delete_outline, size: 11, color: Colors.redAccent),
                            SizedBox(width: 3),
                            Text(
                              'Delete',
                              style: TextStyle(
                                color: Colors.redAccent,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
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
  }
}
