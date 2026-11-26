import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/models/group_chat_message_model.dart';
import 'package:worship_chat/models/one_to_one_message_model.dart';

/// Search category filters supported in both 1-to-1 and Group chats.
enum ChatSearchFilter {
  all('All'),
  photos('Photos'),
  videos('Videos'),
  links('Links'),
  files('Files'),
  text('Text'),
  pinned('Pinned');

  final String label;
  const ChatSearchFilter(this.label);
}

/// Normalized message projection used by Search and Pinned Messages across
/// both 1-to-1 and Group chats without duplicating filtering/banner code.
class ChatMessageSummary {
  final String messageId;
  final String senderId;
  final String senderLabel;
  final String text;
  final String messageType;
  final String? fileMessageData;
  final DateTime timeSent;
  final bool isPinned;
  final DateTime? pinnedAt;
  final String? pinnedBy;
  final bool isDeleted;
  final bool isMyMessage;

  const ChatMessageSummary({
    required this.messageId,
    required this.senderId,
    required this.senderLabel,
    required this.text,
    required this.messageType,
    this.fileMessageData,
    required this.timeSent,
    this.isPinned = false,
    this.pinnedAt,
    this.pinnedBy,
    this.isDeleted = false,
    this.isMyMessage = false,
  });

  factory ChatMessageSummary.fromOneToOne(
    OneToOneMessageModel m, {
    required String currentUserId,
    required String peerName,
  }) {
    final isMine = m.senderId == currentUserId;
    return ChatMessageSummary(
      messageId: m.messageId,
      senderId: m.senderId,
      senderLabel: isMine ? 'You' : peerName,
      text: m.text,
      messageType: m.messageType,
      fileMessageData: m.fileMessageData,
      timeSent: m.timeSent,
      isPinned: m.isPinned,
      pinnedAt: m.pinnedAt,
      pinnedBy: m.pinnedBy,
      isDeleted: m.isDeleted,
      isMyMessage: isMine,
    );
  }

  factory ChatMessageSummary.fromGroup(
    GroupChatMessageModel m, {
    required String currentUserId,
    String? senderName,
  }) {
    final isRoleplay =
        m.messageType == 'roleplay' || m.senderId == 'roleplay';
    final isMine = !isRoleplay && m.senderId == currentUserId;
    final resolvedSender = isRoleplay
        ? 'Roleplay'
        : isMine
            ? 'You'
            : (senderName != null && senderName.trim().isNotEmpty
                ? senderName.trim()
                : 'Member');

    return ChatMessageSummary(
      messageId: m.messageId,
      senderId: m.senderId,
      senderLabel: resolvedSender,
      text: m.text,
      messageType: m.messageType,
      fileMessageData: m.fileMessageData,
      timeSent: m.timeSent,
      isPinned: m.isPinned,
      pinnedAt: m.pinnedAt,
      pinnedBy: m.pinnedBy,
      isDeleted: m.isDeleted,
      isMyMessage: isMine,
    );
  }
}

/// Pure helpers for searching, filtering, and summarizing chat messages.
class ChatPowerUpHelper {
  ChatPowerUpHelper._();

  static final RegExp _urlRegex = RegExp(
    r'(?:https?://|www\.)[^\s]+',
    caseSensitive: false,
  );
  static final RegExp _rawUriRegex = RegExp(
    r'^(?:https?://|file://|/data/|/storage/|/var/|/Users/)',
    caseSensitive: false,
  );

  static bool isPhotoMessage(ChatMessageSummary m) {
    return m.messageType == 'image' ||
        m.messageType == 'gif' ||
        m.messageType == 'roleplay';
  }

  static bool isVideoMessage(ChatMessageSummary m) {
    return m.messageType == 'video';
  }

  static bool isFileMessage(ChatMessageSummary m) {
    return m.messageType == 'document' ||
        m.messageType == 'audio' ||
        m.messageType == 'location' ||
        m.messageType == 'live_location';
  }

  static bool isMediaType(String messageType) {
    return messageType == 'image' ||
        messageType == 'video' ||
        messageType == 'gif' ||
        messageType == 'audio' ||
        messageType == 'roleplay' ||
        messageType == 'document';
  }

  static bool isLinkMessage(ChatMessageSummary m) {
    if (m.messageType == 'link') return true;
    // Never classify photos, videos, GIFs, roleplay images, documents, audio,
    // or locations as links simply because fileMessageData holds a CDN URL
    // or fallback media URL in legacy text.
    if (isPhotoMessage(m) || isVideoMessage(m) || isFileMessage(m)) {
      return false;
    }
    if (m.messageType == 'text' ||
        m.messageType == 'wish' ||
        m.messageType == 'story' ||
        m.messageType.isEmpty) {
      return _urlRegex.hasMatch(m.text);
    }
    return false;
  }

