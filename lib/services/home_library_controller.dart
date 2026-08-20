import 'package:flutter/foundation.dart';

import '../models/bili_models.dart';
import 'auth_service.dart';
import 'favorites_catalog.dart';
import 'up_library.dart';
import 'bili_failure.dart';
import 'database_service.dart';

/// 主页内容条目（sealed，替代 `List<dynamic>`，OPT-009）。
sealed class LibraryItem {
  const LibraryItem();
}

class FolderItem extends LibraryItem {
  const FolderItem(this.folder);
  final Folder folder;
}

class SeasonItem extends LibraryItem {
  const SeasonItem(this.season);
  final Season season;
}

class UpItem extends LibraryItem {
  const UpItem(this.user);
  final FollowUser user;
}

/// 主页数据状态。
sealed class HomeLibraryState {
  const HomeLibraryState();
}

class HomeLibraryLoading extends HomeLibraryState {
  const HomeLibraryLoading();
}

class HomeLibraryError extends HomeLibraryState {
  const HomeLibraryError(this.error);
  final Object error;
}

class HomeLibraryLoaded extends HomeLibraryState {
  const HomeLibraryLoaded(this.items);
  final List<LibraryItem> items;
}

/// 主页内容控制器（OPT-009）。
///
/// 负责加载可见来源（收藏夹/合集/UP 主）、本地搜索与锁定状态，
/// 隐藏分页扫描、并发与错误恢复；UI 只渲染状态。
/// 与 Widget 生命周期解耦：同步任务由 [LibrarySyncCoordinator] 独立执行，
/// 不依赖 `mounted`。
class HomeLibraryController extends ValueNotifier<HomeLibraryState> {
  HomeLibraryController({
    FavoritesCatalog? catalog,
    UpLibrary? upLibrary,
    DatabaseService? databaseService,
    AuthService? authService,
  }) : _catalog = catalog ?? FavoritesCatalog(),
       _upLibrary = upLibrary ?? UpLibrary(),
       _db = databaseService ?? DatabaseService(),
       _auth = authService ?? AuthService(),
       super(const HomeLibraryLoading());

  final FavoritesCatalog _catalog;
  final UpLibrary _upLibrary;
  final DatabaseService _db;
  final AuthService _auth;

  static const int _maxScanPages = 5;
  static const int _pageSize = 20;

  List<int> _visibleFolderIds = [];
  List<int> _visibleSeasonIds = [];
  List<int> _visibleUpIds = [];

  /// 当前搜索关键词（非空时主页显示搜索结果）。
  String searchKeyword = '';

  List<Video> _searchResults = [];
  List<Video> get searchResults => _searchResults;

  bool _isLocked = false;
  bool get isLocked => _isLocked;

  /// 初始化：读取可见 ID 与锁定状态。
  Future<void> init() async {
    _isLocked = await _auth.isFolderSelectionLocked();
    await _reloadVisibleIds();
  }

  Future<void> _reloadVisibleIds() async {
    _visibleFolderIds = await _auth.getVisibleFolderIds();
    _visibleSeasonIds = await _auth.getVisibleSeasonIds();
    _visibleUpIds = await _auth.getVisibleUpIds();
  }

  /// 加载可见内容列表。
  Future<void> refresh() async {
    await _reloadVisibleIds();
    value = const HomeLibraryLoading();
    try {
      final items = await _loadVisibleItems();
      value = HomeLibraryLoaded(items);
    } catch (e) {
      value = HomeLibraryError(e);
    }
  }

  /// 全量重新加载（含后台同步），由刷新手势触发。
  Future<void> refreshWithSync() async {
    final previous = value;
    await refresh();
    if (value is HomeLibraryLoaded) {
      final loaded = value as HomeLibraryLoaded;
      LibrarySyncCoordinator().sync(
        folders: _foldersFrom(loaded.items),
        seasons: _seasonsFrom(loaded.items),
        ups: _upsFrom(loaded.items),
        onError: (source, id, e) =>
            debugPrint('Sync failed for $source $id: $e'),
      );
    } else if (previous is HomeLibraryLoaded && value is HomeLibraryError) {
      // 刷新失败但之前有数据：保留旧数据不显示错误页。
      value = previous;
    }
  }

  List<Folder> _foldersFrom(List<LibraryItem> items) =>
      items.whereType<FolderItem>().map((e) => e.folder).toList();
  List<Season> _seasonsFrom(List<LibraryItem> items) =>
      items.whereType<SeasonItem>().map((e) => e.season).toList();
  List<FollowUser> _upsFrom(List<LibraryItem> items) =>
      items.whereType<UpItem>().map((e) => e.user).toList();

  Future<List<LibraryItem>> _loadVisibleItems() async {
    final items = <LibraryItem>[];

    if (_visibleFolderIds.isNotEmpty) {
      final found = await _scanFolders();
      items.addAll(found.map(FolderItem.new));
    }
    if (_visibleSeasonIds.isNotEmpty) {
      final found = await _scanSeasons();
      items.addAll(found.map(SeasonItem.new));
    }
    if (_visibleUpIds.isNotEmpty) {
      final found = await _loadUps();
      items.addAll(found.map(UpItem.new));
    }
    return items;
  }

