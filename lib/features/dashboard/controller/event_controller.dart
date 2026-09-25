// ============================================
// File: lib/controllers/event_controller.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:worship_chat/features/dashboard/repositories/event_repository.dart';
import 'package:worship_chat/models/event.dart';
// import 'package:your_app/models/event.dart';
// import 'package:your_app/repositories/event_repository.dart';

// State class for events
class EventState {
  final Map<DateTime, List<Event>> events;
  final bool isLoading;
  final String? error;

  EventState({
    required this.events,
    this.isLoading = false,
    this.error,
  });

  EventState copyWith({
    Map<DateTime, List<Event>>? events,
    bool? isLoading,
    String? error,
  }) {
    return EventState(
      events: events ?? this.events,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

// Event Controller
class EventController extends StateNotifier<EventState> {
  final EventRepository _repository;

  EventController(this._repository)
      : super(EventState(events: {}, isLoading: false));

  // Load events from repository
  Future<void> loadEvents() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final events = await _repository.fetchEvents();
      final eventsMap = _groupEventsByDate(events);

      state = EventState(
        events: eventsMap,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  // Create a new event
  Future<void> createEvent({
    required String title,
    required String description,
    required DateTime date,
    required TimeOfDay time,
    required bool isRecurring,
  }) async {
    try {
      final user = _repository.currentUser;
      if (user == null) {
        throw Exception('User must be signed in to create events');
      }

      final event = Event(
        id: '',
        title: title,
        description: description,
        date: date,
        time: time,
        createdBy: user.displayName ?? user.email ?? 'Anonymous',
        userId: user.uid,
        isRecurring: isRecurring,
      );

      final createdEvent = await _repository.createEvent(event);

      // Update local state
      final eventDate = DateTime(date.year, date.month, date.day);
      final updatedEvents = Map<DateTime, List<Event>>.from(state.events);

      if (updatedEvents[eventDate] == null) {
        updatedEvents[eventDate] = [];
      }
      updatedEvents[eventDate]!.add(createdEvent);

      state = state.copyWith(events: updatedEvents);
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  // Delete an event
  Future<void> deleteEvent(Event event) async {
    try {
      await _repository.deleteEvent(event.id);

      // Update local state
      final eventDate = DateTime(
        event.date.year,
        event.date.month,
        event.date.day,
      );
      final updatedEvents = Map<DateTime, List<Event>>.from(state.events);

      updatedEvents[eventDate]?.removeWhere((e) => e.id == event.id);
      if (updatedEvents[eventDate]?.isEmpty ?? false) {
        updatedEvents.remove(eventDate);
      }

      state = state.copyWith(events: updatedEvents);
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  // Update an event
  Future<void> updateEvent(Event event) async {
    try {
      await _repository.updateEvent(event);

      // Update local state:
      // Remove from all existing date entries in case date was modified
      final updatedEvents = Map<DateTime, List<Event>>.from(state.events);
      for (final key in updatedEvents.keys.toList()) {
        final list = List<Event>.from(updatedEvents[key]!);
        list.removeWhere((e) => e.id == event.id);
        if (list.isEmpty) {
          updatedEvents.remove(key);
        } else {
          updatedEvents[key] = list;
        }
      }

      // Add to new date bucket
      final eventDate = DateTime(
        event.date.year,
        event.date.month,
        event.date.day,
      );

      if (updatedEvents[eventDate] == null) {
        updatedEvents[eventDate] = [];
      } else {
        updatedEvents[eventDate] = List<Event>.from(updatedEvents[eventDate]!);
      }
      updatedEvents[eventDate]!.add(event);

      state = state.copyWith(events: updatedEvents);
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  // Get events for a specific day
  List<Event> getEventsForDay(DateTime day) {
    final normalizedDay = DateTime(day.year, day.month, day.day);
    final regularEvents = state.events[normalizedDay] ?? [];
    
    // Also get recurring events that match month and day
    final recurringEvents = <Event>[];
    for (final entry in state.events.entries) {
      for (final event in entry.value) {
        if (event.isRecurring) {
          // Check if month and day match, but not the same year as stored
          if (event.date.month == day.month && 
              event.date.day == day.day &&
              event.date.year != day.year) {
            // Create a copy with the requested year
            final recurringEvent = event.copyWith(
              date: DateTime(day.year, event.date.month, event.date.day),
            );
            recurringEvents.add(recurringEvent);
          }
        }
      }
    }
    
    // Combine regular events and recurring events
    return [...regularEvents, ...recurringEvents];
  }

  // Check if user can edit event
  bool canEditEvent(Event event) {
    return _repository.canEditEvent(event);
  }

  // Check if user can delete event
  bool canDeleteEvent(Event event) {
    return _repository.canDeleteEvent(event);
  }

  // Helper method to group events by date
  Map<DateTime, List<Event>> _groupEventsByDate(List<Event> events) {
    final Map<DateTime, List<Event>> groupedEvents = {};

    for (final event in events) {
      final eventDate = DateTime(
        event.date.year,
        event.date.month,
        event.date.day,
      );

      if (groupedEvents[eventDate] == null) {
        groupedEvents[eventDate] = [];
      }
      groupedEvents[eventDate]!.add(event);
    }

    return groupedEvents;
  }
}

// Provider for EventController
final eventControllerProvider =
    StateNotifierProvider<EventController, EventState>((ref) {
  final repository = ref.watch(eventRepositoryProvider);
  return EventController(repository);
});

// Provider for events of a specific day
final eventsForDayProvider =
    Provider.family<List<Event>, DateTime>((ref, date) {
  final controller = ref.watch(eventControllerProvider.notifier);
  return controller.getEventsForDay(date);
});