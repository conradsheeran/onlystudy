import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';

import 'playback_settings.dart';
import 'settings_service.dart';

/// 播放会话可观察的处理状态（OPT-012）。
enum PlaybackSessionProcessingState {
  idle,
  loading,
  buffering,
  ready,
  completed,
}

/// 推送给会话 sink 的不可变播放状态快照。
class PlaybackSessionState {
  final PlaybackSessionProcessingState processingState;
  final bool playing;
  final Duration position;
  final Duration bufferedPosition;
  final double speed;

  const PlaybackSessionState({
    required this.processingState,
    required this.playing,
    required this.position,
    required this.bufferedPosition,
    required this.speed,
  });
}

/// 会话的推送出口（生产为 OnlyStudyAudioHandler，测试可注入记录器）。
abstract class PlaybackSessionSink {
  FutureOr<void> updateMediaItem(MediaItem item);

  void updatePlaybackState(PlaybackSessionState state);

  void updatePosition(Duration position);

  void clearSession();
}


/// 音频会话适配（生产为 [RealAudioSessionAdapter]，测试可注入替身）。
///
/// 会话通过该接口统一获得 AudioSession 生命周期，
/// 不再需要 AudioSessionHandler 反向调用播放桥接（消除环依赖，OPT-012）。
abstract class AudioSessionAdapter {
  Future<void> init();

  Future<void> configure(AudioSessionConfiguration configuration);

  Stream<AudioInterruptionEvent> get interruptionEventStream;

  Stream<void> get becomingNoisyEventStream;

  Future<bool> setActive(bool active);
}

/// 基于 package:audio_session 的生产适配。
class RealAudioSessionAdapter implements AudioSessionAdapter {
  AudioSession? _session;

  @override
  Future<void> init() async {
    _session = await AudioSession.instance;
  }

  @override
  Future<void> configure(AudioSessionConfiguration configuration) async {
    await _session?.configure(configuration);
  }

  @override
  Stream<AudioInterruptionEvent> get interruptionEventStream =>
      _session?.interruptionEventStream ?? const Stream.empty();

  @override
  Stream<void> get becomingNoisyEventStream =>
      _session?.becomingNoisyEventStream ?? const Stream.empty();

  @override
  Future<bool> setActive(bool active) async {
    return await _session?.setActive(active) ?? false;
  }
}

/// 播放会话深模块（OPT-012）。
///
/// 同时拥有：
/// - 媒体播放：attach/detach、play/pause/seek/stop、媒体元数据与状态推送；
/// - AudioSession 生命周期：配置、激活、中断/噪音处理、生命周期观察。
///
/// 播放控制回调不再注入到独立的 AudioSessionHandler，中断事件直接驱动
/// 会话自身的 play/pause，从而消除 AudioSessionHandler ↔ PlaybackBridgeService
/// 的双向 import 环。
class PlaybackSession with WidgetsBindingObserver {
  PlaybackSession({
    PlaybackSettings? settings,
    AudioSessionAdapter? audioSession,
  }) : _settings = settings ?? SettingsService(),
       _audio = audioSession ?? RealAudioSessionAdapter();

  /// 应用内默认会话实例（与页面/音频服务共享，行为等同原单例）。
  static final PlaybackSession _default = PlaybackSession();
  static PlaybackSession get instance => _default;

  final PlaybackSettings _settings;
  final AudioSessionAdapter _audio;

  final List<StreamSubscription<dynamic>> _subscriptions = [];

  PlaybackSessionSink? _sessionSink;
  Player? _player;
  MediaItem? _mediaItem;
  bool _isBuffering = false;
  bool _isCompleted = false;
  Duration _position = Duration.zero;
  Duration _bufferedPosition = Duration.zero;
  Duration _duration = Duration.zero;

  bool _audioInitialized = false;
  bool _resumeAfterInterruption = false;
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;

  bool get isPlaying => _player?.state.playing ?? false;
  bool get hasActivePlayer => _player != null;

  /// 绑定会话 sink；绑定后立即推送当前媒体与状态。
  void bindSink(PlaybackSessionSink sink) {
    _sessionSink = sink;
    _pushMediaItem();
    _pushPlaybackState();
  }

  /// 初始化音频会话（配置 music 并订阅中断/噪音事件）。
  Future<void> initAudioSession() async {
    if (_audioInitialized) return;

    WidgetsBinding.instance.addObserver(this);
    await _audio.init();
    await _audio.configure(const AudioSessionConfiguration.music());

    _audio.interruptionEventStream.listen((event) {
      if (event.begin) {
        if (!isPlaying) return;
        switch (event.type) {
          case AudioInterruptionType.pause:
            _resumeAfterInterruption = true;
            pause(interrupted: true);
            break;
          case AudioInterruptionType.unknown:
            if (_shouldIgnoreBackgroundUnknownInterruption()) {
              return;
            }
            _resumeAfterInterruption = true;
            pause(interrupted: true);
            break;
          case AudioInterruptionType.duck:
            break;
        }
        return;
      }

      switch (event.type) {
        case AudioInterruptionType.pause:
          if (_resumeAfterInterruption) {
            play();
          }
          break;
        case AudioInterruptionType.duck:
        case AudioInterruptionType.unknown:
          break;
      }
      _resumeAfterInterruption = false;
    });

    _audio.becomingNoisyEventStream.listen((_) {
      pause();
    });

    _audioInitialized = true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appLifecycleState = state;
  }

