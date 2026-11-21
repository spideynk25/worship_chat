import 'package:flutter/material.dart';

class DeleteMessageDialog extends StatelessWidget {
  final bool isMyMessage;
  final bool isDeleted;
  final VoidCallback onDeleteForMe;
  final VoidCallback? onDeleteForEveryone;

  const DeleteMessageDialog({
    super.key,
    required this.isMyMessage,
    this.isDeleted = false,
    required this.onDeleteForMe,
    this.onDeleteForEveryone,
  });

  static Future<void> show({
    required BuildContext context,
    required bool isMyMessage,
    bool isDeleted = false,
    required VoidCallback onDeleteForMe,
    VoidCallback? onDeleteForEveryone,
  }) {
    return showDialog(
      context: context,
      builder: (ctx) => DeleteMessageDialog(
        isMyMessage: isMyMessage,
        isDeleted: isDeleted,
        onDeleteForMe: onDeleteForMe,
        onDeleteForEveryone: onDeleteForEveryone,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canDeleteForEveryone =
        isMyMessage && !isDeleted && onDeleteForEveryone != null;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1A2E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.12),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.redAccent,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Delete message?',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              canDeleteForEveryone
                  ? 'You can delete this message for everyone or delete it just for yourself.'
                  : 'Delete this message for yourself? This will remove it from your chat.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13.5,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 20),
            if (canDeleteForEveryone) ...[
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent.withValues(alpha: 0.2),
                  foregroundColor: Colors.redAccent,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: Colors.redAccent.withValues(alpha: 0.4),
                    ),
                  ),
                ),
                icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                label: const Text(
                  'Delete for everyone',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                ),
                onPressed: () {
                  Navigator.of(context).pop();
                  onDeleteForEveryone?.call();
                },
              ),
              const SizedBox(height: 8),
            ],
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(
                  color: Colors.white.withValues(alpha: 0.15),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.delete_outline_rounded,
                  size: 18, color: Colors.white70),
              label: const Text(
                'Delete for me',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                onDeleteForMe();
              },
            ),
            const SizedBox(height: 8),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Colors.white54,
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel', style: TextStyle(fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }
}
