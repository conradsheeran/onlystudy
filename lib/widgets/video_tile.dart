import 'package:flutter/material.dart';
import '../models/bili_models.dart';
import 'common_image.dart';

class VideoTile extends StatelessWidget {
  final Video video;
  final VoidCallback onTap;

  const VideoTile({super.key, required this.video, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cover Image with Duration Badge
              Stack(
                children: [
                  CommonImage(
                    video.cover,
                    width: 128,
                    height: 72, // Standard 16:9 thumbnail size
                    radius: 6,
                  ),
                  Positioned(
                    bottom: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: Color.fromARGB((255 * 0.65).round(), 0, 0, 0),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        video.formattedDuration,
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
              // Text Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    Text(
                      video.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                          ),
                    ),
                    const SizedBox(height: 6),
                    // Uploader
                    Row(
                      children: [
                        const Icon(Icons.person_outline, size: 13, color: Colors.grey),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            video.upper.name,
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
                    const SizedBox(height: 6),
                    // Stats & Date
                    Row(
                      children: [
                        // View Count
                        const Icon(Icons.play_circle_outline, size: 13, color: Colors.grey),
                        const SizedBox(width: 3),
                        Text(
                          video.formattedViewCount,
                          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                        ),
                        const SizedBox(width: 12),
                        // Danmaku Count
                        const Icon(Icons.subtitles_outlined, size: 13, color: Colors.grey),
                        const SizedBox(width: 3),
                        Text(
                          video.formattedDanmakuCount,
                          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                        ),
                        const Spacer(),
                        // Pub Date
                        Text(
                          video.formattedPubDate,
                          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                        ),
                      ],
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
}
