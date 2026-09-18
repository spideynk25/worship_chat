// ============================================
// File: lib/repositories/event_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:worship_chat/models/event.dart';
// import 'package:your_app/models/event.dart';

// Provider for FirebaseFirestore instance
final firestoreProvider = Provider<FirebaseFirestore>((ref) {
  return FirebaseFirestore.instance;
});

// Provider for FirebaseAuth instance
final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

// Provider for current user
final currentUserProvider = StreamProvider<User?>((ref) {
  final auth = ref.watch(firebaseAuthProvider);
  return auth.authStateChanges();
});

// Provider for EventRepository
final eventRepositoryProvider = Provider<EventRepository>((ref) {
  final firestore = ref.watch(firestoreProvider);
  final auth = ref.watch(firebaseAuthProvider);
  return EventRepository(firestore: firestore, auth: auth);
});

class EventRepository {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  EventRepository({
    required this.firestore,
    required this.auth,
  });

  // Get current user
  User? get currentUser => auth.currentUser;

  // Load all events from Firebase
  Future<List<Event>> fetchEvents() async {
    try {
      final querySnapshot = await firestore
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
    return firestore
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

    try {
      final docRef = await firestore.collection('events').add(event.toMap());

      return event.copyWith(id: docRef.id);
    } catch (e) {
      throw Exception('Error creating event: $e');
    }
  }

  // Update an event in Firebase
  Future<void> updateEvent(Event event) async {
    try {
      await firestore
          .collection('events')
          .doc(event.id)
          .update(event.toMap());
    } catch (e) {
      throw Exception('Error updating event: $e');
    }
  }

  // Delete an event from Firebase
  Future<void> deleteEvent(String eventId) async {
    try {
      await firestore.collection('events').doc(eventId).delete();
    } catch (e) {
      throw Exception('Error deleting event: $e');
    }
  }

  // Check if user can delete event
  bool canDeleteEvent(Event event) {
    final user = currentUser;
    return user != null && user.uid == event.userId;
  }
}