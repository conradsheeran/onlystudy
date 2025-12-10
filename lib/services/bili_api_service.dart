import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/bili_models.dart';
import 'auth_service.dart';

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

  // 获取用户 ID (up_mid)
  Future<int?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return int.tryParse(prefs.getString('uid') ?? '');
  }

  // 获取请求头所需的 Cookie 字符串
  Future<String> _getCookieHeader() async {
    return AuthService().getCookieString();
  }

  // 获取用户的收藏夹列表
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

  // 获取指定收藏夹内的视频列表
  Future<List<Video>> getFolderVideos(int mediaId,
      {int pn = 1, int ps = 20}) async {
    try {
      final response = await _dio.get(
        '/x/v3/fav/resource/list',
        queryParameters: {
          'media_id': mediaId,
          'pn': pn,
          'ps': ps,
          'jsonp': 'jsonp',
        },
        options: Options(headers: {'Cookie': await _getCookieHeader()}),
      );

      if (response.data['code'] == 0) {
        List<Video> videos = [];
        for (var item in response.data['data']['medias']) {
          videos.add(Video.fromJson(item));
        }
        return videos;
      } else {
        throw Exception('获取收藏夹视频失败: ${response.data['message']}');
      }
    } catch (e) {
      rethrow;
    }
  }

  // 获取视频详情
  Future<int> getVideoCid(String bvid) async {
    try {
      final response = await _dio.get(
        '/x/web-interface/view',
        queryParameters: {'bvid': bvid},
        options: Options(headers: {'Cookie': await _getCookieHeader()}),
      );
      if (response.data['code'] == 0) {
        return response.data['data']['cid'];
      } else {
        throw Exception('获取视频详情失败: ${response.data['message']}');
      }
    } catch (e) {
      rethrow;
    }
  }

  // 获取播放地址
  Future<VideoPlayInfo> getVideoPlayUrl(String bvid, int cid, {int qn = 64}) async {
    try {
      final response = await _dio.get(
        '/x/player/playurl',
        queryParameters: {
          'bvid': bvid,
          'cid': cid,
          'qn': qn, // 默认 64 = 720p
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
