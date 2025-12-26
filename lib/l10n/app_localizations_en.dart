// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'OnlyStudy';

  @override
  String get login => 'Login';

  @override
  String get download => 'Download';

  @override
  String get downloadCache => 'Cache Video';

  @override
  String get addToDownload => 'Added to download queue';

  @override
  String playFailed(Object error) {
    return 'Playback failed: $error';
  }

  @override
  String resumePlayback(Object time) {
    return 'Resumed from: $time';
  }

  @override
  String nextVideo(Object title) {
    return 'Playing next: $title';
  }

  @override
  String get switchingQuality => 'Switching quality...';

  @override
  String switchQualityFailed(Object error) {
    return 'Failed to switch quality: $error';
  }

  @override
  String get quality => 'Quality';

  @override
  String get home => 'Home';

  @override
  String get settings => 'Settings';

  @override
  String get defaultResolution => 'Default Resolution';

  @override
  String get about => 'About';

  @override
  String get version => 'Version';

  @override
  String get appName => 'OnlyStudy';

  @override
  String get developer => 'Developer';

  @override
  String get sourceCode => 'Source Code';

  @override
  String get selectFolders => 'Select Displayed Folders';

  @override
  String get clearCache => 'Clear Cache';

  @override
  String get logout => 'Logout';

  @override
  String get slogan => 'Don\'t let knowledge rot in your favorites';

  @override
  String get githubRepo => 'GitHub Repository';

  @override
  String get reportBug => 'Report Bug';

  @override
  String get checkUpdate => 'Check for Updates';

  @override
  String newVersionAvailable(Object version) {
    return 'New version available: $version';
  }

  @override
  String currentVersion(Object version) {
    return 'Current version: $version';
  }

  @override
  String get update => 'Update';

  @override
  String get cancel => 'Cancel';

  @override
  String get noUpdateAvailable => 'You are using the latest version.';

  @override
  String get checkUpdateFailed => 'Failed to check for updates.';

  @override
  String get autoCheckUpdate => 'Auto Check for Updates';

  @override
  String get playbackSpeed => 'Playback Speed';

  @override
  String get speed => 'Speed';

  @override
  String get volume => 'Volume';

  @override
  String get brightness => 'Brightness';

  @override
  String get seekForward => 'Forward';

  @override
  String get seekBackward => 'Backward';

  @override
  String get defaultPlaybackSpeed => 'Default Playback Speed';

  @override
  String get unlockFolderSelection => 'Unlock Folder Selection';

  @override
  String get enterPassword => 'Enter Password';

  @override
  String get verifyPassword => 'Verify Password';

  @override
  String get confirmClearCache => 'Are you sure you want to clear all cache?';

  @override
  String get confirmLogout => 'Are you sure you want to logout?';

  @override
  String get confirm => 'Confirm';

  @override
  String get unlocked => 'Unlocked';

  @override
  String get passwordIncorrect => 'Incorrect Password';

  @override
  String get cacheCleared => 'Cache Cleared';

  @override
  String get loginBilibili => 'Login to Bilibili';

  @override
  String get fetchingQRCode => 'Fetching QR Code...';

  @override
  String get scanQRCode => 'Please scan with Bilibili App';

  @override
  String get loginSuccess => 'Login Successful! Redirecting...';

  @override
  String get qrCodeExpired => 'QR Code Expired';

  @override
  String get refreshQRCode => 'Refresh QR Code';

  @override
  String get lockedHint => 'Currently locked, long press to unlock';

  @override
  String get locked => 'Locked';

  @override
  String get setPassword => 'Set Lock Password';

  @override
  String get passwordSet => 'Password set and locked';

  @override
  String get unlock => 'Unlock';

  @override
  String get noContentFound => 'No content found, please login or refresh';

  @override
  String get searchHint => 'Search videos...';

  @override
  String get noResult => 'No results found';

  @override
  String get favorites => 'Favorites';

  @override
  String get upTab => 'UP主';

  @override
  String get subscribedSeasons => 'Subscribed Seasons';

  @override
  String get offlineCache => 'Offline Cache';

  @override
  String get completed => 'Completed';

  @override
  String get downloading => 'Downloading';

  @override
  String get noDownloadedVideos => 'No downloaded videos';

  @override
  String get noDownloadingTasks => 'No active downloads';

  @override
  String get confirmDelete => 'Confirm Delete';

  @override
  String deleteTaskConfirm(Object title) {
    return 'Are you sure you want to delete \"$title\"?';
  }

  @override
  String get delete => 'Delete';

  @override
  String get statusPending => 'Pending...';

  @override
  String get statusRunning => 'Downloading';

  @override
  String get statusPaused => 'Paused';

  @override
  String get statusFailed => 'Failed';

  @override
  String get watchHistory => 'Watch History';

  @override
  String get clearHistory => 'Clear History';

  @override
  String get confirmClearHistory =>
      'Are you sure you want to clear all history?';

  @override
  String get noHistory => 'No history';

  @override
  String get searchFolder => 'Search in folder...';

  @override
  String loadFailed(Object error) {
    return 'Load failed: $error';
  }

  @override
  String loadMoreFailed(Object error) {
    return 'Load more failed: $error';
  }

  @override
  String loadUpsFailed(Object error) {
    return '加载UP主列表失败: $error';
  }

  @override
  String get noVideosInFolder => 'No videos in this folder.';

  @override
  String get selectContent => 'Select Content';

  @override
  String get retry => 'Retry';

  @override
  String get selectAll => 'Select All';

  @override
  String get clear => 'Clear';

  @override
  String get confirmAndEnter => 'Confirm and Enter';

  @override
  String get selectAtLeastOne => 'Please select at least one folder or season';

  @override
  String get noUps => '暂无关注的UP主';

  @override
  String get noVideosInSeason => 'No videos in this season.';

  @override
  String get partsList => 'Parts List';

  @override
  String playingPart(Object part, Object title) {
    return 'Playing P$part: $title';
  }

  @override
  String get oopsError => 'Oops, something went wrong';

  @override
  String videoCount(Object count) {
    return '$count Videos';
  }

  @override
  String switchPartFailed(Object error) {
    return 'Failed to switch part: $error';
  }

  @override
  String get language => 'Language';

  @override
  String get followSystem => 'Follow System';

  @override
  String get selectLanguage => 'Select Language';

  @override
  String upHomeTitle(Object name) {
    return '$name\'s Space';
  }

  @override
  String get upHomeFallback => 'Creator Space';

  @override
  String get followers => 'Followers';

  @override
  String get following => 'Following';

  @override
  String get likes => 'Likes';

  @override
  String get plays => 'Views';

  @override
  String get videosCount => 'Videos';

  @override
  String get upIntroDefault => 'No bio yet.';

  @override
  String get upVideosTab => 'Videos';

  @override
  String get upCollectionsTab => 'Collections';

  @override
  String get sortLabel => 'Sort';

  @override
  String get filterLabel => 'Filter';

  @override
  String get allCategories => 'All';

  @override
  String get sortLatest => 'Latest';

  @override
  String get sortPlay => 'Most Viewed';

  @override
  String get sortFavorite => 'Most Collected';

  @override
  String get sortDanmaku => 'Most Danmaku';

  @override
  String get emptyUpVideos => 'No videos yet';

  @override
  String get emptyCollections => 'No collections';

  @override
  String loadUpFailed(Object error) {
    return 'Failed to load profile: $error';
  }

  @override
  String loadUpVideosFailed(Object error) {
    return 'Failed to load videos: $error';
  }

  @override
  String loadCollectionFailed(Object error) {
    return 'Failed to load collections: $error';
  }
}
