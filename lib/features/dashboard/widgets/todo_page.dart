import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/features/dashboard/controller/todo_controller.dart';
import 'package:worship_chat/features/dashboard/providers/todo_providers.dart';
import 'package:worship_chat/features/dashboard/screens/subtask_page.dart';
import 'package:worship_chat/models/todo.dart';

class TodoPage extends ConsumerStatefulWidget {
  static const String routeName = '/todo-page';
  const TodoPage({super.key});

  @override
  ConsumerState<TodoPage> createState() => _TodoPageState();
}

class _TodoPageState extends ConsumerState<TodoPage> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _showAddDialog() {
    _titleController.clear();
    _descriptionController.clear();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(bottomSheetContext).viewInsets.bottom,
        ),
        child: Container(
          decoration: const BoxDecoration(
            color: mobileChatBoxColor,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(
              top: BorderSide(color: dividerColor, width: 1.5),
              left: BorderSide(color: dividerColor, width: 1.5),
              right: BorderSide(color: dividerColor, width: 1.5),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [tabColor, accentOrange],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.add_task_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Create New Task',
                        style: TextStyle(
                          color: textColor,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Add a shared task to track together',
                        style: TextStyle(color: greyColor, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _titleController,
                autofocus: true,
                style: const TextStyle(color: textColor, fontSize: 15),
                decoration: InputDecoration(
                  labelText: 'Task Title',
                  hintText: 'e.g., Sunday Worship Setlist',
                  labelStyle: const TextStyle(color: greyColor),
                  hintStyle: TextStyle(
                    color: greyColor.withValues(alpha: 0.5),
                    fontSize: 13,
                  ),
                  filled: true,
                  fillColor: backgroundColor,
                  prefixIcon: const Icon(
                    Icons.edit_note_rounded,
                    color: tabColor,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: dividerColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: tabColor, width: 1.6),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _descriptionController,
                maxLines: 2,
                style: const TextStyle(color: textColor, fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Description (Optional)',
                  hintText: 'Add details, objectives or notes...',
                  labelStyle: const TextStyle(color: greyColor),
                  hintStyle: TextStyle(
                    color: greyColor.withValues(alpha: 0.5),
                    fontSize: 13,
                  ),
                  filled: true,
                  fillColor: backgroundColor,
                  prefixIcon: const Padding(
                    padding: EdgeInsets.only(bottom: 20),
                    child: Icon(Icons.notes_rounded, color: accentOrange),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: dividerColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                      color: accentOrange,
                      width: 1.6,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(bottomSheetContext),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: dividerColor),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          color: greyColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [tabColor, accentOrange],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: tabColor.withValues(alpha: 0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: () async {
                          final title = _titleController.text.trim();
                          final description =
                              _descriptionController.text.trim();
                          if (title.isEmpty) return;

                          final navigator = Navigator.of(bottomSheetContext);
                          final messenger = ScaffoldMessenger.of(context);

                          try {
                            await ref
                                .read(todoControllerProvider.notifier)
                                .createTodo(
                                  title: title,
                                  description: description,
                                );
                            navigator.pop();
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Task created'),
                                backgroundColor: mobileChatBoxColor,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          } catch (e) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text('Error: $e'),
                                backgroundColor: Colors.redAccent,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Create Task',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDeleteTodo(TodoModel todo) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: mobileChatBoxColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: dividerColor),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.delete_outline_rounded,
                color: Colors.redAccent,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Delete Task',
              style: TextStyle(
                color: textColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          'Delete "${todo.title}" and its subtasks?',
          style: const TextStyle(color: greyColor, fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel', style: TextStyle(color: greyColor)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Delete',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final messenger = ScaffoldMessenger.of(context);
      try {
        await ref.read(todoControllerProvider.notifier).deleteTodo(todo.id!);
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Task deleted'),
            backgroundColor: mobileChatBoxColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Failed to delete: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final todosAsync = ref.watch(todosStreamProvider);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: appBarColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: textColor,
            size: 19,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Shared Tasks',
          style: TextStyle(
            color: textColor,
            fontSize: 20,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.2,
          ),
        ),
        actions: [
          todosAsync.when(
            data: (todos) {
              if (todos.isEmpty) return const SizedBox.shrink();
              final completedCount = todos
                  .where((t) => t.progress == 1.0 && t.totalSubtasks > 0)
                  .length;

              return Center(
                child: Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: tabColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: tabColor.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      '$completedCount/${todos.length} Done',
                      style: const TextStyle(
                        color: tabColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
      body: todosAsync.when(
        data: (todos) {
          if (todos.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            tabColor.withValues(alpha: 0.15),
                            accentOrange.withValues(alpha: 0.15),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: tabColor.withValues(alpha: 0.3),
                          width: 1.5,
                        ),
                      ),
                      child: const Icon(
                        Icons.assignment_outlined,
                        size: 40,
                        color: tabColor,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'No Tasks Yet',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Create a shared task to organize goals and checklists.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: greyColor,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 22),
                    ElevatedButton.icon(
                      onPressed: _showAddDialog,
                      icon: const Icon(Icons.add_rounded, color: Colors.white),
                      label: const Text('Create Task'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: tabColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 85),
            itemCount: todos.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final todo = todos[index];
              final progress = todo.progress;
              final isCompleted =
                  progress == 1.0 && todo.totalSubtasks > 0;
              final percent = (progress * 100).toInt();

              String formattedDate = '';
              if (todo.createdAt != null) {
                formattedDate =
                    DateFormat('MMM d, h:mm a').format(todo.createdAt!);
              }

              return Container(
                decoration: BoxDecoration(
                  color: mobileChatBoxColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isCompleted
                        ? Colors.greenAccent.withValues(alpha: 0.35)
                        : dividerColor,
                    width: isCompleted ? 1.2 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => SubtasksPage(
                            taskId: todo.id!,
                            taskTitle: todo.title,
                          ),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: isCompleted
                                        ? [Colors.green, Colors.teal]
                                        : [
                                            tabColor.withValues(alpha: 0.8),
                                            accentOrange.withValues(alpha: 0.8),
                                          ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  isCompleted
                                      ? Icons.check_circle_rounded
                                      : Icons.assignment_rounded,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      todo.title,
                                      style: TextStyle(
                                        color: textColor,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        decoration: isCompleted
                                            ? TextDecoration.lineThrough
                                            : null,
                                        decorationColor: greyColor,
                                      ),
                                    ),
                                    if (formattedDate.isNotEmpty) ...[
                                      const SizedBox(height: 3),
                                      Text(
                                        formattedDate,
                                        style: const TextStyle(
                                          color: greyColor,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  color: Colors.redAccent,
                                  size: 20,
                                ),
                                tooltip: 'Delete Task',
                                onPressed: () => _confirmDeleteTodo(todo),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          ),
                          if (todo.description.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Text(
                              todo.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: greyColor,
                                fontSize: 13,
                                height: 1.35,
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          if (todo.totalSubtasks > 0) ...[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: Container(
                                height: 5,
                                color: dividerColor,
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    return Stack(
                                      children: [
                                        Container(
                                          width:
                                              constraints.maxWidth * progress,
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: isCompleted
                                                  ? [Colors.green, Colors.teal]
                                                  : [tabColor, accentOrange],
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${todo.completedSubtasks} of ${todo.totalSubtasks} completed',
                                  style: const TextStyle(
                                    color: greyColor,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isCompleted
                                        ? Colors.greenAccent
                                            .withValues(alpha: 0.15)
                                        : tabColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isCompleted
                                          ? Colors.greenAccent
                                              .withValues(alpha: 0.4)
                                          : tabColor.withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Text(
                                    '$percent%',
                                    style: TextStyle(
                                      color: isCompleted
                                          ? Colors.greenAccent
                                          : tabColor,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ] else ...[
                            Row(
                              children: [
                                Icon(
                                  Icons.add_circle_outline_rounded,
                                  size: 14,
                                  color: tabColor.withValues(alpha: 0.9),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'No subtasks • Tap to add checklist',
                                  style: TextStyle(
                                    color: tabColor.withValues(alpha: 0.9),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const Spacer(),
                                const Icon(
                                  Icons.chevron_right_rounded,
                                  size: 18,
                                  color: greyColor,
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: tabColor),
        ),
        error: (error, stack) => Center(
          child: Text('Error: $error', style: const TextStyle(color: Colors.red)),
        ),
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [tabColor, accentOrange],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: tabColor.withValues(alpha: 0.4),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(30),
            onTap: _showAddDialog,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 13),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_rounded, color: Colors.white, size: 22),
                  SizedBox(width: 8),
                  Text(
                    'New Task',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
