import 'dart:async';
import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/bili_models.dart';
import '../services/bili_api_service.dart';
import '../services/history_service.dart';

class VideoPlayerScreen extends StatefulWidget {
  final Video video;

  const VideoPlayerScreen({super.key, required this.video});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  bool _isLoading = true;
  String? _error;
  int? _cid;
  VideoPlayInfo? _playInfo;
  VideoDetail? _videoDetail;
  Timer? _saveHistoryTimer;
  
  // 独立保存清晰度列表，防止切换时 API 返回不完整的列表导致选项丢失
  List<int> _supportQualities = [];
  List<String> _supportQualityDescs = [];

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable(); // 保持屏幕常亮
    _addToHistory(); // 添加到本地观看历史
    _initializePlayer();
  }

  Future<void> _addToHistory() async {
    await HistoryService().addWatchedVideo(widget.video);
  }

  @override
  void dispose() {
    _saveHistoryTimer?.cancel();
    _saveProgress(); // 退出时保存进度
    _videoPlayerController?.dispose();
    _chewieController?.dispose();
    WakelockPlus.disable(); // 取消屏幕常亮
    super.dispose();
  }

  Future<void> _initializePlayer() async {
    try {
      final api = BiliApiService();
      _videoDetail = await api.getVideoDetail(widget.video.bvid);
      _cid = _videoDetail!.cid;
      _playInfo = await api.getVideoPlayUrl(widget.video.bvid, _cid!);
      
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
              content: Text('已为您恢复到上次播放位置: ${_formatDuration(savedPosition)}'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }

      _saveHistoryTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        _saveProgress();
      });

    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '播放失败: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveProgress() async {
    if (_videoPlayerController != null && 
        _videoPlayerController!.value.isInitialized &&
        _videoDetail != null &&
        _cid != null) {
      final position = _videoPlayerController!.value.position.inSeconds;
      if (position > 5) {
         await BiliApiService().reportHistory(
           aid: _videoDetail!.aid,
           cid: _cid!,
           progress: position,
         );
      }
    }
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _setupController(String url, {Duration? startAt}) async {
    final newController = VideoPlayerController.networkUrl(
      Uri.parse(url),
      httpHeaders: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Referer': 'https://www.bilibili.com/video/${widget.video.bvid}',
      },
    );

    await newController.initialize();
    
    if (startAt != null) {
      await newController.seekTo(startAt);
    }

    _videoPlayerController?.dispose();
    _chewieController?.dispose();

    _videoPlayerController = newController;
    _chewieController = ChewieController(
      videoPlayerController: _videoPlayerController!,
      autoPlay: true,
      looping: false,
      aspectRatio: _videoPlayerController!.value.aspectRatio,
      errorBuilder: (context, errorMessage) {
        return Center(
          child: Text(
            errorMessage,
            style: const TextStyle(color: Colors.white),
          ),
        );
      },
      materialProgressColors: ChewieProgressColors(
        playedColor: const Color(0xFF2D7D9A),
        handleColor: const Color(0xFF2D7D9A),
        backgroundColor: Colors.grey,
        bufferedColor: Colors.white24,
      ),
    );
  }

  Future<void> _switchQuality(int quality) async {
    if (_cid == null || _playInfo == null) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('正在切换清晰度...'), duration: Duration(seconds: 1)),
    );

    try {
      final position = _videoPlayerController?.value.position;
      final api = BiliApiService();
      final newInfo = await api.getVideoPlayUrl(widget.video.bvid, _cid!, qn: quality);
      
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
          SnackBar(content: Text('切换清晰度失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(widget.video.title, style: const TextStyle(fontSize: 16)),
        actions: [
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
                  : Chewie(controller: _chewieController!),
        ),
      ),
    );
  }

  String _getCurrentQualityDesc() {
    if (_playInfo == null) return '清晰度';
    final index = _supportQualities.indexOf(_playInfo!.quality);
    if (index != -1 && index < _supportQualityDescs.length) {
      return _supportQualityDescs[index];
    }
    return '清晰度';
  }
}