  static String _extractAttachmentUrl(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '';
    final trimmed = raw.trim();
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      try {
        final map = jsonDecode(trimmed);
        if (map is Map && map['url'] != null) {
          return map['url'].toString().trim();
        }
      } catch (_) {}
    }
    return trimmed;
  }

  static bool _looksLikeRawAttachmentText(
    String candidate,
    ChatMessageSummary m,
  ) {
    final trimmed = candidate.trim();
    if (trimmed.isEmpty) return false;
    final attachmentUrl = _extractAttachmentUrl(m.fileMessageData);
    if (attachmentUrl.isNotEmpty && trimmed == attachmentUrl) return true;
    if (_rawUriRegex.hasMatch(trimmed) && !trimmed.contains(' ')) {
      return true;
    }
    return false;
  }

  static bool _isDefaultMediaPlaceholder(String cleanText) {
    final lower = cleanText.trim().toLowerCase();
    return lower == '📷 photo' ||
        lower == '🎥 video' ||
        lower == '✨ gif' ||
        lower == '🎤 voice message' ||
        lower == '📄 document' ||
        lower == '👑 roleplay photo' ||
        lower == '📍 location' ||
        lower == '📍 live location';
  }

  static String _extractFileLabel(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '';
    final trimmed = raw.trim();
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      try {
        final map = jsonDecode(trimmed);
        if (map is Map) {
          final pieces = <String>[];
          for (final key in [
            'fileName',
            'name',
            'title',
            'address',
            'caption',
          ]) {
            final v = map[key]?.toString().trim() ?? '';
            if (v.isNotEmpty && !_rawUriRegex.hasMatch(v)) {
              pieces.add(v);
            }
          }
          return pieces.join(' ');
        }
      } catch (_) {}
    }
    // Never return raw CDN URLs or filesystem paths as searchable metadata.
    return '';
  }

  static String _cleanSearchableBody(ChatMessageSummary m) {
    final isAttachment =
        isPhotoMessage(m) || isVideoMessage(m) || isFileMessage(m);
    if (!isAttachment) return m.text;
    if (_looksLikeRawAttachmentText(m.text, m)) return '';
    return m.text;
  }

  static String previewText(ChatMessageSummary m) {
    if (m.isDeleted) return 'This message was deleted';

    final rawCollapsed = m.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final isAttachment =
        isPhotoMessage(m) || isVideoMessage(m) || isFileMessage(m);
    final cleanText = (isAttachment &&
            (_looksLikeRawAttachmentText(rawCollapsed, m) ||
                _isDefaultMediaPlaceholder(rawCollapsed)))
        ? ''
        : rawCollapsed;

    if (cleanText.isNotEmpty) {
      return switch (m.messageType) {
        'image' => '📷 $cleanText',
        'video' => '🎥 $cleanText',
        'audio' => '🎤 $cleanText',
        'gif' => '✨ $cleanText',
        'roleplay' => '👑 $cleanText',
        'document' => '📄 $cleanText',
        'location' => '📍 $cleanText',
        'live_location' => '📍 $cleanText',
        _ => cleanText,
      };
    }

    if (m.messageType == 'document') {
      final rawName = _extractFileLabel(m.fileMessageData);
      if (rawName.isNotEmpty) {
        return '📄 $rawName';
      }
      return '📄 Document';
    }

    if (m.messageType == 'location' || m.messageType == 'live_location') {
      final rawPlace = _extractFileLabel(m.fileMessageData);
      if (rawPlace.isNotEmpty) {
        return '📍 $rawPlace';
      }
    }

    return switch (m.messageType) {
      'image' => '📷 Photo',
      'video' => '🎥 Video',
      'audio' => '🎤 Voice message',
      'gif' => '✨ GIF',
      'location' => '📍 Location',
      'live_location' => '📍 Live Location',
      'roleplay' => '👑 Roleplay Photo',
      _ => 'Message',
    };
  }

  static List<ChatMessageSummary> extractPinned(
    List<ChatMessageSummary> messages,
  ) {
    final pinned = messages
        .where((m) => !m.isDeleted && m.isPinned)
        .toList(growable: false);
    pinned.sort((a, b) {
      final bTime = b.pinnedAt ?? b.timeSent;
      final aTime = a.pinnedAt ?? a.timeSent;
      return bTime.compareTo(aTime);
    });
    return pinned;
  }

  static bool matchesFilter(
    ChatMessageSummary m,
    ChatSearchFilter filter,
  ) {
    switch (filter) {
      case ChatSearchFilter.all:
        return true;
      case ChatSearchFilter.photos:
        return isPhotoMessage(m);
      case ChatSearchFilter.videos:
        return isVideoMessage(m);
      case ChatSearchFilter.links:
        return isLinkMessage(m);
      case ChatSearchFilter.files:
        return isFileMessage(m);
      case ChatSearchFilter.text:
        return m.messageType == 'text' ||
            m.messageType == 'wish' ||
            m.messageType == 'story';
      case ChatSearchFilter.pinned:
        return m.isPinned;
    }
  }

  /// Returns chronological matching messages (`oldest .. newest`) for search.
  static List<ChatMessageSummary> searchMessages(
    List<ChatMessageSummary> messages, {
    required String query,
    ChatSearchFilter filter = ChatSearchFilter.all,
  }) {
    final q = query.trim().toLowerCase();
    final matches = <ChatMessageSummary>[];

    for (final m in messages) {
      if (m.isDeleted) continue;
      if (!matchesFilter(m, filter)) continue;
      if (q.isEmpty) {
        matches.add(m);
        continue;
      }

      final textMatch =
          _cleanSearchableBody(m).toLowerCase().contains(q);
      final metaText = _extractFileLabel(m.fileMessageData).toLowerCase();
      final metaMatch = metaText.contains(q);
      final senderMatch =
          !m.isMyMessage && m.senderLabel.toLowerCase().contains(q);

      if (textMatch || metaMatch || senderMatch) {
        matches.add(m);
      }
    }

    matches.sort((a, b) => a.timeSent.compareTo(b.timeSent));
    return matches;
  }
}

