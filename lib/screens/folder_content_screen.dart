import 'package:flutter/material.dart';
import '../models/bili_models.dart';
import '../widgets/video_tile.dart';
import '../services/bili_api_service.dart';
import 'video_player_screen.dart';

class FolderContentScreen extends StatefulWidget {
  final Folder folder;

  const FolderContentScreen({super.key, required this.folder});

  @override
  State<FolderContentScreen> createState() => _FolderContentScreenState();
}

class _FolderContentScreenState extends State<FolderContentScreen> {
  final BiliApiService _biliApiService = BiliApiService();
  List<Video> _videos = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchVideos();
  }

  Future<void> _fetchVideos() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final videos = await _biliApiService.getFolderVideos(widget.folder.id);
      if (mounted) {
        setState(() {
          _videos = videos;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '加载视频失败: ${e.toString()}';
        });
      }
    }
    finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.folder.title),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.red),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _fetchVideos,
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetchVideos,
                  child: _videos.isEmpty
                      ? const Center(
                          child: Text('此收藏夹中没有视频。'),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _videos.length,
                          itemBuilder: (context, index) {
                            final video = _videos[index];
                            return VideoTile(
                              video: video,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => VideoPlayerScreen(
                                      bvid: video.bvid,
                                      title: video.title,
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                ),
    );
  }
}

