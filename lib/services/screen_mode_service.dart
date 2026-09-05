import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 屏幕显示模式服务（方向控制与系统栏控制薄适配层，含幂等守卫与失败重试）
class ScreenModeService {
  static final ScreenModeService _instance = ScreenModeService._internal();
  factory ScreenModeService() => _instance;
  ScreenModeService._internal();

  static const MethodChannel _desktopChannel = MethodChannel(
    'com.alexmercerind/media_kit_video',
  );

  List<DeviceOrientation>? _lastOrientations;
  SystemUiMode? _lastUiMode;

  @visibleForTesting
  List<DeviceOrientation>? get lastOrientations => _lastOrientations;

  @visibleForTesting
  SystemUiMode? get lastUiMode => _lastUiMode;

  @visibleForTesting
  bool? testingIsDesktop;

  bool get _isDesktop =>
      testingIsDesktop ??
      (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS));

  /// 幂等设置屏幕方向（成功后才记录状态，调用异常保留可重试性）
  Future<void> setPreferredOrientations(
    List<DeviceOrientation> orientations,
  ) async {
    if (_isDesktop) return;
    if (_lastOrientations != null &&
        listEquals(_lastOrientations, orientations)) {
      return;
    }
    try {
      await SystemChrome.setPreferredOrientations(orientations);
      _lastOrientations = List.unmodifiable(orientations);
    } catch (_) {}
  }

  /// 幂等设置系统UI模式（成功后才记录状态，调用异常保留可重试性）
  Future<void> setEnabledSystemUIMode(
    SystemUiMode mode, {
    List<SystemUiOverlay>? overlays,
  }) async {
    if (_isDesktop) return;
    if (_lastUiMode == mode) return;
    try {
      await SystemChrome.setEnabledSystemUIMode(mode, overlays: overlays);
      _lastUiMode = mode;
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

  /// 退出全屏模式（Android < 29 使用 manual + 全部 overlays 兼容恢复）
  Future<void> exitFullscreen({int? androidSdkInt}) async {
    if (_isDesktop) {
      try {
        await _desktopChannel.invokeMethod('Utils.ExitNativeFullscreen');
      } catch (_) {}
      return;
    }
    await setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    final sdk = androidSdkInt ?? _detectAndroidSdkInt();
    final isPreAndroid29 = (androidSdkInt != null)
        ? (androidSdkInt < 29)
        : (!kIsWeb && Platform.isAndroid && (sdk != null && sdk < 29));
    if (isPreAndroid29) {
      await setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );
    } else {
      await setEnabledSystemUIMode(
        SystemUiMode.edgeToEdge,
        overlays: SystemUiOverlay.values,
      );
    }
  }

  int? _detectAndroidSdkInt() {
    if (kIsWeb || !Platform.isAndroid) return null;
    final match = RegExp(
      r'(?:API|SDK)\s*(\d+)',
      caseSensitive: false,
    ).firstMatch(Platform.operatingSystemVersion);
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }
    final releaseMatch = RegExp(
      r'^(\d+)',
    ).firstMatch(Platform.operatingSystemVersion);
    if (releaseMatch != null) {
      final rel = int.tryParse(releaseMatch.group(1)!);
      if (rel != null) return rel <= 9 ? 28 : 29;
    }
    return null;
  }

  /// 重置记录状态
  void reset() {
    _lastOrientations = null;
    _lastUiMode = null;
    testingIsDesktop = null;
  }
}
