import 'package:path/path.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/bili_models.dart';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io';

/// 视频来源类型。
enum VideoSourceType {
  folder,
  season,
  up,
}

extension VideoSourceTypeX on VideoSourceType {
  String get dbValue => name;
  static VideoSourceType fromDb(String value) =>
      VideoSourceType.values.firstWhere((e) => e.name == value);
}

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Database? _database;

  /// 测试专用：注入已打开的数据库。
  @visibleForTesting
  set databaseOverride(Database db) => _database = db;
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
      version: 3,
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
        await db.execute('''
          CREATE TABLE video_sources(
            bvid TEXT NOT NULL,
            source_type TEXT NOT NULL,
            source_id INTEGER NOT NULL,
            synced_at INTEGER NOT NULL,
            PRIMARY KEY (bvid, source_type, source_id)
          )
        ''');
        await db.execute('''
          CREATE INDEX video_sources_by_source
          ON video_sources(source_type, source_id)
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE videos ADD COLUMN season_id INTEGER');
        }
        if (oldVersion < 3) {
          await db.execute('''
            CREATE TABLE video_sources(
              bvid TEXT NOT NULL,
              source_type TEXT NOT NULL,
              source_id INTEGER NOT NULL,
              synced_at INTEGER NOT NULL,
              PRIMARY KEY (bvid, source_type, source_id)
            )
          ''');
          await db.execute('''
            CREATE INDEX video_sources_by_source
            ON video_sources(source_type, source_id)
          ''');
          // 迁移旧数据：把 videos 表的 folder_id/season_id 转为关系
          await db.execute('''
            INSERT OR IGNORE INTO video_sources (bvid, source_type, source_id, synced_at)
            SELECT bvid, 'folder', folder_id, timestamp FROM videos
            WHERE folder_id IS NOT NULL AND folder_id > 0
          ''');
          await db.execute('''
            INSERT OR IGNORE INTO video_sources (bvid, source_type, source_id, synced_at)
            SELECT bvid, 'season', season_id, timestamp FROM videos
            WHERE season_id IS NOT NULL AND season_id > 0
          ''');
        }
      },
    );
  }

  /// 缓存视频信息到本地数据库，并记录来源关系。
  ///
  /// 同一视频可同时属于多个收藏夹/合集/UP 主；关系写入
  /// `video_sources`，不再互相覆盖（OPT-002）。
  Future<void> insertVideos(
    List<Video> videos, {
    int? folderId,
    int? seasonId,
    int? upId,
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();

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

      // 记录来源关系（up 来源与收藏夹/合集可并存）
      if (folderId != null) {
        batch.insert(
          'video_sources',
          {
            'bvid': video.bvid,
            'source_type': VideoSourceType.folder.dbValue,
            'source_id': folderId,
            'synced_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      if (seasonId != null) {
        batch.insert(
          'video_sources',
          {
            'bvid': video.bvid,
            'source_type': VideoSourceType.season.dbValue,
            'source_id': seasonId,
            'synced_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      if (upId != null) {
        batch.insert(
          'video_sources',
          {
            'bvid': video.bvid,
            'source_type': VideoSourceType.up.dbValue,
            'source_id': upId,
            'synced_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    }
    await batch.commit(noResult: true);
  }

  /// 本地搜索视频 (支持按可见收藏夹/合集/UP 过滤)
  ///
  /// 通过 `video_sources` 关联过滤，同一视频属于多个来源时
  /// 任一来源命中都会被返回（OPT-002）。
  Future<List<Video>> searchVideos(
    String keyword, {
    List<int>? visibleFolderIds,
    List<int>? visibleSeasonIds,
    List<int>? visibleUpIds,
  }) async {
    final db = await database;

    String whereClause = 'v.title LIKE ?';
    List<dynamic> whereArgs = ['%$keyword%'];

    if ((visibleFolderIds != null && visibleFolderIds.isNotEmpty) ||
        (visibleSeasonIds != null && visibleSeasonIds.isNotEmpty) ||
        (visibleUpIds != null && visibleUpIds.isNotEmpty)) {
      final sourceConditions = <String>[];
      if (visibleFolderIds != null && visibleFolderIds.isNotEmpty) {
        sourceConditions.add(
            "(vs.source_type = 'folder' AND vs.source_id IN (${visibleFolderIds.join(',')}))");
      }
      if (visibleSeasonIds != null && visibleSeasonIds.isNotEmpty) {
        sourceConditions.add(
            "(vs.source_type = 'season' AND vs.source_id IN (${visibleSeasonIds.join(',')}))");
      }
      if (visibleUpIds != null && visibleUpIds.isNotEmpty) {
        sourceConditions.add(
            "(vs.source_type = 'up' AND vs.source_id IN (${visibleUpIds.join(',')}))");
      }
      whereClause += ' AND EXISTS (SELECT 1 FROM video_sources vs '
          'WHERE vs.bvid = v.bvid AND (${sourceConditions.join(' OR ')}))';
    }

    final List<Map<String, dynamic>> maps = await db.rawQuery(
      '''
      SELECT DISTINCT v.* FROM videos v
      WHERE $whereClause
      ORDER BY v.timestamp DESC
      ''',
      whereArgs,
    );

    return List.generate(maps.length, (i) {
      final jsonMap = jsonDecode(maps[i]['json_data']);
      return Video.fromJson(jsonMap);
    });
  }

  /// 清理指定收藏夹的缓存数据：只删除该来源的关系，
  /// 无任何来源的视频再删除主体记录。
  Future<void> clearFolderCache(int folderId) async {
    final db = await database;
    await db.delete('video_sources',
        where: 'source_type = ? AND source_id = ?',
        whereArgs: ['folder', folderId]);
    await _deleteOrphanVideos(db);
  }

  /// 清理指定合集的缓存数据。
  Future<void> clearSeasonCache(int seasonId) async {
    final db = await database;
    await db.delete('video_sources',
        where: 'source_type = ? AND source_id = ?',
        whereArgs: ['season', seasonId]);
    await _deleteOrphanVideos(db);
  }

  /// 清理指定 UP 主的缓存数据。
  Future<void> clearUpCache(int upId) async {
    final db = await database;
    await db.delete('video_sources',
        where: 'source_type = ? AND source_id = ?',
        whereArgs: ['up', upId]);
    await _deleteOrphanVideos(db);
  }

  /// 删除不再属于任何来源的视频主体记录。
  Future<void> _deleteOrphanVideos(Database db) async {
    await db.rawDelete('''
      DELETE FROM videos WHERE bvid NOT IN (
        SELECT DISTINCT bvid FROM video_sources
      )
    ''');
  }

  /// 清空所有视频缓存数据
  Future<void> clearAllCache() async {
    final db = await database;
    await db.delete('video_sources');
    await db.delete('videos');
  }
}
