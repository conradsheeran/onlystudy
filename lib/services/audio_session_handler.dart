import 'package:flutter/widgets.dart';
import 'package:audio_session/audio_session.dart';

import 'playback_bridge.dart';
import 'settings_service.dart';

class AudioSessionHandler with WidgetsBindingObserver {
  static final AudioSessionHandler _instance = AudioSessionHandler._internal();
  factory AudioSessionHandler() => _instance;
  AudioSessionHandler._internal();

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
      if (event.begin) {
        if (!PlaybackBridgeService().isPlaying) return;
        switch (event.type) {
          case AudioInterruptionType.pause:
            _resumeAfterInterruption = true;
            PlaybackBridgeService().pause(interrupted: true);
            break;
          case AudioInterruptionType.unknown:
            if (_shouldIgnoreBackgroundUnknownInterruption()) {
              return;
            }
            _resumeAfterInterruption = true;
            PlaybackBridgeService().pause(interrupted: true);
            break;
          case AudioInterruptionType.duck:
            break;
        }
        return;
      }

      switch (event.type) {
        case AudioInterruptionType.pause:
          if (_resumeAfterInterruption) {
            PlaybackBridgeService().play();
          }
          break;
        case AudioInterruptionType.duck:
        case AudioInterruptionType.unknown:
          break;
      }
      _resumeAfterInterruption = false;
    });

    _session!.becomingNoisyEventStream.listen((_) {
      PlaybackBridgeService().pause();
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
