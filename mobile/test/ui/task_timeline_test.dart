import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memento_mobile/models/ask_turn.dart';
import 'package:memento_mobile/ui/widgets/task_timeline.dart';

void main() {
  test('a tool step is updated in place, other events append', () {
    var events = <Map<String, dynamic>>[];
    events = mergeTaskEvent(events, {'kind': 'tool', 'id': 't1', 'name': 'Bash', 'detail': 'ls', 'status': 'running'});
    events = mergeTaskEvent(events, {'kind': 'steer', 'text': '顺便看 README', 'status': 'sent'});
    events = mergeTaskEvent(events, {'kind': 'tool', 'id': 't1', 'status': 'done', 'output': 'README.md'});
    expect(events.length, 2);
    expect(events.first['status'], 'done');
    expect(events.first['detail'], 'ls');
    expect(events.first['output'], 'README.md');
  });

  test('run summary counts steps, cost and time', () {
    expect(
      taskRunSummary([
        {'kind': 'tool', 'id': 'a'},
        {'kind': 'tool', 'id': 'b'},
        {'kind': 'usage', 'cost_usd': 0.1137, 'duration_ms': 124000},
      ]),
      '2 步 · \$0.11 · 2 分 4 秒',
    );
    expect(taskRunSummary([{'kind': 'tool'}, {'kind': 'usage', 'duration_ms': 3986}]), '1 步 · 4 秒');
  });

  test('tools read as what they do', () {
    expect(taskToolLook('Bash').$2, '运行命令');
    expect(taskToolLook('Shell').$2, '运行命令');
    expect(taskToolLook('Edit').$1, Icons.edit_note_rounded);
    expect(taskToolLook('mcp.search').$2, 'mcp.search');
  });

  test('events survive the JSON round trip of a saved conversation', () {
    final result = ToolCallResult.fromJson({
      'task_id': 't',
      'events': [
        {'kind': 'worktree', 'status': 'kept', 'branch': 'memento/abcd1234'},
      ],
    });
    expect(result.events.single['branch'], 'memento/abcd1234');
  });
}
