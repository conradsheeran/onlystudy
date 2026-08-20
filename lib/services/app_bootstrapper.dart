import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import 'audio_handler.dart';
import 'auth_service.dart';
import 'cache_service.dart';
import 'download_service.dart';
import 'settings_service.dart';

/// 启动阶段（OPT-011）。
enum BootstrapPhase { mediaKit, download, cache, audio, settings, authCheck }

/// 启动结果（sealed）。
sealed class BootstrapResult {
  const BootstrapResult();
}

/// 启动成功。
class BootstrapReady extends BootstrapResult {
  const BootstrapReady({required this.isLoggedIn});

  final bool isLoggedIn;
}

/// 启动失败，记录失败阶段与错误。
class BootstrapFailed extends BootstrapResult {
  const BootstrapFailed({required this.phase, required this.error});

  final BootstrapPhase phase;
  final Object error;
}

/// 应用启动引导（OPT-011）。
///
/// 保留既有启动顺序（各步骤存在真实依赖，不能盲目并行）：
/// MediaKit → DownloadService → CacheService → Audio → Settings → auth。
/// 任一阶段失败都返回 [BootstrapFailed]，由 UI 显示错误状态与重试入口，
/// 而不是在 `runApp()` 前崩溃或进入“看似启动成功、首次使用时再崩溃”的
/// 半初始化状态。
class AppBootstrapper {
  const AppBootstrapper();

  /// 执行完整启动流程。
  ///
  /// [onPhase] 可在每阶段开始时回调（用于 UI 显示进度）。
  Future<BootstrapResult> bootstrap({
    void Function(BootstrapPhase phase)? onPhase,
  }) async {
    BootstrapPhase phase = BootstrapPhase.mediaKit;
    try {
      phase = BootstrapPhase.mediaKit;
      onPhase?.call(phase);
      MediaKit.ensureInitialized();

      phase = BootstrapPhase.download;
      onPhase?.call(phase);
      await DownloadService().init();

      phase = BootstrapPhase.cache;
      onPhase?.call(phase);
      await CacheService().checkAndClearCache();

      phase = BootstrapPhase.audio;
      onPhase?.call(phase);
      await initAudioService();

      phase = BootstrapPhase.settings;
      onPhase?.call(phase);
      await SettingsService().init();

      phase = BootstrapPhase.authCheck;
      onPhase?.call(phase);
      final bool isLoggedIn = await AuthService().isLoggedIn();

      return BootstrapReady(isLoggedIn: isLoggedIn);
    } catch (e, stackTrace) {
      debugPrint('App bootstrap failed: $e\n$stackTrace');
      return BootstrapFailed(phase: phase, error: e);
    }
  }
}
