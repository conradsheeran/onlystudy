/// 应用设置的不可变快照。
///
/// SettingsService 暴露 `ValueNotifier<AppSettings> settings`，
/// 设置变更后发布一个新快照，页面监听同一接口自动刷新。
class AppSettings {
  final int defaultResolution;
  final bool autoCheckUpdate;
  final String? lastPromptedUpdateVersion;
  final double defaultPlaybackSpeed;
  final bool enableBackgroundPlayback;
  final String? localeCode;

  const AppSettings({
    required this.defaultResolution,
    required this.autoCheckUpdate,
    required this.lastPromptedUpdateVersion,
    required this.defaultPlaybackSpeed,
    required this.enableBackgroundPlayback,
    required this.localeCode,
  });

  AppSettings copyWith({
    int? defaultResolution,
    bool? autoCheckUpdate,
    String? lastPromptedUpdateVersion,
    double? defaultPlaybackSpeed,
    bool? enableBackgroundPlayback,
    String? localeCode,
  }) {
    return AppSettings(
      defaultResolution: defaultResolution ?? this.defaultResolution,
      autoCheckUpdate: autoCheckUpdate ?? this.autoCheckUpdate,
      lastPromptedUpdateVersion:
          lastPromptedUpdateVersion ?? this.lastPromptedUpdateVersion,
      defaultPlaybackSpeed: defaultPlaybackSpeed ?? this.defaultPlaybackSpeed,
      enableBackgroundPlayback:
          enableBackgroundPlayback ?? this.enableBackgroundPlayback,
      localeCode: localeCode ?? this.localeCode,
    );
  }
}
