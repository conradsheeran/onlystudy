import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/bili_models.dart';
import 'auth_service.dart';
import 'bili_failure.dart';
import 'bili_http_client.dart';
import 'settings_service.dart';

/// Bilibili API 服务（OPT-007）。
///
/// 所有请求通过 [BiliHttpClient] 统一发送：
/// - Cookie 注入、User-Agent/Referer、超时统一配置。
/// - 业务 `code` 检查统一处理，失败抛 [BiliFailure]。
/// - 服务层不再抛包含中文文案的 `Exception`。
///
/// 公共方法签名保持不变，屏幕端仅需适配 [BiliFailure] 展示。
class BiliApiService {
  BiliApiService({BiliHttpClient? client})
      : _client = client ?? BiliHttpClient();

  final BiliHttpClient _client;

  String? _cachedWbiKey;
  int _cachedWbiKeyTs = 0;

  /// 获取用户 ID (up_mid)
  Future<int?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return int.tryParse(prefs.getString('uid') ?? '');
  }

  /// 获取 WBI 混淆密钥，按需缓存一小时
  Future<String> _getWbiKey() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_cachedWbiKey != null && now - _cachedWbiKeyTs < 3600 * 1000) {
      return _cachedWbiKey!;
    }

    final data = await _client.get('/x/web-interface/nav');
    final wbiImg = data['data']?['wbi_img'];
    final imgUrl = wbiImg?['img_url'] ?? '';
    final subUrl = wbiImg?['sub_url'] ?? '';
    final imgKey = _extractKeyFromUrl(imgUrl);
    final subKey = _extractKeyFromUrl(subUrl);

    if (imgKey.isEmpty || subKey.isEmpty) {
      throw const BiliFailure(BiliFailureKind.notFound, message: 'WBI key missing');
    }

    final mixinKey = _mixinKey('$imgKey$subKey');
    _cachedWbiKey = mixinKey;
    _cachedWbiKeyTs = now;
    return mixinKey;
  }

  /// 从 WBI 图片 URL 中提取 key
  String _extractKeyFromUrl(String url) {
    if (url.isEmpty) return '';
    final parts = url.split('/');
    if (parts.isEmpty) return '';
    final last = parts.last;
    return last.split('.').first;
  }

  /// 混淆算法生成 WBI 密钥
  String _mixinKey(String origin) {
    const mixinKeyEncTab = [
      46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35,
      27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13,
      37, 48, 7, 16, 24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4,
      22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36, 20, 34, 44, 52,
    ];
    final chars = origin.split('');
    final buffer = StringBuffer();
    for (final idx in mixinKeyEncTab) {
      if (idx < chars.length) {
        buffer.write(chars[idx]);
      }
    }
    return buffer.toString().substring(0, 32);
  }

  /// 构建带 w_rid 和 wts 的签名参数
  Future<Map<String, dynamic>> _buildWbiParams(
      Map<String, dynamic> params) async {
    final wbiKey = await _getWbiKey();
    final filtered = <String, dynamic>{};
    params.forEach((key, value) {
      if (value == null) return;
      filtered[key] = _filterWbiValue(value.toString());
    });
    final wts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    filtered['wts'] = wts;
    final sortedKeys = filtered.keys.toList()..sort();
    final query = sortedKeys.map((k) => '$k=${filtered[k]}').join('&');
    final wRid = md5.convert(utf8.encode('$query$wbiKey')).toString();
    filtered['w_rid'] = wRid;
    return filtered;
  }

  /// 过滤参数中的特殊字符，符合 WBI 要求
  String _filterWbiValue(String input) {
    final blacklist = RegExp(r"[!'()*]");
    return input.replaceAll(blacklist, '');
  }

  /// 获取用户的收藏夹列表
  Future<List<Folder>> getFavoriteFolders({int pn = 1, int ps = 20}) async {
    final uid = await getUserId();
    if (uid == null) {
      throw const BiliFailure(BiliFailureKind.unauthorized, message: 'no uid');
    }

    final data = await _client.get(
      '/x/v3/fav/folder/created/list',
      queryParameters: {
        'up_mid': uid,
        'pn': pn,
        'ps': ps,
        'jsonp': 'jsonp',
      },
    );
    final list = data['data']?['list'] ?? [];
    return List<Folder>.from(
      list.map((item) => Folder.fromJson(item)),
    );
  }

  /// 获取指定收藏夹内的视频列表
  Future<List<Video>> getFolderVideos(int mediaId,
      {int pn = 1, int ps = 20, String? keyword}) async {
    final queryParams = {
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
    return List<Video>.from(
      medias.map((item) => Video.fromJson(item)),
    );
  }

  /// 获取用户订阅的合集列表
  Future<List<Season>> getSubscribedSeasons({int pn = 1, int ps = 20}) async {
    final uid = await getUserId();
    if (uid == null) {
      throw const BiliFailure(BiliFailureKind.unauthorized, message: 'no uid');
    }

    final data = await _client.get(
      '/x/v3/fav/folder/collected/list',
      queryParameters: {
        'up_mid': uid,
        'pn': pn,
        'ps': ps,
        'platform': 'web',
      },
    );
    final list = data['data']?['list'] ?? [];
    return List<Season>.from(
      list.map((item) => Season(
            id: item['id'],
            title: item['title'],
            cover: item['cover'] ?? '',
            mediaCount: item['media_count'] ?? 0,
            upper: BiliUpper(
              mid: item['upper']?['mid'] ?? 0,
              name: item['upper']?['name'] ?? '',
            ),
          )),
    );
  }

  /// 获取合集内的视频列表。
  ///
  /// 优先尝试收藏夹资源接口；若端点不适用（返回空列表），
  /// 再回退到合集档案接口。真实网络失败直接抛出，不会被误判为回退。
  Future<List<Video>> getSeasonVideos(int seasonId, int mid,
      {int pn = 1, int ps = 20}) async {
    try {
      final folderVideos = await getFolderVideos(seasonId, pn: pn, ps: ps);
      if (folderVideos.isNotEmpty) {
        return folderVideos;
      }
      // 收藏夹接口返回空，视为端点不适用，继续尝试合集接口。
    } on BiliFailure catch (e) {
      if (e.kind != BiliFailureKind.notFound) {
        // 真实业务/网络失败不属于“端点不适用”，交给合集接口决定。
        // 这里不吞掉网络错误：如果合集接口也失败，由上层处理。
        if (e.kind == BiliFailureKind.network ||
            e.kind == BiliFailureKind.unauthorized) {
          rethrow;
        }
      }
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
      archives.map((item) => Video(
            bvid: item['bvid'] ?? '',
            title: item['title'] ?? '',
            cover: item['pic'] ?? '',
            duration: item['duration'] ?? 0,
            upper: BiliUpper(mid: mid, name: item['author'] ?? ''),
            view: item['stat']?['view'] ?? 0,
            danmaku: item['stat']?['danmaku'] ?? 0,
            pubTimestamp: item['pubdate'] ?? 0,
          )),
    );
  }

  /// 获取视频详情 (包含 CID, AID, 历史进度)
  Future<VideoDetail> getVideoDetail(String bvid) async {
    final data = await _client.get(
      '/x/web-interface/view',
      queryParameters: {'bvid': bvid},
    );
    return VideoDetail.fromJson(data['data']);
  }

  /// 上报播放进度（失败静默，不阻塞本地保存）
  Future<void> reportHistory({
    required int aid,
    required int cid,
    required int progress,
  }) async {
    final csrf = await AuthService().getCsrfToken();
    try {
      await _client.post(
        '/x/v2/history/report',
        data: {
          'aid': aid,
          'cid': cid,
          'progress': progress,
          'platform': 'android',
          'csrf': csrf,
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
    } catch (e) {
      // 忽略上报错误
    }
  }

  /// 获取 UP 主基础信息、粉丝数据与统计
  Future<BiliUserInfo> getUpInfo(int mid) async {
    final results = await Future.wait([
      _client.get('/x/space/acc/info', queryParameters: {'mid': mid}),
      _client.get('/x/relation/stat', queryParameters: {'vmid': mid}),
      _client.get('/x/space/upstat', queryParameters: {'mid': mid}),
      _client.get('/x/space/navnum', queryParameters: {'mid': mid}),
    ]);

    return BiliUserInfo.fromApis(
      info: Map<String, dynamic>.from(results[0]['data'] ?? {}),
      relation: Map<String, dynamic>.from(results[1]['data'] ?? {}),
      upstat: Map<String, dynamic>.from(results[2]['data'] ?? {}),
      navnum: Map<String, dynamic>.from(results[3]['data'] ?? {}),
    );
  }

  /// 获取 UP 主投稿列表（仅视频稿件，支持排序与分区筛选）
  Future<UpSpaceVideoPage> getUpVideos({
    required int mid,
    int pn = 1,
    int ps = 20,
    String order = 'pubdate',
    int? tid,
  }) async {
    final params = {
      'mid': mid,
      'pn': pn,
      'ps': ps,
      'order': order,
      'platform': 'web',
    };
    final signedParams = await _buildWbiParams(params);
    final data = await _client.get(
      '/x/space/wbi/arc/search',
      queryParameters: signedParams,
    );

    final payload = data['data'] ?? {};
    final list = payload['list'] ?? {};
    final vlist = List<Map<String, dynamic>>.from(list['vlist'] ?? []);
    final videos = vlist.map((item) => Video.fromJson(item)).toList();

    final tlistRaw = list['tlist'] as Map<String, dynamic>?;
    final categories = <UpSpaceCategory>[];
    if (tlistRaw != null) {
      tlistRaw.forEach((_, value) {
        if (value is Map<String, dynamic>) {
          categories.add(UpSpaceCategory.fromJson(value));
        }
      });
      categories.sort((a, b) => b.count.compareTo(a.count));
    }

    final page = payload['page'] ?? {};
    final total = page['count'] ?? videos.length;
    final hasMore = (pn * ps) < total;

    return UpSpaceVideoPage(
      videos: videos,
      categories: categories,
      hasMore: hasMore,
      totalCount: total,
      pageNumber: pn,
    );
  }

  /// 获取当前账号关注的 UP 主列表
  Future<List<FollowUser>> getFollowings({int pn = 1, int ps = 20}) async {
    final mid = await getUserId();
    if (mid == null) {
      throw const BiliFailure(BiliFailureKind.unauthorized, message: 'no uid');
    }

    final data = await _client.get(
      '/x/relation/followings',
      queryParameters: {
        'vmid': mid,
        'pn': pn,
        'ps': ps,
        'order': 'desc',
      },
    );
    final list = List<Map<String, dynamic>>.from(
      data['data']?['list'] ?? [],
    );
    return list.map((item) => FollowUser.fromJson(item)).toList();
  }

  /// 获取 UP 主的合集（系列）列表
  Future<List<UpSeries>> getUpSeries(int mid) async {
    final data = await _client.get(
      '/x/series/series',
      queryParameters: {'mid': mid},
    );

    final payload = data['data'] ?? {};
    final items = payload['items'] ?? payload['list'] ?? [];
    if (items is! List) {
      return [];
    }

    final list = List<Map<String, dynamic>>.from(items);
    return list.map((item) => UpSeries.fromJson(item)).toList();
  }

  /// 获取指定合集下的视频列表
  Future<UpSpaceVideoPage> getUpSeriesVideos({
    required int mid,
    required int seriesId,
    int pn = 1,
    int ps = 20,
  }) async {
    final data = await _client.get(
      '/x/series/archives',
      queryParameters: {
        'mid': mid,
        'series_id': seriesId,
        'pn': pn,
        'ps': ps,
      },
    );

    final archives = List<Map<String, dynamic>>.from(
      data['data']?['archives'] ?? [],
    );
    final videos = archives.map((item) => Video.fromJson(item)).toList();
    final page = data['data']?['page'] ?? {};
    final total = page['count'] ?? videos.length;
    final hasMore = (pn * ps) < total;

    return UpSpaceVideoPage(
      videos: videos,
      categories: const [],
      hasMore: hasMore,
      totalCount: total,
      pageNumber: pn,
    );
  }

  /// 获取播放地址
  Future<VideoPlayInfo> getVideoPlayUrl(String bvid, int cid, {int? qn}) async {
    final data = await _client.get(
      '/x/player/playurl',
      queryParameters: {
        'bvid': bvid,
        'cid': cid,
        'qn': qn ?? SettingsService().defaultResolution,
        'fnval': 1,
        'fnver': 0,
        'fourk': 1,
      },
    );
    return VideoPlayInfo.fromJson(data['data']);
  }
}
