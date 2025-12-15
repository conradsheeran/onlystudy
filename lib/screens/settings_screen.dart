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
            subtitle: Text(SettingsService.resolutionMap[SettingsService().defaultResolution] ?? '720P'),
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
        title: const Text('解锁收藏夹修改'),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: const InputDecoration(hintText: '输入密码'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final isCorrect = await AuthService().checkFolderLockPassword(controller.text);
              if (!context.mounted) return;
              
              if (isCorrect) {
                 await AuthService().setFolderSelectionLocked(false);
                 if (context.mounted) {
                   Navigator.pop(context); // Close dialog
                   ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已解锁')),
                   );
                   Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const SelectFoldersScreen()),
                   );
                 }
              } else {
                 ScaffoldMessenger.of(context).showSnackBar(
                   const SnackBar(content: Text('密码错误')),
                 );
              }
            },
            child: const Text('解锁'),
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
        content: const Text('确定要清理所有缓存吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await CacheService().clearCache();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('缓存已清理')),
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
        title: const Text('验证密码'),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: const InputDecoration(hintText: '输入密码'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final isCorrect = await AuthService().checkFolderLockPassword(controller.text);
              if (context.mounted) {
                if (isCorrect) {
                  Navigator.pop(context, true);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('密码错误')),
                  );
                }
              }
            },
            child: const Text('确定'),
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
        content: const Text('确定要退出登录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('退出'),
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
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(AppLocalizations.of(context)!.defaultResolution),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: SettingsService.resolutionMap.entries.map((entry) {
                return RadioListTile<int>(
                  title: Text(entry.value),
                  value: entry.key,
                  groupValue: SettingsService().defaultResolution,
                  onChanged: (value) async {
                    if (value != null) {
                      await SettingsService().setDefaultResolution(value);
                      if (mounted) {
                        setState(() {});
                        Navigator.pop(context);
                      }
                    }
                  },
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  /// 显示默认倍速选择对话框
  void _showSpeedDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(AppLocalizations.of(context)!.defaultPlaybackSpeed),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0].map((speed) {
                return RadioListTile<double>(
                  title: Text('${speed}x'),
                  value: speed,
                  groupValue: SettingsService().defaultPlaybackSpeed,
                  onChanged: (value) async {
                    if (value != null) {
                      await SettingsService().setDefaultPlaybackSpeed(value);
                      if (mounted) {
                        setState(() {});
                        Navigator.pop(context);
                      }
                    }
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
}
