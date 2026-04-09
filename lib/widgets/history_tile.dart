import 'package:flutter/material.dart';

import '../models/history_entry.dart';
import 'common_image.dart';

class HistoryTile extends StatelessWidget {
  final HistoryEntry entry;
  final VoidCallback onTap;

  const HistoryTile({
    super.key,
    required this.entry,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final progress = entry.duration > 0
        ? (entry.progressSeconds / entry.duration).clamp(0.0, 1.0).toDouble()
        : 0.0;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  CommonImage(
                    entry.cover,
                    width: 128,
                    height: 72,
                    radius: 6,
                  ),
                  Positioned(
                    bottom: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: Color.fromARGB((255 * 0.65).round(), 0, 0, 0),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _formatDuration(entry.duration),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      entry.partTitle.isNotEmpty
                          ? 'P${entry.page} ${entry.partTitle}'
                          : 'P${entry.page}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.person_outline,
                            size: 13, color: Colors.grey),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            entry.upperName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _progressLabel(entry),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[500],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatViewedAt(entry.viewedAt),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        minHeight: 4,
                        value: progress,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _progressLabel(HistoryEntry entry) {
    if (entry.isFinished && entry.duration > 0) {
      return '${_formatDuration(entry.duration)} / ${_formatDuration(entry.duration)}';
    }
    return '${_formatDuration(entry.progressSeconds)} / ${_formatDuration(entry.duration)}';
  }

  static String _formatDuration(int seconds) {
    final safeSeconds = seconds < 0 ? 0 : seconds;
    final minutes = safeSeconds ~/ 60;
    final remainSeconds = safeSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainSeconds.toString().padLeft(2, '0')}';
  }

  static String _formatViewedAt(int viewedAt) {
    if (viewedAt <= 0) {
      return '';
    }

    final date = DateTime.fromMillisecondsSinceEpoch(viewedAt);
    final now = DateTime.now();
    final isSameDay = now.year == date.year &&
        now.month == date.month &&
        now.day == date.day;

    if (isSameDay) {
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }
    if (now.year == date.year) {
      return '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    }
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
