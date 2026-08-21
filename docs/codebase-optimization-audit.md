# onlystudy 代码库优化审查

> 审查日期：2026-08-20  
> onlystudy 基线：`acbd6ec` (`style(login): apply dart format`)  
> 参考仓库基线：`ref/` 的 `e09754991` (`fix ios bottom sheet patch`)

## 1. 文档目的

本文记录对 onlystudy 与 `ref/` 参考仓库的静态审查结果，供后续按优先级拆分 Issue、设计迁移方案和实施修复。

本文不是要求照搬参考仓库。onlystudy 与参考仓库的规模、产品目标和维护成本差异很大：

- onlystudy 约有 35 个手写 Dart 文件、约 8,000 行手写 Dart 代码（不含生成的本地化文件）。
- `ref/` 约有 1,298 个 Dart 文件，其中包含大量生成的 gRPC 代码和完整第三方客户端功能。
- onlystudy 已有 18 个测试；`ref/` 当前未发现 `test/` 目录。

因此，本审查的核心原则是：**借鉴参考仓库已经验证过的模块缝隙和可靠性机制，不复制其规模、全局状态和大型控制器。**

---

## 2. 当前基线与优点

审查时验证结果：

```text
flutter analyze: 0 issues
flutter test: 18/18 passed
```

当前仓库已有以下良好基础：

1. 项目规模较小，关键路径容易定位。
2. Bilibili 业务请求基本集中在 `BiliApiService`，没有散落在大量页面中。
3. 已建立 `models / services / screens / widgets` 的基本分层。
4. 已接入 ARB 生成式本地化。
5. 已覆盖 Android、Windows、Linux 发布构建。
6. 已为登录凭据解析、历史记录、更新检查和部分设置流程添加测试。
7. 已完成 app 端二维码登录迁移，并在 `bd2e127` 修复 `auth_code` 字段读取问题。
8. 使用 `IndexedStack` 保持主页面标签状态，符合当前产品形态。
9. 桌面端数据库已使用 `sqflite_common_ffi`。

后续优化应保持这些优点，尤其不要因为参考仓库使用 GetX、Hive 或大型控制器就进行无收益的框架迁移。

---

## 3. 参考仓库中值得借鉴的做法

### 3.1 类型化的二维码登录接口

参考位置：

- `ref/lib/http/login.dart`
- `ref/lib/pages/login/controller.dart`

参考仓库在取得二维码后立即把动态 JSON 转换为类型化记录：

```dart
Future<LoadingState<({String authCode, String url})>> getHDcode()
```

它还使用 `_isReq` 防止定时器触发重叠轮询。

onlystudy 最近发生过 `qrcode_key` 与 `auth_code` 字段不一致的回归。该问题已经修复，但说明 `Map<String, dynamic>` 是过于脆弱的模块接口。

### 3.2 统一网络传输模块

参考位置：

- `ref/lib/http/init.dart`
- `ref/lib/utils/accounts/account_manager/account_mgr.dart`

值得借鉴：

- 集中设置超时、请求头和拦截器。
- 账号 Cookie 由账号模块统一注入。
- 网络重试、连接变化和响应解码集中处理。

不应照搬：

- 忽略 TLS 证书错误。
- 捕获网络异常后伪装成普通 `Response`。
- 当前产品不需要的 HTTP/2、代理和 Brotli 复杂度。

### 3.3 通用异步和分页状态

参考位置：

- `ref/lib/http/loading_state.dart`
- `ref/lib/pages/common/common_list_controller.dart`

参考仓库将加载状态建模为 sealed 类型，并集中处理：

- 刷新。
- 加载下一页。
- 页码递增。
- 是否结束。
- 首屏错误和追加错误。
- 重复请求抑制。

该模式非常适合替换 onlystudy 多个页面中重复的 `_page / _hasMore / _isLoading / _error` 状态。

### 3.4 分离账号、设置、缓存和历史存储

参考位置：

- `ref/lib/utils/storage.dart`
- `ref/lib/utils/storage_pref.dart`
- `ref/lib/services/account_service.dart`
- `ref/lib/utils/accounts/`

参考仓库使用不同存储区域管理：

- 账号。
- 设置。
- 本地缓存。
- 视频设置。
- 播放进度。

这种“按数据生命周期和作用域分离”的思路值得采用。是否使用 Hive 并不重要，关键是不要让注销通过一次全局 `clear()` 清除所有数据。

### 3.5 可取消、可续传的下载模块

参考位置：

- `ref/lib/services/download/download_manager.dart`
- `ref/lib/services/download/download_service.dart`

值得借鉴：

- `CancelToken`。
- Range 续传。
- 等待队列。
- 当前任务。
- 暂停、失败和完成状态。
- 下载元数据持久化。
- 音视频轨道分别下载。
- 取消当前任务后继续队列。

### 3.6 集中的路由表

参考位置：

- `ref/lib/router/app_pages.dart`

集中路由可以避免页面之间相互 import，降低导航环依赖。onlystudy 不需要采用 GetX 字符串路由，但可以建立类型化 `AppNavigator` 或 Flutter 原生路由表。

### 3.7 可复现的 Flutter 工具链

参考位置：

- `ref/.fvmrc`
- `ref/pubspec.yaml`
- `ref/.github/workflows/build.yml`

参考仓库把 Flutter 版本写入仓库，并在 PR 上执行构建。onlystudy 当前只在 tag 发布时运行 CI，可借鉴其版本固定和 PR 验证思路。

---

## 4. 优化发现总览

