import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:it4788_btl/core/config/app_config.dart';
import 'package:it4788_btl/core/errors/app_failure.dart';
import 'package:it4788_btl/core/media/media_upload_service.dart';
import 'package:it4788_btl/core/network/api_client.dart';
import 'package:it4788_btl/core/storage/draft_store.dart';
import 'package:it4788_btl/core/storage/json_cache.dart';
import 'package:it4788_btl/core/storage/session_store.dart';
import 'package:it4788_btl/features/chat/data/chat_repository.dart';
import 'package:it4788_btl/features/chat/controllers/conversations_controller.dart';
import 'package:it4788_btl/features/chat/models/conversation_item.dart';
import 'package:it4788_btl/features/chat/models/chat_message.dart';

import '../../support/fakes.dart';
import '../auth/auth_test.dart' show AuthAdapter, response;
import 'chat_flows_test.dart' show TestChatRepository, controller, message;

class DeleteRepository extends TestChatRepository {
  int deletes = 0;
  final started = Completer<void>();
  Completer<MessageDeleteResult>? pendingDelete;
  AppFailure? deleteFailure;

  @override
  Future<MessageDeleteResult> deleteMessage(
    String id,
    MessageDeleteScope scope,
  ) async {
    deletes++;
    if (!started.isCompleted) started.complete();
    if (deleteFailure != null) throw deleteFailure!;
    return pendingDelete == null
        ? MessageDeleteResult(id, scope)
        : pendingDelete!.future;
  }
}

ChatMessage serverMessage(int id) => ChatMessage.fromJson(message(id));

class PreviewRepository extends DeleteRepository {
  ConversationListResponse? saved;
  @override
  Future<ConversationListResponse?> loadCachedConversations(
    String userId,
  ) async => ConversationListResponse(
    items: [
      const ConversationItem(
        conversationId: '1',
        type: 'DIRECT',
        displayName: 'Bạn',
        lastMessageId: '11',
        lastMessageContent: 'Nội dung cũ',
      ),
    ],
  );
  @override
  Future<ConversationListResponse> fetchConversations({
    String? after,
    String? cursor,
    int limit = 20,
  }) async => throw AppFailure.offline;
  @override
  Future<void> saveCachedConversations(
    String userId,
    ConversationListResponse response,
  ) async {
    saved = response;
  }
}

