import 'package:flutter/material.dart';
import '../models/bili_models.dart';
import '../widgets/folder_card.dart';
import 'folder_content_screen.dart';
import '../services/auth_service.dart';
import '../services/bili_api_service.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final BiliApiService _biliApiService = BiliApiService();
  final ScrollController _scrollController = ScrollController();
  List<Folder> _folders = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _error;
  int _page = 1;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _fetchFolders(refresh: true);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的收藏'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('搜索功能待开发')),
              );
            },
          ),
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
                          onPressed: () => _fetchFolders(refresh: true),
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                )
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
                            // +1 for the loading indicator at the bottom
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
                              final folder = _folders[index];
                              return FolderCard(
                                folder: folder,
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => FolderContentScreen(folder: folder),
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
}