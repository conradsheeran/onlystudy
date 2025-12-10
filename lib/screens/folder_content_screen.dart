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
  final ScrollController _scrollController = ScrollController();
  List<Video> _videos = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _error;
  int _page = 1;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _fetchVideos(refresh: true);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        _hasMore) {
      _fetchVideos(refresh: false);
    }
  }

  Future<void> _fetchVideos({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _isLoading = true;
        _error = null;
        _page = 1;
        _hasMore = true;
        _videos.clear();
      });
    } else {
      setState(() {
        _isLoadingMore = true;
      });
    }

    try {
      final videos = await _biliApiService.getFolderVideos(
        widget.folder.id,
        pn: _page,
      );
      
      if (mounted) {
        setState(() {
          if (refresh) {
            _videos = videos;
          } else {
            _videos.addAll(videos);
          }
          
          if (videos.length < 20) {
            _hasMore = false;
          } else {
            _page++;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        if (refresh) {
          setState(() {
            _error = '加载视频失败: ${e.toString()}';
          });
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('加载更多失败: ${e.toString()}')),
          );
        }
      }
    }
    finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
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
                          onPressed: () => _fetchVideos(refresh: true),
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => _fetchVideos(refresh: true),
                  child: _videos.isEmpty
                      ? const Center(
                          child: Text('此收藏夹中没有视频。'),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(12),
                          // +1 for the loading indicator
                          itemCount: _videos.length + (_hasMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == _videos.length) {
                               return const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(8.0),
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                            }
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