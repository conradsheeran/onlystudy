import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart'; // Import for debugPrint
import '../models/download_task.dart';
import '../models/bili_models.dart';
import 'bili_api_service.dart';

class DownloadService {
  static final DownloadService _instance = DownloadService._internal();
  factory DownloadService() => _instance;
  DownloadService._internal();

  Database? _db;
  final Dio _dio = Dio();
  final StreamController<List<DownloadTask>> _tasksController = StreamController.broadcast();
  List<DownloadTask> _memoryTasks = [];

  Stream<List<DownloadTask>> get tasksStream => _tasksController.stream;
  List<DownloadTask> get currentTasks => List.unmodifiable(_memoryTasks);

  Future<void> init() async {
    if (_db != null) return;
    
    try {
      final databasesPath = await getDatabasesPath();
      final path = join(databasesPath, 'downloads.db');

      _db = await openDatabase(
        path,
        version: 1,
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
              PRIMARY KEY (bvid, cid)
            )
          ''');
        },
      );
      await _loadTasks();
    } catch (e) {
      debugPrint('Database init failed: $e');
    }
  }

  Future<void> _loadTasks() async {
    if (_db == null) return;
    final List<Map<String, dynamic>> maps = await _db!.query('tasks', orderBy: 'createTime DESC');
    _memoryTasks = List.generate(maps.length, (i) => DownloadTask.fromMap(maps[i]));
    _tasksController.add(_memoryTasks);
  }

  Future<void> startDownload(Video video, int cid, int aid, {int qn = 64}) async {
    // 1. Check if task exists
    if (_memoryTasks.any((t) => t.bvid == video.bvid && t.cid == cid)) {
        return; // Already exists
    }

    // 2. Create pending task
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
    
    await _insertOrUpdateTask(newTask);
    
    // 3. Start process
    _executeDownload(newTask, video.bvid, cid, qn);
  }

  Future<void> _executeDownload(DownloadTask task, String bvid, int cid, int qn) async {
    try {
        final playInfo = await BiliApiService().getVideoPlayUrl(bvid, cid, qn: qn);
        
        if (playInfo.url.isEmpty) {
             throw Exception('无法获取有效的MP4下载地址');
        }

        final docDir = await getApplicationDocumentsDirectory();
        // Create a dedicated directory
        final downloadDir = Directory(join(docDir.path, 'downloads'));
        if (!await downloadDir.exists()) {
          await downloadDir.create(recursive: true);
        }

        final fileName = '${bvid}_$cid.mp4';
        final savePath = join(downloadDir.path, fileName);
        
        // Update to Running
        final runningTask = task.copyWith(
            filePath: savePath, 
            status: DownloadStatus.running
        );
        await _insertOrUpdateTask(runningTask);

        // Prepare headers
        final options = Options(headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Referer': 'https://www.bilibili.com/',
        });

        await _dio.download(
            playInfo.url, 
            savePath,
            options: options,
            onReceiveProgress: (received, total) {
                if (total != -1) {
                    final progress = received / total;
                    _updateProgress(bvid, cid, progress);
                }
            },
        );
        
        // Completed
        await _updateStatus(bvid, cid, DownloadStatus.completed);

    } catch (e) {
        debugPrint('Download error: $e');
        await _updateStatus(bvid, cid, DownloadStatus.failed);
    }
  }

  Future<void> _insertOrUpdateTask(DownloadTask task) async {
    if (_db == null) await init();
    
    final index = _memoryTasks.indexWhere((t) => t.bvid == task.bvid && t.cid == task.cid);
    if (index >= 0) {
        _memoryTasks[index] = task;
    } else {
        _memoryTasks.insert(0, task);
    }
    _tasksController.add(List.from(_memoryTasks)); // Emit new list

    // DB Operation
    await _db!.insert(
        'tasks', 
        task.toMap(), 
        conflictAlgorithm: ConflictAlgorithm.replace
    );
  }

  void _updateProgress(String bvid, int cid, double progress) {
     final index = _memoryTasks.indexWhere((t) => t.bvid == bvid && t.cid == cid);
     if (index >= 0) {
         final task = _memoryTasks[index];
         // Throttle: only update if changed significantly
         if ((task.progress - progress).abs() > 0.01) {
             final newTask = task.copyWith(progress: progress);
             _memoryTasks[index] = newTask;
             _tasksController.add(List.from(_memoryTasks));
         }
     }
  }

  Future<void> _updateStatus(String bvid, int cid, DownloadStatus status) async {
     final index = _memoryTasks.indexWhere((t) => t.bvid == bvid && t.cid == cid);
     if (index >= 0) {
         final newTask = _memoryTasks[index].copyWith(
           status: status, 
           progress: status == DownloadStatus.completed ? 1.0 : null
         );
         await _insertOrUpdateTask(newTask);
     }
  }

  Future<void> deleteTask(String bvid, int cid) async {
    final index = _memoryTasks.indexWhere((t) => t.bvid == bvid && t.cid == cid);
    if (index == -1) return;

    final task = _memoryTasks[index];
    
    // 1. Delete file
    if (task.filePath != null) {
      final file = File(task.filePath!);
      if (await file.exists()) {
        await file.delete();
      }
    }

    // 2. Remove from DB
    if (_db != null) {
      await _db!.delete(
        'tasks',
        where: 'bvid = ? AND cid = ?',
        whereArgs: [bvid, cid],
      );
    }

    // 3. Remove from memory
    _memoryTasks.removeAt(index);
    _tasksController.add(List.from(_memoryTasks));
  }
  
  // Clean up
  void dispose() {
    _tasksController.close();
    _db?.close();
  }
}