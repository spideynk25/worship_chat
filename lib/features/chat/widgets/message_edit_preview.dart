import 'package:flutter/material.dart';
import 'package:worship_chat/colors.dart';

class MessageEditPreview extends StatelessWidget {
  final String text;
  final VoidCallback onCancel;

  const MessageEditPreview({
    super.key,
    required this.text,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF161524),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.06),
            width: 1,
          ),
          left: BorderSide(
            color: Colors.white.withValues(alpha: 0.06),
            width: 1,
          ),
          right: BorderSide(
            color: Colors.white.withValues(alpha: 0.06),
            width: 1,
          ),
        ),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 10),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left gradient accent line
            Container(
              width: 3.5,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [tabColor, Color(0xFF64B5F6)],
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            // Edit icon
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(
                Icons.edit_rounded,
                color: tabColor,
                size: 18,
              ),
            ),
            const SizedBox(width: 8),
            // Text preview
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Edit Message',
                    style: TextStyle(
                      color: tabColor,
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            // Cancel button
            IconButton(
              splashRadius: 18,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              icon: const Icon(
                Icons.close_rounded,
                size: 18,
                color: Colors.white54,
              ),
              onPressed: onCancel,
            ),
          ],
        ),
      ),
    );
  }
}

