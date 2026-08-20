import 'package:dio/dio.dart';

import '../models/bili_models.dart';
import 'bili_http_client.dart';
import 'settings_service.dart';

/// 播放领域模块（OPT-007）。
///
/// 负责：
/// - 视频详情（分集、CID、历史进度）。
/// - 播放地址（DASH/Progressive，支持清晰度选择）。
/// - 播放进度上报（静默失败，不阻塞本地保存）。
///
/// 所有请求通过 [BiliHttpClient] 统一发送，失败抛 [BiliFailure]。
class PlaybackGateway {
  PlaybackGateway({BiliHttpClient? client})
    : _client = client ?? BiliHttpClient();

  final BiliHttpClient _client;

  /// 获取视频详情（包含 CID、AID、历史进度）。
  Future<VideoDetail> getVideoDetail(String bvid) async {
    final data = await _client.get(
      '/x/web-interface/view',
      queryParameters: {'bvid': bvid},
    );
    return VideoDetail.fromJson(data['data']);
  }

  /// 获取播放地址。
  Future<VideoPlayInfo> getVideoPlayUrl(String bvid, int cid, {int? qn}) async {
    final data = await _client.get(
      '/x/player/playurl',
      queryParameters: {
        'bvid': bvid,
        'cid': cid,
        'qn': qn ?? SettingsService().defaultResolution,
        'fnval': 1,
        'fnver': 0,
        'fourk': 1,
      },
    );
    return VideoPlayInfo.fromJson(data['data']);
  }

  /// 上报播放进度（失败静默，不阻塞本地保存）。
  Future<void> reportHistory({
    required int aid,
    required int cid,
    required int progress,
  }) async {
    final csrf = await _client.authService.getCsrfToken();
    try {
      await _client.post(
        '/x/v2/history/report',
        data: {
          'aid': aid,
          'cid': cid,
          'progress': progress,
          'platform': 'android',
          'csrf': csrf,
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
    } catch (e) {
      // 忽略上报错误
    }
  }
}
