import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter/foundation.dart';

late AudioHandler audioHandler;

Future<AudioHandler> initAudioService() async {
  audioHandler = await AudioService.init(
    builder: () => BiliAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.conradsheeran.onlystudy.channel.audio',
      androidNotificationChannelName: 'OnlyStudy Audio Service',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      androidNotificationIcon: 'mipmap/launcher_icon',
    ),
  );
  return audioHandler;
}

class BiliAudioHandler extends BaseAudioHandler with SeekHandler {
  final _player = AudioPlayer();

  BiliAudioHandler() {
    // 监听播放事件并更新状态
    _player.playbackEventStream.listen(_broadcastState);

    // 自动处理播放完成
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        stop();
      }
    });
  }

  /// 设置并播放音频
  Future<void> playAudio({
    required String url,
    required String title,
    required String artist,
    required String coverUrl,
    Duration? startAt,
    Map<String, String>? headers,
  }) async {
    // 设置元数据 (通知栏显示)
    final item = MediaItem(
      id: url,
      title: title,
      artist: artist,
      artUri: Uri.parse(coverUrl),
      duration: null, // 时长未知或随后更新
    );
    mediaItem.add(item);

    final actualHeaders = Map<String, String>.from(headers ?? {});
    if (!actualHeaders.containsKey('User-Agent')) {
      actualHeaders['User-Agent'] =
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
    }

    // 设置播放源
    try {
      if (startAt != null) {
        await _player.setUrl(url, headers: actualHeaders);
        await _player.seek(startAt);
      } else {
        await _player.setUrl(url, headers: actualHeaders);
      }
      play();
    } catch (e) {
      debugPrint('Error playing audio: $e');
    }
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  /// 广播播放状态给 AudioService
  void _broadcastState(PlaybackEvent event) {
    final playing = _player.playing;
    final queueIndex = event.currentIndex;

    playbackState.add(playbackState.value.copyWith(
      controls: [
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: queueIndex,
    ));
  }
}
