import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:worship_chat/models/subtasks.dart';
import 'package:worship_chat/models/todo.dart';

class TodoRepository {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  TodoRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance {
    _firestore.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  }

  String? get currentUserId => _auth.currentUser?.uid;
  // Shared collection for all users
  CollectionReference get _todosCollection => 
      _firestore.collection('shared_tasks');

  CollectionReference get _subtasksCollection => 
      _firestore.collection('subtasks');

  // === MAIN TASKS ===
  Future<String> createTodo(TodoModel todo) async {
    try {
      final docRef = await _todosCollection.add(todo.toFirestore());
      return docRef.id;
    } catch (e) {
      throw Exception('Failed to create todo: $e');
    }
  }

  Stream<List<TodoModel>> getTodosStream() {
    try {
      return _todosCollection
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((snapshot) {
        return snapshot.docs.map((doc) => TodoModel.fromFirestore(doc)).toList();
      });
    } catch (e) {
      throw Exception('Failed to get todos stream: $e');
    }
  }

  Future<TodoModel?> getTodoById(String id) async {
    try {
      final doc = await _todosCollection.doc(id).get();
      if (doc.exists) {
        return TodoModel.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      throw Exception('Failed to get todo: $e');
    }
  }

  Future<void> updateTodo(String id, TodoModel todo) async {
    try {
      await _todosCollection.doc(id).update({
        'title': todo.title,
        'description': todo.description,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Failed to update todo: $e');
    }
  }

  Future<void> deleteTodo(String id) async {
    try {
      // Delete all subtasks first
      final subtasks = await _subtasksCollection
          .where('parentTaskId', isEqualTo: id)
          .get();
      
      final batch = _firestore.batch();
      for (var doc in subtasks.docs) {
        batch.delete(doc.reference);
      }
      
      // Delete the main task
      batch.delete(_todosCollection.doc(id));
      await batch.commit();
    } catch (e) {
      throw Exception('Failed to delete todo: $e');
    }
  }

  // === SUBTASKS ===
  Future<String> createSubtask(SubtaskModel subtask) async {
    try {
      final docRef = await _subtasksCollection.add(subtask.toFirestore());
      
      // Update parent task subtask count
      await _updateParentTaskCounts(subtask.parentTaskId);
      
      return docRef.id;
    } catch (e) {
      throw Exception('Failed to create subtask: $e');
    }
  }

  Stream<List<SubtaskModel>> getSubtasksStream(String parentTaskId) {
    try {
      return _subtasksCollection
          .where('parentTaskId', isEqualTo: parentTaskId)
          .orderBy('createdAt', descending: false)
          .snapshots()
          .map((snapshot) {
        return snapshot.docs.map((doc) => SubtaskModel.fromFirestore(doc)).toList();
      });
    } catch (e) {
      throw Exception('Failed to get subtasks stream: $e');
    }
  }

  Future<void> updateSubtask(String id, SubtaskModel subtask) async {
    try {
      await _subtasksCollection.doc(id).update({
        'title': subtask.title,
        'description': subtask.description,
        'completed': subtask.completed,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      // Update parent task counts
      await _updateParentTaskCounts(subtask.parentTaskId);
    } catch (e) {
      throw Exception('Failed to update subtask: $e');
    }
  }

  Future<void> toggleSubtaskCompletion(String id, bool currentStatus, String parentTaskId) async {
    try {
      await _subtasksCollection.doc(id).update({
        'completed': !currentStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      // Update parent task counts
      await _updateParentTaskCounts(parentTaskId);
    } catch (e) {
      throw Exception('Failed to toggle subtask: $e');
    }
  }

  Future<void> deleteSubtask(String id, String parentTaskId) async {
    try {
      await _subtasksCollection.doc(id).delete();
      
      // Update parent task counts
      await _updateParentTaskCounts(parentTaskId);
    } catch (e) {
      throw Exception('Failed to delete subtask: $e');
    }
  }

  // Update parent task with subtask counts
  Future<void> _updateParentTaskCounts(String parentTaskId) async {
    try {
      final subtasks = await _subtasksCollection
          .where('parentTaskId', isEqualTo: parentTaskId)
          .get();
      
      final total = subtasks.docs.length;
      final completed = subtasks.docs.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return data['completed'] == true;
      }).length;
      
      await _todosCollection.doc(parentTaskId).update({
        'totalSubtasks': total,
        'completedSubtasks': completed,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Failed to update parent task counts: $e');
    }
  }
}