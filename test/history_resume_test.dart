import 'package:flutter_test/flutter_test.dart';
import 'package:onlystudy/services/history_service.dart';

void main() {
  // Exercise the public HistoryService resume seam.
  test('已看完或越界的进度不再作为起播位置', () {
    expect(HistoryService.resolveResumePosition(3600, 3600), 0);
    expect(HistoryService.resolveResumePosition(3597, 3600), 0);
    expect(HistoryService.resolveResumePosition(3601, 3600), 0);
    expect(HistoryService.resolveResumePosition(1800, 3600), 1800);
    expect(HistoryService.resolveResumePosition(0, 3600), 0);
    expect(HistoryService.resolveResumePosition(100, 0), 100);
  });
}
