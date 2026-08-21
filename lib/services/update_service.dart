import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:onlystudy/l10n/app_localizations.dart';
import 'settings_service.dart';
import 'update_checker.dart';

/// 应用更新检查的 UI 协调层（OPT-014）。
///
/// 网络请求与版本比较的纯逻辑在 [UpdateChecker]，本类只负责
/// 根据 [UpdateCheckResult] 显示 Dialog/SnackBar。
class UpdateService {
  static final UpdateService _instance = UpdateService._internal();
  factory UpdateService() => _instance;
  UpdateService._internal();

  /// 测试专用：替换 checker 工厂以注入 fake 结果。
  @visibleForTesting
  UpdateChecker Function()? checkerFactory;

  /// 默认的生产 fetch：请求 GitHub Releases API。
  static Future<ReleaseInfo?> _fetchLatestRelease() async {
    final dio = Dio();
    final response = await dio.get(
      'https://api.github.com/repos/conradsheeran/onlystudy/releases/latest',
    );

    if (response.statusCode != 200) {
      return null;
    }
    return UpdateChecker.parseReleaseResponse(response.data);
  }

  /// 检查更新并展示结果。
  ///
  /// [silent] 为 true 时仅在有新版本时弹窗，无更新/失败保持静默；
  /// 为 false 时（手动检查）无更新显示"已是最新版本"，失败显示错误。
  Future<void> checkUpdate(BuildContext context, {bool silent = false}) async {
    // 静默检查且用户关闭了自动检查，直接返回
    if (silent && !SettingsService().autoCheckUpdate) {
      return;
    }

    final packageInfo = await PackageInfo.fromPlatform();

    final checkerFactory =
        this.checkerFactory ??
        (() => UpdateChecker(
          currentVersion: packageInfo.version,
          fetchRelease: _fetchLatestRelease,
        ));
    final result = await checkerFactory().check();

    if (!context.mounted) {
      return;
    }

    switch (result) {
      case UpdateAvailable(:final release):
        if (silent &&
            SettingsService().lastPromptedUpdateVersion == release.version) {
          return;
        }
        if (silent) {
          await SettingsService().setLastPromptedUpdateVersion(release.version);
          if (!context.mounted) return;
        }
        _showUpdateDialog(context, packageInfo.version, release);
      case UpToDate():
        if (!silent) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.noUpdateAvailable),
            ),
          );
        }
      case UpdateCheckFailed():
        if (!silent) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.checkUpdateFailed),
            ),
          );
        }
    }
  }

  /// 显示更新提示对话框
  void _showUpdateDialog(
    BuildContext context,
    String currentVersion,
    ReleaseInfo releaseInfo,
  ) {
    final localizations = AppLocalizations.of(context)!;
    final notes = releaseInfo.notes.isEmpty
        ? localizations.noReleaseNotes
        : releaseInfo.notes;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(localizations.newVersionAvailable(releaseInfo.version)),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(localizations.currentVersion(currentVersion)),
                const SizedBox(height: 4),
                Text(localizations.latestVersion(releaseInfo.version)),
                const SizedBox(height: 16),
                Text(
                  localizations.releaseNotes,
                  style: Theme.of(dialogContext).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: SingleChildScrollView(
                    child: MarkdownBody(
                      data: notes,
                      selectable: true,
                      onTapLink: (text, href, title) {
                        if (href == null) {
                          return;
                        }
                        launchUrl(
                          Uri.parse(href),
                          mode: LaunchMode.externalApplication,
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(localizations.cancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              launchUrl(
                Uri.parse(releaseInfo.url),
                mode: LaunchMode.externalApplication,
              );
            },
            child: Text(localizations.update),
          ),
        ],
      ),
    );
  }
}
