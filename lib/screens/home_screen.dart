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
import 'select_folders_screen.dart';

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
  List<Video> _searchResults = [];
  List<int> _visibleFolderIds = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _error;
  int _page = 1;
  bool _hasMore = true;
  bool _isSearching = false;
  String _searchKeyword = '';
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  bool _isLocked = false;


  /// 执行搜索逻辑，支持按可见收藏夹过滤
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
      final videos = await _databaseService.searchVideos(keyword, visibleFolderIds: _visibleFolderIds);
      if (mounted) {
        setState(() {
          _searchResults = videos;
        });
      }
    } catch (e) {
      debugPrint('Search error: $e');
    }
  }

  /// 处理搜索框输入变化，带防抖 (500ms)
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
    _initData();
    _scrollController.addListener(_onScroll);
  }

  /// 初始化数据：获取可见收藏夹ID和锁定状态
  Future<void> _initData() async {
    _visibleFolderIds = await AuthService().getVisibleFolderIds();
    final locked = await AuthService().isFolderSelectionLocked();
    setState(() {
      _isLocked = locked;
    });
    _fetchFolders(refresh: true);
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

  /// 获取收藏夹列表 (支持分页和可见性过滤)
  Future<void> _fetchFolders({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _isLoading = true;
        _error = null;
        _page = 1;
        _hasMore = true;
        _folders.clear();
      });
      // Refresh visible IDs on refresh
      _visibleFolderIds = await AuthService().getVisibleFolderIds();
    } else {
      setState(() {
        _isLoadingMore = true;
      });
    }

    try {
      final folders = await _biliApiService.getFavoriteFolders(pn: _page);
      
      List<Folder> filteredFolders = folders;
      if (_visibleFolderIds.isNotEmpty) {
        filteredFolders = folders.where((f) => _visibleFolderIds.contains(f.id)).toList();
      }

      if (mounted) {
        setState(() {
          if (refresh) {
            _folders = filteredFolders;
          } else {
            _folders.addAll(filteredFolders);
          }
          
          if (folders.length < 20) {
            _hasMore = false;
          } else {
            _page++;
          }
        });

        if (refresh) {
          _syncAllVideos(List.from(_folders));
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

  /// 后台同步所有(可见)收藏夹的视频数据到本地数据库
  Future<void> _syncAllVideos(List<Folder> folders) async {
    for (var folder in folders) {
      if (!mounted) return;
      try {
        final videos = await _biliApiService.getFolderVideos(folder.id, pn: 1, ps: 20);
        if (videos.isNotEmpty) {
           await _databaseService.insertVideos(videos, folder.id);
        }
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (e) {
        debugPrint('Sync failed for folder ${folder.id}: $e');
      }
    }
  }
    
  /// 处理锁定按钮点击事件 (锁定/设置密码/提示解锁)
  Future<void> _handleLockPress() async {
    if (_isLocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前为锁定状态，请长按解锁')),
      );
    } else {
      final hasPassword = await AuthService().isFolderLockSet();
      if (!hasPassword) {
        _showSetPasswordDialog();
      } else {
        await AuthService().setFolderSelectionLocked(true);
        if (mounted) {
          setState(() {
            _isLocked = true;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已锁定收藏夹修改')),
          );
        }
      }
    }
  }

  /// 处理锁定按钮长按事件 (弹出解锁对话框)
  Future<void> _handleUnlockLongPress() async {
    if (_isLocked) {
      _showUnlockDialog();
    }
  }

  /// 显示设置锁定密码的对话框
  void _showSetPasswordDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('设置锁定密码'),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: const InputDecoration(hintText: '输入密码'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                await AuthService().setFolderLockPassword(controller.text);
                await AuthService().setFolderSelectionLocked(true);
                if (context.mounted) {
                   setState(() {
                    _isLocked = true;
                  });
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('密码已设置并锁定')),
                  );
                }
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 显示解锁对话框
  void _showUnlockDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('解锁收藏夹修改'),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: const InputDecoration(hintText: '输入密码'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
                            final isCorrect = await AuthService().checkFolderLockPassword(controller.text);
                            if (!context.mounted) return;
                            
                            if (isCorrect) {
                               await AuthService().setFolderSelectionLocked(false);
                               if (context.mounted) {
                                 setState(() {
                                  _isLocked = false;
                                 });
                                 Navigator.pop(context);
                                 ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('已解锁')),
                                 );
                               }
                            } else {
                               ScaffoldMessenger.of(context).showSnackBar(
                                 const SnackBar(content: Text('密码错误')),
                               );
                            }            },
            child: const Text('解锁'),
          ),
        ],
      ),
    );
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
          if (!_isSearching) ...[
             IconButton(
              icon: const Icon(Icons.filter_list),
              tooltip: '筛选收藏夹',
              onPressed: () {
                if (_isLocked) {
                   ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('修改功能已锁定，请先解锁')), 
                   );
                } else {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const SelectFoldersScreen()),
                  ).then((_) {
                    _initData();
                  });
                }
              },
            ),
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
            IconButton(
              icon: const Icon(Icons.history),
              tooltip: '本地观看历史', 
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const HistoryScreen()),
                );
              },
            ),
          ],
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
                              child: Text('没有找到收藏夹，请登录或刷新\n或点击右上角筛选按钮选择显示的收藏夹'),
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
      floatingActionButton: GestureDetector(
        onLongPress: _handleUnlockLongPress,
        child: FloatingActionButton(
          onPressed: _handleLockPress,
          backgroundColor: _isLocked ? Colors.red : Theme.of(context).colorScheme.primaryContainer,
          foregroundColor: _isLocked ? Colors.white : Theme.of(context).colorScheme.onPrimaryContainer,
          child: Icon(_isLocked ? Icons.lock : Icons.lock_open_outlined),
        ),
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
                  playlist: [video],
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