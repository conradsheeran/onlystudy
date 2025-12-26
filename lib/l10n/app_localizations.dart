import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh')
  ];

  /// The title of the application
  ///
  /// In zh, this message translates to:
  /// **'唯学'**
  String get appTitle;

  /// No description provided for @login.
  ///
  /// In zh, this message translates to:
  /// **'登录'**
  String get login;

  /// No description provided for @download.
  ///
  /// In zh, this message translates to:
  /// **'下载'**
  String get download;

  /// No description provided for @downloadCache.
  ///
  /// In zh, this message translates to:
  /// **'缓存视频'**
  String get downloadCache;

  /// No description provided for @addToDownload.
  ///
  /// In zh, this message translates to:
  /// **'已添加到下载任务'**
  String get addToDownload;

  /// No description provided for @playFailed.
  ///
  /// In zh, this message translates to:
  /// **'播放失败: {error}'**
  String playFailed(Object error);

  /// No description provided for @resumePlayback.
  ///
  /// In zh, this message translates to:
  /// **'已为您恢复到上次播放位置: {time}'**
  String resumePlayback(Object time);

  /// No description provided for @nextVideo.
  ///
  /// In zh, this message translates to:
  /// **'即将播放下一集: {title}'**
  String nextVideo(Object title);

  /// No description provided for @switchingQuality.
  ///
  /// In zh, this message translates to:
  /// **'正在切换清晰度...'**
  String get switchingQuality;

  /// No description provided for @switchQualityFailed.
  ///
  /// In zh, this message translates to:
  /// **'切换清晰度失败: {error}'**
  String switchQualityFailed(Object error);

  /// No description provided for @quality.
  ///
  /// In zh, this message translates to:
  /// **'清晰度'**
  String get quality;

  /// No description provided for @home.
  ///
  /// In zh, this message translates to:
  /// **'主页'**
  String get home;

  /// No description provided for @settings.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get settings;

  /// No description provided for @defaultResolution.
  ///
  /// In zh, this message translates to:
  /// **'默认清晰度'**
  String get defaultResolution;

  /// No description provided for @about.
  ///
  /// In zh, this message translates to:
  /// **'关于'**
  String get about;

  /// No description provided for @version.
  ///
  /// In zh, this message translates to:
  /// **'版本'**
  String get version;

  /// No description provided for @appName.
  ///
  /// In zh, this message translates to:
  /// **'唯学'**
  String get appName;

  /// No description provided for @developer.
  ///
  /// In zh, this message translates to:
  /// **'开发者'**
  String get developer;

  /// No description provided for @sourceCode.
  ///
  /// In zh, this message translates to:
  /// **'源代码'**
  String get sourceCode;

  /// No description provided for @selectFolders.
  ///
  /// In zh, this message translates to:
  /// **'选择显示的收藏夹'**
  String get selectFolders;

  /// No description provided for @clearCache.
  ///
  /// In zh, this message translates to:
  /// **'清理缓存'**
  String get clearCache;

  /// No description provided for @logout.
  ///
  /// In zh, this message translates to:
  /// **'注销登录'**
  String get logout;

  /// No description provided for @slogan.
  ///
  /// In zh, this message translates to:
  /// **'别让知识烂在收藏夹里'**
  String get slogan;

  /// No description provided for @githubRepo.
  ///
  /// In zh, this message translates to:
  /// **'GitHub 仓库'**
  String get githubRepo;

  /// No description provided for @reportBug.
  ///
  /// In zh, this message translates to:
  /// **'提交 Bug'**
  String get reportBug;

  /// No description provided for @checkUpdate.
  ///
  /// In zh, this message translates to:
  /// **'检查更新'**
  String get checkUpdate;

  /// No description provided for @newVersionAvailable.
  ///
  /// In zh, this message translates to:
  /// **'发现新版本: {version}'**
  String newVersionAvailable(Object version);

  /// No description provided for @currentVersion.
  ///
  /// In zh, this message translates to:
  /// **'当前版本: {version}'**
  String currentVersion(Object version);

  /// No description provided for @update.
  ///
  /// In zh, this message translates to:
  /// **'立即更新'**
  String get update;

  /// No description provided for @cancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get cancel;

  /// No description provided for @noUpdateAvailable.
  ///
  /// In zh, this message translates to:
  /// **'已是最新版本'**
  String get noUpdateAvailable;

  /// No description provided for @checkUpdateFailed.
  ///
  /// In zh, this message translates to:
  /// **'检查更新失败'**
  String get checkUpdateFailed;

  /// No description provided for @autoCheckUpdate.
  ///
  /// In zh, this message translates to:
  /// **'自动检查更新'**
  String get autoCheckUpdate;

  /// No description provided for @playbackSpeed.
  ///
  /// In zh, this message translates to:
  /// **'播放速度'**
  String get playbackSpeed;

  /// No description provided for @speed.
  ///
  /// In zh, this message translates to:
  /// **'倍速'**
  String get speed;

  /// No description provided for @volume.
  ///
  /// In zh, this message translates to:
  /// **'音量'**
  String get volume;

  /// No description provided for @brightness.
  ///
  /// In zh, this message translates to:
  /// **'亮度'**
  String get brightness;

  /// No description provided for @seekForward.
  ///
  /// In zh, this message translates to:
  /// **'快进'**
  String get seekForward;

  /// No description provided for @seekBackward.
  ///
  /// In zh, this message translates to:
  /// **'后退'**
  String get seekBackward;

  /// No description provided for @defaultPlaybackSpeed.
  ///
  /// In zh, this message translates to:
  /// **'默认播放倍速'**
  String get defaultPlaybackSpeed;

  /// No description provided for @unlockFolderSelection.
  ///
  /// In zh, this message translates to:
  /// **'解锁收藏夹修改'**
  String get unlockFolderSelection;

  /// No description provided for @enterPassword.
  ///
  /// In zh, this message translates to:
  /// **'输入密码'**
  String get enterPassword;

  /// No description provided for @verifyPassword.
  ///
  /// In zh, this message translates to:
  /// **'验证密码'**
  String get verifyPassword;

  /// No description provided for @confirmClearCache.
  ///
  /// In zh, this message translates to:
  /// **'确定要清理所有缓存吗？'**
  String get confirmClearCache;

  /// No description provided for @confirmLogout.
  ///
  /// In zh, this message translates to:
  /// **'确定要退出登录吗？'**
  String get confirmLogout;

  /// No description provided for @confirm.
  ///
  /// In zh, this message translates to:
  /// **'确定'**
  String get confirm;

  /// No description provided for @unlocked.
  ///
  /// In zh, this message translates to:
  /// **'已解锁'**
  String get unlocked;

  /// No description provided for @passwordIncorrect.
  ///
  /// In zh, this message translates to:
  /// **'密码错误'**
  String get passwordIncorrect;

  /// No description provided for @cacheCleared.
  ///
  /// In zh, this message translates to:
  /// **'缓存已清理'**
  String get cacheCleared;

  /// No description provided for @loginBilibili.
  ///
  /// In zh, this message translates to:
  /// **'登录 Bilibili'**
  String get loginBilibili;

  /// No description provided for @fetchingQRCode.
  ///
  /// In zh, this message translates to:
  /// **'正在获取二维码...'**
  String get fetchingQRCode;

  /// No description provided for @scanQRCode.
  ///
  /// In zh, this message translates to:
  /// **'请使用 Bilibili 手机端扫码'**
  String get scanQRCode;

  /// No description provided for @loginSuccess.
  ///
  /// In zh, this message translates to:
  /// **'登录成功! 正在跳转...'**
  String get loginSuccess;

  /// No description provided for @qrCodeExpired.
  ///
  /// In zh, this message translates to:
  /// **'二维码已过期'**
  String get qrCodeExpired;

  /// No description provided for @refreshQRCode.
  ///
  /// In zh, this message translates to:
  /// **'刷新二维码'**
  String get refreshQRCode;

  /// No description provided for @lockedHint.
  ///
  /// In zh, this message translates to:
  /// **'当前为锁定状态，请长按解锁'**
  String get lockedHint;

  /// No description provided for @locked.
  ///
  /// In zh, this message translates to:
  /// **'已锁定修改'**
  String get locked;

  /// No description provided for @setPassword.
  ///
  /// In zh, this message translates to:
  /// **'设置锁定密码'**
  String get setPassword;

  /// No description provided for @passwordSet.
  ///
  /// In zh, this message translates to:
  /// **'密码已设置并锁定'**
  String get passwordSet;

  /// No description provided for @unlock.
  ///
  /// In zh, this message translates to:
  /// **'解锁'**
  String get unlock;

  /// No description provided for @noContentFound.
  ///
  /// In zh, this message translates to:
  /// **'没有找到收藏夹或合集，请登录或刷新'**
  String get noContentFound;

  /// No description provided for @searchHint.
  ///
  /// In zh, this message translates to:
  /// **'请输入关键词搜索视频'**
  String get searchHint;

  /// No description provided for @noResult.
  ///
  /// In zh, this message translates to:
  /// **'没有找到相关视频'**
  String get noResult;

  /// No description provided for @favorites.
  ///
  /// In zh, this message translates to:
  /// **'收藏夹'**
  String get favorites;

  /// No description provided for @upTab.
  ///
  /// In zh, this message translates to:
  /// **'UP主'**
  String get upTab;

  /// No description provided for @subscribedSeasons.
  ///
  /// In zh, this message translates to:
  /// **'订阅合集'**
  String get subscribedSeasons;

  /// No description provided for @offlineCache.
  ///
  /// In zh, this message translates to:
  /// **'离线缓存'**
  String get offlineCache;

  /// No description provided for @completed.
  ///
  /// In zh, this message translates to:
  /// **'已完成'**
  String get completed;

  /// No description provided for @downloading.
  ///
  /// In zh, this message translates to:
  /// **'进行中'**
  String get downloading;

  /// No description provided for @noDownloadedVideos.
  ///
  /// In zh, this message translates to:
  /// **'暂无已完成的视频'**
  String get noDownloadedVideos;

  /// No description provided for @noDownloadingTasks.
  ///
  /// In zh, this message translates to:
  /// **'暂无进行中的任务'**
  String get noDownloadingTasks;

  /// No description provided for @confirmDelete.
  ///
  /// In zh, this message translates to:
  /// **'确认删除'**
  String get confirmDelete;

  /// No description provided for @deleteTaskConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定要删除 \"{title}\" 吗？'**
  String deleteTaskConfirm(Object title);

  /// No description provided for @delete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get delete;

  /// No description provided for @statusPending.
  ///
  /// In zh, this message translates to:
  /// **'等待中...'**
  String get statusPending;

  /// No description provided for @statusRunning.
  ///
  /// In zh, this message translates to:
  /// **'下载中'**
  String get statusRunning;

  /// No description provided for @statusPaused.
  ///
  /// In zh, this message translates to:
  /// **'已暂停'**
  String get statusPaused;

  /// No description provided for @statusFailed.
  ///
  /// In zh, this message translates to:
  /// **'下载失败'**
  String get statusFailed;

  /// No description provided for @watchHistory.
  ///
  /// In zh, this message translates to:
  /// **'观看历史'**
  String get watchHistory;

  /// No description provided for @clearHistory.
  ///
  /// In zh, this message translates to:
  /// **'清空历史'**
  String get clearHistory;

  /// No description provided for @confirmClearHistory.
  ///
  /// In zh, this message translates to:
  /// **'确定要清空所有本地观看历史吗？'**
  String get confirmClearHistory;

  /// No description provided for @noHistory.
  ///
  /// In zh, this message translates to:
  /// **'暂无观看记录'**
  String get noHistory;

  /// No description provided for @searchFolder.
  ///
  /// In zh, this message translates to:
  /// **'在线搜索此收藏夹...'**
  String get searchFolder;

  /// No description provided for @loadFailed.
  ///
  /// In zh, this message translates to:
  /// **'加载视频失败: {error}'**
  String loadFailed(Object error);

  /// No description provided for @loadMoreFailed.
  ///
  /// In zh, this message translates to:
  /// **'加载更多失败: {error}'**
  String loadMoreFailed(Object error);

  /// No description provided for @loadUpsFailed.
  ///
  /// In zh, this message translates to:
  /// **'加载UP主列表失败: {error}'**
  String loadUpsFailed(Object error);

  /// No description provided for @noVideosInFolder.
  ///
  /// In zh, this message translates to:
  /// **'此收藏夹中没有视频。'**
  String get noVideosInFolder;

  /// No description provided for @selectContent.
  ///
  /// In zh, this message translates to:
  /// **'选择显示的内容'**
  String get selectContent;

  /// No description provided for @retry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get retry;

  /// No description provided for @selectAll.
  ///
  /// In zh, this message translates to:
  /// **'全选'**
  String get selectAll;

  /// No description provided for @clear.
  ///
  /// In zh, this message translates to:
  /// **'清空'**
  String get clear;

  /// No description provided for @confirmAndEnter.
  ///
  /// In zh, this message translates to:
  /// **'确认并进入'**
  String get confirmAndEnter;

  /// No description provided for @selectAtLeastOne.
  ///
  /// In zh, this message translates to:
  /// **'请至少选择一个收藏夹、合集或UP主'**
  String get selectAtLeastOne;

  /// No description provided for @noUps.
  ///
  /// In zh, this message translates to:
  /// **'暂无关注的UP主'**
  String get noUps;

  /// No description provided for @noVideosInSeason.
  ///
  /// In zh, this message translates to:
  /// **'此合集中没有视频。'**
  String get noVideosInSeason;

  /// No description provided for @partsList.
  ///
  /// In zh, this message translates to:
  /// **'分集列表'**
  String get partsList;

  /// No description provided for @playingPart.
  ///
  /// In zh, this message translates to:
  /// **'即将播放 P{part}: {title}'**
  String playingPart(Object part, Object title);

  /// No description provided for @oopsError.
  ///
  /// In zh, this message translates to:
  /// **'哎呀，出错了'**
  String get oopsError;

  /// No description provided for @videoCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个视频'**
  String videoCount(Object count);

  /// No description provided for @switchPartFailed.
  ///
  /// In zh, this message translates to:
  /// **'切换分P失败: {error}'**
  String switchPartFailed(Object error);

  /// No description provided for @language.
  ///
  /// In zh, this message translates to:
  /// **'语言'**
  String get language;

  /// No description provided for @followSystem.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get followSystem;

  /// No description provided for @selectLanguage.
  ///
  /// In zh, this message translates to:
  /// **'选择语言'**
  String get selectLanguage;

  /// No description provided for @upHomeTitle.
  ///
  /// In zh, this message translates to:
  /// **'{name} 的主页'**
  String upHomeTitle(Object name);

  /// No description provided for @upHomeFallback.
  ///
  /// In zh, this message translates to:
  /// **'UP主主页'**
  String get upHomeFallback;

  /// No description provided for @followers.
  ///
  /// In zh, this message translates to:
  /// **'粉丝'**
  String get followers;

  /// No description provided for @following.
  ///
  /// In zh, this message translates to:
  /// **'关注'**
  String get following;

  /// No description provided for @likes.
  ///
  /// In zh, this message translates to:
  /// **'获赞'**
  String get likes;

  /// No description provided for @plays.
  ///
  /// In zh, this message translates to:
  /// **'总播放'**
  String get plays;

  /// No description provided for @videosCount.
  ///
  /// In zh, this message translates to:
  /// **'投稿数'**
  String get videosCount;

  /// No description provided for @upIntroDefault.
  ///
  /// In zh, this message translates to:
  /// **'这个UP很懒，还没有签名'**
  String get upIntroDefault;

  /// No description provided for @upVideosTab.
  ///
  /// In zh, this message translates to:
  /// **'投稿'**
  String get upVideosTab;

  /// No description provided for @upCollectionsTab.
  ///
  /// In zh, this message translates to:
  /// **'合集'**
  String get upCollectionsTab;

  /// No description provided for @sortLabel.
  ///
  /// In zh, this message translates to:
  /// **'排序'**
  String get sortLabel;

  /// No description provided for @filterLabel.
  ///
  /// In zh, this message translates to:
  /// **'筛选'**
  String get filterLabel;

  /// No description provided for @allCategories.
  ///
  /// In zh, this message translates to:
  /// **'全部分区'**
  String get allCategories;

  /// No description provided for @sortLatest.
  ///
  /// In zh, this message translates to:
  /// **'最新发布'**
  String get sortLatest;

  /// No description provided for @sortPlay.
  ///
  /// In zh, this message translates to:
  /// **'最多播放'**
  String get sortPlay;

  /// No description provided for @sortFavorite.
  ///
  /// In zh, this message translates to:
  /// **'最多收藏'**
  String get sortFavorite;

  /// No description provided for @sortDanmaku.
  ///
  /// In zh, this message translates to:
  /// **'最多弹幕'**
  String get sortDanmaku;

  /// No description provided for @emptyUpVideos.
  ///
  /// In zh, this message translates to:
  /// **'暂无投稿'**
  String get emptyUpVideos;

  /// No description provided for @emptyCollections.
  ///
  /// In zh, this message translates to:
  /// **'暂无合集'**
  String get emptyCollections;

  /// No description provided for @loadUpFailed.
  ///
  /// In zh, this message translates to:
  /// **'加载UP主信息失败: {error}'**
  String loadUpFailed(Object error);

  /// No description provided for @loadUpVideosFailed.
  ///
  /// In zh, this message translates to:
  /// **'加载投稿失败: {error}'**
  String loadUpVideosFailed(Object error);

  /// No description provided for @loadCollectionFailed.
  ///
  /// In zh, this message translates to:
  /// **'加载合集失败: {error}'**
  String loadCollectionFailed(Object error);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
