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

  // Create Event from Firestore document
  factory Event.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Event(
      id: doc.id,
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      date: (data['date'] as Timestamp).toDate(),
      time: TimeOfDay(
        hour: data['timeHour'] ?? 0,
        minute: data['timeMinute'] ?? 0,
      ),
      createdBy: data['createdBy'] ?? 'Anonymous',
      userId: data['userId'] ?? '',
      isRecurring: data['isRecurring'] ?? false,
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
