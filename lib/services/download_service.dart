import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/bili_models.dart';
import '../models/download_task.dart';
import 'playback_gateway.dart';
import 'download_transport.dart';

/// 下载协调器：管理队列、取消、恢复、持久化和原子完成。
///
/// 设计目标（OPT-001）：
/// - 有界并发（默认 2 个同时下载）
/// - 每个任务一个 CancelToken，删除/取消真正停止网络请求
/// - 启动时把遗留的 running 状态恢复为 paused（进程崩溃后不假跑）
/// - `.part` 临时文件 + 成功后原子重命名，杜绝孤儿/半成品文件
/// - 持久化 downloadedBytes/totalBytes，支持断点续传
/// - 失败任务可以 retry
class DownloadService {
  static final DownloadService _instance = DownloadService._internal();
  factory DownloadService() => _instance;
  DownloadService._internal();

  /// 并发下载上限。
  static const int maxConcurrent = 2;

  Database? _db;
  DownloadTransport? _transport;

  /// 测试专用：注入传输层。
  @visibleForTesting
  set transportForTest(DownloadTransport transport) => _transport = transport;

  DownloadTransport get _effectiveTransport =>
      _transport ??= DownloadTransport();

  /// 获取播放地址；默认走 PlaybackGateway，测试可注入。
  Future<String> Function(String bvid, int cid, int qn)? playUrlProvider;

  /// 下载保存目录；默认走系统文档目录，测试可注入。
  Future<Directory> Function()? downloadDirProvider;

  final StreamController<List<DownloadTask>> _tasksController =
      StreamController.broadcast();
  List<DownloadTask> _memoryTasks = [];

  /// 每个任务（bvid:cid）对应的取消令牌和运行 Future。
  final Map<String, CancelToken> _cancelTokens = {};
  final Map<String, Future<void>> _runningFutures = {};

  /// 等待队列：等待中的任务 key 列表（按创建时间顺序）。
  final List<String> _queue = [];
  int _activeCount = 0;

  Stream<List<DownloadTask>> get tasksStream => _tasksController.stream;
  List<DownloadTask> get currentTasks => List.unmodifiable(_memoryTasks);

  /// 测试专用：覆盖数据库目录。
  Future<String> Function()? dbPathProvider;

  Future<String> _resolveDbPath() async {
    if (dbPathProvider != null) return dbPathProvider!();
    return getDatabasesPath();
  }

  static String _taskKey(String bvid, int cid) => '$bvid:$cid';

