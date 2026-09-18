import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:swipe_to/swipe_to.dart';
import 'package:worship_chat/colors.dart';
import 'display_messages.dart';

class MyMessageCard extends StatelessWidget {
  final String message;
  final String date;
  final String messageType;
  final String? fileMessageData;
  final VoidCallback onLeftSwipe;
  final String repliedText;
  final String username;
  final String repliedMessageType;
  final bool isSeen;

  const MyMessageCard({
    super.key,
    required this.message,
    required this.date,
    required this.messageType,
    this.fileMessageData,
    required this.onLeftSwipe,
    required this.repliedText,
    required this.username,
    required this.repliedMessageType,
    required this.isSeen,
  });

  void _copyMessage(BuildContext context) {
    final textToCopy = messageType == 'text' ? message : fileMessageData ?? '';
    if (textToCopy.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: textToCopy));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Message copied'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isReplying = repliedText.isNotEmpty;
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 600;

    return SwipeTo(
      iconSize: 0,
      swipeSensitivity: 8,
      onLeftSwipe: (details) => onLeftSwipe(),
      child: Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: screenWidth * 0.8),
          child: GestureDetector(
            onLongPress: () => _copyMessage(context),
            child: Card(
              elevation: 3,
              shadowColor: Colors.black.withOpacity(0.1),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              color: Colors.pinkAccent.withAlpha(130),
              margin: EdgeInsets.symmetric(
                horizontal: isSmallScreen ? 5 : 15,
                vertical: 6,
              ),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),

                  color: Colors.transparent,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isReplying)
                      Container(
                        padding: const EdgeInsets.all(8),
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surface.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(8),
                          border: Border(
                            left: BorderSide(
                              color: Theme.of(
                                context,
                              ).colorScheme.primary.withOpacity(0.5),
                              width: 2,
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              username,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: isSmallScreen ? 14 : 16,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(0.9),
                              ),
                            ),
                            const SizedBox(height: 4),
                            DisplayMessages(
                              message: repliedText,
                              messageType: repliedMessageType,
                              fileMessageData: repliedText,
                              isPreviewable: false,
                              useCachedMedia:
                                  true, // Use cached media for replies
                            ),
                          ],
                        ),
                      ),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: DisplayMessages(
                        message: message,
                        messageType: messageType,
                        fileMessageData: fileMessageData,
                        isPreviewable: true,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          date,
                          style: TextStyle(
                            fontSize: isSmallScreen ? 12 : 13,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          isSeen
                              ? Icons.visibility
                              : Icons.mark_email_read, // or Icons.mail
                          size: isSmallScreen ? 18 : 20,
                          color: isSeen
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(0.6),
                          semanticLabel: isSeen
                              ? 'Message seen'
                              : 'Message delivered',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
  // Add these methods to your MyMessageCard class

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MyMessageCard &&
        other.message == message &&
        other.date == date &&
        other.messageType == messageType &&
        other.fileMessageData == fileMessageData &&
        other.repliedText == repliedText &&
        other.username == username &&
        other.repliedMessageType == repliedMessageType &&
        other.isSeen == isSeen;
  }

  @override
  int get hashCode {
    return Object.hash(
      message,
      date,
      messageType,
      fileMessageData,
      repliedText,
      username,
      repliedMessageType,
      isSeen,
    );
  }
}
