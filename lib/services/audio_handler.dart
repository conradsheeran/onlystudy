import 'package:audio_service/audio_service.dart';

import 'audio_session_handler.dart';
import 'playback_bridge.dart';

late OnlyStudyAudioHandler audioHandler;

Future<OnlyStudyAudioHandler> initAudioService() async {
  audioHandler = await AudioService.init(
    builder: OnlyStudyAudioHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.conradsheeran.onlystudy.channel.audio',
      androidNotificationChannelName: 'OnlyStudy Audio Service',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      androidNotificationIcon: 'mipmap/launcher_icon',
      androidNotificationChannelDescription: 'Background playback controls',
      fastForwardInterval: Duration(seconds: 10),
      rewindInterval: Duration(seconds: 10),
    ),
  );
  await AudioSessionHandler().init();
  return audioHandler;
}

class OnlyStudyAudioHandler extends BaseAudioHandler
    with SeekHandler
    implements PlaybackSessionSink {
  OnlyStudyAudioHandler() {
    PlaybackBridgeService().bindSessionSink(this);
  }

  @override
  Future<void> play() => PlaybackBridgeService().play();

  @override
  Future<void> pause() => PlaybackBridgeService().pause();

  @override
  Future<void> seek(Duration position) => PlaybackBridgeService().seek(position);

  @override
  Future<void> stop() async {
    await PlaybackBridgeService().stop();
    clearSession();
    await super.stop();
  }

  @override
  Future<void> updateMediaItem(MediaItem mediaItem) async {
    this.mediaItem.add(mediaItem);
  }

  @override
  void updatePlaybackState({
    required bool playing,
    required Duration position,
    required Duration bufferedPosition,
    required double speed,
    required PlaybackBridgeProcessingState processingState,
  }) {
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.rewind,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.fastForward,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: switch (processingState) {
          PlaybackBridgeProcessingState.idle => AudioProcessingState.idle,
          PlaybackBridgeProcessingState.loading => AudioProcessingState.loading,
          PlaybackBridgeProcessingState.buffering =>
            AudioProcessingState.buffering,
          PlaybackBridgeProcessingState.ready => AudioProcessingState.ready,
          PlaybackBridgeProcessingState.completed =>
            AudioProcessingState.completed,
        },
        playing: playing,
        updatePosition: position,
        bufferedPosition: bufferedPosition,
        speed: speed,
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