  /// 初始化下载服务和数据库；把遗留 running 状态恢复为 paused。
  Future<void> init() async {
    if (_db != null) return;
    _transport ??= DownloadTransport();

    try {
      final dbPath = await _resolveDbPath();
      final path = join(dbPath, 'downloads.db');

      _db = await openDatabase(
        path,
        version: 2,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE tasks (
              bvid TEXT,
              cid INTEGER,
              aid INTEGER,
              title TEXT,
              cover TEXT,
              quality INTEGER,
              filePath TEXT,
              progress REAL,
              status INTEGER,
              createTime INTEGER,
              downloadedBytes INTEGER DEFAULT 0,
              totalBytes INTEGER DEFAULT 0,
              PRIMARY KEY (bvid, cid)
            )
          ''');
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute(
              'ALTER TABLE tasks ADD COLUMN downloadedBytes INTEGER DEFAULT 0',
            );
            await db.execute(
              'ALTER TABLE tasks ADD COLUMN totalBytes INTEGER DEFAULT 0',
            );
          }
        },
      );
      await _loadTasks();
      await _recoverInterruptedTasks();
    } catch (e) {
      debugPrint('Database init failed: $e');
    }
  }

  /// 从数据库加载历史下载任务。
  Future<void> _loadTasks() async {
    if (_db == null) return;
    final maps = await _db!.query('tasks', orderBy: 'createTime DESC');
    _memoryTasks = List.generate(
      maps.length,
      (i) => DownloadTask.fromMap(maps[i]),
    );
    _tasksController.add(_memoryTasks);
  }

  /// 启动时把遗留 running 任务恢复为 paused（进程崩溃后不假跑）。
  Future<void> _recoverInterruptedTasks() async {
    final interrupted = _memoryTasks
        .where((t) => t.status == DownloadStatus.running)
        .toList();
    if (interrupted.isEmpty) return;

    for (final task in interrupted) {
      final paused = task.copyWith(status: DownloadStatus.paused);
      await _persistTask(paused);
    }
    _memoryTasks = List.generate(
      _memoryTasks.length,
      (i) => _memoryTasks[i].status == DownloadStatus.running
          ? _memoryTasks[i].copyWith(status: DownloadStatus.paused)
          : _memoryTasks[i],
    );
    _tasksController.add(List.from(_memoryTasks));
  }

  /// 开始一个新的视频下载任务（幂等：已存在则直接返回）。
  Future<void> startDownload(
    Video video,
    int cid,
    int aid, {
    int qn = 64,
  }) async {
    if (_db == null) await init();
    if (_memoryTasks.any((t) => t.bvid == video.bvid && t.cid == cid)) {
      return;
    }

    final newTask = DownloadTask(
      bvid: video.bvid,
      cid: cid,
      aid: aid,
      title: video.title,
      cover: video.cover,
      quality: qn,
      createTime: DateTime.now().millisecondsSinceEpoch,
      status: DownloadStatus.pending,
    );

    await _persistTask(newTask);
    _enqueue(newTask);
  }

  void _enqueue(DownloadTask task) {
    final key = _taskKey(task.bvid, task.cid);
    if (_runningFutures.containsKey(key)) return;

    _queue.add(key);
    _pump();
  }

  /// 从队列取出下一个任务执行，遵守并发上限。
  void _pump() {
    while (_activeCount < maxConcurrent && _queue.isNotEmpty) {
      final key = _queue.removeAt(0);
      final task = _findTask(key);
      if (task == null) continue;

      _activeCount++;
      final future = _executeDownload(task);
      _runningFutures[key] = future;
      future.whenComplete(() {
        _activeCount--;
        _runningFutures.remove(key);
        _cancelTokens.remove(key);
        _pump();
      });
    }
  }

  /// 执行下载逻辑：获取地址、下载到 `.part`、原子完成。
  Future<void> _executeDownload(DownloadTask task) async {
    final key = _taskKey(task.bvid, task.cid);
    final cancelToken = CancelToken();
    _cancelTokens[key] = cancelToken;

    try {
      final playUrlProvider =
          this.playUrlProvider ??
          (bvid, cid, qn) async =>
              (await PlaybackGateway().getVideoPlayUrl(bvid, cid, qn: qn)).url;
      final url = await playUrlProvider(task.bvid, task.cid, task.quality);
      if (url.isEmpty) {
        throw Exception('No playable URL');
      }

      final downloadDirProvider =
          this.downloadDirProvider ??
          () async {
            final docDir = await getApplicationDocumentsDirectory();
            return Directory(join(docDir.path, 'downloads'));
          };
      final downloadDir = await downloadDirProvider();
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }

      final fileName = '${task.bvid}_${task.cid}.mp4';
      final finalPath = join(downloadDir.path, fileName);
      final partPath = '$finalPath.part';

      // 续传：从已有 .part 文件的字节数继续
      final partFile = File(partPath);
      var existingBytes = 0;
      if (await partFile.exists()) {
        existingBytes = await partFile.length();
      }

      await _updateTask(
        key,
        (t) => t.copyWith(
          filePath: finalPath,
          status: DownloadStatus.running,
          progress: 0.0,
        ),
      );

      final headers = {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Referer': 'https://www.bilibili.com/',
      };

      final result = await _effectiveTransport.download(
        url: url,
        savePath: partPath,
        existingBytes: existingBytes,
        headers: headers,
        cancelToken: cancelToken,
        onProgress: (received, total) {
          final progress = total > 0 ? received / total : 0.0;
          final live = _findTask(key);
          if (live != null &&
              (live.downloadedBytes != received ||
                  live.totalBytes != total ||
                  (live.progress - progress).abs() > 0.01)) {
            _updateTask(
              key,
              (t) => t.copyWith(
                progress: progress,
                downloadedBytes: received,
                totalBytes: total,
              ),
              persist: true,
            );
          }
        },
      );

      // 成功后原子重命名
      final finalFile = File(finalPath);
      if (await finalFile.exists()) {
        await finalFile.delete();
      }
      await partFile.rename(finalPath);

      await _updateTask(
        key,
        (t) => t.copyWith(
          status: DownloadStatus.completed,
          progress: 1.0,
          downloadedBytes: result.receivedBytes,
          totalBytes: result.totalBytes,
        ),
        persist: true,
      );
    } catch (e) {
      if (DownloadTransport.isCancelled(e)) {
        // 取消：不覆盖状态，交由 pause/delete 处理
        debugPrint('Download cancelled: $key');
      } else {
        debugPrint('Download error: $e');
        await _updateTask(
          key,
          (t) => t.copyWith(status: DownloadStatus.failed),
          persist: true,
        );
      }
    }
  }

  /// 暂停任务：取消网络请求，保留 `.part` 文件。
  Future<void> pauseTask(String bvid, int cid) async {
    final key = _taskKey(bvid, cid);
    final task = _findTask(key);
    if (task == null) return;

    _cancelTokens[key]?.cancel();
    _queue.remove(key);
    await _updateTask(
      key,
      (t) => t.copyWith(status: DownloadStatus.paused),
      persist: true,
    );
  }

  /// 恢复暂停/失败任务。
  Future<void> resumeTask(String bvid, int cid) async {
    final key = _taskKey(bvid, cid);
    final task = _findTask(key);
    if (task == null) return;
    if (task.status != DownloadStatus.paused &&
        task.status != DownloadStatus.failed) {
      return;
    }

    await _updateTask(
      key,
      (t) => t.copyWith(status: DownloadStatus.pending),
      persist: true,
    );
    _enqueue(task.copyWith(status: DownloadStatus.pending));
  }

  /// 重试失败任务（等价于 resumeTask，语义更明确）。
  Future<void> retryTask(String bvid, int cid) => resumeTask(bvid, cid);

  /// 删除任务：取消网络请求并删除文件与 `.part`。
  Future<void> deleteTask(String bvid, int cid) async {
    final key = _taskKey(bvid, cid);
    final index = _memoryTasks.indexWhere(
      (t) => t.bvid == bvid && t.cid == cid,
    );
    if (index == -1) return;

    final task = _memoryTasks[index];

    _cancelTokens[key]?.cancel();
    _queue.remove(key);

    if (task.filePath != null) {
      final file = File(task.filePath!);
      if (await file.exists()) {
        await file.delete();
      }
      final part = File('${task.filePath!}.part');
      if (await part.exists()) {
        await part.delete();
      }
    }

    if (_db != null) {
      await _db!.delete(
        'tasks',
        where: 'bvid = ? AND cid = ?',
        whereArgs: [bvid, cid],
      );
    }

    _memoryTasks.removeAt(index);
    _tasksController.add(List.from(_memoryTasks));
  }

  DownloadTask? _findTask(String key) {
    final parts = key.split(':');
    if (parts.length != 2) return null;
    final bvid = parts[0];
    final cid = int.tryParse(parts[1]) ?? 0;
    for (final t in _memoryTasks) {
      if (t.bvid == bvid && t.cid == cid) return t;
    }
    return null;
  }

  Future<void> _updateTask(
    String key,
    DownloadTask Function(DownloadTask) transform, {
    bool persist = true,
  }) async {
    final index = _memoryTasks.indexWhere((t) => '${t.bvid}:${t.cid}' == key);
    if (index == -1) return;

    final updated = transform(_memoryTasks[index]);
    _memoryTasks[index] = updated;
    _tasksController.add(List.from(_memoryTasks));
    if (persist && _db != null) {
      await _db!.insert(
        'tasks',
        updated.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<void> _persistTask(DownloadTask task) async {
    final index = _memoryTasks.indexWhere(
      (t) => t.bvid == task.bvid && t.cid == task.cid,
    );
    if (index >= 0) {
      _memoryTasks[index] = task;
    } else {
      _memoryTasks.insert(0, task);
    }
    _tasksController.add(List.from(_memoryTasks));
    if (_db != null) {
      await _db!.insert(
        'tasks',
        task.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  /// 测试专用：重置单例内部状态。
  @visibleForTesting
  void resetForTest() {
    _db?.close();
    _cancelTokens.clear();
    _runningFutures.clear();
    _queue.clear();
    _activeCount = 0;
    _memoryTasks = [];
    _db = null;
    playUrlProvider = null;
    downloadDirProvider = null;
    dbPathProvider = null;
  }

  void dispose() {
    _tasksController.close();
    _db?.close();
  }
}
