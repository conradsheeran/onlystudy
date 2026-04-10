import 'package:audio_session/audio_session.dart';

import 'playback_bridge.dart';

class AudioSessionHandler {
  static final AudioSessionHandler _instance = AudioSessionHandler._internal();
  factory AudioSessionHandler() => _instance;
  AudioSessionHandler._internal();

  AudioSession? _session;
  bool _initialized = false;
  bool _resumeAfterInterruption = false;

  Future<void> init() async {
    if (_initialized) return;

    _session = await AudioSession.instance;
    await _session!.configure(const AudioSessionConfiguration.music());

    _session!.interruptionEventStream.listen((event) {
      if (event.begin) {
        if (!PlaybackBridgeService().isPlaying) return;
        switch (event.type) {
          case AudioInterruptionType.pause:
          case AudioInterruptionType.unknown:
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

  Future<void> setActive(bool active) async {
    await init();
    await _session?.setActive(active);
  }
}
