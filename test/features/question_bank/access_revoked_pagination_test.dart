import 'package:flutter_test/flutter_test.dart';
import 'package:it4788_btl/core/errors/app_failure.dart';
import 'package:it4788_btl/core/storage/json_cache.dart';
import 'package:it4788_btl/features/question_bank/paged_list_controller.dart';
import 'package:it4788_btl/features/question_bank/question_models.dart';

import '../../support/fakes.dart';

void main() {
  test(
    'A revoked question-bank page removes earlier content and disk cache',
    () async {
      final cache = JsonCache(MemoryStore());
      final controller = PagedListController<int>(
        cache: cache,
        userId: '7',
        idOf: (item) => item,
        encode: (item) => item,
        decode: (raw) => raw as int,
        fetch: (after) async {
          if (after != null) {
            throw const AppFailure(FailureKind.forbidden, 'Đã thu hồi quyền');
          }
          return const CursorPage(items: [1], after: 1, hasNext: true);
        },
      )..setResource('test.permission');
      await controller.refresh();
      expect(controller.items, [1]);
      expect(
        await cache.read(userId: '7', resource: 'test.permission'),
        isNotNull,
      );
      await controller.loadMore();
      expect(controller.items, isEmpty);
      expect(controller.hasNext, isFalse);
      expect(controller.failure?.kind, FailureKind.forbidden);
      expect(
        await cache.read(userId: '7', resource: 'test.permission'),
        isNull,
      );
      controller.dispose();
    },
  );
}
