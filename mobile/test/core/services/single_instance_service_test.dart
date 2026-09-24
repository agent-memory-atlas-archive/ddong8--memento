import 'package:flutter_test/flutter_test.dart';
import 'package:memento_mobile/core/services/single_instance_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SingleInstanceService Tests', () {
    test('singleInstancePort is consistent and within valid user range', () {
      final port1 = SingleInstanceService.singleInstancePort;
      final port2 = SingleInstanceService.singleInstancePort;

      expect(port1, equals(port2));
      expect(port1, greaterThanOrEqualTo(45380));
      expect(port1, lessThan(45480));
    });

    test('Primary instance can acquire lock and secondary instance detects it', () async {
      // 1. Primary instance binds to the port
      final isPrimary = await SingleInstanceService.ensureSingleInstance();
      expect(isPrimary, isTrue);

      // 2. A simulated secondary instance attempts to bind to the same port
      // It should detect the collision, notify primary, and return false
      final isSecondary = await SingleInstanceService.ensureSingleInstance();
      expect(isSecondary, isFalse);

      // 3. Clean up by closing the server socket
      await SingleInstanceService.close();

      // 4. After closing, a new instance should be able to acquire lock again
      final canReacquire = await SingleInstanceService.ensureSingleInstance();
      expect(canReacquire, isTrue);

      await SingleInstanceService.close();
    });
  });
}
