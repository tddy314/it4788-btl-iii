import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:it4788_btl/features/chat/data/stomp_client.dart';

class Socket extends Fake implements WebSocket {
  final incoming = StreamController<dynamic>();
  final sent = <String>[];
  bool closed = false;
  @override
  void add(dynamic data) {
    sent.add(data.toString());
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    closed = true;
    if (!incoming.isClosed) await incoming.close();
  }

  @override
  StreamSubscription<dynamic> listen(
    void Function(dynamic)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => incoming.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
}

void main() {
  test('A slow SockJS open never receives a premature raw CONNECT', () async {
    final socket = Socket();
    final client = SqbStompClient(
      url: 'wss://test.invalid/ws',
      tokenProvider: () async => 'test',
      connector: (_) async => socket,
      handshakeTimeout: const Duration(seconds: 3),
    );
    final connecting = client.connect();
    await Future<void>.delayed(const Duration(milliseconds: 750));
    expect(socket.sent, isEmpty);
    socket.incoming.add('o');
    await Future<void>.delayed(Duration.zero);
    socket.incoming.add('a${jsonEncode(['CONNECTED\nversion:1.2\n\n\x00'])}');
    await connecting;
    expect(client.isConnected, isTrue);
    client.dispose();
  });
  test('SockJS handshake, heartbeat, event and real unsubscribe frames', () async {
    final socket = Socket();
    final client = SqbStompClient(
      url: 'wss://test.invalid/ws',
      tokenProvider: () async => 'test',
      connector: (_) async => socket,
    );
    var received = 0;
    client.subscribe('/user/queue/messages', (_) {
      received++;
    });
    final connecting = client.connect();
    await Future<void>.delayed(Duration.zero);
    socket.incoming.add('o');
    await Future<void>.delayed(Duration.zero);
    expect(socket.sent.first, contains('CONNECT'));
    socket.incoming.add('a${jsonEncode(['CONNECTED\nversion:1.2\n\n\x00'])}');
    await connecting;
    expect(client.isConnected, isTrue);
    socket.incoming.add(
      'a${jsonEncode(['\nMESSAGE\ndestination:/user/queue/messages\n\n{"type":"TYPING"}\x00'])}',
    );
    await Future<void>.delayed(Duration.zero);
    expect(received, 1);
    client.unsubscribe('/user/queue/messages');
    expect(socket.sent.last, contains('UNSUBSCRIBE'));
    client.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(socket.closed, isTrue);
  });
  test(
    'Missing CONNECTED times out without an automatic reconnect loop',
    () async {
      final socket = Socket();
      var calls = 0;
      final client = SqbStompClient(
        url: 'wss://test.invalid/raw',
        tokenProvider: () async => 'test',
        connector: (_) async {
          calls++;
          return socket;
        },
        handshakeTimeout: const Duration(milliseconds: 20),
      );
      await client.connect();
      expect(client.state, StompConnectionState.disconnected);
      expect(socket.closed, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(calls, 1);
      client.dispose();
    },
  );
  test(
    'A socket completing after disposal is closed, not subscribed',
    () async {
      final socket = Socket(), late = Completer<WebSocket>();
      final client = SqbStompClient(
        url: 'wss://test.invalid/raw',
        tokenProvider: () async => 'test',
        connector: (_) => late.future,
      );
      final opening = client.connect();
      await Future<void>.delayed(Duration.zero);
      client.dispose();
      late.complete(socket);
      await opening;
      expect(socket.closed, isTrue);
      expect(socket.sent, isEmpty);
    },
  );
}
