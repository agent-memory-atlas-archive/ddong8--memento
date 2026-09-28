import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memento_mobile/collector/services/agent_stream.dart';

List<Map<String, dynamic>> _run(AgentStreamParser parser, String fixture) {
  final events = <Map<String, dynamic>>[];
  for (final line in File('test/collector/fixtures/$fixture').readAsLinesSync()) {
    events.addAll(parser.feed(line) ?? const []);
  }
  return events;
}

void main() {
  group('Claude stream-json', () {
    test('tool calls, final answer, session and usage', () {
      final parser = ClaudeStreamParser();
      final events = _run(parser, 'claude_stream.jsonl');
      final log = AgentEventLog();
      for (final e in events.where((e) => e['kind'] != 'text')) {
        log.add(e);
      }
      final tools = log.events.where((e) => e['kind'] == 'tool').toList();
      expect(tools.map((t) => t['name']), ['Bash', 'Write']);
      expect(tools.first['detail'], 'ls');
      expect(tools.first['status'], 'done');
      expect(tools.first['output'], 'README.md');
      expect(tools.last['detail'], '/tmp/probe/hello.txt');
      expect(parser.finalText, 'DONE');
      expect(parser.sessionId, '6f3d1184-787b-4878-a8f5-2f5ade4fb738');
      expect(parser.finished, isTrue);
      expect(parser.queuedTurns, 0);
      final usage = events.firstWhere((e) => e['kind'] == 'usage');
      expect(usage['cost_usd'], greaterThan(0));
      expect(usage['turns'], 3);
    });

    test('a failed tool result is marked failed', () {
      final parser = ClaudeStreamParser();
      parser.feed('{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"false"}}]}}');
      final events = parser.feed(
          '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"Exit code 1","is_error":true}]}}')!;
      expect(events.single['status'], 'failed');
    });

    test('an error result is reported for retry decisions', () {
      final parser = ClaudeStreamParser();
      parser.feed('{"type":"result","subtype":"error_during_execution","is_error":true,"result":"No conversation found with session ID: x"}');
      expect(parser.errors.toString(), contains('No conversation found'));
    });

    test('non-JSON lines pass through', () {
      expect(ClaudeStreamParser().feed('plain text'), isNull);
    });
  });

  group('Codex exec --json', () {
    test('commands, final answer and thread id', () {
      final parser = CodexStreamParser();
      final events = _run(parser, 'codex_stream.jsonl');
      final log = AgentEventLog();
      for (final e in events.where((e) => e['kind'] != 'text')) {
        log.add(e);
      }
      final tools = log.events.where((e) => e['kind'] == 'tool').toList();
      expect(tools.map((t) => t['detail']), ['ls', 'printf hi > hello2.txt']);
      expect(tools.every((t) => t['status'] == 'done'), isTrue);
      expect(parser.finalText, 'DONE');
      expect(parser.sessionId, '01a0e88c-159e-74f2-9b90-68d0adee98a0');
      expect(events.last['kind'], 'usage');
    });

    test('a non-zero exit marks the command failed', () {
      final events = CodexStreamParser().feed(
          '{"type":"item.completed","item":{"id":"i","type":"command_execution","command":"bash -lc \\"exit 3\\"","aggregated_output":"","exit_code":3,"status":"failed"}}')!;
      expect(events.single['status'], 'failed');
      expect(events.single['detail'], 'exit 3');
    });

    test('file changes list their paths', () {
      final events = CodexStreamParser().feed(
          '{"type":"item.completed","item":{"id":"f","type":"file_change","changes":[{"path":"a.py","kind":"update"},{"path":"b.py","kind":"add"}],"status":"completed"}}')!;
      expect(events.single['name'], 'Edit');
      expect(events.single['detail'], 'a.py, b.py');
    });

    test('turn failures are errors', () {
      final parser = CodexStreamParser();
      parser.feed('{"type":"turn.failed","error":{"message":"thread not found"}}');
      expect(parser.errors.toString(), contains('thread not found'));
    });
  });

  test('tool details read like what the agent did', () {
    expect(claudeToolDetail('Grep', {'pattern': 'TODO', 'path': 'lib'}), 'TODO  lib');
    expect(claudeToolDetail('WebSearch', {'query': 'flutter webview'}), 'flutter webview');
    expect(claudeToolDetail('TodoWrite', {'todos': [1, 2, 3]}), '3 项待办');
    expect(claudeToolDetail('Bash', {'command': 'git status\ngit diff'}), 'git status');
    expect(codexCommand("/bin/zsh -lc 'git status'"), 'git status');
  });

  test('event log keeps one row per tool and caps its size', () {
    final log = AgentEventLog(limit: 2);
    log.add({'kind': 'tool', 'id': 'a', 'name': 'Bash', 'status': 'running'});
    log.add({'kind': 'tool', 'id': 'a', 'status': 'done'});
    log.add({'kind': 'usage', 'turns': 1});
    log.add({'kind': 'error', 'message': 'dropped'});
    expect(log.events.length, 2);
    expect(log.events.first['name'], 'Bash');
    expect(log.events.first['status'], 'done');
  });
}
