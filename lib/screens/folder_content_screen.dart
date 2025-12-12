import 'package:flutter/material.dart';
import '../models/bili_models.dart';
import '../widgets/video_tile.dart';
import '../widgets/error_view.dart';
import '../services/bili_api_service.dart';
import '../services/database_service.dart';
import 'video_player_screen.dart';
import '../widgets/custom_search_bar.dart';

class FolderContentScreen extends StatefulWidget {
  final Folder folder;

  const FolderContentScreen({super.key, required this.folder});

  @override
  State<FolderContentScreen> createState() => _FolderContentScreenState();
}

class _FolderContentScreenState extends State<FolderContentScreen> {
  final BiliApiService _biliApiService = BiliApiService();
  final DatabaseService _databaseService = DatabaseService();
  final ScrollController _scrollController = ScrollController();
  List<Video> _videos = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _error;
  int _page = 1;
  bool _hasMore = true;
  bool _isSearching = false;
  String _searchKeyword = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchVideos(refresh: true);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// 滚动监听，触底加载更多
  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        _hasMore) {
      _fetchVideos(refresh: false);
    }
  }

  /// 获取收藏夹内的视频列表 (支持分页和搜索)
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
        keyword: _searchKeyword,
      );
      
      if (mounted) {
        if (videos.isNotEmpty) {
           _databaseService.insertVideos(videos, widget.folder.id);
        }

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
        title: _isSearching
            ? CustomSearchBar(
                controller: _searchController,
                hintText: '在线搜索此收藏夹...',
                onSubmitted: (value) {
                  setState(() {
                    _searchKeyword = value;
                    _fetchVideos(refresh: true);
                  });
                },
                onClear: () {
                  setState(() {
                     _searchController.clear();
                     _searchKeyword = '';
                     _fetchVideos(refresh: true);
                  });
                },
              )
            : Text(widget.folder.title),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _isSearching = false;
                  _searchKeyword = '';
                  _searchController.clear();
                  _fetchVideos(refresh: true);
                } else {
                  _isSearching = true;
                }
              });
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorView(
                  message: _error!,
                  onRetry: () => _fetchVideos(refresh: true),
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
                                      playlist: _videos,
                                      initialIndex: index,
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