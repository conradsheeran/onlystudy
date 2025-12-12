import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:convert';
import '../models/bili_models.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'onlystudy.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE videos(
            bvid TEXT PRIMARY KEY,
            title TEXT,
            cover TEXT,
            upper_name TEXT,
            folder_id INTEGER,
            json_data TEXT,
            timestamp INTEGER
          )
        ''');
      },
    );
  }

  Future<void> insertVideos(List<Video> videos, int folderId) async {
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
          'json_data': jsonEncode({
             // We need to reconstruct the JSON structure expected by Video.fromJson
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

  Future<List<Video>> searchVideos(String keyword, {List<int>? visibleFolderIds}) async {
    final db = await database;
    
    String whereClause = 'title LIKE ?';
    List<dynamic> whereArgs = ['%$keyword%'];

    if (visibleFolderIds != null && visibleFolderIds.isNotEmpty) {
      whereClause += ' AND folder_id IN (${visibleFolderIds.join(',')})';
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

  // Clear old cache if needed, or specific folder cache
  Future<void> clearFolderCache(int folderId) async {
    final db = await database;
    await db.delete('videos', where: 'folder_id = ?', whereArgs: [folderId]);
  }

  Future<void> clearAllCache() async {
    final db = await database;
    await db.delete('videos');
  }
}
