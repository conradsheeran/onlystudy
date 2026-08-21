import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:onlystudy/services/playback_session.dart';
import 'package:onlystudy/services/playback_settings.dart';

/// 可编程 [PlatformPlayer] 替身：记录命令、暴露可注入的流与状态。
class _FakePlatformPlayer extends PlatformPlayer {
  _FakePlatformPlayer() : super(configuration: const PlayerConfiguration());

  final List<String> commands = [];
  final List<Duration> seeks = [];

  var _playing = false;
  var _position = Duration.zero;
  final _buffer = Duration.zero;
  var _duration = Duration.zero;
  var _buffering = false;
  var _completed = false;
  var _rate = 1.0;

  final playingCtrl = StreamController<bool>.broadcast();
  final positionCtrl = StreamController<Duration>.broadcast();
  final bufferCtrl = StreamController<Duration>.broadcast();
  final durationCtrl = StreamController<Duration>.broadcast();
  final bufferingCtrl = StreamController<bool>.broadcast();
  final completedCtrl = StreamController<bool>.broadcast();

  void emitPlaying(bool v) {
    _playing = v;
    playingCtrl.add(v);
  }

  void emitPosition(Duration v) {
    _position = v;
    positionCtrl.add(v);
  }

  void emitDuration(Duration v) {
    _duration = v;
    durationCtrl.add(v);
  }

  void emitBuffering(bool v) {
    _buffering = v;
    bufferingCtrl.add(v);
  }

  void emitCompleted(bool v) {
    _completed = v;
    completedCtrl.add(v);
  }

  @override
  PlayerState get state => PlayerState(
    playing: _playing,
    position: _position,
    buffer: _buffer,
    duration: _duration,
    buffering: _buffering,
    completed: _completed,
    rate: _rate,
  );

  @override
  PlayerStream get stream => PlayerStream(
    const Stream.empty(),
    playingCtrl.stream,
    completedCtrl.stream,
    positionCtrl.stream,
    durationCtrl.stream,
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    bufferingCtrl.stream,
    const Stream.empty(),
    bufferCtrl.stream,
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
  );

  @override
  Future<void> play() async {
    commands.add('play');
    _playing = true;
  }

  @override
  Future<void> pause() async {
    commands.add('pause');
    _playing = false;
  }

  @override
  Future<void> seek(Duration duration) async {
    commands.add('seek');
    seeks.add(duration);
    _position = duration;
  }

  @override
  Future<void> setRate(double rate) async {
    commands.add('rate:$rate');
    _rate = rate;
  }

  @override
  Future<void> stop() async {
    commands.add('stop');
    _playing = false;
  }

  @override
  Future<void> dispose() async {
    commands.add('dispose');
    await super.dispose();
    await playingCtrl.close();
    await positionCtrl.close();
    await bufferCtrl.close();
    await durationCtrl.close();
    await bufferingCtrl.close();
    await completedCtrl.close();
  }
}

/// 记录会话 sink 收到的推送。
class _RecordingSink implements PlaybackSessionSink {
  final List<MediaItem?> mediaItems = [];
  final List<PlaybackSessionState> states = [];
  final List<Duration> positions = [];
  bool cleared = false;

  @override
  FutureOr<void> updateMediaItem(MediaItem item) async {
    mediaItems.add(item);
  }

  @override
  void updatePlaybackState(PlaybackSessionState state) {
    states.add(state);
  }

  @override
  void updatePosition(Duration position) {
    positions.add(position);
  }

