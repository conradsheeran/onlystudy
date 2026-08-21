import 'package:flutter/foundation.dart';

/// 更新检查的纯逻辑层（OPT-014）。
///
/// [UpdateChecker] 不接触 Widget/UI 上下文：只负责获取最新 release、
/// 与当前版本比较并返回结构化结果。界面展示由调用方（如 UpdateService）
/// 根据 [UpdateCheckResult] 决定。
class UpdateChecker {
  UpdateChecker({required this.currentVersion, required this.fetchRelease});

  /// 当前应用版本（由调用方提供，通常来自 PackageInfo）。
  final String currentVersion;

  /// 获取最新 release；返回 null 表示无可用 release（网络失败、非 200 等）。
  final Future<ReleaseInfo?> Function() fetchRelease;

  /// 执行一次更新检查，永不抛异常；网络/解析错误归入 [UpdateCheckFailed]。
  Future<UpdateCheckResult> check() async {
    final ReleaseInfo? release;
    try {
      release = await fetchRelease();
    } catch (_) {
      return const UpdateCheckFailed();
    }
    if (release == null) {
      return const UpdateCheckFailed();
    }
    // 任一版本号无法解析时视为检查失败，避免误导用户“已是最新版本”。
    if (_parseVersionParts(currentVersion) == null ||
        _parseVersionParts(release.version) == null) {
      return const UpdateCheckFailed();
    }
    if (_isNewVersion(currentVersion, release.version)) {
      return UpdateAvailable(release);
    }
    return const UpToDate();
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
    final nextHeadingMatch = RegExp(
      r'^###\s+',
      multiLine: true,
    ).firstMatch(remaining);
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

  /// 从 GitHub Releases API 响应解析 [ReleaseInfo]。
  ///
  /// 入参是 `dio.get(...).data` 的解码结果；无法识别时返回 null。
  static ReleaseInfo? parseReleaseResponse(Object? data) {
    if (data is! Map) {
      return null;
    }
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
}

/// 最新 release 信息。
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

/// 更新检查的结构化结果。
sealed class UpdateCheckResult {
  const UpdateCheckResult();
}

/// 发现新版本。
class UpdateAvailable extends UpdateCheckResult {
  const UpdateAvailable(this.release);

  final ReleaseInfo release;
}

/// 当前已是最新版本。
class UpToDate extends UpdateCheckResult {
  const UpToDate();
}

/// 检查失败（网络错误、无 release、版本解析失败等）。
class UpdateCheckFailed extends UpdateCheckResult {
  const UpdateCheckFailed();
}
