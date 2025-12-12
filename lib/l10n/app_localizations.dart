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
    Locale('zh'),
  ];

  /// 唯学是一款专为学习设计的沉浸式 Bilibili 视频播放器，提供锁定功能以确保专注的学习环境
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
  /// **'只显示这些收藏夹'**
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
    'that was used.',
  );
}
