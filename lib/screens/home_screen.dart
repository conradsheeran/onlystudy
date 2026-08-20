import 'dart:async';

import 'package:flutter/material.dart';
import 'package:onlystudy/l10n/app_localizations.dart';

import '../models/bili_models.dart';
import '../services/app_navigator.dart';
import '../services/auth_service.dart';
import '../services/bili_failure_message.dart';
import '../services/home_library_controller.dart';
import '../widgets/custom_search_bar.dart';
import '../widgets/error_view.dart';
import '../widgets/folder_card.dart';
import '../widgets/skeletons.dart';
import '../widgets/video_tile.dart';

/// 主页：仅负责渲染 [HomeLibraryController] 状态与导航（OPT-009）。
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final HomeLibraryController _controller;

  bool _isSearching = false;
  String _searchKeyword = '';
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  static const double _tabletBreakpoint = 700;
  static const double _desktopBreakpoint = 1100;
  static const double _wideDesktopBreakpoint = 1500;

  @override
  void initState() {
    super.initState();
    _controller = HomeLibraryController();
    _controller.addListener(_onControllerChanged);
    _init();
  }

  Future<void> _init() async {
    await _controller.init();
    await _controller.refresh();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// 处理搜索框输入变化，带防抖 (500ms)
  void _onSearchChanged(String value) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (value != _searchKeyword) {
        setState(() {
          _searchKeyword = value;
        });
        _controller.search(value);
      }
    });
  }

  /// 处理锁定按钮点击事件 (锁定/设置密码/提示解锁)
  Future<void> _handleLockPress() async {
    if (_controller.isLocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.lockedHint)),
      );
    } else {
      final hasPassword = await AuthService().isFolderLockSet();
      if (!hasPassword) {
        _showSetPasswordDialog();
      } else {
        await _controller.setLocked(true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context)!.locked)),
          );
        }
      }
    }
  }

  /// 处理锁定按钮长按事件 (弹出解锁对话框)
  void _handleUnlockLongPress() {
    if (_controller.isLocked) {
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
            hintText: AppLocalizations.of(context)!.enterPassword,
          ),
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
                await _controller.setLockPassword(controller.text);
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(AppLocalizations.of(context)!.passwordSet),
                    ),
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
            hintText: AppLocalizations.of(context)!.enterPassword,
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          FilledButton(
            onPressed: () async {
              final isCorrect = await _controller.checkLockPassword(
                controller.text,
              );
              if (!context.mounted) return;
              if (isCorrect) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(AppLocalizations.of(context)!.unlocked),
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      AppLocalizations.of(context)!.passwordIncorrect,
                    ),
                  ),
                );
              }
            },
            child: Text(AppLocalizations.of(context)!.unlock),
          ),
        ],
      ),
    );
  }

  _HomeLayoutConfig _getLayoutConfig(double width) {
    if (width >= _wideDesktopBreakpoint) {
      return const _HomeLayoutConfig(
        crossAxisCount: 5,
        childAspectRatio: 0.92,
        maxWidth: 1520,
        padding: 20,
      );
    }
    if (width >= _desktopBreakpoint) {
      return const _HomeLayoutConfig(
        crossAxisCount: 4,
        childAspectRatio: 0.9,
        maxWidth: 1360,
        padding: 18,
      );
    }
    if (width >= _tabletBreakpoint) {
      return const _HomeLayoutConfig(
        crossAxisCount: 3,
        childAspectRatio: 0.88,
        maxWidth: 1080,
        padding: 16,
      );
    }
    return const _HomeLayoutConfig(
      crossAxisCount: 2,
      childAspectRatio: 0.85,
      maxWidth: double.infinity,
      padding: 12,
    );
  }

  Widget _buildCenteredContent({
    required _HomeLayoutConfig layout,
    required Widget child,
  }) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: layout.maxWidth),
        child: child,
      ),
    );
  }

  SliverGridDelegate _buildGridDelegate(_HomeLayoutConfig layout) {
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: layout.crossAxisCount,
      childAspectRatio: layout.childAspectRatio,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
    );
  }

  Widget _buildContentGrid(_HomeLayoutConfig layout, List<LibraryItem> items) {
    if (items.isEmpty) {
      return Center(child: Text(AppLocalizations.of(context)!.noContentFound));
    }

    return _buildCenteredContent(
      layout: layout,
      child: Padding(
        padding: EdgeInsets.all(layout.padding),
        child: GridView.builder(
          itemCount: items.length,
          gridDelegate: _buildGridDelegate(layout),
          itemBuilder: (context, index) {
            final item = items[index];
            return switch (item) {
              FolderItem(:final folder) => FolderCard(
                folder: folder,
                onTap: () => AppNavigator.toFolderContent(context, folder),
              ),
              SeasonItem(:final season) => FolderCard(
                folder: Folder(
                  id: season.id,
                  title: season.title,
                  cover: season.cover,
                  mediaCount: season.mediaCount,
                  upper: season.upper,
                  favState: 1,
                ),
                onTap: () => AppNavigator.toSeasonContent(context, season),
              ),
              UpItem(:final user) => FolderCard(
                folder: Folder(
                  id: user.mid,
                  title: user.name,
                  cover: user.face,
                  mediaCount: user.videoCount,
                  upper: BiliUpper(mid: user.mid, name: user.name),
                  favState: 1,
                ),
                subtitle: AppLocalizations.of(
                  context,
                )!.videoCount(user.videoCount),
                onTap: () => AppNavigator.toUpSpace(context, user.mid),
              ),
            };
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final layout = _getLayoutConfig(MediaQuery.sizeOf(context).width);
    final state = _controller.value;

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
                  hintText: l10n.searchHint,
                  onChanged: _onSearchChanged,
                  onClear: () {
                    setState(() {
                      _searchController.clear();
                      _searchKeyword = '';
                    });
                    _controller.search('');
                  },
                )
              : SizedBox(
                  key: const ValueKey('Title'),
                  width: double.infinity,
                  child: Text(l10n.appTitle),
                ),
        ),
        actions: [
          if (!_isSearching) ...[
            IconButton(
              icon: const Icon(Icons.cloud_download_outlined),
              tooltip: l10n.downloadCache,
              onPressed: () => AppNavigator.toDownloads(context),
            ),
            IconButton(
              icon: const Icon(Icons.history),
              tooltip: l10n.watchHistory,
              onPressed: () => AppNavigator.toHistory(context),
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
                  _controller.search('');
                } else {
                  _isSearching = true;
                }
              });
            },
          ),
        ],
      ),
      body: _buildBody(layout, state, l10n),
      floatingActionButton: GestureDetector(
        onLongPress: _handleUnlockLongPress,
        child: FloatingActionButton(
          onPressed: _handleLockPress,
          backgroundColor: _controller.isLocked
              ? Colors.red
              : Theme.of(context).colorScheme.primaryContainer,
          foregroundColor: _controller.isLocked
              ? Colors.white
              : Theme.of(context).colorScheme.onPrimaryContainer,
          child: Icon(
            _controller.isLocked ? Icons.lock : Icons.lock_open_outlined,
          ),
        ),
      ),
    );
  }

  Widget _buildBody(
    _HomeLayoutConfig layout,
    HomeLibraryState state,
    AppLocalizations l10n,
  ) {
    if (state is HomeLibraryLoading) {
      return _buildCenteredContent(
        layout: layout,
        child: GridView.builder(
          padding: EdgeInsets.all(layout.padding),
          gridDelegate: _buildGridDelegate(layout),
          itemCount: layout.crossAxisCount * 2,
          itemBuilder: (context, index) => const FolderCardSkeleton(),
        ),
      );
    }

    if (state is HomeLibraryError) {
      return ErrorView(
        message: l10n.loadFailed(state.error.toUserMessage(context)),
        onRetry: () => _controller.refresh(),
      );
    }

    final items = (state as HomeLibraryLoaded).items;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 150),
      child: _isSearching
          ? _buildSearchResults(layout)
          : RefreshIndicator(
              key: const ValueKey('ContentList'),
              onRefresh: () => _controller.refreshWithSync(),
              child: _buildContentGrid(layout, items),
            ),
    );
  }

  Widget _buildSearchResults(_HomeLayoutConfig layout) {
    final l10n = AppLocalizations.of(context)!;
    if (_searchKeyword.isEmpty) {
      return SizedBox(
        key: const ValueKey('SearchResults'),
        child: Center(child: Text(l10n.searchHint)),
      );
    }

    final results = _controller.searchResults;
    if (results.isEmpty) {
      return SizedBox(
        key: const ValueKey('SearchResults'),
        child: Center(child: Text(l10n.noResult)),
      );
    }

    return SizedBox(
      key: const ValueKey('SearchResults'),
      child: _buildCenteredContent(
        layout: layout,
        child: ListView.builder(
          padding: EdgeInsets.all(layout.padding),
          itemCount: results.length,
          itemBuilder: (context, index) {
            final video = results[index];
            return VideoTile(
              video: video,
              onTap: () {
                AppNavigator.toVideoPlayer(
                  context,
                  playlist: [video],
                  initialIndex: 0,
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _HomeLayoutConfig {
  final int crossAxisCount;
  final double childAspectRatio;
  final double maxWidth;
  final double padding;

  const _HomeLayoutConfig({
    required this.crossAxisCount,
    required this.childAspectRatio,
    required this.maxWidth,
    required this.padding,
  });
}
