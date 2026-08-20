import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// OPT-017：中英文 ARB 文案 key 必须对齐，避免英文界面缺项。
void main() {
  const arbFiles = [
    'lib/l10n/app_zh.arb',
    'lib/l10n/app_en.arb',
  ];

  Map<String, dynamic> loadArb(String path) {
    final raw = File(path).readAsStringSync();
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Set<String> keys(Map<String, dynamic> arb) {
    return arb.keys.where((k) => !k.startsWith('@')).toSet();
  }

  test('中英文 ARB 拥有相同 key 集合', () {
    final maps = arbFiles.map(loadArb).toList();
    final keySets = maps.map(keys).toList();

    final zhOnly = keySets[0].difference(keySets[1]);
    final enOnly = keySets[1].difference(keySets[0]);

    expect(zhOnly, isEmpty, reason: 'app_zh.arb 包含但 app_en.arb 缺失的 key: $zhOnly');
    expect(enOnly, isEmpty, reason: 'app_en.arb 包含但 app_zh.arb 缺失的 key: $enOnly');
  });

  test('生成的 AppLocalizations 暴露的 getter 覆盖全部 ARB key', () {
    // 生成文件必须与 ARB 同步；此测试防止忘记 flutter gen-l10n
    final zh = loadArb(arbFiles[0]);
    final generated = File('lib/l10n/app_localizations.dart').readAsStringSync();

    for (final key in keys(zh)) {
      final hasGetter =
          generated.contains('String get $key;') ||
          generated.contains('String $key(');
      expect(
        hasGetter,
        isTrue,
        reason:
            '生成的 app_localizations.dart 缺少 getter: $key（请运行 flutter gen-l10n）',
      );
    }
  });
}
