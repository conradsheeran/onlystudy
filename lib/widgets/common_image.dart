import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/cache_service.dart';
/// 通用网络图片加载组件，支持缓存和淡入动画
///
/// 直接使用 [CachedNetworkImage] 的缓存与淡入能力；不再先查询文件
/// 缓存来判断淡入时长（OPT-010：避免为动画时长做一次磁盘查询，
/// 且原 `isCachedInMemory` 变量名会误导维护者）。
///
/// 所有图片共享 [CacheService.imageCacheManager] 统一实例：
/// 设置页清理图片缓存时，正在展示的图片也会立即失效。
class CommonImage extends StatefulWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double radius;
  final int fadeInDurationMs;

  /// 解码内存缓存的目标宽度（逻辑像素）。
  ///
  /// 缩略图按实际展示尺寸解码，避免把原图完整解码进内存
  /// （OPT-010：500 MiB 解码缓存下更易触发 OOM）。
  final int? memCacheWidth;

  /// 解码内存缓存的目标高度（逻辑像素）。
  final int? memCacheHeight;

  const CommonImage(
    this.imageUrl, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.radius = 0,
    this.fadeInDurationMs = 300,
    this.memCacheWidth,
    this.memCacheHeight,
  });

  @override
  State<CommonImage> createState() => _CommonImageState();
}

class _CommonImageState extends State<CommonImage> {
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

    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    final memCacheWidth = widget.memCacheWidth ??
        (widget.width == null ? null : (widget.width! * devicePixelRatio).round());
    final memCacheHeight = widget.memCacheHeight ??
        (widget.height == null
            ? null
            : (widget.height! * devicePixelRatio).round());

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: CachedNetworkImage(
        imageUrl: widget.imageUrl,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        memCacheWidth: memCacheWidth,
        memCacheHeight: memCacheHeight,
        cacheManager: CacheService.imageCacheManager,
        placeholder: (context, url) => Container(color: Colors.grey[200]),
        errorWidget: (context, url, error) => Container(
          color: Colors.grey[200],
          child: Icon(Icons.broken_image, color: Colors.grey[400]),
        ),
        fadeInDuration: Duration(milliseconds: widget.fadeInDurationMs),
      ),
    );
  }
}
