import 'package:flutter/material.dart';
import '../services/download_service.dart';
import '../models/download_task.dart';
import '../models/bili_models.dart';
import '../widgets/common_image.dart';
import 'video_player_screen.dart';

class DownloadScreen extends StatefulWidget {
  const DownloadScreen({super.key});

  @override
  State<DownloadScreen> createState() => _DownloadScreenState();
}

class _DownloadScreenState extends State<DownloadScreen> {
  final DownloadService _downloadService = DownloadService();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('离线缓存'),
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: '已完成'),
              Tab(text: '进行中'),
            ],
          ),
        ),
        body: StreamBuilder<List<DownloadTask>>(
          stream: _downloadService.tasksStream,
          initialData: _downloadService.currentTasks,
          builder: (context, snapshot) {
            final tasks = snapshot.data ?? [];
            final downloaded = tasks.where((t) => t.status == DownloadStatus.completed).toList();
            final downloading = tasks.where((t) => t.status != DownloadStatus.completed).toList();

            return TabBarView(
              children: [
                _buildDownloadedList(downloaded),
                _buildDownloadingList(downloading),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildDownloadedList(List<DownloadTask> tasks) {
    if (tasks.isEmpty) {
      return const Center(child: Text('暂无已完成的视频'));
    }
    return ListView.builder(
      itemCount: tasks.length,
      itemBuilder: (context, index) {
        final task = tasks[index];
        return ListTile(
          leading: SizedBox(
            width: 80,
            height: 45,
            child: CommonImage(task.cover, radius: 4),
          ),
          title: Text(task.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text('画质: ${task.quality}'),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () {
               showDialog(
                 context: context,
                 builder: (ctx) => AlertDialog(
                   title: const Text('确认删除'),
                   content: Text('确定要删除 "${task.title}" 吗？'),
                   actions: [
                     TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                     TextButton(
                       onPressed: () {
                         _downloadService.deleteTask(task.bvid, task.cid);
                         Navigator.pop(ctx);
                       },
                       child: const Text('删除'),
                     ),
                   ],
                 ),
               );
            },
          ),
          onTap: () {
             final video = Video(
               bvid: task.bvid,
               title: task.title,
               cover: task.cover,
               duration: 0, 
               upper: BiliUpper(mid: 0, name: ''), 
               view: 0,
               danmaku: 0,
               pubTimestamp: 0,
             );
             
             Navigator.push(
               context,
               MaterialPageRoute(
                 builder: (context) => VideoPlayerScreen(
                   playlist: [video],
                   initialIndex: 0,
                   localFilePath: task.filePath,
                 ),
               ),
             );
          },
        );
      },
    );
  }
  
  Widget _buildDownloadingList(List<DownloadTask> tasks) {
     if (tasks.isEmpty) {
      return const Center(child: Text('暂无进行中的任务'));
    }
    return ListView.builder(
      itemCount: tasks.length,
      itemBuilder: (context, index) {
        final task = tasks[index];
        return ListTile(
          leading: SizedBox(
             width: 80,
             height: 45,
             child: CommonImage(task.cover, radius: 4),
          ),
          title: Text(task.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              LinearProgressIndicator(value: task.progress),
              const SizedBox(height: 4),
              Text(_getStatusText(task.status)),
            ],
          ),
          trailing: task.status == DownloadStatus.failed 
             ? IconButton(
                 icon: const Icon(Icons.refresh), 
                 onPressed: (){
                    _downloadService.deleteTask(task.bvid, task.cid);
                 }
               ) 
             : IconButton(
                 icon: const Icon(Icons.close),
                 onPressed: () {
                    _downloadService.deleteTask(task.bvid, task.cid);
                 },
               ),
        );
      },
    );
  }

  String _getStatusText(DownloadStatus status) {
    switch (status) {
      case DownloadStatus.pending: return '等待中...';
      case DownloadStatus.running: return '下载中';
      case DownloadStatus.paused: return '已暂停';
      case DownloadStatus.failed: return '下载失败';
      default: return '';
    }
  }
}
