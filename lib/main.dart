import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:onlystudy/l10n/app_localizations.dart';
import 'package:media_kit/media_kit.dart';
import 'package:onlystudy/services/cache_service.dart';
import 'package:onlystudy/services/settings_service.dart';
import 'theme/app_theme.dart';
import 'screens/main_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';
import 'services/audio_handler.dart';
import 'services/download_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 图片解码缓存使用 Flutter 默认预算（100 MiB）；不再提高为
  // 500 MiB，避免移动端 OOM 风险（OPT-010）
  MediaKit.ensureInitialized();
  await DownloadService().init();
  await CacheService().checkAndClearCache();
  await initAudioService();
  await SettingsService().init();
  final bool isLoggedIn = await AuthService().isLoggedIn();

  runApp(
    OnlyStudyApp(
      initialRoute: isLoggedIn ? const MainScreen() : const LoginScreen(),
    ),
  );
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
