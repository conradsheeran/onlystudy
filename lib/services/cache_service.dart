import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CacheService {
  static const String _lastClearKey = 'last_cache_clear_timestamp';
  static const int _cacheDurationDays = 7;

  /// 检查并清理过期的缓存文件 (默认保留7天)
  Future<void> checkAndClearCache() async {
    final prefs = await SharedPreferences.getInstance();
    final lastClear = prefs.getInt(_lastClearKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    if (now - lastClear > _cacheDurationDays * 24 * 60 * 60 * 1000) {
      await DefaultCacheManager().emptyCache();
      await prefs.setInt(_lastClearKey, now);
    }
  }

  /// 手动清理所有缓存
  Future<void> clearCache() async {
    await DefaultCacheManager().emptyCache();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastClearKey, DateTime.now().millisecondsSinceEpoch);
  }
}