| ID | 优先级 | 主题 | 主要影响 |
| --- | --- | --- | --- |
| OPT-001 | 高 | 下载任务生命周期 | 任务无法可靠取消、恢复或重试，可能产生孤儿文件 |
| OPT-002 | 高 | 搜索数据库关系模型 | 同一视频的多收藏夹/合集归属会被覆盖 |
| OPT-003 | 高 | 播放进度状态竞争 | 分集切换时可能把旧进度写入新分集 |
| OPT-004 | 高 | 清晰度切换丢失音频地址 | 多次 DASH 清晰度切换可能失去音轨 |
| OPT-005 | 高 | 注销清除全部偏好 | 语言、设置、锁和历史被一并删除 |
| OPT-006 | 高 | 登录协议动态类型和轮询重叠 | 字段漂移只能在运行时发现，轮询可能并发 |
| OPT-007 | 中高 | 网络传输重复 | 四个 Dio 客户端行为不一致，错误无法统一处理 |
| OPT-008 | 中高 | 页面重复分页状态 | 请求竞争和错误处理在多个页面重复实现 |
| OPT-009 | 中高 | HomeScreen 职责过多 | 数据同步、搜索、锁定和 UI 高耦合 |
| OPT-010 | 中高 | 图片内存缓存 500 MiB | 移动端内存压力和 OOM 风险 |
| OPT-011 | 中 | 启动流程缺少错误状态 | 初始化失败可能造成启动中断或后续延迟崩溃 |
| OPT-012 | 中 | 全局单例和模块环依赖 | 测试替身难注入，播放模块存在双向 import |
| OPT-013 | 中 | 页面导航环依赖 | 页面直接相互 import，导航与页面实现耦合 |
| OPT-014 | 中 | 设置与更新模块接口 | 设置通知不统一，更新服务直接持有 UI 上下文 |
| OPT-015 | 中 | CI、版本和 lint | PR 没有质量门禁，工具链版本说明不一致 |
| OPT-016 | 中 | 依赖维护 | 存在未使用和 discontinued 依赖 |
| OPT-017 | 中 | 本地化不完整 | 英文界面可能出现中文服务错误和硬编码文本 |
| OPT-018 | 中 | 关键路径测试不足 | 下载、数据库、网络、分页和播放器缺少行为测试 |
| OPT-019 | 低 | README 与实际能力漂移 | 构建版本、功能状态和下载能力描述已过时 |

---

## 5. 详细发现

## OPT-001：下载任务生命周期不可靠

**优先级：高**

涉及文件：

- `lib/services/download_service.dart`
- `lib/screens/download_screen.dart`
- `lib/models/download_task.dart`

### 现状

1. `startDownload()` 创建记录后直接调用 `_executeDownload()`，没有返回或跟踪实际下载 Future。
2. 没有 `CancelToken`。
3. 没有下载队列和并发上限。
4. 没有暂停、续传和真正的重试入口。
5. `_updateProgress()` 只更新内存，不持久化进度。
6. 应用异常退出后，数据库中的 `running` 任务仍保持 `running`。
7. 初始化数据库失败时异常被 `debugPrint` 后吞掉，但后续 `_insertOrUpdateTask()` 仍可能访问 `_db!`。
8. 只要任务已存在，`startDownload()` 就直接返回；失败任务不能重新开始。
9. 下载直接写最终文件路径，没有 `.part` 临时文件和原子完成动作。
10. 删除进行中的任务不会取消 Dio 请求，下载可能继续写文件并留下孤儿文件。
11. 下载页面中失败任务的刷新按钮只调用 `deleteTask()`，行为与图标语义不一致。
12. `DownloadStatus.paused` 已存在，但当前没有对应实现。
13. 当前下载解析主要假定单 MP4 地址，而 Bilibili 较高清晰度经常使用 DASH 音视频双轨。

### 影响

- 用户无法可靠暂停或重试任务。
- 关闭应用后任务状态可能失真。
- 删除任务可能不能真正停止下载。
- 文件系统与数据库可能不一致。
- 并发下载可能导致网络、磁盘和内存压力。

### 建议接口

建立深模块 `DownloadCoordinator`：

```dart
abstract interface class DownloadCoordinator {
  Stream<List<DownloadTask>> watchTasks();
  Future<void> enqueue(DownloadRequest request);
  Future<void> pause(DownloadId id);
  Future<void> resume(DownloadId id);
  Future<void> retry(DownloadId id);
  Future<void> delete(DownloadId id);
}
```

内部负责：

- 有界队列。
- `CancelToken`。
- Range 续传。
- `.part` 文件。
- 启动时把遗留 `running` 状态恢复为 `paused`，或自动续传。
- 持久化 downloadedBytes、totalBytes、失败类型和重试次数。
- 成功后原子重命名。
- 音视频双轨下载及离线播放元数据。

### 验证建议

- 使用本地 HTTP Server 测试 Range 请求。
- 测试取消后文件不再增长。
- 测试进程重启后任务恢复。
- 测试失败任务可重试。
- 测试删除进行中任务不产生孤儿文件。
- 测试多任务严格遵守并发上限。

---

## OPT-002：视频缓存表无法表达多来源关系

**优先级：高**

涉及文件：

- `lib/services/database_service.dart`
- `lib/screens/home_screen.dart`
- `lib/screens/select_folders_screen.dart`

### 现状

`videos` 表使用：

```sql
bvid TEXT PRIMARY KEY
```

写入使用：

```dart
ConflictAlgorithm.replace
```

同一个视频如果属于多个收藏夹、一个收藏夹和一个合集，后一次写入会覆盖前一次的 `folder_id` 或 `season_id`。

另外：

