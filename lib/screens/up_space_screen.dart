import 'package:flutter/material.dart';
import 'package:onlystudy/l10n/app_localizations.dart';

import '../models/bili_models.dart';
import '../services/bili_api_service.dart';
import '../services/bili_failure_message.dart';
import '../services/paged_loader.dart';
import '../widgets/common_image.dart';
import '../widgets/error_view.dart';
import '../widgets/video_tile.dart';
import 'video_player_screen.dart';

/// UP 主主页页面，展示基础信息与投稿/合集列表
class UpSpaceScreen extends StatefulWidget {
  final int mid;
  final String? initialName;

  const UpSpaceScreen({super.key, required this.mid, this.initialName});

  @override
  State<UpSpaceScreen> createState() => _UpSpaceScreenState();
}

class _UpSpaceScreenState extends State<UpSpaceScreen> {
  final BiliApiService _api = BiliApiService();
  final ScrollController _scrollController = ScrollController();

  BiliUserInfo? _info;
  bool _loadingInfo = true;
  String _order = 'pubdate';
  String? _infoError;

  late final PagedLoader<Video> _loader;

  @override
  void initState() {
    super.initState();
    _loader = PagedLoader<Video>(
      fetchPage: (page) async {
        final result = await _api.getUpVideos(
          mid: widget.mid,
          pn: page,
          order: _order,
        );
        return PagedResult(items: result.videos, hasMore: result.hasMore);
      },
    );
    _loader.addListener(_onLoaderChanged);
    _scrollController.addListener(_onScroll);
    _loadInitial();
  }

  void _onLoaderChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _loader.removeListener(_onLoaderChanged);
    _loader.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 首次加载，获取 UP 信息与首屏投稿
  Future<void> _loadInitial() async {
    setState(() {
      _loadingInfo = true;
      _infoError = null;
    });
    await Future.wait([
      _loadInfo(),
      _loader.refresh(),
    ]);
  }

  /// 加载 UP 主基础信息
  Future<void> _loadInfo() async {
    try {
      final info = await _api.getUpInfo(widget.mid);
      if (!mounted) return;
      setState(() {
        _info = info;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _infoError = AppLocalizations.of(context)!.loadUpFailed(
            e.toUserMessage(context));
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingInfo = false;
        });
      }
    }
  }

  /// 滚动监听以触发加载更多
  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loader.loadNext();
    }
  }

  /// 切换排序后刷新列表
  void _onOrderChanged(String value) {
    if (value == _order) return;
    setState(() {
      _order = value;
    });
    _loader.refresh();
  }

  /// 构建用户信息卡片
  Widget _buildHeader() {
    if (_loadingInfo && _info == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16.0),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final info = _info;
    if (info == null) {
      return ErrorView(
        message: _infoError ?? AppLocalizations.of(context)!.loadUpFailed(''),
        onRetry: _loadInitial,
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CommonImage(info.face, width: 64, height: 64, radius: 12),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    info.name,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    info.sign.isEmpty
                        ? AppLocalizations.of(context)!.upIntroDefault
                        : info.sign,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建排序与筛选控件
  Widget _buildFilters() {
    final locale = AppLocalizations.of(context)!;
    final isLatest = _order == 'pubdate';
    final label = isLatest ? locale.sortLatest : locale.sortPlay;
    final icon = isLatest ? Icons.schedule : Icons.local_fire_department;

    return Row(
      children: [
        Text(locale.sortLabel),
        const Spacer(),
        TextButton.icon(
          icon: Icon(icon),
          label: Text(label),
          onPressed: () => _onOrderChanged(isLatest ? 'click' : 'pubdate'),
        ),
      ],
    );
  }

  /// 构建列表主体
  Widget _buildBody() {
    final l10n = AppLocalizations.of(context)!;
    final state = _loader.value;

    if (state is PagedLoading<Video> ||
        (state is PagedLoaded<Video> && state.items.isEmpty)) {
      // 首屏加载中或加载完成但为空
      return RefreshIndicator(
        onRefresh: _loader.refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            _buildHeader(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: _buildFilters(),
            ),
            if (state is PagedLoaded<Video>)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(child: Text(l10n.emptyUpVideos)),
              ),
          ],
        ),
      );
    }

    if (state is PagedError<Video>) {
      return ErrorView(
        message: _loader.hasLoaded
            ? (state.error).toUserMessage(context)
            : l10n.loadUpVideosFailed(state.error.toUserMessage(context)),
        onRetry: () => _loader.refresh(),
      );
    }

    if (state is PagedLoaded<Video>) {
      final videos = state.items;
      final hasMore = state.hasMore;
      final loadingMore = state.loadingMore;
      final showTail = hasMore || loadingMore;
      final itemCount = videos.length + 2 + (showTail ? 1 : 0);
      return RefreshIndicator(
        onRefresh: _loader.refresh,
        child: ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(12),
          itemCount: itemCount,
          itemBuilder: (context, index) {
            if (index == 0) return _buildHeader();
            if (index == 1) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildFilters(),
              );
            }
            if (showTail && index == itemCount - 1) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final videoIndex = index - 2;
            final video = videos[videoIndex];
            return VideoTile(
              video: video,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => VideoPlayerScreen(
                      playlist: videos,
                      initialIndex: videoIndex,
                    ),
                  ),
                );
              },
            );
          },
        ),
      );
    }

    return const SizedBox.shrink();
  }

  /// 构建整体界面
  @override
  Widget build(BuildContext context) {
    final locale = AppLocalizations.of(context)!;
    final title = _info != null
        ? locale.upHomeTitle(_info!.name)
        : (widget.initialName != null
            ? locale.upHomeTitle(widget.initialName!)
            : locale.upHomeFallback);

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: _buildBody(),
      ),
    );
  }
}
