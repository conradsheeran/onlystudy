import '../models/bili_models.dart';
import 'bili_failure.dart';
import 'bili_http_client.dart';

/// 收藏夹与合集目录（OPT-007 领域模块）。
///
/// 负责：
/// - 用户创建的收藏夹列表与其中视频。
/// - 订阅的合集列表与其中视频（含 [getSeasonVideos] 的端点 fallback）。
/// - 隐藏 UID 读取、分页与端点不适用/真实失败的区分。
///
/// 所有请求通过 [BiliHttpClient] 统一发送，失败抛 [BiliFailure]。
class FavoritesCatalog {
  FavoritesCatalog({BiliHttpClient? client})
    : _client = client ?? BiliHttpClient();

  final BiliHttpClient _client;

  /// 获取用户 ID（B 站 mid）。
  Future<int?> getUserId() async {
    return _client.authService.getUserId();
  }

  /// 获取用户的收藏夹列表。
  Future<List<Folder>> getFavoriteFolders({int pn = 1, int ps = 20}) async {
    final uid = await getUserId();
    if (uid == null) {
      throw const BiliFailure(BiliFailureKind.unauthorized, message: 'no uid');
    }

    final data = await _client.get(
      '/x/v3/fav/folder/created/list',
      queryParameters: {'up_mid': uid, 'pn': pn, 'ps': ps, 'jsonp': 'jsonp'},
    );
    final list = data['data']?['list'] ?? [];
    return List<Folder>.from(list.map((item) => Folder.fromJson(item)));
  }

  /// 获取指定收藏夹内的视频列表。
  Future<List<Video>> getFolderVideos(
    int mediaId, {
    int pn = 1,
    int ps = 20,
    String? keyword,
  }) async {
    final queryParams = <String, dynamic>{
      'media_id': mediaId,
      'pn': pn,
      'ps': ps,
      'jsonp': 'jsonp',
      'order': 'mtime',
    };
    if (keyword != null && keyword.isNotEmpty) {
      queryParams['keyword'] = keyword;
    }

    final data = await _client.get(
      '/x/v3/fav/resource/list',
      queryParameters: queryParams,
    );
    final medias = data['data']?['medias'] ?? [];
    return List<Video>.from(medias.map((item) => Video.fromJson(item)));
  }

  /// 获取用户订阅的合集列表。
  Future<List<Season>> getSubscribedSeasons({int pn = 1, int ps = 20}) async {
    final uid = await getUserId();
    if (uid == null) {
      throw const BiliFailure(BiliFailureKind.unauthorized, message: 'no uid');
    }

    final data = await _client.get(
      '/x/v3/fav/folder/collected/list',
      queryParameters: {'up_mid': uid, 'pn': pn, 'ps': ps, 'platform': 'web'},
    );
    final list = data['data']?['list'] ?? [];
    return List<Season>.from(
      list.map(
        (item) => Season(
          id: item['id'],
          title: item['title'],
          cover: item['cover'] ?? '',
          mediaCount: item['media_count'] ?? 0,
          upper: BiliUpper(
            mid: item['upper']?['mid'] ?? 0,
            name: item['upper']?['name'] ?? '',
          ),
        ),
      ),
    );
  }

  /// 获取合集内的视频列表。
  ///
  /// 优先尝试收藏夹资源接口；若端点不适用（返回空列表），
  /// 再回退到合集档案接口。真实网络/凭据失败直接抛出，不会被误判为回退。
  Future<List<Video>> getSeasonVideos(
    int seasonId,
    int mid, {
    int pn = 1,
    int ps = 20,
  }) async {
    try {
      final folderVideos = await getFolderVideos(seasonId, pn: pn, ps: ps);
      if (folderVideos.isNotEmpty) {
        return folderVideos;
      }
      // 收藏夹接口返回空，视为端点不适用，继续尝试合集接口。
    } on BiliFailure catch (e) {
      if (e.kind == BiliFailureKind.network ||
          e.kind == BiliFailureKind.unauthorized) {
        // 真实网络/凭据失败不属于“端点不适用”，直接抛出。
        rethrow;
      }
      // 其他业务错误（如参数错误）也回退到合集接口。
    }

    final data = await _client.get(
      '/x/polymer/web-space/seasons_archives_list',
      queryParameters: {
        'mid': mid,
        'season_id': seasonId,
        'sort_reverse': false,
        'page_num': pn,
        'page_size': ps,
      },
    );
    final archives = data['data']?['archives'] ?? [];
    return List<Video>.from(
      archives.map(
        (item) => Video(
          bvid: item['bvid'] ?? '',
          title: item['title'] ?? '',
          cover: item['pic'] ?? '',
          duration: item['duration'] ?? 0,
          upper: BiliUpper(mid: mid, name: item['author'] ?? ''),
          view: item['stat']?['view'] ?? 0,
          danmaku: item['stat']?['danmaku'] ?? 0,
          pubTimestamp: item['pubdate'] ?? 0,
        ),
      ),
    );
  }
}
