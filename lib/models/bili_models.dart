class BiliUpper {
  final int mid;
  final String name;

  BiliUpper({
    required this.mid,
    required this.name,
  });

  factory BiliUpper.fromJson(Map<String, dynamic> json) {
    return BiliUpper(
      mid: json['mid'] ?? 0,
      name: json['name'] ?? '未知UP主',
    );
  }
}

class Folder {
  final int id; // 收藏夹ID
  final String title;
  final int mediaCount; // 视频数量
  final String cover;
  final BiliUpper upper; // UP主信息
  final int favState; // 收藏状态，1表示收藏

  Folder({
    required this.id,
    required this.title,
    required this.mediaCount,
    required this.cover,
    required this.upper,
    required this.favState,
  });

  factory Folder.fromJson(Map<String, dynamic> json) {
    return Folder(
      id: json['id'] ?? 0,
      title: json['title'] ?? '未知收藏夹',
      mediaCount: json['media_count'] ?? 0,
      cover: json['cover'] ?? 'https://via.placeholder.com/150',
      upper: BiliUpper.fromJson(json['upper'] ?? {}),
      favState: json['fav_state'] ?? 0,
    );
  }
}

class Video {
  final String bvid;
  final String title;
  final String cover;
  final int duration; // 时长 (秒)
  final BiliUpper upper; // UP主信息
  final int view; // 播放量
  final int pubTimestamp; // 发布时间戳

  Video({
    required this.bvid,
    required this.title,
    required this.cover,
    required this.duration,
    required this.upper,
    required this.view,
    required this.pubTimestamp,
  });

  factory Video.fromJson(Map<String, dynamic> json) {
    return Video(
      bvid: json['bvid'] ?? '',
      title: json['title'] ?? '未知视频',
      cover: json['cover'] ?? 'https://via.placeholder.com/150',
      duration: json['duration'] ?? 0,
      upper: BiliUpper.fromJson(json['upper'] ?? {}),
      view: json['cnt_info']?['play'] ?? 0, // 播放量在 cnt_info 中
      pubTimestamp: json['pub_time'] ?? 0,
    );
  }

  String get formattedDuration {
    final minutes = duration ~/ 60;
    final seconds = duration % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}