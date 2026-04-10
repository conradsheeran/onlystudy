import 'bili_models.dart';

class HistoryEntry {
  final String bvid;
  final int aid;
  final int cid;
  final int page;
  final String partTitle;
  final String title;
  final String cover;
  final String upperName;
  final int duration;
  final int progressSeconds;
  final int viewedAt;
  final bool isFinished;
  final Map<String, int> partProgress;

  const HistoryEntry({
    required this.bvid,
    this.aid = 0,
    this.cid = 0,
    this.page = 1,
    this.partTitle = '',
    required this.title,
    required this.cover,
    required this.upperName,
    required this.duration,
    this.progressSeconds = 0,
    required this.viewedAt,
    this.isFinished = false,
    this.partProgress = const {},
  });

  factory HistoryEntry.fromJson(Map<String, dynamic> json) {
    final rawPartProgress = json['partProgress'];
    final parsedPartProgress = <String, int>{};

    if (rawPartProgress is Map) {
      for (final entry in rawPartProgress.entries) {
        final value = entry.value;
        if (value is num) {
          parsedPartProgress[entry.key.toString()] = value.toInt();
        }
      }
    }

    return HistoryEntry(
      bvid: json['bvid'] ?? '',
      aid: json['aid'] ?? 0,
      cid: json['cid'] ?? 0,
      page: json['page'] ?? 1,
      partTitle: json['partTitle'] ?? '',
      title: json['title'] ?? '未知视频',
      cover: json['cover'] ?? '',
      upperName: json['upperName'] ?? '未知UP主',
      duration: json['duration'] ?? 0,
      progressSeconds: json['progressSeconds'] ?? 0,
      viewedAt: json['viewedAt'] ?? 0,
      isFinished: json['isFinished'] ?? false,
      partProgress: parsedPartProgress,
    );
  }

  factory HistoryEntry.fromVideo(Video video) {
    return HistoryEntry(
      bvid: video.bvid,
      title: video.title,
      cover: video.cover,
      upperName: video.upper.name,
      duration: video.duration,
      viewedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'bvid': bvid,
      'aid': aid,
      'cid': cid,
      'page': page,
      'partTitle': partTitle,
      'title': title,
      'cover': cover,
      'upperName': upperName,
      'duration': duration,
      'progressSeconds': progressSeconds,
      'viewedAt': viewedAt,
      'isFinished': isFinished,
      'partProgress': partProgress,
    };
  }

  HistoryEntry copyWith({
    String? bvid,
    int? aid,
    int? cid,
    int? page,
    String? partTitle,
    String? title,
    String? cover,
    String? upperName,
    int? duration,
    int? progressSeconds,
    int? viewedAt,
    bool? isFinished,
    Map<String, int>? partProgress,
  }) {
    return HistoryEntry(
      bvid: bvid ?? this.bvid,
      aid: aid ?? this.aid,
      cid: cid ?? this.cid,
      page: page ?? this.page,
      partTitle: partTitle ?? this.partTitle,
      title: title ?? this.title,
      cover: cover ?? this.cover,
      upperName: upperName ?? this.upperName,
      duration: duration ?? this.duration,
      progressSeconds: progressSeconds ?? this.progressSeconds,
      viewedAt: viewedAt ?? this.viewedAt,
      isFinished: isFinished ?? this.isFinished,
      partProgress: partProgress ?? this.partProgress,
    );
  }

  Video toVideo() {
    return Video(
      bvid: bvid,
      title: title,
      cover: cover,
      duration: duration,
      upper: BiliUpper(mid: 0, name: upperName),
      view: 0,
      danmaku: 0,
      pubTimestamp: 0,
    );
  }

  int progressForCid(int cid) {
    final partValue = partProgress['$cid'];
    if (partValue != null) {
      return partValue;
    }
    if (this.cid == cid) {
      return progressSeconds;
    }
    return 0;
  }

  HistoryEntry withPartProgress(int cid, int progressSeconds) {
    final nextPartProgress = Map<String, int>.from(partProgress);
    nextPartProgress['$cid'] = progressSeconds;
    return copyWith(partProgress: nextPartProgress);
  }
}
