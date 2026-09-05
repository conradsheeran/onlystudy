# 登录与播放三个缺陷的修复方案

Status: proposed
Date: 2026-08-30
参考实现: `ref/`（PiliPlus）

## 背景

用户报告三个缺陷：

1. **单设备登录卡死**：截图二维码 → 切到 B 站 App 扫码 → 切回唯学，登录界面无任何反应；必须用第二台设备扫码才能完成登录。
2. **播放问题 1**：长视频（约 1h）无法大幅度拖拽，跳不到��频后半部分。
3. **播放问题 2**：合集中一个视频播完后进度不重置，再次打开会加载到视频末尾并立刻"播完"，严重时根本打不开已看完的视频。

## 诊断方式说明（重要）

本次没有可运行的真机反馈回路（无设备、无法复现网络与 B 站 CDN 行为），因此这三条结论是**代码级静态定位**，不是"红→绿"验证过的。每条 issue 都给出了在实现时应先建立的验证手段（单测 / 一次性脚本 / 真机步骤）。请在实现时先建回路、再改代码。

## 根因摘要

| # | 缺陷 | 根因 | 关键位置 |
|---|---|---|---|
| 01 | 单设备登录无反应 | `AuthService` 私有 Dio **没有任何超时**，App 切后台时在途的 poll 请求可能永久挂起；`_pollInFlight` 闩锁因此永不复位，轮询彻底停摆。且无生命周期监听，回到前台不会立即补一次轮询。 | `lib/services/auth_service.dart`、`lib/screens/login_screen.dart` |
| 02 | 长视频无法大幅拖拽 | `getVideoPlayUrl` 用 `fnval: 1`（旧版 durl/渐进式），长视频 B 站会返回**多段 durl**，而 `VideoPlayInfo.fromJson` 只取 `durl[0]` —— 播放器拿到的只是第一段，后半部分根本不在媒体里。叠加手势拖拽灵敏度只有 200ms/px。 | `lib/services/playback_gateway.dart`、`lib/models/bili_models.dart`、`lib/screens/video_player_screen.dart` |
| 03 | 已看完的视频打不开 | 播放结束时把 `seconds = duration` 写进 `partProgress[cid]`；下次进入时 `resumeSeconds = duration`，被 clamp 到 `duration - 500ms` 后 seek，随即触发 `completed` → 又一次"播完"并自动跳下一个。位置守护还会反复把播放头拽回末尾。 | `lib/screens/video_player_screen.dart`、`lib/services/history_service.dart` |

## Issue 列表

- `issues/01-qr-login-single-device.md`
- `issues/02-long-video-seek.md`
- `issues/03-finished-video-progress-reset.md`

建议实施顺序：**03 → 02 → 01**。03 影响面最大、改动最小、可纯单测验证；02 依赖 03 的 resume 逻辑已修好才好验证；01 独立。
