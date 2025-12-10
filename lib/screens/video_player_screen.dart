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
      final cid = await api.getVideoCid(widget.bvid);
      // 2. 获取播放链接
      final playUrl = await api.getVideoPlayUrl(widget.bvid, cid);

      // 3. 初始化播放器
      // B站视频通常需要 Referer 头才能播放
      _videoPlayerController = VideoPlayerController.networkUrl(
        Uri.parse(playUrl),
        httpHeaders: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Referer': 'https://www.bilibili.com/video/${widget.bvid}',
        },
      );

      await _videoPlayerController!.initialize();

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // 沉浸式黑色背景
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(widget.title, style: const TextStyle(fontSize: 16)),
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
}
