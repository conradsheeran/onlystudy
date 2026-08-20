import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/bili_models.dart';
import 'bili_failure.dart';
import 'bili_http_client.dart';

/// UP 主空间领域模块（OPT-007）。
///
/// 负责：
/// - 关注的 UP 主列表。
/// - UP 主主页信息（粉丝/统计，合并 4 个接口）。
/// - 投稿视频列表（含 WBI 签名）。
/// - UP 主合集（系列）列表与其中视频。
///
/// 所有请求通过 [BiliHttpClient] 统一发送，失败抛 [BiliFailure]。
/// WBI 密钥按需缓存一小时，签名逻辑集中在内部。
class UpLibrary {
  UpLibrary({BiliHttpClient? client}) : _client = client ?? BiliHttpClient();

  final BiliHttpClient _client;

  String? _cachedWbiKey;
  int _cachedWbiKeyTs = 0;

  /// 获取用户 ID（B 站 mid）。
  Future<int?> getUserId() async {
    return _client.authService.getUserId();
  }

  /// 获取当前账号关注的 UP 主列表。
  Future<List<FollowUser>> getFollowings({int pn = 1, int ps = 20}) async {
    final mid = await getUserId();
    if (mid == null) {
      throw const BiliFailure(BiliFailureKind.unauthorized, message: 'no uid');
    }

    final data = await _client.get(
      '/x/relation/followings',
      queryParameters: {'vmid': mid, 'pn': pn, 'ps': ps, 'order': 'desc'},
    );
    final list = List<Map<String, dynamic>>.from(data['data']?['list'] ?? []);
    return list.map((item) => FollowUser.fromJson(item)).toList();
  }

  /// 获取 UP 主基础信息、粉丝数据与统计。
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

  /// 获取 UP 主投稿列表（仅视频稿件，支持排序与分区筛选）。
  Future<UpSpaceVideoPage> getUpVideos({
    required int mid,
    int pn = 1,
    int ps = 20,
    String order = 'pubdate',
    int? tid,
  }) async {
    final params = <String, dynamic>{
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

  /// 获取 UP 主的合集（系列）列表。
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

  /// 获取指定合集下的视频列表。
  Future<UpSpaceVideoPage> getUpSeriesVideos({
    required int mid,
    required int seriesId,
    int pn = 1,
    int ps = 20,
  }) async {
    final data = await _client.get(
      '/x/series/archives',
      queryParameters: {'mid': mid, 'series_id': seriesId, 'pn': pn, 'ps': ps},
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

  // ---- WBI 签名 ----

  /// 获取 WBI 混淆密钥，按需缓存一小时。
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
      throw const BiliFailure(
        BiliFailureKind.notFound,
        message: 'WBI key missing',
      );
    }

    final mixinKey = _mixinKey('$imgKey$subKey');
    _cachedWbiKey = mixinKey;
    _cachedWbiKeyTs = now;
    return mixinKey;
  }

  /// 从 WBI 图片 URL 中提取 key。
  String _extractKeyFromUrl(String url) {
    if (url.isEmpty) return '';
    final parts = url.split('/');
    if (parts.isEmpty) return '';
    final last = parts.last;
    return last.split('.').first;
  }

  /// 混淆算法生成 WBI 密钥。
  String _mixinKey(String origin) {
    const mixinKeyEncTab = [
      46,
      47,
      18,
      2,
      53,
      8,
      23,
      32,
      15,
      50,
      10,
      31,
      58,
      3,
      45,
      35,
      27,
      43,
      5,
      49,
      33,
      9,
      42,
      19,
      29,
      28,
      14,
      39,
      12,
      38,
      41,
      13,
      37,
      48,
      7,
      16,
      24,
      55,
      40,
      61,
      26,
      17,
      0,
      1,
      60,
      51,
      30,
      4,
      22,
      25,
      54,
      21,
      56,
      59,
      6,
      63,
      57,
      62,
      11,
      36,
      20,
      34,
      44,
      52,
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

  /// 构建带 w_rid 和 wts 的签名参数。
  Future<Map<String, dynamic>> _buildWbiParams(
    Map<String, dynamic> params,
  ) async {
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

  /// 过滤参数中的特殊字符，符合 WBI 要求。
  String _filterWbiValue(String input) {
    final blacklist = RegExp(r"[!'()*]");
    return input.replaceAll(blacklist, '');
  }
}
