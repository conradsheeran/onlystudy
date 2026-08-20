import 'package:flutter/foundation.dart';

/// 一页加载结果（OPT-008）。
///
/// [hasMore] 由调用方决定（如 `items.length < pageSize` 或服务端 total），
/// PagedLoader 不自行推断。
class PagedResult<T> {
  const PagedResult({required this.items, required this.hasMore});

  final List<T> items;
  final bool hasMore;
}

/// 分页加载状态（sealed）。
sealed class PagedState<T> {
  const PagedState();
}

/// 初始状态（尚未加载）。
class PagedInitial<T> extends PagedState<T> {
  const PagedInitial();
}

/// 首屏刷新中（refresh 已发起、列表被清空）。
class PagedLoading<T> extends PagedState<T> {
  const PagedLoading();
}

/// 加载成功。
///
/// [loadingMore] 为 true 表示正在追加下一页，列表尾部应显示加载指示。
class PagedLoaded<T> extends PagedState<T> {
  const PagedLoaded({
    required this.items,
    required this.hasMore,
    this.loadingMore = false,
  });

  final List<T> items;
  final bool hasMore;
  final bool loadingMore;
}

/// 首屏刷新失败。
class PagedError<T> extends PagedState<T> {
  const PagedError(this.error);

  final Object error;
}

/// 通用分页加载器（OPT-008）。
///
/// 统一管理：
/// - 页码递增；
/// - 是否还有更多；
/// - 请求世代号（快速 refresh 时旧响应不得覆盖新响应）；
/// - refresh / loadNext 区分；
/// - 列表合并；
/// - 首屏错误与追加错误分离。
///
/// 追加失败保留现有列表（不清空、不覆盖为错误页），并 rethrow，
/// 由调用方决定是否展示 SnackBar。
class PagedLoader<T> extends ValueNotifier<PagedState<T>> {
  PagedLoader({required this.fetchPage, this.pageSize = 20})
    : super(PagedInitial<T>());

  /// 拉取第 [page] 页（从 1 开始）。
  final Future<PagedResult<T>> Function(int page) fetchPage;

  /// 一页数量，用于判断是否需要自动加载下一页（触底场景由调用方触发）。
  final int pageSize;

  int _page = 1;
  bool _hasMore = true;
  int _generation = 0;
  bool _requestInFlight = false;

  /// 当前是否已加载过至少一页（用于区分“首屏加载中”与“加载完成”）。
  bool get hasLoaded => value is PagedLoaded<T> || value is PagedError<T>;

  /// 重置并加载第一页。
  Future<void> refresh() async {
    final gen = ++_generation;
    _page = 1;
    _hasMore = true;
    value = PagedLoading<T>();
    try {
      final result = await fetchPage(_page);
      if (gen != _generation) return; // 旧响应，丢弃
      if (result.hasMore) {
        _page++;
      } else {
        _hasMore = false;
      }
      value = PagedLoaded(items: result.items, hasMore: _hasMore);
    } catch (e) {
      if (gen != _generation) return;
      value = PagedError<T>(e);
    }
  }

  /// 追加下一页。失败时保留现有列表并 rethrow。
  Future<void> loadNext() async {
    if (_requestInFlight || !_hasMore) return;
    final current = value;
    if (current is! PagedLoaded<T>) return;

    _requestInFlight = true;
    final gen = _generation;
    final existing = current.items;
    value = PagedLoaded(items: existing, hasMore: _hasMore, loadingMore: true);

    try {
      final result = await fetchPage(_page);
      if (gen != _generation) return; // refresh 已接管，丢弃
      if (result.hasMore) {
        _page++;
      } else {
        _hasMore = false;
      }
      value = PagedLoaded(
        items: [...existing, ...result.items],
        hasMore: _hasMore,
      );
    } catch (e) {
      if (gen != _generation) return;
      // 追加失败：保留现有列表，标记为已结束，避免无限重试。
      value = PagedLoaded(items: existing, hasMore: _hasMore);
      rethrow;
    } finally {
      _requestInFlight = false;
    }
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }
}
