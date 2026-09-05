# 03 - 已看完的视频进度未重置，再次打开立刻结束

Status: proposed
优先级: P0（用户描述"根本无法打开一个已看完的视频"）

## 症状

合集里某个视频播完后，再次点开它：进度条直接停在末尾，视频瞬间"播完"，然后自动跳到下一个视频。

## 根因链条

1. `video_player_screen.dart:_bootstrapPlayer()` 订阅 `player.stream.completed`，播完调用 `_checkVideoEnd()`。
2. `_checkVideoEnd()` → `_saveProgress(markFinished: true)`。
3. `_captureSnapshot(markFinished: true)` 把 `effectivePosition` 设为 `durationSeconds`（**整段时长**），写入 `PlaybackProgressSnapshot.seconds`。
4. `HistoryService.savePlaybackProgress()` → `withPartProgress(cid, duration)`，于是 `partProgress[cid] == duration` 被持久化。
5. 再次进入：`_initializePlayer()` 读 `resumeHistory?.progressForCid(_cid!)` → 得到 `duration`。
6. `_setupController(startAt: Duration(seconds: duration))` → `_waitForReadyAndClamp()` 把目标 clamp 到 `duration - 500ms` —— **保证落在片尾**。
7. seek 到片尾 → mpv 立刻发 `completed` → `_checkVideoEnd()` 又跑一遍 → 再次写 `duration`、并 `_playNext()` 跳走。
8. 同时 `_ensurePositionSticks()` / `_startPositionGuard()` 在之后 2 秒内反复把播放头 seek 回片尾，用户任何手动拖拽都会被拽回去 —— 这就是"根本打不开"。

注意第 3 步不是唯一入口：`_captureSnapshot()` 里 `isFinished = effectivePosition >= durationSeconds - 3`，5 秒周期保存在片尾附近同样会留下一个"接近 duration"的进度，效果一样。

另外 `HistoryEntry.isFinished` 是**条目级**（每个 bvid 一个），而 `partProgress` 是**按 cid**的。多 P 视频里 P1 播完会把整条 entry 标记为已看完，粒度错误。

## 修复方案

### 主修：在**读取**侧做"接近结尾即从头开始"（自愈）

在读取处而不是写入处做判定，好处是**对已经写坏的历史数据也生效** —— 用户当前已经损坏的本地记录不需要迁移就能恢复。

`lib/services/history_service.dart` 新增：

```dart
/// 判定为"已看完"的尾部容差。与 _captureSnapshot 的 -3 秒阈值保持一致，
/// 再留一点余量，避免片尾 seek 立刻触发 completed。
static const int kNearEndToleranceSeconds = 5;

/// 恢复播放用的起播位置：接近结尾（或超出时长）时返回 0，从头开始。
///
/// 这是"已看完的视频打不开"的单点防线：写入侧无论存了多少，
/// 起播位置永远不会落在会立刻触发 completed 的片尾区间。
Future<int> getResumePosition(String bvid, int cid, int durationSeconds) async {
  final raw = await getProgress(bvid, cid);
  return resolveResumePosition(raw, durationSeconds);
}

@visibleForTesting
static int resolveResumePosition(int rawSeconds, int durationSeconds) {
  if (rawSeconds <= 0) return 0;
  if (durationSeconds <= 0) return rawSeconds;
  if (rawSeconds >= durationSeconds - kNearEndToleranceSeconds) return 0;
  return rawSeconds;
}
```

`video_player_screen.dart` 三处起播计算全部改走它：

- `_initializePlayer()` 里的 `resumeSeconds`（注意它同时来自 `resumeHistory?.progressForCid` 和 `HistoryService().getProgress`，两条路都要过 `resolveResumePosition`，时长用 `_currentDurationSeconds`）
- `_switchPart()` 里的 `localPosition`
- `widget.initialHistoryEntry` 传进来的进度（`_resumeHistoryEntry`）

`resumeSeconds == 0` 时不要再弹"从 xx:xx 继续播放"的 SnackBar。

### 辅修 A：写入侧不要把进度顶到 duration

`_captureSnapshot(markFinished: true)` 改为 `effectivePosition = 0`，`isFinished = true`。语义变成"这一集看完了，下次从头播"。`HistoryEntry.isFinished` 仍然驱动 `history_tile.dart` 的"已看完"角标和满进度条渲染（那里读的是 `isFinished`，不是 `progressSeconds`，所以 UI 不受影响 —— **实现时请确认 `history_tile.dart:199` 的分支确实只依赖 `isFinished`**）。

### 辅修 B：`completed` 事件去抖，切断"打开即跳下一个"的级联

`_bootstrapPlayer()` 的 completed 订阅加两道闸：

```dart
bool _endHandled = false;      // 每次 open 后复位
```

- `_setupController()` 开头 `_endHandled = false;`
- `_checkVideoEnd()` 首行 `if (_endHandled || _isLoading) return; _endHandled = true;`

`_isLoading` 这一条尤其重要：起播 seek 过程中触发的 completed 一律忽略。

### 辅修 C：`isFinished` 改为按 cid（可选，多 P 视频正确性）

`HistoryEntry` 增加 `Set<String> finishedCids`（或复用 `partProgress` 存 `-1` 哨兵）。条目级 `isFinished` 保留为"所有分 P 都看完"。这条不影响用户报告的症状，可单独排期。

## 验证回路（先建再改）

纯逻辑，可直接单测，秒级：

`test/history_resume_test.dart`
```dart
test('已看完的进度不再作为起播位置', () {
  expect(HistoryService.resolveResumePosition(3600, 3600), 0);
  expect(HistoryService.resolveResumePosition(3597, 3600), 0);   // 尾部容差内
  expect(HistoryService.resolveResumePosition(1800, 3600), 1800); // 正常续播
  expect(HistoryService.resolveResumePosition(0, 3600), 0);
  expect(HistoryService.resolveResumePosition(100, 0), 100);      // 时长未知不干预
});
```

跑：`flutter test test/history_resume_test.dart`

真机确认：打开一个已看完的合集视频 → 应从 0 起播、不弹续播提示、不自动跳下一个。
