import 'package:cloud_firestore/cloud_firestore.dart';

class TodoModel {
  final String? id;
  final String title;
  final String description;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String createdBy;
  final int totalSubtasks;
  final int completedSubtasks;

  TodoModel({
    this.id,
    required this.title,
    this.description = '',
    this.createdAt,
    this.updatedAt,
    required this.createdBy,
    this.totalSubtasks = 0,
    this.completedSubtasks = 0,
  });

  factory TodoModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return TodoModel(
      id: doc.id,
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      createdBy: data['createdBy'] ?? '',
      totalSubtasks: data['totalSubtasks'] ?? 0,
      completedSubtasks: data['completedSubtasks'] ?? 0,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'description': description,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'createdBy': createdBy,
      'totalSubtasks': totalSubtasks,
      'completedSubtasks': completedSubtasks,
    };
  }

  TodoModel copyWith({
    String? id,
    String? title,
    String? description,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? createdBy,
    int? totalSubtasks,
    int? completedSubtasks,
  }) {
    return TodoModel(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdBy: createdBy ?? this.createdBy,
      totalSubtasks: totalSubtasks ?? this.totalSubtasks,
      completedSubtasks: completedSubtasks ?? this.completedSubtasks,
    );
  }

  double get progress {
    if (totalSubtasks == 0) return 0.0;
    return completedSubtasks / totalSubtasks;
  }
}