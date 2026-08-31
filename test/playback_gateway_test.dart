import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onlystudy/services/auth_service.dart';
import 'package:onlystudy/services/bili_http_client.dart';
import 'package:onlystudy/services/playback_gateway.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 可编程 [BiliTransport] 替身：按路径返回预设响应或抛预设异常。
class _FakeTransport implements BiliTransport {
  final Map<String, Map<String, dynamic>> responses = {};
  final Map<String, DioException> errors = {};
  final List<String> requestedPaths = [];
  final List<Map<String, dynamic>> requestedQueries = [];

  void on(String path, Map<String, dynamic> data) {
    responses[path] = data;
  }

  void throwOn(String path, DioException error) {
    errors[path] = error;
  }

  @override
  Future<Response<Map<String, dynamic>>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    requestedPaths.add(path);
    requestedQueries.add(Map<String, dynamic>.from(queryParameters ?? {}));
    final error = errors[path];
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
    final error = errors[path];
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
  late PlaybackGateway gateway;

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'uid': '10086',
      'SESSDATA': 'sess',
      'bili_jct': 'csrf_token',
    });
    transport = _FakeTransport();
    gateway = PlaybackGateway(
      client: BiliHttpClient(transport: transport, authService: AuthService()),
    );
  });

  group('PlaybackGateway.getVideoPlayUrl', () {
    test('播放请求使用 DASH fnval=4048 与目标清晰度', () async {
      transport.on('/x/player/playurl', {
        'code': 0,
        'data': {
          'quality': 64,
          'dash': {
            'video': [
              {'id': 64, 'baseUrl': 'http://video/64.m4s'},
            ],
          },
        },
      });

      await gateway.getVideoPlayUrl('BV1', 123, qn: 64);

      expect(transport.requestedQueries.single['fnval'], 4048);
      expect(transport.requestedQueries.single['qn'], 64);
      expect(transport.requestedQueries.single['fnver'], 0);
      expect(transport.requestedQueries.single['fourk'], 1);
    });

    test('解析 DASH 播放地址（含音频轨道）', () async {
      transport.on('/x/player/playurl', {
        'code': 0,
        'data': {
          'quality': 80,
          'accept_quality': [80, 64, 32],
          'accept_description': ['1080P', '720P', '480P'],
          'dash': {
            'video': [
              {'id': 80, 'baseUrl': 'http://video/80.mp4'},
              {'id': 64, 'baseUrl': 'http://video/64.mp4'},
            ],
            'audio': [
              {'id': 30216, 'baseUrl': 'http://audio/30216.m4a'},
            ],
          },
        },
      });

      final info = await gateway.getVideoPlayUrl('BV1', 123, qn: 80);

      expect(info.quality, 80);
      expect(info.url, 'http://video/80.mp4');
      expect(info.audioUrl, 'http://audio/30216.m4a');
      expect(info.acceptQuality, [80, 64, 32]);
    });

    test('解析 Progressive 播放地址（无音频轨道）', () async {
      transport.on('/x/player/playurl', {
        'code': 0,
        'data': {
          'quality': 32,
          'accept_quality': [32],
          'accept_description': ['480P'],
          'durl': [
            {'url': 'http://progressive/480.mp4'},
          ],
        },
      });

      final info = await gateway.getVideoPlayUrl('BV1', 123);

      expect(info.url, 'http://progressive/480.mp4');
      expect(info.audioUrl, isNull);
    });

    test('下载地址明确使用带音频的 progressive 请求', () async {
      transport.on('/x/player/playurl', {
        'code': 0,
        'data': {
          'quality': 64,
          'durl': [
            {'url': 'http://progressive/64.mp4'},
          ],
        },
      });

      final info = await gateway.getDownloadUrl('BV1', 123, qn: 64);

      expect(info.url, 'http://progressive/64.mp4');
      expect(info.audioUrl, isNull);
      expect(transport.requestedQueries.single['fnval'], 1);
      expect(transport.requestedQueries.single['qn'], 64);
    });
  });

  group('PlaybackGateway.reportHistory', () {
    test('上报成功后不抛异常', () async {
      transport.on('/x/v2/history/report', {'code': 0, 'data': {}});

      await gateway.reportHistory(aid: 1, cid: 2, progress: 30);

      expect(transport.requestedPaths, contains('/x/v2/history/report'));
    });

    test('网络失败静默（不抛异常）', () async {
      transport.throwOn(
        '/x/v2/history/report',
        DioException(
          type: DioExceptionType.connectionError,
          requestOptions: RequestOptions(path: '/x/v2/history/report'),
        ),
      );

      // 不应抛出
      await gateway.reportHistory(aid: 1, cid: 2, progress: 30);
    });
  });
}