  bool _shouldIgnoreBackgroundUnknownInterruption() {
    if (!_settings.enableBackgroundPlayback) {
      return false;
    }
    return _appLifecycleState == AppLifecycleState.inactive ||
        _appLifecycleState == AppLifecycleState.hidden ||
        _appLifecycleState == AppLifecycleState.paused;
  }

  /// 挂载播放器并开始监听其状态流。
  void attachPlayer(Player player) {
    if (identical(_player, player)) {
      _pushPlaybackState();
      return;
    }

    _cancelSubscriptions();
    _player = player;
    _position = player.state.position;
    _bufferedPosition = player.state.buffer;
    _duration = player.state.duration;
    _isCompleted = player.state.completed;
    _isBuffering = player.state.buffering;
    _listenToPlayer(player);
    _pushMediaItem();
    _pushPlaybackState();
  }

  /// 卸载播放器；[stopPlayback] 为 true 时先停止播放。
  Future<void> detachPlayer(
    Player player, {
    bool stopPlayback = false,
  }) async {
    if (!identical(_player, player)) return;

    if (stopPlayback) {
      await stop();
    } else {
      await _audio.setActive(false);
    }

    _cancelSubscriptions();
    _player = null;
    _position = Duration.zero;
    _bufferedPosition = Duration.zero;
    _duration = Duration.zero;
    _isBuffering = false;
    _isCompleted = false;
    _mediaItem = null;
    _sessionSink?.clearSession();
  }

  Future<void> play() async {
    final player = _player;
    if (player == null) return;

    await player.play();
    await _audio.setActive(true);
    _pushPlaybackState();
  }

  Future<void> pause({bool interrupted = false}) async {
    final player = _player;
    if (player == null) return;

    await player.pause();
    if (!interrupted) {
      await _audio.setActive(false);
    }
    _pushPlaybackState();
  }

  Future<void> seek(Duration position) async {
    final player = _player;
    if (player == null) return;

    if (position < Duration.zero) {
      position = Duration.zero;
    }
    final duration = _duration;
    if (duration > Duration.zero && position > duration) {
      position = duration;
    }

    await player.seek(position);
    _position = position;
    _sessionSink?.updatePosition(position);
    _pushPlaybackState();
  }

  Future<void> stop() async {
    final player = _player;
    if (player != null) {
      await player.stop();
    }
    await _audio.setActive(false);
    _isCompleted = false;
    _position = Duration.zero;
    _bufferedPosition = Duration.zero;
    _pushPlaybackState(forceIdle: true);
  }

  /// 更新通知栏媒体元数据。
  void updateMediaItem({
    required String id,
    required String title,
    required String artist,
    required String coverUrl,
    Duration? duration,
  }) {
    _mediaItem = MediaItem(
      id: id,
      title: title,
      artist: artist,
      artUri: coverUrl.isEmpty ? null : Uri.tryParse(coverUrl),
      duration: duration,
    );
    _pushMediaItem();
  }

  /// 背景播放开关变化后刷新通知栏状态。
  void refreshConfiguration() {
    if (!_settings.enableBackgroundPlayback) {
      _sessionSink?.clearSession();
      return;
    }
    _pushMediaItem();
    _pushPlaybackState();
  }

  void _listenToPlayer(Player player) {
    _subscriptions.addAll([
      player.stream.playing.listen((_) {
        _isCompleted = false;
        _pushPlaybackState();
      }),
      player.stream.position.listen((position) {
        _position = position;
        if (_settings.enableBackgroundPlayback) {
          _sessionSink?.updatePosition(position);
        }
      }),
      player.stream.buffer.listen((buffer) {
        _bufferedPosition = buffer;
        _pushPlaybackState();
      }),
      player.stream.duration.listen((duration) {
        _duration = duration;
        if (_mediaItem != null && duration > Duration.zero) {
          _mediaItem = _mediaItem!.copyWith(duration: duration);
          _pushMediaItem();
        }
        _pushPlaybackState();
      }),
      player.stream.buffering.listen((isBuffering) {
        _isBuffering = isBuffering;
        _pushPlaybackState();
      }),
      player.stream.completed.listen((completed) {
        _isCompleted = completed;
        _pushPlaybackState();
      }),
    ]);
  }

  void _pushMediaItem() {
    if (!_settings.enableBackgroundPlayback) return;
    final item = _mediaItem;
    if (item == null) return;
    _sessionSink?.updateMediaItem(item);
  }

  void _pushPlaybackState({bool forceIdle = false}) {
    if (!_settings.enableBackgroundPlayback) return;

    _sessionSink?.updatePlaybackState(
      PlaybackSessionState(
        playing: !forceIdle && (_player?.state.playing ?? false),
        position: forceIdle ? Duration.zero : _position,
        bufferedPosition: forceIdle ? Duration.zero : _bufferedPosition,
        speed: forceIdle ? 1.0 : (_player?.state.rate ?? 1.0),
        processingState: _processingState(forceIdle: forceIdle),
      ),
    );
  }

  PlaybackSessionProcessingState _processingState({bool forceIdle = false}) {
    if (forceIdle || _player == null) {
      return PlaybackSessionProcessingState.idle;
    }
    if (_isCompleted) {
      return PlaybackSessionProcessingState.completed;
    }
    if (_isBuffering) {
      return PlaybackSessionProcessingState.buffering;
    }
    return PlaybackSessionProcessingState.ready;
  }

  void _cancelSubscriptions() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
  }
}
