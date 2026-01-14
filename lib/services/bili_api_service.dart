import 'dart:convert';
import 'package:flutter/foundation.dart';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/bili_models.dart';
import 'auth_service.dart';
import 'settings_service.dart';

class BiliApiService {
  static final BiliApiService _instance = BiliApiService._internal();
  factory BiliApiService() => _instance;
  BiliApiService._internal();

  String? _cachedWbiKey;
  int _cachedWbiKeyTs = 0;

  final Dio _dio = Dio(BaseOptions(
    baseUrl: 'https://api.bilibili.com',
    headers: {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Referer': 'https://www.bilibili.com/',
    },
  ));

  /// 获取用户 ID (up_mid)
  Future<int?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return int.tryParse(prefs.getString('uid') ?? '');
  }

  /// 获取请求头所需的 Cookie 字符串
  Future<String> _getCookieHeader() async {
    return AuthService().getCookieString();
  }

  /// 获取 WBI 混淆密钥，按需缓存一小时
  Future<String> _getWbiKey() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_cachedWbiKey != null && now - _cachedWbiKeyTs < 3600 * 1000) {
      return _cachedWbiKey!;
    }

    final response = await _dio.get(
      '/x/web-interface/nav',
      options: Options(headers: {'Cookie': await _getCookieHeader()}),
    );

    if (response.data['code'] != 0) {
      throw Exception('获取WBI密钥失败: ${response.data['message']}');
    }

    final wbiImg = response.data['data']?['wbi_img'];
    final imgUrl = wbiImg?['img_url'] ?? '';
    final subUrl = wbiImg?['sub_url'] ?? '';
    final imgKey = _extractKeyFromUrl(imgUrl);
    final subKey = _extractKeyFromUrl(subUrl);

    if (imgKey.isEmpty || subKey.isEmpty) {
      throw Exception('WBI密钥缺失');
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
      throw Exception('用户未登录或无法获取UID');
    }

    try {
      final response = await _dio.get(
        '/x/v3/fav/folder/created/list',
        queryParameters: {
          'up_mid': uid,
          'pn': pn,
          'ps': ps,
          'jsonp': 'jsonp',
        },
        options: Options(headers: {'Cookie': await _getCookieHeader()}),
      );

      if (response.data['code'] == 0) {
        List<Folder> folders = [];
        for (var item in response.data['data']['list']) {
          folders.add(Folder.fromJson(item));
        }
        return folders;
      } else {
        throw Exception('获取收藏夹列表失败: ${response.data['message']}');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// 获取指定收藏夹内的视频列表
  Future<List<Video>> getFolderVideos(int mediaId,
      {int pn = 1, int ps = 20, String? keyword}) async {
    try {
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

      final response = await _dio.get(
        '/x/v3/fav/resource/list',
        queryParameters: queryParams,
        options: Options(headers: {'Cookie': await _getCookieHeader()}),
      );

      if (response.data['code'] == 0) {
        List<Video> videos = [];
        if (response.data['data']['medias'] != null) {
          for (var item in response.data['data']['medias']) {
            videos.add(Video.fromJson(item));
          }
        }
        return videos;
      } else {
        throw Exception('获取收藏夹视频失败: ${response.data['message']}');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// 获取用户订阅的合集列表
  Future<List<Season>> getSubscribedSeasons({int pn = 1, int ps = 20}) async {
    final uid = await getUserId();
    if (uid == null) {
      throw Exception('用户未登录或无法获取UID');
    }

    try {
      final response = await _dio.get(
        '/x/v3/fav/folder/collected/list',
        queryParameters: {
          'up_mid': uid,
          'pn': pn,
          'ps': ps,
          'platform': 'web',
        },
        options: Options(headers: {'Cookie': await _getCookieHeader()}),
      );

      if (response.data['code'] == 0) {
        List<Season> seasons = [];
        final list = response.data['data']['list'];
        if (list != null) {
          for (var item in list) {
            // 尝试适配合集和收藏夹的数据结构
            seasons.add(Season(
              id: item['id'],
              title: item['title'],
              cover: item['cover'] ?? '',
              mediaCount: item['media_count'] ?? 0,
              upper: BiliUpper(
                mid: item['upper']?['mid'] ?? 0,
                name: item['upper']?['name'] ?? '未知UP主',
              ),
            ));
          }
        }
        return seasons;
      } else {
        throw Exception('获取订阅合集失败: ${response.data['message']}');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// 获取合集内的视频列表
  Future<List<Video>> getSeasonVideos(int seasonId, int mid,
      {int pn = 1, int ps = 20}) async {
    try {
      final folderVideos = await getFolderVideos(seasonId, pn: pn, ps: ps);
      if (folderVideos.isNotEmpty) {
        return folderVideos;
      }
    } catch (e) {
      //
    }

    try {
      final response = await _dio.get(
        '/x/polymer/web-space/seasons_archives_list',
        queryParameters: {
          'mid': mid,
          'season_id': seasonId,
          'sort_reverse': false,
          'page_num': pn,
          'page_size': ps,
        },
        options: Options(headers: {'Cookie': await _getCookieHeader()}),
      );

      if (response.data['code'] == 0) {
        List<Video> videos = [];
        final archives = response.data['data']['archives'];
        if (archives != null) {
          for (var item in archives) {
            videos.add(Video(
              bvid: item['bvid'] ?? '',
              title: item['title'] ?? '未知视频',
              cover: item['pic'] ?? '',
              duration: item['duration'] ?? 0,
              upper: BiliUpper(mid: mid, name: item['author'] ?? ''),
              view: item['stat']?['view'] ?? 0,
              danmaku: item['stat']?['danmaku'] ?? 0,
              pubTimestamp: item['pubdate'] ?? 0,
            ));
          }
        }
        return videos;
      } else {
        throw Exception('获取合集视频失败: ${response.data['message']}');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// 获取视频详情 (包含 CID, AID, 历史进度)
  Future<VideoDetail> getVideoDetail(String bvid) async {
    try {
      final response = await _dio.get(
        '/x/web-interface/view',
        queryParameters: {'bvid': bvid},
        options: Options(headers: {'Cookie': await _getCookieHeader()}),
      );
      if (response.data['code'] == 0) {
        return VideoDetail.fromJson(response.data['data']);
      } else {
        throw Exception('获取视频详情失败: ${response.data['message']}');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// 上报播放进度
  Future<void> reportHistory({
    required int aid,
    required int cid,
    required int progress,
  }) async {
    final csrf = await AuthService().getCsrfToken();
    try {
      await _dio.post(
        '/x/v2/history/report',
        data: {
          'aid': aid,
          'cid': cid,
          'progress': progress,
          'platform': 'android',
          'csrf': csrf,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {'Cookie': await _getCookieHeader()},
        ),
      );
    } catch (e) {
      // 忽略上报错误
    }
  }

  /// 获取 UP 主基础信息、粉丝数据与统计
  Future<BiliUserInfo> getUpInfo(int mid) async {
    final cookie = await _getCookieHeader();
    final options = Options(headers: {'Cookie': cookie});
    final results = await Future.wait([
      _dio.get('/x/space/acc/info',
          queryParameters: {'mid': mid}, options: options),
      _dio.get('/x/relation/stat',
          queryParameters: {'vmid': mid}, options: options),
      _dio.get('/x/space/upstat',
          queryParameters: {'mid': mid}, options: options),
      _dio.get('/x/space/navnum',
          queryParameters: {'mid': mid}, options: options),
    ]);

    for (final res in results) {
      if (res.data['code'] != 0) {
        throw Exception('获取UP信息失败: ${res.data['message']}');
      }
    }

    return BiliUserInfo.fromApis(
      info: Map<String, dynamic>.from(results[0].data['data'] ?? {}),
      relation: Map<String, dynamic>.from(results[1].data['data'] ?? {}),
      upstat: Map<String, dynamic>.from(results[2].data['data'] ?? {}),
      navnum: Map<String, dynamic>.from(results[3].data['data'] ?? {}),
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
    final response = await _dio.get(
      '/x/space/wbi/arc/search',
      queryParameters: signedParams,
      options: Options(headers: {'Cookie': await _getCookieHeader()}),
    );

    if (response.data['code'] != 0) {
      throw Exception('获取UP投稿失败: ${response.data['message']}');
    }

    final data = response.data['data'] ?? {};
    final list = data['list'] ?? {};
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

    final page = data['page'] ?? {};
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
      throw Exception('用户未登录或无法获取UID');
    }

    final response = await _dio.get(
      '/x/relation/followings',
      queryParameters: {
        'vmid': mid,
        'pn': pn,
        'ps': ps,
        'order': 'desc',
      },
      options: Options(headers: {'Cookie': await _getCookieHeader()}),
    );

    if (response.data['code'] != 0) {
      throw Exception('获取关注列表失败: ${response.data['message']}');
    }

    final list = List<Map<String, dynamic>>.from(
      response.data['data']?['list'] ?? [],
    );
    return list.map((item) => FollowUser.fromJson(item)).toList();
  }

  /// 获取 UP 主的合集（系列）列表
  Future<List<UpSeries>> getUpSeries(int mid) async {
    final response = await _dio.get(
      '/x/series/series',
      queryParameters: {'mid': mid},
      options: Options(headers: {'Cookie': await _getCookieHeader()}),
    );

    if (response.data['code'] != 0) {
      throw Exception('获取合集失败: ${response.data['message']}');
    }

    final data = response.data['data'] ?? {};
    final items = data['items'] ?? data['list'] ?? [];
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
    final response = await _dio.get(
      '/x/series/archives',
      queryParameters: {
        'mid': mid,
        'series_id': seriesId,
        'pn': pn,
        'ps': ps,
      },
      options: Options(headers: {'Cookie': await _getCookieHeader()}),
    );

    if (response.data['code'] != 0) {
      throw Exception('获取合集视频失败: ${response.data['message']}');
    }

    final archives = List<Map<String, dynamic>>.from(
      response.data['data']?['archives'] ?? [],
    );
    final videos = archives.map((item) => Video.fromJson(item)).toList();
    final page = response.data['data']?['page'] ?? {};
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
    try {
      final response = await _dio.get(
        '/x/player/playurl',
        queryParameters: {
          'bvid': bvid,
          'cid': cid,
          'qn': qn ?? SettingsService().defaultResolution,
          'fnval': 1,
          'fnver': 0,
          'fourk': 1,
        },
        options: Options(headers: {'Cookie': await _getCookieHeader()}),
      );

      if (response.data['code'] == 0) {
        return VideoPlayInfo.fromJson(response.data['data']);
      } else {
        throw Exception('获取播放地址失败: ${response.data['message']}');
      }
    } catch (e) {
      rethrow;
    }
  }
}
