import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

typedef StompMessageCallback = void Function(Map<String, dynamic> jsonPayload);

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
    final buffer = StringBuffer()..write('$command\n');
    headers.forEach((key, value) {
      buffer.write('$key:$value\n');
    });
    buffer
      ..write('\n')
      ..write(body)
      ..write('\x00');
    return buffer.toString();
  }

  static StompFrame? parse(String raw) {
    if (raw.isEmpty) return null;
    final parts = raw.split('\n\n');
    if (parts.length < 2) return null;

    final headerLines = parts[0].split('\n');
    final command = headerLines.first.trim();
    final headers = <String, String>{};

    for (var i = 1; i < headerLines.length; i++) {
      final line = headerLines[i];
      final colonIndex = line.indexOf(':');
      if (colonIndex > 0) {
        final key = line.substring(0, colonIndex).trim();
        final value = line.substring(colonIndex + 1).trim();
        headers[key] = value;
      }
    }

    var body = parts.sublist(1).join('\n\n');
    if (body.endsWith('\x00')) {
      body = body.substring(0, body.length - 1);
    }

    return StompFrame(command: command, headers: headers, body: body);
  }
}

class SqbStompClient {
  SqbStompClient({required this.url, required this.tokenProvider});

  final String url;
  final Future<String?> Function() tokenProvider;

  WebSocket? _socket;
  StompConnectionState _state = StompConnectionState.disconnected;
  final Map<String, StompMessageCallback> _subscriptions = {};
  int _subIdCounter = 0;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  Timer? _connectFallbackTimer;
  bool _isDisposed = false;
  bool _isSockJs = false;
  String? _currentToken;
  String _incomingBuffer = '';

  StompConnectionState get state => _state;
  bool get isConnected => _state == StompConnectionState.connected;

  final _stateController = StreamController<StompConnectionState>.broadcast();
  Stream<StompConnectionState> get stateStream => _stateController.stream;

  Future<void> connect() async {
    if (_isDisposed ||
        _state == StompConnectionState.connecting ||
        _state == StompConnectionState.connected) {
      return;
    }

    _updateState(StompConnectionState.connecting);

    try {
      final token = await tokenProvider();
      if (token == null || token.isEmpty) {
        _updateState(StompConnectionState.disconnected);
        return;
      }
      _currentToken = token;

      var targetUrl = url.trim();
      if (targetUrl.endsWith('/')) {
        targetUrl = targetUrl.substring(0, targetUrl.length - 1);
      }
      if (targetUrl.contains('/ws') && !targetUrl.contains('/websocket')) {
        final serverId = Random().nextInt(1000).toString().padLeft(3, '0');
        final sessionId = DateTime.now().millisecondsSinceEpoch.toRadixString(
          36,
        );
        targetUrl = '$targetUrl/$serverId/$sessionId/websocket';
      }

      final httpClient = HttpClient()
        ..badCertificateCallback = (cert, host, port) => true;

      _socket = await WebSocket.connect(
        targetUrl,
        customClient: httpClient,
      ).timeout(const Duration(seconds: 10));

      _socket!.listen(
        _onData,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: true,
      );

      // Nếu sau 600ms không nhận frame 'o' của SockJS thì gửi CONNECT raw trực tiếp
      _connectFallbackTimer?.cancel();
      _connectFallbackTimer = Timer(const Duration(milliseconds: 600), () {
        if (!_isSockJs && _state == StompConnectionState.connecting) {
          _sendConnectFrame();
        }
      });
    } catch (_) {
      _handleDisconnectAndScheduleReconnect();
    }
  }

  void _sendWire(String wire) {
    if (_socket == null) return;
    if (_isSockJs) {
      _socket!.add(jsonEncode([wire]));
    } else {
      _socket!.add(wire);
    }
  }

  void _sendConnectFrame() {
    final token = _currentToken;
    if (token == null || _socket == null) return;
    final connectFrame = StompFrame(
      command: 'CONNECT',
      headers: {
        'accept-version': '1.1,1.2',
        'heart-beat': '10000,10000',
        'Authorization': 'Bearer $token',
        'passcode': token,
      },
      body: '',
    );
    _sendWire(connectFrame.toWireFormat());
  }

