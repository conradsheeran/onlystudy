# 01 - 单设备扫码登录：切回 App 后登录界面无反应

Status: proposed
优先级: P1

## 症状

单台设备上：截图登录二维码 → 切到 B 站 App 扫码确认 → 切回唯学。登录界面停在原状态，不前进。用第二台设备扫码则正常。

## 根因

### 主因：`_pollInFlight` 闩锁 + Dio 无超时 = 永久停摆

`lib/screens/login_screen.dart:_startPolling()`：

```dart
if (_pollInFlight) return;
_pollInFlight = true;
try {
  final result = await _authService.pollLoginTyped(_authCode!);
  ...
} finally {
  _pollInFlight = false;
}
```

`finally` 只有在 `pollLoginTyped` 的 Future **完成或抛错**时才跑。而 `lib/services/auth_service.dart` 里 `AuthService` 自己那个 Dio 的 `BaseOptions` **没有 `connectTimeout` / `receiveTimeout` / `sendTimeout`**：

```dart
_dio = Dio(BaseOptions(
  baseUrl: 'https://passport.bilibili.com',
  headers: { ... },   // ← 没有任何 timeout
));
```

对比 `lib/services/bili_http_client.dart:35-36`，那边是有 10 秒超时的 —— 只有登录这条路漏了。

App 被切到后台时，Android 会挂起进程并可能回收/冻结正在使用的 socket。此时如果正好有一次 poll 在途，这个请求可能**永远不返回也不抛错**。于是 `_pollInFlight` 永久卡在 `true`，之后每 3 秒的 tick 全部在第一行 `return` 掉。登录界面就此彻底失去反应 —— **和用户描述完全吻合**。

用第二台设备扫码时不需要切后台，进程不挂起，socket 不断，所以没事。

### 次因：没有生命周期监听

即便请求没卡死，回到前台后也要等下一个 3 秒 tick。`ref` 用的是 **1 秒**间隔（`ref/lib/pages/login/controller.dart:78`），并且我们这里完全没有 `didChangeAppLifecycleState`，回前台不会立刻补一次轮询。

### 次因：单设备场景没有产品出口

界面只有一个二维码。单设备用户被迫"截图 → 切走 → 相册扫码 → 切回"，这个动线本身就把 App 推进了会触发主因的路径。

## 修复方案

### 主修 1：给 AuthService 的 Dio 加超时

```dart
_dio = Dio(BaseOptions(
  baseUrl: 'https://passport.bilibili.com',
  connectTimeout: const Duration(seconds: 10),
  receiveTimeout: const Duration(seconds: 10),
  sendTimeout: const Duration(seconds: 10),
  headers: { ... },
));
```

这一条单独就能让系统自愈：最坏情况 10 秒后抛 `DioException`，`finally` 复位闩锁，轮询恢复。

### 主修 2：闩锁改为带时间戳的看门狗（纵深防御）

不要只依赖超时。把 `bool _pollInFlight` 换成 `DateTime? _pollStartedAt`：

```dart
static const _pollStuckAfter = Duration(seconds: 15);

final startedAt = _pollStartedAt;
if (startedAt != null && DateTime.now().difference(startedAt) < _pollStuckAfter) {
  return;   // 正常在途，跳过
}
// 超过 15 秒视为卡死：放弃旧请求（它的结果由 generation 号丢弃），发起新的
_pollStartedAt = DateTime.now();
```

配合一个 `int _pollGeneration`，回调里 `if (gen != _pollGeneration) return;` 丢弃过期响应，避免两个请求的结果互相覆盖。

### 主修 3：监听生命周期，回前台立即轮询一次

`_LoginScreenState` 混入 `WidgetsBindingObserver`：

```dart
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state != AppLifecycleState.resumed) return;
  _pollStartedAt = null;     // 主动打掉可能已死的在途请求
  _pollGeneration++;
  _pollOnce();               // 从 Timer 回调里抽出来的独立方法
}
```

记得 `initState` 里 `addObserver(this)`、`dispose` 里 `removeObserver(this)`。

### 主修 4：轮询间隔 3s → 1.5s，并显示二维码剩余有效期

二维码有效期 180 秒。`ref` 每秒轮询并倒计时展示（`qrCodeLeftTime`）。我们至少应该：
- 间隔降到 1.5 秒；
- 显示"二维码剩余 xx 秒"，到期自动切 `_isExpired`，而不是只等服务端返回 86038。

截图—切走—扫码—切回这套动线很容易吃掉 60 秒以上，用户需要看到还剩多久。

### 次修：给单设备用户一条正路

在二维码下方加一个「用本机哔哩哔哩 App 扫码」按钮，用 `url_launcher` 直接拉起二维码里那个 URL：

```dart
await launchUrl(Uri.parse(_qrUrl!), mode: LaunchMode.externalApplication);
```

B 站 App 已安装时会接管这个 passport 链接并直接展示确认页，省掉"截图 + 相册扫码"。回到前台时主修 3 会立刻补一次轮询，确认结果几乎是瞬时的。

未安装 B 站 App 时 `launchUrl` 会失败，需要捕获并回退到"请用其他设备扫码"的提示。

## 验证回路（先建再改）

**回路 A（单测，秒级，直接打中主因）**：`AuthService` 已经有 `@visibleForTesting set dioForTest`，注入一个**永不完成**的 fake adapter：

```dart
test('poll 请求挂起时轮询能自愈', () async {
  // fake Dio：第一次请求返回一个永不 complete 的 Future，
  // 之后的请求正常返回已确认状态。
  // 断言：登录界面在 <20 秒模拟时间内仍能走到 QrLoginConfirmed。
});
```

修复前这个测试会超时（闩锁永久 true），修复后通过。用 `fakeAsync` 让它跑在毫秒级。

**回路 B（真机，验证完整动线）**：飞行模式切换模拟 socket 断裂 —— 打开登录页 → 立刻开飞行模式 5 秒 → 关掉 → 界面应在数秒内恢复轮询（状态文案变化即可观察）。

**回路 C（真机，原始场景）**：单设备完整走一遍截图 → 切走 → 扫码 → 切回。

## 注意

- 轮询与登录相关的日志/错误文案里**不要打印 `auth_code`、`SESSDATA`、`bili_jct`、`refresh_token`**。当前 `debugPrint('QR poll error: $e')` 打的是 DioException，可能带上完整 query（含 `auth_code` 和 `sign`），建议改成只打 `e.runtimeType` 与状态码。
