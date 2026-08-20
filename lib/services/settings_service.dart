import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_settings.dart';

/// 全局设置服务，管理应用配置
///
/// 所有设置通过不可变 [AppSettings] 快照发布，页面用
/// `ValueListenableBuilder` 监听 `settings` 统一刷新（OPT-014）。
class SettingsService {
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  static const String _keyDefaultResolution = 'default_resolution';
  static const String _keyAutoCheckUpdate = 'auto_check_update';
  static const String _keyLastPromptedUpdateVersion =
      'last_prompted_update_version';
  static const String _keyDefaultPlaybackSpeed = 'default_playback_speed';
  static const String _keyEnableBackgroundPlayback =
      'enable_background_playback';
  static const String _keyLocale = 'app_locale';

  AppSettings _settings = const AppSettings(
    defaultResolution: 64,
    autoCheckUpdate: true,
    lastPromptedUpdateVersion: null,
    defaultPlaybackSpeed: 1.0,
    enableBackgroundPlayback: true,
    localeCode: null,
  );

  final ValueNotifier<AppSettings> _settingsNotifier =
      ValueNotifier(const AppSettings(
    defaultResolution: 64,
    autoCheckUpdate: true,
    lastPromptedUpdateVersion: null,
    defaultPlaybackSpeed: 1.0,
    enableBackgroundPlayback: true,
    localeCode: null,
  ));

  /// 设置快照监听器；设置变更后发布新快照。
  ValueListenable<AppSettings> get settings => _settingsNotifier;

  /// 兼容旧 API：语言通知器（main.dart 监听）。
  final ValueNotifier<Locale?> localeNotifier = ValueNotifier(null);

  int get defaultResolution => _settings.defaultResolution;
  bool get autoCheckUpdate => _settings.autoCheckUpdate;
  String? get lastPromptedUpdateVersion =>
      _settings.lastPromptedUpdateVersion;
  double get defaultPlaybackSpeed => _settings.defaultPlaybackSpeed;
  bool get enableBackgroundPlayback => _settings.enableBackgroundPlayback;
  String? get localeCode => _settings.localeCode;

  static const Map<int, String> resolutionMap = {
    120: '4K',
    112: '1080P+',
    80: '1080P',
    64: '720P',
    32: '480P',
    16: '360P',
  };

  /// 初始化配置，从 SharedPreferences 加载
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _settings = AppSettings(
      defaultResolution: prefs.getInt(_keyDefaultResolution) ?? 64,
      autoCheckUpdate: prefs.getBool(_keyAutoCheckUpdate) ?? true,
      lastPromptedUpdateVersion:
          prefs.getString(_keyLastPromptedUpdateVersion),
      defaultPlaybackSpeed:
          prefs.getDouble(_keyDefaultPlaybackSpeed) ?? 1.0,
      enableBackgroundPlayback:
          prefs.getBool(_keyEnableBackgroundPlayback) ?? true,
      localeCode: prefs.getString(_keyLocale),
    );
    _settingsNotifier.value = _settings;
    if (_settings.localeCode != null) {
      localeNotifier.value = Locale(_settings.localeCode!);
    }
  }

  /// 设置默认清晰度
  Future<void> setDefaultResolution(int resolution) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyDefaultResolution, resolution);
    _publish(_settings.copyWith(defaultResolution: resolution));
  }

  /// 设置是否自动检查更新
  Future<void> setAutoCheckUpdate(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoCheckUpdate, value);
    _publish(_settings.copyWith(autoCheckUpdate: value));
  }

  Future<void> setLastPromptedUpdateVersion(String? version) async {
    final prefs = await SharedPreferences.getInstance();
    if (version == null || version.isEmpty) {
      await prefs.remove(_keyLastPromptedUpdateVersion);
    } else {
      await prefs.setString(_keyLastPromptedUpdateVersion, version);
    }
    _publish(_settings.copyWith(lastPromptedUpdateVersion: version));
  }

  /// 设置默认播放倍速
  Future<void> setDefaultPlaybackSpeed(double speed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyDefaultPlaybackSpeed, speed);
    _publish(_settings.copyWith(defaultPlaybackSpeed: speed));
  }

  Future<void> setEnableBackgroundPlayback(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnableBackgroundPlayback, value);
    _publish(_settings.copyWith(enableBackgroundPlayback: value));
  }

  /// 设置语言 (null 表示跟随系统)
  Future<void> setLocale(String? languageCode) async {
    final prefs = await SharedPreferences.getInstance();
    if (languageCode == null) {
      await prefs.remove(_keyLocale);
      localeNotifier.value = null;
    } else {
      await prefs.setString(_keyLocale, languageCode);
      localeNotifier.value = Locale(languageCode);
    }
    _publish(_settings.copyWith(localeCode: languageCode));
  }

  void _publish(AppSettings next) {
    _settings = next;
    _settingsNotifier.value = next;
  }

  /// 测试专用：重置为默认值。
  @visibleForTesting
  void resetForTest() {
    _settings = const AppSettings(
      defaultResolution: 64,
      autoCheckUpdate: true,
      lastPromptedUpdateVersion: null,
      defaultPlaybackSpeed: 1.0,
      enableBackgroundPlayback: true,
      localeCode: null,
    );
    _settingsNotifier.value = _settings;
  }
}
