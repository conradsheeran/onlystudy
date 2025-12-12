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

  DownloadTask({
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
      progress: map['progress'] ?? 0.0,
      status: DownloadStatus.values[map['status'] ?? 0],
      createTime: map['createTime'],
    );
  }

  DownloadTask copyWith({
    String? filePath,
    double? progress,
    DownloadStatus? status,
  }) {
    return DownloadTask(
      bvid: bvid,
      cid: cid,
      aid: aid,
      title: title,
      cover: cover,
      quality: quality,
      filePath: filePath ?? this.filePath,
      progress: progress ?? this.progress,
      status: status ?? this.status,
      createTime: createTime,
    );
  }
}
