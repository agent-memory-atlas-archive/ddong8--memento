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

  group('AskTurn Multimodal and Attachments Tests', () {
    test('AskTurn parses images and attachments correctly', () {
      final json = {
        'role': 'user',
        'content': '请帮我看一下这张截图',
        'images': ['data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=='],
        'attachments': [
          {
            'id': 'att_123',
            'name': 'error.log',
            'type': 'file',
            'size': 1024,
            'text_content': 'Fatal error at line 42',
          }
        ],
      };

      final turn = AskTurn.fromJson(json);
      expect(turn.role, 'user');
      expect(turn.content, '请帮我看一下这张截图');
      expect(turn.images.length, 1);
      expect(turn.images.first, startsWith('data:image/png;base64,'));
      expect(turn.attachments.length, 1);
      expect(turn.attachments.first['name'], 'error.log');

      final serialized = turn.toJson();
      expect(serialized['images'], isNotEmpty);
      expect(serialized['attachments'], isNotEmpty);
    });
  });
}
