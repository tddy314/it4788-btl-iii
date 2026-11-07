import 'package:flutter_test/flutter_test.dart';
import 'package:it4788_btl/core/storage/draft_store.dart';
import 'package:it4788_btl/features/chat/data/stomp_client.dart';
import 'package:it4788_btl/features/chat/models/chat_message.dart';
import 'package:it4788_btl/features/chat/models/conversation_item.dart';
import 'package:it4788_btl/features/chat/utils/chat_emote_converter.dart';

import '../../support/fakes.dart';

void main() {
  group('Chat Emote Converter (Yêu cầu IT4788 Slide 28)', () {
    test('Converts special characters to emoticons accurately', () {
      expect(ChatEmoteConverter.convertEmotes('Vui quá :))'), 'Vui quá 😆');
      expect(ChatEmoteConverter.convertEmotes('Chào bạn :)'), 'Chào bạn 😊');
      expect(ChatEmoteConverter.convertEmotes('Buồn ghê :('), 'Buồn ghê 🙁');
      expect(ChatEmoteConverter.convertEmotes('Thích nè <3'), 'Thích nè ❤️');
      expect(ChatEmoteConverter.convertEmotes('Ngầu chưa B)'), 'Ngầu chưa 😎');
      expect(ChatEmoteConverter.convertEmotes('Được đấy (y)'), 'Được đấy 👍');
      expect(ChatEmoteConverter.convertEmotes('Cánh cụt <(") nè'), 'Cánh cụt 🐧 nè');
      expect(ChatEmoteConverter.convertEmotes('Cá mập (^^^) bơi'), 'Cá mập 🦈 bơi');
      expect(ChatEmoteConverter.convertEmotes('Khóc quá :((('), 'Khóc quá 😭');
      expect(ChatEmoteConverter.convertEmotes('Hôn nè :*'), 'Hôn nè 😘');
    });

    test('Leaves normal text without emotes intact', () {
      const normal = 'Hôm nay chúng mình ôn thi môn IT4788 nhé!';
      expect(ChatEmoteConverter.convertEmotes(normal), normal);
    });
  });

  group('Chat Models & Idempotency', () {
    test('ChatMessage holds clientMsgId and distinguishes sender', () {
      final message = ChatMessage(
        messageId: 'msg_100',
        clientMsgId: 'client_temp_100',
        conversationId: 'conv_1',
        senderId: 'user_A',
        senderName: 'Trường',
        content: 'Chào cậu!',
        createdAt: DateTime.now(),
        status: MessageStatus.sent,
      );

      expect(message.isMine('user_A'), isTrue);
      expect(message.isMine('user_B'), isFalse);
      expect(message.status, MessageStatus.sent);

      final failed = message.copyWith(status: MessageStatus.failed);
      expect(failed.status, MessageStatus.failed);
      expect(failed.clientMsgId, 'client_temp_100'); // ID giữ nguyên khi thử lại
    });

    test('ConversationItem correctly parses unread_count and last_message', () {
      final json = {
        'conversation_id': 'conv_99',
        'type': 'DIRECT',
        'display_name': 'Nguyễn Văn B',
        'display_avatar_url': 'https://example.com/b.jpg',
        'last_message': {
          'id': 'msg_88',
          'content': 'Hẹn gặp ở thư viện',
        },
        'unread_count': '3',
      };

      final conv = ConversationItem.fromJson(json);
      expect(conv.conversationId, 'conv_99');
      expect(conv.displayName, 'Nguyễn Văn B');
      expect(conv.lastMessageContent, 'Hẹn gặp ở thư viện');
      expect(conv.unreadCount, 3);
    });
  });

  group('STOMP Frame Serializer & Parser', () {
    test('Parses incoming STOMP MESSAGE frame', () {
      const rawFrame =
          'MESSAGE\n'
          'destination:/user/queue/messages\n'
          'content-type:application/json\n'
          'subscription:sub-0\n'
          '\n'
          '{"conversation_id":"1","content":"Xin chào"}\x00';

      final frame = StompFrame.parse(rawFrame);
      expect(frame, isNotNull);
      expect(frame!.command, 'MESSAGE');
      expect(frame.headers['destination'], '/user/queue/messages');
      expect(frame.headers['subscription'], 'sub-0');
      expect(frame.body, '{"conversation_id":"1","content":"Xin chào"}');
    });

    test('Serializes STOMP SEND frame with correct wire format', () {
      final frame = StompFrame(
        command: 'SEND',
        headers: {
          'destination': '/app/chat.send',
          'content-type': 'application/json',
        },
        body: '{"text":"test"}',
      );

      final wire = frame.toWireFormat();
      expect(wire.startsWith('SEND\n'), isTrue);
      expect(wire.contains('destination:/app/chat.send\n'), isTrue);
      expect(wire.endsWith('{"text":"test"}\x00'), isTrue);
    });
  });

  group('Chat Draft Store', () {
    test('DraftStore saves, recovers and removes chat message drafts', () async {
      final memory = MemoryStore();
      final draftStore = DraftStore(memory);

      const userId = 'user_student_1';
      const draftName = 'chat_draft_conv_42';

      await draftStore.save(
        userId: userId,
        name: draftName,
        data: {'text': 'Nội dung đang gõ dở…'},
      );

      final recovered = await draftStore.read(userId: userId, name: draftName);
      expect(recovered, isNotNull);
      expect(recovered!['text'], 'Nội dung đang gõ dở…');

      await draftStore.remove(userId: userId, name: draftName);
      final empty = await draftStore.read(userId: userId, name: draftName);
      expect(empty, isNull);
    });
  });
}
