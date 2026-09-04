import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart' as mkv;
import 'package:onlystudy/l10n/app_localizations.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:screen_brightness/screen_brightness.dart';

import '../models/bili_models.dart';
import '../models/history_entry.dart';
import '../models/playback_progress_snapshot.dart';
import '../services/playback_gateway.dart';
import '../services/playback_media_strategy.dart';
import '../services/bili_failure_message.dart';
import '../services/download_service.dart';
import '../services/history_service.dart';
import '../services/playback_completion_strategy.dart';
import '../services/playback_session.dart';
import '../services/progress_save_queue.dart';
import '../services/settings_service.dart';
import '../widgets/player_chrome.dart';
import '../widgets/error_view.dart';
import '../services/screen_mode_service.dart';

/// 视频播放器页面
class VideoPlayerScreen extends StatefulWidget {
  final List<Video> playlist;
  final int initialIndex;
  final String? localFilePath;
  final HistoryEntry? initialHistoryEntry;

  const VideoPlayerScreen({
    super.key,
    required this.playlist,
    required this.initialIndex,
    this.localFilePath,
    this.initialHistoryEntry,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen>
    with WidgetsBindingObserver {
  Player? _playerInstance;
  mkv.VideoController? _controllerInstance;
  StreamSubscription<bool>? _completedSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<Duration>? _bufferSubscription;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<bool>? _bufferingSubscription;
  bool _isFullscreen = false;
  bool _isLocked = false;
  Duration _currentPosition = Duration.zero;
  Duration _currentDuration = Duration.zero;
  Duration _currentBuffered = Duration.zero;
  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _fsProcessing = false;
  final GlobalKey _videoKey = GlobalKey();
  PlayerChromeHud? _activeHud;
  Timer? _hudTimer;
  late final Future<void> _playerBootstrap;
  bool _disposed = false;
  final PlaybackGateway _playback = PlaybackGateway();
  final PlaybackCompletionStrategy _completionStrategy =
      PlaybackCompletionStrategy();

  late int _currentIndex;
  bool _isLoading = true;
  String? _error;
  int? _cid;
  VideoPlayInfo? _playInfo;
  VideoDetail? _videoDetail;
  Timer? _saveHistoryTimer;
  late final ProgressSaveQueue _progressQueue;
  List<int> _supportQualities = [];
  List<String> _supportQualityDescs = [];

  List<VideoPage> _pages = [];
  int _currentPartIndex = 0;

  late double _playbackSpeed;
  late final ValueNotifier<double> _playbackSpeedNotifier;
  final ValueNotifier<int?> _qualityNotifier = ValueNotifier(null);
  int _qualitySwitchGeneration = 0;

  Player get _player => _playerInstance!;
  mkv.VideoController get _controller => _controllerInstance!;

  /// 获取当前播放中的视频
  Video get _currentVideo => widget.playlist[_currentIndex];

  HistoryEntry? get _resumeHistoryEntry {
    final entry = widget.initialHistoryEntry;
    if (entry == null || entry.bvid != _currentVideo.bvid) {
      return null;
    }
    return entry;
  }

  int get _currentPageNumber {
    if (_pages.isNotEmpty && _currentPartIndex < _pages.length) {
      return _pages[_currentPartIndex].page;
    }
    return 1;
  }

  String get _currentPartTitle {
    if (_pages.isNotEmpty && _currentPartIndex < _pages.length) {
      return _pages[_currentPartIndex].part;
    }
    return '';
  }

  int get _currentDurationSeconds {
    if (_pages.isNotEmpty && _currentPartIndex < _pages.length) {
      final pageDuration = _pages[_currentPartIndex].duration;
      if (pageDuration > 0) {
        return pageDuration;
      }
    }
    return _currentVideo.duration;
  }

  List<int> get _knownCids => _pages
      .map((page) => page.cid)
      .where((cid) => cid > 0)
      .toList(growable: false);

  /// 初始化组件状态并准备播放器
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentIndex = widget.initialIndex;
    _playbackSpeed = SettingsService().defaultPlaybackSpeed;
    _progressQueue = ProgressSaveQueue(persist: _persistSnapshot);
    _playbackSpeedNotifier = ValueNotifier(_playbackSpeed);

    WakelockPlus.enable();
    _playerBootstrap = _bootstrapPlayer();

    _playCurrentVideo();
  }

  Future<void> _bootstrapPlayer() async {
    final player = Player(
      configuration: const PlayerConfiguration(logLevel: MPVLogLevel.error),
    );
    final controller = mkv.VideoController(
      player,
      configuration: const mkv.VideoControllerConfiguration(
        androidAttachSurfaceAfterVideoParameters: false,
      ),
    );

    // Hosted media_kit doesn't expose Player.create/VideoController.create,
    // so we mirror that async setup by waiting until the native video
    // controller is actually created before wiring the player into the UI.
    await controller.platform.future;

    if (_disposed) {
      await player.dispose();
      return;
    }

    _playerInstance = player;
    _controllerInstance = controller;
    PlaybackSession.instance.attachPlayer(player);
    _completedSubscription = player.stream.completed.listen((completed) {
      if (completed) {
        _checkVideoEnd();
      }
    });
    _positionSubscription = player.stream.position.listen((pos) {
      if (!_disposed && mounted && pos.inSeconds != _currentPosition.inSeconds) {
        setState(() {
          _currentPosition = pos;
        });
      }
    });
    _durationSubscription = player.stream.duration.listen((dur) {
      if (!_disposed && mounted && dur != _currentDuration) {
        setState(() {
          _currentDuration = dur;
        });
      }
    });
    _bufferSubscription = player.stream.buffer.listen((buf) {
      if (!_disposed && mounted && buf != _currentBuffered) {
        setState(() {
          _currentBuffered = buf;
        });
      }
    });
    _playingSubscription = player.stream.playing.listen((playing) {
      if (!_disposed && mounted && playing != _isPlaying) {
        setState(() {
          _isPlaying = playing;
        });
      }
    });
    _bufferingSubscription = player.stream.buffering.listen((buffering) {
      if (!_disposed && mounted && buffering != _isBuffering) {
        setState(() {
          _isBuffering = buffering;
        });
      }
    });
  }

  /// 开始播放当前视频（初始化状态、记录历史、加载播放器）
  Future<void> _playCurrentVideo() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _pages = [];
      _currentPartIndex = 0;
      _playbackSpeed = SettingsService().defaultPlaybackSpeed;
    });

