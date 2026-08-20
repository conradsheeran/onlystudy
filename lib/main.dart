import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:onlystudy/l10n/app_localizations.dart';
import 'package:onlystudy/services/app_bootstrapper.dart';

import 'screens/login_screen.dart';
import 'screens/main_screen.dart';
import 'services/settings_service.dart';
import 'theme/app_theme.dart';
import 'widgets/bootstrap_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 图片解码缓存使用 Flutter 默认预算（100 MiB）；不再提高为
  // 500 MiB，避免移动端 OOM 风险（OPT-010）
  runApp(const BootstrapGate());
}

/// 启动门卫（OPT-011）。
///
/// 先运行 [AppBootstrapper] 按既有顺序初始化；失败时显示 [BootstrapApp]
/// 错误界面与重试入口，而不是在 runApp 前崩溃或进入半初始化状态。
class BootstrapGate extends StatefulWidget {
  const BootstrapGate({super.key, this.bootstrapper});

  final AppBootstrapper? bootstrapper;

  @override
  State<BootstrapGate> createState() => _BootstrapGateState();
}

class _BootstrapGateState extends State<BootstrapGate> {
  late final AppBootstrapper _bootstrapper;
  BootstrapResult? _result;

  @override
  void initState() {
    super.initState();
    _bootstrapper = widget.bootstrapper ?? const AppBootstrapper();
    _start();
  }

  Future<void> _start() async {
    final result = await _bootstrapper.bootstrap();
    if (!mounted) return;
    setState(() {
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    if (result == null) {
      // 启动中：显示占位，避免黑屏
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }
    return switch (result) {
      BootstrapReady(:final isLoggedIn) => OnlyStudyApp(
          initialRoute: isLoggedIn ? const MainScreen() : const LoginScreen(),
        ),
      BootstrapFailed(:final phase, :final error) => BootstrapApp(
          failure: BootstrapFailed(phase: phase, error: error),
          onRetry: _start,
        ),
    };
  }
}

class OnlyStudyApp extends StatelessWidget {
  final Widget initialRoute;
  const OnlyStudyApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale?>(
      valueListenable: SettingsService().localeNotifier,
      builder: (context, locale, child) {
        return MaterialApp(
          onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('en'),
            Locale('zh'),
          ],
          locale: locale,
          theme: AppTheme.darkTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.dark,
          home: initialRoute,
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}
