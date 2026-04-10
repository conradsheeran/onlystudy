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
  static const double _desktopRailBreakpoint = 1200;
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
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isWideLayout = screenWidth >= _railBreakpoint;
    final centerRailDestinations =
        screenWidth >= _railBreakpoint && screenWidth < _desktopRailBreakpoint;
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
                _buildSideNavigation(destinations, centerRailDestinations),
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

  Widget _buildSideNavigation(
    List<NavigationDestination> destinations,
    bool centerRailDestinations,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: SizedBox(
        width: 92,
        child: Column(
          mainAxisAlignment: centerRailDestinations
              ? MainAxisAlignment.center
              : MainAxisAlignment.start,
          children: [
            for (int index = 0; index < destinations.length; index++) ...[
              _buildSideNavigationItem(
                destination: destinations[index],
                selected: _currentIndex == index,
                indicatorColor: colorScheme.secondaryContainer,
                selectedIconColor: colorScheme.onSecondaryContainer,
                unselectedIconColor: colorScheme.onSurfaceVariant,
                onTap: () {
                  setState(() {
                    _currentIndex = index;
                  });
                },
              ),
              if (index != destinations.length - 1)
                SizedBox(height: centerRailDestinations ? 14 : 10),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSideNavigationItem({
    required NavigationDestination destination,
    required bool selected,
    required Color indicatorColor,
    required Color selectedIconColor,
    required Color unselectedIconColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              width: 56,
              height: 32,
              decoration: BoxDecoration(
                color: selected ? indicatorColor : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: IconTheme(
                data: IconThemeData(
                  color: selected ? selectedIconColor : unselectedIconColor,
                ),
                child: selected
                    ? destination.selectedIcon ?? destination.icon
                    : destination.icon,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              destination.label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: selected
                        ? Theme.of(context).colorScheme.onSurface
                        : unselectedIconColor,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
