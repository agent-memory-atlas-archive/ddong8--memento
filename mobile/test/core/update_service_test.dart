import 'package:flutter_test/flutter_test.dart';
import 'package:memento_mobile/core/services/update_service.dart';

void main() {
  group('UpdateService Version Comparison Tests', () {
    test('isNewerVersion correctly compares semver', () {
      expect(UpdateService.isNewerVersion('1.0.1', '1.0.0'), isTrue);
      expect(UpdateService.isNewerVersion('1.1.0', '1.0.9'), isTrue);
      expect(UpdateService.isNewerVersion('2.0.0', '1.99.99'), isTrue);
      expect(UpdateService.isNewerVersion('1.0.0', '1.0.0'), isFalse);
      expect(UpdateService.isNewerVersion('0.9.9', '1.0.0'), isFalse);
      expect(UpdateService.isNewerVersion('v1.0.2', '1.0.1'), isTrue);
    });

    test('isNewerVersion handles different lengths', () {
      expect(UpdateService.isNewerVersion('1.0.0.1', '1.0.0'), isTrue);
      expect(UpdateService.isNewerVersion('1.0', '1.0.0'), isFalse);
      expect(UpdateService.isNewerVersion('1.1', '1.0.5'), isTrue);
      expect(UpdateService.isNewerVersion('', '1.0.0'), isFalse);
    });
  });
}
