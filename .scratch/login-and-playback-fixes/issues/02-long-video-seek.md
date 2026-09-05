# 02 - 长视频无法大幅度拖拽到后半部分

Status: proposed
优先级: P1

## 症状

约 1 小时的长视频，无法直接跳到后半部分；表现像"加载不出来"。

## 根因

### 主因：只取了多段 durl 的第一段

`lib/services/playback_gateway.dart:getVideoPlayUrl()` 请求参数是：

```dart
'fnval': 1,   // 旧版渐进式 MP4 / durl
'fnver': 0,
'fourk': 1,
```

`fnval: 1` 走的是**旧版 durl 分片格式**。B 站对长视频会把 `durl` 切成**多段**返回（每段带 `order` / `length` / `size`）。而 `lib/models/bili_models.dart:VideoPlayInfo.fromJson()` 是：

```dart
if (json['durl'] != null && (json['durl'] as List).isNotEmpty) {
  url = json['durl'][0]['url'];   // ← 只取第一段
}
```

于是播放器拿到的媒体**只有第一段**。视频后半部分的字节根本不在这个 URL 里，所以往后拖必然失败 —— 这不是"加载慢"，是"数据不存在"。同时 mpv 报告的 duration 也只是第一段的时长。

对照 `ref/`（PiliPlus）：`ref/lib/http/video.dart:videoUrl()` 用 `'fnval': 4048`（DASH，全格式），`qn: 80`，从不走 durl。

### 次因：手势拖拽灵敏度过低

`video_player_screen.dart:onHorizontalDragUpdate` 是 `delta * 200`（200ms / 像素）。要从一小时视频的开头拖到 1800 秒处，需要横向滑动 9000 像素 —— 物理上做不到。用户说的"无法大幅度拖拽"里有这一半原因。

### 次因：没有任何 mpv 缓存/解复用配置

`_bootstrapPlayer()` 只设了 `logLevel`。`ref` 会为每个非本地源注入缓冲参数（`ref/lib/utils/storage_pref.dart:initBuffer`）：

```
cache=yes
cache-secs=<N>
demuxer-hysteresis-secs=<N/1.5>
demuxer-max-bytes / demuxer-max-back-bytes
```

远端长视频跨大距离 seek 时，这组参数直接决定重新起播的等待时间。

## 修复方案

### 主修 1：切到 DASH（`fnval: 4048`）

`playback_gateway.dart`：

```dart
queryParameters: {
  'bvid': bvid,
  'cid': cid,
  'qn': qn ?? SettingsService().defaultResolution,
  'fnval': 4048,   // DASH，全格式
  'fnver': 0,
  'fourk': 1,
},
```

DASH 的 `baseUrl` 是单个完整媒体流、支持 Range，跨段 seek 本来就是它的常规路径。

### 主修 2：`VideoPlayInfo.fromJson` 正确解析

改成 **DASH 优先**：

1. 有 `dash` → 从 `dash.video` 里挑 **id 最接近目标 qn 且不超过它**的表示（不是 `videoList[0]`，B 站返回的排序不保证）；音频取 `dash.audio` 里 `id` 最大的（或按 `bandwidth` 最大）；两者都要保留 `backup_url` 作为兜底。
2. 没有 `dash`、只有 `durl` → **保留整个列表**，而不是丢掉除第一段外的所有段。

`VideoPlayInfo` 增加 `List<String> segmentUrls`（durl 场景），`url` 保持为 `segmentUrls.first` 以兼容现有调用点。

### 主修 3：durl 多段的播放（若仍需兼容）

media_kit / mpv 可以用 `edl://` 把多段拼成一条时间线：

```
edl://!no_clip;!no_chapters;%<len>%<url1>;%<len>%<url2>;...
```

`ref` 就是用 `edl://` 把 video 与 audio 合成一条流的（`ref/lib/plugin/pl_player/controller.dart:_createVideoController`）。

