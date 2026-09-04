import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:onlystudy/l10n/app_localizations.dart';

/// HUD 显示类型
sealed class PlayerChromeHud {
  const PlayerChromeHud();
}

class VolumeHud extends PlayerChromeHud {
  final double volume;
  const VolumeHud(this.volume);
}

class BrightnessHud extends PlayerChromeHud {
  final double brightness;
  const BrightnessHud(this.brightness);
}

class SpeedHud extends PlayerChromeHud {
  final double speed;
  const SpeedHud(this.speed);
}

class SeekPreviewHud extends PlayerChromeHud {
  final Duration target;
  final bool isForward;
  const SeekPreviewHud({required this.target, required this.isForward});
}

/// 播放器控件层不可变状态
@immutable
class PlayerChromeState {
  final Duration position;
  final Duration duration;
  final Duration buffered;
  final bool isPlaying;
  final bool isBuffering;
  final bool isSeeking;
  final String title;
  final String? partLabel;
  final String speedLabel;
  final String qualityLabel;
  final bool hasParts;
  final bool isFullscreen;
  final bool isLocked;
  final bool controlsVisible;
  final PlayerChromeHud? hud;
  final List<double> availableSpeeds;
  final List<int> availableQualities;
  final List<String> availableQualityDescs;
  final int? currentQuality;

  const PlayerChromeState({
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.buffered = Duration.zero,
    this.isPlaying = false,
    this.isBuffering = false,
    this.isSeeking = false,
    this.title = '',
    this.partLabel,
    this.speedLabel = '1.0x',
    this.qualityLabel = '',
    this.hasParts = false,
    this.isFullscreen = false,
    this.isLocked = false,
    this.controlsVisible = true,
    this.hud,
    this.availableSpeeds = const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0],
    this.availableQualities = const [],
    this.availableQualityDescs = const [],
    this.currentQuality,
  });

  PlayerChromeState copyWith({
    Duration? position,
    Duration? duration,
    Duration? buffered,
    bool? isPlaying,
    bool? isBuffering,
    bool? isSeeking,
    String? title,
    String? partLabel,
    String? speedLabel,
    String? qualityLabel,
    bool? hasParts,
    bool? isFullscreen,
    bool? isLocked,
    bool? controlsVisible,
    PlayerChromeHud? hud,
    List<double>? availableSpeeds,
    List<int>? availableQualities,
    List<String>? availableQualityDescs,
    int? currentQuality,
  }) {
    return PlayerChromeState(
      position: position ?? this.position,
      duration: duration ?? this.duration,
      buffered: buffered ?? this.buffered,
      isPlaying: isPlaying ?? this.isPlaying,
      isBuffering: isBuffering ?? this.isBuffering,
      isSeeking: isSeeking ?? this.isSeeking,
      title: title ?? this.title,
      partLabel: partLabel ?? this.partLabel,
      speedLabel: speedLabel ?? this.speedLabel,
      qualityLabel: qualityLabel ?? this.qualityLabel,
      hasParts: hasParts ?? this.hasParts,
      isFullscreen: isFullscreen ?? this.isFullscreen,
      isLocked: isLocked ?? this.isLocked,
      controlsVisible: controlsVisible ?? this.controlsVisible,
      hud: hud ?? this.hud,
      availableSpeeds: availableSpeeds ?? this.availableSpeeds,
      availableQualities: availableQualities ?? this.availableQualities,
      availableQualityDescs:
          availableQualityDescs ?? this.availableQualityDescs,
      currentQuality: currentQuality ?? this.currentQuality,
    );
  }
}

/// 播放器控件层事件回调
class PlayerChromeCallbacks {
  final VoidCallback? onBack;
  final VoidCallback? onPlayPause;
  final ValueChanged<Duration>? onSeek;
  final ValueChanged<Duration>? onSeekPreview;
  final VoidCallback? onToggleFullscreen;
  final VoidCallback? onToggleLock;
  final VoidCallback? onToggleControls;
  final ValueChanged<double>? onSelectSpeed;
  final ValueChanged<int>? onSelectQuality;
  final VoidCallback? onShowParts;
  final VoidCallback? onDownload;
  final ValueChanged<double>? onVolumeDelta;
  final ValueChanged<double>? onBrightnessDelta;

  const PlayerChromeCallbacks({
    this.onBack,
    this.onPlayPause,
    this.onSeek,
    this.onSeekPreview,
    this.onToggleFullscreen,
    this.onToggleLock,
    this.onToggleControls,
    this.onSelectSpeed,
    this.onSelectQuality,
    this.onShowParts,
    this.onDownload,
    this.onVolumeDelta,
    this.onBrightnessDelta,
  });
}

