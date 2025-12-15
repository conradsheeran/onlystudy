import 'package:shared_preferences/shared_preferences.dart';

/// 全局设置服务，管理应用配置
class SettingsService {
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  static const String _keyDefaultResolution = 'default_resolution';
  static const String _keyAutoCheckUpdate = 'auto_check_update';
  static const String _keyDefaultPlaybackSpeed = 'default_playback_speed';
  
  int _defaultResolution = 64;
  bool _autoCheckUpdate = true;
  double _defaultPlaybackSpeed = 1.0;

  int get defaultResolution => _defaultResolution;
  bool get autoCheckUpdate => _autoCheckUpdate;
  double get defaultPlaybackSpeed => _defaultPlaybackSpeed;

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
    _defaultResolution = prefs.getInt(_keyDefaultResolution) ?? 64;
    _autoCheckUpdate = prefs.getBool(_keyAutoCheckUpdate) ?? true;
    _defaultPlaybackSpeed = prefs.getDouble(_keyDefaultPlaybackSpeed) ?? 1.0;
  }

  /// 设置默认清晰度
  Future<void> setDefaultResolution(int resolution) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyDefaultResolution, resolution);
    _defaultResolution = resolution;
  }

  /// 设置是否自动检查更新
  Future<void> setAutoCheckUpdate(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoCheckUpdate, value);
    _autoCheckUpdate = value;
  }

  /// 设置默认播放倍速
  Future<void> setDefaultPlaybackSpeed(double speed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyDefaultPlaybackSpeed, speed);
    _defaultPlaybackSpeed = speed;
  }
}
