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
}
