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
}
