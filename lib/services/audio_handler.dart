import 'package:audio_service/audio_service.dart';

import 'playback_session.dart';

late OnlyStudyAudioHandler audioHandler;

const _rewind10Control = MediaControl(
  androidIcon: 'drawable/ic_notification_replay_10',
  label: 'Rewind 10 seconds',
  action: MediaAction.rewind,
);

const _fastForward10Control = MediaControl(
  androidIcon: 'drawable/ic_notification_forward_10',
  label: 'Fast forward 10 seconds',
  action: MediaAction.fastForward,
);

/// 初始化后台音频服务（OPT-012）。
///
/// 注册 [OnlyStudyAudioHandler] 作为会话 sink，并初始化音频会话
/// （配置、中断/噪音处理）。AudioService 通知栏控制全部转发给
/// [PlaybackSession.instance]。
Future<OnlyStudyAudioHandler> initAudioService() async {
  audioHandler = await AudioService.init(
    builder: OnlyStudyAudioHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.conradsheeran.onlystudy.channel.audio',
      androidNotificationChannelName: 'OnlyStudy Audio Service',
      androidNotificationOngoing: false,
      // Keep the media service in the foreground so Android 12+/Samsung
      // devices don't reject background resume after transient pauses.
      androidStopForegroundOnPause: false,
      androidNotificationIcon: 'drawable/ic_stat_onlystudy',
      androidNotificationChannelDescription: 'Background playback controls',
      fastForwardInterval: Duration(seconds: 10),
      rewindInterval: Duration(seconds: 10),
    ),
  );
  await PlaybackSession.instance.initAudioSession();
  return audioHandler;
}

/// 后台音频服务的薄适配层（OPT-012）。
///
/// 只负责把 AudioService 的媒体通知栏控制映射到 [PlaybackSession]，
/// 以及把会话推送的状态转换为 audio_service 的 [PlaybackState]。
/// 不再持有播放器桥接逻辑。
class OnlyStudyAudioHandler extends BaseAudioHandler
    with SeekHandler
    implements PlaybackSessionSink {
  OnlyStudyAudioHandler() {
    PlaybackSession.instance.bindSink(this);
  }

  @override
  Future<void> play() => PlaybackSession.instance.play();

  @override
  Future<void> pause() => PlaybackSession.instance.pause();

  @override
  Future<void> seek(Duration position) =>
      PlaybackSession.instance.seek(position);

  @override
  Future<void> stop() async {
    await PlaybackSession.instance.stop();
    clearSession();
    await super.stop();
  }

  @override
  Future<void> updateMediaItem(MediaItem mediaItem) async {
    this.mediaItem.add(mediaItem);
  }

  @override
  void updatePlaybackState(PlaybackSessionState state) {
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          _rewind10Control,
          if (state.playing) MediaControl.pause else MediaControl.play,
          _fastForward10Control,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: switch (state.processingState) {
          PlaybackSessionProcessingState.idle => AudioProcessingState.idle,
          PlaybackSessionProcessingState.loading =>
            AudioProcessingState.loading,
          PlaybackSessionProcessingState.buffering =>
            AudioProcessingState.buffering,
          PlaybackSessionProcessingState.ready => AudioProcessingState.ready,
          PlaybackSessionProcessingState.completed =>
            AudioProcessingState.completed,
        },
        playing: state.playing,
        updatePosition: state.position,
        bufferedPosition: state.bufferedPosition,
        speed: state.speed,
      ),
    );
  }

  @override
  void updatePosition(Duration position) {
    playbackState.add(
      playbackState.value.copyWith(
        updatePosition: position,
      ),
    );
  }

  @override
  void clearSession() {
    mediaItem.add(null);
    playbackState.add(
      PlaybackState(
        processingState: AudioProcessingState.idle,
        playing: false,
      ),
    );
  }
}
