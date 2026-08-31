import 'package:intl/intl.dart';

/// Bilibili UP主信息模型
class BiliUpper {
  final int mid;
  final String name;

  BiliUpper({
    required this.mid,
    required this.name,
  });

  /// 从通用 JSON 构造 UP 主基础信息
  factory BiliUpper.fromJson(Map<String, dynamic> json) {
    return BiliUpper(
      mid: json['mid'] ?? 0,
      name: json['name'] ?? '',
    );
  }
}

/// UP 主主页用户信息模型
class BiliUserInfo {
  final int mid;
  final String name;
  final String face;
  final String sign;
  final int level;
  final int fans;
  final int following;
  final int likes;
  final int archiveView;
  final int videoCount;

  BiliUserInfo({
    required this.mid,
    required this.name,
    required this.face,
    required this.sign,
    required this.level,
    required this.fans,
    required this.following,
    required this.likes,
    required this.archiveView,
    required this.videoCount,
  });

  /// 合并多个接口数据生成用户信息模型
  factory BiliUserInfo.fromApis({
    required Map<String, dynamic> info,
    required Map<String, dynamic> relation,
    required Map<String, dynamic> upstat,
    required Map<String, dynamic> navnum,
  }) {
    return BiliUserInfo(
      mid: info['mid'] ?? 0,
      name: info['name'] ?? '',
      face: info['face'] ?? '',
      sign: info['sign'] ?? '',
      level: info['level'] ?? 0,
      fans: relation['follower'] ?? 0,
      following: relation['following'] ?? 0,
      likes: upstat['likes'] ?? 0,
      archiveView: upstat['archive']?['view'] ?? 0,
      videoCount: navnum['video'] ?? 0,
    );
  }
}

/// UP 主分区统计模型
class UpSpaceCategory {
  final int tid;
  final String name;
  final int count;

  UpSpaceCategory({
    required this.tid,
    required this.name,
    required this.count,
  });

  /// 从空间分区统计 JSON 构造模型
  factory UpSpaceCategory.fromJson(Map<String, dynamic> json) {
    return UpSpaceCategory(
      tid: json['tid'] ?? 0,
      name: json['name'] ?? '',
      count: json['count'] ?? 0,
    );
  }
}

/// UP 主投稿分页模型
class UpSpaceVideoPage {
  final List<Video> videos;
  final List<UpSpaceCategory> categories;
  final bool hasMore;
  final int totalCount;
  final int pageNumber;

  UpSpaceVideoPage({
    required this.videos,
    required this.categories,
    required this.hasMore,
    required this.totalCount,
    required this.pageNumber,
  });
}

/// 关注列表中的 UP 主精简信息模型
class FollowUser {
  final int mid;
  final String name;
  final String face;
  final String sign;
  final int videoCount;

  FollowUser({
    required this.mid,
    required this.name,
    required this.face,
    required this.sign,
    this.videoCount = 0,
  });

  /// 从关注列表接口构造精简信息
  factory FollowUser.fromJson(Map<String, dynamic> json) {
    return FollowUser(
      mid: json['mid'] ?? 0,
      name: json['uname'] ?? json['name'] ?? '',
      face: json['face'] ?? '',
      sign: json['sign'] ?? '',
      videoCount: json['video_count'] ?? json['videos'] ?? 0,
    );
  }
}

/// UP 主合集（系列）模型
class UpSeries {
  final int id;
  final String title;
  final String cover;
  final int videoCount;

  UpSeries({
    required this.id,
    required this.title,
    required this.cover,
    required this.videoCount,
  });

  /// 从合集列表接口构造模型
  factory UpSeries.fromJson(Map<String, dynamic> json) {
    return UpSeries(
      id: json['series_id'] ?? json['id'] ?? 0,
      title: json['title'] ?? json['name'] ?? '',
      cover: json['cover'] ?? json['pic'] ?? 'https://via.placeholder.com/150',
      videoCount: json['video_count'] ?? json['count'] ?? json['number'] ?? 0,
    );
  }
}

