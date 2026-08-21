import 'package:flutter_test/flutter_test.dart';
import 'package:onlystudy/services/update_checker.dart';

void main() {
  group('UpdateChecker version parsing', () {
    test('normalizes version prefixes', () {
      expect(UpdateChecker.normalizeVersion('v0.7.0-alpha'), '0.7.0-alpha');
      expect(UpdateChecker.normalizeVersion('V1.2.3'), '1.2.3');
    });

    test('detects newer semantic versions', () {
      expect(UpdateChecker.isNewVersion('0.6.9', 'v0.7.0'), isTrue);
      expect(UpdateChecker.isNewVersion('0.7.0', 'v0.7.1'), isTrue);
      expect(UpdateChecker.isNewVersion('1.2.3', '1.2.3'), isFalse);
      expect(UpdateChecker.isNewVersion('1.2.4', '1.2.3'), isFalse);
    });

    test('ignores prerelease suffix when comparing versions', () {
      expect(UpdateChecker.isNewVersion('0.6.9', 'v0.7.0-alpha'), isTrue);
      expect(UpdateChecker.isNewVersion('0.7.0', 'v0.7.0-alpha'), isFalse);
    });

    test('returns false for invalid versions', () {
      expect(UpdateChecker.isNewVersion('0.7.0', 'latest'), isFalse);
      expect(UpdateChecker.isNewVersion('dev', 'v0.8.0'), isFalse);
    });

    test('extracts only content under release notes heading', () {
      const body = '''### 更新日志：

- 初步实现后台播放功能 #1

> 目前还有些许 Bug，不过基本能用，后续再慢慢修吧

### 我该下载哪个安装包？

- 安卓手机通常来说使用 app-arm64-v8a-release.apk
''';

      expect(UpdateChecker.extractReleaseNotes(body), '- 初步实现后台播放功能 #1');
    });

    test('falls back to full body when release notes heading is missing', () {
      const body = '没有标题的更新内容';
      expect(UpdateChecker.extractReleaseNotes(body), isEmpty);
    });

    test('keeps ordered and unordered list items only', () {
      const body = '''### 更新日志

1. 第一项
2. 第二项

补充说明

- 第三项
''';

      expect(
        UpdateChecker.extractReleaseNotes(body),
        '1. 第一项\n2. 第二项\n\n- 第三项',
      );
    });
  });

  group('UpdateChecker.parseReleaseResponse', () {
    test('parses tag, url and notes from GitHub release payload', () {
      final release = UpdateChecker.parseReleaseResponse({
        'tag_name': 'v0.8.1',
        'html_url':
            'https://github.com/conradsheeran/onlystudy/releases/tag/v0.8.1',
        'body': '### 更新日志\n\n- 修复登录问题',
      });

      expect(release, isNotNull);
      expect(release!.version, '0.8.1');
      expect(
        release.url,
        'https://github.com/conradsheeran/onlystudy/releases/tag/v0.8.1',
      );
      expect(release.notes, '- 修复登录问题');
    });

    test('returns null when tag or url is missing', () {
      expect(
        UpdateChecker.parseReleaseResponse({'tag_name': 'v0.8.1'}),
        isNull,
      );
      expect(
        UpdateChecker.parseReleaseResponse({'html_url': 'https://x'}),
        isNull,
      );
    });

    test('returns null when payload is not a map', () {
      expect(UpdateChecker.parseReleaseResponse(null), isNull);
      expect(UpdateChecker.parseReleaseResponse('oops'), isNull);
    });
  });

  group('UpdateChecker.check', () {
    test('returns UpdateAvailable when a newer release exists', () async {
      final checker = UpdateChecker(
        currentVersion: '0.7.0',
        fetchRelease: () async => const ReleaseInfo(
          version: '0.8.0',
          url: 'https://github.com/conradsheeran/onlystudy/releases',
          notes: '- 新功能',
        ),
      );

      final result = await checker.check();
      expect(result, isA<UpdateAvailable>());
      final available = result as UpdateAvailable;
      expect(available.release.version, '0.8.0');
    });

    test('returns UpToDate when current version equals latest', () async {
      final checker = UpdateChecker(
        currentVersion: '0.8.0',
        fetchRelease: () async => const ReleaseInfo(
          version: '0.8.0',
          url: 'https://github.com/conradsheeran/onlystudy/releases',
          notes: '',
        ),
      );

      expect(await checker.check(), isA<UpToDate>());
    });

    test('returns UpToDate when current version is newer', () async {
      final checker = UpdateChecker(
        currentVersion: '0.9.0',
        fetchRelease: () async => const ReleaseInfo(
          version: '0.8.0',
          url: 'https://github.com/conradsheeran/onlystudy/releases',
          notes: '',
        ),
      );

      expect(await checker.check(), isA<UpToDate>());
    });

    test('returns UpdateCheckFailed when fetch returns null', () async {
      final checker = UpdateChecker(
        currentVersion: '0.7.0',
        fetchRelease: () async => null,
      );

      expect(await checker.check(), isA<UpdateCheckFailed>());
    });

    test('returns UpdateCheckFailed when fetch throws', () async {
      final checker = UpdateChecker(
        currentVersion: '0.7.0',
        fetchRelease: () async => throw Exception('network down'),
      );

      expect(await checker.check(), isA<UpdateCheckFailed>());
    });

    test('returns UpdateCheckFailed when current version is invalid', () async {
      final checker = UpdateChecker(
        currentVersion: 'dev',
        fetchRelease: () async => const ReleaseInfo(
          version: '0.8.0',
          url: 'https://github.com/conradsheeran/onlystudy/releases',
          notes: '',
        ),
      );

      expect(await checker.check(), isA<UpdateCheckFailed>());
    });
  });
}
