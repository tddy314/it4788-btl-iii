import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'key_value_store.dart';

class SessionTokens {
  const SessionTokens({
    required this.userId,
    required this.accessToken,
    required this.refreshToken,
  });
  final String userId;
  final String accessToken;
  final String refreshToken;
  Map<String, Object> toJson() => {
    'user_id': userId,
    'access_token': accessToken,
    'refresh_token': refreshToken,
  };
  static SessionTokens fromJson(Map<String, dynamic> json) {
    final userId = json['user_id'];
    final access = json['access_token'];
    final refresh = json['refresh_token'];
    if (userId is! String ||
        userId.isEmpty ||
        access is! String ||
        access.isEmpty ||
        refresh is! String ||
        refresh.isEmpty) {
      throw const FormatException('Invalid saved session');
    }
    return SessionTokens(
      userId: userId,
      accessToken: access,
      refreshToken: refresh,
    );
  }
}

/// Một record tránh lệch cặp token. Không kiểm tra mạng khi khôi phục phiên.
class SessionStore extends ChangeNotifier {
  SessionStore(this._storage);
  final KeyValueStore _storage;
  static const _key = 'sqb.session.v1';
  SessionTokens? _tokens;
  int _revision = 0;
  bool _disposed = false;
  Future<void>? _writes;
  SessionTokens? get tokens => _tokens;
  bool get hasSession => _tokens != null;
  Future<void> restore() async {
    final raw = await _storage.read(_key);
    if (raw == null) return;
    try {
      _tokens = SessionTokens.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on FormatException {
      await _storage.remove(_key);
    } on TypeError {
      await _storage.remove(_key);
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> save(SessionTokens tokens) async {
    SessionTokens.fromJson(tokens.toJson());
    final revision = ++_revision;
    await _persist(() => _storage.write(_key, jsonEncode(tokens.toJson())));
    if (revision != _revision) return;
    _tokens = tokens;
    if (!_disposed) notifyListeners();
  }

  Future<void> clear() async {
    ++_revision;
    _tokens = null;
    if (!_disposed) notifyListeners();
    await _persist(() => _storage.remove(_key));
  }

  Future<void> _persist(Future<void> Function() operation) {
    final next = _writes?.then((_) => operation()) ?? operation();
    _writes = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  @override
  void dispose() {
    _disposed = true;
    ++_revision;
    super.dispose();
  }
}