void main() {
  test('A deletion updates conversation previews offline and stays within its account', () async {
    final preview = PreviewRepository(), other = PreviewRepository();
    final list = ConversationsController(repository: preview, userId: '7');
    final otherList = ConversationsController(repository: other, userId: '8');
    await list.initialize();
    await otherList.initialize();
    final r = DeleteRepository();
    final c = controller(r);
    await c.initialize();
    r.stomp.emit(message(11));
    expect(
      await c.deleteMessage(c.messages.single, MessageDeleteScope.me),
      isTrue,
    );
    await Future<void>.delayed(Duration.zero);
    expect(
      list.items.single.lastMessageContent,
      'Tin nhắn không còn hiển thị.',
    );
    expect(
      preview.saved!.items.single.lastMessageContent,
      'Tin nhắn không còn hiển thị.',
    );
    expect(otherList.items.single.lastMessageContent, 'Nội dung cũ');
    c.dispose();
    list.dispose();
    otherList.dispose();
  });

  test(
    'A GET predating an uncertain DELETE cannot unlock a repeated mutation',
    () async {
      final drafts = DraftStore(MemoryStore());
      final r = DeleteRepository()
        ..deleteFailure = const AppFailure(FailureKind.timeout, 'Timeout');
      final c = controller(r, drafts: drafts);
      await c.initialize();
      r.stomp.emit(message(11));
      final item = c.messages.single;
      r.pending = Completer<ChatMessagesResponse>();
      final old = c.fetchFirstPage();
      await Future<void>.delayed(Duration.zero);
      await c.deleteMessage(item, MessageDeleteScope.me);
      r.pending!.complete(
        ChatMessagesResponse(
          conversationId: '1',
          messages: [serverMessage(11)],
        ),
      );
      await old;
      expect(
        (await drafts.read(
          userId: '7',
          name: 'chat_draft_1',
        ))!['pending_deletes'],
        {'11': 'ME'},
      );
      expect(await c.deleteMessage(item, MessageDeleteScope.me), isFalse);
      expect(r.deletes, 1);
      c.dispose();
    },
  );

  test(
    'Loading an older page cannot reintroduce deleted or revoked content',
    () async {
      final r = DeleteRepository()
        ..pending = (Completer<ChatMessagesResponse>()
          ..complete(
            ChatMessagesResponse(
              conversationId: '1',
              messages: [serverMessage(11)],
              hasNext: true,
              after: '1000',
            ),
          ));
      final c = controller(r);
      await c.initialize();
      final item = c.messages.single;
      r.pending = Completer<ChatMessagesResponse>();
      final old = c.loadEarlierMessages();
      await Future<void>.delayed(Duration.zero);
      await c.deleteMessage(item, MessageDeleteScope.me);
      r.pending!.complete(
        ChatMessagesResponse(
          conversationId: '1',
          messages: [
            serverMessage(11),
            ChatMessage.fromJson({...message(12), 'revoked': true}),
          ],
        ),
      );
      await old;
      expect(c.messages, isEmpty);
      expect(r.cached, isEmpty);
      c.dispose();
    },
  );
  test(
    'Revoked REST content and media never return to the timeline or cache',
    () async {
      final revoked = ChatMessage.fromJson({
        ...message(11),
        'revoked': true,
        'content': 'Private old text',
        'media_urls': ['https://example.invalid/private.png'],
      });
      expect(revoked.content, isEmpty);
      expect(revoked.mediaUrls, isEmpty);
      expect(revoked.toJson()['revoked'], isTrue);
      final r = DeleteRepository()
        ..pending = (Completer<ChatMessagesResponse>()
          ..complete(
            ChatMessagesResponse(conversationId: '1', messages: [revoked]),
          ));
      final c = controller(r);
      await c.initialize();
      expect(c.messages, isEmpty);
      expect(r.cached, isEmpty);
      r.stomp.emit({...message(12), 'content': 123});
      expect(c.messages, isEmpty);
      expect(c.errorMessage, contains('không hợp lệ'));
      c.dispose();
    },
  );
  test('Delete keeps content until confirmation, blocks duplicate taps and updates cache', () async {
    final r = DeleteRepository()
      ..pendingDelete = Completer<MessageDeleteResult>();
    final c = controller(r);
    await c.initialize();
    r.stomp.emit(message(11));
    final item = c.messages.single;
    final work = c.deleteMessage(item, MessageDeleteScope.everyone);
    await r.started.future;
    expect(c.isDeleting, isTrue);
    expect(c.messages.single.messageId, '11');
    expect(await c.deleteMessage(item, MessageDeleteScope.everyone), isFalse);
    expect(r.deletes, 1);
    r.pendingDelete!.complete(
      const MessageDeleteResult('11', MessageDeleteScope.everyone),
    );
    expect(await work, isTrue);
    expect(c.messages, isEmpty);
    expect(r.cached, isEmpty);
    expect(c.isDeleting, isFalse);
    c.dispose();
  });

  test('Only own confirmed messages can be recalled; ME can hide a partner message', () async {
    final r = DeleteRepository();
    final c = controller(r);
    await c.initialize();
    r.stomp.emit({...message(12), 'sender_id': 8});
    final partner = c.messages.single;
    expect(
      await c.deleteMessage(partner, MessageDeleteScope.everyone),
      isFalse,
    );
    expect(r.deletes, 0);
    expect(await c.deleteMessage(partner, MessageDeleteScope.me), isTrue);
    expect(c.messages, isEmpty);
    await c.sendTextMessage('Bản đang gửi');
    expect(
      await c.deleteMessage(c.messages.single, MessageDeleteScope.me),
      isFalse,
    );
    expect(r.deletes, 1);
    c.dispose();
  });

  test(
    'An old GET response cannot resurrect a confirmed deleted message',
    () async {
      final r = DeleteRepository();
      final c = controller(r);
      await c.initialize();
      r.stomp.emit(message(11));
      final item = c.messages.single;
      r.pending = Completer<ChatMessagesResponse>();
      final get = c.fetchFirstPage();
      await Future<void>.delayed(Duration.zero);
      expect(await c.deleteMessage(item, MessageDeleteScope.me), isTrue);
      r.pending!.complete(
        ChatMessagesResponse(
          conversationId: '1',
          messages: [serverMessage(11)],
        ),
      );
      await get;
      expect(c.messages, isEmpty);
      r.stomp.emit(message(11));
      expect(c.messages, isEmpty);
      c.dispose();
    },
  );

  test('Timed-out DELETE is not replayed, including after process restoration offline', () async {
    final drafts = DraftStore(MemoryStore());
    final r = DeleteRepository()
      ..deleteFailure = const AppFailure(FailureKind.timeout, 'Timeout');
    final c = controller(r, drafts: drafts);
    await c.initialize();
    r.stomp.emit(message(11));
    final item = c.messages.single;
    expect(await c.deleteMessage(item, MessageDeleteScope.me), isFalse);
    expect(await c.deleteMessage(item, MessageDeleteScope.me), isFalse);
    expect(r.deletes, 1);
    final saved = await drafts.read(userId: '7', name: 'chat_draft_1');
    expect(saved!['pending_deletes'], {'11': 'ME'});
    c.dispose();
    final next = DeleteRepository()
      ..cached = r.cached
      ..fetchFailure = AppFailure.offline;
    final restored = controller(next, drafts: drafts);
    await restored.initialize();
    expect(await restored.deleteMessage(item, MessageDeleteScope.me), isFalse);
    expect(next.deletes, 0);
    next.fetchFailure = null;
    next.pending = Completer<ChatMessagesResponse>()
      ..complete(
        ChatMessagesResponse(
          conversationId: '1',
          messages: [serverMessage(11)],
        ),
      );
    await restored.fetchFirstPage();
    expect(next.deletes, 0);
    expect(await restored.deleteMessage(item, MessageDeleteScope.me), isTrue);
    expect(next.deletes, 1);
    restored.dispose();
  });

  test('A partial history cannot prove an uncertain deletion; full absent history can', () async {
    final drafts = DraftStore(MemoryStore());
    final r = DeleteRepository()
      ..deleteFailure = const AppFailure(FailureKind.invalidData, 'Bad body');
    final c = controller(r, drafts: drafts);
    await c.initialize();
    r.stomp.emit(message(11));
    await c.deleteMessage(c.messages.single, MessageDeleteScope.everyone);
    r.pending = Completer<ChatMessagesResponse>()
      ..complete(
        const ChatMessagesResponse(
          conversationId: '1',
          messages: [],
          hasNext: true,
          after: '1',
        ),
      );
    await c.fetchFirstPage();
    expect(
      (await drafts.read(
        userId: '7',
        name: 'chat_draft_1',
      ))!['pending_deletes'],
      {'11': 'EVERYONE'},
    );
    r.pending = null;
    await c.fetchFirstPage();
    expect(await drafts.read(userId: '7', name: 'chat_draft_1'), isNull);
    expect(r.deletes, 1);
    c.dispose();
  });

  test('Permission rejection keeps history; late response after account change is ignored', () async {
    var current = true;
    final r = DeleteRepository()
      ..deleteFailure = const AppFailure(
        FailureKind.forbidden,
        'Không có quyền',
        statusCode: 403,
      );
    final c = controller(r, current: () => current);
    await c.initialize();
    r.stomp.emit(message(11));
    final item = c.messages.single;
    expect(await c.deleteMessage(item, MessageDeleteScope.everyone), isFalse);
    expect(c.messages.length, 1);
    r.deleteFailure = null;
    r.pendingDelete = Completer<MessageDeleteResult>();
    final work = c.deleteMessage(item, MessageDeleteScope.me);
    while (r.deletes < 2) {
      await Future<void>.delayed(Duration.zero);
    }
    current = false;
    r.pendingDelete!.complete(
      const MessageDeleteResult('11', MessageDeleteScope.me),
    );
    expect(await work, isFalse);
    expect(c.messages.length, 1);
    c.dispose();
  });

  test(
    'Repository sends exact DELETE JSON and validates response ID/scope',
    () async {
      final adapter = AuthAdapter();
      final session = SessionStore(MemoryStore());
      await session.save(
        const SessionTokens(
          userId: '7',
          accessToken: 'test-access',
          refreshToken: 'test-refresh',
        ),
      );
      final connection = FakeConnection();
      final api = ApiClient(
        config: AppConfig(),
        session: session,
        connection: connection,
        dio: Dio()..httpClientAdapter = adapter,
      );
      final repo = ChatRepository(
        api: api,
        cache: JsonCache(MemoryStore()),
        mediaUploadService: MediaUploadService(api),
        privateStore: DraftStore(MemoryStore()),
      );
      try {
        adapter.respond = (_) async =>
            response(200, {'message_id': 11, 'scope': 'ME', 'note': 'OK'});
        final result = await repo.deleteMessage('11', MessageDeleteScope.me);
        expect(result.messageId, '11');
        expect(adapter.requests.single.method, 'DELETE');
        expect(adapter.requests.single.path, 'messages/11');
        expect(adapter.requests.single.data, {'scope': 'ME'});
        adapter.respond = (_) async =>
            response(200, {'message_id': 12, 'scope': 'EVERYONE'});
        await expectLater(
          repo.deleteMessage('11', MessageDeleteScope.me),
          throwsA(isA<AppFailure>()),
        );
        final count = adapter.requests.length;
        await expectLater(
          repo.deleteMessage('invalid', MessageDeleteScope.me),
          throwsA(isA<AppFailure>()),
        );
        expect(adapter.requests.length, count);
      } finally {
        repo.dispose();
        api.close();
        session.dispose();
        connection.dispose();
      }
    },
  );
}