**顺带修一个现存隐患**：当前代码用 `_player.setAudioTrack(AudioTrack.uri(audioUrl))` 挂 DASH 音轨。外挂音轨在远端大跨度 seek 时音画同步/重新缓冲表现明显差于 `edl://` 合流。建议一并改为 `edl://` 方案，与 `ref` 对齐。

### 主修 4：注入 mpv 缓冲参数

`_setupController()` 里对非本地源：

```dart
final media = Media(
  url,
  httpHeaders: isLocal ? null : httpHeaders,
  start: startAt,                       // ← 见下
  extras: isLocal
      ? {'cache': 'no'}
      : {
          'cache': 'yes',
          'cache-secs': '30',
          'demuxer-hysteresis-secs': '20',
          'demuxer-max-bytes': '${64 * 1024 * 1024}',
          'demuxer-max-back-bytes': '${64 * 1024 * 1024}',
        },
);
```

### 主修 5：用 `Media(start:)` 取代 open-then-seek

当前 `_setupController` 是 `open(play: false)` → `_waitForReadyAndClamp` → `seek` → `_ensurePositionSticks`（最多 4 次重试）→ `_startPositionGuard`（2 秒内每 250ms 拽回去）。这一整套"位置守护"是在跟 mpv 抢方向盘，本身就是不稳定起播的症状而非解药，且在 issue 03 里会把用户锁死在片尾。

`ref` 的做法是把起播点交给 mpv：`Media(video, start: seekTo)`。改用它之后，`_waitForReadyAndClamp` / `_ensurePositionSticks` / `_startPositionGuard` / `_positionGuardTimer` 可以整体删除。

### 次修：拖拽灵敏度按时长自适应

```dart
// 全屏横滑一次 ≈ 覆盖视频 25%，且限定在 [1x, 30x] 常速区间
final durationMs = _player.state.duration.inMilliseconds;
final screenWidth = MediaQuery.of(context).size.width;
final msPerPixel = (durationMs * 0.25 / screenWidth).clamp(200.0, 30000.0);
final newMs = (currentMs + delta * msPerPixel).clamp(0, durationMs).toInt();
```

进度条（`seekBar`）本身是绝对定位拖拽，不受此影响；但如果 duration 因为 durl 截断而错误，进度条同样是坏的 —— 主修 1/2 才是根本。

## 验证回路（先建再改）

**回路 A（离线、秒级、能直接证伪主因）**：把一个真实的 1h 视频的 `playurl` 响应 JSON 存到 `test/fixtures/playurl_long_video.json`（**存之前删掉 URL 里的鉴权参数，或整体做脱敏**），然后：

```dart
test('多段 durl 不会丢掉除第一段以外的内容', () {
  final info = VideoPlayInfo.fromJson(fixture);
  expect(info.segmentUrls.length, greaterThan(1));  // 修复前这里就是 1
});
test('DASH 响应优先取 dash 流', () { ... });
```

抓 fixture 的一次性脚本（凭据走环境变量，不要写进文件）：
```bash
curl -s -H "Cookie: SESSDATA=$SESSDATA" \
  "https://api.bilibili.com/x/player/playurl?bvid=<BVID>&cid=<CID>&qn=64&fnval=1&fnver=0&fourk=1" \
  | jq '{code, durl_count: (.data.durl|length), durations: [.data.durl[].length]}'
```
若 `durl_count > 1`，主因当场坐实。再跑一次 `fnval=4048` 对比 `.data.dash` 是否存在。

**回路 B（真机）**：打开 1h 视频 → 拖到 50 分钟处 → 应在数秒内起播且能继续正常播放。

## 风险

- 改 `fnval` 会改变返回结构，`_switchQuality` / `acceptQuality` / 下载模块（`download_service.dart`）都可能依赖当前 durl 形态，**需要一起排查**。
- DASH 需要 video+audio 双流，离线下载路径要确认是否也走这个 gateway。
