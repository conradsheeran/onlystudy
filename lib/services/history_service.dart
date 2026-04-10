import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/bili_models.dart';
import '../models/history_entry.dart';

/// 管理本地观看历史和播放进度的服务
class HistoryService {
  static final HistoryService _instance = HistoryService._internal();
  factory HistoryService() => _instance;
  HistoryService._internal();

  static const String _historyKey = 'local_watch_history_entries';
  static const String _legacyHistoryKey = 'local_watch_history';
  static const String _legacyProgressKey = 'local_watch_progress';

  Future<List<HistoryEntry>> getHistoryEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final storedHistory = prefs.getStringList(_historyKey);
    if (storedHistory != null) {
      return _decodeEntries(storedHistory);
    }

    final migratedEntries = await _migrateLegacyData(prefs);
    await _persistEntries(prefs, migratedEntries);
    return migratedEntries;
  }

  Future<HistoryEntry?> getHistoryEntry(String bvid) async {
    final entries = await getHistoryEntries();
    for (final entry in entries) {
      if (entry.bvid == bvid) {
        return entry;
      }
    }
    return null;
  }

  Future<void> seedHistory(Video video) async {
    final existingEntry = await getHistoryEntry(video.bvid);
    final nextEntry = (existingEntry ?? HistoryEntry.fromVideo(video)).copyWith(
      title: video.title,
      cover: video.cover,
      upperName: video.upper.name,
      duration: video.duration,
      viewedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await upsertHistoryEntry(nextEntry);
  }

  Future<void> upsertHistoryEntry(HistoryEntry entry) async {
    final prefs = await SharedPreferences.getInstance();
    final entries = await getHistoryEntries();
    entries.removeWhere((item) => item.bvid == entry.bvid);
    entries.insert(0, entry);

    if (entries.length > 100) {
      entries.removeRange(100, entries.length);
    }

    await _persistEntries(prefs, entries);
  }

  Future<void> savePlaybackProgress({
    required Video video,
    required int aid,
    required int cid,
    required int page,
    required String partTitle,
    required int duration,
    required int seconds,
    required bool isFinished,
  }) async {
    final existingEntry = await getHistoryEntry(video.bvid);
    final viewedAt = DateTime.now().millisecondsSinceEpoch;
    final normalizedDuration = duration > 0 ? duration : video.duration;
    final normalizedProgress = seconds
        .clamp(0, normalizedDuration > 0 ? normalizedDuration : seconds)
        .toInt();

    final nextEntry = (existingEntry ?? HistoryEntry.fromVideo(video))
        .copyWith(
          aid: aid,
          cid: cid,
          page: page,
          partTitle: partTitle,
          title: video.title,
          cover: video.cover,
          upperName: video.upper.name,
          duration: normalizedDuration,
          progressSeconds: normalizedProgress,
          viewedAt: viewedAt,
          isFinished: isFinished,
        )
        .withPartProgress(cid, normalizedProgress);

    await upsertHistoryEntry(nextEntry);
  }

  Future<int> getProgress(String bvid, int cid) async {
    final entry = await getHistoryEntry(bvid);
    if (entry == null) {
      return 0;
    }
    return entry.progressForCid(cid);
  }

  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
    await prefs.remove(_legacyHistoryKey);
    await prefs.remove(_legacyProgressKey);
  }

  List<HistoryEntry> _decodeEntries(List<String> rawEntries) {
    final entries = <HistoryEntry>[];

    for (final item in rawEntries) {
      try {
        final json = jsonDecode(item) as Map<String, dynamic>;
        entries.add(HistoryEntry.fromJson(json));
      } catch (e) {
        debugPrint('解析历史记录失败: $e');
      }
    }

    entries.sort((a, b) => b.viewedAt.compareTo(a.viewedAt));
    return entries;
  }

  Future<void> _persistEntries(
    SharedPreferences prefs,
    List<HistoryEntry> entries,
  ) async {
    final rawEntries = entries.map((entry) => jsonEncode(entry.toJson())).toList();
    await prefs.setStringList(_historyKey, rawEntries);
  }

  Future<List<HistoryEntry>> _migrateLegacyData(SharedPreferences prefs) async {
    final legacyHistory = prefs.getStringList(_legacyHistoryKey) ?? [];
    final rawProgress = prefs.getString(_legacyProgressKey);
    Map<String, dynamic> progressMap = {};

    if (rawProgress != null) {
      try {
        progressMap = jsonDecode(rawProgress) as Map<String, dynamic>;
      } catch (_) {
        progressMap = {};
      }
    }

    final migratedEntries = <HistoryEntry>[];
    for (final item in legacyHistory) {
      try {
        final json = jsonDecode(item) as Map<String, dynamic>;
        final video = Video.fromJson(json);
        final viewedAt = json['viewed_at'] ?? DateTime.now().millisecondsSinceEpoch;
        final partProgress = <String, int>{};

        for (final progressEntry in progressMap.entries) {
          final key = progressEntry.key;
          if (!key.startsWith('${video.bvid}_')) {
            continue;
          }

          final cid = key.substring(video.bvid.length + 1);
          final value = progressEntry.value;
          if (value is num) {
            partProgress[cid] = value.toInt();
          }
        }

        final primaryCid = partProgress.keys.isNotEmpty
            ? int.tryParse(partProgress.keys.first) ?? 0
            : 0;
        final primaryProgress = primaryCid == 0
            ? 0
            : partProgress['$primaryCid'] ?? 0;

        migratedEntries.add(
          HistoryEntry(
            bvid: video.bvid,
            title: video.title,
            cover: video.cover,
            upperName: video.upper.name,
            duration: video.duration,
            viewedAt: viewedAt,
            cid: primaryCid,
            progressSeconds: primaryProgress,
            partProgress: partProgress,
          ),
        );
      } catch (e) {
        debugPrint('迁移历史记录失败: $e');
      }
    }

    migratedEntries.sort((a, b) => b.viewedAt.compareTo(a.viewedAt));
    return migratedEntries;
  }
}
