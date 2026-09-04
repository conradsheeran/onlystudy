import 'dart:convert';
import 'package:flutter/services.dart';

import '../models/bili_models.dart';

/// Builds stable media sources for the native media_kit/mpv player.
class PlaybackMediaStrategy {
  static const Map<String, dynamic> _remoteMediaExtras = {
    'cache': 'yes',
    'cache-secs': '30',
    'demuxer-hysteresis-secs': '20',
    'demuxer-max-bytes': '${64 * 1024 * 1024}',
    'demuxer-max-back-bytes': '${64 * 1024 * 1024}',
  };

  /// Returns the mpv cache options for local or remote media.
  static Map<String, dynamic> mediaExtras({required bool isLocal}) {
    return isLocal
        ? {'cache': 'no'}
        : Map<String, dynamic>.from(_remoteMediaExtras);
  }

  /// Returns the horizontal seek distance represented by one screen pixel.
  static double msPerPixel({
    required int durationMs,
    required double screenWidth,
  }) {
    if (durationMs <= 0 || screenWidth <= 0) return 200.0;
    return (durationMs * 0.25 / screenWidth).clamp(200.0, 30000.0);
  }

  /// Calculates a clamped horizontal seek target.
  static int seekTargetMs({
    required int currentMs,
    required double deltaPixels,
    required int durationMs,
    required double screenWidth,
  }) {
    final target = currentMs +
        deltaPixels *
            msPerPixel(durationMs: durationMs, screenWidth: screenWidth);
    return target.clamp(0, durationMs.clamp(0, 1 << 62)).toInt();
  }

  /// Combines DASH video and audio into one mpv EDL source.
  static String composeSource(
    VideoPlayInfo info, {
    bool isLocal = false,
  }) {
    final videoSource = _videoSource(info, isLocal: isLocal);
    if (videoSource.isEmpty) return '';

    final audioUrl = info.audioUrl;
    if (audioUrl == null || audioUrl.isEmpty) return videoSource;

    return _composeTracks(
      videoSource,
      audioUrl,
      isLocal: isLocal,
    );
  }

  static String _videoSource(
    VideoPlayInfo info, {
    required bool isLocal,
  }) {
    if (info.segmentUrls.length > 1) {
      final buffer = StringBuffer('edl://!no_clip;!no_chapters;');
      for (var index = 0; index < info.segmentUrls.length; index++) {
        final url = info.segmentUrls[index];
        buffer.write('%${_edlLength(url, isLocal: isLocal)}%$url');
        final duration = index < info.segmentDurationsMs.length
            ? info.segmentDurationsMs[index]
            : 0;
        if (duration > 0) {
          buffer.write(',length=${duration / 1000}');
        }
        buffer.write(';');
      }
      return buffer.toString();
    }
    return info.url;
  }

  static int _edlLength(String url, {required bool isLocal}) {
    return isLocal ? utf8.encode(url).length : url.length;
  }

  static String _composeTracks(
    String videoUrl,
    String audioUrl, {
    required bool isLocal,
  }) {
    return 'edl://!no_clip;!no_chapters;'
        '%${_edlLength(videoUrl, isLocal: isLocal)}%$videoUrl;'
        '!new_stream;!no_clip;!no_chapters;'
        '%${_edlLength(audioUrl, isLocal: isLocal)}%$audioUrl';
  }

  /// 根据视频宽高比决策进入全屏时的目标方向：
  /// 宽高比 < 1.0 为竖屏视频，保持竖屏；否则锁定横屏。宽高未知或异常按横屏处理。
  static List<DeviceOrientation> decideFullscreenOrientations({
    int? width,
    int? height,
  }) {
    if (width != null && height != null && height > 0 && (width / height < 1.0)) {
      return const [DeviceOrientation.portraitUp];
    }
    return const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ];
  }

  /// 退出全屏时恢复的方向（明确为 portraitUp，避免解锁为任意方向）
  static List<DeviceOrientation> decideExitFullscreenOrientations() {
    return const [DeviceOrientation.portraitUp];
  }
}
