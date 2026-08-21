import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onlystudy/l10n/app_localizations.dart';
import 'package:onlystudy/services/update_checker.dart';
import 'package:onlystudy/services/update_service.dart';
import 'package:onlystudy/services/settings_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 展示层测试：UpdateService 根据 UpdateCheckResult 显示正确的 UI。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late UpdateService service;

  setUp(() async {
    service = UpdateService();
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'onlystudy',
      packageName: 'com.example.onlystudy',
      version: '0.7.0',
      buildNumber: '1',
      buildSignature: '',
    );
    await SettingsService().init();
  });

  tearDown(() {
    service.checkerFactory = null;
    SettingsService().resetForTest();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('zh'),
        home: Scaffold(body: SizedBox()),
      ),
    );
  }

  testWidgets('shows update dialog when a newer version exists', (
    tester,
  ) async {
    service.checkerFactory = () => UpdateChecker(
      currentVersion: '0.7.0',
      fetchRelease: () async => const ReleaseInfo(
        version: '0.8.0',
        url: 'https://github.com/conradsheeran/onlystudy/releases',
        notes: '- 新功能',
      ),
    );

    await pumpApp(tester);
    await service.checkUpdate(tester.element(find.byType(Scaffold)));
    await tester.pumpAndSettle();

    expect(find.text('发现新版本: 0.8.0'), findsOneWidget);
    expect(find.text('立即更新'), findsOneWidget);
  });

  testWidgets(
    'shows "already latest" snackbar on manual check when up to date',
    (tester) async {
      service.checkerFactory = () => UpdateChecker(
        currentVersion: '0.8.0',
        fetchRelease: () async => const ReleaseInfo(
          version: '0.8.0',
          url: 'https://github.com/conradsheeran/onlystudy/releases',
          notes: '',
        ),
      );

      await pumpApp(tester);
      await service.checkUpdate(tester.element(find.byType(Scaffold)));
      await tester.pumpAndSettle();

      expect(find.text('已是最新版本'), findsOneWidget);
    },
  );

  testWidgets('shows failure snackbar on manual check when check fails', (
    tester,
  ) async {
    service.checkerFactory = () =>
        UpdateChecker(currentVersion: '0.7.0', fetchRelease: () async => null);

    await pumpApp(tester);
    await service.checkUpdate(tester.element(find.byType(Scaffold)));
    await tester.pumpAndSettle();

    expect(find.text('检查更新失败'), findsOneWidget);
  });

  testWidgets('stays silent on auto check when up to date', (tester) async {
    service.checkerFactory = () => UpdateChecker(
      currentVersion: '0.8.0',
      fetchRelease: () async => const ReleaseInfo(
        version: '0.8.0',
        url: 'https://github.com/conradsheeran/onlystudy/releases',
        notes: '',
      ),
    );

    await pumpApp(tester);
    await service.checkUpdate(
      tester.element(find.byType(Scaffold)),
      silent: true,
    );
    await tester.pumpAndSettle();

    expect(find.text('已是最新版本'), findsNothing);
  });

  testWidgets('stays silent on auto check when check fails', (tester) async {
    service.checkerFactory = () => UpdateChecker(
      currentVersion: '0.7.0',
      fetchRelease: () async => throw Exception('network down'),
    );

    await pumpApp(tester);
    await service.checkUpdate(
      tester.element(find.byType(Scaffold)),
      silent: true,
    );
    await tester.pumpAndSettle();

    expect(find.text('检查更新失败'), findsNothing);
  });

  testWidgets('skips auto check when auto check is disabled', (tester) async {
    SharedPreferences.setMockInitialValues({'auto_check_update': false});
    await SettingsService().init();
    var checkerCalled = false;
    service.checkerFactory = () {
      checkerCalled = true;
      return UpdateChecker(
        currentVersion: '0.7.0',
        fetchRelease: () async => null,
      );
    };

    await pumpApp(tester);
    await service.checkUpdate(
      tester.element(find.byType(Scaffold)),
      silent: true,
    );
    await tester.pumpAndSettle();

    expect(checkerCalled, isFalse);
  });

  testWidgets('auto check remembers prompted version', (tester) async {
    service.checkerFactory = () => UpdateChecker(
      currentVersion: '0.7.0',
      fetchRelease: () async => const ReleaseInfo(
        version: '0.8.0',
        url: 'https://github.com/conradsheeran/onlystudy/releases',
        notes: '',
      ),
    );

    await pumpApp(tester);
    await service.checkUpdate(
      tester.element(find.byType(Scaffold)),
      silent: true,
    );
    await tester.pumpAndSettle();

    // 弹窗出现，且记录已提示版本
    expect(find.text('发现新版本: 0.8.0'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('last_prompted_update_version'), '0.8.0');
  });

  testWidgets('auto check does not re-prompt same version', (tester) async {
    SharedPreferences.setMockInitialValues({
      'last_prompted_update_version': '0.8.0',
    });
    await SettingsService().init();
    var checkerCalled = false;
    service.checkerFactory = () {
      checkerCalled = true;
      return UpdateChecker(
        currentVersion: '0.7.0',
        fetchRelease: () async => const ReleaseInfo(
          version: '0.8.0',
          url: 'https://github.com/conradsheeran/onlystudy/releases',
          notes: '',
        ),
      );
    };

    await pumpApp(tester);
    await service.checkUpdate(
      tester.element(find.byType(Scaffold)),
      silent: true,
    );
    await tester.pumpAndSettle();

    expect(checkerCalled, isTrue);
    expect(find.text('发现新版本: 0.8.0'), findsNothing);
  });
}
