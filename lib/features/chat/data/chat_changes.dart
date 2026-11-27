import 'dart:async';

class ChatMessageRemoval {
  const ChatMessageRemoval(this.userId, this.messageId);
  final String userId, messageId;
}

/// Feature-local updates keep cached previews consistent with confirmed deletes.
abstract final class ChatChanges {
  static final _removals = StreamController<ChatMessageRemoval>.broadcast(
    sync: true,
  );
  static Stream<ChatMessageRemoval> get removals => _removals.stream;
  static void removed(String userId, String messageId) =>
      _removals.add(ChatMessageRemoval(userId, messageId));
}
