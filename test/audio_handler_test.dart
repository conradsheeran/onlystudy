import 'package:flutter_test/flutter_test.dart';
import 'package:onlystudy/services/audio_handler.dart';

void main() {
  group('音频通知栏控制 label 本地化（OPT-017）', () {
    test('中文 locale 使用中文 label', () {
      final controls = buildTransportControls('zh');
      expect(controls.rewind.label, '后退10秒');
      expect(controls.forward.label, '快进10秒');
    });

    test('英文 locale 使用英文 label', () {
      final controls = buildTransportControls('en');
      expect(controls.rewind.label, 'Rewind 10 seconds');
      expect(controls.forward.label, 'Fast forward 10 seconds');
    });

    test('null locale 跟随系统（默认英文 fallback 不崩溃）', () {
      final controls = buildTransportControls(null);
      expect(controls.rewind.label, isNotEmpty);
      expect(controls.forward.label, isNotEmpty);
    });
  });
}
