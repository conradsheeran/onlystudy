import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';
import 'services/download_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DownloadService().init();
  final bool isLoggedIn = await AuthService().isLoggedIn();

  runApp(
    OnlyStudyApp(
      initialRoute: isLoggedIn ? const HomeScreen() : const LoginScreen(),
    ),
  );
}

class OnlyStudyApp extends StatelessWidget {
  final Widget initialRoute;
  const OnlyStudyApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '只准搞学',
      theme: AppTheme.darkTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      home: initialRoute,
      debugShowCheckedModeBanner: false,
    );
  }
}
