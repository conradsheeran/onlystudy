# 播放器控件层横竖屏统一与体验优化

Status: ready-for-agent
Date: 2026-09-01
参考实现: `ref/`（PiliPlus 2.1.0，`lib/plugin/pl_player/`）
相关审查项: `docs/codebase-optimization-audit.md` OPT-018（播放器缺少行为测试）

## 诊断方式说明（重要）

本 spec 与上一份 `login-and-playback-fixes` 一样，**没有真机回路**：结论来自对 `lib/screens/video_player_screen.dart`、`media_kit_video` 2.0.1 源码和 `ref/` 的代码级静态定位，不是"红→绿"验证过的。实现时请**先建 Widget 测试回路（见「测试决策」），再动 UI**；真机走查（刘海屏横屏、竖屏视频、旋转锁定）放在实现末尾。

---

## 问题陈述 (Problem Statement)

用户在唯学里看网课，竖屏时播放器是"应用自己的样子"：青色（`colorScheme.primary`）的进度条、顶部一行返回/标题/分集/倍速/缓存/清晰度。

一旦点全屏转到横屏，播放器**看起来像换了一个 App**：

1. 进度条从青色变成**鲜红色**，并且从距底部 60 的位置**贴死到屏幕最底边**；
2. 底部按钮排布、中央播放键大小都跟着变；
3. 横屏时顶部的返回键和右侧按钮**会被刘海/挖孔压住**；
4. 退出全屏后屏幕方向被解锁成"任意方向"，回到列表页可能仍是横的；
5. 竖屏拍摄的视频进全屏后也被**强制转成横屏**，画面反而更小。

除了不一致，播放器本身也停留在"贴在 media_kit 默认控件上"的状态：

6. 调音量/亮度/快进时弹出的是一个 24×16 内边距、48 号图标、18 号粗体白字的**大黑方块**，和应用其它地方的视觉语言完全不搭，而且只显示 `85%` 这种裸数字，没有"音量/亮度"标签（`volume`/`brightness`/`seekForward`/`seekBackward` 四个 l10n key 早就写好了，从没被用过）；
7. 看不到"当前时间 / 总时长"，控件隐藏后也没有任何进度提示；
8. 横屏时没有防误触锁，握持时经常误触发暂停或快进；
9. 加载失败只有一行白字，没有 `ErrorView`、没有重试；
10. 分集列表弹窗用的是 `Colors.grey[900]` + `Colors.white` 硬编码色、没有安全区、没有拖拽手柄，横屏时几乎占满屏幕。

### 根因（静态定位）

| # | 现象 | 根因 |
|---|---|---|
| A | 横屏进度条变红、贴底、按钮位移 | `media_kit_video` 2.0.1 的 `MaterialVideoControlsTheme` 持有 `normal` 与 `fullscreen` **两个互不继承的整体对象**。当前代码在 `fullscreen` 里只给了 `topButtonBar` / `topButtonBarMargin`，其余字段回落到**构造函数默认值**——既不是 `normal`，也不是包自带的 `kDefaultMaterialVideoControlsThemeDataFullscreen`。于是 `seekBarPositionColor`/`seekBarThumbColor` 回到 `Color(0xFFFF0000)`，`seekBarMargin` 回到 `EdgeInsets.zero`，中央播放键回到 48（全屏默认是 56），底栏丢掉 `bottom: 42` 的抬升。 |
| B | 一致性只能靠人工对齐 | media_kit 的全屏是在 **root navigator 上 push 的一条新路由**，控件在那里被**重新创建**为另一个元素。两份 ThemeData + 两棵控件树意味着：以后每加一个状态都要再对齐一遍。该包的 `MaterialVideoControlsTheme.updateShouldNotify` 语义还是反的（数据**没变**时返回 `true`），主题更新的传播不可靠。 |
| C | 横屏被刘海遮挡 | media_kit 全屏路由挂在 root navigator 上，页面自己的 `SafeArea` 完全不生效；包内唯一的补偿是 `padding ?? MediaQuery.of(context).padding`，而当前代码没设 `padding`，全屏又走的是构造函数默认（`null`），只能拿到 `MediaQuery.padding`——在 `immersiveSticky` 下这个值会塌成 0，横屏左右两侧的挖孔得不到补偿。 |
| D | 方向失控 | 全仓库**没有任何** `SystemChrome` / `OrientationBuilder` / `DeviceOrientation` 调用（已穷举）。方向完全由 media_kit 的 `defaultEnterNativeFullscreen`（强制 `landscapeLeft/Right`）和 `defaultExitNativeFullscreen`（`setPreferredOrientations([])`，即解锁成任意方向）决定，应用没有自己的方向策略。 |
| E | 手势与 HUD 是"贴上去"的 | media_kit 的内建手势在 `normal` 下全部默认关闭，所以 `_buildGestureLayer` + `_buildOverlay` 是**叠在** `MaterialVideoControls` 之上的第二层，两套逻辑各管一半（seek bar 归包管、手势归应用管），HUD 样式也就没进主题体系。 |