1. 数据库没有 `up_id` 或通用来源表。
2. 用户已经可以选择 UP 主，但 UP 视频不会被 Home 后台同步到搜索数据库。
3. 本地搜索仅接受 `visibleFolderIds` 和 `visibleSeasonIds`。
4. Home 后台同步只抓取每个收藏夹和合集的第一页。
5. 视频缓存没有来源索引和迁移测试。
6. 设置页面“清理缓存”只清理文件缓存，不清理搜索数据库；用户对“缓存”的理解可能与实际不一致。

### 影响

- 搜索结果可能遗漏属于多个来源的视频。
- UP 主选择与搜索能力不一致。
- 搜索完整性依赖插入顺序。
- 缓存清理语义不清晰。

### 建议数据库 v3

```sql
CREATE TABLE videos(
  bvid TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  cover TEXT,
  upper_id INTEGER,
  upper_name TEXT,
  json_data TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE TABLE video_sources(
  bvid TEXT NOT NULL,
  source_type TEXT NOT NULL,
  source_id INTEGER NOT NULL,
  synced_at INTEGER NOT NULL,
  PRIMARY KEY (bvid, source_type, source_id),
  FOREIGN KEY (bvid) REFERENCES videos(bvid) ON DELETE CASCADE
);

CREATE INDEX video_sources_by_source
ON video_sources(source_type, source_id);
```

`source_type` 至少支持：

- `folder`
- `season`
- `up`

数据量增长后可评估 FTS5；当前阶段普通 `LIKE` 仍可继续使用。

### 需要先做的产品决定

搜索缓存范围属于用户可见行为，迁移前需要明确：

1. 仅同步首屏，强调快速但不完整；或
2. 后台渐进同步全部所选来源；或
3. 本地优先，搜索无结果时允许显式远程补充。

不得在纯数据库重构中静默改变该行为。

### 验证建议

- 同一 bvid 同时属于两个收藏夹时，两种筛选都能命中。
- 收藏夹和合集共享视频时不丢失任一来源。
- UP 来源可以单独筛选。
- v2 到 v3 迁移不会丢失现有视频数据。
- `clearFolderCache()` 只删除关系；无任何来源的视频再删除主体记录。

---

## OPT-003：播放进度保存存在状态竞争

**优先级：高**

涉及文件：

- `lib/screens/video_player_screen.dart`
- `lib/services/history_service.dart`

### 现状

以下流程会先启动 `_saveProgress()`，随后立即修改当前视频或分集状态：

- `_checkVideoEnd()`
- `_playNext()`
- `_switchPart()`

`_saveProgress()` 会：

1. 读取当前位置。
2. 等待 Bilibili 历史上报。
3. 再调用 `_syncHistoryContext()`。

第 3 步仍读取可变字段：

- `_currentVideo`
- `_cid`
- `_videoDetail`
- `_currentPageNumber`
- `_currentPartTitle`

网络等待期间这些字段可能已经切换，因此旧分集的进度可能写入新分集。

另外，5 秒周期保存可能重叠。`HistoryService` 每次都是 SharedPreferences 全列表的读取—修改—写入，不是原子事务，并发保存可能互相覆盖。

### 建议

在任何 `await` 之前创建不可变快照：

```dart
final snapshot = PlaybackProgressSnapshot(
  video: currentVideo,
  aid: aid,
  cid: cid,
  page: page,
  partTitle: partTitle,
  duration: duration,
  seconds: position,
);
```

保存逻辑只能使用快照，不再读取播放器页面的可变状态。

同时：

- 串行化保存命令，或只保留最后一个待保存快照。
- 页面切换前可先获取快照，再允许状态变化。
- 本地历史应优先快速写入，远程上报可以独立失败，不应阻塞本地保存。
- 如果历史继续使用 SharedPreferences，至少增加互斥锁；更稳妥的是迁移到现有 sqflite。

### 验证建议

- 模拟远程上报延迟，在上报期间切换分集，验证旧进度仍写入旧 cid。
- 连续快速切换视频时，不发生跨视频覆盖。
- 两次并发保存不会丢失较新的进度。

---

## OPT-004：清晰度切换会丢弃 DASH 音频地址

**优先级：高**

涉及文件：

- `lib/screens/video_player_screen.dart`
- `lib/models/bili_models.dart`

### 现状

`_switchQuality()` 获取 `newInfo` 后手工创建 `updatedInfo`，只复制：

- url
- quality
- acceptQuality
- acceptDescription

没有复制 `audioUrl`。

第一次切换时 `_setupController()` 仍可能使用旧 `_playInfo.audioUrl`；随后 `_playInfo` 被替换为没有音频地址的 `updatedInfo`。再次切换时就可能无法设置 DASH 音轨。

此外，`VideoPlayInfo.fromJson()` 在 DASH 视频列表中直接选择第一个视频轨道，没有显式按返回的 `quality` 或轨道 id 选择，后续需要通过真实响应 fixture 验证其排序假设。

### 建议

- 清晰度切换直接保留完整 `newInfo`。
- 如果需要保留旧的可选清晰度描述，使用完整 `copyWith()`，不得遗漏音频、备选 URL 或编码信息。
- 将播放地址解析改为类型化 DASH/Progressive 模型。
- 快速连续切换清晰度时使用请求世代号或 CancelToken，避免旧响应覆盖新选择。

### 验证建议

- 使用带 DASH 视频和音频轨的固定 JSON fixture。
- 连续切换两次清晰度后仍设置正确音轨。
- 先发起低清晰度请求、后发起高清晰度请求，旧请求晚返回时不得覆盖新状态。

---

## OPT-005：AuthService 混合多个数据生命周期，注销清除全部偏好

**优先级：高**

涉及文件：