    await _playerBootstrap;
    if (_disposed || !mounted) {
      return;
    }

    await HistoryService().seedHistory(_currentVideo);
    await _initializePlayer();
  }

  /// 释放播放器及相关资源
  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _playbackSpeedNotifier.dispose();
    _qualityNotifier.dispose();
    _saveHistoryTimer?.cancel();
    _hudTimer?.cancel();
    _completedSubscription?.cancel();
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _bufferSubscription?.cancel();
    _playingSubscription?.cancel();
    _bufferingSubscription?.cancel();
    final player = _playerInstance;
    if (player != null) {
      _saveProgress();
      PlaybackSession.instance.detachPlayer(player, stopPlayback: true);
      player.dispose();
    }
    WakelockPlus.disable();
    if (_isFullscreen) {
      ScreenModeService().exitFullscreen();
    }
    ScreenModeService().reset();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (SettingsService().enableBackgroundPlayback) {
      return;
    }

    // Only pause once the app is actually backgrounded. `inactive` is a
    // transient state that also fires for system overlays.
    if ((state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden) &&
        _playerInstance?.state.playing == true) {
      PlaybackSession.instance.pause();
    }
  }

  /// 初始化播放器：获取详情、播放地址、设置控制器
  Future<void> _initializePlayer() async {
    try {
      if (widget.localFilePath != null) {
        await _setupController(
          VideoPlayInfo(
            url: widget.localFilePath!,
            quality: 0,
            acceptQuality: const [],
            acceptDescription: const [],
          ),
          isLocal: true,
        );
        _syncBackgroundPlaybackMetadata();
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }

      _videoDetail = await _playback.getVideoDetail(_currentVideo.bvid);

      _pages = _videoDetail!.pages;
      final localHistory = await HistoryService().getHistoryEntry(
        _currentVideo.bvid,
      );
      final resumeHistory = _resumeHistoryEntry ?? localHistory;
      final preferredCid = resumeHistory?.cid ?? _videoDetail!.cid;
      _cid = preferredCid > 0 ? preferredCid : _videoDetail!.cid;

      if (_pages.isNotEmpty) {
        final index = _pages.indexWhere((p) => p.cid == _cid);
        if (index != -1) {
          _currentPartIndex = index;
        } else {
          _cid = _videoDetail!.cid;
          final defaultIndex = _pages.indexWhere((p) => p.cid == _cid);
          if (defaultIndex != -1) {
            _currentPartIndex = defaultIndex;
          }
        }
      }

      try {
        _playInfo = await _playback.getVideoPlayUrl(_currentVideo.bvid, _cid!);
      } catch (e) {
        debugPrint(
          'Failed to get video url with default resolution: $e. Attempting fallback discovery...',
        );
        try {
          final lowQualityInfo = await _playback.getVideoPlayUrl(
            _currentVideo.bvid,
            _cid!,
            qn: 16,
          );
          if (lowQualityInfo.acceptQuality.isNotEmpty) {
            final bestQuality = lowQualityInfo.acceptQuality.first;
            if (bestQuality > 16) {
              try {
                _playInfo = await _playback.getVideoPlayUrl(
                  _currentVideo.bvid,
                  _cid!,
                  qn: bestQuality,
                );
              } catch (e3) {
                _playInfo = lowQualityInfo;
              }
            } else {
              _playInfo = lowQualityInfo;
            }
          } else {
            _playInfo = lowQualityInfo;
          }
        } catch (e2) {
          debugPrint('Fallback discovery failed: $e2');
          rethrow;
        }
      }

      if (_playInfo != null) {
        _supportQualities = _playInfo!.acceptQuality;
        _supportQualityDescs = _playInfo!.acceptDescription;
      }

      final historyService = HistoryService();
      final initialHistory = _resumeHistoryEntry;
      final resumeSeconds = initialHistory != null
          ? HistoryService.resolveResumePosition(
              initialHistory.progressForCid(_cid!),
              _currentDurationSeconds,
            )
          : await historyService.getResumePosition(
              _currentVideo.bvid,
              _cid!,
              _currentDurationSeconds,
            );

      await _setupController(
        _playInfo!,
        startAt: resumeSeconds > 0 ? Duration(seconds: resumeSeconds) : null,
      );
      _syncBackgroundPlaybackMetadata();
      await _saveProgress();
      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        if (resumeSeconds > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(
                  context,
                )!.resumePlayback(_formatDuration(resumeSeconds)),
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }

      _saveHistoryTimer?.cancel();
      _saveHistoryTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        _saveProgress();
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = AppLocalizations.of(
            context,
          )!.playFailed(e.toUserMessage(context));
          _isLoading = false;
        });
      }
    }
  }

  /// 在任何网络等待之前捕获当前播放进度的不可变快照。
  PlaybackProgressSnapshot _captureSnapshot({bool markFinished = false}) {
    final position = _player.state.position.inSeconds;
    final durationSeconds = _currentDurationSeconds;
    final effectivePosition = markFinished ? 0 : position;
    final isFinished =
        markFinished ||
        (durationSeconds > 0 && effectivePosition >= durationSeconds - 3);

    return PlaybackProgressSnapshot(
      video: _currentVideo,
      aid: _videoDetail?.aid ?? 0,
      cid: _cid ?? 0,
      page: _currentPageNumber,
      partTitle: _currentPartTitle,
      duration: durationSeconds,
      seconds: effectivePosition,
      isFinished: isFinished,
      knownCids: _knownCids,
    );
  }

  /// 串行化提交进度保存，避免并发读改写 SharedPreferences。
  Future<void> _saveProgress({bool markFinished = false}) {
    return _progressQueue.submit(_captureSnapshot(markFinished: markFinished));
  }

  /// 保存单个快照：本地写入优先，远程上报独立失败。
  Future<void> _persistSnapshot(PlaybackProgressSnapshot snapshot) async {
    if (snapshot.seconds > 5 && snapshot.aid > 0 && snapshot.cid > 0) {
      try {
        await _playback.reportHistory(
          aid: snapshot.aid,
          cid: snapshot.cid,
          progress: snapshot.seconds,
        );
      } catch (e) {
        // 远程上报失败不阻塞本地保存
        debugPrint('Failed to report history: $e');
      }
    }

    await HistoryService().savePlaybackProgress(
      video: snapshot.video,
      aid: snapshot.aid,
      cid: snapshot.cid,
      page: snapshot.page,
      partTitle: snapshot.partTitle,
      duration: snapshot.duration,
      seconds: snapshot.seconds,
      isFinished: snapshot.isFinished,
      knownCids: snapshot.knownCids,
    );
  }

  /// 将秒数格式化为分秒字符串
  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// 配置并启动播放器控制器
  Future<void> _setupController(
    VideoPlayInfo info, {
    Duration? startAt,
    bool isLocal = false,
    bool shouldPlay = true,
  }) async {
    _completionStrategy.reset();

    final httpHeaders = {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Referer': 'https://www.bilibili.com/video/${_currentVideo.bvid}',
    };

    final media = Media(
      PlaybackMediaStrategy.composeSource(info, isLocal: isLocal),
      httpHeaders: isLocal ? null : httpHeaders,
      start: startAt,
      extras: PlaybackMediaStrategy.mediaExtras(isLocal: isLocal),
    );

    await _player.open(media, play: false);
    _player.setRate(_playbackSpeed);

    if (shouldPlay) {
      await PlaybackSession.instance.play();
    }
  }

  void _syncBackgroundPlaybackMetadata() {
    final durationSeconds = _pages.isNotEmpty
        ? _pages[_currentPartIndex].duration
        : _currentVideo.duration;
    final title = _pages.length > 1
        ? _pages[_currentPartIndex].part
        : _currentVideo.title;

    PlaybackSession.instance.updateMediaItem(
      id: '${_currentVideo.bvid}:${_cid ?? _currentVideo.bvid}',
      title: title,
      artist: _currentVideo.upper.name,
      coverUrl: _currentVideo.cover,
      duration: durationSeconds > 0 ? Duration(seconds: durationSeconds) : null,
    );
  }

  /// 检查视频播放结束
  void _checkVideoEnd() {
    if (!_completionStrategy.shouldHandle(
      completed: true,
      isLoading: _isLoading,
    )) {
      return;
    }

    _saveProgress(markFinished: true);
    if (_pages.isNotEmpty && _currentPartIndex < _pages.length - 1) {
      _switchPart(_currentPartIndex + 1);
    } else if (_currentIndex < widget.playlist.length - 1) {
      _playNext();
    }
  }

  /// 播放下一个视频
  void _playNext() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppLocalizations.of(
            context,
          )!.nextVideo(widget.playlist[_currentIndex + 1].title),
        ),
        duration: const Duration(seconds: 2),
      ),
    );

    _saveProgress();
    setState(() {
      _currentIndex++;
    });
    _playCurrentVideo();
  }

  /// 切换分集
  Future<void> _switchPart(int index) async {
    if (index < 0 || index >= _pages.length) return;

    _saveProgress();

    setState(() {
      _isLoading = true;
      _currentPartIndex = index;
      _cid = _pages[index].cid;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppLocalizations.of(
            context,
          )!.playingPart((index + 1).toString(), _pages[index].part),
        ),
        duration: const Duration(seconds: 1),
      ),
    );

    try {
      _playInfo = await _playback.getVideoPlayUrl(_currentVideo.bvid, _cid!);

      if (_playInfo != null) {
        _supportQualities = _playInfo!.acceptQuality;
        _supportQualityDescs = _playInfo!.acceptDescription;
      }

      final localPosition = await HistoryService().getResumePosition(
        _currentVideo.bvid,
        _cid!,
        _currentDurationSeconds,
      );

      await _setupController(
        _playInfo!,
        startAt: localPosition > 0
            ? Duration(seconds: localPosition)
            : Duration.zero,
      );
      _syncBackgroundPlaybackMetadata();
      await _saveProgress();
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = AppLocalizations.of(
            context,
          )!.switchPartFailed(e.toUserMessage(context));
          _isLoading = false;
        });
      }
    }
  }

  /// 切换清晰度
  Future<void> _switchQuality(int quality) async {
    if (_cid == null || _playInfo == null) return;

    // 请求世代号：快速连续切换时旧响应不得覆盖新选择
    final requestGeneration = ++_qualitySwitchGeneration;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.switchingQuality),
        duration: const Duration(seconds: 1),
      ),
    );

    try {
      final position = _player.state.position;
      final wasPlaying = _player.state.playing;
      final newInfo = await _playback.getVideoPlayUrl(
        _currentVideo.bvid,
        _cid!,
        qn: quality,
      );

      if (requestGeneration != _qualitySwitchGeneration) {
        // 已有更新的清晰度选择，丢弃本次响应
        return;
      }

      // 保留完整 newInfo（含 audioUrl），避免 DASH 音轨丢失
      await _setupController(
        newInfo,
        startAt: position,
        shouldPlay: wasPlaying,
      );
      _syncBackgroundPlaybackMetadata();

      if (mounted) {
        setState(() {
          _playInfo = newInfo;
        });
        _qualityNotifier.value = newInfo.quality;
      }
    } catch (e) {
      if (requestGeneration != _qualitySwitchGeneration) {
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(
                context,
              )!.switchQualityFailed(e.toUserMessage(context)),
            ),
          ),
        );
      }
    }
  }

  /// 设置播放速度
  void _setPlaybackSpeed(double speed) {
    setState(() {
      _playbackSpeed = speed;
    });
    _playbackSpeedNotifier.value = speed;
    _player.setRate(speed);
    PlaybackSession.instance.refreshConfiguration();
  }


  /// 展示分集选择列表
  void _showPartsList() {
    showVideoPartsSheet(
      context: context,
      pages: _pages,
      currentPartIndex: _currentPartIndex,
      onSelectPart: (index) {
        if (index != _currentPartIndex) {
          _switchPart(index);
        }
      },
      isFullscreen: _isFullscreen,
    );
  }

  PlayerChromeState _buildPlayerChromeState() {
    final partLabel = (_pages.isNotEmpty &&
            _pages.length > 1 &&
            _currentPartIndex < _pages.length)
        ? 'P${_currentPartIndex + 1} ${_pages[_currentPartIndex].part}'
        : null;

    final duration = _currentDuration > Duration.zero
        ? _currentDuration
        : (_currentDurationSeconds > 0
            ? Duration(seconds: _currentDurationSeconds)
            : Duration.zero);

    return PlayerChromeState(
      position: _currentPosition,
      duration: duration,
      buffered: _currentBuffered,
      isPlaying: _isPlaying,
      isBuffering: _isBuffering,
      title: _currentVideo.title,
      partLabel: partLabel,
      speedLabel: '${_playbackSpeed}x',
      qualityLabel: _getCurrentQualityDesc(),
      hasParts: _pages.isNotEmpty && _pages.length > 1,
      isFullscreen: _isFullscreen,
      isLocked: _isLocked,
      hud: _activeHud,
      availableSpeeds: const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0],
      availableQualities: _supportQualities,
      availableQualityDescs: _supportQualityDescs,
      currentQuality: _playInfo?.quality,
    );
  }

  Future<void> _enterFullscreen() async {
    if (_fsProcessing || _isFullscreen) return;
    _fsProcessing = true;
    try {
      final width = _playerInstance?.state.width;
      final height = _playerInstance?.state.height;
      final orientations = PlaybackMediaStrategy.decideFullscreenOrientations(
        width: width,
        height: height,
      );
      await ScreenModeService().enterFullscreen(orientations);
    } finally {
      _fsProcessing = false;
      if (mounted) {
        setState(() {
          _isFullscreen = true;
        });
      }
    }
  }

  Future<void> _exitFullscreen() async {
    if (_fsProcessing || !_isFullscreen) return;
    _fsProcessing = true;
    try {
      await ScreenModeService().exitFullscreen();
    } finally {
      _fsProcessing = false;
      if (mounted) {
        setState(() {
          _isFullscreen = false;
          _isLocked = false;
        });
      }
    }
  }

  Future<void> _toggleFullscreen() async {
    if (_isFullscreen) {
      await _exitFullscreen();
    } else {
      await _enterFullscreen();
    }
  }

  Future<void> _handleBack() async {
    if (_isLocked) {
      setState(() => _isLocked = false);
    } else if (_isFullscreen) {
      await _exitFullscreen();
    } else {
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  PlayerChromeCallbacks _buildPlayerChromeCallbacks() {
    return PlayerChromeCallbacks(
      onBack: _handleBack,
      onPlayPause: () {
        if (_player.state.playing) {
          PlaybackSession.instance.pause();
        } else {
          PlaybackSession.instance.play();
        }
      },
      onSeek: (target) {
        PlaybackSession.instance.seek(target);
      },
      onToggleFullscreen: _toggleFullscreen,
      onToggleLock: () => setState(() => _isLocked = !_isLocked),
      onShowParts: _showPartsList,
      onSelectSpeed: _setPlaybackSpeed,
      onSelectQuality: _switchQuality,
      onDownload: () {
        if (_cid != null && _videoDetail != null) {
          DownloadService().startDownload(
            _currentVideo,
            _cid!,
            _videoDetail!.aid,
            qn: _playInfo?.quality ?? 64,
          );
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.addToDownload),
            ),
          );
        }
      },
      onVolumeDelta: (delta) async {
        final currentVol = await FlutterVolumeController.getVolume() ?? 0.5;
        final newVol = (currentVol + delta).clamp(0.0, 1.0);
        await FlutterVolumeController.setVolume(newVol);
        if (mounted) {
          setState(() {
            _activeHud = VolumeHud(newVol);
          });
          _hudTimer?.cancel();
          _hudTimer = Timer(const Duration(seconds: 1), () {
            if (mounted) setState(() => _activeHud = null);
          });
        }
      },
      onBrightnessDelta: (delta) async {
        try {
          final currentB = await ScreenBrightness().application;
          final newB = (currentB + delta).clamp(0.0, 1.0);
          await ScreenBrightness().setApplicationScreenBrightness(newB);
          if (mounted) {
            setState(() {
              _activeHud = BrightnessHud(newB);
            });
            _hudTimer?.cancel();
            _hudTimer = Timer(const Duration(seconds: 1), () {
              if (mounted) setState(() => _activeHud = null);
            });
          }
        } catch (_) {}
      },
    );
  }

  /// 构建播放器界面
  @override
  Widget build(BuildContext context) {
    final Widget playerContent = _isLoading
        ? const Center(
            child: CircularProgressIndicator(color: Colors.white),
          )
        : _error != null
            ? Center(
                child: ErrorView(
                  message: _error!,
                  onRetry: _playCurrentVideo,
                ),
              )
            : Stack(
                children: [
                  Center(
                    child: mkv.Video(
                      key: _videoKey,
                      controller: _controller,
                      pauseUponEnteringBackgroundMode:
                          !SettingsService().enableBackgroundPlayback,
                      controls: mkv.NoVideoControls,
                    ),
                  ),
                  PlayerChrome(
                    state: _buildPlayerChromeState(),
                    callbacks: _buildPlayerChromeCallbacks(),
                  ),
                ],
              );

    return PopScope(
      canPop: !_isFullscreen && !_isLocked,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_isLocked) {
          setState(() => _isLocked = false);
        } else if (_isFullscreen) {
          await _exitFullscreen();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: _isFullscreen
            ? playerContent
            : SafeArea(child: playerContent),
      ),
    );
  }

  /// 获取当前清晰度的描述文本
  String _getCurrentQualityDesc() {
    if (_playInfo == null) return AppLocalizations.of(context)!.quality;
    final index = _supportQualities.indexOf(_playInfo!.quality);
    if (index != -1 && index < _supportQualityDescs.length) {
      return _supportQualityDescs[index];
    }
    return AppLocalizations.of(context)!.quality;
  }
}