---

## 解决方案 (Solution)

**让播放器页面自己拥有"全屏"这个概念，并且只保留一棵控件树。**

1. **不再调用 media_kit 的 `toggleFullscreen`，不再 push 全屏路由。** 全屏 = 在同一个 `VideoPlayerScreen` 内切换一个 `isFullscreen` 标志 + 方向锁 + 系统栏 + 安全区内边距。控件树全程唯一、从不销毁，**横竖屏一致是结构保证的，不是靠约定维持的**（这正是 `ref/` 的做法：单一 `PLVideoPlayer` + `isFullScreen` 响应式标志，整份 2412 行的控件层里只有约 25 处 `isFullScreen` 条件，且几乎全是"加一个按钮 / 加一点内边距"这种**增量**差异）。
2. **弃用 `MaterialVideoControls`，改用应用自有的控件层 `PlayerChrome`。** 强调色一律取 `colorScheme.primary`，圆角沿用应用的 12/16 尺度，文案一律走 `AppLocalizations`。视频画面上的图标/文字仍用白色与半透明黑（画面上必须保证对比度），但这是**一处显式声明的例外**，不是散落的硬编码。
3. **借鉴 PiliPlus 补齐横屏体验**：分区手势（双击四分区、竖向三分区）、全屏防误触锁、按视频宽高比决定全屏方向、常驻细进度条 + 位置/总时长显示。

---

## 用户故事 (User Stories)

### 外观一致

1. 作为一个用网课学习的用户，我希望横屏播放时的进度条和竖屏一样是应用的青色，这样我不会觉得自己切到了另一个 App。
2. 作为一个用户，我希望横屏时进度条不要贴死在屏幕最底边，而是和竖屏一样留出边距，这样我用拇指拖动时不会误触到系统手势条。
3. 作为一个用户，我希望横竖屏下顶部的按钮是同一组、同样的顺序（返回、标题、分集、倍速、缓存、清晰度），这样我不用重新找按钮在哪。
4. 作为一个用户，我希望横竖屏下的中央播放键、按钮尺寸、圆角、字号都一致，这样切换方向时视觉不会跳变。
5. 作为一个用户，我希望播放器的强调色跟随应用主题，而不是出现一个应用里任何其它地方都没有的红色。
6. 作为一个用户，我希望切换横竖屏时画面不黑屏、不重新缓冲、不从头开始，因为播放器只是被重新排版而不是被重建。

### 方向与全屏