- `lib/services/auth_service.dart`
- `lib/services/settings_service.dart`
- `lib/services/history_service.dart`
- `lib/screens/settings_screen.dart`

### 现状

`AuthService` 同时负责：

- 二维码登录网络请求。
- 登录凭据解析。
- Cookie、CSRF、refresh token。
- 收藏夹锁密码。
- 锁定状态。
- 可见收藏夹、合集和 UP 主。
- 注销。

`logout()` 调用：

```dart
await prefs.clear();
```

这会同时清除：

- 登录凭据。
- 语言。
- 默认清晰度。
- 默认倍速。
- 后台播放设置。
- 更新设置。
- 锁密码和锁状态。
- 内容选择。
- 本地历史。
- 文件缓存清理时间戳。

但 `SettingsService` 已加载的内存字段不会同步清空。因此用户可能在当前进程继续看到旧设置，下次启动才恢复默认值。

### 建议模块

- `LoginGateway`：只负责登录协议。
- `CredentialStore`：只负责敏感凭据。
- `AccountSession`：登录状态与注销流程。
- `ContentSelectionStore`：可见来源。
- `FocusLockStore`：锁密码和锁状态。
- `AppSettingsStore`：应用级设置。
- `HistoryStore`：历史作用域。

注销应显式删除账号凭据，不使用全局 `clear()`。

### 需要先做的产品决定

- 历史记录是全局还是按账号隔离？
- 下载内容是全局还是按账号隔离？
- 内容选择是否在切换账号时保留？
- 锁密码是设备级还是账号级？

### 安全说明

- `SESSDATA`、CSRF 和 refresh token 当前存储在 SharedPreferences，不属于安全存储。
- 锁密码当前是无盐 SHA-256，适合作为“防分心提示”，不适合作为真正安全访问控制。

若要保护会话凭据，应使用平台 Keychain/Keystore 等安全存储。该调整会增加新运行时依赖，实施前应单独评估迁移和桌面端支持。

---

## OPT-006：登录接口动态类型且轮询可能重叠

**优先级：高**

涉及文件：

- `lib/services/auth_service.dart`
- `lib/screens/login_screen.dart`
- `test/auth_service_test.dart`

### 现状

`generateQRCode()` 返回动态 Map。最近 `auth_code` 字段问题说明 JSON 字段漂移不能被编译器发现。

轮询使用：

```dart
Timer.periodic(..., (timer) async { ... });
```

如果一次请求超过 3 秒，下一次 tick 会开始第二个请求。可能产生：

- 重复 poll。
- 重复保存登录信息。
- 重复导航。
- 过期与成功状态竞争。

过期判断目前依赖异常字符串是否包含“过期”，也会把协议状态与本地化文案耦合。

### 建议接口

```dart
class QrLoginChallenge {
  final Uri url;
  final String authCode;
}

sealed class QrLoginPollResult {
  const QrLoginPollResult();
}

class QrLoginPending extends QrLoginPollResult {}
class QrLoginConfirmed extends QrLoginPollResult {
  final LoginCredentials credentials;
}
class QrLoginExpired extends QrLoginPollResult {}
```

轮询应选择以下任一方式：

1. `_pollInFlight` 防重入；或
2. 一次请求完成后再 `Future.delayed()` 开始下一次；或
3. 将完整状态机放入 `QrLoginController`。

### 测试问题

当前名称为“签名确定性”的测试实际上只检查 buvid 格式，没有验证 `_appSign` 结果。应把签名逻辑提取为可直接测试的纯模块，并使用固定 timestamp 和已知签名向量。

### 验证建议

- challenge JSON 缺少 `auth_code` 时返回明确解析失败。
- 请求持续超过轮询间隔时，最大并发请求数仍为 1。
- 成功只触发一次保存和一次导航。
- 过期使用类型判断，不检查中文字符串。

---

## OPT-007：存在四个独立 Dio 客户端

**优先级：中高**

涉及文件：

- `lib/services/auth_service.dart`
- `lib/services/bili_api_service.dart`
- `lib/services/download_service.dart`
- `lib/services/update_service.dart`

### 现状

每个模块各自创建 Dio，导致以下内容重复或不一致：

- User-Agent。
- Referer。
- Cookie。
- 超时。
- 状态码验证。
- Bilibili `code/message` 处理。
- 网络错误展示。
- 取消请求。

`BiliApiService` 多个方法重复：

1. 创建 Options。
2. 添加 Cookie。
3. 发请求。
4. 检查 `response.data['code']`。
5. 抛中文 `Exception`。
6. 某些方法额外使用无意义的 `catch (e) { rethrow; }`。

### 建议

建立最小 `BiliHttpClient`：

- 统一 BaseOptions 和超时。
- 通过 `CredentialStore` 注入 Cookie。
- 统一请求取消。
- 将 DioException、HTTP 错误和 Bilibili 业务错误转换为结构化 `BiliFailure`。
- 服务层返回错误类型或抛领域异常，不包含本地化文案。

领域模块按能力组织：

- `FavoritesCatalog`
- `UpLibrary`
- `PlaybackGateway`
- `HistoryReporter`
- `LoginGateway`

不要为每个端点建立一个只有一行转发逻辑的浅模块；只有能够隐藏签名、分页、fallback 和解析复杂度的模块才值得存在。

### 额外问题

`getSeasonVideos()` 会吞掉第一个收藏夹端点的所有异常再尝试另一个端点。Fallback 可以保留，但应记录“端点不适用”和“真实网络失败”的区别，避免网络故障被误判为正常 fallback。

---

## OPT-008：分页和异步加载逻辑重复

**优先级：中高**

