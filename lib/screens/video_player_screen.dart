import 'dart:async';
import 'package:flutter/material.dart';
import 'package:onlystudy/l10n/app_localizations.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart' as mkv;
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/bili_models.dart';
import '../services/bili_api_service.dart';
import '../services/history_service.dart';
import '../services/download_service.dart';

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

  Video get _currentVideo => widget.playlist[_currentIndex];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
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

      _playInfo = await api.getVideoPlayUrl(_currentVideo.bvid, _cid!);
      
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

  /// 设置 media_kit 播放控制器 (设置 User-Agent, Referer)
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
    
    if (startAt != null) {
      await _player.seek(startAt);
    }
  }

  /// 检查视频播放结束，自动播放下一集或下一个视频
  void _checkVideoEnd() {
    if (_pages.isNotEmpty && _currentPartIndex < _pages.length - 1) {
      _switchPart(_currentPartIndex + 1);
    } else if (_currentIndex < widget.playlist.length - 1) {
      _playNext();
    }
  }

  /// 播放列表中的下一个视频
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
  
  /// 切换多P视频的分集
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

  /// 切换视频清晰度
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
  
  /// 显示分集列表底部弹窗
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

  @override
  Widget build(BuildContext context) {
    String title = _currentVideo.title;
    if (_pages.isNotEmpty && _pages.length > 1) {
       title += ' - P${_currentPartIndex + 1} ${_pages[_currentPartIndex].part}';
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(title, style: const TextStyle(fontSize: 16)),
        actions: [
          if (_pages.isNotEmpty && _pages.length > 1)
             IconButton(
              icon: const Icon(Icons.list),
              tooltip: '分集列表',
              onPressed: _showPartsList,
            ),
          IconButton(
            icon: const Icon(Icons.download),
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
              itemBuilder: (context) {
                return List.generate(_supportQualities.length, (index) {
                  final quality = _supportQualities[index];
                  final description = index < _supportQualityDescs.length 
                      ? _supportQualityDescs[index] 
                      : '$quality';
                  return PopupMenuItem(
                    value: quality,
                    child: Text(description),
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
        ],
      ),
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
                      ),
                      fullscreen: const mkv.MaterialVideoControlsThemeData(),
                      child: mkv.Video(controller: _controller),
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