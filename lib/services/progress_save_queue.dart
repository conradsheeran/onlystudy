import '../models/playback_progress_snapshot.dart';

/// 串行化播放进度保存命令，并在队列中只保留最后一个待保存快照。
///
/// 5 秒周期的进度保存与分集切换、播放下一个视频时的保存可能重叠；
/// 本队列保证：
/// 1. 任意时刻最多一个持久化操作在途（不会并发读改写 SharedPreferences）；
/// 2. 排队中的快照被更新的快照替换，旧状态不会覆盖新状态。
class ProgressSaveQueue {
  ProgressSaveQueue({required this.persist});

  /// 持久化单个快照；由调用方注入（生产为 HistoryService，测试可替换）。
  final Future<void> Function(PlaybackProgressSnapshot snapshot) persist;

  PlaybackProgressSnapshot? _pending;
  bool _draining = false;

  /// 提交一个快照。若已有保存循环在跑，只更新待保存快照并立即返回。
  Future<void> submit(PlaybackProgressSnapshot snapshot) {
    _pending = snapshot;
    if (_draining) {
      return Future<void>.value();
    }
    _draining = true;
    return _drain();
  }

  Future<void> _drain() async {
    try {
      while (_pending != null) {
        final next = _pending!;
        _pending = null;
        await persist(next);
      }
    } finally {
      _draining = false;
    }
  }
}