/// Coordinates chat message state, in-chat search, and jump-to-message requests
/// between a chat screen (`OneToOneChatScreen` / `GroupChatScreen`) and its list.
class ChatPowerUpController {
  final ValueNotifier<List<ChatMessageSummary>> messagesNotifier =
      ValueNotifier<List<ChatMessageSummary>>(const []);
  final ValueNotifier<bool> searchOpenNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<String> searchQueryNotifier = ValueNotifier<String>('');

  void Function(String messageId)? _jumpHandler;

  void attachJumpHandler(void Function(String messageId) handler) {
    _jumpHandler = handler;
  }

  void detachJumpHandler(void Function(String messageId) handler) {
    if (_jumpHandler == handler) {
      _jumpHandler = null;
    }
  }

  void updateMessages(List<ChatMessageSummary> messages) {
    messagesNotifier.value = List<ChatMessageSummary>.unmodifiable(messages);
  }

  void openSearch() {
    searchOpenNotifier.value = true;
  }

  void closeSearch() {
    searchOpenNotifier.value = false;
    searchQueryNotifier.value = '';
  }

  void toggleSearch() {
    if (searchOpenNotifier.value) {
      closeSearch();
    } else {
      openSearch();
    }
  }

  void jumpToMessage(String messageId) {
    if (messageId.isEmpty) return;
    _jumpHandler?.call(messageId);
  }

  void dispose() {
    _jumpHandler = null;
    messagesNotifier.dispose();
    searchOpenNotifier.dispose();
    searchQueryNotifier.dispose();
  }
}

/// Top docked in-chat search bar with filter chips, prev/next stepping,
/// match counter, and a bottom sheet listing all matching results.
class ChatSearchToolbar extends StatefulWidget {
  final ChatPowerUpController controller;
  final Color accentColor;

  const ChatSearchToolbar({
    super.key,
    required this.controller,
    this.accentColor = tabColor,
  });

  @override
  State<ChatSearchToolbar> createState() => _ChatSearchToolbarState();
}