涉及文件：

- `lib/screens/folder_content_screen.dart`
- `lib/screens/season_content_screen.dart`
- `lib/screens/up_space_screen.dart`
- `lib/screens/select_folders_screen.dart`
- `lib/screens/home_screen.dart`

### 现状

多个页面重复维护：

- `_page`
- `_hasMore`
- `_isLoading`
- `_isLoadingMore`
- `_error`
- ScrollController 触底判断
- refresh
- 首屏错误
- 加载更多 SnackBar
- mounted 检查

`folder_content_screen.dart` 与 `season_content_screen.dart` 的加载逻辑几乎相同。

重复实现容易产生：

- 页码递增规则不一致。
- 快速刷新时旧响应覆盖新响应。
- 页面销毁后 setState。
- 追加失败后状态无法恢复。
- 搜索条件变化与旧请求竞争。

### 建议模块

无需引入新的状态管理框架。可以实现：

```dart
sealed class PagedState<T> {
  const PagedState();
}

class PagedLoader<T> extends ValueNotifier<PagedState<T>> {
  Future<void> refresh();
  Future<void> loadNext();
  void dispose();
}
```

内部隐藏：

- 页码。
- 是否结束。
- 当前请求。
- 请求世代号。
- refresh/loadMore 区分。
- 列表合并。
- 去重。
- 错误类型。

页面测试和模块测试都通过该接口完成。

---

## OPT-009：HomeScreen 是数据、同步、锁和 UI 的混合模块

**优先级：中高**

涉及文件：

- `lib/screens/home_screen.dart`

### 现状

约 685 行的 State 同时负责：

- 加载可见 ID。
- 收藏夹分页扫描。
- 合集分页扫描。
- UP 信息加载。
- 数据库后台同步。
- 本地搜索。
- 搜索防抖。
- 锁定状态和密码对话框。
- 响应式布局。
- 页面导航。

具体风险：

1. `_items` 使用 `List<dynamic>`，错误只能在运行时发现。
2. 收藏夹和合集加载最多扫描 5 页；选择的项目超过该范围时可能静默消失。
3. UP 信息逐个串行请求，所选 UP 较多时首屏变慢。
4. `_syncAllContent()` 与 Widget `mounted` 生命周期耦合，不是独立同步任务。
5. 后台同步仅第一页，但 UI 没有明确说明搜索不完整。
6. Folder、Season、FollowUser 在构建时临时转换为 FolderCard 数据。
7. `_initData()` 多次 await 后直接 setState，缺少统一的 mounted/取消策略。

### 建议模块

```text
HomeLibraryController
  - loadVisibleLibrary()
  - refresh()
  - search(query)
  - lock/unlock state

LibrarySyncCoordinator
  - syncSelectedSources()
  - report progress/status

sealed LibraryItem
  - FolderItem
  - SeasonItem
  - UpItem
```

UI 只负责：

- 渲染 `HomeLibraryState`。
- 响应式布局。
- 导航。
- 调用锁定/刷新/搜索命令。

不要只把现有方法搬到一个新文件；新模块应隐藏分页扫描、并发、缓存和错误恢复。

### SelectFoldersScreen 相关问题

- 收藏夹和合集在进入页面时全量串行加载，列表很多时首屏延迟明显。
- 首次登录默认全选 UP 主时，实际只会选中当前已加载的第一页 UP。
- “全选”同样只覆盖已加载的 UP。
- 收藏夹、合集和 UP 加载可在确认依赖后并行或分别分页显示。

---

## OPT-010：全局解码图片缓存被提高到 500 MiB

**优先级：中高**

涉及文件：

- `lib/main.dart`
- `lib/widgets/common_image.dart`
- `lib/services/cache_service.dart`

### 现状

onlystudy 设置：

```dart
PaintingBinding.instance.imageCache.maximumSizeBytes = 500 * 1024 * 1024;
```

当前 Flutter 3.38.4 的默认值是 100 MiB。该缓存保存的是解码后的内存图片，不是磁盘缓存。移动设备允许 500 MiB 容易增加 OOM 或被系统终止的风险。

`CommonImage` 还会：

1. 先调用 `DefaultCacheManager().getFileFromCache()`。
2. 再构建 `CachedNetworkImage`，由后者执行自己的缓存流程。

这仅为判断淡入时长增加了一次磁盘缓存查询。变量名 `isCachedInMemory` 实际判断的是文件缓存，也容易误导维护者。

### 建议

- 删除 500 MiB 覆盖，先使用 Flutter 默认值。
- 如确有性能证据，再按移动端和桌面端设置不同预算。
- 缩略图使用 `memCacheWidth` / `memCacheHeight`，避免按原图尺寸解码。
- 移除额外的 `FutureBuilder + getFileFromCache`。
- 统一创建 CacheManager 实例，不在每个组件中重复构造。
- 将“图片文件缓存”“搜索数据库缓存”“下载文件”在 UI 中使用不同名称和清理操作。

### 验证建议

- 在大量封面滚动场景记录峰值 RSS 和栅格线程耗时。
- Android 低内存设备上进行长列表压力测试。
- 验证清理图片缓存不会误导用户认为搜索数据库或下载也被清理。

---

## OPT-011：启动流程缺少显式错误状态

**优先级：中**

涉及文件：

- `lib/main.dart`
- `lib/services/download_service.dart`
- `lib/services/cache_service.dart`
- `lib/services/settings_service.dart`
- `lib/services/audio_handler.dart`

### 现状

`main()` 在 `runApp()` 前执行多个异步初始化。任一未处理异常都可能阻止 UI 启动。部分模块则吞掉异常，导致应用进入“看似启动成功、首次使用时再崩溃”的半初始化状态。

