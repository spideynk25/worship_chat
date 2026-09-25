/// Tracks the UID of the chat the user is currently viewing.
/// When non-null, foreground notifications from that sender are suppressed.
class ActiveChatNotifier {
  ActiveChatNotifier._();
  static final ActiveChatNotifier instance = ActiveChatNotifier._();

  String? _activeChatUid;

  String? get activeChatUid => _activeChatUid;

  void Function(String chatId, String? chatName)? onChatEntered;

  void enter(String uid, {String? chatName}) {
    _activeChatUid = uid;
    onChatEntered?.call(uid, chatName);
  }

  void leave() => _activeChatUid = null;

  bool isChatActive(String senderUid) => _activeChatUid == senderUid;
}
