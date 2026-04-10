import 'package:flutter_test/flutter_test.dart';
import 'package:onlystudy/services/update_service.dart';

void main() {
  group('UpdateService version parsing', () {
    test('normalizes version prefixes', () {
      expect(UpdateService.normalizeVersion('v0.7.0-alpha'), '0.7.0-alpha');
      expect(UpdateService.normalizeVersion('V1.2.3'), '1.2.3');
    });

    test('detects newer semantic versions', () {
      expect(UpdateService.isNewVersion('0.6.9', 'v0.7.0'), isTrue);
      expect(UpdateService.isNewVersion('0.7.0', 'v0.7.1'), isTrue);
      expect(UpdateService.isNewVersion('1.2.3', '1.2.3'), isFalse);
      expect(UpdateService.isNewVersion('1.2.4', '1.2.3'), isFalse);
    });

    test('ignores prerelease suffix when comparing versions', () {
      expect(UpdateService.isNewVersion('0.6.9', 'v0.7.0-alpha'), isTrue);
      expect(UpdateService.isNewVersion('0.7.0', 'v0.7.0-alpha'), isFalse);
    });

    test('returns false for invalid versions', () {
      expect(UpdateService.isNewVersion('0.7.0', 'latest'), isFalse);
      expect(UpdateService.isNewVersion('dev', 'v0.8.0'), isFalse);
    });

    test('extracts only content under release notes heading', () {
      const body = '''### 更新日志：

- 初步实现后台播放功能 #1

> 目前还有些许 Bug，不过基本能用，后续再慢慢修吧

### 我该下载哪个安装包？

- 安卓手机通常来说使用 app-arm64-v8a-release.apk
''';

      expect(
        UpdateService.extractReleaseNotes(body),
        '- 初步实现后台播放功能 #1',
      );
    });

    test('falls back to full body when release notes heading is missing', () {
      const body = '没有标题的更新内容';
      expect(UpdateService.extractReleaseNotes(body), isEmpty);
    });

    test('keeps ordered and unordered list items only', () {
      const body = '''### 更新日志

1. 第一项
2. 第二项

补充说明

- 第三项
''';

      expect(
        UpdateService.extractReleaseNotes(body),
        '1. 第一项\n2. 第二项\n\n- 第三项',
      );
    });
  });
}
