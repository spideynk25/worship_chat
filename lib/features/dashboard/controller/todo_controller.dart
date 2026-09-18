import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:worship_chat/features/dashboard/providers/todo_providers.dart';
import 'package:worship_chat/features/dashboard/repositories/todo_repository.dart';
import 'package:worship_chat/models/subtasks.dart';
import 'package:worship_chat/models/todo.dart';

class TodoController extends StateNotifier<AsyncValue<void>> {
  final TodoRepository _repository;

  TodoController(this._repository) : super(const AsyncValue.data(null));

  String? get _currentUserId => FirebaseAuth.instance.currentUser?.uid;

  // Main Tasks
  Future<void> createTodo({
    required String title,
    String description = '',
  }) async {
    if (_currentUserId == null) throw Exception('User not authenticated');
    
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final todo = TodoModel(
        title: title,
        description: description,
        createdBy: _currentUserId!,
      );
      await _repository.createTodo(todo);
    });
  }

  Future<void> updateTodo({
    required String id,
    required String title,
    String? description,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final existingTodo = await _repository.getTodoById(id);
      if (existingTodo == null) throw Exception('Todo not found');
      
      final updatedTodo = existingTodo.copyWith(
        title: title,
        description: description,
      );
      await _repository.updateTodo(id, updatedTodo);
    });
  }

  Future<void> deleteTodo(String id) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await _repository.deleteTodo(id);
    });
  }

  // Subtasks
  Future<void> createSubtask({
    required String parentTaskId,
    required String title,
    String description = '',
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final subtask = SubtaskModel(
        title: title,
        description: description,
        parentTaskId: parentTaskId,
      );
      await _repository.createSubtask(subtask);
    });
  }

  Future<void> updateSubtask({
    required String id,
    required String title,
    String? description,
    bool? completed,
    required String parentTaskId,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final subtask = SubtaskModel(
        id: id,
        title: title,
        description: description ?? '',
        completed: completed ?? false,
        parentTaskId: parentTaskId,
      );
      await _repository.updateSubtask(id, subtask);
    });
  }

  Future<void> toggleSubtaskCompletion(String id, bool currentStatus, String parentTaskId) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await _repository.toggleSubtaskCompletion(id, currentStatus, parentTaskId);
    });
  }

  Future<void> deleteSubtask(String id, String parentTaskId) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await _repository.deleteSubtask(id, parentTaskId);
    });
  }
}

final todoControllerProvider = StateNotifierProvider<TodoController, AsyncValue<void>>((ref) {
  final repository = ref.watch(todoRepositoryProvider);
  return TodoController(repository);
});