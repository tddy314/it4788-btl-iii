import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:it4788_btl/core/errors/app_failure.dart';
import 'package:it4788_btl/core/media/media_upload_service.dart';
import 'package:it4788_btl/core/storage/draft_store.dart';
import 'package:it4788_btl/features/chat/controllers/chat_detail_controller.dart';
import 'package:it4788_btl/features/chat/data/chat_repository.dart';
import 'package:it4788_btl/features/chat/data/stomp_client.dart';
import 'package:it4788_btl/features/chat/models/chat_message.dart';

import '../../support/fakes.dart';

import 'package:it4788_btl/core/storage/json_cache.dart';
import 'package:it4788_btl/core/storage/session_store.dart';
import 'package:it4788_btl/core/network/api_client.dart';
import 'package:it4788_btl/core/config/app_config.dart';

class FullStore extends MemoryStore {
  @override
  Future<void> write(String key, String value) async {
    throw StateError('Disk full');
  }
}

class TestStomp extends SqbStompClient {
  TestStomp()
    : super(url: 'wss://test.invalid', tokenProvider: () async => null);
  final callbacks = <String, StompMessageCallback>{};
  bool connected = true, closed = false;
  @override
  bool get isConnected => connected;
  @override
  Future<void> connect() async {}
  @override
  Stream<StompConnectionState> get stateStream => const Stream.empty();
  @override
  String subscribe(String destination, StompMessageCallback callback) {
    callbacks[destination] = callback;
    return destination;
  }

  @override
  void unsubscribe(String destination) {
    callbacks.remove(destination);
  }

  @override
  void disconnect() {
    closed = true;
    connected = false;
  }

  void emit(Map<String, dynamic> event) =>
      callbacks['/user/queue/messages']?.call(event);
}

class TestChatRepository extends Fake implements ChatRepository {
  @override
  final TestStomp stomp = TestStomp();
  Completer<ChatMessagesResponse>? pending;
  AppFailure? fetchFailure, uploadFailure;
  List<ChatMessage>? cached;
  int sends = 0, uploads = 0, clears = 0;
  @override
  Future<ChatMessagesResponse> fetchMessages(
    String id, {
    String? after,
    int limit = 20,
  }) async {
    if (fetchFailure != null) throw fetchFailure!;
    return pending == null
        ? const ChatMessagesResponse(conversationId: '1', messages: [])
        : pending!.future;
  }

  @override
  Future<List<ChatMessage>?> loadCachedMessages({
    required String userId,
    required String conversationId,
  }) async => cached;
  @override
  Future<void> saveCachedMessages({
    required String userId,
    required String conversationId,
    required List<ChatMessage> messages,
  }) async {
    cached = [...messages];
  }

  @override
  Future<void> clearCachedMessages(String userId, String conversationId) async {
    clears++;
    cached = null;
  }

  @override
  void sendReadStatus({
    required String conversationId,
    required String messageId,
  }) {}
  @override
  void sendTypingStatus({
    required String conversationId,
    required bool isTyping,
  }) {}
  @override
  void sendStompMessage({
    required String conversationId,
    required String content,
    required String clientMsgId,
    List<String> mediaUrls = const [],
  }) {
    sends++;
  }

  @override
  Future<UploadedMedia> uploadChatImage(
    String filePath, {
    ProgressCallback? onProgress,
    CancelToken? cancelToken,
  }) async {
    uploads++;
    throw uploadFailure ?? AppFailure.offline;
  }
}

ChatDetailController controller(
  TestChatRepository r, {
  DraftStore? drafts,
  bool Function()? current,
}) => ChatDetailController(
  repository: r,
  draftStore: drafts ?? DraftStore(MemoryStore()),
  userId: '7',
  currentUserName: 'Tôi',
  conversationId: '1',
  partnerName: 'Bạn',
  isCurrent: current,
  ackTimeout: const Duration(milliseconds: 20),
);
Map<String, dynamic> message(
  int id, {
  String? clientId,
  String content = 'OK',
}) => {
  'type': 'NEW_MESSAGE',
  'conversation_id': 1,
  'message_id': id,
  'sender_id': 7,
  'content': content,
  'created_at': '2026-11-17T12:00:00Z',
  'client_msg_id': ?clientId,
};

