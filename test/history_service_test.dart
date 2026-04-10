import 'package:flutter_test/flutter_test.dart';
import 'package:onlystudy/models/bili_models.dart';
import 'package:onlystudy/services/history_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Video buildVideo(String bvid, String title) {
  return Video(
    bvid: bvid,
    title: title,
    cover: 'https://example.com/$bvid.jpg',
    duration: 120,
    upper: BiliUpper(mid: 1, name: 'UP $bvid'),
    view: 0,
    danmaku: 0,
    pubTimestamp: 0,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HistoryService', () {
    late HistoryService service;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      service = HistoryService();
    });

    test('stores one entry per video and updates current part progress',
        () async {
      final video = buildVideo('BV1', 'Video 1');

      await service.seedHistory(video);
      await service.savePlaybackProgress(
        video: video,
        aid: 100,
        cid: 200,
        page: 2,
        partTitle: 'Part 2',
        duration: 300,
        seconds: 87,
        isFinished: false,
      );

      final entries = await service.getHistoryEntries();
      expect(entries, hasLength(1));
      expect(entries.first.bvid, 'BV1');
      expect(entries.first.aid, 100);
      expect(entries.first.cid, 200);
      expect(entries.first.page, 2);
      expect(entries.first.partTitle, 'Part 2');
      expect(entries.first.progressSeconds, 87);
      expect(entries.first.progressForCid(200), 87);
    });

    test('sorts entries by latest viewed time', () async {
      final video1 = buildVideo('BV1', 'Video 1');
      final video2 = buildVideo('BV2', 'Video 2');

      await service.seedHistory(video1);
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await service.seedHistory(video2);
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await service.savePlaybackProgress(
        video: video1,
        aid: 101,
        cid: 201,
        page: 1,
        partTitle: 'Part 1',
        duration: 120,
        seconds: 15,
        isFinished: false,
      );

      final entries = await service.getHistoryEntries();
      expect(entries.map((entry) => entry.bvid).toList(), ['BV1', 'BV2']);
    });

    test('migrates legacy local history and progress data', () async {
      SharedPreferences.setMockInitialValues({
        'local_watch_history': [
          '{"bvid":"BV9","title":"Old Video","cover":"cover","duration":90,"upper":{"mid":1,"name":"Old UP"},"cnt_info":{"play":1},"pub_time":1,"viewed_at":123456}'
        ],
        'local_watch_progress': '{"BV9_333":66}',
      });

      final migratedEntries = await HistoryService().getHistoryEntries();
      expect(migratedEntries, hasLength(1));
      expect(migratedEntries.first.bvid, 'BV9');
      expect(migratedEntries.first.cid, 333);
      expect(migratedEntries.first.progressSeconds, 66);
      expect(migratedEntries.first.progressForCid(333), 66);
    });

    test('clearHistory removes new and legacy storage', () async {
      final video = buildVideo('BV1', 'Video 1');
      await service.seedHistory(video);
      await service.clearHistory();

      expect(await service.getHistoryEntries(), isEmpty);
    });
  });
}
