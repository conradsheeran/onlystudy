import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 图片文件缓存服务（OPT-010）。
///
/// 统一持有 [imageCacheManager] 实例：所有 [CommonImage] 与清理操作
/// 共享同一个缓存目录，避免每个组件重复构造 CacheManager；
/// 清理图片缓存不会影响搜索数据库（onlystudy.db）或下载文件（downloads/）。
class CacheService {
  /// 全局唯一的图片缓存管理器。
  static final BaseCacheManager imageCacheManager = DefaultCacheManager();

  static const String _lastClearKey = 'last_cache_clear_timestamp';
  static const int _cacheDurationDays = 7;

  /// 检查并清理过期的缓存文件 (默认保留7天)
  Future<void> checkAndClearCache() async {
    final prefs = await SharedPreferences.getInstance();
    final lastClear = prefs.getInt(_lastClearKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    if (now - lastClear > _cacheDurationDays * 24 * 60 * 60 * 1000) {
      await imageCacheManager.emptyCache();
      await prefs.setInt(_lastClearKey, now);
    }
  }

  /// 手动清理图片缓存
  Future<void> clearCache() async {
    await imageCacheManager.emptyCache();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastClearKey, DateTime.now().millisecondsSinceEpoch);
  }
}
