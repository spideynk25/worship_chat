import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:worship_chat/common/providers/message_reply_provider.dart';
import 'package:worship_chat/features/chat/widgets/display_messages.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:io';

class MessageReplyPreview extends ConsumerWidget {
  const MessageReplyPreview({super.key});

  void cancelReply(WidgetRef ref) {
    ref.read(messageReplyProvider.notifier).state = null;
  }

  Widget _buildPhotoPreview(String? fileMessageData) {
    if (fileMessageData == null || fileMessageData.isEmpty) {
      return Container(
        width: 70,
        height: 70,
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(Icons.image_outlined, color: Colors.grey[600], size: 30),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 70,
        height: 70,
        color: Colors.grey[900],
        child: fileMessageData.startsWith('http')
            ? CachedNetworkImage(
                imageUrl: fileMessageData,
                fit: BoxFit.cover,
                placeholder: (context, url) => Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: Colors.grey[600],
                    ),
                  ),
                ),
                errorWidget: (context, url, error) => Icon(
                  Icons.image_outlined,
                  color: Colors.grey[600],
                  size: 30,
                ),
              )
            : Image.file(
                File(fileMessageData),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Icon(
                  Icons.image_outlined,
                  color: Colors.grey[600],
                  size: 30,
                ),
              ),
      ),
    );
  }

  Widget _buildVideoPreview(String? fileMessageData) {
    return SizedBox(
      width: 70,
      height: 70,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Container(
              width: 70,
              height: 70,
              color: Colors.grey[900],
              child: Icon(
                Icons.videocam_outlined,
                color: Colors.grey[600],
                size: 30,
              ),
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.9),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.play_arrow,
                    color: Colors.grey[900],
                    size: 18,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messageReply = ref.watch(messageReplyProvider);
    final isPhoto = messageReply!.messageType == 'image';
    final isVideo = messageReply.messageType == 'video';
    final isMedia = isPhoto || isVideo;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor.withOpacity(0.1),
            width: 1,
          ),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Accent line
            Container(
              width: 3,
              decoration: BoxDecoration(
                color: Colors.pinkAccent,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),

            const SizedBox(width: 12),

            // Content - Make it tappable for media
            Expanded(
              child: GestureDetector(
                onTap: isMedia
                    ? () {
                        // Open media preview
                        if (messageReply.fileMessageData != null &&
                            messageReply.fileMessageData!.isNotEmpty) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => MediaPreviewWidget(
                                mediaType: messageReply.messageType,
                                mediaUrl: messageReply.fileMessageData!,
                              ),
                            ),
                          );
                        }
                      }
                    : null,
                child: Row(
                  children: [
                    // Media preview (if applicable)
                    if (isPhoto)
                      _buildPhotoPreview(messageReply.fileMessageData),
                    if (isVideo)
                      _buildVideoPreview(messageReply.fileMessageData),

                    if (isMedia) const SizedBox(width: 12),

                    // Text content
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isPhoto || isVideo)
                            Row(
                              children: [
                                Icon(
                                  isPhoto ? Icons.camera_alt : Icons.videocam,
                                  size: 14,
                                  color: Colors.pinkAccent.withOpacity(0.8),
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    isPhoto
                                        ? (messageReply.isMe
                                              ? 'Your photo'
                                              : 'Photo')
                                        : (messageReply.isMe
                                              ? 'Your video'
                                              : 'Video'),
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.pinkAccent.withOpacity(0.9),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            )
                          else
                            Text(
                              messageReply.isMe ? 'You' : 'Replying to',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.pinkAccent.withOpacity(0.9),
                              ),
                            ),

                          const SizedBox(height: 4),

                          if (isPhoto || isVideo)
                            Text(
                              isPhoto ? 'Tap to view' : 'Tap to play',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(0.5),
                              ),
                            )
                          else
                            Text(
                              messageReply.message,
                              style: TextStyle(
                                fontSize: 14,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(0.6),
                                height: 1.4,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(width: 8),

            // Close button
            InkWell(
              onTap: () => cancelReply(ref),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.close,
                  size: 20,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
