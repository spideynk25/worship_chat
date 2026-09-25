import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:swipe_to/swipe_to.dart';
import 'display_messages.dart';

class SenderMessageCard extends StatelessWidget {
  final String message;
  final String date;
  final String messageType;
  final String? fileMessageData;
  final VoidCallback onRightSwipe;
  final String repliedText;
  final String username;
  final String repliedMessageType;

  const SenderMessageCard({
    super.key,
    required this.message,
    required this.date,
    required this.messageType,
    this.fileMessageData,
    required this.onRightSwipe,
    required this.repliedText,
    required this.username,
    required this.repliedMessageType,
  });

  void _copyMessage(BuildContext context) {
    final textToCopy = messageType == 'text' ? message : fileMessageData ?? '';
    if (textToCopy.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: textToCopy));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Message copied'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(bottom: 80, left: 16, right: 16),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isReplying = repliedText.isNotEmpty;
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 600;

    final isMedia = messageType == 'image' ||
        messageType == 'video' ||
        messageType == 'gif';
    final hasCaption = isMedia &&
        message.isNotEmpty &&
        message != fileMessageData;
    final isPureMedia = isMedia && !hasCaption;

    // Compact single-line detection for short messages (like "hi", "ok", "yes")
    final isShortSingleLine = messageType == 'text' &&
        !isReplying &&
        !message.contains('\n') &&
        !message.contains('http://') &&
        !message.contains('https://') &&
        message.length <= 25;

    // Asymmetrical tail pointing towards sender's avatar on the left
    const bubbleRadius = BorderRadius.only(
      topLeft: Radius.circular(18),
      topRight: Radius.circular(18),
      bottomLeft: Radius.circular(4),
      bottomRight: Radius.circular(18),
    );

    return SwipeTo(
      iconSize: 0,
      swipeSensitivity: 8,
      onRightSwipe: (details) => onRightSwipe(),
      child: Align(
        alignment: Alignment.bottomLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: screenWidth * 0.75),
          child: GestureDetector(
            onLongPress: () => _copyMessage(context),
            child: Container(
              margin: EdgeInsets.symmetric(
                horizontal: isSmallScreen ? 3 : 6,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                borderRadius: bubbleRadius,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF262137), // Rich obsidian violet
                    Color(0xFF1B1728), // Deep slate dusk
                  ],
                ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                  width: 0.8,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: bubbleRadius,
                child: isPureMedia
                    ? _buildPureMedia(context, isReplying)
                    : isShortSingleLine
                        ? _buildShortSingleLine(context, isSmallScreen)
                        : _buildDynamicContent(
                            context,
                            isReplying,
                            isMedia,
                            isSmallScreen,
                          ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Compact single-line bubble: text & timestamp side-by-side with dynamic snug fit
  Widget _buildShortSingleLine(BuildContext context, bool isSmallScreen) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 7, 10, 7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            message,
            style: TextStyle(
              fontSize: isSmallScreen ? 14 : 15,
              color: Colors.white,
              height: 1.2,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            date,
            style: TextStyle(
              fontSize: isSmallScreen ? 11 : 12,
              fontWeight: FontWeight.w400,
              color: Colors.white.withValues(alpha: 0.6),
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  /// Edge-to-edge media with a floating frosted pill for timestamp
  Widget _buildPureMedia(BuildContext context, bool isReplying) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isReplying)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: _buildReplyHeader(context),
          ),
        Stack(
          children: [
            DisplayMessages(
              message: message,
              messageType: messageType,
              fileMessageData: fileMessageData,
              isPreviewable: true,
              useCachedMedia: true,
            ),
            // Floating frosted pill for timestamp
            Positioned(
              bottom: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.15),
                    width: 0.5,
                  ),
                ),
                child: Text(
                  date,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Multi-line or captioned content that dynamically sizes to the message width
  Widget _buildDynamicContent(
    BuildContext context,
    bool isReplying,
    bool isMedia,
    bool isSmallScreen,
  ) {
    return Padding(
      padding: isMedia
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isReplying)
              Padding(
                padding: isMedia
                    ? const EdgeInsets.fromLTRB(8, 8, 8, 4)
                    : const EdgeInsets.only(bottom: 6),
                child: _buildReplyHeader(context),
              ),
            if (isMedia)
              DisplayMessages(
                message: message,
                messageType: messageType,
                fileMessageData: fileMessageData,
                isPreviewable: true,
                useCachedMedia: true,
              )
            else
              DisplayMessages(
                message: message,
                messageType: messageType,
                fileMessageData: fileMessageData,
                isPreviewable: true,
                useCachedMedia: true,
              ),
            // Dynamic bottom row without Spacer to hug message bounds
            Padding(
              padding: isMedia
                  ? const EdgeInsets.fromLTRB(10, 4, 10, 6)
                  : const EdgeInsets.only(top: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(width: 14), // Minimum separation
                  Text(
                    date,
                    style: TextStyle(
                      fontSize: isSmallScreen ? 11 : 12,
                      fontWeight: FontWeight.w400,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Sleek glassy reply preview quote
  Widget _buildReplyHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(10),
        border: const Border(
          left: BorderSide(
            color: Color(0xFF8B7FF5), // Iris lavender accent
            width: 3.5,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            username,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: Color(0xFFA594F9),
            ),
          ),
          const SizedBox(height: 2),
          DisplayMessages(
            message: repliedText,
            messageType: repliedMessageType,
            fileMessageData: repliedText,
            isPreviewable: false,
            useCachedMedia: true,
          ),
        ],
      ),
    );
  }
}