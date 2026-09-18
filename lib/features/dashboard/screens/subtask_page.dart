import 'dart:developer';

import 'package:any_link_preview/any_link_preview.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:worship_chat/features/dashboard/controller/todo_controller.dart';
import 'package:worship_chat/features/dashboard/providers/todo_providers.dart';
import 'package:worship_chat/models/subtasks.dart';

class SubtasksPage extends ConsumerStatefulWidget {
  final String taskId;
  final String taskTitle;

  const SubtasksPage({Key? key, required this.taskId, required this.taskTitle})
    : super(key: key);

  @override
  ConsumerState<SubtasksPage> createState() => _SubtasksPageState();
}

class _SubtasksPageState extends ConsumerState<SubtasksPage> {
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

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Subtask'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Subtask (e.g., Having Breakfast)',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description (Optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (_titleController.text.trim().isEmpty) return;

              try {
                await ref
                    .read(todoControllerProvider.notifier)
                    .createSubtask(
                      parentTaskId: widget.taskId,
                      title: _titleController.text.trim(),
                      description: _descriptionController.text.trim(),
                    );
                Navigator.pop(context);
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Subtask added')));
              } catch (e) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Error: $e')));
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(SubtaskModel subtask) {
    _titleController.text = subtask.title;
    _descriptionController.text = subtask.description;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Subtask'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Subtask Title',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (_titleController.text.trim().isEmpty) return;

              try {
                await ref
                    .read(todoControllerProvider.notifier)
                    .updateSubtask(
                      id: subtask.id!,
                      title: _titleController.text.trim(),
                      description: _descriptionController.text.trim(),
                      completed: subtask.completed,
                      parentTaskId: widget.taskId,
                    );
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Subtask updated')),
                );
              } catch (e) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Error: $e')));
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _launchURL(String url) async {
    try {
      String cleanUrl = url.trim();

      if (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://')) {
        cleanUrl = 'https://$cleanUrl';
      }

      log('Attempting to open URL: $cleanUrl');

      final uri = Uri.parse(cleanUrl);

      bool canLaunch = await canLaunchUrl(uri);
      log('Can launch URL: $canLaunch');

      if (!canLaunch) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Cannot open this link: $cleanUrl'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      bool launched = false;

      try {
        launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
        log('External app launch: $launched');
      } catch (e) {
        log('External app launch failed: $e');
      }

      if (!launched) {
        try {
          launched = await launchUrl(uri, mode: LaunchMode.platformDefault);
        } catch (e) {
          log('Platform default launch failed: $e');
        }
      }

      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open link: $cleanUrl'),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () => _launchURL(url),
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open link: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Widget _buildTextWithLinks(
    String text,
    BuildContext context,
    bool isSmallScreen,
    bool isSubtaskCompleted,
    bool isDescription,
  ) {
    final urlPattern = RegExp(
      r'(?:(?:https?|ftp):\/\/)?(?:www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b(?:[-a-zA-Z0-9()@:%_\+.~#?&\/=]*)',
      caseSensitive: false,
    );

    final matches = urlPattern.allMatches(text);

    if (matches.isEmpty) {
      return Text(
        text,
        style: TextStyle(
          fontSize: isSmallScreen ? 14 : 16,
          color: isDescription ? Colors.grey[400] : Colors.orange,
        ),
      );
    }

    final spans = <TextSpan>[];
    int currentPosition = 0;

    for (final match in matches) {
      if (match.start > currentPosition) {
        spans.add(
          TextSpan(
            text: text.substring(currentPosition, match.start),
            style: TextStyle(
              fontSize: isSmallScreen ? 14 : 16,
              color: isDescription ? Colors.grey[400] : Colors.orange,
            ),
          ),
        );
      }

      final url = match.group(0)!;
      spans.add(
        TextSpan(
          text: url,
          style: TextStyle(
            fontSize: isSmallScreen ? 14 : 16,
            color: Colors.blue,
            decoration: isSubtaskCompleted
                ? TextDecoration.lineThrough
                : TextDecoration.underline,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () {
              log('Link tapped: $url');
              _launchURL(url);
            },
          children: [
            WidgetSpan(
              child: AnyLinkPreview(
                link: url,
                displayDirection: UIDirection.uiDirectionHorizontal,
                showMultimedia: true,
                bodyMaxLines: 2,
                previewHeight: 100,
                bodyTextOverflow: TextOverflow.ellipsis,
                titleStyle: TextStyle(
                  color: Colors.pink,
                  fontWeight: FontWeight.bold,
                  fontSize: isSmallScreen ? 10 : 12,
                ),
              ),
            ),
          ],
        ),
      );

      currentPosition = match.end;
    }

    if (currentPosition < text.length) {
      spans.add(
        TextSpan(
          text: text.substring(currentPosition),
          style: TextStyle(
            fontSize: isSmallScreen ? 14 : 16,
            color: isDescription ? Colors.grey[400] : Colors.orange,
            decoration: isSubtaskCompleted
                ? TextDecoration.lineThrough
                : TextDecoration.none,
          ),
        ),
      );
    }

    return RichText(text: TextSpan(children: spans));
  }

  @override
  Widget build(BuildContext context) {
    final subtasksAsync = ref.watch(subtasksStreamProvider(widget.taskId));

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.taskTitle),
            Text(
              'Subtasks',
              style: TextStyle(fontSize: 12, color: Colors.grey[300]),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: subtasksAsync.when(
          data: (subtasks) {
            if (subtasks.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.checklist, size: 80, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    Text(
                      'No subtasks yet',
                      style: TextStyle(fontSize: 20, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Add subtasks to track your progress',
                      style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                    ),
                  ],
                ),
              );
            }

            return ListView.builder(
              itemCount: subtasks.length,
              padding: const EdgeInsets.all(8),
              itemBuilder: (context, index) {
                final subtask = subtasks[index];
                return Card(
                  elevation: 4,
                  shadowColor: Colors.white.withAlpha(50),
                  margin: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: ListTile(
                    leading: Checkbox(
                      value: subtask.completed,
                      onChanged: (value) {
                        ref
                            .read(todoControllerProvider.notifier)
                            .toggleSubtaskCompletion(
                              subtask.id!,
                              subtask.completed,
                              widget.taskId,
                            );
                      },
                    ),
                    title: _buildTextWithLinks(
                      subtask.title,
                      context,
                      false,
                      subtask.completed,
                      false,
                    ),
                    subtitle: subtask.description.isNotEmpty
                        ? _buildTextWithLinks(
                            subtask.description,
                            context,
                            true,
                            subtask.completed,
                            true,
                          )
                        : null,
                    trailing: PopupMenuButton(
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit, size: 20),
                              SizedBox(width: 8),
                              Text('Edit'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete, size: 20, color: Colors.red),
                              SizedBox(width: 8),
                              Text(
                                'Delete',
                                style: TextStyle(color: Colors.red),
                              ),
                            ],
                          ),
                        ),
                      ],
                      onSelected: (value) async {
                        if (value == 'edit') {
                          _showEditDialog(subtask);
                        } else if (value == 'delete') {
                          await ref
                              .read(todoControllerProvider.notifier)
                              .deleteSubtask(subtask.id!, widget.taskId);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Subtask deleted')),
                          );
                        }
                      },
                    ),
                  ),
                );
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 60, color: Colors.red),
                const SizedBox(height: 16),
                Text('Error: $error'),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDialog,
        icon: const Icon(Icons.add),
        label: const Text('Add Subtask'),
      ),
    );
  }
}
