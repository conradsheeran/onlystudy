import 'package:flutter/material.dart';
import '../models/bili_models.dart';
import '../services/auth_service.dart';
import '../services/bili_api_service.dart';
import '../services/database_service.dart';
import 'home_screen.dart';

class SelectFoldersScreen extends StatefulWidget {
  final bool isFirstLogin;

  const SelectFoldersScreen({super.key, this.isFirstLogin = false});

  @override
  State<SelectFoldersScreen> createState() => _SelectFoldersScreenState();
}

class _SelectFoldersScreenState extends State<SelectFoldersScreen> {
  final BiliApiService _apiService = BiliApiService();
  List<Folder> _allFolders = [];
  Set<int> _selectedIds = {};
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Fetch all folders
      // Note: This fetches page 1, strictly speaking we should fetch ALL pages if user has many folders.
      // For now, assuming user has < 20 folders or we implement paging.
      // Implementing paging here to be safe.
      List<Folder> allFolders = [];
      int page = 1;
      while (true) {
        final folders = await _apiService.getFavoriteFolders(pn: page, ps: 20);
        allFolders.addAll(folders);
        if (folders.length < 20) break;
        page++;
      }

      // Get saved selection
      final savedIds = await AuthService().getVisibleFolderIds();
      
      setState(() {
        _allFolders = allFolders;
        if (savedIds.isEmpty && widget.isFirstLogin) {
          // Default select all on first login
          _selectedIds = allFolders.map((e) => e.id).toSet();
        } else {
          // Merge saved with current available
          _selectedIds = savedIds.toSet();
        }
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '加载收藏夹失败: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _onConfirm() async {
    if (_selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请至少选择一个收藏夹')),
      );
      return;
    }

    try {
      // Save selection
      await AuthService().saveVisibleFolderIds(_selectedIds.toList());
      
      // Clear search cache so it can be rebuilt with only selected folders
      await DatabaseService().clearAllCache();

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const HomeScreen()),
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
        title: const Text('选择显示的收藏夹'),
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
                      child: ListView.builder(
                        itemCount: _allFolders.length,
                        itemBuilder: (context, index) {
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
