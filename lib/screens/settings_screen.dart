import 'package:flutter/material.dart';
import 'package:onlystudy/l10n/app_localizations.dart';
import '../services/settings_service.dart';
import '../services/auth_service.dart';
import '../services/cache_service.dart';
import 'about_screen.dart';
import 'login_screen.dart';
import 'select_folders_screen.dart';

/// 设置页面，包含清晰度、倍速、收藏夹过滤、缓存清理等功能
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.settings),
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.video_settings),
            title: Text(AppLocalizations.of(context)!.defaultResolution),
            subtitle: Text(SettingsService
                    .resolutionMap[SettingsService().defaultResolution] ??
                '720P'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: _showResolutionDialog,
          ),
          ListTile(
            leading: const Icon(Icons.speed),
            title: Text(AppLocalizations.of(context)!.defaultPlaybackSpeed),
            subtitle: Text('${SettingsService().defaultPlaybackSpeed}x'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: _showSpeedDialog,
          ),
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(AppLocalizations.of(context)!.language),
            subtitle: Text(_getLanguageName(SettingsService().localeCode)),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: _showLanguageDialog,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.filter_list),
            title: Text(AppLocalizations.of(context)!.selectFolders),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: _handleSelectFolders,
          ),
          ListTile(
            leading: const Icon(Icons.cleaning_services_outlined),
            title: Text(AppLocalizations.of(context)!.clearCache),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: _handleClearCache,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(AppLocalizations.of(context)!.about),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AboutScreen()),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: Text(
              AppLocalizations.of(context)!.logout,
              style: const TextStyle(color: Colors.red),
            ),
            onTap: _handleLogout,
          ),
        ],
      ),
    );
  }

  /// 处理收藏夹选择点击 (包含锁定校验)
  Future<void> _handleSelectFolders() async {
    final isLocked = await AuthService().isFolderSelectionLocked();
    if (isLocked) {
      if (mounted) {
        _showUnlockDialog();
      }
    } else {
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const SelectFoldersScreen()),
        );
      }
    }
  }

  /// 显示解锁对话框
  void _showUnlockDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.unlockFolderSelection),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: InputDecoration(
              hintText: AppLocalizations.of(context)!.enterPassword),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          FilledButton(
            onPressed: () async {
              final isCorrect =
                  await AuthService().checkFolderLockPassword(controller.text);
              if (!context.mounted) return;

              if (isCorrect) {
                await AuthService().setFolderSelectionLocked(false);
                if (context.mounted) {
                  Navigator.pop(context); // Close dialog
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(AppLocalizations.of(context)!.unlocked)),
                  );
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const SelectFoldersScreen()),
                  );
                }
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(
                          AppLocalizations.of(context)!.passwordIncorrect)),
                );
              }
            },
            child: Text(AppLocalizations.of(context)!.unlock),
          ),
        ],
      ),
    );
  }

  /// 处理清理缓存点击
  Future<void> _handleClearCache() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.clearCache),
        content: Text(AppLocalizations.of(context)!.confirmClearCache),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppLocalizations.of(context)!.confirm),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await CacheService().clearCache();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.cacheCleared)),
        );
      }
    }
  }

  /// 验证密码 (通用)
  Future<bool> _verifyPassword() async {
    final controller = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.verifyPassword),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: InputDecoration(
              hintText: AppLocalizations.of(context)!.enterPassword),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          FilledButton(
            onPressed: () async {
              final isCorrect =
                  await AuthService().checkFolderLockPassword(controller.text);
              if (context.mounted) {
                if (isCorrect) {
                  Navigator.pop(context, true);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(
                            AppLocalizations.of(context)!.passwordIncorrect)),
                  );
                }
              }
            },
            child: Text(AppLocalizations.of(context)!.confirm),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// 处理注销点击
  Future<void> _handleLogout() async {
    final isLocked = await AuthService().isFolderSelectionLocked();
    if (isLocked) {
      if (mounted) {
        final verified = await _verifyPassword();
        if (!verified) return;
      }
    }

    if (!mounted) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.logout),
        content: Text(AppLocalizations.of(context)!.confirmLogout),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppLocalizations.of(context)!.logout),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await AuthService().logout();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  /// 显示默认清晰度选择对话框
  void _showResolutionDialog() {
    final navigator = Navigator.of(context);
    final current = SettingsService().defaultResolution;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(AppLocalizations.of(context)!.defaultResolution),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: SettingsService.resolutionMap.entries.map((entry) {
                final selected = entry.key == current;
                return ListTile(
                  title: Text(entry.value),
                  trailing: selected
                      ? const Icon(Icons.check, color: Colors.green)
                      : null,
                  selected: selected,
                  onTap: () async {
                    await SettingsService().setDefaultResolution(entry.key);
                    if (!mounted) return;
                    setState(() {});
                    navigator.pop();
                  },
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.of(context)!.cancel),
            ),
          ],
        );
      },
    );
  }

  /// 显示默认倍速选择对话框
  void _showSpeedDialog() {
    final navigator = Navigator.of(context);
    final current = SettingsService().defaultPlaybackSpeed;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(AppLocalizations.of(context)!.defaultPlaybackSpeed),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0].map((speed) {
                final selected = speed == current;
                return ListTile(
                  title: Text('${speed}x'),
                  trailing: selected
                      ? const Icon(Icons.check, color: Colors.green)
                      : null,
                  selected: selected,
                  onTap: () async {
                    await SettingsService().setDefaultPlaybackSpeed(speed);
                    if (!mounted) return;
                    setState(() {});
                    navigator.pop();
                  },
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.of(context)!.cancel),
            ),
          ],
        );
      },
    );
  }

  void _showLanguageDialog() {
    final navigator = Navigator.of(context);
    final current = SettingsService().localeCode;
    final options = <String?, String>{
      null: AppLocalizations.of(context)!.followSystem,
      'en': 'English',
      'zh': '中文',
    };

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(AppLocalizations.of(context)!.selectLanguage),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: options.entries.map((entry) {
                final selected = entry.key == current;
                return ListTile(
                  title: Text(entry.value),
                  trailing: selected
                      ? const Icon(Icons.check, color: Colors.green)
                      : null,
                  selected: selected,
                  onTap: () async {
                    await SettingsService().setLocale(entry.key);
                    if (!mounted) return;
                    setState(() {});
                    navigator.pop();
                  },
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.of(context)!.cancel),
            ),
          ],
        );
      },
    );
  }

  String _getLanguageName(String? code) {
    switch (code) {
      case 'en':
        return 'English';
      case 'zh':
        return '中文';
      default:
        return AppLocalizations.of(context)!.followSystem;
    }
  }
}
