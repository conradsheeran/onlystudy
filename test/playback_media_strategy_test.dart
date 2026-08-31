import 'package:flutter_test/flutter_test.dart';
import 'package:onlystudy/models/bili_models.dart';
import 'package:onlystudy/services/playback_media_strategy.dart';

void main() {
  test('DASH video 与 audio 使用 mpv EDL 合成单一连续媒体源', () {
    final info = VideoPlayInfo(
      url: 'video.m4s',
      audioUrl: 'audio.m4s',
      quality: 64,
      acceptQuality: const [64],
      acceptDescription: const ['720P'],
    );

    expect(
      PlaybackMediaStrategy.composeSource(info),
      'edl://!no_clip;!no_chapters;%9%video.m4s;'
      '!new_stream;!no_clip;!no_chapters;%9%audio.m4s',
    );
  });

  test('多段 durl 使用带时长的 EDL 保持连续时间线', () {
    final info = VideoPlayInfo(
      url: 'segment-1.m4s',
      quality: 64,
      acceptQuality: const [64],
      acceptDescription: const ['720P'],
      segmentUrls: const ['segment-1.m4s', 'segment-2.m4s'],
      segmentDurationsMs: const [1000, 2500],
    );

    expect(
      PlaybackMediaStrategy.composeSource(info),
      'edl://!no_clip;!no_chapters;'
      '%13%segment-1.m4s,length=1.0;'
      '%13%segment-2.m4s,length=2.5;',
    );
  });

  test('远端媒体启用缓存参数，本地媒体明确禁用缓存', () {
    expect(
      PlaybackMediaStrategy.mediaExtras(isLocal: false),
      {
        'cache': 'yes',
        'cache-secs': '30',
        'demuxer-hysteresis-secs': '20',
        'demuxer-max-bytes': '${64 * 1024 * 1024}',
        'demuxer-max-back-bytes': '${64 * 1024 * 1024}',
      },
    );
    expect(
      PlaybackMediaStrategy.mediaExtras(isLocal: true),
      {'cache': 'no'},
    );
  });

  test('横向 seek 按视频时长和屏宽计算并限制灵敏度', () {
    expect(
      PlaybackMediaStrategy.msPerPixel(
        durationMs: const Duration(hours: 1).inMilliseconds,
        screenWidth: 1000,
      ),
      900,
    );
    expect(
      PlaybackMediaStrategy.seekTargetMs(
        currentMs: 0,
        deltaPixels: 1000,
        durationMs: const Duration(hours: 1).inMilliseconds,
        screenWidth: 1000,
      ),
      const Duration(minutes: 15).inMilliseconds,
    );
    expect(
      PlaybackMediaStrategy.msPerPixel(
        durationMs: const Duration(seconds: 30).inMilliseconds,
        screenWidth: 1000,
      ),
      200,
    );
  });
}