/// 收藏夹信息模型
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
      title: json['title'] ?? '',
      mediaCount: json['media_count'] ?? 0,
      cover: json['cover'] ?? 'https://via.placeholder.com/150',
      upper: BiliUpper.fromJson(json['upper'] ?? {}),
      favState: json['fav_state'] ?? 0,
    );
  }
}

/// 合集信息模型 (订阅的合集)
class Season {
  final int id;
  final String title;
  final String cover;
  final BiliUpper upper;
  final int mediaCount;

  Season({
    required this.id,
    required this.title,
    required this.cover,
    required this.upper,
    required this.mediaCount,
  });

  factory Season.fromJson(Map<String, dynamic> json) {
    return Season(
      id: json['season_id'] ?? 0,
      title: json['title'] ?? '',
      cover: json['cover'] ?? '',
      upper: BiliUpper.fromJson(json['upper'] ?? {}),
      mediaCount: json['media_count'] ?? 0,
    );
  }
}

/// 视频基本信息模型 (用于列表展示)
class Video {
  final String bvid;
  final String title;
  final String cover;
  final int duration; // 时长 (秒)
  final BiliUpper upper; // UP主信息
  final int view; // 播放量
  final int danmaku; // 弹幕数
  final int pubTimestamp; // 发布时间戳

  Video({
    required this.bvid,
    required this.title,
    required this.cover,
    required this.duration,
    required this.upper,
    required this.view,
    required this.danmaku,
    required this.pubTimestamp,
  });

  /// 兼容收藏夹/空间稿件等多种数据格式的解析
  factory Video.fromJson(Map<String, dynamic> json) {
    final upperJson = json['upper'] ??
        json['owner'] ??
        {
          'mid': json['mid'] ?? 0,
          'name': json['author'] ?? '',
        };
    final pubTime = json['pub_time'] ?? json['pubdate'] ?? json['created'] ?? 0;

    int durationSeconds = json['duration'] ?? 0;
    if (durationSeconds == 0 && json['length'] is String) {
      final parts = (json['length'] as String).split(':');
      if (parts.length == 2) {
        final minutes = int.tryParse(parts[0]) ?? 0;
        final seconds = int.tryParse(parts[1]) ?? 0;
        durationSeconds = minutes * 60 + seconds;
      }
    }

    final viewCount = json['cnt_info']?['play'] ??
        json['stat']?['view'] ??
        json['play'] ??
        json['play_count'] ??
        json['view'] ??
        0;
    final danmakuCount = json['cnt_info']?['danmaku'] ??
        json['stat']?['danmaku'] ??
        json['video_review'] ??
        json['dm'] ??
        json['danmaku'] ??
        0;

    return Video(
      bvid: json['bvid'] ?? '',
      title: json['title'] ?? '',
      cover: json['cover'] ?? json['pic'] ?? 'https://via.placeholder.com/150',
      duration: durationSeconds,
      upper: BiliUpper.fromJson(upperJson),
      view: viewCount,
      danmaku: danmakuCount,
      pubTimestamp: pubTime,
    );
  }

