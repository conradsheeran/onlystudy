import 'package:flutter/material.dart';
import 'package:onlystudy/l10n/app_localizations.dart';
import '../models/history_entry.dart';
import '../services/history_service.dart';
import '../widgets/history_tile.dart';
import 'video_player_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<HistoryEntry> _entries = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final entries = await HistoryService().getHistoryEntries();
    if (mounted) {
      setState(() {
        _entries = entries;
        _isLoading = false;
      });
    }
  }

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
          : _entries.isEmpty
              ? Center(child: Text(AppLocalizations.of(context)!.noHistory))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _entries.length,
                  itemBuilder: (context, index) {
                    final entry = _entries[index];
                    return HistoryTile(
                      entry: entry,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => VideoPlayerScreen(
                              playlist: [entry.toVideo()],
                              initialIndex: 0,
                              initialHistoryEntry: entry,
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
