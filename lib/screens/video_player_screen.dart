import 'dart:async';
import 'package:flutter/material.dart';
import 'package:onlystudy/l10n/app_localizations.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart' as mkv;
import 'package:screen_brightness/screen_brightness.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/bili_models.dart';
import '../services/bili_api_service.dart';
import '../services/history_service.dart';
import '../services/download_service.dart';
import '../services/settings_service.dart';

class VideoPlayerScreen extends StatefulWidget {
  final List<Video> playlist;
  final int initialIndex;
  final String? localFilePath;

  const VideoPlayerScreen({
    super.key,
    required this.playlist,
    required this.initialIndex,
    this.localFilePath,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final Player _player;
  late final mkv.VideoController _controller;
  
  late int _currentIndex;
  bool _isLoading = true;
  String? _error;
  int? _cid;
  VideoPlayInfo? _playInfo;
  VideoDetail? _videoDetail;
  Timer? _saveHistoryTimer;
  
  List<int> _supportQualities = [];
  List<String> _supportQualityDescs = [];
  
  List<VideoPage> _pages = [];
  int _currentPartIndex = 0;

  late double _playbackSpeed;
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

  Video get _currentVideo => widget.playlist[_currentIndex];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _playbackSpeed = SettingsService().defaultPlaybackSpeed;
    
    WakelockPlus.enable();
    _player = Player();
    _controller = mkv.VideoController(_player);

    _player.stream.completed.listen((completed) {
      if (completed) {
         _checkVideoEnd();
      }
    });

    _playCurrentVideo();
  }

  /// 开始播放当前视频 (初始化状态、记录历史、加载播放器)
  Future<void> _playCurrentVideo() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _pages = [];
      _currentPartIndex = 0;
      _playbackSpeed = SettingsService().defaultPlaybackSpeed;
    });
    
    await _addToHistory();
    await _initializePlayer();
  }

  /// 将当前视频添加到观看历史
  Future<void> _addToHistory() async {
    await HistoryService().addWatchedVideo(_currentVideo);
  }

  @override
  void dispose() {
    _saveHistoryTimer?.cancel();
    _overlayTimer?.cancel();
    _saveProgress();
    _player.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  /// 初始化播放器：获取详情、播放地址、设置控制器
  Future<void> _initializePlayer() async {
    try {
      if (widget.localFilePath != null) {
        await _setupController(widget.localFilePath!, isLocal: true);
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }

      final api = BiliApiService();
      _videoDetail = await api.getVideoDetail(_currentVideo.bvid);
      
      _pages = _videoDetail!.pages;
      _cid = _videoDetail!.cid;
      
      if (_pages.isNotEmpty) {
        final index = _pages.indexWhere((p) => p.cid == _cid);
        if (index != -1) {
          _currentPartIndex = index;
        }
      }

      try {
        _playInfo = await api.getVideoPlayUrl(_currentVideo.bvid, _cid!);
      } catch (e) {
        debugPrint('Failed to get video url with default resolution: $e. Attempting fallback discovery...');
        try {
          final lowQualityInfo = await api.getVideoPlayUrl(_currentVideo.bvid, _cid!, qn: 16);
          if (lowQualityInfo.acceptQuality.isNotEmpty) {
             final bestQuality = lowQualityInfo.acceptQuality.first;
             if (bestQuality > 16) {
                try {
                   _playInfo = await api.getVideoPlayUrl(_currentVideo.bvid, _cid!, qn: bestQuality);
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

      final savedPosition = _videoDetail!.historyProgress;
      
      await _setupController(
        _playInfo!.url, 
        startAt: savedPosition > 0 ? Duration(seconds: savedPosition) : null
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        
        if (savedPosition > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.resumePlayback(_formatDuration(savedPosition))),
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
          _error = AppLocalizations.of(context)!.playFailed(e.toString());
          _isLoading = false;
        });
      }
    }
  }

  /// 保存当前播放进度到 Bilibili 服务器
  Future<void> _saveProgress() async {
    final position = _player.state.position.inSeconds;
    if (position > 5 && _videoDetail != null && _cid != null) {
        await BiliApiService().reportHistory(
          aid: _videoDetail!.aid,
          cid: _cid!,
          progress: position,
        );
    }
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// 设置 media_kit 播放控制器
  Future<void> _setupController(String url, {Duration? startAt, bool isLocal = false}) async {
    final httpHeaders = {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Referer': 'https://www.bilibili.com/video/${_currentVideo.bvid}',
    };

    final media = Media(
      url, 
      httpHeaders: isLocal ? null : httpHeaders,
    );

    await _player.open(media, play: true);
    _player.setRate(_playbackSpeed);
    
    if (startAt != null) {
      await _player.seek(startAt);
    }
  }

  /// 检查视频播放结束
  void _checkVideoEnd() {
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
        content: Text(AppLocalizations.of(context)!.nextVideo(widget.playlist[_currentIndex + 1].title)),
        duration: const Duration(seconds: 2),
      ),
    );
    
    _saveProgress();
    setState(() {
      _currentIndex++;
    });
    _playCurrentVideo();
  }
  
  /// 切换分P
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
        content: Text('即将播放 P${index + 1}: ${_pages[index].part}'),
        duration: const Duration(seconds: 1),
      ),
    );

    try {
      final api = BiliApiService();
      _playInfo = await api.getVideoPlayUrl(_currentVideo.bvid, _cid!);
      
      if (_playInfo != null) {
        _supportQualities = _playInfo!.acceptQuality;
        _supportQualityDescs = _playInfo!.acceptDescription;
      }
      
      await _setupController(_playInfo!.url, startAt: Duration.zero);
      
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '切换分P失败: $e';
          _isLoading = false;
        });
      }
    }
  }

  /// 切换清晰度
  Future<void> _switchQuality(int quality) async {
    if (_cid == null || _playInfo == null) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.switchingQuality), duration: const Duration(seconds: 1)),
    );

    try {
      final position = _player.state.position;
      final api = BiliApiService();
      final newInfo = await api.getVideoPlayUrl(_currentVideo.bvid, _cid!, qn: quality);
      
      final updatedInfo = VideoPlayInfo(
        url: newInfo.url,
        quality: newInfo.quality,
        acceptQuality: _playInfo!.acceptQuality,
        acceptDescription: _playInfo!.acceptDescription,
      );
      
      await _setupController(updatedInfo.url, startAt: position);

      if (mounted) {
        setState(() {
          _playInfo = updatedInfo;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.switchQualityFailed(e.toString()))),
        );
      }
    }
  }

  /// 设置播放速度
  void _setPlaybackSpeed(double speed) {
    setState(() {
      _playbackSpeed = speed;
    });
    _player.setRate(speed);
    _showOverlayInfo(Icons.speed, '${AppLocalizations.of(context)!.speed} ${speed}x');
  }

  /// 显示覆盖信息 (音量/亮度/倍速)
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
                '分集列表 (${_pages.length})',
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
                        color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey,
                      ),
                    ),
                    title: Text(
                      page.part,
                      style: TextStyle(
                        color: isSelected ? Theme.of(context).colorScheme.primary : Colors.white,
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
          _player.pause();
        } else {
          _player.play();
        }
      },
      onLongPressStart: (_) {
         _player.setRate(2.0);
         _showOverlayInfo(
            Icons.fast_forward, 
            '${AppLocalizations.of(context)!.speed} 2.0x',
            autoHide: false 
         );
         // Hide overlay after 1.5 seconds even if held
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
         _player.setRate(_playbackSpeed); // Restore to selected speed
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

        // Determine area once at start
        if (x > screenWidth / 2) {
           _isAdjustingVolume = true;
           // Fetch initial volume
           FlutterVolumeController.getVolume().then((v) {
              _startVolume = v ?? 0.5;
           });
        } else {
           _isAdjustingBrightness = true;
           // Fetch initial brightness
           ScreenBrightness().application.then((v) {
              _startBrightness = v;
           }).catchError((e) {
              _startBrightness = 0.5; // Fallback
           });
        }
      },
      onVerticalDragUpdate: (details) async {
        if (!_isAdjustingVolume && !_isAdjustingBrightness) return;

        _accumulatedDy += details.primaryDelta ?? 0;
        
        // Sensitivity: 200px = 100% change
        // Delta is positive when dragging down (decrease), negative when up (increase)
        // So change = -delta / sensitivity
        double change = -_accumulatedDy / 200.0;

        if (_isAdjustingVolume && _startVolume != null) {
            double newVol = (_startVolume! + change).clamp(0.0, 1.0);
            await FlutterVolumeController.setVolume(newVol);
            _showOverlayInfo(
              newVol <= 0 ? Icons.volume_off : (newVol < 0.5 ? Icons.volume_down : Icons.volume_up), 
              '${(newVol * 100).toInt()}%'
            );
        } else if (_isAdjustingBrightness && _startBrightness != null) {
             try {
                double newB = (_startBrightness! + change).clamp(0.0, 1.0);
                await ScreenBrightness().setApplicationScreenBrightness(newB);
                _showOverlayInfo(Icons.brightness_medium, '${(newB * 100).toInt()}%');
             } catch (e) {
                // Ignore platform errors
             }
        }
      },
      onHorizontalDragStart: (details) {
         _seekTarget = _player.state.position;
      },
      onHorizontalDragUpdate: (details) {
         final delta = details.primaryDelta ?? 0;
         final currentMs = _seekTarget.inMilliseconds;
         // Drag sensitivity: 1px = 200ms
         final newMs = (currentMs + delta * 200).clamp(0, _player.state.duration.inMilliseconds).toInt();
         _seekTarget = Duration(milliseconds: newMs);
         
         final isForward = delta > 0;
         _showOverlayInfo(
            isForward ? Icons.fast_forward : Icons.fast_rewind, 
            _formatDuration(_seekTarget.inSeconds)
         );
      },
      onHorizontalDragEnd: (details) {
         _player.seek(_seekTarget);
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
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建顶部 App Bar 按钮列表
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
          tooltip: '分集列表',
          onPressed: _showPartsList,
        ),
      // Speed Control
      PopupMenuButton<double>(
        initialValue: _playbackSpeed,
        tooltip: AppLocalizations.of(context)!.playbackSpeed,
        onSelected: _setPlaybackSpeed,
        color: Colors.grey[900],
        itemBuilder: (context) {
          return [0.5, 0.75, 1.0, 1.25, 1.5, 2.0].map((speed) {
            return PopupMenuItem(
              value: speed,
              child: Text('${speed}x', style: const TextStyle(color: Colors.white)),
            );
          }).toList();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0),
          child: Center(
            child: Text(
              '${_playbackSpeed}x',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
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
                SnackBar(content: Text(AppLocalizations.of(context)!.addToDownload)),
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
                child: Text(description, style: const TextStyle(color: Colors.white)),
              );
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Center(
              child: Text(
                _getCurrentQualityDesc(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      // Removed AppBar to use custom TopBar in controls
      body: SafeArea(
        child: Center(
          child: _isLoading
              ? const CircularProgressIndicator(color: Colors.white)
              : _error != null
                  ? Text(
                      _error!,
                      style: const TextStyle(color: Colors.white),
                    )
                  : mkv.MaterialVideoControlsTheme(
                      normal: mkv.MaterialVideoControlsThemeData(
                        seekBarPositionColor: Theme.of(context).colorScheme.primary,
                        seekBarThumbColor: Theme.of(context).colorScheme.primary,
                        seekBarMargin: const EdgeInsets.fromLTRB(12, 0, 12, 60),
                        topButtonBar: _buildTopBarActions(),
                        topButtonBarMargin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      ),
                      fullscreen: mkv.MaterialVideoControlsThemeData(
                        topButtonBar: _buildTopBarActions(),
                        topButtonBarMargin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      ),
                      child: mkv.Video(
                        controller: _controller,
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

  String _getCurrentQualityDesc() {
    if (_playInfo == null) return AppLocalizations.of(context)!.quality;
    final index = _supportQualities.indexOf(_playInfo!.quality);
    if (index != -1 && index < _supportQualityDescs.length) {
      return _supportQualityDescs[index];
    }
    return AppLocalizations.of(context)!.quality;
  }
}