  /// 分页扫描收藏夹直到找到所有可见 ID（上限 [maxScanPages] 页）。
  Future<List<Folder>> _scanFolders() async {
    final result = <Folder>[];
    final foundIds = <int>{};
    var page = 1;
    while (foundIds.length < _visibleFolderIds.length &&
        page <= _maxScanPages) {
      final folders = await _catalog.getFavoriteFolders(
        pn: page,
        ps: _pageSize,
      );
      if (folders.isEmpty) break;
      for (final f in folders) {
        if (_visibleFolderIds.contains(f.id) && foundIds.add(f.id)) {
          result.add(f);
        }
      }
      if (folders.length < _pageSize) break;
      page++;
    }
    return result;
  }

  Future<List<Season>> _scanSeasons() async {
    final result = <Season>[];
    final foundIds = <int>{};
    var page = 1;
    while (foundIds.length < _visibleSeasonIds.length &&
        page <= _maxScanPages) {
      final seasons = await _catalog.getSubscribedSeasons(
        pn: page,
        ps: _pageSize,
      );
      if (seasons.isEmpty) break;
      for (final s in seasons) {
        if (_visibleSeasonIds.contains(s.id) && foundIds.add(s.id)) {
          result.add(s);
        }
      }
      if (seasons.length < _pageSize) break;
      page++;
    }
    return result;
  }

  /// 逐个加载 UP 信息（并发 4，避免串行变慢）。
  Future<List<FollowUser>> _loadUps() async {
    final results = <FollowUser>[];
    final mids = List<int>.from(_visibleUpIds);
    const concurrency = 4;
    for (var i = 0; i < mids.length; i += concurrency) {
      final chunk = mids.skip(i).take(concurrency).toList();
      final chunkResults = await Future.wait(
        chunk.map((mid) async {
          try {
            final info = await _upLibrary.getUpInfo(mid);
            return FollowUser(
              mid: info.mid,
              name: info.name,
              face: info.face,
              sign: info.sign,
              videoCount: info.videoCount,
            );
          } on BiliFailure {
            rethrow;
          } catch (e) {
            debugPrint('Failed to load up $mid: $e');
            return null;
          }
        }),
      );
      results.addAll(chunkResults.whereType<FollowUser>());
    }
    return results;
  }

  /// 本地搜索（仅命中可见来源）。
  Future<void> search(String keyword) async {
    searchKeyword = keyword;
    if (keyword.isEmpty) {
      _searchResults = [];
      return;
    }
    try {
      _searchResults = await _db.searchVideos(
        keyword,
        visibleFolderIds: _visibleFolderIds,
        visibleSeasonIds: _visibleSeasonIds,
        visibleUpIds: _visibleUpIds,
      );
    } catch (e) {
      debugPrint('Search error: $e');
      _searchResults = [];
    }
  }

  // ---- 锁定状态 ----

  Future<bool> setLocked(bool locked) async {
    await _auth.setFolderSelectionLocked(locked);
    _isLocked = locked;
    return _isLocked;
  }

  Future<bool> setLockPassword(String password) async {
    await _auth.setFolderLockPassword(password);
    return setLocked(true);
  }

  Future<bool> checkLockPassword(String password) async {
    final ok = await _auth.checkFolderLockPassword(password);
    if (ok) {
      _isLocked = false;
      await _auth.setFolderSelectionLocked(false);
    }
    return ok;
  }
}

/// 后台同步所有可见内容的视频数据到本地数据库（OPT-009）。
///
/// 独立于 Widget 生命周期运行，不依赖 `mounted`。
class LibrarySyncCoordinator {
  LibrarySyncCoordinator({
    FavoritesCatalog? catalog,
    UpLibrary? upLibrary,
    DatabaseService? db,
  }) : _catalog = catalog ?? FavoritesCatalog(),
       _upLibrary = upLibrary ?? UpLibrary(),
       _db = db ?? DatabaseService();

  final FavoritesCatalog _catalog;
  final UpLibrary _upLibrary;
  final DatabaseService _db;

  static const Duration _rateLimit = Duration(milliseconds: 500);

  Future<void> sync({
    required List<Folder> folders,
    required List<Season> seasons,
    required List<FollowUser> ups,
    void Function(String source, int id, Object error)? onError,
  }) async {
    for (final folder in folders) {
      try {
        final videos = await _catalog.getFolderVideos(folder.id, pn: 1, ps: 20);
        if (videos.isNotEmpty) {
          await _db.insertVideos(videos, folderId: folder.id);
        }
        await Future.delayed(_rateLimit);
      } catch (e) {
        onError?.call('folder', folder.id, e);
      }
    }
    for (final season in seasons) {
      try {
        final videos = await _catalog.getSeasonVideos(
          season.id,
          season.upper.mid,
          pn: 1,
          ps: 20,
        );
        if (videos.isNotEmpty) {
          await _db.insertVideos(videos, seasonId: season.id);
        }
        await Future.delayed(_rateLimit);
      } catch (e) {
        onError?.call('season', season.id, e);
      }
    }
    for (final up in ups) {
      try {
        final page = await _upLibrary.getUpVideos(mid: up.mid, pn: 1, ps: 20);
        if (page.videos.isNotEmpty) {
          await _db.insertVideos(page.videos, upId: up.mid);
        }
        await Future.delayed(_rateLimit);
      } catch (e) {
        onError?.call('up', up.mid, e);
      }
    }
  }
}
