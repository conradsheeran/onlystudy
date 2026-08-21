import 'package:audio_service/audio_service.dart';

import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';
import 'playback_session.dart';
import 'settings_service.dart';

late OnlyStudyAudioHandler audioHandler;

/// 通知栏快退/快进控制（label 按应用内语言本地化，OPT-017）。
class TransportControls {
  const TransportControls({required this.rewind, required this.forward});

  final MediaControl rewind;
  final MediaControl forward;
}

/// 按 [localeCode]（null 跟随系统）构造通知栏控制。
TransportControls buildTransportControls(String? localeCode) {
  final locale = localeCode == null || localeCode.isEmpty
      ? const Locale('zh')
      : Locale(localeCode);
  final l10n = lookupAppLocalizations(locale);
  return TransportControls(
    rewind: MediaControl(
      androidIcon: 'drawable/ic_notification_replay_10',
      label: l10n.rewind10,
      action: MediaAction.rewind,
    ),
    forward: MediaControl(
      androidIcon: 'drawable/ic_notification_forward_10',
      label: l10n.forward10,
      action: MediaAction.fastForward,
    ),
  );
}

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
    final controls = buildTransportControls(SettingsService().localeCode);
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          controls.rewind,
          if (state.playing) MediaControl.pause else MediaControl.play,
          controls.forward,
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
    playbackState.add(playbackState.value.copyWith(updatePosition: position));
  }

  @override
  void clearSession() {
    mediaItem.add(null);
    playbackState.add(
      PlaybackState(processingState: AudioProcessingState.idle, playing: false),
    );
  }
}
