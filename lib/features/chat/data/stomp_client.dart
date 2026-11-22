import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

typedef StompMessageCallback = void Function(Map<String, dynamic> jsonPayload);
typedef SocketConnector = Future<WebSocket> Function(String url);

enum StompConnectionState { disconnected, connecting, connected }

class StompFrame {
  const StompFrame({
    required this.command,
    required this.headers,
    required this.body,
  });
  final String command;
  final Map<String, String> headers;
  final String body;
  String toWireFormat() {
    final out = StringBuffer()..writeln(command);
    headers.forEach((key, value) => out.writeln('$key:$value'));
    return '${out.toString()}\n$body\x00';
  }

  static StompFrame? parse(String raw) {
    raw = raw.replaceFirst(RegExp(r'^[\r\n]+'), '').replaceAll('\r\n', '\n');
    final separator = raw.indexOf('\n\n');
    if (separator < 0) return null;
    final lines = raw.substring(0, separator).split('\n');
    if (lines.first.isEmpty) return null;
    final headers = <String, String>{};
    for (final line in lines.skip(1)) {
      final colon = line.indexOf(':');
      if (colon > 0) {
        headers[line.substring(0, colon)] = line.substring(colon + 1);
      }
    }
    var body = raw.substring(separator + 2);
    if (body.endsWith('\x00')) body = body.substring(0, body.length - 1);
    return StompFrame(command: lines.first, headers: headers, body: body);
  }
}

/// One verified connection. Reconnect is explicit; writes are never replayed.
class SqbStompClient {
  SqbStompClient({
    required this.url,
    required this.tokenProvider,
    SocketConnector? connector,
    this.handshakeTimeout = const Duration(seconds: 12),
  }) : _connector = connector ?? WebSocket.connect;
  final String url;
  final Future<String?> Function() tokenProvider;
  final SocketConnector _connector;
  final Duration handshakeTimeout;
  WebSocket? _socket;
  StreamSubscription<dynamic>? _socketSubscription;
  final _subscriptions = <String, (String, StompMessageCallback)>{};
  final _states = StreamController<StompConnectionState>.broadcast();
  StompConnectionState _state = StompConnectionState.disconnected;
  bool _disposed = false, _sockJs = false;
  int _generation = 0, _nextId = 0;
  String _buffer = '';
  String? _token;
  String? lastError;
  Timer? _heartbeat, _fallback;
  Completer<void>? _handshake;
  Future<void>? _connecting;
  StompConnectionState get state => _state;
  bool get isConnected =>
      _state == StompConnectionState.connected && !_disposed;
  Stream<StompConnectionState> get stateStream => _states.stream;

  Future<void> connect() {
    if (_disposed || isConnected) return Future.value();
    return _connecting ??= _connect().whenComplete(() => _connecting = null);
  }

  Future<void> _connect() async {
    final generation = ++_generation;
    bool current() => !_disposed && generation == _generation;
    lastError = null;
    _setState(StompConnectionState.connecting);
    _handshake = Completer<void>();
    try {
      _token = await tokenProvider();
      if (!current()) return;
      if (_token == null || _token!.isEmpty) {
        lastError = 'Cần đăng nhập để kết nối trò chuyện.';
        disconnect();
        return;
      }
      var target = url.replaceFirst(RegExp(r'/$'), '');
      final uri = Uri.parse(target);
      _sockJs = uri.path.endsWith('/ws') || uri.path.endsWith('/websocket');
      if (uri.scheme != 'wss' &&
          !(uri.scheme == 'ws' &&
              (uri.host == '127.0.0.1' || uri.host == 'localhost'))) {
        throw const FormatException('WSS required');
      }
      if (uri.path.endsWith('/ws')) {
        target +=
            '/${Random.secure().nextInt(1000).toString().padLeft(3, '0')}'
            '/${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}/websocket';
      }
      final opening = _connector(target);
      unawaited(
        opening.then((socket) {
          if (!current()) unawaited(socket.close());
        }, onError: (Object _) {}),
      );
      final socket = await opening.timeout(handshakeTimeout);
      if (!current()) {
        unawaited(socket.close());
        return;
      }
      _socket = socket;
      _socketSubscription = socket.listen(
        (data) {
          if (current()) _onData(data);
        },
        onError: (Object _) {
          if (current()) {
            lastError = 'Mất kết nối trò chuyện. Hãy thử kết nối lại.';
            disconnect();
          }
        },
        onDone: () {
          if (current()) disconnect();
        },
        cancelOnError: true,
      );
      _fallback = Timer(const Duration(milliseconds: 600), () {
        if (current() && !_sockJs) _sendConnect();
      });
      await _handshake!.future.timeout(handshakeTimeout);
    } catch (_) {
      if (current()) {
        lastError =
            'Không thể kết nối trò chuyện. Hãy kiểm tra mạng và thử lại.';
        disconnect();
      }
    }
  }

