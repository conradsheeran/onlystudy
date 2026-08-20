import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onlystudy/models/bili_models.dart';
import 'package:onlystudy/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// OPT-002 数据库 v3 测试：
/// - 同一视频多来源归属不被覆盖
/// - UP 来源可单独筛选
/// - 清理只删关系，无来源视频再删主体
/// - v2→v3 迁移保留现有数据
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  Future<Database> openV3Db() async {
    return databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
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
      ),
    );
  }

  Video makeVideo(String bvid, String title) => Video(
    bvid: bvid,
    title: title,
    cover: 'https://example.com/$bvid.jpg',
    duration: 60,
    upper: BiliUpper(mid: 1, name: 'UP1'),
    view: 100,
    danmaku: 5,
    pubTimestamp: 1700000000,
  );

  test('同一视频属于两个收藏夹时两种筛选都能命中', () async {
    final db = await openV3Db();
    final service = DatabaseService()..databaseOverride = db;

    await service.insertVideos([makeVideo('BV1', '数学课')], folderId: 11);
    await service.insertVideos([makeVideo('BV1', '数学课')], folderId: 22);

    // 按收藏夹 11 搜索
    final r1 = await service.searchVideos('数学', visibleFolderIds: [11]);
    expect(r1.map((v) => v.bvid), contains('BV1'));

    // 按收藏夹 22 搜索
    final r2 = await service.searchVideos('数学', visibleFolderIds: [22]);
    expect(r2.map((v) => v.bvid), contains('BV1'));

    // 两个都选也命中
    final r3 = await service.searchVideos('数学', visibleFolderIds: [11, 22]);
    expect(r3.map((v) => v.bvid), contains('BV1'));
  });

  test('收藏夹和合集共享视频时不丢失任一来源', () async {
    final db = await openV3Db();
    final service = DatabaseService()..databaseOverride = db;

    await service.insertVideos([makeVideo('BV2', '物理课')], folderId: 33);
    await service.insertVideos([makeVideo('BV2', '物理课')], seasonId: 44);

    final r1 = await service.searchVideos('物理', visibleFolderIds: [33]);
    expect(r1, hasLength(1));

    final r2 = await service.searchVideos('物理', visibleSeasonIds: [44]);
    expect(r2, hasLength(1));
  });

  test('UP 来源可以单独筛选', () async {
    final db = await openV3Db();
    final service = DatabaseService()..databaseOverride = db;

    await service.insertVideos([makeVideo('BV3', '化学课')], upId: 555);

    final r1 = await service.searchVideos('化学', visibleUpIds: [555]);
    expect(r1, hasLength(1));

    // 未选该 UP 时不命中
    final r2 = await service.searchVideos('化学', visibleUpIds: [999]);
    expect(r2, isEmpty);
  });

  test('clearFolderCache 只删关系，多来源视频保留', () async {
    final db = await openV3Db();
    final service = DatabaseService()..databaseOverride = db;

    await service.insertVideos([makeVideo('BV4', '生物课')], folderId: 66);
    await service.insertVideos([makeVideo('BV4', '生物课')], seasonId: 77);

    await service.clearFolderCache(66);

    // 视频仍可通过 season 搜索到
    final r = await service.searchVideos('生物', visibleSeasonIds: [77]);
    expect(r, hasLength(1));
  });

  test('clearFolderCache 后无来源视频被删除', () async {
    final db = await openV3Db();
    final service = DatabaseService()..databaseOverride = db;

    await service.insertVideos([makeVideo('BV5', '历史课')], folderId: 88);
    await service.clearFolderCache(88);

    final r = await service.searchVideos('历史');
    expect(r, isEmpty);
  });

  test('v2 到 v3 迁移保留现有视频数据', () async {
    final dir = await Directory.systemTemp.createTemp('db_migrate');
    final dbPath = '${dir.path}${Platform.pathSeparator}test.db';
    // 先建 v2 表（只有 videos，无 video_sources）
    final db = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
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
      ),
    );
    await db.insert('videos', {
      'bvid': 'BV6',
      'title': '老视频',
      'cover': '',
      'upper_name': 'UP',
      'folder_id': 99,
      'season_id': null,
      'json_data':
          '{"bvid":"BV6","title":"老视频","cover":"","duration":10,"upper":{"mid":1,"name":"UP"},"cnt_info":{"play":0,"danmaku":0},"pub_time":0}',
      'timestamp': 1700000000,
    });
    await db.close();

    // 重新以 v3 打开触发迁移
    final db3 = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 3,
        onUpgrade: (db, oldVersion, newVersion) async {
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
            await db.execute('''
                INSERT OR IGNORE INTO video_sources (bvid, source_type, source_id, synced_at)
                SELECT bvid, 'folder', folder_id, timestamp FROM videos
                WHERE folder_id IS NOT NULL AND folder_id > 0
              ''');
          }
        },
      ),
    );

    // 迁移后关系表有旧数据
    final sources = await db3.query(
      'video_sources',
      where: 'source_type = ?',
      whereArgs: ['folder'],
    );
    expect(sources, hasLength(1));
    expect(sources.first['bvid'], 'BV6');
    expect(sources.first['source_id'], 99);
    await db3.close();
    await dir.delete(recursive: true);
  });
}
