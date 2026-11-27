import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:it4788_btl/core/errors/app_failure.dart';
import 'package:it4788_btl/features/notifications/controllers/notification_controller.dart';
import 'package:it4788_btl/features/notifications/data/notification_repository.dart';
import 'package:it4788_btl/features/notifications/models/notification_item.dart';
import 'package:it4788_btl/features/notifications/push/notification_presenter.dart';

class Repository extends Fake implements NotificationRepository {
  Completer<NotificationListResponse>? pending;
  AppFailure? failure, writeFailure;
  int posts = 0, clears = 0;
  NotificationListResponse? saved;
  NotificationReadResult? readResult;
  Completer<NotificationReadResult>? pendingRead;
  final item = NotificationItem(
    notificationId: '1',
    type: 'SYSTEM',
    title: 'Thông báo',
    body: '',
    createdAt: DateTime(2026),
  );
  @override
  Future<NotificationListResponse> fetchNotifications({
    String? after,
    int limit = 20,
  }) async {
    if (failure != null) throw failure!;
    return pending == null
        ? NotificationListResponse(
            items: [item],
            unreadCount: 1,
            after: after ?? '2',
            hasNext: true,
          )
        : pending!.future;
  }

  @override
  Future<NotificationListResponse?> loadCached(String id) async => saved;
  @override
  Future<void> saveToCache(String id, NotificationListResponse value) async {
    saved = value;
  }

  @override
  Future<void> clearCache(String id) async {
    clears++;
    saved = null;
  }

  @override
  Future<NotificationReadResult> markAsRead(String id) async {
    posts++;
    if (writeFailure != null) throw writeFailure!;
    return pendingRead != null
        ? pendingRead!.future
        : readResult ??
              NotificationReadResult(
                notificationId: id,
                read: true,
                readAt: DateTime.utc(2026, 11, 17),
                unreadCount: 0,
              );
  }

  @override
  Future<void> markAllAsRead() async {
    posts++;
    if (writeFailure != null) throw writeFailure!;
  }
}

