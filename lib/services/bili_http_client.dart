import 'package:dio/dio.dart';

import 'auth_service.dart';
import 'bili_failure.dart';

/// 底层 HTTP 传输抽象（OPT-007）。
///
/// 生产实现为 [DioTransport]；测试注入内存 fake 即可，
/// 无需 mock Dio 的复杂实现。
abstract interface class BiliTransport {
  Future<Response<Map<String, dynamic>>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  });

  Future<Response<Map<String, dynamic>>> post(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  });
}

/// 基于 Dio 的生产传输实现。
class DioTransport implements BiliTransport {
  DioTransport({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 10),
            ),
          );

  final Dio _dio;

  @override
  Future<Response<Map<String, dynamic>>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) {
    return _dio.get<Map<String, dynamic>>(
      path,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }

  @override
  Future<Response<Map<String, dynamic>>> post(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) {
    return _dio.post<Map<String, dynamic>>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }
}

/// Bilibili API 的统一网络传输（OPT-007）。
///
/// 集中管理：
/// - BaseOptions（baseUrl、User-Agent、Referer、超时）
/// - Cookie 注入（通过 [AuthService]）
/// - 业务 `code` 检查与 [BiliFailure] 转换
/// - DioException → [BiliFailureKind.network] 转换
///
/// 服务层只抛出 [BiliFailure]，不包含本地化文案。
class BiliHttpClient {
  BiliHttpClient({BiliTransport? transport, AuthService? authService})
    : _transport = transport ?? DioTransport(),
      _authService = authService ?? AuthService();

  final BiliTransport _transport;
  final AuthService _authService;

  /// 发起 GET 请求并校验 Bilibili 业务 code。
  ///
  /// [okCodes] 允许的 code 集合（默认只允许 0）。
  /// 失败抛 [BiliFailure]。
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    Set<int> okCodes = const {0},
  }) async {
    try {
      final cookie = await _authService.getCookieString();
      final response = await _transport.get(
        path,
        queryParameters: queryParameters,
        cancelToken: cancelToken,
        options:
            options ??
            Options(headers: {if (cookie.isNotEmpty) 'Cookie': cookie}),
      );
      return _checkBizCode(response.data, okCodes: okCodes);
    } on DioException catch (e) {
      throw _mapDioException(e);
    }
  }

  /// 发起 POST 请求并校验 Bilibili 业务 code。
  Future<Map<String, dynamic>> post(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    Set<int> okCodes = const {0},
  }) async {
    try {
      final cookie = await _authService.getCookieString();
      final response = await _transport.post(
        path,
        data: data,
        queryParameters: queryParameters,
        cancelToken: cancelToken,
        options:
            options ??
            Options(headers: {if (cookie.isNotEmpty) 'Cookie': cookie}),
      );
      return _checkBizCode(response.data, okCodes: okCodes);
    } on DioException catch (e) {
      throw _mapDioException(e);
    }
  }

  /// 校验 `response.data['code']`，非 [okCodes] 时抛 [BiliFailure]。
  Map<String, dynamic> _checkBizCode(
    Map<String, dynamic>? data, {
    Set<int> okCodes = const {0},
  }) {
    if (data == null) {
      throw const BiliFailure(BiliFailureKind.notFound, message: 'empty data');
    }
    final code = data['code'];
    if (code is! int || !okCodes.contains(code)) {
      final codeValue = code is num ? code.toInt() : null;
      final message = data['message']?.toString();
      final kind = codeValue == -101 || codeValue == -400
          ? BiliFailureKind.unauthorized
          : BiliFailureKind.bizError;
      throw BiliFailure(kind, code: codeValue, message: message);
    }
    return data;
  }

  BiliFailure _mapDioException(DioException e) {
    if (e.type == DioExceptionType.cancel) {
      // 取消不是失败，调用方应通过 CancelToken 感知。
      return const BiliFailure(BiliFailureKind.unknown, message: 'cancelled');
    }
    final statusCode = e.response?.statusCode;
    if (statusCode == 401 || statusCode == 403) {
      return const BiliFailure(
        BiliFailureKind.unauthorized,
        message: 'http auth rejected',
      );
    }
    if (statusCode == 404) {
      return const BiliFailure(BiliFailureKind.notFound, message: 'http 404');
    }
    return BiliFailure(BiliFailureKind.network, message: e.message);
  }
}
