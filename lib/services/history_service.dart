import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/bili_models.dart';

/// 管理本地观看历史和播放进度的服务
class HistoryService {
  static final HistoryService _instance = HistoryService._internal();
  factory HistoryService() => _instance;
  HistoryService._internal();

  static const String _historyKey = 'local_watch_history';
  static const String _progressKey = 'local_watch_progress';

  /// 添加观看记录（插入队首并去重）
  Future<void> addWatchedVideo(Video video) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> historyJson = prefs.getStringList(_historyKey) ?? [];

    historyJson.removeWhere((item) {
      try {
        final Map<String, dynamic> json = jsonDecode(item);
        return json['bvid'] == video.bvid;
      } catch (e) {
        return false;
      }
    });

    final Map<String, dynamic> videoMap = {
      'bvid': video.bvid,
      'title': video.title,
      'cover': video.cover,
      'duration': video.duration,
      'upper': {
        'mid': video.upper.mid,
        'name': video.upper.name,
      },
      'cnt_info': {'play': video.view},
      'pub_time': video.pubTimestamp,
      'viewed_at': DateTime.now().millisecondsSinceEpoch,
    };

    historyJson.insert(0, jsonEncode(videoMap));

    if (historyJson.length > 100) {
      historyJson.removeRange(100, historyJson.length);
    }

    await prefs.setStringList(_historyKey, historyJson);
  }

  /// 保存本地播放进度（秒），按 bvid+cid 组合键存储
  Future<void> saveProgress(String bvid, int cid, int seconds) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_progressKey);
    Map<String, dynamic> data;
    try {
      data = raw != null ? jsonDecode(raw) as Map<String, dynamic> : {};
    } catch (_) {
      data = {};
    }
    data['${bvid}_$cid'] = seconds;
    await prefs.setString(_progressKey, jsonEncode(data));
  }

  /// 读取本地播放进度（秒），不存在则返回 0
  Future<int> getProgress(String bvid, int cid) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_progressKey);
    if (raw == null) return 0;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final value = data['${bvid}_$cid'];
      if (value is int) return value;
      if (value is num) return value.toInt();
    } catch (_) {}
    return 0;
  }

  /// 获取本地观看记录列表
  Future<List<Video>> getWatchedVideos() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> historyJson = prefs.getStringList(_historyKey) ?? [];

    List<Video> videos = [];
    for (var item in historyJson) {
      try {
        final Map<String, dynamic> json = jsonDecode(item);
        videos.add(Video.fromJson(json));
      } catch (e) {
        debugPrint('解析历史记录失败: $e');
      }
    }
    return videos;
  }

  /// 清空本地观看历史
  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
  }
}
