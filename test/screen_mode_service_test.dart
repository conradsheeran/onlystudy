import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onlystudy/services/screen_mode_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final service = ScreenModeService();

  setUp(() {
    service.reset();
    service.testingIsDesktop = false;
  });

  tearDown(() {
    service.reset();
  });

  group('ScreenModeService 幂等与重试', () {
    test('重复设置相同方向不会触发多余平台记录', () async {
      const target = [DeviceOrientation.landscapeLeft];
      await service.setPreferredOrientations(target);
      expect(service.lastOrientations, target);

      // 第二次相同调用直接走幂等守卫
      await service.setPreferredOrientations(target);
      expect(service.lastOrientations, target);
    });

    test('重置后状态被清空，可再次下发', () async {
      const target = [DeviceOrientation.landscapeLeft];
      await service.setPreferredOrientations(target);
      expect(service.lastOrientations, target);

      service.reset();
      expect(service.lastOrientations, isNull);
      expect(service.lastUiMode, isNull);
    });

    test('退出全屏在 Android < 29 时使用 manual，>= 29 时使用 edgeToEdge', () async {
      await service.exitFullscreen(androidSdkInt: 28);
      expect(service.lastOrientations, [DeviceOrientation.portraitUp]);
      expect(service.lastUiMode, SystemUiMode.manual);

      service.reset();
      service.testingIsDesktop = false;
      await service.exitFullscreen(androidSdkInt: 29);
      expect(service.lastOrientations, [DeviceOrientation.portraitUp]);
      expect(service.lastUiMode, SystemUiMode.edgeToEdge);
    });
  });
}
