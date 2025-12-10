import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final bool isLoggedIn = await AuthService().isLoggedIn();
  
  runApp(OnlyStudyApp(initialRoute: isLoggedIn ? const HomeScreen() : const LoginScreen()));
}

class OnlyStudyApp extends StatelessWidget {
  final Widget initialRoute;
  const OnlyStudyApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OnlyStudy',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: initialRoute,
      debugShowCheckedModeBanner: false,
    );
  }
}