import 'bili_models.dart';

/// 播放进度的不可变快照。
///
/// 在任意网络等待之前从播放器页面捕获，之后保存逻辑只依赖快照，
/// 避免 await 期间页面状态切换导致旧分集的进度写入新分集。
class PlaybackProgressSnapshot {
  final Video video;
  final int aid;
  final int cid;
  final int page;
  final String partTitle;
  final int duration;
  final int seconds;
  final bool isFinished;
  final List<int> knownCids;

  const PlaybackProgressSnapshot({
    required this.video,
    required this.aid,
    required this.cid,
    required this.page,
    required this.partTitle,
    required this.duration,
    required this.seconds,
    required this.isFinished,
    this.knownCids = const [],
  });

  PlaybackProgressSnapshot copyWith({
    int? seconds,
    bool? isFinished,
    List<int>? knownCids,
  }) {
    return PlaybackProgressSnapshot(
      video: video,
      aid: aid,
      cid: cid,
      page: page,
      partTitle: partTitle,
      duration: duration,
      seconds: seconds ?? this.seconds,
      isFinished: isFinished ?? this.isFinished,
      knownCids: knownCids ?? this.knownCids,
    );
  }
}