7. 作为一个手持刘海屏手机的用户，我希望横屏时返回键和右上角按钮不被挖孔压住，这样我随时点得到它们。
8. 作为一个用户，我希望在横屏全屏时系统状态栏和导航栏自动隐藏，画面能真正铺满。
9. 作为一个看竖屏视频（比如竖版录屏课）的用户，我希望点全屏后**保持竖屏**放大，而不是被强制转成横屏让画面更小。
10. 作为一个用户，我希望退出全屏后屏幕恢复到竖屏，而不是停留在横着的状态回到列表页。
11. 作为一个用户，我希望按手机的返回键时是一层层退出的：先解锁 → 再退出全屏 → 最后才退出播放页，而不是一下子把播放页关掉。
12. 作为一个用户，我希望屏幕上的"全屏 / 退出全屏"按钮和返回键的行为完全一致。
13. 作为一个用户，我希望反复快速点全屏按钮时播放器不会卡在半全屏的错乱状态。

### 控件与信息

14. 作为一个用户，我希望随时能看到"当前播放到第几分钟 / 总共多长"，这样我能判断这节课还剩多少。
15. 作为一个用户，我希望时间数字在秒数跳动时宽度不抖动，不要把旁边的按钮挤来挤去。
16. 作为一个用户，我希望控件自动隐藏后屏幕底部仍有一条很细的进度条，这样我不用点一下就能知道进度。
17. 作为一个用户，我希望进度条上能看出已缓冲到哪里，这样网络卡的时候我知道是不是快要卡住了。
18. 作为一个用户，我希望点一下画面就能显示/隐藏控件，几秒不操作就自动隐藏，不要一直挡着画面。
19. 作为一个用户，我希望我正在拖动进度条时控件不要突然自动隐藏。
20. 作为一个用户，我希望拖动进度条时播放头不会和我的手指"打架"往回跳。
21. 作为一个用户，我希望缓冲/加载中有明确的指示，而不是画面就那么停住。
22. 作为一个用户，我希望播放失败时看到和应用其它页面一样的错误视图并且有一个重试按钮，而不是一行白字。

### 手势

23. 作为一个用户，我希望双击画面中间是播放/暂停，双击左边是后退、双击右边是快进，这样我不用去够进度条。
24. 作为一个用户，我希望连续多次双击快进时秒数是累加的（10 秒、20 秒、30 秒）并且只跳一次，而不是每次都单独跳一下。
25. 作为一个用户，我希望在画面左侧上下滑动调亮度、右侧上下滑动调音量，并且亮度比音量更"钝"一些，方便微调。
26. 作为一个用户，我希望长按画面临时倍速播放、松手立刻恢复我原来的倍速（而不是恢复成 1.0x）。
27. 作为一个用户，我希望左右滑动快进快退时能预先看到"将要跳到的时间"，松手才真正跳过去。
28. 作为一个用户，我希望斜着滑动时播放器什么都不做，而不是又调音量又快进。
29. 作为一个用户，我希望从屏幕最边缘开始的滑动不被播放器抢走，这样系统的返回手势还能用。
30. 作为一个用户，我希望音量/亮度/倍速/快进的提示是一个克制的小胶囊，并且写明"音量""亮度"，而不是屏幕中央一个大黑方块加一串裸数字。
31. 作为一个用户，我希望这些提示的文案跟随我的界面语言（中文/英文）。

### 防误触

32. 作为一个横屏握持手机看课的用户，我希望有一个"锁定"按钮，锁上以后单击、双击、长按、滑动都不再改变播放，这样我怎么握都不会误触。
33. 作为一个已锁定的用户，我希望点一下画面只出现"解锁"这一个按钮，其它控件都不出现。
34. 作为一个已锁定的用户，我希望按返回键是先解锁而不是直接退出全屏或退出播放。
35. 作为一个用户，我希望锁定按钮只在横屏全屏时出现，竖屏时不要多这么一个按钮占地方。

### 分集与菜单

36. 作为一个看多 P 合集的用户，我希望分集列表在竖屏时从底部弹出、在横屏时从右侧滑出，两种情况下都不被刘海遮住、都能滚动到最后一集。
37. 作为一个用户，我希望分集列表、倍速菜单、清晰度菜单的配色和应用其它弹窗一致，而不是一块突兀的深灰。

---

## 实现决策 (Implementation Decisions)

### 模块划分

