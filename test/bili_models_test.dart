import 'package:flutter_test/flutter_test.dart';
import 'package:onlystudy/models/bili_models.dart';

void main() {
  group('Video 紧凑计数格式化（OPT-017：不硬编码中文单位）', () {
    Video makeVideo({int view = 0, int danmaku = 0}) => Video(
          bvid: 'BV1',
          title: 't',
          cover: 'https://example.com/c.jpg',
          duration: 60,
          upper: BiliUpper(mid: 1, name: 'UP1'),
          view: view,
          danmaku: danmaku,
          pubTimestamp: 1700000000,
        );

    test('中文 locale 输出万/亿', () {
      final v = makeVideo(view: 12345, danmaku: 123456789);
      expect(v.formattedViewCount('zh'), contains('万'));
      expect(v.formattedDanmakuCount('zh'), contains('亿'));
    });

    test('英文 locale 输出 K/M，不出现中文单位', () {
      final v = makeVideo(view: 12345, danmaku: 123456789);
      expect(v.formattedViewCount('en'), contains('K'));
      expect(v.formattedViewCount('en'), isNot(contains('万')));
      expect(v.formattedDanmakuCount('en'), contains('M'));
      expect(v.formattedDanmakuCount('en'), isNot(contains('亿')));
    });

    test('小数值不缩写', () {
      final v = makeVideo(view: 999, danmaku: 42);
      expect(v.formattedViewCount('zh'), '999');
      expect(v.formattedDanmakuCount('en'), '42');
    });
  });
}
