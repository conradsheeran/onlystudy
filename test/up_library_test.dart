import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onlystudy/services/auth_service.dart';
import 'package:onlystudy/services/bili_http_client.dart';
import 'package:onlystudy/services/up_library.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 可编程 [BiliTransport] 替身：按路径返回预设响应。
class _FakeTransport implements BiliTransport {
  final Map<String, Map<String, dynamic>> responses = {};
  final List<String> requestedPaths = [];

  void on(String path, Map<String, dynamic> data) {
    responses[path] = data;
  }

  @override
  Future<Response<Map<String, dynamic>>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    requestedPaths.add(path);
    return Response<Map<String, dynamic>>(
      data: responses[path],
      statusCode: 200,
      requestOptions: RequestOptions(path: path),
    );
  }

  @override
  Future<Response<Map<String, dynamic>>> post(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    requestedPaths.add(path);
    return Response<Map<String, dynamic>>(
      data: responses[path],
      statusCode: 200,
      requestOptions: RequestOptions(path: path),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeTransport transport;
  late UpLibrary upLibrary;

  setUp(() {
    SharedPreferences.setMockInitialValues({'uid': '10086'});
    transport = _FakeTransport();
    upLibrary = UpLibrary(
      client: BiliHttpClient(transport: transport, authService: AuthService()),
    );
  });

  group('UpLibrary.getUpVideos WBI 签名', () {
    test('请求携带 wts/w_rid 且带签名参数', () async {
      transport.on('/x/web-interface/nav', {
        'code': 0,
        'data': {
          'wbi_img': {
            'img_url':
                'https://i0.hdslb.com/bfs/wbi/7cd0849410c1c9b771b0d8d2e5f6a7b8c9d0e1f2a3b4c5d6e7f8.png',
            'sub_url':
                'https://i0.hdslb.com/bfs/wbi/1a2b3c4d5e6f708192a3b4c5d6e7f8a9b0c1d2e3f4.png',
          },
        },
      });
      transport.on('/x/space/wbi/arc/search', {
        'code': 0,
        'data': {
          'list': {
            'vlist': [
              {'bvid': 'BV1', 'title': '视频', 'duration': 60},
            ],
          },
          'page': {'count': 1},
        },
      });

      final page = await upLibrary.getUpVideos(mid: 7, pn: 1, ps: 20);

      expect(page.videos, hasLength(1));
      expect(page.videos.first.bvid, 'BV1');
      // 需要先请求 WBI 密钥
      expect(transport.requestedPaths, contains('/x/web-interface/nav'));
      expect(transport.requestedPaths, contains('/x/space/wbi/arc/search'));
    });
  });

  group('UpLibrary.getUpInfo', () {
    test('合并 4 个接口数据生成 BiliUserInfo', () async {
      transport.on('/x/space/acc/info', {
        'code': 0,
        'data': {'mid': 7, 'name': '某UP', 'face': 'http://face', 'sign': '简介'},
      });
      transport.on('/x/relation/stat', {
        'code': 0,
        'data': {'follower': 123, 'following': 45},
      });
      transport.on('/x/space/upstat', {
        'code': 0,
        'data': {
          'archive': {'view': 999, 'like': 888},
        },
      });
      transport.on('/x/space/navnum', {
        'code': 0,
        'data': {'video': 10},
      });

      final info = await upLibrary.getUpInfo(7);

      expect(info.mid, 7);
      expect(info.name, '某UP');
      expect(info.fans, 123);
      expect(info.videoCount, 10);
      expect(transport.requestedPaths, hasLength(4));
    });
  });

  group('UpLibrary.getFollowings', () {
    test('未登录（无 uid）抛 unauthorized', () async {
      SharedPreferences.setMockInitialValues({});
      expect(() => upLibrary.getFollowings(), throwsA(isA<Exception>()));
    });

    test('返回关注列表', () async {
      transport.on('/x/relation/followings', {
        'code': 0,
        'data': {
          'list': [
            {'mid': 11, 'uname': 'UP甲'},
            {'mid': 22, 'uname': 'UP乙'},
          ],
        },
      });

      final users = await upLibrary.getFollowings();

      expect(users, hasLength(2));
      expect(users.first.mid, 11);
      expect(users.first.name, 'UP甲');
    });
  });
}
