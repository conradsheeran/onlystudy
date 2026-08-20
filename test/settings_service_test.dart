import 'package:flutter_test/flutter_test.dart';
import 'package:onlystudy/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// OPT-014：设置通过不可变快照 + 统一 notifier 发布。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsService settings 快照', () {
    test('init 后发布已加载设置', () async {
      SharedPreferences.setMockInitialValues({
        'default_resolution': 80,
        'default_playback_speed': 1.5,
      });
      final service = SettingsService();
      service.resetForTest();

      await service.init();

      expect(service.settings.value.defaultResolution, 80);
      expect(service.settings.value.defaultPlaybackSpeed, 1.5);
    });

    test('setter 更新后发布新快照（不可变）', () async {
      SharedPreferences.setMockInitialValues({});
      final service = SettingsService();
      service.resetForTest();
      await service.init();

      final before = service.settings.value;
      await service.setDefaultResolution(112);
      final after = service.settings.value;

      expect(after.defaultResolution, 112);
      // 不可变：旧快照不受影响
      expect(before.defaultResolution, 64);
    });

    test('多个 setter 后快照一致', () async {
      SharedPreferences.setMockInitialValues({});
      final service = SettingsService();
      service.resetForTest();
      await service.init();

      await service.setDefaultPlaybackSpeed(2.0);
      await service.setEnableBackgroundPlayback(false);
      await service.setLocale('en');

      final s = service.settings.value;
      expect(s.defaultPlaybackSpeed, 2.0);
      expect(s.enableBackgroundPlayback, isFalse);
      expect(s.localeCode, 'en');
    });

    test('notifier 在设置变更时通知监听者', () async {
      SharedPreferences.setMockInitialValues({});
      final service = SettingsService();
      service.resetForTest();
      await service.init();

      var notified = 0;
      service.settings.addListener(() => notified++);
      await service.setDefaultResolution(32);
      await service.setDefaultResolution(16);

      expect(notified, 2);
    });
  });
}
