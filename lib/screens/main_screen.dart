import 'package:flutter/material.dart';
import 'package:onlystudy/l10n/app_localizations.dart';
import '../services/update_service.dart';
import 'home_screen.dart';
import 'settings_screen.dart';

/// 主界面容器，包含底部导航栏和子页面切换
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  static const double _railBreakpoint = 900;
  int _currentIndex = 0;
  final List<Widget> _screens = [
    const HomeScreen(),
    const SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // 界面加载完成后自动检查更新
    WidgetsBinding.instance.addPostFrameCallback((_) {
      UpdateService().checkUpdate(context, silent: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final locale = AppLocalizations.of(context)!;
    final isWideLayout = MediaQuery.sizeOf(context).width >= _railBreakpoint;
    final destinations = [
      NavigationDestination(
        icon: const Icon(Icons.home_outlined),
        selectedIcon: const Icon(Icons.home),
        label: locale.home,
      ),
      NavigationDestination(
        icon: const Icon(Icons.settings_outlined),
        selectedIcon: const Icon(Icons.settings),
        label: locale.settings,
      ),
    ];

    return Scaffold(
      body: isWideLayout
          ? Row(
              children: [
                SafeArea(
                  child: NavigationRail(
                    selectedIndex: _currentIndex,
                    labelType: NavigationRailLabelType.all,
                    onDestinationSelected: (index) {
                      setState(() {
                        _currentIndex = index;
                      });
                    },
                    destinations: [
                      NavigationRailDestination(
                        icon: destinations[0].icon,
                        selectedIcon: destinations[0].selectedIcon,
                        label: Text(destinations[0].label),
                      ),
                      NavigationRailDestination(
                        icon: destinations[1].icon,
                        selectedIcon: destinations[1].selectedIcon,
                        label: Text(destinations[1].label),
                      ),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: IndexedStack(
                    index: _currentIndex,
                    children: _screens,
                  ),
                ),
              ],
            )
          : IndexedStack(
              index: _currentIndex,
              children: _screens,
            ),
      bottomNavigationBar: isWideLayout
          ? null
          : NavigationBar(
              selectedIndex: _currentIndex,
              onDestinationSelected: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              destinations: destinations,
            ),
    );
  }
}
