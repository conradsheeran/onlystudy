/// 下载任务状态枚举
enum DownloadStatus { pending, running, paused, completed, failed }

/// 视频下载任务模型
class DownloadTask {
  final String bvid;
  final int cid;
  final int aid;
  final String title;
  final String cover;
  final int quality;
  final String? filePath;
  final double progress;
  final DownloadStatus status;
  final int createTime;

  /// 已下载字节数（用于启动恢复和持久化进度）
  final int downloadedBytes;

  /// 总字节数（未知时为 0）
  final int totalBytes;

  const DownloadTask({
    required this.bvid,
    required this.cid,
    required this.aid,
    required this.title,
    required this.cover,
    required this.quality,
    this.filePath,
    this.progress = 0.0,
    this.status = DownloadStatus.pending,
    required this.createTime,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'bvid': bvid,
      'cid': cid,
      'aid': aid,
      'title': title,
      'cover': cover,
      'quality': quality,
      'filePath': filePath,
      'progress': progress,
      'status': status.index,
      'createTime': createTime,
      'downloadedBytes': downloadedBytes,
      'totalBytes': totalBytes,
    };
  }

  factory DownloadTask.fromMap(Map<String, dynamic> map) {
    return DownloadTask(
      bvid: map['bvid'],
      cid: map['cid'],
      aid: map['aid'],
      title: map['title'],
      cover: map['cover'],
      quality: map['quality'],
      filePath: map['filePath'],
      progress: (map['progress'] as num?)?.toDouble() ?? 0.0,
      status: DownloadStatus.values[(map['status'] as num?)?.toInt() ?? 0],
      createTime: map['createTime'],
      downloadedBytes: (map['downloadedBytes'] as num?)?.toInt() ?? 0,
      totalBytes: (map['totalBytes'] as num?)?.toInt() ?? 0,
    );
  }

  DownloadTask copyWith({
    String? filePath,
    double? progress,
    DownloadStatus? status,
    int? downloadedBytes,
    int? totalBytes,
    bool clearProgress = false,
  }) {
    return DownloadTask(
      bvid: bvid,
      cid: cid,
      aid: aid,
      title: title,
      cover: cover,
      quality: quality,
      filePath: filePath ?? this.filePath,
      progress: clearProgress ? 0.0 : (progress ?? this.progress),
      status: status ?? this.status,
      createTime: createTime,
      downloadedBytes:
          clearProgress ? 0 : (downloadedBytes ?? this.downloadedBytes),
      totalBytes: clearProgress ? 0 : (totalBytes ?? this.totalBytes),
    );
  }
}
