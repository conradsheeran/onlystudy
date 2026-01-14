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
  // 设置图片缓存限制为 500MB，避免内存溢出
  PaintingBinding.instance.imageCache.maximumSizeBytes = 500 * 1024 * 1024;
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
