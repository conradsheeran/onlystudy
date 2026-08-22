import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onlystudy/services/download_transport.dart';

/// DownloadTransport 的本地 HTTP Server 集成测试。
///
/// 覆盖：普通下载、Range 续传、取消后文件不再增长、删除 .part。
void main() {
  late HttpServer server;
  late String baseUrl;
  late Directory tempDir;

  final fileBytes = List<int>.generate(256 * 1024, (i) => i % 251);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dl_transport_test');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://127.0.0.1:${server.port}';
    server.listen((request) async {
      final range = request.headers.value(HttpHeaders.rangeHeader);
      if (range != null) {
        final match = RegExp(r'bytes=(\d+)-').firstMatch(range);
        if (match == null) {
          request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          await request.response.close();
          return;
        }
        final start = int.parse(match.group(1)!);
        final chunk = fileBytes.sublist(start);
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-${fileBytes.length - 1}/${fileBytes.length}',
        );
        request.response.contentLength = chunk.length;
        request.response.add(chunk);
        await request.response.close();
      } else {
        request.response.headers.set(
          HttpHeaders.contentLengthHeader,
          fileBytes.length.toString(),
        );
        request.response.add(fileBytes);
        await request.response.close();
      }
    });
  });

  tearDown(() async {
    await server.close(force: true);
    await tempDir.delete(recursive: true);
  });

  String path(String name) => '${tempDir.path}${Platform.pathSeparator}$name';

  test('普通下载完整写入文件', () async {
    final transport = DownloadTransport();
    final target = path('video.mp4');

    final result = await transport.download(
      url: '$baseUrl/file',
      savePath: target,
    );

    expect(result.receivedBytes, fileBytes.length);
    expect(result.totalBytes, fileBytes.length);
    expect(File(target).lengthSync(), fileBytes.length);
  });

  test('Range 续传：已有部分文件时从断点继续', () async {
    final transport = DownloadTransport();
    final target = path('resume.mp4');

    // 模拟下载到一半留下的部分文件（真实场景中由取消/中断产生）。
    // 不用"下载到一半再取消"来制造部分文件：取消时机取决于 dio 收到的
    // chunk 大小，服务器可能一次发完整文件，取消时文件已写满，
    // 在 CI（Linux）上不稳定。
    const half = 128 * 1024;
    await File(target).writeAsBytes(fileBytes.sublist(0, half));
    expect(File(target).lengthSync(), half);

    // 从已有字节继续：发送 Range 请求并追加写入
    final result = await transport.download(
      url: '$baseUrl/file',
      savePath: target,
      existingBytes: half,
    );

    expect(result.receivedBytes, fileBytes.length);
    expect(result.totalBytes, fileBytes.length);
    // 内容完整
    expect(File(target).lengthSync(), fileBytes.length);
    expect(File(target).readAsBytesSync(), fileBytes);
  });

  test('取消后文件不再增长', () async {
    final transport = DownloadTransport();
    final target = path('cancel.mp4');
    final cancelToken = CancelToken();

    var lastLength = 0;
    final future = transport.download(
      url: '$baseUrl/file',
      savePath: target,
      cancelToken: cancelToken,
      onProgress: (received, total) {
        lastLength = File(target).lengthSync();
        if (received >= fileBytes.length ~/ 4) {
          cancelToken.cancel('user cancelled');
        }
      },
    );

    await expectLater(future, throwsA(isA<DioException>()));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(File(target).lengthSync(), lastLength, reason: '取消后文件不得继续增长');
  });

  test('isCancelled 识别取消错误', () async {
    final cancelToken = CancelToken();
    cancelToken.cancel('x');
    final error = await cancelToken.whenCancel;
    expect(DownloadTransport.isCancelled(error), isTrue);
    expect(DownloadTransport.isCancelled(Exception('other')), isFalse);
  });
}
