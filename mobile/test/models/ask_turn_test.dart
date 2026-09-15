import 'package:flutter_test/flutter_test.dart';
import 'package:memento_mobile/models/ask_turn.dart';

void main() {
  group('ToolCallItem Status Resolution Tests', () {
    test('still_running status is correctly identified and NOT treated as success', () {
      final item = ToolCallItem(
        id: 'call-1',
        name: 'run_on_device',
        args: {'command': 'test', 'action': 'agent'},
        result: ToolCallResult(
          status: 'still_running',
          exitCode: null,
          note: '任务执行已超过 180s，设备端已尝试终止或仍在后台',
        ),
      );

      expect(item.isStillRunning, isTrue);
      expect(item.isSuccess, isFalse);
      expect(item.isRunning, isFalse);
      expect(item.result?.note, contains('仍在后台'));
    });

    test('succeeded status without exit code is success', () {
      final item = ToolCallItem(
        id: 'call-2',
        name: 'run_on_device',
        args: {},
        result: ToolCallResult(status: 'succeeded'),
      );

      expect(item.isStillRunning, isFalse);
      expect(item.isSuccess, isTrue);
      expect(item.isFailed, isFalse);
    });

    test('completed with exit code 0 is success', () {
      final item = ToolCallItem(
        id: 'call-3',
        name: 'run_on_device',
        args: {},
        result: ToolCallResult(status: 'completed', exitCode: 0),
      );

      expect(item.isStillRunning, isFalse);
      expect(item.isSuccess, isTrue);
      expect(item.isFailed, isFalse);
    });

    test('failed status or non-zero exit code is failed', () {
      final item = ToolCallItem(
        id: 'call-4',
        name: 'run_on_device',
        args: {},
        result: ToolCallResult(status: 'failed', exitCode: 1),
      );

      expect(item.isStillRunning, isFalse);
      expect(item.isSuccess, isFalse);
      expect(item.isFailed, isTrue);
    });

    test('null result or queued/running status is isRunning', () {
      final pending = ToolCallItem(id: 'call-5', name: 'run_on_device', args: {});
      expect(pending.isRunning, isTrue);
      expect(pending.isSuccess, isFalse);
      expect(pending.isStillRunning, isFalse);

      final queued = ToolCallItem(
        id: 'call-6',
        name: 'run_on_device',
        args: {},
        result: ToolCallResult(status: 'queued'),
      );
      expect(queued.isRunning, isTrue);
      expect(queued.isSuccess, isFalse);

      final running = ToolCallItem(
        id: 'call-7',
        name: 'run_on_device',
        args: {},
        result: ToolCallResult(status: 'running'),
      );
      expect(running.isRunning, isTrue);
      expect(running.isSuccess, isFalse);
    });
  });
}