- **`PlayerChrome`（新，唯一的新缝隙）**：播放器控件层 Widget。**不 import `media_kit` / `media_kit_video`**，输入只有两样东西：
  - `PlayerChromeState`：不可变值对象，携带 `position` / `duration` / `buffered`（统一用**秒**，毫秒精度另存，减少每帧重建）、`isPlaying` / `isBuffering` / `isSeeking`、`title` / `partLabel`、`speedLabel` / `qualityLabel`、`hasParts`、`isFullscreen` / `isLocked` / `controlsVisible`、以及当前 HUD（无 / 音量 / 亮度 / 倍速 / seek 预览 + 数值）。
  - `PlayerChromeCallbacks`：`onBack` / `onPlayPause` / `onSeek` / `onSeekPreview` / `onToggleFullscreen` / `onToggleLock` / `onToggleControls` / `onSelectSpeed` / `onSelectQuality` / `onShowParts` / `onDownload` / `onVolumeDelta` / `onBrightnessDelta`。
  - 横竖屏**共用同一个实例**；`isFullscreen` 只允许产生**增量**差异：全屏时额外挂锁定按钮、额外应用左右安全区内边距。凡是"竖屏一套、横屏另一套"的写法都不接受。
- **`VideoPlayerScreen`（改）**：继续持有 `Player` / `VideoController`，负责把 media_kit 的流映射成 `PlayerChromeState`、驱动全屏状态、处理 `PopScope`。`Video` 只当纹理用（`controls: NoVideoControls`），`MaterialVideoControlsTheme` / `MaterialVideoControls` / `toggleFullscreen` 全部移除。
- **`PlaybackMediaStrategy`（扩展，复用既有缝隙）**：所有新增的**纯判定逻辑**都加到这里，不新建纯逻辑模块——双击四分区判定、竖向三分区判定、方向锁定判定、音量/亮度灵敏度、双击累加秒数、边缘死区、自动隐藏是否应被抑制。
- **`ScreenModeService`（新，薄适配层，不测）**：把 `SystemChrome.setPreferredOrientations` / `setEnabledSystemUIMode` 收在一处，并做**幂等守卫**（模块级记住上一次的方向列表与系统栏状态，相同则直接返回，避免重复打平台通道造成的抖动——`ref/lib/plugin/pl_player/utils/fullscreen.dart` 就是这么做的）。它内部**不做任何判断**，判断都在 `PlaybackMediaStrategy` 里。
- **不动的模块**：`PlaybackSession`、`PlaybackGateway`、`HistoryService`、`ProgressSaveQueue`、`DownloadService`、`SettingsService`。本次不碰播放地址、清晰度协商、进度上报、断点续播、后台播放。
- **不引入 GetX / Hive / Obx**（与 `docs/codebase-optimization-audit.md` 的既定原则一致：借鉴 `ref/` 的模块缝隙，不复制它的全局状态与大型控制器）。状态用 `ValueNotifier` + `setState`，与 OPT-014 建立的 `ValueListenable` 约定一致。

### 全屏机制

- 全屏是**页面内状态**，不 push 路由。进入时先请求方向与系统栏，`isFullscreen` 在 `finally` 里最后置位，使布局只重排一次。
- **重入守卫**：一个 `_fsProcessing` 布尔量，处理中忽略新的切换请求；目标状态与当前一致时直接返回。
- **播放器 Widget 挂 `GlobalKey`**：旋转会改变 `MediaQuery`，可能让 `build` 选到不同的布局分支；`GlobalKey` 让元素被 reparent 而不是重建，从而保住 media_kit 纹理、动画控制器与手势识别器——**不黑屏、不重新缓冲**。
- **桌面端（Windows/Linux）**：全屏按钮仍走 `MethodChannel('com.alexmercerind/media_kit_video')` 的 `Utils.EnterNativeFullscreen` / `Utils.ExitNativeFullscreen`，复用同一个 `PlayerChrome`。桌面端的验收不在本次范围（见 Out of Scope），但**不得回归**。

