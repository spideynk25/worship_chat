import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:worship_chat/colors.dart';
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
                color: Colors.black.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
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
    final fileData = messageReply.fileMessageData;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF161524),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
          left: BorderSide(
            color: Colors.white.withValues(alpha: 0.04),
            width: 1,
          ),
          right: BorderSide(
            color: Colors.white.withValues(alpha: 0.04),
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
            // Gradient accent line
            Container(
              width: 3.5,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [tabColor, accentOrange],
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            const SizedBox(width: 12),

            // Content - Make it tappable for media
            Expanded(
              child: GestureDetector(
                onTap: isMedia
                    ? () {
                        // Open media preview
                        if (fileData.isNotEmpty) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => MediaPreviewWidget(
                                mediaType: messageReply.messageType,
                                mediaUrl: fileData,
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
                      _buildPhotoPreview(fileData),
                    if (isVideo)
                      _buildVideoPreview(fileData),

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
                                  color: tabColor.withValues(alpha: 0.8),
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
                                      color: tabColor.withValues(alpha: 0.9),
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
                                color: tabColor.withValues(alpha: 0.9),
                              ),
                            ),

                          const SizedBox(height: 3),

                          if (isPhoto || isVideo)
                            Text(
                              isPhoto ? 'Tap to view' : 'Tap to play',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.5),
                              ),
                            )
                          else
                            Text(
                              messageReply.message,
                              style: TextStyle(
                                fontSize: 13.5,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.75),
                                height: 1.35,
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
            Center(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => cancelReply(ref),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: greyColor,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
