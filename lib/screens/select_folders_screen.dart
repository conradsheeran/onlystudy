import 'package:flutter/material.dart';
import '../models/bili_models.dart';
import '../services/auth_service.dart';
import '../services/bili_api_service.dart';
import '../services/database_service.dart';
import 'main_screen.dart';

class SelectFoldersScreen extends StatefulWidget {
  final bool isFirstLogin;

  const SelectFoldersScreen({super.key, this.isFirstLogin = false});

  @override
  State<SelectFoldersScreen> createState() => _SelectFoldersScreenState();
}

class _SelectFoldersScreenState extends State<SelectFoldersScreen> {
  final BiliApiService _apiService = BiliApiService();
  List<Folder> _allFolders = [];
  List<Season> _allSeasons = [];
  Set<int> _selectedIds = {};
  Set<int> _selectedSeasonIds = {};
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  /// 加载所有收藏夹及合集数据
  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      List<Folder> allFolders = [];
      int page = 1;
      while (true) {
        final folders = await _apiService.getFavoriteFolders(pn: page, ps: 20);
        allFolders.addAll(folders);
        if (folders.length < 20) break;
        page++;
      }
      
      List<Season> allSeasons = [];
      try {
        int seasonPage = 1;
        while(true) {
          final seasons = await _apiService.getSubscribedSeasons(pn: seasonPage, ps: 20);
          allSeasons.addAll(seasons);
          if (seasons.length < 20) break;
          seasonPage++;
        }
      } catch (e) {
        debugPrint('Failed to load seasons: $e');
      }

      final savedFolderIds = await AuthService().getVisibleFolderIds();
      final savedSeasonIds = await AuthService().getVisibleSeasonIds();
      
      setState(() {
        _allFolders = allFolders;
        _allSeasons = allSeasons;
        
        if (savedFolderIds.isEmpty && savedSeasonIds.isEmpty && widget.isFirstLogin) {
          _selectedIds = allFolders.map((e) => e.id).toSet();
          _selectedSeasonIds = allSeasons.map((e) => e.id).toSet();
        } else {
          _selectedIds = savedFolderIds.toSet();
          _selectedSeasonIds = savedSeasonIds.toSet();
        }
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '加载失败: $e';
          _isLoading = false;
        });
      }
    }
  }

  /// 确认选择，保存设置并重建缓存
  Future<void> _onConfirm() async {
    if (_selectedIds.isEmpty && _selectedSeasonIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请至少选择一个收藏夹或合集')),
      );
      return;
    }

    try {
      await AuthService().saveVisibleFolderIds(_selectedIds.toList());
      await AuthService().saveVisibleSeasonIds(_selectedSeasonIds.toList());
      
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
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('选择显示的内容'),
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
                        child: const Text('重试'),
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
                              onPressed: () {
                                setState(() {
                                  _selectedIds = _allFolders.map((e) => e.id).toSet();
                                  _selectedSeasonIds = _allSeasons.map((e) => e.id).toSet();
                                });
                              },
                              icon: const Icon(Icons.select_all),
                              label: const Text('全选'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                setState(() {
                                  _selectedIds.clear();
                                  _selectedSeasonIds.clear();
                                });
                              },
                              icon: const Icon(Icons.clear_all),
                              label: const Text('清空'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: CustomScrollView(
                        slivers: [
                          if (_allFolders.isNotEmpty) ...[
                            const SliverToBoxAdapter(
                                child: Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                                  child: Text('收藏夹', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                ),
                            ),
                            SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  final folder = _allFolders[index];
                                  final isSelected = _selectedIds.contains(folder.id);
                                  return CheckboxListTile(
                                    value: isSelected,
                                    title: Text(folder.title),
                                    subtitle: Text('${folder.mediaCount}个视频'),
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
                                          _selectedIds.add(folder.id);
                                        } else {
                                          _selectedIds.remove(folder.id);
                                        }
                                      });
                                    },
                                  );
                                },
                                childCount: _allFolders.length,
                              ),
                            ),
                          ],
                          
                          if (_allSeasons.isNotEmpty) ...[
                            const SliverToBoxAdapter(
                                child: Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                                  child: Text('订阅合集', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                ),
                            ),
                             SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  final season = _allSeasons[index];
                                  final isSelected = _selectedSeasonIds.contains(season.id);
                                  return CheckboxListTile(
                                    value: isSelected,
                                    title: Text(season.title),
                                    subtitle: Text('${season.mediaCount}个视频 · ${season.upper.name}'),
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
                                childCount: _allSeasons.length,
                              ),
                            ),
                          ]
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _onConfirm,
                          child: const Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Text(
                              '确认并进入',
                              style: TextStyle(fontSize: 18),
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