### 方向策略

- 判定是纯函数（在 `PlaybackMediaStrategy` 里）：
  - 视频宽高比 < 1（竖屏视频）→ 全屏保持 `portraitUp`；
  - 否则锁横屏；Android 上按当前重力方向在 `landscapeLeft` / `landscapeRight` 之间选（规避 Flutter 的方向抖动问题），其它平台固定一个方向；
  - 退出全屏 → 恢复 `portraitUp`（**不是** `[]`，`[]` 会把方向解锁成任意方向，正是当前退出全屏后停在横屏的原因）。
- 视频宽高比来自 `player.state.width/height`；取不到时按横屏处理。
- 系统栏：进入全屏 `SystemUiMode.immersiveSticky`；退出恢复 `SystemUiMode.edgeToEdge`（Android SDK < 29 用 `manual` + 全部 overlays）。
- **本次不做重力感应自动进出全屏**（`ref` 的 `NativeDeviceOrientation` 监听），只做手动切换。

### 安全区

- 用 **`MediaQuery.viewPaddingOf`**，不用 `paddingOf`：`immersiveSticky` 下 `padding` 会塌成 0，而挖孔仍然存在，`viewPadding` 才保留得住。
- 只在**全屏时**应用 `left` / `right` 内边距（横屏时挖孔在左右侧）；竖屏时页面自身的 `SafeArea` 已经够用。

### 控件可见性

- 单一 setter：`set controlsVisible(bool)` —— 无论谁改，都在同一处取消并重启自动隐藏计时器，计时器不可能被忘记重启。
- 默认 3 秒自动隐藏；`isSeeking`（拖动进度条 / 横滑 seek 进行中）期间抑制隐藏。
- 动画：100ms `SlideTransition`，顶栏从 `Offset(0,-1)`、底栏从 `Offset(0,1.2)`（底栏多走一点，让它的渐变蒙层完全滑出下边缘）；顶/底栏各自带一层 `transparent → Color(0xBF000000)` 的线性渐变蒙层保证文字可读；整体包在 `ClipRect` + `RepaintBoundary` 里，避免动画影响视频图层。
- 锁定时 `PlayerChrome` 把 `controlsVisible` 当作 false 处理（除解锁按钮外）。

### 进度条

- 应用自有进度条（不再用 media_kit 的 `MaterialSeekBar`）。数值取自 `ref` 的实测值：轨道高 `3.5`、主进度条 thumb 半径 `7`、常驻细进度条 thumb 半径 `2.5`、轨道底色 `Color(0x33FFFFFF)`、缓冲色 `colorScheme.primary` @ `0.4`、进度色与 thumb 色 `colorScheme.primary`。
- **两个实例，命中测试不同**：控件栏里的主进度条可拖动；屏幕最底边的常驻细进度条**完全不参与命中测试**（纯展示，不抢手势）。
- 拖动期间冻结来自播放器的位置更新（`isSeeking` 为真时不覆盖 `position`），松手才 `seek`。
- 时间显示为 `position / duration`，等宽数字（`FontFeature.tabularFigures()`），**布局宽度按 `duration` 预留**，避免秒数跳动时宽度抖动。

### 手势

- 一层手势，不再是"内建手势 + 自绘手势"两套。
- **方向锁定用 3:1 比例**：累计位移的主轴必须超过副轴 3 倍才认定方向；斜滑什么都不做。区域在认定的那一刻确定，之后不再重算。
- **双击四分区**：`< 25%` 后退、`25%–75%` 播放/暂停、`> 75%` 快进。快进/后退步长 10 秒，**400ms 防抖累加**（连点 3 次 = 一次 30 秒的跳转）。播放已结束时双击中间 = 从头播放。
- **竖向三分区**：左 1/3 亮度（灵敏度 `maxHeight * 3`，很钝，便于微调）、右 1/3 音量（灵敏度 `maxHeight * 0.5`，并做约 20ms 节流）。中间 1/3 本次留空（不做上滑进全屏）。
- **横向 seek** 复用现有的 `PlaybackMediaStrategy.seekTargetMs`（已有测试覆盖），拖动时只更新预览、松手才 `seek`。
- **25px 边缘死区**：起点落在画面四边 25px 内的拖拽不被播放器接管，把系统返回手势和控件栏让出去。
- 长按倍速：2.0x，松手恢复到**用户当前设定的倍速**（不是 1.0x）；仅在正在播放时生效；锁定时不生效。

