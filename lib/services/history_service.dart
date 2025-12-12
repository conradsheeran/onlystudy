import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/bili_models.dart';

class HistoryService {
  static final HistoryService _instance = HistoryService._internal();
  factory HistoryService() => _instance;
  HistoryService._internal();

  static const String _historyKey = 'local_watch_history';

  /// 添加观看记录 (添加到队首，去重)
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
        //
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