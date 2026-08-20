import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:onlystudy/services/paged_loader.dart';

void main() {
  group('PagedLoader refresh', () {
    test('加载第一页并发布 PagedLoaded', () async {
      final loader = PagedLoader<int>(
        fetchPage: (page) async => PagedResult(
          items: page == 1 ? [1, 2, 3] : [4, 5],
          hasMore: page < 2,
        ),
      );

      await loader.refresh();

      final state = loader.value;
      expect(state, isA<PagedLoaded<int>>());
      final loaded = state as PagedLoaded<int>;
      expect(loaded.items, [1, 2, 3]);
      expect(loaded.hasMore, isTrue);
    });

    test('首屏失败发布 PagedError', () async {
      final loader = PagedLoader<int>(
        fetchPage: (page) async => throw Exception('boom'),
      );

      await loader.refresh();

      expect(loader.value, isA<PagedError<int>>());
    });

    test('refresh 清除旧列表并加载新数据', () async {
      var call = 0;
      final loader = PagedLoader<int>(
        fetchPage: (page) async {
          call++;
          return PagedResult(items: [call], hasMore: false);
        },
      );

      await loader.refresh();
      expect((loader.value as PagedLoaded<int>).items, [1]);

      await loader.refresh();
      expect((loader.value as PagedLoaded<int>).items, [2]);
    });
  });

  group('PagedLoader loadNext', () {
    test('追加下一页并合并列表', () async {
      final loader = PagedLoader<int>(
        fetchPage: (page) async =>
            PagedResult(items: page == 1 ? [1, 2] : [3, 4], hasMore: page < 2),
      );

      await loader.refresh();
      await loader.loadNext();

      final loaded = loader.value as PagedLoaded<int>;
      expect(loaded.items, [1, 2, 3, 4]);
      expect(loaded.hasMore, isFalse);
    });

    test('没有更多时 loadNext 不发起请求', () async {
      var calls = 0;
      final loader = PagedLoader<int>(
        fetchPage: (page) async {
          calls++;
          return const PagedResult(items: [1], hasMore: false);
        },
      );

      await loader.refresh();
      await loader.loadNext();
      expect(calls, 1);
    });

    test('追加失败保留现有列表并 rethrow', () async {
      final loader = PagedLoader<int>(
        fetchPage: (page) async {
          if (page == 1) return const PagedResult(items: [1], hasMore: true);
          throw Exception('network');
        },
      );

      await loader.refresh();
      await expectLater(loader.loadNext(), throwsException);
      final loaded = loader.value as PagedLoaded<int>;
      expect(loaded.items, [1]);
    });
  });

  group('PagedLoader 请求竞争', () {
    test('快速 refresh 时旧响应不覆盖新响应（世代号）', () async {
      final completers = <Completer<PagedResult<int>>>[];
      final loader = PagedLoader<int>(
        fetchPage: (page) {
          final completer = Completer<PagedResult<int>>();
          completers.add(completer);
          return completer.future;
        },
      );

      final first = loader.refresh(); // 发起第 1 次
      final second = loader.refresh(); // 发起第 2 次（接管）
      await Future<void>.delayed(Duration.zero);

      // 旧响应晚返回
      completers[0].complete(const PagedResult(items: [1], hasMore: false));
      await first;

      // 新响应返回
      completers[1].complete(const PagedResult(items: [2], hasMore: false));
      await second;

      final loaded = loader.value as PagedLoaded<int>;
      expect(loaded.items, [2], reason: '旧响应不得覆盖新响应');
    });

    test('loadNext 期间 refresh 后，旧追加响应不覆盖新列表', () async {
      final page1 = Completer<PagedResult<int>>();
      final page2 = Completer<PagedResult<int>>();
      final page3 = Completer<PagedResult<int>>();
      var call = 0;
      final loader = PagedLoader<int>(
        fetchPage: (page) {
          call++;
          if (call == 1) return page1.future;
          if (call == 2) return page2.future;
          return page3.future;
        },
      );

      final refresh1 = loader.refresh();
      page1.complete(const PagedResult(items: [1], hasMore: true));
      await refresh1;

      final next = loader.loadNext(); // 追加第 2 页（挂起）
      await Future<void>.delayed(Duration.zero);

      final refresh2 = loader.refresh(); // 用户刷新（第 3 次调用）
      page3.complete(const PagedResult(items: [2], hasMore: false));
      await refresh2;

      // 旧追加响应此时才返回，应被丢弃
      page2.complete(const PagedResult(items: [99], hasMore: false));
      await next;

      final loaded = loader.value as PagedLoaded<int>;
      expect(loaded.items, [2], reason: '刷新后的旧追加响应不得覆盖');
    });
  });
}