### HUD / 提示

- 替换现有的居中大黑方块。统一为小胶囊：`Color(0x88000000)`、圆角 64（seek/音量/亮度）或 16（倍速）、内边距 `symmetric(h: 8, v: 5)`、图标 20、文字 13、`AnimatedOpacity` 150ms `easeInOut`、`IgnorePointer`。
- 文案必须走 `AppLocalizations`，并**启用四个已声明但从未使用的 key**：`volume`（音量/Volume）、`brightness`（亮度/Brightness）、`seekForward`（快进/Forward）、`seekBackward`（后退/Backward）。倍速继续用 `speed`。
- 音量图标按 `0 / <0.5 / ≥0.5` 取 `volume_off / volume_down / volume_up`；亮度图标按 `<1/3 / <2/3 / else` 取 `brightness_low / medium / high`。

### 锁定

- 仅全屏时挂载，居左垂直居中，`Color(0x45000000)` 圆角 8 的小方块按钮，图标随状态在"锁/解锁"之间切换，带本地化 tooltip。
- 锁定时：跳过双击、长按、拖拽识别器的注册（只保留单击，用来唤出解锁按钮）；`PlayerChrome` 只渲染解锁按钮；返回键先解锁。
- 需要新增 l10n key：`lockControls`（锁定 / Lock）、`unlockControls`（解锁 / Unlock）。注意 `unlock`（解锁）已被收藏夹锁定功能占用，不要复用语义。改 `.arb` 后必须跑 `flutter gen-l10n`。

### 返回键

- `PopScope` 分层剥离，与 `ref` 的 `onPopInvokedWithResult` 一致：**锁定 → 解锁**；**全屏 → 退出全屏**；**否则 → 退出播放页**。屏幕上的返回箭头调用同一个函数，保证两条路径行为完全相同。

### 主题令牌

- 强调色一律 `colorScheme.primary`；分集弹窗与弹出菜单改用 `surfaceContainer` / `surfaceContainerLow` 等令牌，**移除 `Colors.grey[900]`**；选中项用 `colorScheme.primary`，次要文字用 `onSurfaceVariant`（不再是 `Colors.grey`）。
- 视频画面之上的图标与文字保持白色 / 半透明黑，这是**唯一被显式允许的硬编码例外**（画面内容不可预测，必须保证对比度）。
- 字号回到类型标度：弹窗标题用 `titleMedium`，时长等次要信息用 `bodySmall`，不再出现游离的 `fontSize: 18` 粗体。
- 错误态改用现有的 `ErrorView`（带重试），播放页不再是全应用唯一不用 `ErrorView` 的页面。
- 分集弹窗：竖屏 `showModalBottomSheet` + `isScrollControlled` + `useSafeArea` + `showDragHandle`；横屏改为从右侧滑出的抽屉（约 50% 宽 / 100% 高），350ms `easeInOut`。

---

## 测试决策 (Testing Decisions)

### 什么算好测试

只断言**外部可观察行为**：这个方向下渲染出了什么、点了它触发哪个回调。不断言私有 State 字段、不断言 Widget 树的嵌套形状、不依赖真实的 `Player` / 网络 / 平台通道。测试要能在 `flutter test` 里离线、确定性地跑完。

### 唯一的新缝隙：`PlayerChrome`

`VideoPlayerScreen` 在 `initState` 里直接 `new Player()` / `VideoController()`，页面级 Widget 测试跑不起来；而 `PlayerChrome` 因为只吃 `PlayerChromeState` + `PlayerChromeCallbacks`，可以直接 pump。全部外观断言都挂在这里：

