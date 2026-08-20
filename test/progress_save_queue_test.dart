import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:onlystudy/models/bili_models.dart';
import 'package:onlystudy/models/playback_progress_snapshot.dart';
import 'package:onlystudy/services/progress_save_queue.dart';

void main() {
  final video = Video(
    bvid: 'BV1test',
    title: '测试视频',
    cover: '',
    duration: 600,
    upper: BiliUpper(mid: 1, name: '测试UP'),
    view: 0,
    danmaku: 0,
    pubTimestamp: 0,
  );

  PlaybackProgressSnapshot snapshotFor({
    required int cid,
    int seconds = 10,
    int page = 1,
    String partTitle = 'P1',
    bool isFinished = false,
  }) {
    return PlaybackProgressSnapshot(
      video: video,
      aid: 1000,
      cid: cid,
      page: page,
      partTitle: partTitle,
      duration: 600,
      seconds: seconds,
      isFinished: isFinished,
    );
  }

  group('PlaybackProgressSnapshot', () {
    test('不可变快照保持字段固定', () {
      final snapshot = snapshotFor(cid: 11, seconds: 42);
      expect(snapshot.cid, 11);
      expect(snapshot.seconds, 42);
    });

    test('copyWith 只修改指定字段', () {
      final snapshot = snapshotFor(cid: 11, seconds: 42);
      final updated = snapshot.copyWith(seconds: 100, isFinished: true);
      expect(updated.cid, 11);
      expect(updated.seconds, 100);
      expect(updated.isFinished, true);
      // 原快照不受影响
      expect(snapshot.seconds, 42);
      expect(snapshot.isFinished, false);
    });
  });

  group('ProgressSaveQueue', () {
    test('顺序提交按序持久化', () async {
      final persisted = <PlaybackProgressSnapshot>[];
      final queue = ProgressSaveQueue(
        persist: (snapshot) async {
          persisted.add(snapshot);
        },
      );

      await queue.submit(snapshotFor(cid: 11, seconds: 10));
      await queue.submit(snapshotFor(cid: 11, seconds: 20));

      expect(persisted, hasLength(2));
      expect(persisted[0].seconds, 10);
      expect(persisted[1].seconds, 20);
    });

    test('持久化在途时提交的新快照合并为最后一个，旧值不覆盖新值', () async {
      final persisted = <PlaybackProgressSnapshot>[];
      final gate = Completer<void>();
      final queue = ProgressSaveQueue(
        persist: (snapshot) async {
          persisted.add(snapshot);
          await gate.future; // 模拟慢速持久化（网络等待）
        },
      );

      final first = queue.submit(snapshotFor(cid: 11, seconds: 10));
      // 第一个持久化仍卡在 gate；期间提交两次新快照
      final second = queue.submit(snapshotFor(cid: 11, seconds: 20));
      final third = queue.submit(snapshotFor(cid: 12, seconds: 30));

      // 让第一个 drain 循环完成 gate
      await Future<void>.delayed(Duration.zero);
      gate.complete();
      await first;
      await second;
      await third;

      expect(persisted, hasLength(2));
      expect(persisted[0].seconds, 10);
      // 合并后的最后一个快照是新分集 cid=12
      expect(persisted[1].cid, 12);
      expect(persisted[1].seconds, 30);
    });

    test('同一时刻最多一个持久化在途', () async {
      var inFlight = 0;
      var maxInFlight = 0;
      final queue = ProgressSaveQueue(
        persist: (snapshot) async {
          inFlight++;
          maxInFlight = maxInFlight > inFlight ? maxInFlight : inFlight;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          inFlight--;
        },
      );

      await Future.wait([
        queue.submit(snapshotFor(cid: 11)),
        queue.submit(snapshotFor(cid: 11, seconds: 20)),
        queue.submit(snapshotFor(cid: 11, seconds: 30)),
      ]);

      expect(maxInFlight, 1);
    });
  });
}
