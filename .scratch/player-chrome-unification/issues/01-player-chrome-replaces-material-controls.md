# 01: 控件层落地——PlayerChrome 取代 MaterialVideoControls

**What to build:** 播放器的控件层变成应用自己的东西。用户在竖屏下看到的播放器和今天基本一样——顶部一行返回、标题、分集、倍速、缓存、清晰度，中央播放/暂停键，底部一条青色可拖动的进度条，点一下画面切换显隐、几秒不动自动隐藏——但它已经不再是 media_kit 的内建控件，而是一个只吃不可变状态、只吐回调的应用自有控件层。全屏按钮改成播放页自己的一个标志：按下去画面原地铺满（本票**不**改变屏幕方向），不再往根导航上 push 任何路由，media_kit 的两份 `normal` / `fullscreen` ThemeData 一并删除。做完这一票，"横竖屏一致"就已经是结构上成立的事实，横竖屏一致性测试应当在这里变绿。

**Blocked by:** None (can start immediately)

**Status:** done

- [x] 播放页不再构造 `MaterialVideoControlsTheme` / `MaterialVideoControls`，也不再调用 media_kit 的 `toggleFullscreen`；视频组件降级为纯纹理（不带内建控件）
- [x] `PlayerChrome` 不 import `media_kit` / `media_kit_video`，输入只有不可变的 `PlayerChromeState` 与 `PlayerChromeCallbacks`
- [x] 横竖屏渲染同一组顶栏按钮、同样顺序：返回、标题（多 P 时带 P 序号与分集名）、分集列表、倍速、缓存、清晰度
- [x] 中央播放/暂停键与可拖动进度条就位；进度条与 thumb 取 `colorScheme.primary`，渲染树中不出现 `Color(0xFFFF0000)`
- [x] 进度条允许先用最简实现（可拖动 + 正确配色 + 正确边距），精修留给 03
- [x] 单击画面切换控件显隐；3 秒无操作自动隐藏；拖动进度条期间不自动隐藏
- [x] 全屏按钮切换播放页内的 `isFullscreen` 标志，画面原地铺满；不 push 路由，不改变屏幕方向
- [x] 既有行为不回归：播放、暂停、拖动、切分集、切倍速、切清晰度、缓存、返回、断点续播提示、播完自动下一集
- [x] Widget 测试：同一状态在竖屏与横屏尺寸下渲染出同一组按钮图标、同一进度条配色、同一圆角与字号
- [x] Widget 测试：逐个按钮点击触发对应回调（返回、播放/暂停、全屏、分集、倍速、清晰度、缓存）
- [x] Widget 测试：`zh` 与 `en` 两种 locale 下控件文案与 tooltip 均来自 `AppLocalizations`，无硬编码中文
- [x] `flutter analyze` 0 issues，`flutter test` 全绿
