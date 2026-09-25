import 'dart:developer';

import 'package:any_link_preview/any_link_preview.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/features/dashboard/controller/todo_controller.dart';
import 'package:worship_chat/features/dashboard/providers/todo_providers.dart';
import 'package:worship_chat/models/subtasks.dart';

class SubtasksPage extends ConsumerStatefulWidget {
  final String taskId;
  final String taskTitle;

  const SubtasksPage({
    super.key,
    required this.taskId,
    required this.taskTitle,
  });

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
                        'Add Subtask',
                        style: TextStyle(
                          color: textColor,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Add items with optional links or notes',
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
                  labelText: 'Subtask Title',
                  hintText: 'e.g., Check microphones & sound check',
                  labelStyle: const TextStyle(color: greyColor),
                  hintStyle: TextStyle(
                    color: greyColor.withValues(alpha: 0.5),
                    fontSize: 13,
                  ),
                  filled: true,
                  fillColor: backgroundColor,
                  prefixIcon: const Icon(
                    Icons.check_circle_outline_rounded,
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
                  labelText: 'Description / Links (Optional)',
                  hintText: 'Include details or paste URLs (https://...)',
                  labelStyle: const TextStyle(color: greyColor),
                  hintStyle: TextStyle(
                    color: greyColor.withValues(alpha: 0.5),
                    fontSize: 13,
                  ),
                  filled: true,
                  fillColor: backgroundColor,
                  prefixIcon: const Padding(
                    padding: EdgeInsets.only(bottom: 20),
                    child: Icon(Icons.link_rounded, color: accentOrange),
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
                                .createSubtask(
                                  parentTaskId: widget.taskId,
                                  title: title,
                                  description: description,
                                );
                            navigator.pop();
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Subtask added'),
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
                          'Add Subtask',
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

  void _showEditDialog(SubtaskModel subtask) {
    _titleController.text = subtask.title;
    _descriptionController.text = subtask.description;

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
                      color: accentOrange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: accentOrange.withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Icon(
                      Icons.edit_note_rounded,
                      color: accentOrange,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Edit Subtask',
                        style: TextStyle(
                          color: textColor,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Update title, notes, or links',
                        style: TextStyle(color: greyColor, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _titleController,
                style: const TextStyle(color: textColor, fontSize: 15),
                decoration: InputDecoration(
                  labelText: 'Subtask Title',
                  labelStyle: const TextStyle(color: greyColor),
                  filled: true,
                  fillColor: backgroundColor,
                  prefixIcon: const Icon(Icons.edit_rounded, color: tabColor),
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
                  labelText: 'Description / Links',
                  labelStyle: const TextStyle(color: greyColor),
                  filled: true,
                  fillColor: backgroundColor,
                  prefixIcon: const Padding(
                    padding: EdgeInsets.only(bottom: 20),
                    child: Icon(Icons.link_rounded, color: accentOrange),
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
                                .updateSubtask(
                                  id: subtask.id!,
                                  title: title,
                                  description: description,
                                  completed: subtask.completed,
                                  parentTaskId: widget.taskId,
                                );
                            navigator.pop();
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Subtask updated'),
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
                          'Save Changes',
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

  Future<void> _confirmDeleteSubtask(SubtaskModel subtask) async {
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
              'Delete Subtask',
              style: TextStyle(
                color: textColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          'Delete "${subtask.title}"?',
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
        await ref
            .read(todoControllerProvider.notifier)
            .deleteSubtask(subtask.id!, widget.taskId);
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Subtask deleted'),
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

  Future<void> _launchURL(String url) async {
    try {
      String cleanUrl = url.trim();
      if (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://')) {
        cleanUrl = 'https://$cleanUrl';
      }
      log('Attempting to open URL: $cleanUrl');
      final uri = Uri.parse(cleanUrl);

      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (e) {
      log('Launch error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open link: $url'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  List<String> _extractUrls(String text) {
    final urlPattern = RegExp(
      r'(?:(?:https?|ftp):\/\/)?(?:www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b(?:[-a-zA-Z0-9()@:%_\+.~#?&\/=]*)',
      caseSensitive: false,
    );
    return urlPattern.allMatches(text).map((m) => m.group(0)!).toList();
  }

  Widget _buildTextWithLinks(
    String text, {
    required bool isCompleted,
    required bool isDescription,
  }) {
    final urlPattern = RegExp(
      r'(?:(?:https?|ftp):\/\/)?(?:www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b(?:[-a-zA-Z0-9()@:%_\+.~#?&\/=]*)',
      caseSensitive: false,
    );

    final matches = urlPattern.allMatches(text);

    if (matches.isEmpty) {
      return Text(
        text,
        style: TextStyle(
          fontSize: isDescription ? 13 : 15,
          color: isCompleted
              ? greyColor
              : (isDescription ? greyColor : textColor),
          fontWeight: isDescription ? FontWeight.normal : FontWeight.w600,
          decoration: isCompleted ? TextDecoration.lineThrough : null,
          decorationColor: greyColor,
          height: 1.35,
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
              fontSize: isDescription ? 13 : 15,
              color: isCompleted
                  ? greyColor
                  : (isDescription ? greyColor : textColor),
              fontWeight: isDescription ? FontWeight.normal : FontWeight.w600,
              decoration: isCompleted ? TextDecoration.lineThrough : null,
              decorationColor: greyColor,
            ),
          ),
        );
      }

      final url = match.group(0)!;
      spans.add(
        TextSpan(
          text: url,
          style: TextStyle(
            fontSize: isDescription ? 13 : 15,
            color: tabColor,
            fontWeight: FontWeight.w600,
            decoration: isCompleted
                ? TextDecoration.lineThrough
                : TextDecoration.underline,
            decorationColor: tabColor,
          ),
          recognizer: TapGestureRecognizer()..onTap = () => _launchURL(url),
        ),
      );

      currentPosition = match.end;
    }

    if (currentPosition < text.length) {
      spans.add(
        TextSpan(
          text: text.substring(currentPosition),
          style: TextStyle(
            fontSize: isDescription ? 13 : 15,
            color: isCompleted
                ? greyColor
                : (isDescription ? greyColor : textColor),
            fontWeight: isDescription ? FontWeight.normal : FontWeight.w600,
            decoration: isCompleted ? TextDecoration.lineThrough : null,
            decorationColor: greyColor,
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.taskTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: textColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Text(
              'Subtasks & Links',
              style: TextStyle(color: greyColor, fontSize: 11),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: subtasksAsync.when(
          data: (subtasks) {
            final total = subtasks.length;
            final completedCount = subtasks.where((s) => s.completed).length;
            final progress = total > 0 ? completedCount / total : 0.0;
            final percent = (progress * 100).toInt();

            return Column(
              children: [
                // ── Sleek Task Header Card ──────────────────────────────────
                if (total > 0)
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: mobileChatBoxColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: dividerColor),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  progress == 1.0
                                      ? Icons.check_circle_rounded
                                      : Icons.pie_chart_outline_rounded,
                                  size: 16,
                                  color: progress == 1.0
                                      ? Colors.greenAccent
                                      : tabColor,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '$completedCount of $total completed',
                                  style: const TextStyle(
                                    color: textColor,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: progress == 1.0
                                    ? Colors.greenAccent
                                        .withValues(alpha: 0.15)
                                    : tabColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: progress == 1.0
                                      ? Colors.greenAccent
                                          .withValues(alpha: 0.4)
                                      : tabColor.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Text(
                                '$percent%',
                                style: TextStyle(
                                  color: progress == 1.0
                                      ? Colors.greenAccent
                                      : tabColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Container(
                            height: 6,
                            color: dividerColor,
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                return Stack(
                                  children: [
                                    AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 300),
                                      width: constraints.maxWidth * progress,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: progress == 1.0
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
                      ],
                    ),
                  ),

                // ── Subtask List ────────────────────────────────────────────
                Expanded(
                  child: subtasks.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 76,
                                  height: 76,
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
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.checklist_rounded,
                                    size: 38,
                                    color: tabColor,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                const Text(
                                  'No Subtasks Yet',
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Add subtasks or paste links to organize this task.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: greyColor,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                ElevatedButton.icon(
                                  onPressed: _showAddDialog,
                                  icon: const Icon(
                                    Icons.add_rounded,
                                    color: Colors.white,
                                  ),
                                  label: const Text('Add Subtask'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: tabColor,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
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
                        )
                      : ListView.separated(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 85),
                          itemCount: subtasks.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final subtask = subtasks[index];
                            final isDone = subtask.completed;
                            final detectedUrls = [
                              ..._extractUrls(subtask.title),
                              ..._extractUrls(subtask.description),
                            ];

                            return Container(
                              decoration: BoxDecoration(
                                color: mobileChatBoxColor,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isDone
                                      ? Colors.greenAccent
                                          .withValues(alpha: 0.3)
                                      : dividerColor,
                                  width: isDone ? 1.2 : 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.2),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: () {
                                    ref
                                        .read(todoControllerProvider.notifier)
                                        .toggleSubtaskCompletion(
                                          subtask.id!,
                                          subtask.completed,
                                          widget.taskId,
                                        );
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            // Checkbox
                                            GestureDetector(
                                              onTap: () {
                                                ref
                                                    .read(
                                                      todoControllerProvider
                                                          .notifier,
                                                    )
                                                    .toggleSubtaskCompletion(
                                                      subtask.id!,
                                                      subtask.completed,
                                                      widget.taskId,
                                                    );
                                              },
                                              child: AnimatedContainer(
                                                duration: const Duration(
                                                  milliseconds: 200,
                                                ),
                                                width: 24,
                                                height: 24,
                                                margin: const EdgeInsets.only(
                                                  top: 1,
                                                  right: 12,
                                                ),
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  gradient: isDone
                                                      ? const LinearGradient(
                                                          colors: [
                                                            tabColor,
                                                            accentOrange,
                                                          ],
                                                          begin:
                                                              Alignment.topLeft,
                                                          end: Alignment
                                                              .bottomRight,
                                                        )
                                                      : null,
                                                  color: isDone
                                                      ? null
                                                      : backgroundColor,
                                                  border: Border.all(
                                                    color: isDone
                                                        ? Colors.transparent
                                                        : dividerColor,
                                                    width: 1.8,
                                                  ),
                                                ),
                                                child: isDone
                                                    ? const Icon(
                                                        Icons.check_rounded,
                                                        size: 16,
                                                        color: Colors.white,
                                                      )
                                                    : null,
                                              ),
                                            ),

                                            // Text
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  _buildTextWithLinks(
                                                    subtask.title,
                                                    isCompleted: isDone,
                                                    isDescription: false,
                                                  ),
                                                  if (subtask
                                                      .description
                                                      .isNotEmpty) ...[
                                                    const SizedBox(height: 4),
                                                    _buildTextWithLinks(
                                                      subtask.description,
                                                      isCompleted: isDone,
                                                      isDescription: true,
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),

                                            // More Menu
                                            PopupMenuButton<String>(
                                              icon: const Icon(
                                                Icons.more_vert_rounded,
                                                color: greyColor,
                                                size: 20,
                                              ),
                                              color: mobileChatBoxColor,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                side: const BorderSide(
                                                  color: dividerColor,
                                                ),
                                              ),
                                              itemBuilder: (context) => [
                                                const PopupMenuItem(
                                                  value: 'edit',
                                                  child: Row(
                                                    children: [
                                                      Icon(
                                                        Icons.edit_outlined,
                                                        size: 18,
                                                        color: textColor,
                                                      ),
                                                      SizedBox(width: 8),
                                                      Text(
                                                        'Edit',
                                                        style: TextStyle(
                                                          color: textColor,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const PopupMenuItem(
                                                  value: 'delete',
                                                  child: Row(
                                                    children: [
                                                      Icon(
                                                        Icons
                                                            .delete_outline_rounded,
                                                        size: 18,
                                                        color:
                                                            Colors.redAccent,
                                                      ),
                                                      SizedBox(width: 8),
                                                      Text(
                                                        'Delete',
                                                        style: TextStyle(
                                                          color:
                                                              Colors.redAccent,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                              onSelected: (val) {
                                                if (val == 'edit') {
                                                  _showEditDialog(subtask);
                                                } else if (val == 'delete') {
                                                  _confirmDeleteSubtask(
                                                    subtask,
                                                  );
                                                }
                                              },
                                            ),
                                          ],
                                        ),

                                        // ── Link Preview (Restored!) ────────
                                        if (detectedUrls.isNotEmpty) ...[
                                          const SizedBox(height: 10),
                                          ...detectedUrls.map((url) {
                                            return Container(
                                              margin: const EdgeInsets.only(
                                                left: 36,
                                                top: 6,
                                              ),
                                              decoration: BoxDecoration(
                                                color: backgroundColor,
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: dividerColor,
                                                ),
                                              ),
                                              clipBehavior: Clip.antiAlias,
                                              child: AnyLinkPreview(
                                                link: url,
                                                displayDirection:
                                                    UIDirection
                                                        .uiDirectionHorizontal,
                                                showMultimedia: true,
                                                bodyMaxLines: 2,
                                                previewHeight: 100,
                                                bodyTextOverflow:
                                                    TextOverflow.ellipsis,
                                                backgroundColor:
                                                    backgroundColor,
                                                titleStyle: const TextStyle(
                                                  color: tabColor,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                ),
                                                bodyStyle: const TextStyle(
                                                  color: greyColor,
                                                  fontSize: 11,
                                                ),
                                                errorWidget: Container(
                                                  padding:
                                                      const EdgeInsets.all(10),
                                                  child: Row(
                                                    children: [
                                                      const Icon(
                                                        Icons.link_rounded,
                                                        size: 16,
                                                        color: tabColor,
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Expanded(
                                                        child: Text(
                                                          url,
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style:
                                                              const TextStyle(
                                                            color: tabColor,
                                                            fontSize: 12,
                                                            decoration:
                                                                TextDecoration
                                                                    .underline,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            );
                                          }),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
          loading: () => const Center(
            child: CircularProgressIndicator(color: tabColor),
          ),
          error: (error, stack) => Center(
            child: Text(
              'Error: $error',
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
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
                    'Add Subtask',
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
