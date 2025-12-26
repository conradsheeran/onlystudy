import 'dart:async';
import 'package:flutter/material.dart';
import 'package:onlystudy/l10n/app_localizations.dart';
import '../models/bili_models.dart';
import '../services/bili_api_service.dart';
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
  List<Video> _videos = [];
  bool _loadingInfo = true;
  bool _loadingList = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 1;
  String _order = 'pubdate';
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadInitial();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 首次加载，获取 UP 信息、合集与首屏投稿
  Future<void> _loadInitial() async {
    setState(() {
      _loadingInfo = true;
      _loadingList = true;
      _error = null;
    });
    await Future.wait([
      _loadInfo(),
      _loadVideos(reset: true),
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
        _error = AppLocalizations.of(context)!.loadUpFailed(e.toString());
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingInfo = false;
        });
      }
    }
  }

  /// 统一加载投稿列表
  Future<void> _loadList({bool reset = false}) async {
    await _loadVideos(reset: reset);
  }

  /// 加载投稿列表，支持排序
  Future<void> _loadVideos({bool reset = false}) async {
    if (reset) {
      setState(() {
        _loadingList = true;
        _loadingMore = false;
        _hasMore = true;
        _page = 1;
        _videos.clear();
      });
    } else {
      if (_loadingMore || !_hasMore) return;
      setState(() {
        _loadingMore = true;
      });
    }

    try {
      final page = await _api.getUpVideos(
        mid: widget.mid,
        pn: _page,
        order: _order,
      );
      if (!mounted) return;
      setState(() {
        if (reset) {
          _videos = page.videos;
        } else {
          _videos.addAll(page.videos);
        }
        if (page.hasMore) {
          _page++;
        } else {
          _hasMore = false;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppLocalizations.of(context)!.loadUpVideosFailed(e.toString());
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppLocalizations.of(context)!
                .loadUpVideosFailed(e.toString()))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loadingList = false;
          _loadingMore = false;
        });
      }
    }
  }

  /// 滚动监听以触发加载更多
  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_loadingMore &&
        _hasMore) {
      _loadList();
    }
  }

  /// 切换排序后刷新列表
  void _onOrderChanged(String value) {
    if (value == _order) return;
    setState(() {
      _order = value;
    });
    _loadVideos(reset: true);
  }

  /// 数字格式化，千位以上使用万/亿
  String _formatCount(int count) {
    if (count >= 100000000) {
      return '${(count / 100000000).toStringAsFixed(1)}亿';
    } else if (count >= 10000) {
      return '${(count / 10000).toStringAsFixed(1)}万';
    }
    return count.toString();
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
        message: _error ?? AppLocalizations.of(context)!.loadUpFailed(''),
        onRetry: _loadInitial,
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
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
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _buildStat(AppLocalizations.of(context)!.followers, info.fans),
                _buildStat(
                    AppLocalizations.of(context)!.following, info.following),
                _buildStat(AppLocalizations.of(context)!.likes, info.likes),
                _buildStat(
                    AppLocalizations.of(context)!.plays, info.archiveView),
                _buildStat(
                    AppLocalizations.of(context)!.videosCount, info.videoCount),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 构建统计项
  Widget _buildStat(String label, int value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _formatCount(value),
          style: Theme.of(context)
              .textTheme
              .bodyLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  /// 构建排序与筛选控件
  Widget _buildFilters() {
    final locale = AppLocalizations.of(context)!;
    final orderOptions = [
      {'value': 'pubdate', 'label': locale.sortLatest},
      {'value': 'click', 'label': locale.sortPlay},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('${locale.sortLabel}: '),
            const SizedBox(width: 8),
            DropdownButton<String>(
              value: _order,
              items: orderOptions
                  .map(
                    (item) => DropdownMenuItem<String>(
                      value: item['value']!,
                      child: Text(item['label']!),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  _onOrderChanged(value);
                }
              },
            ),
          ],
        ),
      ],
    );
  }

  /// 构建列表主体
  Widget _buildBody() {
    if (_loadingList && _videos.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _videos.isEmpty) {
      return ErrorView(
        message: _error!,
        onRetry: () => _loadList(reset: true),
      );
    }

    if (_videos.isEmpty) {
      final emptyText = AppLocalizations.of(context)!.emptyUpVideos;
      return RefreshIndicator(
        onRefresh: () => _loadList(reset: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            _buildHeader(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: _buildFilters(),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(child: Text(emptyText)),
            ),
          ],
        ),
      );
    }

    final itemCount = _videos.length + 2 + (_loadingMore ? 1 : 0);
    return RefreshIndicator(
      onRefresh: () => _loadList(reset: true),
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
          if (_loadingMore && index == itemCount - 1) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final videoIndex = index - 2;
          final video = _videos[videoIndex];
          return VideoTile(
            video: video,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => VideoPlayerScreen(
                    playlist: _videos,
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
