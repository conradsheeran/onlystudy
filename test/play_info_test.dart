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

    test('DASH 选择不超过目标的最近 video 并保留音视频兜底地址', () {
      final info = VideoPlayInfo.fromJson(
        {
          'quality': 120,
          'accept_quality': [120, 80, 64, 32],
          'accept_description': ['4K', '1080P', '720P', '480P'],
          'dash': {
            'video': [
              {
                'id': 32,
                'baseUrl': 'https://example.com/video-32.m4s',
                'backup_url': ['https://example.com/video-32-backup.m4s'],
              },
              {
                'id': 80,
                'baseUrl': 'https://example.com/video-80.m4s',
                'backup_url': ['https://example.com/video-80-backup.m4s'],
              },
              {
                'id': 64,
                'baseUrl': 'https://example.com/video-64.m4s',
                'backup_url': [
                  'https://example.com/video-64-backup-1.m4s',
                  'https://example.com/video-64-backup-2.m4s',
                ],
              },
            ],
            'audio': [
              {
                'id': 30232,
                'bandwidth': 132000,
                'baseUrl': 'https://example.com/audio-132.m4s',
              },
              {
                'id': 30280,
                'bandwidth': 192000,
                'baseUrl': 'https://example.com/audio-192.m4s',
                'backup_url': ['https://example.com/audio-192-backup.m4s'],
              },
            ],
          },
        },
        targetQuality: 70,
      );

      expect(info.quality, 64);
      expect(info.url, 'https://example.com/video-64.m4s');
      expect(info.backupUrls, [
        'https://example.com/video-64-backup-1.m4s',
        'https://example.com/video-64-backup-2.m4s',
      ]);
      expect(info.audioUrl, 'https://example.com/audio-192.m4s');
      expect(info.audioBackupUrls, [
        'https://example.com/audio-192-backup.m4s',
      ]);
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

    test('目标低于所有 DASH 清晰度时选择最低可用表示', () {
      final info = VideoPlayInfo.fromJson(
        {
          'quality': 64,
          'dash': {
            'video': [
              {'id': 64, 'baseUrl': 'https://example.com/video-64.m4s'},
              {'id': 32, 'baseUrl': 'https://example.com/video-32.m4s'},
            ],
          },
        },
        targetQuality: 16,
      );

      expect(info.quality, 32);
      expect(info.url, 'https://example.com/video-32.m4s');
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

    test('多段 durl 按 order 保留完整有序地址与时长', () {
      final info = VideoPlayInfo.fromJson({
        'quality': 64,
        'durl': [
          {
            'order': 2,
            'length': 2000,
            'url': 'https://example.com/segment-2.mp4',
          },
          {
            'order': 1,
            'length': 1000,
            'url': 'https://example.com/segment-1.mp4',
          },
        ],
      });

      expect(info.segmentUrls, [
        'https://example.com/segment-1.mp4',
        'https://example.com/segment-2.mp4',
      ]);
      expect(info.segmentDurationsMs, [1000, 2000]);
      expect(info.url, 'https://example.com/segment-1.mp4');
    });
  });
}
