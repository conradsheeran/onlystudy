import 'package:flutter/material.dart';
import 'package:onlystudy/l10n/app_localizations.dart';

import '../models/bili_models.dart';
import '../services/favorites_catalog.dart';
import '../services/bili_failure_message.dart';
import '../services/database_service.dart';
import '../services/paged_loader.dart';
import '../widgets/custom_search_bar.dart';
import '../widgets/error_view.dart';
import '../widgets/video_tile.dart';
import '../services/app_navigator.dart';

class FolderContentScreen extends StatefulWidget {
  final Folder folder;

  const FolderContentScreen({super.key, required this.folder});

  @override
  State<FolderContentScreen> createState() => _FolderContentScreenState();
}

class _FolderContentScreenState extends State<FolderContentScreen> {
  final FavoritesCatalog _catalog = FavoritesCatalog();
  final DatabaseService _databaseService = DatabaseService();
  final ScrollController _scrollController = ScrollController();

  late final PagedLoader<Video> _loader;
  bool _isSearching = false;
  String _searchKeyword = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loader = PagedLoader<Video>(
      fetchPage: (page) async {
        final videos = await _catalog.getFolderVideos(
          widget.folder.id,
          pn: page,
          keyword: _searchKeyword,
        );
        if (videos.isNotEmpty) {
          _databaseService.insertVideos(videos, folderId: widget.folder.id);
        }
        return PagedResult(items: videos, hasMore: videos.length >= 20);
      },
    );
    _loader.addListener(_onLoaderChanged);
    _scrollController.addListener(_onScroll);
    _loader.refresh();
  }

  void _onLoaderChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _loader.removeListener(_onLoaderChanged);
    _loader.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// 滚动监听，触底加载更多
  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loader.loadNext();
    }
  }

  Future<void> _search(String keyword) {
    _searchKeyword = keyword;
    return _loader.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? CustomSearchBar(
                controller: _searchController,
                hintText: l10n.searchFolder,
                onSubmitted: (value) {
                  setState(() {
                    _searchKeyword = value;
                  });
                  _search(value);
                },
                onClear: () {
                  setState(() {
                    _searchController.clear();
                    _searchKeyword = '';
                  });
                  _search('');
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
                } else {
                  _isSearching = true;
                }
              });
              _search('');
            },
          ),
        ],
      ),
      body: _buildBody(l10n),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    return switch (_loader.value) {
      PagedLoading<Video>() => const Center(child: CircularProgressIndicator()),
      PagedError<Video>(:final error) => ErrorView(
        message: l10n.loadFailed(error.toUserMessage(context)),
        onRetry: _loader.refresh,
      ),
      PagedLoaded<Video>(:final items, :final hasMore) => RefreshIndicator(
        onRefresh: _loader.refresh,
        child: items.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: 300,
                    child: Center(child: Text(l10n.noVideosInFolder)),
                  ),
                ],
              )
            : ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(12),
                itemCount: items.length + (hasMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == items.length) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(8.0),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }
                  final video = items[index];
                  return VideoTile(
                    video: video,
                    onTap: () {
                      AppNavigator.toVideoPlayer(
                        context,
                        playlist: items,
                        initialIndex: index,
                      );
                    },
                  );
                },
              ),
      ),
      PagedInitial<Video>() => const SizedBox.shrink(),
    };
  }
}
