import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onlystudy/services/auth_service.dart';
import 'package:onlystudy/services/bili_failure.dart';
import 'package:onlystudy/services/bili_http_client.dart';
import 'package:onlystudy/services/favorites_catalog.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 可编程 [BiliTransport] 替身：按路径返回预设响应或抛预设异常。
class _FakeTransport implements BiliTransport {
  final Map<String, Map<String, dynamic>> responses = {};
  final List<String> requestedPaths = [];

  void on(String path, Map<String, dynamic> data) {
    responses[path] = data;
  }

  void throwOn(String path, DioException error) {
    responses[path] = _throw;
    _errors[path] = error;
  }

  static const _throw = <String, dynamic>{};

  final Map<String, DioException> _errors = {};

  @override
  Future<Response<Map<String, dynamic>>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    requestedPaths.add(path);
    final error = _errors[path];
    if (error != null) throw error;
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
    final error = _errors[path];
    if (error != null) throw error;
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
  late FavoritesCatalog catalog;

  setUp(() {
    SharedPreferences.setMockInitialValues({'uid': '10086'});
    transport = _FakeTransport();
    catalog = FavoritesCatalog(
      client: BiliHttpClient(transport: transport, authService: AuthService()),
    );
  });

  group('FavoritesCatalog.getSeasonVideos fallback', () {
    test('收藏夹接口有数据时直接返回，不请求合集接口', () async {
      transport.on('/x/v3/fav/resource/list', {
        'code': 0,
        'data': {
          'medias': [
            {'bvid': 'BV1', 'title': '视频1', 'duration': 60},
          ],
        },
      });

      final videos = await catalog.getSeasonVideos(42, 7);

      expect(videos, hasLength(1));
      expect(videos.first.bvid, 'BV1');
      expect(
        transport.requestedPaths,
        isNot(contains('/x/polymer/web-space/seasons_archives_list')),
      );
    });

    test('收藏夹接口返回空时回退合集接口', () async {
      transport.on('/x/v3/fav/resource/list', {
        'code': 0,
        'data': {'medias': []},
      });
      transport.on('/x/polymer/web-space/seasons_archives_list', {
        'code': 0,
        'data': {
          'archives': [
            {
              'bvid': 'BV2',
              'title': '合集视频',
              'pic': 'http://cover',
              'duration': 120,
              'author': '某UP',
            },
          ],
        },
      });

      final videos = await catalog.getSeasonVideos(42, 7);

      expect(videos, hasLength(1));
      expect(videos.first.bvid, 'BV2');
      expect(videos.first.upper.mid, 7);
      expect(
        transport.requestedPaths,
        contains('/x/polymer/web-space/seasons_archives_list'),
      );
    });

    test('真实网络失败直接抛出，不误判为端点不适用', () async {
      transport.throwOn(
        '/x/v3/fav/resource/list',
        DioException(
          type: DioExceptionType.connectionTimeout,
          requestOptions: RequestOptions(path: '/x/v3/fav/resource/list'),
        ),
      );

      expect(
        () => catalog.getSeasonVideos(42, 7),
        throwsA(
          isA<BiliFailure>().having(
            (f) => f.kind,
            'kind',
            BiliFailureKind.network,
          ),
        ),
      );
      // 合集接口不应被请求
      expect(
        transport.requestedPaths,
        isNot(contains('/x/polymer/web-space/seasons_archives_list')),
      );
    });

    test('未登录（无 uid）直接抛 unauthorized', () async {
      SharedPreferences.setMockInitialValues({});
      expect(
        () => catalog.getFavoriteFolders(),
        throwsA(
          isA<BiliFailure>().having(
            (f) => f.isUnauthorized,
            'isUnauthorized',
            isTrue,
          ),
        ),
      );
    });
  });
}
