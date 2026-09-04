import 'dart:convert';
import 'package:flutter/services.dart';

import '../models/bili_models.dart';

/// 双击画面动作类型
enum DoubleTapAction { backward, playPause, forward }

/// 滑动手势认定的方向
enum DragDirection { none, horizontal, vertical }

/// 竖向滑动的屏幕分区
enum VerticalDragZone { brightness, none, volume }
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

  /// 双击四分区判定：<25%后退，25%-75%播放暂停，>75%快进
  static DoubleTapAction decideDoubleTapAction(double x, double totalWidth) {
    if (totalWidth <= 0) return DoubleTapAction.playPause;
    final fraction = x / totalWidth;
    if (fraction < 0.25) return DoubleTapAction.backward;
    if (fraction > 0.75) return DoubleTapAction.forward;
    return DoubleTapAction.playPause;
  }

  /// 25px 边缘死区：落入四边指定死区内返回 true
  static bool isWithinEdgeDeadZone(Offset point, Size size, {double deadZone = 25.0}) {
    return point.dx < deadZone ||
        point.dx > size.width - deadZone ||
        point.dy < deadZone ||
        point.dy > size.height - deadZone;
  }

  /// 3:1 比例方向锁：累计位移主轴必须超过副轴 3 倍才认定方向；斜滑或位移过小返回 none
  static DragDirection decideDragDirection(double totalDx, double totalDy, {double minDistance = 10.0}) {
    final absDx = totalDx.abs();
    final absDy = totalDy.abs();
    if (absDx >= 3 * absDy && absDx >= minDistance) {
      return DragDirection.horizontal;
    }
    if (absDy >= 3 * absDx && absDy >= minDistance) {
      return DragDirection.vertical;
    }
    return DragDirection.none;
  }

  /// 竖向三分区判定：左1/3亮度，右1/3音量，中间1/3留空
  static VerticalDragZone decideVerticalDragZone(double x, double totalWidth) {
    if (totalWidth <= 0) return VerticalDragZone.none;
    final fraction = x / totalWidth;
    if (fraction < 1.0 / 3.0) return VerticalDragZone.brightness;
    if (fraction > 2.0 / 3.0) return VerticalDragZone.volume;
    return VerticalDragZone.none;
  }

  /// 计算音量调节变化量（灵敏度 maxHeight * 0.5）
  static double calculateVolumeDelta(double deltaDy, double maxHeight) {
    if (maxHeight <= 0) return 0.0;
    return -deltaDy / (maxHeight * 0.5);
  }

  /// 计算亮度调节变化量（灵敏度 maxHeight * 3.0，更钝）
  static double calculateBrightnessDelta(double deltaDy, double maxHeight) {
    if (maxHeight <= 0) return 0.0;
    return -deltaDy / (maxHeight * 3.0);
  }
}
