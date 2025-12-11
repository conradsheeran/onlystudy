import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class CommonImage extends StatefulWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double radius;
  final int fadeInDurationMs;

  const CommonImage(
    this.imageUrl, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.radius = 0,
    this.fadeInDurationMs = 300, // Revert to 300ms default
  });

  @override
  State<CommonImage> createState() => _CommonImageState();
}

class _CommonImageState extends State<CommonImage> {
  Future<FileInfo?>? _fileInfoFuture;

  @override
  void initState() {
    super.initState();
    // Check if image is in cache (memory or disk)
    _fileInfoFuture = DefaultCacheManager().getFileFromCache(widget.imageUrl);
  }

  @override
  void didUpdateWidget(covariant CommonImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.imageUrl != oldWidget.imageUrl) {
      _fileInfoFuture = DefaultCacheManager().getFileFromCache(widget.imageUrl);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.imageUrl.isEmpty) {
      return Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(widget.radius),
        ),
        child: Icon(Icons.image_not_supported, color: Colors.grey[500]),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: FutureBuilder<FileInfo?>(
        future: _fileInfoFuture,
        builder: (context, snapshot) {
          final bool isCachedInMemory = snapshot.data != null;
          
          return CachedNetworkImage(
            imageUrl: widget.imageUrl,
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            placeholder: (context, url) => Container(
              color: Colors.grey[200],
            ),
            errorWidget: (context, url, error) => Container(
              color: Colors.grey[200],
              child: Icon(Icons.broken_image, color: Colors.grey[400]),
            ),
            fadeInDuration: isCachedInMemory
                ? Duration.zero // No fade if already in cache
                : Duration(milliseconds: widget.fadeInDurationMs), // Fade if from network
          );
        },
      ),
    );
  }
}