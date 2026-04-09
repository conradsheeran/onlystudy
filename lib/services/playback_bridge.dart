import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:media_kit/media_kit.dart';

import 'audio_session_handler.dart';
import 'settings_service.dart';

enum PlaybackBridgeProcessingState {
  idle,
  loading,
  buffering,
  ready,
  completed,
}

abstract class PlaybackSessionSink {
  FutureOr<void> updateMediaItem(MediaItem item);

  void updatePlaybackState({
    required bool playing,
    required Duration position,
    required Duration bufferedPosition,
    required double speed,
    required PlaybackBridgeProcessingState processingState,
  });

  void updatePosition(Duration position);

  void clearSession();
}

class PlaybackBridgeService {
  static final PlaybackBridgeService _instance = PlaybackBridgeService._internal();
  factory PlaybackBridgeService() => _instance;
  PlaybackBridgeService._internal();

  final List<StreamSubscription<dynamic>> _subscriptions = [];

  PlaybackSessionSink? _sessionSink;
  Player? _player;
  MediaItem? _mediaItem;

  bool _isBuffering = false;
  bool _isCompleted = false;
  Duration _position = Duration.zero;
  Duration _bufferedPosition = Duration.zero;
  Duration _duration = Duration.zero;

  bool get isPlaying => _player?.state.playing ?? false;
  bool get hasActivePlayer => _player != null;

  void bindSessionSink(PlaybackSessionSink sink) {
    _sessionSink = sink;
    _pushMediaItem();
    _pushPlaybackState();
  }

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
    _listenToPlayer(player);
    _pushMediaItem();
    _pushPlaybackState();
  }

  Future<void> detachPlayer(
    Player player, {
    bool stopPlayback = false,
  }) async {
    if (!identical(_player, player)) return;

    if (stopPlayback) {
      await stop();
    } else {
      await AudioSessionHandler().setActive(false);
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
    await AudioSessionHandler().setActive(true);
    _pushPlaybackState();
  }

  Future<void> pause({bool interrupted = false}) async {
    final player = _player;
    if (player == null) return;

    await player.pause();
    if (!interrupted) {
      await AudioSessionHandler().setActive(false);
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
    await AudioSessionHandler().setActive(false);
    _isCompleted = false;
    _position = Duration.zero;
    _bufferedPosition = Duration.zero;
    _pushPlaybackState(forceIdle: true);
  }

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

  void refreshConfiguration() {
    if (!SettingsService().enableBackgroundPlayback) {
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
        if (SettingsService().enableBackgroundPlayback) {
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
    if (!SettingsService().enableBackgroundPlayback) return;
    final item = _mediaItem;
    if (item == null) return;
    _sessionSink?.updateMediaItem(item);
  }

  void _pushPlaybackState({bool forceIdle = false}) {
    if (!SettingsService().enableBackgroundPlayback) return;

    _sessionSink?.updatePlaybackState(
      playing: !forceIdle && (_player?.state.playing ?? false),
      position: forceIdle ? Duration.zero : _position,
      bufferedPosition: forceIdle ? Duration.zero : _bufferedPosition,
      speed: forceIdle ? 1.0 : (_player?.state.rate ?? 1.0),
      processingState: _processingState(forceIdle: forceIdle),
    );
  }

  PlaybackBridgeProcessingState _processingState({bool forceIdle = false}) {
    if (forceIdle || _player == null) {
      return PlaybackBridgeProcessingState.idle;
    }

    if (_isCompleted) {
      return PlaybackBridgeProcessingState.completed;
    }
    if (_isBuffering) {
      return PlaybackBridgeProcessingState.buffering;
    }

    return PlaybackBridgeProcessingState.ready;
  }

  void _cancelSubscriptions() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
  }
}
