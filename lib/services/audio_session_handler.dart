import 'package:flutter/widgets.dart';
import 'package:audio_session/audio_session.dart';

import 'settings_service.dart';

/// 音频会话可调用的播放控制回调。
///
/// 由播放桥接方注入，避免 AudioSessionHandler 反向依赖
/// PlaybackBridgeService（消除模块环依赖，OPT-012）。
class PlaybackControl {
  final bool Function() isPlaying;
  final void Function({bool interrupted}) pause;
  final void Function() play;

  const PlaybackControl({
    required this.isPlaying,
    required this.pause,
    required this.play,
  });
}

class AudioSessionHandler with WidgetsBindingObserver {
  static final AudioSessionHandler _instance = AudioSessionHandler._internal();
  factory AudioSessionHandler() => _instance;
  AudioSessionHandler._internal();

  /// 播放控制回调；由 PlaybackBridgeService 在 init 时注入。
  PlaybackControl? playbackControl;

  AudioSession? _session;
  bool _initialized = false;
  bool _resumeAfterInterruption = false;
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;

  Future<void> init() async {
    if (_initialized) return;

    WidgetsBinding.instance.addObserver(this);
    _session = await AudioSession.instance;
    await _session!.configure(const AudioSessionConfiguration.music());

    _session!.interruptionEventStream.listen((event) {
      final control = playbackControl;
      if (event.begin) {
        if (control == null || !control.isPlaying()) return;
        switch (event.type) {
          case AudioInterruptionType.pause:
            _resumeAfterInterruption = true;
            control.pause(interrupted: true);
            break;
          case AudioInterruptionType.unknown:
            if (_shouldIgnoreBackgroundUnknownInterruption()) {
              return;
            }
            _resumeAfterInterruption = true;
            control.pause(interrupted: true);
            break;
          case AudioInterruptionType.duck:
            break;
        }
        return;
      }

      switch (event.type) {
        case AudioInterruptionType.pause:
          if (_resumeAfterInterruption) {
            control?.play();
          }
          break;
        case AudioInterruptionType.duck:
        case AudioInterruptionType.unknown:
          break;
      }
      _resumeAfterInterruption = false;
    });

    _session!.becomingNoisyEventStream.listen((_) {
      playbackControl?.pause();
    });

    _initialized = true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appLifecycleState = state;
  }

  bool _shouldIgnoreBackgroundUnknownInterruption() {
    if (!SettingsService().enableBackgroundPlayback) {
      return false;
    }

    return _appLifecycleState == AppLifecycleState.inactive ||
        _appLifecycleState == AppLifecycleState.hidden ||
        _appLifecycleState == AppLifecycleState.paused;
  }

  Future<void> setActive(bool active) async {
    await init();
    await _session?.setActive(active);
  }
}