void main() {
  test(
    'Tapping during refresh sends one read and an older GET cannot undo it',
    () async {
      final r = Repository();
      final c = NotificationController(repository: r, userId: '7');
      await c.initialize();
      r.pending = Completer();
      final refresh = c.refresh();
      await c.markAsRead('1');
      expect(r.posts, 1);
      expect(c.items.single.isRead, isTrue);
      r.pending!.complete(
        NotificationListResponse(items: [r.item], unreadCount: 1),
      );
      await refresh;
      expect(c.items.single.isRead, isTrue);
      expect(c.unreadCount, 0);
      c.dispose();
    },
  );
  test(
    'Mark-read waits for confirmation and uses server count and timestamp',
    () async {
      final r = Repository()..pendingRead = Completer();
      final c = NotificationController(repository: r, userId: '7');
      await c.initialize();
      final pending = c.markAsRead('1');
      expect(c.items.single.isRead, isFalse);
      expect(c.unreadCount, 1);
      await c.markAsRead('1');
      expect(r.posts, 1);
      final at = DateTime.utc(2026, 11, 17, 8, 30);
      r.pendingRead!.complete(
        NotificationReadResult(
          notificationId: '1',
          read: true,
          readAt: at,
          unreadCount: 8,
        ),
      );
      await pending;
      expect(c.unreadCount, 8);
      expect(c.items.single.readAt, at);
      expect(r.saved!.unreadCount, 8);
      c.dispose();
    },
  );
  test(
    'A mismatched notification receipt never marks the requested item',
    () async {
      final r = Repository()
        ..readResult = NotificationReadResult(
          notificationId: '9',
          read: true,
          readAt: DateTime.utc(2026),
          unreadCount: 0,
        );
      final c = NotificationController(repository: r, userId: '7');
      await c.initialize();
      await c.markAsRead('1');
      expect(c.items.single.isRead, isFalse);
      expect(c.unreadCount, 1);
      expect(r.posts, 1);
      c.dispose();
    },
  );
  test(
    'Read-all honors the documented null result without replay on failure',
    () async {
      final r = Repository();
      final c = NotificationController(repository: r, userId: '7');
      await c.initialize();
      r.writeFailure = AppFailure.offline;
      await c.markAllAsRead();
      expect(c.items.single.isRead, isFalse);
      expect(c.unreadCount, 1);
      r.writeFailure = null;
      await c.markAllAsRead();
      expect(c.items.single.isRead, isTrue);
      expect(c.unreadCount, 0);
      expect(r.posts, 2);
      c.dispose();
    },
  );
  test('Additional pages persist and a forbidden page invalidates previous content', () async {
    final r = Repository();
    final c = NotificationController(repository: r, userId: '7');
    await c.initialize();
    final other = NotificationItem(
      notificationId: '2',
      type: 'SYSTEM',
      title: 'Thông báo khác',
      body: '',
      createdAt: DateTime(2026),
    );
    r.pending = Completer()
      ..complete(
        NotificationListResponse(
          items: [other],
          unreadCount: 2,
          after: '3',
          hasNext: true,
        ),
      );
    await c.loadMore();
    expect(r.saved!.items, hasLength(2));
    expect(c.unreadCount, 2);
    r.failure = const AppFailure(FailureKind.forbidden, 'Không còn quyền');
    await c.loadMore();
    expect(c.items, isEmpty);
    expect(r.saved, isNull);
    c.dispose();
  });
  test('Disposed notification controller ignores a delayed response', () async {
    final r = Repository()..pending = Completer();
    final c = NotificationController(repository: r, userId: '7');
    final future = c.fetchFirstPage();
    c.dispose();
    r.pending!.complete(
      const NotificationListResponse(items: [], unreadCount: 0),
    );
    await future;
    expect(r.saved, isNull);
  });
  test(
    'Offline mark-read does not fake success or replay; confirmation persists',
    () async {
      final r = Repository();
      final c = NotificationController(repository: r, userId: '7');
      await c.initialize();
      r.writeFailure = AppFailure.offline;
      await c.markAsRead('1');
      expect(c.unreadCount, 1);
      expect(c.items.single.isRead, isFalse);
      expect(c.errorMessage, isNotNull);
      expect(r.posts, 1);
      r.writeFailure = null;
      await c.markAsRead('1');
      expect(c.unreadCount, 0);
      expect(r.saved!.items.single.isRead, isTrue);
      c.dispose();
    },
  );
  test('Offline retains cache, forbidden drops it, pagination stops a repeated cursor', () async {
    final r = Repository();
    final c = NotificationController(repository: r, userId: '7');
    await c.initialize();
    await c.loadMore();
    expect(c.hasNext, isFalse);
    expect(c.items, hasLength(1));
    r.failure = AppFailure.offline;
    await c.refresh();
    expect(c.items, hasLength(1));
    r.failure = const AppFailure(FailureKind.forbidden, 'Không có quyền');
    await c.refresh();
    expect(c.items, isEmpty);
    expect(r.clears, 1);
    c.dispose();
  });
  test('Push targets validate account, type and numeric IDs', () {
    expect(
      NotificationPresenter.target({
        'recipient_user_id': '8',
        'target_type': 'POST',
        'target_id': 1,
      }, '7'),
      isNull,
    );
    expect(
      NotificationPresenter.target({
        'target_type': 'POST',
        'target_id': '../admin',
      }, '7'),
      isNull,
    );
    expect(
      NotificationPresenter.target({
        'target_type': 'ADMIN',
        'target_id': 1,
      }, '7'),
      isNull,
    );
    expect(
      NotificationPresenter.target({
        'recipient_user_id': '7',
        'target_type': 'POST',
        'target_id': 1,
      }, '7')?['id'],
      '1',
    );
    expect(
      NotificationPresenter.stableId('one'),
      NotificationPresenter.stableId('one'),
    );
  });
}
