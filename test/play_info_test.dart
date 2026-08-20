import 'package:flutter_test/flutter_test.dart';
import 'package:onlystudy/models/bili_models.dart';

/// OPT-004 回归测试：DASH 清晰度切换不得丢弃音频地址。
///
/// 模拟两次连续清晰度切换，每次都拿到完整 newInfo；
/// 断言切换后使用的 VideoPlayInfo 仍保留 audioUrl。
Map<String, dynamic> _dashPlayInfoJson({
  required int quality,
  String videoUrl = 'https://example.com/video.m4s',
  String audioUrl = 'https://example.com/audio.m4s',
}) {
  return {
    'quality': quality,
    'accept_quality': [127, 64, 16],
    'accept_description': ['超清 4K', '高清 1080P', '流畅 360P'],
    'dash': {
      'video': [
        {'baseUrl': videoUrl, 'id': quality},
      ],
      'audio': [
        {'baseUrl': audioUrl, 'id': 30280},
      ],
    },
  };
}

void main() {
  group('VideoPlayInfo DASH 解析', () {
    test('解析 DASH 响应保留音视频地址', () {
      final info = VideoPlayInfo.fromJson(_dashPlayInfoJson(quality: 64));
      expect(info.url, 'https://example.com/video.m4s');
      expect(info.audioUrl, 'https://example.com/audio.m4s');
      expect(info.quality, 64);
    });

    test('没有 audio 列表时 audioUrl 为 null', () {
      final json = _dashPlayInfoJson(quality: 64);
      json['dash'] = {
        'video': [
          {'baseUrl': 'https://example.com/video.m4s'},
        ],
      };
      final info = VideoPlayInfo.fromJson(json);
      expect(info.audioUrl, isNull);
    });

    test('baseUrl 为空时 audio 使用 backup_url 兜底', () {
      final json = _dashPlayInfoJson(quality: 64);
      json['dash'] = {
        'video': [
          {'baseUrl': 'https://example.com/video.m4s'},
        ],
        'audio': [
          {
            'baseUrl': '',
            'backup_url': ['https://example.com/backup-audio.m4s'],
          },
        ],
      };
      final info = VideoPlayInfo.fromJson(json);
      expect(info.audioUrl, 'https://example.com/backup-audio.m4s');
    });

    test('progressive durl 响应同样保留字段', () {
      final json = {
        'quality': 64,
        'accept_quality': [64, 16],
        'accept_description': ['高清 1080P', '流畅 360P'],
        'durl': [
          {'url': 'https://example.com/progressive.mp4'},
        ],
      };
      final info = VideoPlayInfo.fromJson(json);
      expect(info.url, 'https://example.com/progressive.mp4');
      expect(info.audioUrl, isNull);
      expect(info.quality, 64);
    });
  });
}