  void _onData(dynamic rawData) {
    final String text;
    if (rawData is String) {
      text = rawData;
    } else if (rawData is List<int>) {
      text = utf8.decode(rawData, allowMalformed: true);
    } else {
      return;
    }

    if (text == 'o') {
      _isSockJs = true;
      _connectFallbackTimer?.cancel();
      _sendConnectFrame();
      return;
    }

    if (text == 'h') {
      return;
    }

    if (text.startsWith('c[')) {
      _handleDisconnectAndScheduleReconnect();
      return;
    }

    if (text.startsWith('a[')) {
      _isSockJs = true;
      _connectFallbackTimer?.cancel();
      try {
        final jsonArray = jsonDecode(text.substring(1));
        if (jsonArray is List) {
          for (final item in jsonArray) {
            if (item is String) {
              _handleRawStompStream(item);
            }
          }
        }
      } catch (_) {}
      return;
    }

    _handleRawStompStream(text);
  }

  void _handleRawStompStream(String stream) {
    _incomingBuffer += stream;
    while (_incomingBuffer.contains('\x00')) {
      final nullIndex = _incomingBuffer.indexOf('\x00');
      final singleFrameRaw = _incomingBuffer.substring(0, nullIndex + 1);
      _incomingBuffer = _incomingBuffer.substring(nullIndex + 1);

      final frame = StompFrame.parse(singleFrameRaw);
      if (frame != null) {
        _handleFrame(frame);
      }
    }
  }

  void _handleFrame(StompFrame frame) {
    switch (frame.command) {
      case 'CONNECTED':
        _updateState(StompConnectionState.connected);
        _reconnectTimer?.cancel();
        _resubscribeAll();
        _startHeartbeat();
        break;

      case 'MESSAGE':
        final destination = frame.headers['destination'];
        if (destination != null) {
          final callback = _subscriptions[destination];
          if (callback != null && frame.body.isNotEmpty) {
            try {
              final json = jsonDecode(frame.body);
              if (json is Map<String, dynamic>) {
                callback(json);
              }
            } catch (_) {}
          }
        }
        break;

      case 'ERROR':
        _handleDisconnectAndScheduleReconnect();
        break;
    }
  }

  void _onError(dynamic error) {
    _handleDisconnectAndScheduleReconnect();
  }

  void _onDone() {
    _handleDisconnectAndScheduleReconnect();
  }

  void _handleDisconnectAndScheduleReconnect() {
    _heartbeatTimer?.cancel();
    _connectFallbackTimer?.cancel();
    _socket = null;
    _isSockJs = false;
    _updateState(StompConnectionState.disconnected);

    if (!_isDisposed) {
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(const Duration(seconds: 5), () {
        if (!_isDisposed && !isConnected) {
          connect();
        }
      });
    }
  }

  void _updateState(StompConnectionState newState) {
    if (_state != newState) {
      _state = newState;
      if (!_stateController.isClosed) {
        _stateController.add(newState);
      }
    }
  }

  String subscribe(String destination, StompMessageCallback callback) {
    _subscriptions[destination] = callback;
    final subId = 'sub-${_subIdCounter++}';

    if (isConnected && _socket != null) {
      final frame = StompFrame(
        command: 'SUBSCRIBE',
        headers: {'id': subId, 'destination': destination, 'ack': 'auto'},
        body: '',
      );
      _sendWire(frame.toWireFormat());
    }

    return destination;
  }

  void unsubscribe(String destination) {
    _subscriptions.remove(destination);
  }

  void _resubscribeAll() {
    if (!isConnected || _socket == null) return;
    var index = 0;
    _subscriptions.forEach((destination, _) {
      final frame = StompFrame(
        command: 'SUBSCRIBE',
        headers: {
          'id': 'sub-${index++}',
          'destination': destination,
          'ack': 'auto',
        },
        body: '',
      );
      _sendWire(frame.toWireFormat());
    });
  }

  void send(String destination, Map<String, dynamic> body) {
    if (!isConnected || _socket == null) return;

    final jsonStr = jsonEncode(body);
    final frame = StompFrame(
      command: 'SEND',
      headers: {
        'destination': destination,
        'content-type': 'application/json',
        'content-length': utf8.encode(jsonStr).length.toString(),
      },
      body: jsonStr,
    );
    _sendWire(frame.toWireFormat());
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (isConnected && _socket != null) {
        _sendWire('\n'); // STOMP Heartbeat ping
      }
    });
  }

  void disconnect() {
    _heartbeatTimer?.cancel();
    _connectFallbackTimer?.cancel();
    _reconnectTimer?.cancel();
    if (_socket != null && isConnected) {
      final frame = StompFrame(
        command: 'DISCONNECT',
        headers: {'receipt': 'bye'},
        body: '',
      );
      _sendWire(frame.toWireFormat());
      _socket!.close();
    }
    _socket = null;
    _isSockJs = false;
    _updateState(StompConnectionState.disconnected);
  }

  void dispose() {
    _isDisposed = true;
    disconnect();
    _subscriptions.clear();
    _stateController.close();
  }
}
