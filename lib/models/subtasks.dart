import 'package:cloud_firestore/cloud_firestore.dart';

class SubtaskModel {
  final String? id;
  final String title;
  final String description;
  final bool completed;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String parentTaskId;

  SubtaskModel({
    this.id,
    required this.title,
    this.description = '',
    this.completed = false,
    this.createdAt,
    this.updatedAt,
    required this.parentTaskId,
  });

  factory SubtaskModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return SubtaskModel(
      id: doc.id,
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      completed: data['completed'] ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      parentTaskId: data['parentTaskId'] ?? '',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'description': description,
      'completed': completed,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'parentTaskId': parentTaskId,
    };
  }

  SubtaskModel copyWith({
    String? id,
    String? title,
    String? description,
    bool? completed,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? parentTaskId,
  }) {
    return SubtaskModel(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      completed: completed ?? this.completed,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      parentTaskId: parentTaskId ?? this.parentTaskId,
    );
  }
}