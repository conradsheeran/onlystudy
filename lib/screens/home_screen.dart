import 'dart:async';
import 'package:flutter/material.dart';
import 'package:onlystudy/l10n/app_localizations.dart';
import '../models/bili_models.dart';
import '../widgets/folder_card.dart';
import '../widgets/video_tile.dart';
import '../widgets/custom_search_bar.dart';
import '../widgets/skeletons.dart';
import '../widgets/error_view.dart';
import 'season_content_screen.dart';
import 'folder_content_screen.dart';
import 'download_screen.dart';
import '../services/auth_service.dart';
import '../services/bili_api_service.dart';
import '../services/database_service.dart';
import 'history_screen.dart';
import 'video_player_screen.dart';
import 'up_space_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final BiliApiService _biliApiService = BiliApiService();
  final DatabaseService _databaseService = DatabaseService();
  final ScrollController _scrollController = ScrollController();

  List<dynamic> _items = [];

  List<int> _visibleFolderIds = [];
  List<int> _visibleSeasonIds = [];
  List<int> _visibleUpIds = [];

  List<Video> _searchResults = [];
  bool _isLoading = true;
  String? _error;
  bool _isSearching = false;
  String _searchKeyword = '';
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  bool _isLocked = false;

  /// 执行搜索逻辑，支持按可见收藏夹/合集过滤
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
      final videos = await _databaseService.searchVideos(
        keyword,
        visibleFolderIds: _visibleFolderIds,
        visibleSeasonIds: _visibleSeasonIds,
      );
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
  }

  /// 初始化数据：获取可见ID和锁定状态
  Future<void> _initData() async {
    final locked = await AuthService().isFolderSelectionLocked();
    _visibleFolderIds = await AuthService().getVisibleFolderIds();
    _visibleSeasonIds = await AuthService().getVisibleSeasonIds();
    _visibleUpIds = await AuthService().getVisibleUpIds();

    setState(() {
      _isLocked = locked;
    });
    _fetchContent(refresh: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// 获取内容列表 (收藏夹 + 合集)
  Future<void> _fetchContent({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _isLoading = true;
        _error = null;
        _items.clear();
      });
      // Refresh visible IDs on refresh
      _visibleFolderIds = await AuthService().getVisibleFolderIds();
      _visibleSeasonIds = await AuthService().getVisibleSeasonIds();
      _visibleUpIds = await AuthService().getVisibleUpIds();
    }

    try {
      List<Folder> visibleFolders = [];
      if (_visibleFolderIds.isNotEmpty) {
        int page = 1;
        Set<int> foundIds = {};
        while (foundIds.length < _visibleFolderIds.length) {
          final folders =
              await _biliApiService.getFavoriteFolders(pn: page, ps: 20);
          if (folders.isEmpty) break;

          for (var f in folders) {
            if (_visibleFolderIds.contains(f.id)) {
              visibleFolders.add(f);
              foundIds.add(f.id);
            }
          }
          if (folders.length < 20) break;
          page++;
          if (page > 5) break;
        }
      }

      List<Season> visibleSeasons = [];
      if (_visibleSeasonIds.isNotEmpty) {
        int page = 1;
        Set<int> foundIds = {};
        while (foundIds.length < _visibleSeasonIds.length) {
          final seasons =
              await _biliApiService.getSubscribedSeasons(pn: page, ps: 20);
          if (seasons.isEmpty) break;

          for (var s in seasons) {
            if (_visibleSeasonIds.contains(s.id)) {
              visibleSeasons.add(s);
              foundIds.add(s.id);
            }
          }
          if (seasons.length < 20) break;
          page++;
          if (page > 5) break;
        }
      }

      List<FollowUser> visibleUps = [];
      if (_visibleUpIds.isNotEmpty) {
        for (final mid in _visibleUpIds) {
          try {
            final info = await _biliApiService.getUpInfo(mid);
            visibleUps.add(FollowUser(
              mid: info.mid,
              name: info.name,
              face: info.face,
              sign: info.sign,
            ));
          } catch (e) {
            debugPrint('Failed to load up $mid: $e');
          }
        }
      }

      if (mounted) {
        setState(() {
          _items = [...visibleFolders, ...visibleSeasons, ...visibleUps];
        });

        if (refresh) {
          _syncAllContent(visibleFolders, visibleSeasons);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = AppLocalizations.of(context)!.loadFailed(e.toString());
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// 后台同步所有可见内容的视频数据到本地数据库
  Future<void> _syncAllContent(
      List<Folder> folders, List<Season> seasons) async {
    for (var folder in folders) {
      if (!mounted) return;
      try {
        final videos =
            await _biliApiService.getFolderVideos(folder.id, pn: 1, ps: 20);
        if (videos.isNotEmpty) {
          await _databaseService.insertVideos(videos, folderId: folder.id);
        }
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (e) {
        debugPrint('Sync failed for folder ${folder.id}: $e');
      }
    }

    for (var season in seasons) {
      if (!mounted) return;
      try {
        final videos = await _biliApiService
            .getSeasonVideos(season.id, season.upper.mid, pn: 1, ps: 20);
        if (videos.isNotEmpty) {
          await _databaseService.insertVideos(videos, seasonId: season.id);
        }
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (e) {
        debugPrint('Sync failed for season ${season.id}: $e');
      }
    }
  }

  /// 处理锁定按钮点击事件 (锁定/设置密码/提示解锁)
  Future<void> _handleLockPress() async {
    if (_isLocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.lockedHint)),
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
            SnackBar(content: Text(AppLocalizations.of(context)!.locked)),
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
        title: Text(AppLocalizations.of(context)!.setPassword),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: InputDecoration(
              hintText: AppLocalizations.of(context)!.enterPassword),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.cancel),
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
                    SnackBar(
                        content:
                            Text(AppLocalizations.of(context)!.passwordSet)),
                  );
                }
              }
            },
            child: Text(AppLocalizations.of(context)!.confirm),
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
        title: Text(AppLocalizations.of(context)!.unlockFolderSelection),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: InputDecoration(
              hintText: AppLocalizations.of(context)!.enterPassword),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          FilledButton(
            onPressed: () async {
              final isCorrect =
                  await AuthService().checkFolderLockPassword(controller.text);
              if (!context.mounted) return;

              if (isCorrect) {
                await AuthService().setFolderSelectionLocked(false);
                if (context.mounted) {
                  setState(() {
                    _isLocked = false;
                  });
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(AppLocalizations.of(context)!.unlocked)),
                  );
                }
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(
                          AppLocalizations.of(context)!.passwordIncorrect)),
                );
              }
            },
            child: Text(AppLocalizations.of(context)!.unlock),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          transitionBuilder: (Widget child, Animation<double> animation) {
            return FadeTransition(opacity: animation, child: child);
          },
          child: _isSearching
              ? CustomSearchBar(
                  key: const ValueKey('SearchBar'),
                  controller: _searchController,
                  hintText: AppLocalizations.of(context)!.searchHint,
                  onChanged: _onSearchChanged,
                  onClear: () {
                    setState(() {
                      _searchController.clear();
                      _searchKeyword = '';
                      _searchResults = [];
                    });
                  },
                )
              : SizedBox(
                  key: const ValueKey('Title'),
                  width: double.infinity,
                  child: Text(AppLocalizations.of(context)!.appTitle),
                ),
        ),
        actions: [
          if (!_isSearching) ...[
            IconButton(
              icon: const Icon(Icons.cloud_download_outlined),
              tooltip: AppLocalizations.of(context)!.downloadCache,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const DownloadScreen()),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.history),
              tooltip: AppLocalizations.of(context)!.watchHistory,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const HistoryScreen()),
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
                  onRetry: () => _fetchContent(refresh: true),
                )
              : AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  child: _isSearching
                      ? _buildSearchResults()
                      : RefreshIndicator(
                          key: const ValueKey('ContentList'),
                          onRefresh: () => _fetchContent(refresh: true),
                          child: _items.isEmpty
                              ? Center(
                                  child: Text(AppLocalizations.of(context)!
                                      .noContentFound),
                                )
                              : Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: GridView.builder(
                                    controller: _scrollController,
                                    gridDelegate:
                                        const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      childAspectRatio: 0.85,
                                      crossAxisSpacing: 12,
                                      mainAxisSpacing: 12,
                                    ),
                                    itemCount: _items.length,
                                    itemBuilder: (context, index) {
                                      final item = _items[index];
                                      if (item is Folder) {
                                        return FolderCard(
                                          folder: item,
                                          onTap: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (context) =>
                                                    FolderContentScreen(
                                                        folder: item),
                                              ),
                                            );
                                          },
                                        );
                                      } else if (item is Season) {
                                        // Reuse FolderCard for Season, but might want to differentiate visually
                                        // Constructing a "Folder" like object for UI reuse or create SeasonCard
                                        // For simplicity, reusing FolderCard with mapping.
                                        return FolderCard(
                                          folder: Folder(
                                            id: item.id,
                                            title: item.title,
                                            cover: item.cover,
                                            mediaCount: item.mediaCount,
                                            upper: item.upper,
                                            favState: 1,
                                          ),
                                          onTap: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (context) =>
                                                    SeasonContentScreen(
                                                        season: item),
                                              ),
                                            );
                                          },
                                        );
                                      } else if (item is FollowUser) {
                                        final locale =
                                            AppLocalizations.of(context)!;
                                        return FolderCard(
                                          folder: Folder(
                                            id: item.mid,
                                            title: item.name,
                                            cover: item.face,
                                            mediaCount: 0,
                                            upper: BiliUpper(
                                              mid: item.mid,
                                              name: item.name,
                                            ),
                                            favState: 1,
                                          ),
                                          subtitle: item.sign.isEmpty
                                              ? locale.upIntroDefault
                                              : item.sign,
                                          onTap: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (context) =>
                                                    UpSpaceScreen(
                                                        mid: item.mid),
                                              ),
                                            );
                                          },
                                        );
                                      }
                                      return const SizedBox();
                                    },
                                  ),
                                ),
                        ),
                ),
      floatingActionButton: GestureDetector(
        onLongPress: _handleUnlockLongPress,
        child: FloatingActionButton(
          onPressed: _handleLockPress,
          backgroundColor: _isLocked
              ? Colors.red
              : Theme.of(context).colorScheme.primaryContainer,
          foregroundColor: _isLocked
              ? Colors.white
              : Theme.of(context).colorScheme.onPrimaryContainer,
          child: Icon(_isLocked ? Icons.lock : Icons.lock_open_outlined),
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_searchKeyword.isEmpty) {
      return Container(
        key: const ValueKey('SearchResults'),
        child: Center(child: Text(AppLocalizations.of(context)!.searchHint)),
      );
    }

    if (_searchResults.isEmpty) {
      return Container(
        key: const ValueKey('SearchResults'),
        child: Center(child: Text(AppLocalizations.of(context)!.noResult)),
      );
    }

    return Container(
      key: const ValueKey('SearchResults'),
      child: ListView.builder(
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
      ),
    );
  }
}
