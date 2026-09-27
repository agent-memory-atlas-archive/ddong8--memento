import 'package:flutter_test/flutter_test.dart';
import 'package:memento_mobile/ui/screens/health_screen.dart';

void main() {
  test('success rate counts fallback answers as answered', () {
    expect(healthSuccessPercent({'total': 10, 'ok': 6, 'fallback': 3, 'failed': 1}), 90);
    expect(healthSuccessPercent({'total': 3, 'ok': 2, 'fallback': 0, 'failed': 1}), 66);
  });

  test('no calls has no success rate', () => expect(healthSuccessPercent({'total': 0}), isNull));

  test('latency reads in seconds past one second', () {
    expect(healthLatency(null), '—');
    expect(healthLatency(850), '850 毫秒');
    expect(healthLatency(12340), '12.3 秒');
  });
}
