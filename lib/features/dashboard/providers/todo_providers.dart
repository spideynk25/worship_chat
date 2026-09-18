import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:worship_chat/features/dashboard/repositories/todo_repository.dart';
import 'package:worship_chat/models/subtasks.dart';
import 'package:worship_chat/models/todo.dart';

// Repository Provider
final todoRepositoryProvider = Provider<TodoRepository>((ref) {
  return TodoRepository();
});

// Current User Provider
final currentUserProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

// Main Tasks Stream Provider
final todosStreamProvider = StreamProvider<List<TodoModel>>((ref) {
  final repository = ref.watch(todoRepositoryProvider);
  return repository.getTodosStream();
});

// Subtasks Stream Provider (family provider - takes parentTaskId)
final subtasksStreamProvider = StreamProvider.family<List<SubtaskModel>, String>((ref, parentTaskId) {
  final repository = ref.watch(todoRepositoryProvider);
  return repository.getSubtasksStream(parentTaskId);
});

// Single Todo Provider
final singleTodoProvider = FutureProvider.family<TodoModel?, String>((ref, id) async {
  final repository = ref.watch(todoRepositoryProvider);
  return await repository.getTodoById(id);
});

// Todo Statistics Provider
final todoStatsProvider = Provider<TodoStats>((ref) {
  final todosAsync = ref.watch(todosStreamProvider);
  
  return todosAsync.when(
    data: (todos) {
      final totalSubtasks = todos.fold<int>(0, (sum, todo) => sum + todo.totalSubtasks);
      final completedSubtasks = todos.fold<int>(0, (sum, todo) => sum + todo.completedSubtasks);
      
      return TodoStats(
        totalTasks: todos.length,
        totalSubtasks: totalSubtasks,
        completedSubtasks: completedSubtasks,
      );
    },
    loading: () => TodoStats(totalTasks: 0, totalSubtasks: 0, completedSubtasks: 0),
    error: (_, __) => TodoStats(totalTasks: 0, totalSubtasks: 0, completedSubtasks: 0),
  );
});

class TodoStats {
  final int totalTasks;
  final int totalSubtasks;
  final int completedSubtasks;

  TodoStats({
    required this.totalTasks,
    required this.totalSubtasks,
    required this.completedSubtasks,
  });
}