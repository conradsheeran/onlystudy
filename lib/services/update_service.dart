import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:onlystudy/l10n/app_localizations.dart';
import 'settings_service.dart';

/// 应用更新检查服务
class UpdateService {
  static final UpdateService _instance = UpdateService._internal();
  factory UpdateService() => _instance;
  UpdateService._internal();

  /// 检查 GitHub Release 更新
  Future<void> checkUpdate(BuildContext context, {bool silent = false}) async {
    // 如果是静默检查且用户关闭了自动检查，则直接返回
    if (silent && !SettingsService().autoCheckUpdate) {
      return;
    }

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final dio = Dio();
      final response = await dio.get('https://api.github.com/repos/conradsheeran/onlystudy/releases/latest');
      
      if (response.statusCode == 200) {
        final data = response.data;
        final String tagName = data['tag_name'];
        final String htmlUrl = data['html_url'];
        // 移除版本号可能存在的前缀 'v'
        final latestVersion = tagName.startsWith('v') ? tagName.substring(1) : tagName;

        if (_isNewVersion(currentVersion, latestVersion)) {
          if (context.mounted) {
            _showUpdateDialog(context, latestVersion, htmlUrl);
          }
        } else if (!silent && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text(AppLocalizations.of(context)!.noUpdateAvailable)),
          );
        }
      }
    } catch (e) {
      if (!silent && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text(AppLocalizations.of(context)!.checkUpdateFailed)),
        );
      }
      debugPrint('Error checking update: $e');
    }
  }

  /// 简单的版本号比对逻辑 (x.y.z)
  bool _isNewVersion(String current, String latest) {
    try {
        final currentParts = current.split('.').map(int.parse).toList();
        final latestParts = latest.split('.').map(int.parse).toList();
        
        for (int i = 0; i < 3; i++) { // 比较 major, minor, patch
            final c = i < currentParts.length ? currentParts[i] : 0;
            final l = i < latestParts.length ? latestParts[i] : 0;
            if (l > c) return true;
            if (l < c) return false;
        }
        return false;
    } catch (e) {
        return false;
    }
  }

  /// 显示更新提示对话框
  void _showUpdateDialog(BuildContext context, String version, String url) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.checkUpdate),
        content: Text(AppLocalizations.of(context)!.newVersionAvailable(version)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
            },
            child: Text(AppLocalizations.of(context)!.update),
          ),
        ],
      ),
    );
  }
}