/// 播放器控件层 Widget
class PlayerChrome extends StatefulWidget {
  final PlayerChromeState state;
  final PlayerChromeCallbacks callbacks;

  const PlayerChrome({
    super.key,
    required this.state,
    required this.callbacks,
  });

  @override
  State<PlayerChrome> createState() => _PlayerChromeState();
}

class _PlayerChromeState extends State<PlayerChrome> {
  Timer? _hideTimer;
  late bool _controlsVisible;
  double? _dragPositionSeconds;

  @override
  void initState() {
    super.initState();
    _controlsVisible = widget.state.controlsVisible;
    _resetHideTimer();
  }

  @override
  void didUpdateWidget(covariant PlayerChrome extendsWidget) {
    super.didUpdateWidget(extendsWidget);
    if (widget.state.controlsVisible != extendsWidget.state.controlsVisible) {
      _controlsVisible = widget.state.controlsVisible;
      _resetHideTimer();
    } else if (widget.state.isSeeking != extendsWidget.state.isSeeking) {
      _resetHideTimer();
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _resetHideTimer() {
    _hideTimer?.cancel();
    if (!_controlsVisible || widget.state.isSeeking) return;
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() {
        _controlsVisible = false;
      });
      widget.callbacks.onToggleControls?.call();
    });
  }

  void _toggleControls() {
    setState(() {
      _controlsVisible = !_controlsVisible;
    });
    _resetHideTimer();
    widget.callbacks.onToggleControls?.call();
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (duration.inHours > 0) {
      return '${duration.inHours}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  Widget _buildTimeReadout(Duration position, Duration duration) {
    final posStr = _formatDuration(position);
    final durStr = _formatDuration(duration);
    final sampleStr =
        duration.inHours > 0 ? '00:00:00 / 00:00:00' : '00:00 / 00:00';
    const textStyle = TextStyle(
      color: Colors.white,
      fontSize: 12,
      fontFeatures: [FontFeature.tabularFigures()],
    );

    final painter = TextPainter(
      text: TextSpan(text: sampleStr, style: textStyle),
      textDirection: TextDirection.ltr,
    )..layout();

    return SizedBox(
      key: const Key('player_chrome_time_readout'),
      width: painter.width + 4.0,
      child: Text(
        '$posStr / $durStr',
        style: textStyle,
        textAlign: TextAlign.center,
        maxLines: 1,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final viewPadding = MediaQuery.viewPaddingOf(context);
    final horizontalSafePadding = widget.state.isFullscreen
        ? EdgeInsets.only(left: viewPadding.left, right: viewPadding.right)
        : EdgeInsets.zero;

    final titleText = (widget.state.partLabel != null &&
            widget.state.partLabel!.isNotEmpty)
        ? '${widget.state.title} - ${widget.state.partLabel}'
        : widget.state.title;

    final durationSeconds = widget.state.duration.inMilliseconds / 1000.0;
    final positionSeconds = _dragPositionSeconds ??
        (widget.state.position.inMilliseconds / 1000.0);
    final sliderMax = max(1.0, durationSeconds);
    final progressFraction = (positionSeconds / sliderMax).clamp(0.0, 1.0);
    final bufferFraction = (widget.state.buffered.inMilliseconds /
            max(1, widget.state.duration.inMilliseconds))
        .clamp(0.0, 1.0);

    return Stack(
      children: [
        // 1. 全局手势层（单击切换显示）
        Positioned.fill(
          child: GestureDetector(
            key: const Key('player_chrome_gesture_detector'),
            behavior: HitTestBehavior.translucent,
            onTap: _toggleControls,
          ),
        ),

        // 2. 缓冲中转圈
        if (widget.state.isBuffering)
          const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),

        // 3. 控件层（带动画显示/隐藏）
        AnimatedOpacity(
          key: const Key('player_chrome_controls'),
          opacity: _controlsVisible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeInOut,
          child: IgnorePointer(
            ignoring: !_controlsVisible,
            child: Padding(
              padding: horizontalSafePadding,
              child: Stack(
              children: [
                // 顶部操作栏
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xBF000000), Colors.transparent],
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8.0,
                      vertical: 4.0,
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back, color: Colors.white),
                          onPressed: widget.callbacks.onBack,
                        ),
                        Expanded(
                          child: Text(
                            titleText,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (widget.state.hasParts)
                          IconButton(
                            icon: const Icon(Icons.list, color: Colors.white),
                            tooltip: l10n?.partsList ?? '分集列表',
                            onPressed: widget.callbacks.onShowParts,
                          ),
                        PopupMenuButton<double>(
                          initialValue: widget.state.availableSpeeds.contains(
                            double.tryParse(
                                  widget.state.speedLabel.replaceAll('x', ''),
                                ) ??
                                1.0,
                          )
                              ? double.tryParse(
                                  widget.state.speedLabel.replaceAll('x', ''),
                                )
                              : null,
                          tooltip: l10n?.playbackSpeed ?? '倍速',
                          onSelected: (speed) {
                            _resetHideTimer();
                            widget.callbacks.onSelectSpeed?.call(speed);
                          },
                          color: theme.colorScheme.surfaceContainer,
                          itemBuilder: (context) {
                            return widget.state.availableSpeeds.map((s) {
                              return PopupMenuItem(
                                value: s,
                                child: Text(
                                  '${s}x',
                                  style: TextStyle(
                                    color: (widget.state.speedLabel == '${s}x')
                                        ? primaryColor
                                        : Colors.white,
                                  ),
                                ),
                              );
                            }).toList();
                          },
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 10.0),
                            child: Text(
                              widget.state.speedLabel,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.download, color: Colors.white),
                          tooltip: l10n?.downloadCache ?? '缓存',
                          onPressed: widget.callbacks.onDownload,
                        ),
                        if (widget.state.availableQualities.isNotEmpty)
                          PopupMenuButton<int>(
                            initialValue: widget.state.currentQuality,
                            tooltip: l10n?.quality ?? '清晰度',
                            onSelected: (quality) {
                              _resetHideTimer();
                              widget.callbacks.onSelectQuality?.call(quality);
                            },
                            color: theme.colorScheme.surfaceContainer,
                            itemBuilder: (context) {
                              return List.generate(
                                widget.state.availableQualities.length,
                                (index) {
                                  final q =
                                      widget.state.availableQualities[index];
                                  final desc = index <
                                          widget
                                              .state
                                              .availableQualityDescs
                                              .length
                                      ? widget
                                          .state.availableQualityDescs[index]
                                      : '$q';
                                  final isSelected =
                                      q == widget.state.currentQuality;
                                  return PopupMenuItem(
                                    value: q,
                                    child: Text(
                                      desc,
                                      style: TextStyle(
                                        color: isSelected
                                            ? primaryColor
                                            : Colors.white,
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12.0),
                              child: Text(
                                widget.state.qualityLabel,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                // 中央播放/暂停按键
                Center(
                  child: IconButton(
                    iconSize: 52,
                    icon: Icon(
                      widget.state.isPlaying
                          ? Icons.pause
                          : Icons.play_arrow,
                      color: Colors.white,
                    ),
                    onPressed: () {
                      _resetHideTimer();
                      widget.callbacks.onPlayPause?.call();
                    },
                  ),
                ),

                // 底部操作栏（进度条 + 全屏按钮）
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Color(0xBF000000), Colors.transparent],
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Row(
                      children: [
                        _buildTimeReadout(
                          Duration(
                            milliseconds: (positionSeconds * 1000).round(),
                          ),
                          widget.state.duration,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: PlayerProgressBar(
                            key: const Key('player_chrome_main_progress_bar'),
                            progressFraction: progressFraction,
                            bufferFraction: bufferFraction,
                            primaryColor: primaryColor,
                            onSeekPreview: (fraction) {
                              final targetSeconds = fraction * durationSeconds;
                              setState(() {
                                _dragPositionSeconds = targetSeconds;
                              });
                              _hideTimer?.cancel();
                              widget.callbacks.onSeekPreview?.call(
                                Duration(
                                  milliseconds: (targetSeconds * 1000).round(),
                                ),
                              );
                            },
                            onSeek: (fraction) {
                              final targetSeconds = fraction * durationSeconds;
                              setState(() {
                                _dragPositionSeconds = null;
                              });
                              _resetHideTimer();
                              widget.callbacks.onSeek?.call(
                                Duration(
                                  milliseconds: (targetSeconds * 1000).round(),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: Icon(
                            widget.state.isFullscreen
                                ? Icons.fullscreen_exit
                                : Icons.fullscreen,
                            color: Colors.white,
                          ),
                          onPressed: () {
                            _resetHideTimer();
                            widget.callbacks.onToggleFullscreen?.call();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              ),
            ),
          ),
        ),

        // 4. 控件隐藏后的常驻细进度条
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            ignoring: true,
            child: AnimatedOpacity(
              opacity: _controlsVisible ? 0.0 : 1.0,
              duration: const Duration(milliseconds: 150),
              child: SizedBox(
                key: const Key('player_chrome_tiny_progress_bar'),
                height: 2.5,
                child: CustomPaint(
                  painter: _ProgressBarPainter(
                    progressFraction: progressFraction,
                    bufferFraction: bufferFraction,
                    trackHeight: 2.5,
                    thumbRadius: 0.0,
                    primaryColor: primaryColor,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 进度条绘制器（支持缓冲进度与等比圆角轨道）
class _ProgressBarPainter extends CustomPainter {
  final double progressFraction;
  final double bufferFraction;
  final double trackHeight;
  final double thumbRadius;
  final Color primaryColor;

  _ProgressBarPainter({
    required this.progressFraction,
    required this.bufferFraction,
    required this.trackHeight,
    required this.thumbRadius,
    required this.primaryColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final trackRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        0,
        (size.height - trackHeight) / 2,
        size.width,
        trackHeight,
      ),
      Radius.circular(trackHeight / 2),
    );

    // 1. 底轨色
    final bgPaint = Paint()..color = const Color(0x33FFFFFF);
    canvas.drawRRect(trackRect, bgPaint);

    // 2. 缓冲轨
    if (bufferFraction > 0) {
      final bufferWidth = size.width * bufferFraction.clamp(0.0, 1.0);
      final bufferRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          0,
          (size.height - trackHeight) / 2,
          bufferWidth,
          trackHeight,
        ),
        Radius.circular(trackHeight / 2),
      );
      final bufferPaint = Paint()..color = primaryColor.withValues(alpha: 0.4);
      canvas.drawRRect(bufferRect, bufferPaint);
    }

    // 3. 播放进度轨
    final progressWidth = size.width * progressFraction.clamp(0.0, 1.0);
    final progressRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        0,
        (size.height - trackHeight) / 2,
        progressWidth,
        trackHeight,
      ),
      Radius.circular(trackHeight / 2),
    );
    final progressPaint = Paint()..color = primaryColor;
    canvas.drawRRect(progressRect, progressPaint);

    // 4. Thumb 拖动点
    if (thumbRadius > 0) {
      final thumbCenter = Offset(
        progressWidth.clamp(thumbRadius, size.width - thumbRadius),
        size.height / 2,
      );
      final thumbPaint = Paint()..color = primaryColor;
      canvas.drawCircle(thumbCenter, thumbRadius, thumbPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ProgressBarPainter oldDelegate) {
    return oldDelegate.progressFraction != progressFraction ||
        oldDelegate.bufferFraction != bufferFraction ||
        oldDelegate.trackHeight != trackHeight ||
        oldDelegate.thumbRadius != thumbRadius ||
        oldDelegate.primaryColor != primaryColor;
  }
}

/// 应用自有进度条 Widget（支持缓冲展示、拖动交互与冻结更新）
class PlayerProgressBar extends StatelessWidget {
  final double progressFraction;
  final double bufferFraction;
  final double trackHeight;
  final double thumbRadius;
  final Color primaryColor;
  final ValueChanged<double>? onSeekPreview;
  final ValueChanged<double>? onSeek;

  const PlayerProgressBar({
    super.key,
    required this.progressFraction,
    required this.bufferFraction,
    this.trackHeight = 3.5,
    this.thumbRadius = 7.0,
    required this.primaryColor,
    this.onSeekPreview,
    this.onSeek,
  });

  void _handleDrag(Offset localPosition, double width) {
    if (width <= 0) return;
    final fraction = (localPosition.dx / width).clamp(0.0, 1.0);
    onSeekPreview?.call(fraction);
  }

  void _handleDragEnd(Offset localPosition, double width) {
    if (width <= 0) return;
    final fraction = (localPosition.dx / width).clamp(0.0, 1.0);
    onSeek?.call(fraction);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (details) =>
              _handleDrag(details.localPosition, width),
          onHorizontalDragUpdate: (details) =>
              _handleDrag(details.localPosition, width),
          onHorizontalDragEnd: (details) =>
              _handleDragEnd(details.localPosition, width),
          onTapDown: (details) {
            _handleDrag(details.localPosition, width);
            _handleDragEnd(details.localPosition, width);
          },
          child: SizedBox(
            height: max(24.0, thumbRadius * 2),
            child: CustomPaint(
              size: Size(width, max(24.0, thumbRadius * 2)),
              painter: _ProgressBarPainter(
                progressFraction: progressFraction,
                bufferFraction: bufferFraction,
                trackHeight: trackHeight,
                thumbRadius: thumbRadius,
                primaryColor: primaryColor,
              ),
            ),
          ),
        );
      },
    );
  }
}