void main() {
  test(
    'A long realtime stream bounds RAM while preserving the pending outbox',
    () async {
      final r = TestChatRepository();
      final c = controller(r);
      await c.initialize();
      await c.sendTextMessage('Tin đang chờ');
      final localId = c.messages.single.clientMsgId;
      for (var id = 1; id <= 250; id++) {
        r.stomp.emit(message(id));
      }
      expect(c.messages, hasLength(200));
      expect(c.messages.any((m) => m.clientMsgId == localId), isTrue);
      expect(
        c.messages.where((m) => m.messageId.isNotEmpty).first.messageId,
        '250',
      );
      c.dispose();
    },
  );
  test('Older history persists for offline use and revocation during pagination purges it', () async {
    final r = TestChatRepository()..pending = Completer();
    r.pending!.complete(
      ChatMessagesResponse(
        conversationId: '1',
        messages: [ChatMessage.fromJson(message(11))],
        after: '20',
        hasNext: true,
      ),
    );
    final c = controller(r);
    await c.initialize();
    r.pending = Completer()
      ..complete(
        ChatMessagesResponse(
          conversationId: '1',
          messages: [ChatMessage.fromJson(message(10))],
          after: '10',
          hasNext: true,
        ),
      );
    await c.loadEarlierMessages();
    expect(r.cached, hasLength(2));
    r.fetchFailure = const AppFailure(FailureKind.forbidden, 'Không còn quyền');
    await c.loadEarlierMessages();
    expect(c.messages, isEmpty);
    expect(r.clears, 1);
    c.dispose();
  });
  test('A group conversation reached by a deep link cannot enable direct-chat sending', () async {
    final r = TestChatRepository()..pending = Completer();
    r.pending!.complete(
      const ChatMessagesResponse(
        conversationId: '1',
        messages: [],
        conversationType: 'GROUP',
      ),
    );
    final c = controller(r);
    await c.initialize();
    expect(c.accessDenied, isTrue);
    expect(c.canCompose, isFalse);
    expect(await c.sendTextMessage('Không gửi vào nhóm'), isFalse);
    expect(r.sends, 0);
    c.dispose();
  });
  test('Private cache is encrypted-store only and a repository cannot follow an account switch', () async {
    final session = SessionStore(MemoryStore());
    await session.save(
      const SessionTokens(
        userId: '7',
        accessToken: 'test',
        refreshToken: 'test',
      ),
    );
    final privateStore = DraftStore(MemoryStore()),
        cache = JsonCache(MemoryStore());
    final connection = FakeConnection();
    final api = ApiClient(
      config: AppConfig(),
      session: session,
      connection: connection,
    );
    final r = ChatRepository(
      api: api,
      cache: cache,
      mediaUploadService: MediaUploadService(api),
      privateStore: privateStore,
    );
    await r.saveCachedMessages(
      userId: '7',
      conversationId: '1',
      messages: [ChatMessage.fromJson(message(11))],
    );
    expect(await cache.read(userId: '7', resource: 'messages_1'), isNull);
    expect(
      await privateStore.read(userId: '7', name: 'chat.cache.v2/messages_1'),
      isNotNull,
    );
    await session.save(
      const SessionTokens(
        userId: '8',
        accessToken: 'other',
        refreshToken: 'other',
      ),
    );
    expect(r.isActive, isFalse);
    expect(
      await r.loadCachedMessages(userId: '8', conversationId: '1'),
      isNull,
    );
    r.dispose();
    api.close();
    session.dispose();
    connection.dispose();
  });
  test(
    'Storage failure preserves composer and prevents a non-durable send',
    () async {
      final r = TestChatRepository();
      final c = controller(r, drafts: DraftStore(FullStore()));
      await c.initialize();
      expect(await c.sendTextMessage('Không được mất nội dung'), isFalse);
      expect(r.sends, 0);
      expect(c.draftText, 'Không được mất nội dung');
      c.dispose();
    },
  );
  test('Response after dispose and after account change is ignored', () async {
    final r = TestChatRepository();
    final c = controller(r);
    await c.initialize();
    r.pending = Completer();
    final future = c.fetchFirstPage();
    c.dispose();
    r.pending!.complete(
      const ChatMessagesResponse(conversationId: '1', messages: []),
    );
    await future;
    expect(r.stomp.closed, isTrue);
    var active = true;
    final r2 = TestChatRepository();
    final c2 = controller(r2, current: () => active);
    await c2.initialize();
    r2.pending = Completer();
    final future2 = c2.fetchFirstPage();
    active = false;
    r2.pending!.complete(
      ChatMessagesResponse(
        conversationId: '1',
        messages: [ChatMessage.fromJson(message(1))],
      ),
    );
    await future2;
    expect(c2.messages, isEmpty);
    c2.dispose();
  });
  test(
    'Send stays pending, timeout is uncertain, retry uncertain only reads',
    () async {
      final r = TestChatRepository();
      final c = controller(r);
      await c.initialize();
      expect(await c.sendTextMessage('Chào'), isTrue);
      expect(c.messages.single.status, MessageStatus.sending);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(c.messages.single.status, MessageStatus.unconfirmed);
      await c.retryFailedMessage(c.messages.single);
      expect(r.sends, 1);
      c.dispose();
    },
  );
  test('Only matching server acknowledgement confirms local message', () async {
    final r = TestChatRepository();
    final c = controller(r);
    await c.initialize();
    await c.sendTextMessage('Chào');
    final id = c.messages.single.clientMsgId;
    r.stomp.emit(message(11, clientId: id, content: 'Chào'));
    expect(c.messages, hasLength(1));
    expect(c.messages.single.status, MessageStatus.sent);
    expect(c.messages.single.messageId, '11');
    c.dispose();
  });
  test('Distinct IDs with identical content remain two messages; replay deduplicates', () async {
    final r = TestChatRepository();
    final c = controller(r);
    await c.initialize();
    r.stomp.emit(message(11));
    r.stomp.emit(message(12));
    r.stomp.emit(message(12));
    expect(c.messages, hasLength(2));
    c.dispose();
  });
  test(
    'Read/typing events do not create messages and read is bounded by ID',
    () async {
      final r = TestChatRepository();
      final c = controller(r);
      await c.initialize();
      r.stomp.emit(message(11));
      r.stomp.emit(message(12));
      r.stomp.emit({
        'type': 'READ_RECEIPT',
        'conversation_id': 1,
        'message_id': 11,
        'user_id': 8,
      });
      r.stomp.emit({
        'type': 'TYPING',
        'conversation_id': 1,
        'typing': true,
        'user_id': 8,
      });
      expect(c.messages, hasLength(2));
      expect(c.isPartnerTyping, isTrue);
      expect(c.messages.singleWhere((m) => m.messageId == '11').isRead, isTrue);
      expect(
        c.messages.singleWhere((m) => m.messageId == '12').isRead,
        isFalse,
      );
      c.dispose();
    },
  );
  test('Retry image preserves one bubble and local ID', () async {
    final r = TestChatRepository();
    final c = controller(r);
    await c.initialize();
    await c.sendImageMessage('/image.png');
    final id = c.messages.single.clientMsgId;
    expect(c.messages.single.status, MessageStatus.failed);
    await c.retryFailedMessage(c.messages.single);
    expect(c.messages, hasLength(1));
    expect(c.messages.single.clientMsgId, id);
    expect(c.messages.single.status, MessageStatus.failed);
    expect(r.uploads, 2);
    c.dispose();
  });
  test(
    'Offline retains history; forbidden removes history and encrypted cache',
    () async {
      final r = TestChatRepository()
        ..cached = [ChatMessage.fromJson(message(11))];
      final c = controller(r);
      r.fetchFailure = AppFailure.offline;
      await c.initialize();
      expect(c.messages, hasLength(1));
      r.fetchFailure = const AppFailure(
        FailureKind.forbidden,
        'Không có quyền',
      );
      await c.fetchFirstPage();
      expect(c.messages, isEmpty);
      expect(c.accessDenied, isTrue);
      expect(r.clears, 1);
      c.dispose();
    },
  );
  test('Draft persists immediately, including an unconfirmed outbox', () async {
    final memory = MemoryStore(), drafts = DraftStore(MemoryStore());
    final store = DraftStore(memory);
    final r = TestChatRepository();
    final c = controller(r, drafts: store);
    await c.initialize();
    c.onTextChanged('Nháp cuối');
    c.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(
      (await store.read(userId: '7', name: 'chat_draft_1'))?['text'],
      'Nháp cuối',
    );
    final c2 = controller(TestChatRepository(), drafts: drafts);
    await c2.initialize();
    await c2.sendTextMessage('Chưa xác nhận');
    c2.dispose();
    final saved = await drafts.read(userId: '7', name: 'chat_draft_1');
    expect(saved?['outbox'], hasLength(1));
  });
  test('Cache never turns failed or interrupted send into sent', () {
    final m = ChatMessage.fromJson(message(1))
        .copyWith(status: MessageStatus.failed);
    expect(ChatMessage.fromCache(m.toJson()).status, MessageStatus.failed);
    expect(
      ChatMessage.fromCache(m.copyWith(status: MessageStatus.sending).toJson())
          .status,
      MessageStatus.unconfirmed,
    );
    expect(
      StompFrame.parse('\n\r\nMESSAGE\ndestination:/x\n\n{}\x00')?.command,
      'MESSAGE',
    );
  });
  test('Dispose before token arrives prevents socket creation', () async {
    final token = Completer<String?>();
    var calls = 0;
    final client = SqbStompClient(
      url: 'wss://test.invalid/ws',
      tokenProvider: () => token.future,
      connector: (_) async {
        calls++;
        throw const SocketException('Unexpected');
      },
    );
    final connecting = client.connect();
    client.dispose();
    token.complete('token');
    await connecting;
    expect(calls, 0);
    expect(client.state, StompConnectionState.disconnected);
  });
}
