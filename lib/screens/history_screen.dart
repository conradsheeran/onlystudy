import 'package:flutter/material.dart';
import 'package:onlystudy/l10n/app_localizations.dart';
import '../models/bili_models.dart';
import '../services/history_service.dart';
import '../widgets/video_tile.dart';
import 'video_player_screen.dart';
// import 'up_space_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Video> _videos = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  /// 加载本地观看历史记录
  Future<void> _loadHistory() async {
    final videos = await HistoryService().getWatchedVideos();
    if (mounted) {
      setState(() {
        _videos = videos;
        _isLoading = false;
      });
    }
  }

  /// 清空本地观看历史记录
  Future<void> _clearHistory() async {
    await HistoryService().clearHistory();
    _loadHistory();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.watchHistory),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            tooltip: AppLocalizations.of(context)!.clearHistory,
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text(AppLocalizations.of(context)!.clearHistory),
                  content:
                      Text(AppLocalizations.of(context)!.confirmClearHistory),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(AppLocalizations.of(context)!.cancel),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _clearHistory();
                      },
                      child: Text(AppLocalizations.of(context)!.clear),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _videos.isEmpty
              ? Center(child: Text(AppLocalizations.of(context)!.noHistory))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _videos.length,
                  itemBuilder: (context, index) {
                    final video = _videos[index];
                    return VideoTile(
                      video: video,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => VideoPlayerScreen(
                              playlist: _videos,
                              initialIndex: index,
                            ),
                          ),
                        ).then((_) => _loadHistory());
                      },
                    );
                  },
                ),
    );
  }
}
