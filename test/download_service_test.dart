import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onlystudy/models/bili_models.dart';
import 'package:onlystudy/models/download_task.dart';
import 'package:onlystudy/services/download_service.dart';
import 'package:onlystudy/services/download_transport.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// DownloadService 的队列/取消/恢复行为测试。
///
/// 通过注入 fake transport 与 fake 播放地址/保存目录，避免真实网络
/// 和真实数据库（OPT-001 验证建议：取消后文件不增长、失败可重试、
/// 并发上限）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory tempDir;
  late DownloadService service;

  final video = Video(
    bvid: 'BV1queue',
    title: '队列测试',
    cover: '',
    duration: 100,
    upper: BiliUpper(mid: 1, name: 'UP'),
    view: 0,
    danmaku: 0,
    pubTimestamp: 0,
  );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dl_service_test');
    service = DownloadService();
    service.resetForTest();
    service.downloadDirProvider = () async => tempDir;
    service.dbPathProvider = () async => tempDir.path;
  });
  tearDown(() async {
    // 先取消所有进行中任务并等待它们收尾，避免异步写 db
    for (final t in service.currentTasks) {
      if (t.status == DownloadStatus.running ||
          t.status == DownloadStatus.pending) {
        service.pauseTask(t.bvid, t.cid);
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
    service.resetForTest();
    await tempDir.delete(recursive: true);
  });

  /// 构造一个记录调用并受控完成的 fake transport。
  FakeTransport makeFakeTransport() {
    return FakeTransport();
  }

  test('多任务严格遵守并发上限（maxConcurrent=2）', () async {
    final transport = makeFakeTransport();
    service.transportForTest = transport;
    service.playUrlProvider = (bvid, cid, qn) async =>
        'https://example.com/video.mp4';

    // 添加 4 个任务
    for (var i = 0; i < 4; i++) {
      await service.startDownload(
        video.copyWithTest(bvid: 'BV$i'),
        100 + i,
        1000 + i,
      );
    }

    // 等待前两个传输开始
    await transport.waitForDownloads(2, timeout: const Duration(seconds: 2));

    // 队列应最多 2 个同时进行
    expect(
      transport.activeCount,
      lessThanOrEqualTo(DownloadService.maxConcurrent),
    );
    expect(transport.startedUrls.length, 2);

    // 完成前两个，队列继续推进
    transport.completeAll();
    await transport.waitForDownloads(4, timeout: const Duration(seconds: 3));
    expect(transport.startedUrls.length, 4);
    expect(
      transport.activeCount,
      lessThanOrEqualTo(DownloadService.maxConcurrent),
    );
  });

  test('失败任务可以 retry 并成功', () async {
    final transport = makeFakeTransport()..autoComplete = true;
    service.transportForTest = transport;
    service.playUrlProvider = (bvid, cid, qn) async {
      if (bvid == 'BVfail') {
        throw Exception('network down');
      }
      return 'https://example.com/video.mp4';
    };

    await service.startDownload(video.copyWithTest(bvid: 'BVfail'), 1, 1000);

    // 等待失败
    await _waitForStatus(service, 'BVfail', 1, DownloadStatus.failed);
    expect(
      service.currentTasks.any(
        (t) => t.bvid == 'BVfail' && t.status == DownloadStatus.failed,
      ),
      isTrue,
    );

    // 修复网络并重试
    service.playUrlProvider = (bvid, cid, qn) async =>
        'https://example.com/ok.mp4';
    await service.retryTask('BVfail', 1);
    await _waitForStatus(service, 'BVfail', 1, DownloadStatus.completed);
  });

  test('删除进行中的任务取消请求且不产生孤儿文件', () async {
    final transport = makeFakeTransport();
    service.transportForTest = transport;
    service.playUrlProvider = (bvid, cid, qn) async =>
        'https://example.com/video.mp4';

    await service.startDownload(video, 1, 1000);
    await transport.waitForDownloads(1, timeout: const Duration(seconds: 2));

    await service.deleteTask(video.bvid, 1);

    // 传输被取消
    expect(transport.cancelled, isTrue);
    // 无残留下载文件（.part 或 .mp4；downloads.db 是测试数据库不算）
    final files = tempDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.mp4') || f.path.endsWith('.part'))
        .toList();
    expect(files, isEmpty);
  });

  test('进程重启后遗留 running 任务恢复为 paused（不假跑）', () async {
    final transport = makeFakeTransport();
    service.transportForTest = transport;
    service.playUrlProvider = (bvid, cid, qn) async =>
        'https://example.com/video.mp4';

    // 启动下载并让它保持在 running 状态（传输挂起未完成）
    await service.startDownload(video, 1, 1000);
    await transport.waitForDownloads(1, timeout: const Duration(seconds: 2));
    expect(
      service.currentTasks.any(
        (t) => t.bvid == video.bvid && t.status == DownloadStatus.running,
      ),
      isTrue,
    );

    // 模拟进程崩溃：同目录重建服务并重新 init
    final dbPath = await service.dbPathProvider!();
    service.resetForTest();
    service.dbPathProvider = () async => dbPath;

    await service.init();

    // running 任务被恢复为 paused，不会被自动重启
    final restored = service.currentTasks
        .where((t) => t.bvid == video.bvid)
        .firstOrNull;
    expect(restored, isNotNull);
    expect(restored!.status, DownloadStatus.paused);
    expect(
      service.currentTasks.any((t) => t.status == DownloadStatus.running),
      isFalse,
    );
    expect(transport.startedUrls, hasLength(1), reason: '重启后不得自动重新下载');
  });
}

class FakeTransport extends DownloadTransport {
  final List<String> startedUrls = [];
  final List<Completer<void>> _completers = [];

  bool cancelled = false;

  /// 下载开始后自动完成（用于 retry/恢复等无需手动控制的场景）。
  bool autoComplete = false;
  int get activeCount => _completers.where((c) => !c.isCompleted).length;

  @override
  Future<DownloadTransferResult> download({
    required String url,
    required String savePath,
    int existingBytes = 0,
    Map<String, String> headers = const {},
    CancelToken? cancelToken,
    void Function(int received, int total)? onProgress,
  }) async {
    startedUrls.add(url);
    // 模拟真实写入：创建 .part 文件（供后续 rename）
    final file = File(savePath);
    if (!await file.exists()) {
      await file.writeAsBytes(List.filled(2048, 1));
    }

    final completer = Completer<void>();
    _completers.add(completer);

    // 监听取消
    cancelToken?.whenCancel.then((_) {
      cancelled = true;
      if (!completer.isCompleted) {
        completer.completeError(cancelToken.cancelError!);
      }
    });
    if (autoComplete) {
      completer.complete();
    }
    await completer.future;
    onProgress?.call(1024, 2048);
    return const DownloadTransferResult(receivedBytes: 2048, totalBytes: 2048);
  }

  /// 完成所有尚未完成的下载（除非 autoComplete 已自动完成）。
  void completeAll() {
    for (final c in _completers) {
      if (!c.isCompleted) c.complete();
    }
  }

  Future<void> waitForDownloads(int count, {required Duration timeout}) async {
    final deadline = DateTime.now().add(timeout);
    while (startedUrls.length < count && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(
      startedUrls.length,
      greaterThanOrEqualTo(count),
      reason: '等待 $count 个下载开始超时',
    );
  }
}

Future<void> _waitForStatus(
  DownloadService service,
  String bvid,
  int cid,
  DownloadStatus status,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (DateTime.now().isBefore(deadline)) {
    final task = service.currentTasks
        .where((t) => t.bvid == bvid && t.cid == cid)
        .firstOrNull;
    if (task != null && task.status == status) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('任务 $bvid:$cid 未在超时前到达状态 $status');
}

extension on Video {
  Video copyWithTest({String? bvid}) => Video(
    bvid: bvid ?? this.bvid,
    title: title,
    cover: cover,
    duration: duration,
    upper: upper,
    view: view,
    danmaku: danmaku,
    pubTimestamp: pubTimestamp,
  );
}
