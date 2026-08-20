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
    client = BiliHttpClient(transport: fakeTransport, authService: AuthService());
  });

  group('BiliHttpClient 业务 code 检查', () {
    test('code=0 时返回完整 data', () async {
      fakeTransport.responseData = {
        'code': 0,
        'message': 'ok',
        'data': {'list': [1, 2]},
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
          isA<BiliFailure>()
              .having((f) => f.isUnauthorized, 'isUnauthorized', isTrue),
        ),
      );
    });

    test('data 为 null 时抛 notFound', () async {
      fakeTransport.responseData = null;
      expect(
        () => client.get('/x/test'),
        throwsA(
          isA<BiliFailure>()
              .having((f) => f.kind, 'kind', BiliFailureKind.notFound),
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
          isA<BiliFailure>()
              .having((f) => f.kind, 'kind', BiliFailureKind.network),
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
          isA<BiliFailure>()
              .having((f) => f.isUnauthorized, 'isUnauthorized', isTrue),
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
          isA<BiliFailure>()
              .having((f) => f.kind, 'kind', BiliFailureKind.notFound),
        ),
      );
    });
  });

  group('BiliHttpClient Cookie 注入', () {
    test('从 AuthService 读取 Cookie 注入请求头', () async {
      fakeTransport.responseData = {
        'code': 0,
        'data': {},
      };
      await client.get('/x/test');
      expect(fakeTransport.lastHeaders?['Cookie'],
          'SESSDATA=sess_value; bili_jct=csrf_value');
    });

    test('未登录时不发送 Cookie 头', () async {
      SharedPreferences.setMockInitialValues({});
      fakeTransport.responseData = {
        'code': 0,
        'data': {},
      };
      await client.get('/x/test');
      expect(fakeTransport.lastHeaders?.containsKey('Cookie'), isFalse);
    });
  });
}
