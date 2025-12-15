import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/bili_models.dart';
import 'auth_service.dart';
import 'settings_service.dart';

class BiliApiService {
  static final BiliApiService _instance = BiliApiService._internal();
  factory BiliApiService() => _instance;
  BiliApiService._internal();

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
  Future<List<Video>> getSeasonVideos(int seasonId, int mid, {int pn = 1, int ps = 20}) async {
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
               bvid: item['bvid'],
               title: item['title'],
               cover: item['cover'],
               duration: item['duration'],
               upper: BiliUpper(mid: mid, name: item['author'] ?? ''),
               view: item['stat']['view'],
               danmaku: item['stat']['danmaku'],
               pubTimestamp: item['pubdate'],
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

  /// 获取播放地址
  Future<VideoPlayInfo> getVideoPlayUrl(String bvid, int cid, {int? qn}) async {
    try {
      final response = await _dio.get(
        '/x/player/playurl',
        queryParameters: {
          'bvid': bvid,
          'cid': cid,
          'qn': qn ?? SettingsService().defaultResolution, 
          'fnval': 1, // mp4 格式
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