class _ChatSearchToolbarState extends State<ChatSearchToolbar> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  ChatSearchFilter _filter = ChatSearchFilter.all;
  int _activeMatchIdx = -1;
  String? _activeMatchId;
  String? _lastSignature;

  @override
  void initState() {
    super.initState();
    widget.controller.searchOpenNotifier.addListener(_onSearchOpenChanged);
  }

  @override
  void dispose() {
    widget.controller.searchOpenNotifier.removeListener(_onSearchOpenChanged);
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onSearchOpenChanged() {
    if (widget.controller.searchOpenNotifier.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    } else {
      _textController.clear();
      if (mounted) {
        setState(() {
          _filter = ChatSearchFilter.all;
          _activeMatchIdx = -1;
          _activeMatchId = null;
          _lastSignature = null;
        });
      }
      _focusNode.unfocus();
    }
  }

  void _jumpToMatch(
    List<ChatMessageSummary> matches,
    int index,
  ) {
    if (matches.isEmpty) return;
    final wrapped = ((index % matches.length) + matches.length) % matches.length;
    final target = matches[wrapped];
    setState(() {
      _activeMatchIdx = wrapped;
      _activeMatchId = target.messageId;
    });
    widget.controller.jumpToMessage(target.messageId);
  }

  void _onQueryOrFilterChanged(
    String newQuery,
    List<ChatMessageSummary> allMessages,
  ) {
    widget.controller.searchQueryNotifier.value = newQuery;
    final matches = ChatPowerUpHelper.searchMessages(
      allMessages,
      query: newQuery,
      filter: _filter,
    );
    final hasActiveSearch =
        newQuery.trim().isNotEmpty || _filter != ChatSearchFilter.all;
    final firstId = matches.isNotEmpty ? matches.first.messageId : '';
    final lastId = matches.isNotEmpty ? matches.last.messageId : '';
    final signature =
        '$newQuery|${_filter.name}|${matches.length}|$firstId|$lastId';
    if (!hasActiveSearch || matches.isEmpty) {
      setState(() {
        _activeMatchIdx = -1;
        _activeMatchId = null;
        _lastSignature = signature;
      });
      return;
    }

    final newestIndex = matches.length - 1;
    final newestId = matches[newestIndex].messageId;
    setState(() {
      _activeMatchIdx = newestIndex;
      _activeMatchId = newestId;
      _lastSignature = signature;
    });
    widget.controller.jumpToMessage(newestId);
  }

  IconData _iconForSearchResult(ChatMessageSummary m) {
    if (m.isPinned) return Icons.push_pin_rounded;
    if (ChatPowerUpHelper.isVideoMessage(m)) return Icons.videocam_rounded;
    if (ChatPowerUpHelper.isPhotoMessage(m)) return Icons.photo_rounded;
    if (ChatPowerUpHelper.isLinkMessage(m)) return Icons.link_rounded;
    if (ChatPowerUpHelper.isFileMessage(m)) {
      return Icons.insert_drive_file_rounded;
    }
    return Icons.chat_bubble_outline_rounded;
  }

  void _showMatchesSheet(List<ChatMessageSummary> matches) {
    final reversed = matches.reversed.toList();
    final q = _textController.text.trim();
    final sheetTitle = _filter != ChatSearchFilter.all && q.isEmpty
        ? '${reversed.length} ${_filter.label}'
        : '${reversed.length} ${reversed.length == 1 ? 'Match' : 'Matches'}${_filter != ChatSearchFilter.all ? ' in ${_filter.label}' : ''}${q.isNotEmpty ? ' for "$q"' : ''}';

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF161426),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.65,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 14, 10),
                  child: Row(
                    children: [
                      Icon(
                        Icons.manage_search_rounded,
                        color: widget.accentColor,
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          sheetTitle,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15.5,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: reversed.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                    itemBuilder: (_, idx) {
                      final m = reversed[idx];
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 17,
                          backgroundColor:
                              widget.accentColor.withValues(alpha: 0.2),
                          child: Icon(
                            _iconForSearchResult(m),
                            size: 16,
                            color: m.isPinned
                                ? const Color(0xFFFFD700)
                                : widget.accentColor,
                          ),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                m.senderLabel,
                                style: TextStyle(
                                  color: widget.accentColor,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              DateFormat('MMM d, h:mm a').format(m.timeSent),
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: _HighlightedSnippet(
                            text: ChatPowerUpHelper.previewText(m),
                            query: q,
                            highlightColor: const Color(0xFFFFD700),
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          final originalIdx = matches.indexWhere(
                            (item) => item.messageId == m.messageId,
                          );
                          if (originalIdx >= 0) {
                            setState(() {
                              _activeMatchIdx = originalIdx;
                              _activeMatchId = m.messageId;
                            });
                          }
                          widget.controller.jumpToMessage(m.messageId);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: widget.controller.searchOpenNotifier,
      builder: (context, isOpen, _) {
        if (!isOpen) return const SizedBox.shrink();

        return ValueListenableBuilder<List<ChatMessageSummary>>(
          valueListenable: widget.controller.messagesNotifier,
          builder: (context, allMessages, _) {
            final query = _textController.text;
            final matches = ChatPowerUpHelper.searchMessages(
              allMessages,
              query: query,
              filter: _filter,
            );

            final hasActiveSearch =
                query.trim().isNotEmpty || _filter != ChatSearchFilter.all;
            final firstId = matches.isNotEmpty ? matches.first.messageId : '';
            final lastId = matches.isNotEmpty ? matches.last.messageId : '';
            final signature =
                '$query|${_filter.name}|${matches.length}|$firstId|$lastId';

            if (!hasActiveSearch || matches.isEmpty) {
              _activeMatchIdx = -1;
              _activeMatchId = null;
              _lastSignature = signature;
            } else if (_lastSignature != signature) {
              final preservedIdx = _activeMatchId == null
                  ? -1
                  : matches.indexWhere((m) => m.messageId == _activeMatchId);
              if (preservedIdx >= 0) {
                _activeMatchIdx = preservedIdx;
              } else if (_activeMatchIdx >= 0 &&
                  _activeMatchIdx < matches.length) {
                // Keep valid clamped slot
              } else {
                _activeMatchIdx = matches.length - 1;
              }
              _activeMatchId = matches[_activeMatchIdx].messageId;
              _lastSignature = signature;
            }

            final showCounter = hasActiveSearch;
            final displayPos =
                (_activeMatchIdx >= 0 && _activeMatchIdx < matches.length)
                    ? _activeMatchIdx + 1
                    : 0;

            return Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
              decoration: BoxDecoration(
                color: const Color(0xEE161426),
                border: Border(
                  bottom: BorderSide(
                    color: Colors.white.withValues(alpha: 0.10),
                    width: 0.8,
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F0E17),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: widget.accentColor.withValues(alpha: 0.35),
                              width: 0.9,
                            ),
                          ),
                          child: Row(
                            children: [
                              const SizedBox(width: 10),
                              Icon(
                                Icons.search_rounded,
                                size: 18,
                                color: widget.accentColor,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: TextField(
                                  controller: _textController,
                                  focusNode: _focusNode,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13.5,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'Search messages...',
                                    hintStyle: TextStyle(
                                      color: Colors.grey[500],
                                      fontSize: 13,
                                    ),
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                  textInputAction: TextInputAction.search,
                                  onSubmitted: (_) {
                                    if (matches.isNotEmpty) {
                                      _jumpToMatch(
                                        matches,
                                        _activeMatchIdx >= 0
                                            ? _activeMatchIdx - 1
                                            : matches.length - 1,
                                      );
                                    }
                                  },
                                  onChanged: (v) =>
                                      _onQueryOrFilterChanged(v, allMessages),
                                ),
                              ),
                              if (showCounter)
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 6),
                                  child: Text(
                                    matches.isEmpty
                                        ? '0/0'
                                        : '$displayPos/${matches.length}',
                                    style: TextStyle(
                                      color: matches.isEmpty
                                          ? Colors.redAccent
                                          : const Color(0xFFFFD700),
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              if (query.isNotEmpty)
                                IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 28,
                                    minHeight: 28,
                                  ),
                                  icon: Icon(
                                    Icons.clear_rounded,
                                    size: 16,
                                    color: Colors.grey[400],
                                  ),
                                  tooltip: 'Clear search',
                                  onPressed: () {
                                    _textController.clear();
                                    _onQueryOrFilterChanged('', allMessages);
                                  },
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      IconButton(
                        icon: Icon(
                          Icons.keyboard_arrow_up_rounded,
                          color: matches.isNotEmpty
                              ? Colors.white
                              : Colors.white24,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 34,
                          minHeight: 36,
                        ),
                        padding: EdgeInsets.zero,
                        tooltip: 'Older match',
                        onPressed: matches.isEmpty
                            ? null
                            : () => _jumpToMatch(
                                  matches,
                                  (_activeMatchIdx >= 0
                                          ? _activeMatchIdx
                                          : matches.length) -
                                      1,
                                ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: matches.isNotEmpty
                              ? Colors.white
                              : Colors.white24,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 34,
                          minHeight: 36,
                        ),
                        padding: EdgeInsets.zero,
                        tooltip: 'Newer match',
                        onPressed: matches.isEmpty
                            ? null
                            : () => _jumpToMatch(
                                  matches,
                                  (_activeMatchIdx >= 0
                                          ? _activeMatchIdx
                                          : -1) +
                                      1,
                                ),
                      ),
                      if (matches.isNotEmpty)
                        IconButton(
                          icon: const Icon(
                            Icons.view_list_rounded,
                            color: Color(0xFFFFD700),
                            size: 20,
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 34,
                            minHeight: 36,
                          ),
                          padding: EdgeInsets.zero,
                          tooltip: 'View matching messages',
                          onPressed: () => _showMatchesSheet(matches),
                        ),
                      IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white70,
                          size: 20,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 34,
                          minHeight: 36,
                        ),
                        padding: EdgeInsets.zero,
                        tooltip: 'Close search',
                        onPressed: widget.controller.closeSearch,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 28,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: ChatSearchFilter.values.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 6),
                      itemBuilder: (_, idx) {
                        final item = ChatSearchFilter.values[idx];
                        final selected = _filter == item;
                        return ChoiceChip(
                          label: Text(item.label),
                          selected: selected,
                          showCheckmark: false,
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          labelPadding: EdgeInsets.zero,
                          selectedColor:
                              widget.accentColor.withValues(alpha: 0.28),
                          backgroundColor: const Color(0xFF0F0E17),
                          side: BorderSide(
                            color: selected
                                ? widget.accentColor
                                : Colors.white.withValues(alpha: 0.12),
                          ),
                          labelStyle: TextStyle(
                            color: selected ? Colors.white : Colors.grey[400],
                            fontSize: 11.5,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w500,
                          ),
                          onSelected: (_) {
                            setState(() => _filter = item);
                            _onQueryOrFilterChanged(
                              _textController.text,
                              allMessages,
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Top docked banner displaying pinned chat messages with tap-to-jump cycling,
/// multi-pin progress indicator, quick unpin, and full pinned list sheet.
class PinnedMessagesBanner extends StatefulWidget {
  final ChatPowerUpController controller;
  final Future<void> Function(String messageId)? onUnpin;
  final Color accentColor;

  const PinnedMessagesBanner({
    super.key,
    required this.controller,
    this.onUnpin,
    this.accentColor = tabColor,
  });

  static Future<void> showPinnedMessagesSheet(
    BuildContext context, {
    required ChatPowerUpController controller,
    Future<void> Function(String messageId)? onUnpin,
    Color accentColor = tabColor,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF161426),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: ValueListenableBuilder<List<ChatMessageSummary>>(
            valueListenable: controller.messagesNotifier,
            builder: (_, allMessages, __) {
              final pinned = ChatPowerUpHelper.extractPinned(allMessages);
              return ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(ctx).height * 0.65,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 14, 14, 10),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.push_pin_rounded,
                            color: Color(0xFFFFD700),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Pinned Messages (${pinned.length})',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (pinned.isNotEmpty && onUnpin != null)
                            TextButton(
                              onPressed: () async {
                                for (final p in pinned) {
                                  await onUnpin(p.messageId);
                                }
                                if (ctx.mounted) Navigator.pop(ctx);
                              },
                              child: const Text(
                                'Unpin All',
                                style: TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Divider(
                      height: 1,
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                    if (pinned.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 28,
                        ),
                        child: Text(
                          'No pinned messages yet.\nLong-press any message and tap Pin to keep important moments at the top.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 13,
                            height: 1.45,
                          ),
                        ),
                      )
                    else
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: pinned.length,
                          separatorBuilder: (_, __) => Divider(
                            height: 1,
                            color: Colors.white.withValues(alpha: 0.06),
                          ),
                          itemBuilder: (_, idx) {
                            final msg = pinned[idx];
                            return ListTile(
                              leading: CircleAvatar(
                                radius: 17,
                                backgroundColor: const Color(0xFFFFD700)
                                    .withValues(alpha: 0.16),
                                child: const Icon(
                                  Icons.push_pin_rounded,
                                  size: 16,
                                  color: Color(0xFFFFD700),
                                ),
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      msg.senderLabel,
                                      style: TextStyle(
                                        color: accentColor,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    DateFormat('MMM d, h:mm a')
                                        .format(msg.timeSent),
                                    style: TextStyle(
                                      color: Colors.grey[500],
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  ChatPowerUpHelper.previewText(msg),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              trailing: onUnpin == null
                                  ? null
                                  : IconButton(
                                      icon: const Icon(
                                        Icons.close_rounded,
                                        size: 18,
                                        color: Colors.white54,
                                      ),
                                      tooltip: 'Unpin',
                                      onPressed: () => onUnpin(msg.messageId),
                                    ),
                              onTap: () {
                                Navigator.pop(ctx);
                                controller.jumpToMessage(msg.messageId);
                              },
                            );
                          },
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  @override
  State<PinnedMessagesBanner> createState() => _PinnedMessagesBannerState();
}

class _PinnedMessagesBannerState extends State<PinnedMessagesBanner> {
  int _activeIndex = 0;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<ChatMessageSummary>>(
      valueListenable: widget.controller.messagesNotifier,
      builder: (context, allMessages, _) {
        final pinned = ChatPowerUpHelper.extractPinned(allMessages);
        if (pinned.isEmpty) return const SizedBox.shrink();

        final safeIndex = _activeIndex % pinned.length;
        final current = pinned[safeIndex];
        final preview = ChatPowerUpHelper.previewText(current);
        final headerText = pinned.length > 1
            ? 'Pinned Message • ${safeIndex + 1} of ${pinned.length}'
            : 'Pinned Message';

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              widget.controller.jumpToMessage(current.messageId);
              if (pinned.length > 1) {
                setState(() => _activeIndex = (safeIndex + 1) % pinned.length);
              }
            },
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 7, 6, 7),
              decoration: BoxDecoration(
                color: const Color(0xE8161426),
                border: Border(
                  bottom: BorderSide(
                    color: Colors.white.withValues(alpha: 0.08),
                    width: 0.8,
                  ),
                ),
              ),
              child: Row(
                children: [
                  // Segmented vertical pin bars (Telegram/WhatsApp style)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(
                      pinned.length.clamp(1, 4),
                      (barIdx) {
                        final isCurrent = pinned.length <= 4
                            ? barIdx == safeIndex
                            : barIdx == (safeIndex % 4);
                        return Container(
                          width: 3,
                          height: pinned.length == 1
                              ? 26
                              : (pinned.length == 2 ? 12 : 7),
                          margin: const EdgeInsets.symmetric(vertical: 1),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(2),
                            color: isCurrent
                                ? const Color(0xFFFFD700)
                                : Colors.white24,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Icon(
                    Icons.push_pin_rounded,
                    size: 16,
                    color: Color(0xFFFFD700),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          headerText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFFFD700),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.92),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (pinned.length > 1)
                    IconButton(
                      icon: const Icon(
                        Icons.view_agenda_outlined,
                        size: 18,
                        color: Colors.white70,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 34,
                        minHeight: 34,
                      ),
                      padding: EdgeInsets.zero,
                      tooltip: 'All pinned messages',
                      onPressed: () =>
                          PinnedMessagesBanner.showPinnedMessagesSheet(
                        context,
                        controller: widget.controller,
                        onUnpin: widget.onUnpin,
                        accentColor: widget.accentColor,
                      ),
                    ),
                  if (widget.onUnpin != null)
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: Colors.white54,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 34,
                        minHeight: 34,
                      ),
                      padding: EdgeInsets.zero,
                      tooltip: 'Unpin message',
                      onPressed: () => widget.onUnpin!(current.messageId),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HighlightedSnippet extends StatelessWidget {
  final String text;
  final String query;
  final Color highlightColor;

  const _HighlightedSnippet({
    required this.text,
    required this.query,
    required this.highlightColor,
  });

  @override
  Widget build(BuildContext context) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      return Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white70, fontSize: 13),
      );
    }

    final lower = text.toLowerCase();
    final idx = lower.indexOf(q);
    if (idx < 0) {
      return Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white70, fontSize: 13),
      );
    }

    final before = text.substring(0, idx);
    final match = text.substring(idx, idx + q.length);
    final after = text.substring(idx + q.length);

    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: const TextStyle(color: Colors.white70, fontSize: 13),
        children: [
          TextSpan(text: before),
          TextSpan(
            text: match,
            style: TextStyle(
              color: highlightColor,
              fontWeight: FontWeight.bold,
              backgroundColor: highlightColor.withValues(alpha: 0.16),
            ),
          ),
          TextSpan(text: after),
        ],
      ),
    );
  }
}

/// Manages visibility and unread incoming count for [ChatScrollToBottomButton].
class ChatScrollToBottomController {
  static const double showThresholdPx = 140.0;
  static const double clearUnreadThresholdPx = 24.0;

  final ValueNotifier<bool> visibleNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<int> unreadCountNotifier = ValueNotifier<int>(0);

  void handleScroll(ScrollPosition position) {
    final pixels = position.pixels;
    final shouldShow = pixels > showThresholdPx;
    if (visibleNotifier.value != shouldShow) {
      visibleNotifier.value = shouldShow;
    }
    if (pixels <= clearUnreadThresholdPx && unreadCountNotifier.value != 0) {
      unreadCountNotifier.value = 0;
    }
  }

  void notifyIncomingMessages([int count = 1]) {
    if (count <= 0) return;
    unreadCountNotifier.value += count;
  }

  void reset() {
    if (visibleNotifier.value) visibleNotifier.value = false;
    if (unreadCountNotifier.value != 0) unreadCountNotifier.value = 0;
  }

  Future<void> scrollToBottom(ScrollController controller) async {
    unreadCountNotifier.value = 0;
    if (!controller.hasClients) return;
    final current = controller.position.pixels;
    if (current.isFinite && current > 2400.0) {
      controller.jumpTo(1200.0);
    }
    await controller.animateTo(
      0.0,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void dispose() {
    visibleNotifier.dispose();
    unreadCountNotifier.dispose();
  }
}

/// WhatsApp-style floating button anchored at the bottom-right corner of the
/// chat message list when scrolled up into older messages.
class ChatScrollToBottomButton extends StatelessWidget {
  final ChatScrollToBottomController controller;
  final ScrollController scrollController;
  final Color accentColor;

  const ChatScrollToBottomButton({
    super.key,
    required this.controller,
    required this.scrollController,
    this.accentColor = tabColor,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 12,
      bottom: 14,
      child: ValueListenableBuilder<bool>(
        valueListenable: controller.visibleNotifier,
        builder: (context, visible, _) {
          return IgnorePointer(
            ignoring: !visible,
            child: AnimatedScale(
              scale: visible ? 1.0 : 0.72,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutBack,
              child: AnimatedOpacity(
                opacity: visible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 160),
                child: ValueListenableBuilder<int>(
                  valueListenable: controller.unreadCountNotifier,
                  builder: (context, unreadCount, _) {
                    return Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.topCenter,
                      children: [
                        Material(
                          color: const Color(0xEB1D1A30),
                          elevation: 5,
                          shadowColor: Colors.black.withValues(alpha: 0.55),
                          shape: CircleBorder(
                            side: BorderSide(
                              color: accentColor.withValues(alpha: 0.45),
                              width: 1.0,
                            ),
                          ),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () =>
                                controller.scrollToBottom(scrollController),
                            child: Semantics(
                              button: true,
                              label: 'Scroll to bottom',
                              child: const Tooltip(
                                message: 'Jump to latest messages',
                                child: SizedBox(
                                  width: 42,
                                  height: 42,
                                  child: Icon(
                                    Icons.keyboard_double_arrow_down_rounded,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (unreadCount > 0)
                          Positioned(
                            top: -9,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: accentColor,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.35),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                              child: Text(
                                unreadCount > 99 ? '99+' : '$unreadCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Auto-expands pagination when older messages exist but rendered grouped rows
/// do not yet fill the viewport (prevents a sticky top loading spinner).
class ChatPaginationHelper {
  ChatPaginationHelper._();

  static void scheduleUnderfilledCheck({
    required ScrollController scrollController,
    required bool hasMore,
    required bool isLoadingMore,
    required VoidCallback onLoadMore,
    double maxExtentThreshold = 40.0,
  }) {
    if (!hasMore || isLoadingMore) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scrollController.hasClients) return;
      final pos = scrollController.position;
      if (!pos.hasViewportDimension || !pos.hasContentDimensions) return;
      if (pos.maxScrollExtent <= maxExtentThreshold) {
        onLoadMore();
      }
    });
  }
}

/// Descriptor locating a target message within grouped chat rows.
class ChatRowLookup {
  final int rowCount;
  final int targetRowIndex;
  final String primaryMessageId;

  const ChatRowLookup({
    required this.rowCount,
    required this.targetRowIndex,
    required this.primaryMessageId,
  });
}

/// Multi-frame closed-loop scroller for reverse chat lists whose rows have
/// highly variable heights (photos, videos, grouped albums, link previews).
class ChatListJumpHelper {
  ChatListJumpHelper._();

  static void convergeToMessage({
    required int generation,
    required int Function() currentGeneration,
    required bool Function() isMounted,
    required ScrollController scrollController,
    required ChatRowLookup? Function() lookupTargetRow,
    required List<String> Function() orderedPrimaryIds,
    required GlobalKey Function(String primaryId) keyForPrimaryId,
    required void Function(String targetMessageId) onHighlight,
    required String targetMessageId,
    int attempt = 0,
    int maxAttempts = 12,
  }) {
    if (!isMounted() || generation != currentGeneration()) return;
    final lookup = lookupTargetRow();
    if (lookup == null || lookup.rowCount <= 0) return;

    final directCtx = keyForPrimaryId(lookup.primaryMessageId).currentContext;
    if (directCtx != null) {
      Scrollable.ensureVisible(
        directCtx,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOutCubic,
        alignment: 0.5,
      ).then((_) {
        if (isMounted() && generation == currentGeneration()) {
          onHighlight(targetMessageId);
        }
      });
      return;
    }

    if (attempt >= maxAttempts || !scrollController.hasClients) {
      if (keyForPrimaryId(lookup.primaryMessageId).currentContext != null &&
          isMounted() &&
          generation == currentGeneration()) {
        onHighlight(targetMessageId);
      }
      return;
    }

    final pos = scrollController.position;
    if (!pos.hasContentDimensions || !pos.hasViewportDimension) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        convergeToMessage(
          generation: generation,
          currentGeneration: currentGeneration,
          isMounted: isMounted,
          scrollController: scrollController,
          lookupTargetRow: lookupTargetRow,
          orderedPrimaryIds: orderedPrimaryIds,
          keyForPrimaryId: keyForPrimaryId,
          onHighlight: onHighlight,
          targetMessageId: targetMessageId,
          attempt: attempt + 1,
          maxAttempts: maxAttempts,
        );
      });
      return;
    }

    final targetReverseIdx = (lookup.rowCount - 1 - lookup.targetRowIndex)
        .clamp(0, lookup.rowCount - 1);
    final primaries = orderedPrimaryIds();
    int? minMountedRev;
    int? maxMountedRev;
    for (int rowIdx = 0; rowIdx < primaries.length; rowIdx++) {
      if (keyForPrimaryId(primaries[rowIdx]).currentContext != null) {
        final revIdx = primaries.length - 1 - rowIdx;
        minMountedRev =
            minMountedRev == null ? revIdx : math.min(minMountedRev, revIdx);
        maxMountedRev =
            maxMountedRev == null ? revIdx : math.max(maxMountedRev, revIdx);
      }
    }

    final maxExtent = pos.maxScrollExtent;
    double nextOffset;
    if (attempt == 0 || minMountedRev == null || maxMountedRev == null) {
      final fraction = lookup.rowCount <= 1
          ? 0.0
          : targetReverseIdx / (lookup.rowCount - 1);
      nextOffset = (fraction * maxExtent).clamp(0.0, maxExtent);
    } else if (targetReverseIdx > maxMountedRev) {
      final rowsAway = targetReverseIdx - maxMountedRev;
      final remainingRows = math.max(1, (lookup.rowCount - 1) - maxMountedRev);
      final proportionalStep =
          (rowsAway / remainingRows) * (maxExtent - pos.pixels);
      final minStep = pos.viewportDimension * 0.75;
      final step = math.max(minStep, proportionalStep);
      nextOffset = (pos.pixels + step).clamp(0.0, maxExtent);
    } else if (targetReverseIdx < minMountedRev) {
      final rowsAway = minMountedRev - targetReverseIdx;
      final remainingRows = math.max(1, minMountedRev);
      final proportionalStep = (rowsAway / remainingRows) * pos.pixels;
      final minStep = pos.viewportDimension * 0.75;
      final step = math.max(minStep, proportionalStep);
      nextOffset = (pos.pixels - step).clamp(0.0, maxExtent);
    } else {
      final span = math.max(1, maxMountedRev - minMountedRev);
      final rel = (targetReverseIdx - minMountedRev) / span;
      nextOffset = (pos.pixels + (rel - 0.5) * pos.viewportDimension * 0.8)
          .clamp(0.0, maxExtent);
    }

    if ((nextOffset - pos.pixels).abs() >= 1.0) {
      scrollController.jumpTo(nextOffset);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      convergeToMessage(
        generation: generation,
        currentGeneration: currentGeneration,
        isMounted: isMounted,
        scrollController: scrollController,
        lookupTargetRow: lookupTargetRow,
        orderedPrimaryIds: orderedPrimaryIds,
        keyForPrimaryId: keyForPrimaryId,
        onHighlight: onHighlight,
        targetMessageId: targetMessageId,
        attempt: attempt + 1,
        maxAttempts: maxAttempts,
      );
    });
  }
}
