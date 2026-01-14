import 'package:path/path.dart';
import 'dart:convert';
import '../models/bili_models.dart';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Database? _database;

  /// 获取数据库实例
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// 初始化数据库表结构
  Future<Database> _initDatabase() async {
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    String path = join(await getDatabasesPath(), 'onlystudy.db');
    return await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE videos(
            bvid TEXT PRIMARY KEY,
            title TEXT,
            cover TEXT,
            upper_name TEXT,
            folder_id INTEGER,
            season_id INTEGER,
            json_data TEXT,
            timestamp INTEGER
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE videos ADD COLUMN season_id INTEGER');
        }
      },
    );
  }

  /// 缓存视频信息到本地数据库
  Future<void> insertVideos(List<Video> videos,
      {int? folderId, int? seasonId}) async {
    final db = await database;
    final batch = db.batch();
    final now = DateTime.now().millisecondsSinceEpoch;

    for (var video in videos) {
      batch.insert(
        'videos',
        {
          'bvid': video.bvid,
          'title': video.title,
          'cover': video.cover,
          'upper_name': video.upper.name,
          'folder_id': folderId,
          'season_id': seasonId,
          'json_data': jsonEncode({
            'bvid': video.bvid,
            'title': video.title,
            'cover': video.cover,
            'duration': video.duration,
            'upper': {'mid': video.upper.mid, 'name': video.upper.name},
            'cnt_info': {'play': video.view, 'danmaku': video.danmaku},
            'pub_time': video.pubTimestamp,
          }),
          'timestamp': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// 本地搜索视频 (支持按可见收藏夹/合集过滤)
  Future<List<Video>> searchVideos(String keyword,
      {List<int>? visibleFolderIds, List<int>? visibleSeasonIds}) async {
    final db = await database;

    String whereClause = 'title LIKE ?';
    List<dynamic> whereArgs = ['%$keyword%'];
    List<String> subConditions = [];
    if (visibleFolderIds != null && visibleFolderIds.isNotEmpty) {
      subConditions.add('folder_id IN (${visibleFolderIds.join(',')})');
    }
    if (visibleSeasonIds != null && visibleSeasonIds.isNotEmpty) {
      subConditions.add('season_id IN (${visibleSeasonIds.join(',')})');
    }

    if (subConditions.isNotEmpty) {
      whereClause += ' AND (${subConditions.join(' OR ')})';
    }

    final List<Map<String, dynamic>> maps = await db.query(
      'videos',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'timestamp DESC',
    );

    return List.generate(maps.length, (i) {
      final jsonMap = jsonDecode(maps[i]['json_data']);
      return Video.fromJson(jsonMap);
    });
  }

  /// 清理指定收藏夹的缓存数据
  Future<void> clearFolderCache(int folderId) async {
    final db = await database;
    await db.delete('videos', where: 'folder_id = ?', whereArgs: [folderId]);
  }

  /// 清理指定合集的缓存数据
  Future<void> clearSeasonCache(int seasonId) async {
    final db = await database;
    await db.delete('videos', where: 'season_id = ?', whereArgs: [seasonId]);
  }

  /// 清空所有视频缓存数据
  Future<void> clearAllCache() async {
    final db = await database;
    await db.delete('videos');
  }
}