  /// 返回格式化后的视频时长 mm:ss
  String get formattedDuration {
    final minutes = duration ~/ 60;
    final seconds = duration % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// 返回格式化后的播放量字符串
  /// 返回格式化后的播放量字符串（按 locale 使用万/亿或 K/M 等紧凑单位，OPT-017）。
  String formattedViewCount(String locale) => _compactCount(view, locale);

  /// 返回格式化后的弹幕数量字符串（紧凑单位，OPT-017）。
  String formattedDanmakuCount(String locale) => _compactCount(danmaku, locale);

  static String _compactCount(int value, String locale) =>
      NumberFormat.compact(locale: locale).format(value);

  /// 返回格式化后的发布时间
  String get formattedPubDate {
    if (pubTimestamp == 0) return '';
    final date = DateTime.fromMillisecondsSinceEpoch(pubTimestamp * 1000);
    final now = DateTime.now();
    if (now.year == date.year) {
      return '${date.month}-${date.day}';
    } else {
      return '${date.year}-${date.month}-${date.day}';
    }
  }
}

List<String> _jsonStrings(Object? value) {
  if (value is String) {
    return value.isEmpty ? const [] : [value];
  }
  if (value is! List) return const [];
  return value
      .whereType<String>()
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

List<int> _jsonInts(Object? value) {
  if (value is! List) return const [];
  return value
      .map(_jsonInt)
      .whereType<int>()
      .toList(growable: false);
}

int? _jsonInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

Map<String, dynamic>? _jsonMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}

List<Map<String, dynamic>> _jsonMaps(Object? value) {
  if (value is! List) return const [];
  return value
      .map(_jsonMap)
      .whereType<Map<String, dynamic>>()
      .toList(growable: false);
}

List<String> _mediaUrls(
  Map<String, dynamic> item, {
  required String primaryKey,
  String? alternatePrimaryKey,
}) {
  final urls = <String>[];
  var primary = item[primaryKey];
  if ((primary is! String || primary.isEmpty) &&
      alternatePrimaryKey != null) {
    primary = item[alternatePrimaryKey];
  }
  if (primary is String && primary.isNotEmpty) {
    urls.add(primary);
  }

  final backups = _jsonStrings(item['backup_url'] ?? item['backupUrl']);
  for (final backup in backups) {
    if (!urls.contains(backup)) urls.add(backup);
  }
  return urls;
}

Map<String, dynamic>? _selectVideoRepresentation(
  List<Map<String, dynamic>> representations,
  int targetQuality,
) {
  if (representations.isEmpty) return null;

  final withQuality = representations
      .where((representation) => _jsonInt(representation['id']) != null)
      .toList();
  if (withQuality.isEmpty) return representations.first;

  final notAboveTarget = withQuality
      .where((representation) =>
          _jsonInt(representation['id'])! <= targetQuality)
      .toList();
  final candidates = notAboveTarget.isNotEmpty ? notAboveTarget : withQuality;
  candidates.sort((a, b) {
    final aId = _jsonInt(a['id'])!;
    final bId = _jsonInt(b['id'])!;
    return aId.compareTo(bId);
  });
  // If every representation is above the target, the lowest one is the
  // closest available match; otherwise choose the highest one not above it.
  return notAboveTarget.isNotEmpty ? candidates.last : candidates.first;
}

Map<String, dynamic>? _selectAudioRepresentation(
  List<Map<String, dynamic>> representations,
) {
  if (representations.isEmpty) return null;

  final candidates = representations.toList();
  candidates.sort((a, b) {
    final idComparison = (_jsonInt(a['id']) ?? 0).compareTo(
      _jsonInt(b['id']) ?? 0,
    );
    if (idComparison != 0) return idComparison;
    return (_jsonInt(a['bandwidth']) ?? 0).compareTo(
      _jsonInt(b['bandwidth']) ?? 0,
    );
  });
  return candidates.last;
}

/// 视频播放地址信息模型 (包含清晰度信息)
class VideoPlayInfo {
  final String url;
  final String? audioUrl;
  final int quality;
  final List<int> acceptQuality;
  final List<String> acceptDescription;

  /// Progressive 响应中的完整 durl 分段，按 `order` 排序。
  final List<String> segmentUrls;

  /// durl 分段的时长，单位为毫秒，与 [segmentUrls] 一一对应。
  final List<int> segmentDurationsMs;

  /// DASH video representation 的备用地址。
  final List<String> backupUrls;

  /// DASH audio representation 的备用地址。
  final List<String> audioBackupUrls;

  VideoPlayInfo({
    required this.url,
    this.audioUrl,
    required this.quality,
    required this.acceptQuality,
    required this.acceptDescription,
    this.segmentUrls = const [],
    this.segmentDurationsMs = const [],
    this.backupUrls = const [],
    this.audioBackupUrls = const [],
  });

