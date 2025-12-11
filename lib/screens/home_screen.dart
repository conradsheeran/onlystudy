import 'dart:async';
import 'package:flutter/material.dart';
import 'package:onlystudy/services/cache_service.dart';
import 'package:onlystudy/l10n/app_localizations.dart';
import '../models/bili_models.dart';
import '../widgets/folder_card.dart';
import '../widgets/video_tile.dart';
import '../widgets/custom_search_bar.dart';
import '../widgets/skeletons.dart';
import '../widgets/error_view.dart';
import 'folder_content_screen.dart';
import 'download_screen.dart';
import '../services/auth_service.dart';
import '../services/bili_api_service.dart';
import '../services/database_service.dart';
import 'login_screen.dart';
import 'history_screen.dart';
import 'video_player_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final BiliApiService _biliApiService = BiliApiService();
  final DatabaseService _databaseService = DatabaseService();
  final ScrollController _scrollController = ScrollController();
  List<Folder> _folders = [];
  List<Video> _searchResults = []; // Added for video search
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _error;
  int _page = 1;
  bool _hasMore = true;
  bool _isSearching = false;
  String _searchKeyword = '';
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;


  Future<void> _performSearch(String keyword) async {
    if (keyword.isEmpty) {
      if (mounted) {
        setState(() {
          _searchResults = [];
        });
      }
      return;
    }
    
    try {
      final videos = await _databaseService.searchVideos(keyword);
      if (mounted) {
        setState(() {
          _searchResults = videos;
        });
      }
    } catch (e) {
      debugPrint('Search error: $e');
    }
  }

  void _onSearchChanged(String value) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (value != _searchKeyword) {
          setState(() {
            _searchKeyword = value;
          });
          _performSearch(value);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _fetchFolders(refresh: true);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        _hasMore) {
      _fetchFolders(refresh: false);
    }
  }

  Future<void> _fetchFolders({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _isLoading = true;
        _error = null;
        _page = 1;
        _hasMore = true;
        _folders.clear();
      });
    } else {
      setState(() {
        _isLoadingMore = true;
      });
    }

    try {
      final folders = await _biliApiService.getFavoriteFolders(pn: _page);
      if (mounted) {
        setState(() {
          if (refresh) {
            _folders = folders;
          } else {
            _folders.addAll(folders);
          }
          
          if (folders.length < 20) {
            _hasMore = false;
          } else {
            _page++;
          }
        });
        
        // Start background sync if it's the first page refresh
        if (refresh) {
          _syncAllVideos(List.from(folders));
        }
      }
    } catch (e) {
      if (mounted) {
        if (refresh) {
          setState(() {
            _error = '加载收藏夹失败: ${e.toString()}';
          });
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('加载更多失败: ${e.toString()}')),
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  // Background sync to fetch and cache videos from all folders
  Future<void> _syncAllVideos(List<Folder> folders) async {
    for (var folder in folders) {
      if (!mounted) return;
      try {
        // Fetch first page of each folder to build cache
        // We limit to first page (20 videos) per folder to avoid API rate limits
        // In a real production app, this should be more robust with queueing
        final videos = await _biliApiService.getFolderVideos(folder.id, pn: 1, ps: 20);
        if (videos.isNotEmpty) {
           await _databaseService.insertVideos(videos, folder.id);
        }
        // Small delay to be nice to the API
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (e) {
        debugPrint('Sync failed for folder ${folder.id}: $e');
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
                onChanged: _onSearchChanged,
                onClear: () {
                  setState(() {
                    _searchController.clear();
                    _searchKeyword = '';
                    _searchResults = [];
                  });
                },
              )
            : Text(AppLocalizations.of(context)!.appTitle),
        actions: [
          if (!_isSearching)
            IconButton(
              icon: const Icon(Icons.cloud_download_outlined),
              tooltip: AppLocalizations.of(context)!.downloadCache,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const DownloadScreen()),
                );
              },
            ),
          if (!_isSearching)
            IconButton(
              icon: const Icon(Icons.history),
              tooltip: '本地观看历史', // Consider localizing this too
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const HistoryScreen()),
                );
              },
            ),
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _isSearching = false;
                  _searchKeyword = '';
                  _searchController.clear();
                  _searchResults = [];
                } else {
                  _isSearching = true;
                }
              });
            },
          ),
          if (!_isSearching)
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'logout') {
                await AuthService().logout();
                if (context.mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (context) => const LoginScreen()),
                    (route) => false,
                  );
                }
              } else if (value == 'refresh') {
                _fetchFolders(refresh: true);
              } else if (value == 'clear_cache') {
                await CacheService().clearCache();
                if (context.mounted) {
                   ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('缓存已清理')),
                   );
                }
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'refresh',
                child: Row(
                  children: [
                    Icon(Icons.refresh, color: Colors.black54),
                    SizedBox(width: 8),
                    Text('刷新收藏夹'),
                  ],
                ),
              ),
               const PopupMenuItem(
                value: 'clear_cache',
                child: Row(
                  children: [
                    Icon(Icons.cleaning_services_outlined, color: Colors.black54),
                    SizedBox(width: 8),
                    Text('清理缓存'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, color: Colors.black54),
                    SizedBox(width: 8),
                    Text('注销登录'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? GridView.builder(
              padding: const EdgeInsets.all(12.0),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.85,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: 8,
              itemBuilder: (context, index) => const FolderCardSkeleton(),
            )
          : _error != null
              ? ErrorView(
                  message: _error!,
                  onRetry: () => _fetchFolders(refresh: true),
                )
              : _isSearching
                  ? _buildSearchResults()
                  : RefreshIndicator(
                      onRefresh: () => _fetchFolders(refresh: true),
                      child: _folders.isEmpty
                          ? const Center(
                              child: Text('没有找到收藏夹，请登录或刷新'),
                            )
                          : Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: GridView.builder(
                                controller: _scrollController,
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  childAspectRatio: 0.85,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                ),
                                itemCount: _folders.length + (_hasMore ? 1 : 0),
                                itemBuilder: (context, index) {
                                  if (index == _folders.length) {
                                    return const Center(
                                      child: Padding(
                                        padding: EdgeInsets.all(8.0),
                                        child: CircularProgressIndicator(),
                                      ),
                                    );
                                  }
                                  return FolderCard(
                                    folder: _folders[index],
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              FolderContentScreen(folder: _folders[index]),
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                    ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
           ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('创建收藏夹功能待开发')),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_searchKeyword.isEmpty) {
      return const Center(child: Text('请输入关键词搜索视频'));
    }
    
    if (_searchResults.isEmpty) {
      return const Center(child: Text('没有找到相关视频'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final video = _searchResults[index];
        return VideoTile(
          video: video,
          onTap: () {
             Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => VideoPlayerScreen(
                  playlist: [video], // Only play this one from search for now
                  initialIndex: 0,
                ),
              ),
            );
          },
        );
      },
    );
  }
}