1. **横竖屏一致性**（本 spec 的核心断言）：用同一个 `PlayerChromeState`，分别在竖屏尺寸和横屏尺寸下 pump（`tester.view.physicalSize` / `devicePixelRatio`），断言两次渲染出**同一组按钮图标**、进度条为**同一个颜色**（等于 `colorScheme.primary`，且**不出现 `Color(0xFFFF0000)`**）、同一组圆角与字号。
2. **允许的差异是白名单**：横屏额外出现锁定按钮；除此之外不允许出现竖屏没有的控件。
3. **安全区**：给定非零的 `viewPadding.left/right`，断言横屏时控件被推离左右边缘，竖屏时不受影响。
4. **锁定**：`isLocked: true` 时只渲染解锁按钮，其它按钮全部不可见；点击解锁触发 `onToggleLock`。
5. **回调映射**：逐个按钮断言点击后触发对应回调（返回、播放/暂停、全屏、锁定、分集、倍速、清晰度、缓存）。
6. **自动隐藏**：`pump` 3 秒后控件不可见；单击后重新可见；`isSeeking: true` 时到点也不隐藏。
7. **常驻细进度条**：控件隐藏时仍渲染，且不拦截命中测试。
8. **时间显示**：给定 position/duration 渲染 `mm:ss / mm:ss`，且秒数变化时布局宽度不变。
9. **本地化**：分别以 `Locale('zh')` 和 `Locale('en')` pump，断言 HUD 与 tooltip 走 `AppLocalizations`（无硬编码中文）。

### 复用既有缝隙：`PlaybackMediaStrategy`

新增的纯判定逻辑（双击分区、竖向分区、方向决策、灵敏度、双击累加、边缘死区、3:1 方向锁）作为静态方法加到 `PlaybackMediaStrategy`，断言写进**已有的** `test/playback_media_strategy_test.dart`，**不新建纯逻辑测试文件**。重点用例：

- 竖屏视频（宽高比 < 1）全屏时**不请求横屏**；横屏视频请求横屏；退出全屏请求 `portraitUp` 而不是 `[]`。
- 双击 x 落在 24% / 50% / 76% 分别得到 backward / center / forward。
- 连续 3 次快进累加为 30 秒。
- 斜向位移（dx≈dy）不产生任何方向。
- 起点落在边缘 25px 内 → 拖拽不被接管。

### 不测的部分

`ScreenModeService` 是**没有分支的薄适配层**（判断都在 `PlaybackMediaStrategy` 里），只保留幂等守卫；不为它建平台通道测试替身。全屏的真实视觉效果（刘海、旋转、沉浸式）靠真机走查。

### 既有测试作为参照

- 纯逻辑风格：`test/playback_media_strategy_test.dart`、`test/playback_completion_strategy_test.dart`。
- Widget + 本地化风格：`test/settings_screen_test.dart`、`test/login_screen_test.dart`（`MaterialApp` + `AppLocalizations.localizationsDelegates` + 显式 `locale`）。

---

## 不在范围内 (Out of Scope)

- **设置项与持久化**：全屏方向策略、双击行为开关、长按倍速倍率、常驻进度条开关等一律使用固定默认值，**不进** `AppSettings` / `SettingsService` / 设置页。将来要做再单开一份 spec。
- **重力感应自动进出全屏**（`ref` 的 `NativeDeviceOrientation` 监听 + `isManualFS` 语义）。本次只做手动切换。
- 弹幕、字幕、投屏、PiP、截图/录屏、画面缩放与翻转、画面比例切换、键盘快捷键、SponsorBlock 分段、章节/看点、seek 预览缩略图（需要 `videoshot` 接口，且与"专注学习"的产品定位不符）。
- 播放地址协商、清晰度默认值、DASH 合成、下载、历史与断点续播、后台播放与通知栏——本次一行不动。
- **桌面端（Windows/Linux）全屏的验收**：保留现有的原生全屏调用并复用同一控件层，但本次只保证不回归，不做桌面视觉走查。
- 不迁移 GetX / Hive / `Obx`，不引入 `auto_orientation` 之类的方向辅助包。
- 不重构应用其它页面的硬编码颜色（`VideoTile` / `CommonImage` / `skeletons` 里那批浅色系遗留值），那是独立的一次清理。