项目约束已明确启动顺序具有意义：

```text
MediaKit.ensureInitialized()
→ DownloadService.init()
→ CacheService.checkAndClearCache()
→ initAudioService()
→ SettingsService.init()
→ auth check
```

优化不能盲目使用 `Future.wait()` 打乱该顺序。

### 建议

建立 `AppBootstrapper`，保留当前顺序并返回类型化结果：

```dart
sealed class BootstrapResult {}
class BootstrapReady extends BootstrapResult { ... }
class BootstrapFailed extends BootstrapResult {
  final BootstrapPhase phase;
  final Object error;
}
```

启动时先运行一个最小 `BootstrapApp`，显示：

- 初始化状态。
- 失败阶段。
- 重试入口。
- 可选的本地日志导出。

只有经过证据确认相互独立的初始化步骤才并行。

### 全局错误处理

可增加：

- `FlutterError.onError`
- `PlatformDispatcher.instance.onError`
- `runZonedGuarded`

是否接入第三方崩溃遥测涉及隐私和新依赖，应单独决定；本地日志已经可以先实现。

---

## OPT-012：全局单例降低测试性，播放模块存在环依赖

**优先级：中**

涉及文件：

- `lib/services/`
- `lib/services/playback_bridge.dart`
- `lib/services/audio_session_handler.dart`

### 现状

当前至少有 9 个仓库级单例，页面直接调用 `Service()` 获取隐藏的全局实例。主要问题：

- Dio、SharedPreferences、数据库和时钟无法方便替换。
- Widget 测试难注入 fake。
- 一个测试留下的全局状态可能影响下一个测试。
- 模块依赖只在实现内部体现，组合关系不清晰。

播放模块还有双向 import：

```text
AudioSessionHandler -> PlaybackBridgeService
PlaybackBridgeService -> AudioSessionHandler
```

### 建议

不需要引入大型 DI 框架。可以在 `main.dart` 建立轻量组合根：

```dart
class AppDependencies {
  final LoginGateway loginGateway;
  final LibraryRepository libraryRepository;
  final DownloadCoordinator downloadCoordinator;
  final AppSettingsStore settingsStore;
}
```

生产环境注入真实实现，测试注入 fake。

对于播放环依赖：

- 让一个 `PlaybackSession` 深模块同时拥有播放器桥接和 AudioSession 生命周期；或
- 让 AudioSession 接受少量播放控制回调，不再反向读取全局单例。

不要为了测试把所有内部类都暴露成公共接口。模块的外部接口应保持小，测试通过同一接口观察行为。

---

## OPT-013：页面导航形成环依赖

**优先级：中**

涉及文件：

- `lib/screens/main_screen.dart`
- `lib/screens/settings_screen.dart`
- `lib/screens/login_screen.dart`
- `lib/screens/select_folders_screen.dart`

当前页面之间直接 import 并构造 `MaterialPageRoute`，形成导航环依赖，例如：

```text
MainScreen -> SettingsScreen
SettingsScreen -> LoginScreen / SelectFoldersScreen
LoginScreen -> SelectFoldersScreen
SelectFoldersScreen -> MainScreen
```

### 建议

使用 Flutter 原生能力建立类型化导航模块：

```dart
abstract final class AppNavigator {
  static Future<void> toLogin(BuildContext context) { ... }
  static Future<void> toFolderSelection(BuildContext context, ...) { ... }
  static Future<void> resetToMain(BuildContext context) { ... }
}
```

或者使用 `onGenerateRoute`/Router 配置。目标是让页面表达“导航意图”，不直接依赖目标页面的实现文件。

当前应用页面数量不多，不需要为了这项优化引入 GetX 或 go_router，除非未来深链、Web URL 和嵌套路由成为明确需求。

---

## OPT-014：设置通知不统一，UpdateService 混合网络和 UI

> ✅ 已完成（2026-08-21，commit 9b76f65）
>
> - SettingsService 已暴露 `ValueListenable<AppSettings> settings` 统一快照（此前已完成）。
> - UpdateService 拆为 `UpdateChecker` 纯逻辑层（`check()` 返回 sealed `UpdateCheckResult`）+ UI 协调层。
> - 新增 UpdateChecker 16 个纯逻辑测试、UpdateService 8 个 widget 测试。

**优先级：中**

涉及文件：

- `lib/services/settings_service.dart`
- `lib/services/update_service.dart`
- `lib/screens/settings_screen.dart`

### SettingsService

当前只有 locale 使用 `ValueNotifier`。其他设置是可变字段加 setter，调用方需要自己 setState 或主动刷新其他模块。

建议暴露一个不可变 `AppSettings` 快照及统一 notifier：

```dart
ValueListenable<AppSettings> get settings;
```

设置变更后只发布一个一致的新快照。播放、主题和设置页面都监听同一接口。

### UpdateService

`checkUpdate(BuildContext context)` 既请求 GitHub，又直接显示 SnackBar/Dialog。这样网络逻辑必须在 Widget 环境中测试。

建议拆成：

- `UpdateChecker.check()` 返回 `UpdateCheckResult`。
- 页面或 Presenter 根据结果显示 Dialog。

版本比较和 release notes 解析已有测试，应保留为纯逻辑。

---

## OPT-015：CI 只在发布 tag 上运行，工具链版本不统一

**优先级：中**

涉及文件：

- `.github/workflows/flutter_release.yml`
- `pubspec.yaml`
- `analysis_options.yaml`
- `README.md`

### 现状

