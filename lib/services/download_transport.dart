import 'package:dio/dio.dart';

/// 单次文件下载的传输结果。
class DownloadTransferResult {
  /// 写入文件的累计字节数（含续传部分）。
  final int receivedBytes;

  /// 已知的总字节数；服务器不提供时为 0。
  final int totalBytes;

  const DownloadTransferResult({
    required this.receivedBytes,
    required this.totalBytes,
  });
}

/// 单文件的 HTTP 下载传输层。
///
/// 负责 Range 续传、取消与进度回调，不涉及任务状态管理。
/// 独立成模块以便用本地 HTTP Server 做集成测试。
class DownloadTransport {
  DownloadTransport({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  /// 下载 [url] 到 [savePath]。
  ///
  /// [existingBytes] > 0 时发送 `Range: bytes=existingBytes-` 并追加写入，
  /// 实现断点续传。若服务器不支持 Range（返回 200 而非 206），抛异常，
  /// 由调用方决定从头重试或标记失败。
  ///
  /// 失败时不删除已有部分文件（deleteOnError: false），保留 `.part` 供重试。
  Future<DownloadTransferResult> download({
    required String url,
    required String savePath,
    int existingBytes = 0,
    Map<String, String> headers = const {},
    CancelToken? cancelToken,
    void Function(int received, int total)? onProgress,
  }) async {
    final options = Options(
      headers: {
        ...headers,
        if (existingBytes > 0) 'Range': 'bytes=$existingBytes-',
      },
    );

    var received = existingBytes;
    var knownTotal = 0;

    final response = await _dio.download(
      url,
      savePath,
      options: options,
      cancelToken: cancelToken,
      fileAccessMode: existingBytes > 0
          ? FileAccessMode.append
          : FileAccessMode.write,
      deleteOnError: false,
      onReceiveProgress: (count, total) {
        received = existingBytes + count;
        if (total != -1) {
          knownTotal = existingBytes + total;
        }
        onProgress?.call(received, knownTotal);
      },
    );

    final statusCode = response.statusCode ?? 0;
    if (existingBytes > 0 && statusCode != 206) {
      throw DioException(
        requestOptions: response.requestOptions,
        type: DioExceptionType.badResponse,
        error: 'Server ignored Range request (status $statusCode)',
      );
    }

    return DownloadTransferResult(
      receivedBytes: received,
      totalBytes: knownTotal,
    );
  }

  /// 校验 [cancelToken] 是否因取消而失败。
  static bool isCancelled(Object error) =>
      error is DioException && CancelToken.isCancel(error);
}
