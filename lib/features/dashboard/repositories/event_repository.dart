// ============================================
// File: lib/repositories/event_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:worship_chat/models/event.dart';
// import 'package:your_app/models/event.dart';

// Provider for FirebaseFirestore instance
final firestoreProvider = Provider<FirebaseFirestore?>((ref) {
  try {
    return FirebaseFirestore.instance;
  } catch (_) {
    return null;
  }
});

// Provider for FirebaseAuth instance
final firebaseAuthProvider = Provider<FirebaseAuth?>((ref) {
  try {
    return FirebaseAuth.instance;
  } catch (_) {
    return null;
  }
});

// Provider for current user
final currentUserProvider = StreamProvider<User?>((ref) {
  final auth = ref.watch(firebaseAuthProvider);
  if (auth == null) return const Stream.empty();
  return auth.authStateChanges();
});

// Provider for EventRepository
final eventRepositoryProvider = Provider<EventRepository>((ref) {
  final firestore = ref.watch(firestoreProvider);
  final auth = ref.watch(firebaseAuthProvider);
  return EventRepository(firestore: firestore, auth: auth);
});

class EventRepository {
  final FirebaseFirestore? firestore;
  final FirebaseAuth? auth;

  EventRepository({
    this.firestore,
    this.auth,
  });

  // Get current user
  User? get currentUser => auth?.currentUser;

  // Load all events from Firebase
  Future<List<Event>> fetchEvents() async {
    final fs = firestore;
    if (fs == null) return const [];
    try {
      final querySnapshot = await fs
          .collection('events')
          .orderBy('date')
          .get();

      return querySnapshot.docs
          .map((doc) => Event.fromFirestore(doc))
          .toList();
    } catch (e) {
      throw Exception('Error loading events: $e');
    }
  }

  // Stream of events for real-time updates
  Stream<List<Event>> eventsStream() {
    final fs = firestore;
    if (fs == null) return const Stream.empty();
    return fs
        .collection('events')
        .orderBy('date')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => Event.fromFirestore(doc)).toList();
    });
  }

  // Create a new event in Firebase
  Future<Event> createEvent(Event event) async {
    final user = currentUser;
    if (user == null) {
      throw Exception('User must be signed in to create events');
    }
    final fs = firestore;
    if (fs == null) {
      throw Exception('Firestore not initialized');
    }

    try {
      final docRef = await fs.collection('events').add(event.toMap());

      return event.copyWith(id: docRef.id);
    } catch (e) {
      throw Exception('Error creating event: $e');
    }
  }

  // Update an event in Firebase
  Future<void> updateEvent(Event event) async {
    final fs = firestore;
    if (fs == null) return;
    try {
      await fs
          .collection('events')
          .doc(event.id)
          .update(event.toUpdateMap());
    } catch (e) {
      throw Exception('Error updating event: $e');
    }
  }

  // Delete an event from Firebase
  Future<void> deleteEvent(String eventId) async {
    final fs = firestore;
    if (fs == null) return;
    try {
      await fs.collection('events').doc(eventId).delete();
    } catch (e) {
      throw Exception('Error deleting event: $e');
    }
  }

  // Check if user can delete event
  bool canDeleteEvent(Event event) {
    return true;
  }

  // Check if user can edit event
  bool canEditEvent(Event event) {
    return true;
  }
}