  factory VideoPlayInfo.fromJson(
    Map<String, dynamic> json, {
    int? targetQuality,
  }) {
    var url = '';
    String? audioUrl;
    var quality = _jsonInt(json['quality']) ?? 0;
    var segmentUrls = <String>[];
    var segmentDurationsMs = <int>[];
    var backupUrls = <String>[];
    var audioBackupUrls = <String>[];

    final dash = _jsonMap(json['dash']);
    final videoRepresentations = _jsonMaps(dash?['video']);
    if (videoRepresentations.isNotEmpty) {
      final requestedQuality = targetQuality ?? quality;
      final selectedVideo = _selectVideoRepresentation(
        videoRepresentations,
        requestedQuality,
      );
      if (selectedVideo != null) {
        final videoUrls = _mediaUrls(
          selectedVideo,
          primaryKey: 'baseUrl',
          alternatePrimaryKey: 'base_url',
        );
        if (videoUrls.isNotEmpty) {
          url = videoUrls.first;
          backupUrls = videoUrls.skip(1).toList(growable: false);
        }
        quality = _jsonInt(selectedVideo['id']) ?? quality;
      }

      final selectedAudio = _selectAudioRepresentation(
        _jsonMaps(dash?['audio']),
      );
      if (selectedAudio != null) {
        final audioUrls = _mediaUrls(
          selectedAudio,
          primaryKey: 'baseUrl',
          alternatePrimaryKey: 'base_url',
        );
        if (audioUrls.isNotEmpty) {
          audioUrl = audioUrls.first;
          audioBackupUrls = audioUrls.skip(1).toList(growable: false);
        }
      }
    }

    // DASH is preferred. If it is absent or unusable, retain every durl
    // segment so the player can build one continuous timeline.
    if (url.isEmpty) {
      final indexedDurl = _jsonMaps(json['durl']).asMap().entries.toList();
      indexedDurl.sort((a, b) {
        final aOrder = _jsonInt(a.value['order']);
        final bOrder = _jsonInt(b.value['order']);
        if (aOrder == null && bOrder == null) {
          return a.key.compareTo(b.key);
        }
        if (aOrder == null) return 1;
        if (bOrder == null) return -1;
        final orderComparison = aOrder.compareTo(bOrder);
        return orderComparison != 0
            ? orderComparison
            : a.key.compareTo(b.key);
      });

      for (final entry in indexedDurl) {
        final durl = entry.value;
        final urls = _mediaUrls(
          durl,
          primaryKey: 'url',
          alternatePrimaryKey: 'baseUrl',
        );
        if (urls.isEmpty) continue;
        segmentUrls.add(urls.first);
        segmentDurationsMs.add((_jsonInt(durl['length']) ?? 0).clamp(0, 1 << 31));
        if (backupUrls.isEmpty && urls.length > 1) {
          backupUrls = urls.skip(1).toList(growable: false);
        }
      }
      if (segmentUrls.isNotEmpty) url = segmentUrls.first;
    }

    return VideoPlayInfo(
      url: url,
      audioUrl: audioUrl,
      quality: quality,
      acceptQuality: _jsonInts(json['accept_quality']),
      acceptDescription: _jsonStrings(json['accept_description']),
      segmentUrls: segmentUrls,
      segmentDurationsMs: segmentDurationsMs,
      backupUrls: backupUrls,
      audioBackupUrls: audioBackupUrls,
    );
  }
}

/// 视频分P信息模型
class VideoPage {
  final int cid;
  final int page;
  final String part;
  final int duration;

  VideoPage({
    required this.cid,
    required this.page,
    required this.part,
    required this.duration,
  });

  factory VideoPage.fromJson(Map<String, dynamic> json) {
    return VideoPage(
      cid: json['cid'] ?? 0,
      page: json['page'] ?? 1,
      part: json['part'] ?? '',
      duration: json['duration'] ?? 0,
    );
  }
}

/// 视频详细信息模型 (包含 AID, CID, 历史进度, 分P列表)
class VideoDetail {
  final int bvid;
  final int aid;
  final int cid;
  final int historyProgress; // 观看进度(秒)
  final List<VideoPage> pages;

  VideoDetail({
    required this.aid,
    required this.cid,
    this.bvid = 0,
    this.historyProgress = 0,
    this.pages = const [],
  });

  factory VideoDetail.fromJson(Map<String, dynamic> json) {
    var pagesList = <VideoPage>[];
    if (json['pages'] != null) {
      for (var p in json['pages']) {
        pagesList.add(VideoPage.fromJson(p));
      }
    }

    return VideoDetail(
      aid: json['aid'] ?? 0,
      cid: json['cid'] ?? 0,
      historyProgress: json['history']?['progress'] ?? 0,
      pages: pagesList,
    );
  }
}
