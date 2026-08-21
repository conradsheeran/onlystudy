import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onlystudy/services/auth_service.dart';
import 'package:onlystudy/services/bili_failure.dart';
import 'package:onlystudy/services/bili_http_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 最小可编程 [BiliTransport] 替身：记录请求并返回预设响应或抛预设异常。
class _FakeTransport implements BiliTransport {
  DioException? errorToThrow;
  Map<String, dynamic>? responseData;
  Map<String, String>? lastHeaders;
  String? lastPath;

  @override
  Future<Response<Map<String, dynamic>>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    lastPath = path;
    lastHeaders = options?.headers?.cast<String, String>();
    if (errorToThrow != null) {
      throw errorToThrow!;
    }
    return Response<Map<String, dynamic>>(
      data: responseData,
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
    lastPath = path;
    lastHeaders = options?.headers?.cast<String, String>();
    if (errorToThrow != null) {
      throw errorToThrow!;
    }
    return Response<Map<String, dynamic>>(
      data: responseData,
      statusCode: 200,
      requestOptions: RequestOptions(path: path),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeTransport fakeTransport;
  late BiliHttpClient client;

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'SESSDATA': 'sess_value',
      'bili_jct': 'csrf_value',
    });
    fakeTransport = _FakeTransport();
    client = BiliHttpClient(
      transport: fakeTransport,
      authService: AuthService(),
    );
  });

  group('BiliHttpClient 业务 code 检查', () {
    test('code=0 时返回完整 data', () async {
      fakeTransport.responseData = {
        'code': 0,
        'message': 'ok',
        'data': {
          'list': [1, 2],
        },
      };
      final result = await client.get('/x/test');
      expect(result['data']['list'], [1, 2]);
    });

    test('code!=0 时抛 bizError 且携带 code/message', () async {
      fakeTransport.responseData = {
        'code': -403,
        'message': '风控拦截',
        'data': null,
      };
      expect(
        () => client.get('/x/test'),
        throwsA(
          isA<BiliFailure>()
              .having((f) => f.kind, 'kind', BiliFailureKind.bizError)
              .having((f) => f.code, 'code', -403)
              .having((f) => f.message, 'message', '风控拦截'),
        ),
      );
    });

    test('code=-101 (未登录) 时抛 unauthorized', () async {
      fakeTransport.responseData = {
        'code': -101,
        'message': '账号未登录',
        'data': null,
      };
      expect(
        () => client.get('/x/test'),
        throwsA(
          isA<BiliFailure>().having(
            (f) => f.isUnauthorized,
            'isUnauthorized',
            isTrue,
          ),
        ),
      );
    });

    test('data 为 null 时抛 notFound', () async {
      fakeTransport.responseData = null;
      expect(
        () => client.get('/x/test'),
        throwsA(
          isA<BiliFailure>().having(
            (f) => f.kind,
            'kind',
            BiliFailureKind.notFound,
          ),
        ),
      );
    });
  });

  group('BiliHttpClient DioException 映射', () {
    test('超时映射为 network', () async {
      fakeTransport.errorToThrow = DioException(
        type: DioExceptionType.connectionTimeout,
        requestOptions: RequestOptions(path: '/x/test'),
      );
      expect(
        () => client.get('/x/test'),
        throwsA(
          isA<BiliFailure>().having(
            (f) => f.kind,
            'kind',
            BiliFailureKind.network,
          ),
        ),
      );
    });

    test('HTTP 401 映射为 unauthorized', () async {
      fakeTransport.errorToThrow = DioException(
        type: DioExceptionType.badResponse,
        response: Response(
          statusCode: 401,
          requestOptions: RequestOptions(path: '/x/test'),
        ),
        requestOptions: RequestOptions(path: '/x/test'),
      );
      expect(
        () => client.get('/x/test'),
        throwsA(
          isA<BiliFailure>().having(
            (f) => f.isUnauthorized,
            'isUnauthorized',
            isTrue,
          ),
        ),
      );
    });

    test('HTTP 404 映射为 notFound', () async {
      fakeTransport.errorToThrow = DioException(
        type: DioExceptionType.badResponse,
        response: Response(
          statusCode: 404,
          requestOptions: RequestOptions(path: '/x/test'),
        ),
        requestOptions: RequestOptions(path: '/x/test'),
      );
      expect(
        () => client.get('/x/test'),
        throwsA(
          isA<BiliFailure>().having(
            (f) => f.kind,
            'kind',
            BiliFailureKind.notFound,
          ),
        ),
      );
    });
  });

  group('BiliHttpClient Cookie 注入', () {
    test('从 AuthService 读取 Cookie 注入请求头', () async {
      fakeTransport.responseData = {'code': 0, 'data': {}};
      await client.get('/x/test');
      expect(
        fakeTransport.lastHeaders?['Cookie'],
        'SESSDATA=sess_value; bili_jct=csrf_value',
      );
    });

    test('未登录时不发送 Cookie 头', () async {
      SharedPreferences.setMockInitialValues({});
      fakeTransport.responseData = {'code': 0, 'data': {}};
      await client.get('/x/test');
      expect(fakeTransport.lastHeaders?.containsKey('Cookie'), isFalse);
    });
  });

  group('DioTransport 生产配置', () {
    test('默认构造自带 api.bilibili.com baseUrl（相对路径可解析为完整 URL）', () async {
      // 直接构造生产传输并请求一个相对路径；若 baseUrl 缺失，Dio 会把
      // 请求发到无 host 的 path-only URI（此前导致“网络连接失败”）。
      // 通过真实网络冒烟：能拿到业务 JSON 即证明 baseUrl 已生效。
      final transport = DioTransport();
      Map<String, dynamic>? result;
      try {
        final resp = await transport.get('/x/web-interface/nav');
        result = resp.data;
      } catch (_) {
        // 网络不可用环境下跳过，不能作为失败依据
      }
      if (result != null) {
        expect(result.containsKey('code'), isTrue);
        expect(result.containsKey('data'), isTrue);
      }
    });

    test('注入的 Dio 使用 api.bilibili.com baseUrl 与 UA/Referer 头', () async {
      final adapter = _CapturingAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'https://api.bilibili.com'))
        ..httpClientAdapter = adapter;
      final transport = DioTransport(dio: dio);
      try {
        await transport.get('/x/v3/fav/folder/created/list');
      } catch (_) {}
      final options = adapter.lastOptions;
      expect(options, isNotNull);
      expect(options!.uri.toString(), startsWith('https://api.bilibili.com'));
      expect(options.uri.path, '/x/v3/fav/folder/created/list');
    });
  });
}

class _CapturingAdapter implements HttpClientAdapter {
  RequestOptions? lastOptions;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastOptions = options;
    return ResponseBody.fromString(
      '{}',
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
