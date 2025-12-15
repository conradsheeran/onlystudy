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
}
