import 'package:flutter_test/flutter_test.dart';
import 'package:onlystudy/services/playback_completion_strategy.dart'
    show PlaybackCompletionStrategy;

void main() {
  test('每次打开只接受一次非加载期的完成事件', () {
    final strategy = PlaybackCompletionStrategy();

    expect(strategy.shouldHandle(completed: true, isLoading: true), isFalse);
    expect(strategy.shouldHandle(completed: true, isLoading: false), isTrue);
    expect(strategy.shouldHandle(completed: true, isLoading: false), isFalse);

    strategy.reset();
    expect(strategy.shouldHandle(completed: false, isLoading: false), isFalse);
    expect(strategy.shouldHandle(completed: true, isLoading: false), isTrue);
  });
}
