import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class Event {
  final String id;
  final String title;
  final String description;
  final DateTime date;
  final TimeOfDay time;
  final String createdBy;
  final String userId;
  final bool isRecurring; // New field for recurring events

  Event({
    required this.id,
    required this.title,
    required this.description,
    required this.date,
    required this.time,
    required this.createdBy,
    required this.userId,
    this.isRecurring = false, // Default to false
  });

  // Convert Event to Map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'description': description,
      'date': Timestamp.fromDate(date),
      'timeHour': time.hour,
      'timeMinute': time.minute,
      'createdBy': createdBy,
      'userId': userId,
      'isRecurring': isRecurring,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  // Convert Event to Map for updating in Firestore (preserves creator and created timestamp)
  Map<String, dynamic> toUpdateMap() {
    return {
      'title': title,
      'description': description,
      'date': Timestamp.fromDate(date),
      'timeHour': time.hour,
      'timeMinute': time.minute,
      'isRecurring': isRecurring,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  // Create Event from Firestore document
  factory Event.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};
    DateTime eventDate;
    final rawDate = data['date'];
    if (rawDate is Timestamp) {
      eventDate = rawDate.toDate();
    } else if (rawDate is int) {
      eventDate = DateTime.fromMillisecondsSinceEpoch(rawDate);
    } else if (rawDate is String) {
      eventDate = DateTime.tryParse(rawDate) ?? DateTime.now();
    } else {
      eventDate = DateTime.now();
    }

    return Event(
      id: doc.id,
      title: data['title'] as String? ?? '',
      description: data['description'] as String? ?? '',
      date: eventDate,
      time: TimeOfDay(
        hour: (data['timeHour'] as num?)?.toInt() ?? 0,
        minute: (data['timeMinute'] as num?)?.toInt() ?? 0,
      ),
      createdBy: data['createdBy'] as String? ?? 'Anonymous',
      userId: data['userId'] as String? ?? '',
      isRecurring: data['isRecurring'] as bool? ?? false,
    );
  }

  // Create a copy of the event with updated fields
  Event copyWith({
    String? id,
    String? title,
    String? description,
    DateTime? date,
    TimeOfDay? time,
    String? createdBy,
    String? userId,
    bool? isRecurring,
  }) {
    return Event(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      date: date ?? this.date,
      time: time ?? this.time,
      createdBy: createdBy ?? this.createdBy,
      userId: userId ?? this.userId,
      isRecurring: isRecurring ?? this.isRecurring,
    );
  }
}
