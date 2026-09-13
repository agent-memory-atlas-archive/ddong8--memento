import 'package:flutter_test/flutter_test.dart';
import '../../lib/collector/models/task_message.dart';

void main() {
  group('TaskMessage Tests', () {
    test('TaskDispatch parses json correctly', () {
      final json = {
        'id': 'task-1234',
        'action': 'shell',
        'payload': {
          'command': 'ls -la',
          'cwd': '/Users/test',
        },
        'timeout_seconds': 45,
      };

      final task = TaskDispatch.fromJson(json);
      expect(task.id, equals('task-1234'));
      expect(task.action, equals('shell'));
      expect(task.payload['command'], equals('ls -la'));
      expect(task.payload['cwd'], equals('/Users/test'));
      expect(task.timeoutSeconds, equals(45));
    });

    test('TaskChunk formats to JSON properly', () {
      const chunk = TaskChunk(
        taskId: 'task-1234',
        stream: 'stdout',
        text: 'hello world\n',
      );

      final json = chunk.toJson();
      expect(json['type'], equals('task_chunk'));
      expect(json['task_id'], equals('task-1234'));
      expect(json['stream'], equals('stdout'));
      expect(json['text'], equals('hello world\n'));
    });

    test('TaskFinished serializes properly with prompt_too_long', () {
      const finished = TaskFinished(
        taskId: 'task-5678',
        status: 'failed',
        exitCode: 1,
        stderr: 'Prompt is too long',
        error: 'Prompt is too long',
        errorType: 'prompt_too_long',
      );

      final json = finished.toJson();
      expect(json['type'], equals('task_finished'));
      expect(json['task_id'], equals('task-5678'));
      expect(json['status'], equals('failed'));
      expect(json['exit_code'], equals(1));
      expect(json['error_type'], equals('prompt_too_long'));
    });
  });
}