- 发布工作流只匹配 `v*` tag。
- PR 和普通 push 没有 `flutter analyze`、`flutter test` 门禁。
- CI 固定 Flutter 3.38.4。
- README 仍写 Flutter 3.10+。
- pubspec 没有 Flutter SDK 约束，Dart 约束仍是 `>=3.0.0 <4.0.0`。
- `flutter_lints` 当前解析到 2.0.3；当前 Flutter 模板使用 6.0.0，且本项目可解析 6.0.0。

### 建议

新增 `ci.yml`：

```text
on: pull_request, push(main)
flutter pub get
flutter gen-l10n
flutter analyze
flutter test
```

可选的较重验证：

- Android debug build：PR 或 main push。
- Windows/Linux debug build：定时或 main push。

版本固定：

- 增加 `.fvmrc`，写入 3.38.4。
- pubspec 增加与 CI 一致的 Flutter/Dart 约束。
- workflow 优先从版本文件读取 Flutter 版本，减少重复。
- README 与实际版本同步。

lint 升级应独立提交，先查看 6.0.0 引入的新增警告，再逐项修复，不能为了保持 0 issues 大面积关闭规则。

---

## OPT-016：依赖中存在未使用项和 discontinued 包

**优先级：中**

涉及文件：

- `pubspec.yaml`
- `windows/CMakeLists.txt`

### permission_handler

静态扫描没有发现 `lib/` 中任何 `permission_handler` import。

该依赖此前还引入了 Windows 插件兼容问题，项目因此在 `windows/CMakeLists.txt` 增加：

```cmake
_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS
```

如果确认没有后续权限功能，应：

1. 移除 `permission_handler`。
2. `flutter pub get`。
3. 验证 Android 和 Windows 构建。
4. 若插件不再被传递依赖引入，删除对应 CMake 抑制宏。

如果暂时保留，应继续停留在 12.x。不要直接升级 13.x；该版本的 Android 插件与当前 AGP/KGP/Gradle 工具链存在已验证的兼容问题。

### flutter_markdown

当前工具输出提示 `flutter_markdown 0.7.7+1` 已 discontinued，并由 `flutter_markdown_plus` 替代。应单独评估：

- Markdown API 兼容性。
- 更新弹窗渲染差异。
- 链接点击与安全策略。

### 其他依赖

`dart pub outdated --json` 显示多个可升级依赖。建议按风险分批：

1. patch/minor 基础依赖。
2. 网络与平台插件。
3. media_kit 2.x 等 major 版本单独迁移。

每批至少运行 analyze、test 及受影响平台构建。

---

## OPT-017：本地化边界不完整

**优先级：中**

涉及示例：

- `lib/widgets/custom_search_bar.dart`
- `lib/widgets/folder_card.dart`
- `lib/widgets/history_tile.dart`
- `lib/screens/about_screen.dart`
- `lib/screens/select_folders_screen.dart`
- `lib/services/auth_service.dart`
- `lib/services/bili_api_service.dart`
- `lib/services/download_service.dart`
- `lib/services/audio_handler.dart`

### 现状

仍存在用户可见硬编码：

- “搜索...”
- “个视频”
- “已看完”
- “Error: ...”
- 音频控制英文 accessibility label
- 服务层中文异常文本
- 模型 fallback 文本，如“未知UP主”

UI 经常通过：

```dart
loadFailed(e.toString())
```

把服务异常直接拼进本地化模板。英文界面因此仍可能出现中文错误或 `Exception:` 前缀。

### 建议

- Widget 用户文案必须来自 `AppLocalizations`，或由调用方显式传入。
- 服务返回错误代码/错误类型，不返回用户文案。
- UI 将 `FailureKind` 映射到 ARB 文案。
- 模型层使用空值或语义枚举，fallback 展示由 UI 决定。
- 为 ARB 增加 key 对齐测试，避免中英文缺项。

---

## OPT-018：测试覆盖尚未覆盖最高风险模块

**优先级：中**

当前测试：

- `test/auth_service_test.dart`
- `test/history_service_test.dart`
- `test/settings_screen_test.dart`
- `test/update_service_test.dart`

### 现有优势

- 登录凭据解析已有 fixture 风格测试。
- 历史迁移和排序已有测试。
- 更新版本比较和 release notes 提取为纯逻辑测试。
- 设置锁定流程已有 Widget 测试。

### 主要缺口

1. `DatabaseService`
   - 多来源关系。
   - schema migration。
   - visible source filtering。
2. `DownloadService`
   - 取消、恢复、失败、重试和进程重启。
3. `BiliApiService`
   - code/message 错误映射。
   - WBI 签名 fixture。
   - JSON 解析变化。
4. `LoginScreen`
   - challenge 字段映射。
   - 轮询防重入。
   - 成功只导航一次。
5. 分页控制
   - refresh/loadMore 竞争。
   - 旧响应不得覆盖新响应。
6. 播放器控制
   - 分集进度快照。
   - 多次清晰度切换保留音频。
   - 快速切换请求顺序。
7. `HomeScreen`
   - 选中来源过滤。
   - 锁定状态。
   - 搜索缓存完整性策略。

### 测试策略

优先通过提取后的模块接口测试，而不是直接测试私有 State 字段。建议使用：

- 注入的 fake Dio/transport。
- 临时或内存 sqflite 数据库。
- 本地 HTTP Server 测试下载。
- fake clock/timer。
- ValueListenable 状态断言。

不要复制参考仓库“功能很多但无测试目录”的做法。

---

## OPT-019：README 与代码现状不一致

**优先级：低**

涉及文件：

- `README.md`

### 已发现漂移

