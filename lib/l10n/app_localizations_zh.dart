// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => '唯学';

  @override
  String get login => '登录';

  @override
  String get download => '下载';

  @override
  String get downloadCache => '缓存视频';

  @override
  String get addToDownload => '已添加到下载任务';

  @override
  String playFailed(Object error) {
    return '播放失败: $error';
  }

  @override
  String resumePlayback(Object time) {
    return '已为您恢复到上次播放位置: $time';
  }

  @override
  String nextVideo(Object title) {
    return '即将播放下一集: $title';
  }

  @override
  String get switchingQuality => '正在切换清晰度...';

  @override
  String switchQualityFailed(Object error) {
    return '切换清晰度失败: $error';
  }

  @override
  String get quality => '清晰度';

  @override
  String get home => '主页';

  @override
  String get settings => '设置';

  @override
  String get defaultResolution => '默认清晰度';

  @override
  String get about => '关于';

  @override
  String get version => '版本';

  @override
  String get appName => '唯学';

  @override
  String get developer => '开发者';

  @override
  String get sourceCode => '源代码';

  @override
  String get selectFolders => '选择显示的收藏夹';

  @override
  String get clearCache => '清理缓存';

  @override
  String get logout => '注销登录';

  @override
  String get slogan => '别让知识烂在收藏夹里';

  @override
  String get githubRepo => 'GitHub 仓库';

  @override
  String get reportBug => '提交 Bug';

  @override
  String get checkUpdate => '检查更新';

  @override
  String newVersionAvailable(Object version) {
    return '发现新版本: $version';
  }

  @override
  String currentVersion(Object version) {
    return '当前版本: $version';
  }

  @override
  String get update => '立即更新';

  @override
  String get cancel => '取消';

  @override
  String get noUpdateAvailable => '已是最新版本';

  @override
  String get checkUpdateFailed => '检查更新失败';

  @override
  String get autoCheckUpdate => '自动检查更新';

  @override
  String get playbackSpeed => '播放速度';

  @override
  String get speed => '倍速';

  @override
  String get volume => '音量';

  @override
  String get brightness => '亮度';

  @override
  String get seekForward => '快进';

  @override
  String get seekBackward => '后退';

  @override
  String get defaultPlaybackSpeed => '默认播放倍速';

  @override
  String get unlockFolderSelection => '解锁收藏夹修改';

  @override
  String get enterPassword => '输入密码';

  @override
  String get verifyPassword => '验证密码';

  @override
  String get confirmClearCache => '确定要清理所有缓存吗？';

  @override
  String get confirmLogout => '确定要退出登录吗？';

  @override
  String get confirm => '确定';

  @override
  String get unlocked => '已解锁';

  @override
  String get passwordIncorrect => '密码错误';

  @override
  String get cacheCleared => '缓存已清理';

  @override
  String get loginBilibili => '登录 Bilibili';

  @override
  String get fetchingQRCode => '正在获取二维码...';

  @override
  String get scanQRCode => '请使用 Bilibili 手机端扫码';

  @override
  String get loginSuccess => '登录成功! 正在跳转...';

  @override
  String get qrCodeExpired => '二维码已过期';

  @override
  String get refreshQRCode => '刷新二维码';

  @override
  String get lockedHint => '当前为锁定状态，请长按解锁';

  @override
  String get locked => '已锁定修改';

  @override
  String get setPassword => '设置锁定密码';

  @override
  String get passwordSet => '密码已设置并锁定';

  @override
  String get unlock => '解锁';

  @override
  String get noContentFound => '没有找到收藏夹或合集，请登录或刷新';

  @override
  String get searchHint => '请输入关键词搜索视频';

  @override
  String get noResult => '没有找到相关视频';

  @override
  String get favorites => '收藏夹';

  @override
  String get upTab => 'UP主';

  @override
  String get subscribedSeasons => '订阅合集';

  @override
  String get offlineCache => '离线缓存';

  @override
  String get completed => '已完成';

  @override
  String get downloading => '进行中';

  @override
  String get noDownloadedVideos => '暂无已完成的视频';

  @override
  String get noDownloadingTasks => '暂无进行中的任务';

  @override
  String get confirmDelete => '确认删除';

  @override
  String deleteTaskConfirm(Object title) {
    return '确定要删除 \"$title\" 吗？';
  }

  @override
  String get delete => '删除';

  @override
  String get statusPending => '等待中...';

  @override
  String get statusRunning => '下载中';

  @override
  String get statusPaused => '已暂停';

  @override
  String get statusFailed => '下载失败';

  @override
  String get watchHistory => '观看历史';

  @override
  String get clearHistory => '清空历史';

  @override
  String get confirmClearHistory => '确定要清空所有本地观看历史吗？';

  @override
  String get noHistory => '暂无观看记录';

  @override
  String get searchFolder => '在线搜索此收藏夹...';

  @override
  String loadFailed(Object error) {
    return '加载视频失败: $error';
  }

  @override
  String loadMoreFailed(Object error) {
    return '加载更多失败: $error';
  }

  @override
  String loadUpsFailed(Object error) {
    return '加载UP主列表失败: $error';
  }

  @override
  String get noVideosInFolder => '此收藏夹中没有视频。';

  @override
  String get selectContent => '选择显示的内容';

  @override
  String get retry => '重试';

  @override
  String get selectAll => '全选';

  @override
  String get clear => '清空';

  @override
  String get confirmAndEnter => '确认并进入';

  @override
  String get selectAtLeastOne => '请至少选择一个收藏夹、合集或UP主';

  @override
  String get noUps => '暂无关注的UP主';

  @override
  String get noVideosInSeason => '此合集中没有视频。';

  @override
  String get partsList => '分集列表';

  @override
  String playingPart(Object part, Object title) {
    return '即将播放 P$part: $title';
  }

  @override
  String get oopsError => '哎呀，出错了';

  @override
  String videoCount(Object count) {
    return '$count 个视频';
  }

  @override
  String switchPartFailed(Object error) {
    return '切换分P失败: $error';
  }

  @override
  String get language => '语言';

  @override
  String get followSystem => '跟随系统';

  @override
  String get selectLanguage => '选择语言';

  @override
  String upHomeTitle(Object name) {
    return '$name 的主页';
  }

  @override
  String get upHomeFallback => 'UP主主页';

  @override
  String get followers => '粉丝';

  @override
  String get following => '关注';

  @override
  String get likes => '获赞';

  @override
  String get plays => '总播放';

  @override
  String get videosCount => '投稿数';

  @override
  String get upIntroDefault => '这个UP很懒，还没有签名';

  @override
  String get upVideosTab => '投稿';

  @override
  String get upCollectionsTab => '合集';

  @override
  String get sortLabel => '排序';

  @override
  String get filterLabel => '筛选';

  @override
  String get allCategories => '全部分区';

  @override
  String get sortLatest => '最新发布';

  @override
  String get sortPlay => '最多播放';

  @override
  String get sortFavorite => '最多收藏';

  @override
  String get sortDanmaku => '最多弹幕';

  @override
  String get emptyUpVideos => '暂无投稿';

  @override
  String get emptyCollections => '暂无合集';

  @override
  String loadUpFailed(Object error) {
    return '加载UP主信息失败: $error';
  }

  @override
  String loadUpVideosFailed(Object error) {
    return '加载投稿失败: $error';
  }

  @override
  String loadCollectionFailed(Object error) {
    return '加载合集失败: $error';
  }
}