---

## 其它说明 (Further Notes)

### 落地顺序建议

1. 先把 `PlayerChrome` + `PlayerChromeState` 抽出来，在**竖屏**下替换掉 `MaterialVideoControls`，跑通 Widget 测试回路（此时外观应与今天的竖屏基本一致）。
2. 再接管全屏（`ScreenModeService` + `PlaybackMediaStrategy` 的方向决策 + `GlobalKey` + `PopScope`），此时横竖屏一致性测试应该直接变绿。
3. 最后叠加锁定、分区手势、HUD 改版、常驻进度条、分集弹窗改版。

这样每一步都有独立可验证的绿灯，不会出现"改完一大片再一起调"的局面。

### 关键事实备查（`media_kit_video` 2.0.1）

- `MaterialVideoControlsTheme` 的 `normal` / `fullscreen` 是两个 required 的整体对象，**不合并、不 `copyWith` 继承**；在 `fullscreen` 里少写一个字段，拿到的是构造函数默认值。
- 构造函数默认：`seekBarPositionColor` / `seekBarThumbColor` = `Color(0xFFFF0000)`，`seekBarMargin` = `EdgeInsets.zero`，`seekBarHeight` = 2.4，`buttonBarHeight` = 56，`backdropColor` = `Color(0x66000000)`，`controlsHoverDuration` = 3s，`controlsTransitionDuration` = 300ms，`volumeGesture` / `brightnessGesture` / `seekGesture` / `seekOnDoubleTap` / `speedUpOnLongPress` 全为 `false`。
- `defaultEnterNativeFullscreen` 在移动端强制 `landscapeLeft/Right`；`defaultExitNativeFullscreen` 调用 `setPreferredOrientations([])`。
- `MaterialVideoControlsTheme` / `FullscreenInheritedWidget` / `VideoStateInheritedWidget` 的 `updateShouldNotify` 语义是反的（数据未变时返回 `true`）。

这四条是"为什么要把控件层拿回自己手里"的直接依据；实现时如果发现升级 `media_kit_video` 已修复其中某条，也不改变本 spec 的结论——单一控件树本身就是目标。

### 参考坐标（`ref/`）

- `lib/plugin/pl_player/view/view.dart` —— 单一控件层 + 手势层（分区判定、3:1 方向锁、25px 死区、seek 取消区）。
- `lib/plugin/pl_player/controller.dart` —— `triggerFullScreen` 的重入守卫与 `finally` 置位、`set controls` 与自动隐藏、`onPopInvokedWithResult` 的分层剥离、`changeOrientation` 的方向决策。
- `lib/plugin/pl_player/utils/fullscreen.dart` —— `SystemChrome` 的幂等守卫。
- `lib/plugin/pl_player/widgets/app_bar_ani.dart` —— 顶/底栏滑动 + 渐变蒙层 + `ViewSafeArea`。
- `lib/plugin/pl_player/view/widgets.dart` —— 不抖动的两行时间渲染。
- `lib/common/widgets/progress_bar/audio_video_progress_bar.dart` —— 两个实例、不同命中测试的进度条。

按 `docs/codebase-optimization-audit.md` 的既定原则：**借鉴它验证过的缝隙与机制，不复制它的规模、全局状态与大型控制器。**

### 文档现状

仓库当前没有 `CONTEXT.md`，也没有 `docs/adr/`，因此本 spec 不与任何已有 ADR 冲突。若后续引入 ADR 目录，建议把「播放器控件层单一化 + 应用自管全屏」记为第一条播放器领域的决策。