  void _setState(StompConnectionState state) {
    if (_state == state) return;
    _state = state;
    if (!_states.isClosed) _states.add(state);
  }

  void _wire(String wire) {
    if (_disposed || _socket == null) throw StateError('Chat disconnected');
    _socket!.add(_sockJs ? jsonEncode([wire]) : wire);
  }

  void _sendConnect() {
    if (_socket == null || _token == null) return;
    _wire(
      StompFrame(
        command: 'CONNECT',
        headers: {
          'accept-version': '1.2',
          'heart-beat': '10000,10000',
          'Authorization': 'Bearer $_token',
        },
        body: '',
      ).toWireFormat(),
    );
  }

  void _onData(dynamic data) {
    final text = data is String
        ? data
        : data is List<int>
        ? utf8.decode(data, allowMalformed: true)
        : '';
    if (text == 'o') {
      _sockJs = true;
      _fallback?.cancel();
      _sendConnect();
      return;
    }
    if (text == 'h') return;
    if (text.startsWith('c[')) {
      disconnect();
      return;
    }
    if (text.startsWith('a[')) {
      _sockJs = true;
      try {
        final array = jsonDecode(text.substring(1));
        if (array is List) {
          for (final value in array.whereType<String>()) {
            _consume(value);
          }
        }
      } on FormatException {
        disconnect();
      }
    } else {
      _consume(text);
    }
  }

  void _consume(String text) {
    _buffer += text;
    _buffer = _buffer.replaceFirst(RegExp(r'^[\r\n]+'), '');
    if (_buffer.length > 1024 * 1024) {
      disconnect();
      return;
    }
    while (_buffer.contains('\x00')) {
      final end = _buffer.indexOf('\x00');
      final frame = StompFrame.parse(_buffer.substring(0, end + 1));
      _buffer = _buffer
          .substring(end + 1)
          .replaceFirst(RegExp(r'^[\r\n]+'), '');
      if (frame == null) continue;
      switch (frame.command) {
        case 'CONNECTED':
          _fallback?.cancel();
          _setState(StompConnectionState.connected);
          for (final entry in _subscriptions.entries) {
            _subscribe(entry.key, entry.value.$1);
          }
          if (_handshake?.isCompleted == false) _handshake!.complete();
          _heartbeat?.cancel();
          _heartbeat = Timer.periodic(const Duration(seconds: 10), (_) {
            if (isConnected) {
              try {
                _wire('\n');
              } catch (_) {
                disconnect();
              }
            }
          });
        case 'MESSAGE':
          final callback = _subscriptions[frame.headers['destination']]?.$2;
          if (callback != null) {
            try {
              final body = jsonDecode(frame.body);
              if (body is Map<String, dynamic>) callback(body);
            } on FormatException {
              /* Ignore malformed event. */
            }
          }
        case 'ERROR':
          lastError = 'Máy chủ từ chối thao tác trò chuyện. Hãy tải lại để kiểm tra phiên và quyền.';
          disconnect();
      }
    }
  }

  void _subscribe(String destination, String id) {
    _wire(
      StompFrame(
        command: 'SUBSCRIBE',
        headers: {'id': id, 'destination': destination, 'ack': 'auto'},
        body: '',
      ).toWireFormat(),
    );
  }

  String subscribe(String destination, StompMessageCallback callback) {
    if (_disposed) return destination;
    final id = _subscriptions[destination]?.$1 ?? 'sub-${_nextId++}';
    final existed = _subscriptions.containsKey(destination);
    _subscriptions[destination] = (id, callback);
    if (isConnected && !existed) _subscribe(destination, id);
    return destination;
  }

  void unsubscribe(String destination) {
    final removed = _subscriptions.remove(destination);
    if (isConnected && removed != null) {
      _wire(
        StompFrame(
          command: 'UNSUBSCRIBE',
          headers: {'id': removed.$1},
          body: '',
        ).toWireFormat(),
      );
    }
  }

  void send(String destination, Map<String, dynamic> body) {
    if (!isConnected) throw StateError('Chat disconnected');
    final json = jsonEncode(body);
    _wire(
      StompFrame(
        command: 'SEND',
        headers: {
          'destination': destination,
          'content-type': 'application/json',
          'content-length': utf8.encode(json).length.toString(),
        },
        body: json,
      ).toWireFormat(),
    );
  }

  void disconnect() {
    ++_generation;
    _fallback?.cancel();
    _heartbeat?.cancel();
    final socket = _socket;
    _socket = null;
    unawaited(_socketSubscription?.cancel());
    _socketSubscription = null;
    if (socket != null) unawaited(socket.close());
    if (_handshake?.isCompleted == false) _handshake!.complete();
    _buffer = '';
    _token = null;
    _sockJs = false;
    _setState(StompConnectionState.disconnected);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    disconnect();
    _subscriptions.clear();
    unawaited(_states.close());
  }
}
