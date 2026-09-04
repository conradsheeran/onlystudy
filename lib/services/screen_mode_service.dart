import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 屏幕显示模式服务（方向控制与系统栏控制薄适配层，含幂等守卫）
class ScreenModeService {
  static final ScreenModeService _instance = ScreenModeService._internal();
  factory ScreenModeService() => _instance;
  ScreenModeService._internal();

  static const MethodChannel _desktopChannel =
      MethodChannel('com.alexmercerind/media_kit_video');

  List<DeviceOrientation>? _lastOrientations;
  SystemUiMode? _lastUiMode;

  bool get _isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  /// 幂等设置屏幕方向
  Future<void> setPreferredOrientations(
      List<DeviceOrientation> orientations) async {
    if (_isDesktop) return;
    if (_lastOrientations != null &&
        listEquals(_lastOrientations, orientations)) {
      return;
    }
    _lastOrientations = List.unmodifiable(orientations);
    try {
      await SystemChrome.setPreferredOrientations(orientations);
    } catch (_) {}
  }

  /// 幂等设置系统UI模式
  Future<void> setEnabledSystemUIMode(SystemUiMode mode) async {
    if (_isDesktop) return;
    if (_lastUiMode == mode) return;
    _lastUiMode = mode;
    try {
      await SystemChrome.setEnabledSystemUIMode(mode);
    } catch (_) {}
  }

  /// 进入全屏模式
  Future<void> enterFullscreen(List<DeviceOrientation> orientations) async {
    if (_isDesktop) {
      try {
        await _desktopChannel.invokeMethod('Utils.EnterNativeFullscreen');
      } catch (_) {}
      return;
    }
    await setPreferredOrientations(orientations);
    await setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  /// 退出全屏模式
  Future<void> exitFullscreen() async {
    if (_isDesktop) {
      try {
        await _desktopChannel.invokeMethod('Utils.ExitNativeFullscreen');
      } catch (_) {}
      return;
    }
    await setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    await setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  /// 重置记录状态
  void reset() {
    _lastOrientations = null;
    _lastUiMode = null;
  }
}
