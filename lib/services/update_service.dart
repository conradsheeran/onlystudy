import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:onlystudy/l10n/app_localizations.dart';
import 'settings_service.dart';

class ReleaseInfo {
  const ReleaseInfo({
    required this.version,
    required this.url,
    required this.notes,
  });

  final String version;
  final String url;
  final String notes;
}

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

      final releaseInfo = await _fetchLatestRelease();
      if (releaseInfo == null) {
        return;
      }

      if (_isNewVersion(currentVersion, releaseInfo.version)) {
        if (silent &&
            SettingsService().lastPromptedUpdateVersion ==
                releaseInfo.version) {
          return;
        }

        if (context.mounted) {
          if (silent) {
            SettingsService().setLastPromptedUpdateVersion(
              releaseInfo.version,
            );
          }
          _showUpdateDialog(context, currentVersion, releaseInfo);
        }
      } else if (!silent && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(AppLocalizations.of(context)!.noUpdateAvailable)),
        );
      }
    } catch (e) {
      if (!silent && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(AppLocalizations.of(context)!.checkUpdateFailed)),
        );
      }
      debugPrint('Error checking update: $e');
    }
  }

  Future<ReleaseInfo?> _fetchLatestRelease() async {
    final dio = Dio();
    final response = await dio.get(
      'https://api.github.com/repos/conradsheeran/onlystudy/releases/latest',
    );

    if (response.statusCode != 200) {
      return null;
    }

    final data = response.data;
    final tagName = data['tag_name'] as String?;
    final htmlUrl = data['html_url'] as String?;
    if (tagName == null || htmlUrl == null) {
      return null;
    }

    return ReleaseInfo(
      version: _normalizeVersion(tagName),
      url: htmlUrl,
      notes: _extractReleaseNotes((data['body'] as String?)?.trim() ?? ''),
    );
  }

  @visibleForTesting
  static String normalizeVersion(String version) => _normalizeVersion(version);

  static String _normalizeVersion(String version) {
    return version.trim().replaceFirst(RegExp(r'^[vV]'), '');
  }

  @visibleForTesting
  static bool isNewVersion(String current, String latest) {
    return _isNewVersion(current, latest);
  }

  /// 简单的版本号比对逻辑，忽略预发布后缀
  static bool _isNewVersion(String current, String latest) {
    final currentParts = _parseVersionParts(current);
    final latestParts = _parseVersionParts(latest);

    if (currentParts == null || latestParts == null) {
      return false;
    }

    final maxLength = currentParts.length > latestParts.length
        ? currentParts.length
        : latestParts.length;
    for (int i = 0; i < maxLength; i++) {
      final currentPart = i < currentParts.length ? currentParts[i] : 0;
      final latestPart = i < latestParts.length ? latestParts[i] : 0;
      if (latestPart > currentPart) {
        return true;
      }
      if (latestPart < currentPart) {
        return false;
      }
    }

    return false;
  }

  static List<int>? _parseVersionParts(String version) {
    final normalizedVersion = _normalizeVersion(version);
    final match = RegExp(r'^\d+(?:\.\d+)*').firstMatch(normalizedVersion);
    if (match == null) {
      return null;
    }

    try {
      return match.group(0)!.split('.').map(int.parse).toList();
    } catch (_) {
      return null;
    }
  }

  @visibleForTesting
  static String extractReleaseNotes(String body) => _extractReleaseNotes(body);

  static String _extractReleaseNotes(String body) {
    if (body.trim().isEmpty) {
      return '';
    }

    final headingMatch = RegExp(
      r'^###\s*更新日志\s*[:：]?\s*$',
      multiLine: true,
      caseSensitive: false,
    ).firstMatch(body);
    if (headingMatch == null) {
      return _keepOnlyListItems(body);
    }

    final sectionStart = headingMatch.end;
    final remaining = body.substring(sectionStart);
    final nextHeadingMatch =
        RegExp(r'^###\s+', multiLine: true).firstMatch(remaining);
    final section = nextHeadingMatch == null
        ? remaining
        : remaining.substring(0, nextHeadingMatch.start);

    return _keepOnlyListItems(section);
  }

  static String _keepOnlyListItems(String markdown) {
    final lines = markdown
        .split('\n')
        .map((line) => line.replaceAll(RegExp(r'\s+$'), ''))
        .toList();

    final keptLines = <String>[];
    var previousWasListItem = false;

    for (final line in lines) {
      final trimmed = line.trimLeft();
      final isListItem = RegExp(r'^([-*+]|\d+\.)\s+').hasMatch(trimmed);

      if (isListItem) {
        if (keptLines.isNotEmpty && !previousWasListItem) {
          keptLines.add('');
        }
        keptLines.add(trimmed);
        previousWasListItem = true;
        continue;
      }

      if (trimmed.isEmpty && previousWasListItem) {
        previousWasListItem = false;
      }
    }

    return keptLines.join('\n').trim();
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
