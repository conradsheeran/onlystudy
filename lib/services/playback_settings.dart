/// 会话只依赖的背景播放开关，避免反向依赖整个 SettingsService（OPT-012）。
abstract class PlaybackSettings {
  bool get enableBackgroundPlayback;
}
