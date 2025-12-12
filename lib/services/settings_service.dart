import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  static const String _keyDefaultResolution = 'default_resolution';
  
  int _defaultResolution = 64;

  int get defaultResolution => _defaultResolution;

  static const Map<int, String> resolutionMap = {
    120: '4K',
    112: '1080P+',
    80: '1080P',
    64: '720P',
    32: '480P',
    16: '360P',
  };

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _defaultResolution = prefs.getInt(_keyDefaultResolution) ?? 64;
  }

  Future<void> setDefaultResolution(int resolution) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyDefaultResolution, resolution);
    _defaultResolution = resolution;
  }
}
