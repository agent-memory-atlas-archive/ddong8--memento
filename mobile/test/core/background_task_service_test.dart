import 'package:flutter_test/flutter_test.dart';
import 'package:memento_mobile/core/background_task_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BackgroundTaskService Tests', () {
    test('begin and end can be called safely on host platform without exceptions', () async {
      await expectLater(BackgroundTaskService.begin(name: 'test_task'), completes);
      await expectLater(BackgroundTaskService.end(), completes);
    });

    test('multiple begin and end calls match without errors', () async {
      await BackgroundTaskService.begin(name: 'task_1');
      await BackgroundTaskService.begin(name: 'task_2');
      await BackgroundTaskService.end();
      await BackgroundTaskService.end();
    });

    test('excess end calls do not throw', () async {
      await BackgroundTaskService.end();
      await BackgroundTaskService.end();
    });
  });
}