- README 写 Flutter 3.10+，CI 实际使用 3.38.4。
- 功能介绍主要描述收藏夹，未完整反映合集和 UP 主选择。
- 开发计划仍将后台播放标为未完成，但代码已经实现。
- 断点续播也已有较完整实现，计划状态未同步。
- “支持后台下载和任务管理”容易让用户理解为系统后台下载、暂停和恢复；当前实现尚不具备完整保证。
- 声称“完整支持简体中文和英文”，但仍有硬编码文案。
- 构建说明没有完整记录 CI 中使用的版本和 Linux 系统依赖。

### 建议

在核心可靠性修复后更新 README，避免文档先承诺尚未稳定的行为。

---

## 6. 建议的目标模块形态

这不是要求一次性迁移目录，而是说明长期模块缝隙。应先提取真正有行为深度的模块，再决定是否移动文件。

```text
lib/
  core/
    network/
      bili_http_client.dart
      bili_failure.dart
    persistence/
      credential_store.dart
      app_settings_store.dart
    app_bootstrapper.dart
    app_navigator.dart

  features/
    auth/
      login_gateway.dart
      qr_login_controller.dart
      account_session.dart

    library/
      library_repository.dart
      library_item.dart
      paged_loader.dart
      library_sync_coordinator.dart

    playback/
      playback_controller.dart
      playback_progress_snapshot.dart
      playback_session.dart

    downloads/
      download_coordinator.dart
      download_transport.dart
      download_store.dart
```

设计原则：

1. 页面和测试通过同一个小接口使用模块。
2. 模块内部可以有私有适配器，不要为了测试扩大公共接口。
3. 只有真实存在生产/测试或多平台实现时才引入接口缝隙。
4. 不新增只做一行转发的浅服务。
5. 不为了目录整齐进行纯路径重构。
6. 不默认引入 GetX、Riverpod、Bloc 或 go_router；只有当前接口无法清晰表达需求时再评估依赖。

---

## 7. 推荐实施顺序

## 阶段 A：小范围正确性修复

建议独立提交：

1. 播放进度使用不可变快照。
2. 清晰度切换保留完整 `VideoPlayInfo`，包括 `audioUrl`。
3. 登录轮询增加防重入。
4. 二维码 challenge 和 poll result 类型化。
5. 补对应回归测试。

该阶段改动范围相对小，不需要数据迁移。

## 阶段 B：工程门禁和低风险清理

1. 增加 PR CI：gen-l10n、analyze、test。
2. 添加 `.fvmrc` 并同步 README/pubspec。
3. 升级 `flutter_lints` 6.0.0 并修复新增警告。
4. 确认并移除未使用 `permission_handler`。
5. 验证后清理 Windows CMake workaround。
6. 修复硬编码本地化文案。

## 阶段 C：下载可靠性

1. 先写本地 HTTP Server 集成测试。
2. 引入 DownloadCoordinator。
3. 实现取消、队列和启动恢复。
4. 再实现 Range 续传和 DASH 双轨。
5. 最后调整下载页面交互。

## 阶段 D：数据库 v3

实施前先确认搜索完整性策略和账号作用域。

1. 添加迁移测试。
2. 引入 `video_sources`。
3. 迁移现有 folder/season 关系。
4. 增加 UP 来源。
5. 修改搜索过滤和清理逻辑。
6. 根据产品决定实现首屏或渐进全量同步。

## 阶段 E：模块深化

1. BiliHttpClient 和结构化错误。
2. PagedLoader。
3. HomeLibraryController。
4. AccountSession 与分离存储。
5. PlaybackSession，消除播放模块环依赖。
6. AppNavigator，消除页面环依赖。

---

## 8. 需要用户决策的事项

以下内容会改变用户可见行为、数据模型或安全边界，实施前需要明确决定：

1. 搜索缓存是首屏、不完整，还是后台全量同步？
2. 历史记录是否按 Bilibili 账号隔离？
3. 下载是否按账号隔离？
4. 内容选择和锁密码是设备级还是账号级？
5. 是否引入平台安全存储保存 Cookie/token？
6. 下载目标是“应用前台可靠下载”，还是“系统后台任务”？
7. 是否需要完整 DASH 离线合并，还是只支持可直接播放的流？
8. 是否需要深链/Web URL；如果不需要，不应增加路由框架。
9. 是否允许错误日志或崩溃信息上传第三方服务？

---

## 9. 不建议从参考仓库照搬的内容

1. 全量 GetX 全局状态。
2. 大型全局 `Pref` 类。
3. 1,000～2,000 行控制器和 View。
4. 当前产品不需要的 gRPC 生成代码。
5. 无条件忽略 TLS 证书错误。
6. 将网络异常伪装成普通 Response。
7. 大量静态全局状态。
8. 硬编码中文用户文案。
9. 缺少测试的快速功能扩张。
10. 在没有第二个实现或测试替身需求时建立大量接口层。

参考仓库的价值主要在于验证了“账号管理、统一请求、分页控制、下载管理、播放器模块”这些缝隙确实存在，而不是证明其每个实现细节都适合 onlystudy。

---

## 10. 每批变更的验证要求

基础检查：

```bash
flutter gen-l10n  # 仅 ARB 变化时
flutter analyze
flutter test
```

按模块追加：

- Android 相关依赖或权限：`flutter build apk --debug`
- Windows 插件/CMake：`flutter build windows --debug`
- Linux 原生依赖：`flutter build linux --debug`
- 数据库：迁移测试 + 临时数据库行为测试
- 下载：本地 HTTP Server 集成测试
- 播放器：固定 JSON fixture + 控制器状态测试

提交应按独立工作单元拆分，避免把数据库迁移、状态管理、依赖升级和 UI 重构混在一个提交中。
