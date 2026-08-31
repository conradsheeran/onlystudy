import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart' as mkv;
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:onlystudy/l10n/app_localizations.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/bili_models.dart';
import '../models/history_entry.dart';
import '../models/playback_progress_snapshot.dart';
import '../services/playback_gateway.dart';
import '../services/bili_failure_message.dart';
import '../services/download_service.dart';
import '../services/history_service.dart';
import '../services/playback_completion_strategy.dart';
import '../services/playback_session.dart';
import '../services/progress_save_queue.dart';
import '../services/settings_service.dart';

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
  Timer? _positionGuardTimer;
  late final ProgressSaveQueue _progressQueue;
  List<int> _supportQualities = [];
  List<String> _supportQualityDescs = [];

  List<VideoPage> _pages = [];
  int _currentPartIndex = 0;

  late double _playbackSpeed;
  late final ValueNotifier<double> _playbackSpeedNotifier;
  final ValueNotifier<int?> _qualityNotifier = ValueNotifier(null);
  int _qualitySwitchGeneration = 0;
  bool _showOverlay = false;
  String _overlayText = '';
  IconData _overlayIcon = Icons.info;
  Timer? _overlayTimer;

  double _accumulatedDy = 0.0;
  double? _startVolume;
  double? _startBrightness;
  bool _isAdjustingVolume = false;
  bool _isAdjustingBrightness = false;

  Duration _seekTarget = Duration.zero;

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
    _positionGuardTimer?.cancel();
    _overlayTimer?.cancel();
    _completedSubscription?.cancel();
    final player = _playerInstance;
    if (player != null) {
      _saveProgress();
      PlaybackSession.instance.detachPlayer(player, stopPlayback: true);
      player.dispose();
    }
    WakelockPlus.disable();
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
        await _setupController(widget.localFilePath!, isLocal: true);
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
        _playInfo!.url,
        audioUrl: _playInfo!.audioUrl,
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
    String url, {
    String? audioUrl,
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

    final media = Media(url, httpHeaders: isLocal ? null : httpHeaders);

    await _player.open(media, play: false);

    if (audioUrl != null && audioUrl.isNotEmpty) {
      await _player.setAudioTrack(AudioTrack.uri(audioUrl));
    }

    _player.setRate(_playbackSpeed);

    Duration? effectiveTarget;

    if (startAt != null) {
      effectiveTarget = await _waitForReadyAndClamp(startAt);
      await PlaybackSession.instance.seek(effectiveTarget);
    }

    if (shouldPlay) {
      await PlaybackSession.instance.play();
    }

    if (effectiveTarget != null) {
      await _ensurePositionSticks(effectiveTarget);
      _startPositionGuard(effectiveTarget);
    }
  }

  /// 等待媒体就绪并对起始时间进行合理化处理
  Future<Duration> _waitForReadyAndClamp(Duration target) async {
    final durationFuture = _player.stream.duration
        .firstWhere((d) => d > Duration.zero)
        .timeout(const Duration(seconds: 3), onTimeout: () => Duration.zero);

    final bufferingFuture = _player.stream.buffering
        .firstWhere((b) => b == false)
        .timeout(const Duration(seconds: 3), onTimeout: () => false);

    final duration = await durationFuture;
    await bufferingFuture;

    if (duration > Duration.zero && target > duration) {
      target = duration - const Duration(milliseconds: 500);
    }
    if (target < Duration.zero) {
      target = Duration.zero;
    }
    return target;
  }

  /// 确保跳转位置稳定粘住
  Future<void> _ensurePositionSticks(Duration target) async {
    const attempts = 4;
    const interval = Duration(milliseconds: 220);

    for (var i = 0; i < attempts; i++) {
      await Future.delayed(interval);
      final current = _player.state.position;
      if ((current - target).abs() <= const Duration(milliseconds: 500)) {
        return;
      }
      await PlaybackSession.instance.seek(target);
    }
  }

  /// 短时间内守护位置防止回跳
  void _startPositionGuard(Duration target) {
    _positionGuardTimer?.cancel();
    var remaining = 8;
    _positionGuardTimer = Timer.periodic(const Duration(milliseconds: 250), (
      timer,
    ) {
      remaining--;
      if (remaining <= 0) {
        timer.cancel();
        return;
      }
      final current = _player.state.position;
      if ((current - target).abs() <= const Duration(milliseconds: 500)) {
        timer.cancel();
        return;
      }
      PlaybackSession.instance.seek(target);
    });
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
        _playInfo!.url,
        audioUrl: _playInfo!.audioUrl,
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
        newInfo.url,
        audioUrl: newInfo.audioUrl,
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
    _showOverlayInfo(
      Icons.speed,
      '${AppLocalizations.of(context)!.speed} ${speed}x',
    );
  }

  /// 显示覆盖信息（音量/亮度/倍速）
  void _showOverlayInfo(IconData icon, String text, {bool autoHide = true}) {
    setState(() {
      _showOverlay = true;
      _overlayIcon = icon;
      _overlayText = text;
    });
    _overlayTimer?.cancel();
    if (autoHide) {
      _overlayTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _showOverlay = false;
          });
        }
      });
    }
  }

  /// 展示分集选择列表
  void _showPartsList() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                '${AppLocalizations.of(context)!.partsList} (${_pages.length})',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _pages.length,
                itemBuilder: (context, index) {
                  final page = _pages[index];
                  final isSelected = index == _currentPartIndex;
                  return ListTile(
                    selected: isSelected,
                    selectedTileColor: Colors.white10,
                    leading: Text(
                      'P${page.page}',
                      style: TextStyle(
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey,
                      ),
                    ),
                    title: Text(
                      page.part,
                      style: TextStyle(
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Text(
                      _formatDuration(page.duration),
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      if (!isSelected) {
                        _switchPart(index);
                      }
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  /// 构建手势层
  Widget _buildGestureLayer(mkv.VideoState state) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onDoubleTap: () {
        if (_player.state.playing) {
          PlaybackSession.instance.pause();
        } else {
          PlaybackSession.instance.play();
        }
      },
      onLongPressStart: (_) {
        _player.setRate(2.0);
        PlaybackSession.instance.refreshConfiguration();
        _showOverlayInfo(
          Icons.fast_forward,
          '${AppLocalizations.of(context)!.speed} 2.0x',
          autoHide: false,
        );
        _overlayTimer?.cancel();
        _overlayTimer = Timer(const Duration(milliseconds: 1500), () {
          if (mounted && _showOverlay) {
            setState(() {
              _showOverlay = false;
            });
          }
        });
      },
      onLongPressEnd: (_) {
        _player.setRate(_playbackSpeed);
        PlaybackSession.instance.refreshConfiguration();
        if (_showOverlay) {
          setState(() {
            _showOverlay = false;
          });
        }
      },
      onVerticalDragStart: (details) {
        final screenWidth = MediaQuery.of(context).size.width;
        final x = details.globalPosition.dx;

        _accumulatedDy = 0.0;
        _isAdjustingVolume = false;
        _isAdjustingBrightness = false;

        if (x > screenWidth / 2) {
          _isAdjustingVolume = true;
          FlutterVolumeController.getVolume().then((v) {
            _startVolume = v ?? 0.5;
          });
        } else {
          _isAdjustingBrightness = true;
          ScreenBrightness().application
              .then((v) {
                _startBrightness = v;
              })
              .catchError((e) {
                _startBrightness = 0.5;
              });
        }
      },
      onVerticalDragUpdate: (details) async {
        if (!_isAdjustingVolume && !_isAdjustingBrightness) return;

        _accumulatedDy += details.primaryDelta ?? 0;

        double change = -_accumulatedDy / 200.0;

        if (_isAdjustingVolume && _startVolume != null) {
          double newVol = (_startVolume! + change).clamp(0.0, 1.0);
          await FlutterVolumeController.setVolume(newVol);
          _showOverlayInfo(
            newVol <= 0
                ? Icons.volume_off
                : (newVol < 0.5 ? Icons.volume_down : Icons.volume_up),
            '${(newVol * 100).toInt()}%',
          );
        } else if (_isAdjustingBrightness && _startBrightness != null) {
          try {
            double newB = (_startBrightness! + change).clamp(0.0, 1.0);
            await ScreenBrightness().setApplicationScreenBrightness(newB);
            _showOverlayInfo(
              Icons.brightness_medium,
              '${(newB * 100).toInt()}%',
            );
          } catch (e) {
            debugPrint('调整亮度失败: $e');
          }
        }
      },
      onHorizontalDragStart: (details) {
        _seekTarget = _player.state.position;
      },
      onHorizontalDragUpdate: (details) {
        final delta = details.primaryDelta ?? 0;
        final currentMs = _seekTarget.inMilliseconds;
        final newMs = (currentMs + delta * 200)
            .clamp(0, _player.state.duration.inMilliseconds)
            .toInt();
        _seekTarget = Duration(milliseconds: newMs);

        final isForward = delta > 0;
        _showOverlayInfo(
          isForward ? Icons.fast_forward : Icons.fast_rewind,
          _formatDuration(_seekTarget.inSeconds),
        );
      },
      onHorizontalDragEnd: (details) {
        PlaybackSession.instance.seek(_seekTarget);
      },
    );
  }

  /// 构建信息覆盖层
  Widget _buildOverlay() {
    if (!_showOverlay) return const SizedBox.shrink();
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_overlayIcon, color: Colors.white, size: 48),
            const SizedBox(height: 8),
            Text(
              _overlayText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建顶部按钮区域
  List<Widget> _buildTopBarActions() {
    return [
      IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
      Expanded(
        child: Text(
          _pages.isNotEmpty && _pages.length > 1
              ? '${_currentVideo.title} - P${_currentPartIndex + 1} ${_pages[_currentPartIndex].part}'
              : _currentVideo.title,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      if (_pages.isNotEmpty && _pages.length > 1)
        IconButton(
          icon: const Icon(Icons.list, color: Colors.white),
          tooltip: AppLocalizations.of(context)!.partsList,
          onPressed: _showPartsList,
        ),
      PopupMenuButton<double>(
        initialValue: _playbackSpeed,
        tooltip: AppLocalizations.of(context)!.playbackSpeed,
        onSelected: _setPlaybackSpeed,
        color: Colors.grey[900],
        itemBuilder: (context) {
          return [0.5, 0.75, 1.0, 1.25, 1.5, 2.0].map((speed) {
            return PopupMenuItem(
              value: speed,
              child: Text(
                '${speed}x',
                style: const TextStyle(color: Colors.white),
              ),
            );
          }).toList();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0),
          child: Center(
            child: ValueListenableBuilder<double>(
              valueListenable: _playbackSpeedNotifier,
              builder: (context, value, child) {
                return Text(
                  '${value}x',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                );
              },
            ),
          ),
        ),
      ),
      IconButton(
        icon: const Icon(Icons.download, color: Colors.white),
        tooltip: AppLocalizations.of(context)!.downloadCache,
        onPressed: () {
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
      ),
      if (_playInfo != null && _supportQualities.isNotEmpty)
        PopupMenuButton<int>(
          initialValue: _playInfo!.quality,
          onSelected: _switchQuality,
          color: Colors.grey[900],
          itemBuilder: (context) {
            return List.generate(_supportQualities.length, (index) {
              final quality = _supportQualities[index];
              final description = index < _supportQualityDescs.length
                  ? _supportQualityDescs[index]
                  : '$quality';
              return PopupMenuItem(
                value: quality,
                child: Text(
                  description,
                  style: const TextStyle(color: Colors.white),
                ),
              );
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Center(
              child: ValueListenableBuilder<int?>(
                valueListenable: _qualityNotifier,
                builder: (context, value, child) {
                  return Text(
                    _getCurrentQualityDesc(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
    ];
  }

  /// 构建播放器界面
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: _isLoading
              ? const CircularProgressIndicator(color: Colors.white)
              : _error != null
              ? Text(_error!, style: const TextStyle(color: Colors.white))
              : mkv.MaterialVideoControlsTheme(
                  normal: mkv.MaterialVideoControlsThemeData(
                    seekBarPositionColor: Theme.of(context).colorScheme.primary,
                    seekBarThumbColor: Theme.of(context).colorScheme.primary,
                    seekBarMargin: const EdgeInsets.fromLTRB(12, 0, 12, 60),
                    topButtonBar: _buildTopBarActions(),
                    topButtonBarMargin: const EdgeInsets.fromLTRB(
                      16,
                      16,
                      16,
                      0,
                    ),
                  ),
                  fullscreen: mkv.MaterialVideoControlsThemeData(
                    topButtonBar: _buildTopBarActions(),
                    topButtonBarMargin: const EdgeInsets.fromLTRB(
                      16,
                      16,
                      16,
                      0,
                    ),
                  ),
                  child: mkv.Video(
                    controller: _controller,
                    pauseUponEnteringBackgroundMode:
                        !SettingsService().enableBackgroundPlayback,
                    controls: (state) {
                      return Stack(
                        children: [
                          mkv.MaterialVideoControls(state),
                          _buildGestureLayer(state),
                          _buildOverlay(),
                        ],
                      );
                    },
                  ),
                ),
        ),
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
