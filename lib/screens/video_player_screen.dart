import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/bili_models.dart';
import '../services/bili_api_service.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String bvid;
  final String title;

  const VideoPlayerScreen({super.key, required this.bvid, required this.title});

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
  
  // 独立保存清晰度列表，防止切换时 API 返回不完整的列表导致选项丢失
  List<int> _supportQualities = [];
  List<String> _supportQualityDescs = [];

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable(); // 保持屏幕常亮
    _initializePlayer();
  }

  @override
  void dispose() {
    _videoPlayerController?.dispose();
    _chewieController?.dispose();
    WakelockPlus.disable(); // 取消屏幕常亮
    super.dispose();
  }

  Future<void> _initializePlayer() async {
    try {
      final api = BiliApiService();
      // 1. 获取 CID
      _cid = await api.getVideoCid(widget.bvid);
      // 2. 获取播放链接 (默认清晰度)
      _playInfo = await api.getVideoPlayUrl(widget.bvid, _cid!);
      
      // 初始化清晰度列表
      if (_playInfo != null) {
        _supportQualities = _playInfo!.acceptQuality;
        _supportQualityDescs = _playInfo!.acceptDescription;
      }

      await _setupController(_playInfo!.url);

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '播放失败: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _setupController(String url, {Duration? startAt}) async {
    // B站视频通常需要 Referer 头才能播放
    final newController = VideoPlayerController.networkUrl(
      Uri.parse(url),
      httpHeaders: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Referer': 'https://www.bilibili.com/video/${widget.bvid}',
      },
    );

    await newController.initialize();
    
    if (startAt != null) {
      await newController.seekTo(startAt);
    }

    // Dispose old controllers if they exist
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
      // 自定义一些 UI 颜色以匹配你的主题
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
    
    // Show a loading indicator overlay? Or just let the user know.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('正在切换清晰度...'), duration: Duration(seconds: 1)),
    );

    try {
      final position = _videoPlayerController?.value.position;
      final api = BiliApiService();
      final newInfo = await api.getVideoPlayUrl(widget.bvid, _cid!, qn: quality);
      
      await _setupController(newInfo.url, startAt: position);

      if (mounted) {
        setState(() {
          _playInfo = newInfo;
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
      backgroundColor: Colors.black, // 沉浸式黑色背景
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(widget.title, style: const TextStyle(fontSize: 16)),
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