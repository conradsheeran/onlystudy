import 'package:flutter/material.dart';
import 'package:onlystudy/l10n/app_localizations.dart';
import '../models/bili_models.dart';
import '../services/auth_service.dart';
import '../services/bili_api_service.dart';
import '../services/database_service.dart';
import 'main_screen.dart';

/// 选择可见内容页面，包含收藏夹、合集、UP 三个 Tab
class SelectFoldersScreen extends StatefulWidget {
  final bool isFirstLogin;

  const SelectFoldersScreen({super.key, this.isFirstLogin = false});

  @override
  State<SelectFoldersScreen> createState() => _SelectFoldersScreenState();
}

class _SelectFoldersScreenState extends State<SelectFoldersScreen>
    with SingleTickerProviderStateMixin {
  final BiliApiService _apiService = BiliApiService();
  final ScrollController _upScrollController = ScrollController();

  late final TabController _tabController;

  List<Folder> _allFolders = [];
  List<Season> _allSeasons = [];
  final List<FollowUser> _allUps = [];

  Set<int> _selectedFolderIds = {};
  Set<int> _selectedSeasonIds = {};
  Set<int> _selectedUpIds = {};

  bool _isLoading = true;
  bool _loadingUps = false;
  bool _loadingMoreUps = false;
  bool _upHasMore = true;
  int _upPage = 1;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _upScrollController.addListener(_onUpScroll);
    _loadData();
  }

  @override
  void dispose() {
    _upScrollController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  /// 初始化加载收藏夹、合集与关注的UP主
  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final savedFolderIds = await AuthService().getVisibleFolderIds();
      final savedSeasonIds = await AuthService().getVisibleSeasonIds();
      final savedUpIds = await AuthService().getVisibleUpIds();

      final folders = await _loadFolders();
      final seasons = await _loadSeasons();
      await _loadUps(reset: true);

      setState(() {
        _allFolders = folders;
        _allSeasons = seasons;

        if (savedFolderIds.isEmpty &&
            savedSeasonIds.isEmpty &&
            savedUpIds.isEmpty &&
            widget.isFirstLogin) {
          _selectedFolderIds = folders.map((e) => e.id).toSet();
          _selectedSeasonIds = seasons.map((e) => e.id).toSet();
          _selectedUpIds = _allUps.map((e) => e.mid).toSet();
        } else {
          _selectedFolderIds = savedFolderIds.toSet();
          _selectedSeasonIds = savedSeasonIds.toSet();
          _selectedUpIds = savedUpIds.toSet();
        }
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = AppLocalizations.of(context)!.loadFailed(e.toString());
          _isLoading = false;
        });
      }
    }
  }

  /// 加载收藏夹列表
  Future<List<Folder>> _loadFolders() async {
    List<Folder> allFolders = [];
    int page = 1;
    while (true) {
      final folders = await _apiService.getFavoriteFolders(pn: page, ps: 20);
      allFolders.addAll(folders);
      if (folders.length < 20) break;
      page++;
    }
    return allFolders;
  }

  /// 加载合集列表
  Future<List<Season>> _loadSeasons() async {
    List<Season> allSeasons = [];
    try {
      int seasonPage = 1;
      while (true) {
        final seasons =
            await _apiService.getSubscribedSeasons(pn: seasonPage, ps: 20);
        allSeasons.addAll(seasons);
        if (seasons.length < 20) break;
        seasonPage++;
      }
    } catch (e) {
      debugPrint('Failed to load seasons: $e');
    }
    return allSeasons;
  }

  /// 加载关注的UP主列表，支持懒加载
  Future<void> _loadUps({bool reset = false}) async {
    if (reset) {
      setState(() {
        _loadingUps = true;
        _loadingMoreUps = false;
        _upHasMore = true;
        _upPage = 1;
        _allUps.clear();
      });
    } else {
      if (_loadingMoreUps || !_upHasMore) return;
      setState(() {
        _loadingMoreUps = true;
      });
    }

    try {
      final ups = await _apiService.getFollowings(pn: _upPage, ps: 20);
      if (!mounted) return;
      setState(() {
        _allUps.addAll(ups);
        if (ups.length < 20) {
          _upHasMore = false;
        } else {
          _upPage++;
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                AppLocalizations.of(context)!.loadUpsFailed(e.toString()))),
      );
      setState(() {
        _upHasMore = false;
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingUps = false;
          _loadingMoreUps = false;
        });
      }
    }
  }

  /// 滚动到末尾自动加载更多UP主
  void _onUpScroll() {
    if (_upScrollController.position.pixels >=
            _upScrollController.position.maxScrollExtent - 200 &&
        !_loadingMoreUps &&
        _upHasMore) {
      _loadUps();
    }
  }

  /// 全选当前三类内容
  void _selectAll() {
    setState(() {
      _selectedFolderIds = _allFolders.map((e) => e.id).toSet();
      _selectedSeasonIds = _allSeasons.map((e) => e.id).toSet();
      _selectedUpIds = _allUps.map((e) => e.mid).toSet();
    });
  }

  /// 清空全部选择
  void _clearAll() {
    setState(() {
      _selectedFolderIds.clear();
      _selectedSeasonIds.clear();
      _selectedUpIds.clear();
    });
  }

  /// 确认选择，保存并清空缓存
  Future<void> _onConfirm() async {
    if (_selectedFolderIds.isEmpty &&
        _selectedSeasonIds.isEmpty &&
        _selectedUpIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.selectAtLeastOne)),
      );
      return;
    }

    try {
      await AuthService().saveVisibleFolderIds(_selectedFolderIds.toList());
      await AuthService().saveVisibleSeasonIds(_selectedSeasonIds.toList());
      await AuthService().saveVisibleUpIds(_selectedUpIds.toList());

      await DatabaseService().clearAllCache();

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const MainScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  /// 构建收藏夹列表
  Widget _buildFoldersTab(AppLocalizations locale) {
    if (_allFolders.isEmpty) {
      return Center(child: Text(locale.noContentFound));
    }
    return ListView.builder(
      itemCount: _allFolders.length,
      itemBuilder: (context, index) {
        final folder = _allFolders[index];
        final isSelected = _selectedFolderIds.contains(folder.id);
        return CheckboxListTile(
          value: isSelected,
          title: Text(folder.title),
          subtitle: Text(locale.videoCount(folder.mediaCount)),
          secondary: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.network(
              folder.cover,
              width: 40,
              height: 40,
              fit: BoxFit.cover,
              errorBuilder: (ctx, err, stack) => Container(
                width: 40,
                height: 40,
                color: Colors.grey,
              ),
            ),
          ),
          onChanged: (val) {
            setState(() {
              if (val == true) {
                _selectedFolderIds.add(folder.id);
              } else {
                _selectedFolderIds.remove(folder.id);
              }
            });
          },
        );
      },
    );
  }

  /// 构建合集列表
  Widget _buildSeasonsTab(AppLocalizations locale) {
    if (_allSeasons.isEmpty) {
      return Center(child: Text(locale.noContentFound));
    }
    return ListView.builder(
      itemCount: _allSeasons.length,
      itemBuilder: (context, index) {
        final season = _allSeasons[index];
        final isSelected = _selectedSeasonIds.contains(season.id);
        return CheckboxListTile(
          value: isSelected,
          title: Text(season.title),
          subtitle: Text(
              '${locale.videoCount(season.mediaCount)} · ${season.upper.name}'),
          secondary: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.network(
              season.cover,
              width: 40,
              height: 40,
              fit: BoxFit.cover,
              errorBuilder: (ctx, err, stack) => Container(
                width: 40,
                height: 40,
                color: Colors.grey,
              ),
            ),
          ),
          onChanged: (val) {
            setState(() {
              if (val == true) {
                _selectedSeasonIds.add(season.id);
              } else {
                _selectedSeasonIds.remove(season.id);
              }
            });
          },
        );
      },
    );
  }

  /// 构建UP主列表（关注）
  Widget _buildUpsTab(AppLocalizations locale) {
    if (_loadingUps && _allUps.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_allUps.isEmpty) {
      return Center(child: Text(locale.noUps));
    }

    final itemCount = _allUps.length + (_loadingMoreUps ? 1 : 0);
    return ListView.builder(
      controller: _upScrollController,
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (_loadingMoreUps && index == itemCount - 1) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final up = _allUps[index];
        final isSelected = _selectedUpIds.contains(up.mid);
        return CheckboxListTile(
          value: isSelected,
          title: Text(up.name),
          subtitle: Text(
            up.sign.isEmpty ? locale.upIntroDefault : up.sign,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          secondary: CircleAvatar(
            backgroundImage: NetworkImage(up.face),
            onBackgroundImageError: (_, __) {},
          ),
          onChanged: (val) {
            setState(() {
              if (val == true) {
                _selectedUpIds.add(up.mid);
              } else {
                _selectedUpIds.remove(up.mid);
              }
            });
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final locale = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(locale.selectContent),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: locale.favorites),
            Tab(text: locale.subscribedSeasons),
            Tab(text: locale.upTab),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _isLoading ? null : _onConfirm,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_error!),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadData,
                        child: Text(locale.retry),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _selectAll,
                              icon: const Icon(Icons.select_all),
                              label: Text(locale.selectAll),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _clearAll,
                              icon: const Icon(Icons.clear_all),
                              label: Text(locale.clear),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildFoldersTab(locale),
                          _buildSeasonsTab(locale),
                          _buildUpsTab(locale),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _onConfirm,
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Text(
                              locale.confirmAndEnter,
                              style: const TextStyle(fontSize: 18),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