  @override
  void clearSession() {
    cleared = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlaybackSession 挂载', () {
    test('attach 后绑定 sink 并推送当前媒体与状态', () {
      final player = Player(platformPlayer: _FakePlatformPlayer());
      final sink = _RecordingSink();
      final session = PlaybackSession(
        settings: _StubSettings(enableBackgroundPlayback: true),
      )..bindSink(sink);

      session.attachPlayer(player);
      session.updateMediaItem(
        id: 'bv1:1',
        title: '标题',
        artist: 'UP',
        coverUrl: 'https://example.com/cover.jpg',
      );

      expect(sink.mediaItems, hasLength(1));
      expect(sink.mediaItems.single!.id, 'bv1:1');
      expect(sink.mediaItems.single!.title, '标题');
      expect(sink.mediaItems.single!.artist, 'UP');
      expect(
        sink.mediaItems.single!.artUri.toString(),
        'https://example.com/cover.jpg',
      );
    });

    test('attach 后可从会话发出 play/pause/seek/stop', () async {
      final platform = _FakePlatformPlayer();
      final player = Player(platformPlayer: platform);
      final session = PlaybackSession(settings: _StubSettings());
      session.attachPlayer(player);

      await session.play();
      await session.pause();
      await session.seek(const Duration(seconds: 42));
      await session.stop();

      expect(platform.commands, ['play', 'pause', 'seek', 'stop']);
      expect(platform.seeks, [const Duration(seconds: 42)]);
    });

    test('detach 停止播放并清空会话 sink', () async {
      final platform = _FakePlatformPlayer();
      final player = Player(platformPlayer: platform);
      final sink = _RecordingSink();
      final session = PlaybackSession(settings: _StubSettings())
        ..bindSink(sink);
      session.attachPlayer(player);

      await session.detachPlayer(player, stopPlayback: true);

      expect(platform.commands, contains('stop'));
      expect(sink.cleared, isTrue);
      expect(session.hasActivePlayer, isFalse);
    });
  });

  group('PlaybackSession seek 钳制', () {
    test('seek 超过时长被钳制到时长', () async {
      final platform = _FakePlatformPlayer();
      final player = Player(platformPlayer: platform);
      final session = PlaybackSession(settings: _StubSettings());
      session.attachPlayer(player);

      platform.emitDuration(const Duration(seconds: 100));
      await Future<void>.delayed(Duration.zero);
      await session.seek(const Duration(seconds: 200));

      expect(platform.seeks.single, const Duration(seconds: 100));
    });

    test('seek 负数被钳制到 0', () async {
      final platform = _FakePlatformPlayer();
      final player = Player(platformPlayer: platform);
      final session = PlaybackSession(settings: _StubSettings());
      session.attachPlayer(player);

      await session.seek(const Duration(seconds: -5));

      expect(platform.seeks.single, Duration.zero);
    });
  });

  group('PlaybackSession 背景播放开关', () {
    test('关闭背景播放时 sink 不推送媒体/状态', () {
      final platform = _FakePlatformPlayer();
      final player = Player(platformPlayer: platform);
      final sink = _RecordingSink();
      final session = PlaybackSession(
        settings: _StubSettings(enableBackgroundPlayback: false),
      )..bindSink(sink);

      session.attachPlayer(player);
      session.updateMediaItem(
        id: 'bv1:1',
        title: 't',
        artist: 'a',
        coverUrl: '',
      );

      expect(sink.mediaItems, isEmpty);
      expect(sink.states, isEmpty);
    });

    test('开启背景播放时引擎事件推送到 sink', () async {
      final platform = _FakePlatformPlayer();
      final player = Player(platformPlayer: platform);
      final sink = _RecordingSink();
      final session = PlaybackSession(
        settings: _StubSettings(enableBackgroundPlayback: true),
      )..bindSink(sink);
      session.attachPlayer(player);
      session.updateMediaItem(
        id: 'bv1:1',
        title: 't',
        artist: 'a',
        coverUrl: '',
      );
      sink.mediaItems.clear();
      sink.states.clear();

      platform.emitPosition(const Duration(seconds: 10));
      platform.emitBuffering(true);

      await Future<void>.delayed(Duration.zero);

      expect(sink.positions, contains(const Duration(seconds: 10)));
      expect(
        sink.states.any(
          (s) => s.processingState == PlaybackSessionProcessingState.buffering,
        ),
        isTrue,
      );
    });
  });

  group('PlaybackSession 中断处理', () {
    test('收到中断开始事件时暂停播放', () async {
      final platform = _FakePlatformPlayer();
      final player = Player(platformPlayer: platform);
      final fakeAudioSession = _FakeAudioSession();
      final session = PlaybackSession(
        settings: _StubSettings(),
        audioSession: fakeAudioSession,
      );
      session.attachPlayer(player);
      platform.emitPlaying(true);
      await session.initAudioSession();

      fakeAudioSession.emitInterruption(
        AudioInterruptionEvent(true, AudioInterruptionType.pause),
      );

      await Future<void>.delayed(Duration.zero);

      expect(platform.commands, contains('pause'));
    });

    test('中断结束后恢复播放', () async {
      final platform = _FakePlatformPlayer();
      final player = Player(platformPlayer: platform);
      final fakeAudioSession = _FakeAudioSession();
      final session = PlaybackSession(
        settings: _StubSettings(),
        audioSession: fakeAudioSession,
      );
      session.attachPlayer(player);
      platform.emitPlaying(true);
      await session.initAudioSession();

      fakeAudioSession.emitInterruption(
        AudioInterruptionEvent(true, AudioInterruptionType.pause),
      );
      await Future<void>.delayed(Duration.zero);
      platform.commands.clear();

      fakeAudioSession.emitInterruption(
        AudioInterruptionEvent(false, AudioInterruptionType.pause),
      );
      await Future<void>.delayed(Duration.zero);

      expect(platform.commands, contains('play'));
    });
  });
}

/// 测试用设置快照：仅暴露背景播放开关。
class _StubSettings implements PlaybackSettings {
  _StubSettings({this.enableBackgroundPlayback = true});

  @override
  final bool enableBackgroundPlayback;
}

/// 记录配置与激活状态的可编程 AudioSession 替身。
class _FakeAudioSession implements AudioSessionAdapter {
  AudioSessionConfiguration? configured;
  int activeCount = 0;

  final _interruptionCtrl =
      StreamController<AudioInterruptionEvent>.broadcast();
  final _noisyCtrl = StreamController<void>.broadcast();

  @override
  Future<void> init() async {}

  @override
  Future<void> configure(AudioSessionConfiguration configuration) async {
    configured = configuration;
  }

  void emitInterruption(AudioInterruptionEvent event) {
    _interruptionCtrl.add(event);
  }

  void emitNoisy() {
    _noisyCtrl.add(null);
  }

  @override
  Stream<AudioInterruptionEvent> get interruptionEventStream =>
      _interruptionCtrl.stream;

  @override
  Stream<void> get becomingNoisyEventStream => _noisyCtrl.stream;

  @override
  Future<bool> setActive(bool active) async {
    activeCount++;
    return true;
  }
}
