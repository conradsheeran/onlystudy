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
}
