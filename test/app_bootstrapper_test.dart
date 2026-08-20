import 'package:flutter_test/flutter_test.dart';
import 'package:onlystudy/services/app_bootstrapper.dart';
import 'package:onlystudy/widgets/bootstrap_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BootstrapResult', () {
    test('BootstrapReady 携带登录状态', () {
      const ready = BootstrapReady(isLoggedIn: true);
      expect(ready, isA<BootstrapReady>());
      expect(ready.isLoggedIn, isTrue);
    });

    test('BootstrapFailed 记录阶段与错误', () {
      const failed = BootstrapFailed(
        phase: BootstrapPhase.download,
        error: 'db open error',
      );
      expect(failed.phase, BootstrapPhase.download);
      expect(failed.error, 'db open error');
    });

    test('sealed 类型可被模式匹配区分', () {
      BootstrapResult result = const BootstrapFailed(
        phase: BootstrapPhase.audio,
        error: 'init failed',
      );
      expect(result, isA<BootstrapFailed>());
      expect(result, isNot(isA<BootstrapReady>()));
    });
  });

  group('BootstrapApp widget', () {
    testWidgets('显示失败阶段与重试按钮', (tester) async {
      const failure = BootstrapFailed(
        phase: BootstrapPhase.cache,
        error: 'cache error',
      );
      var retried = false;

      await tester.pumpWidget(
        BootstrapApp(
          failure: failure,
          onRetry: () => retried = true,
        ),
      );

      // 测试环境默认 en locale；断言英文文案（App 实际运行跟随系统）
      expect(find.text('App failed to start'), findsOneWidget);
      expect(find.text('Error during startup phase cache. Please retry.'),
          findsOneWidget);

      await tester.tap(find.text('Retry'));
      expect(retried, isTrue);
    });
  });
}
