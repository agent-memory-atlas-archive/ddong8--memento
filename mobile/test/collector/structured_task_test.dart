// End to end through the collector: a fake server dispatches a Claude task in a
// worktree, a fake `claude` replays a real stream-json run and pauses for a
// follow-up, and the collector's reports are checked.
//
// The fake binary is found on PATH, so run with its directory first, e.g.:
//   FAKE_AGENT_DIR=... PATH=$FAKE_AGENT_DIR:$PATH flutter test test/collector/structured_task_test.dart
// (tool/structured_task_test.sh does that). Skipped when FAKE_AGENT_DIR isn't set.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memento_mobile/collector/models/collector_config.dart';
import 'package:memento_mobile/collector/services/ws_task_client.dart';
import 'package:path/path.dart' as p;

void main() {
  final fakeDir = Platform.environment['FAKE_AGENT_DIR'];

  test('Claude task: steps, follow-up, worktree, final answer', () async {
    final repo = Directory.systemTemp.createTempSync('structured_repo');
    Future<void> git(List<String> args) async {
      final r = await Process.run('git', ['-c', 'user.email=t@t', '-c', 'user.name=t', ...args], workingDirectory: repo.path);
      expect(r.exitCode, 0, reason: r.stderr.toString());
    }

    File(p.join(repo.path, 'README.md')).writeAsStringSync('# repo\n');
    await git(['init', '-q']);
    await git(['add', '.']);
    await git(['commit', '-qm', 'init']);

    final received = <Map<String, dynamic>>[];
    final finished = Completer<Map<String, dynamic>>();
    const taskId = 'feedbeef-0000-4000-8000-000000000001';
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final ws = await WebSocketTransformer.upgrade(req);
      ws.add(jsonEncode({'type': 'connected', 'device_name': 'test'}));
      ws.add(jsonEncode({
        'type': 'task_dispatch',
        'task': {
          'id': taskId,
          'action': 'agent',
          'timeout_seconds': 60,
          'payload': {'binary': 'claude-fake-memento', 'prompt': '列一下文件', 'cwd': repo.path, 'worktree': true},
        },
      }));
      var steered = false;
      ws.listen((raw) {
        final msg = jsonDecode(raw as String) as Map<String, dynamic>;
        received.add(msg);
        final event = msg['event'] as Map?;
        if (!steered && msg['type'] == 'agent_event' && event?['kind'] == 'tool') {
          steered = true;
          ws.add(jsonEncode({'type': 'task_input', 'task_id': taskId, 'input': '顺便看看 README'}));
        }
        if (msg['type'] == 'task_finished' && !finished.isCompleted) finished.complete(msg);
      });
    });

    final client = WsTaskClient(
      config: CollectorConfig(
        serverUrl: 'http://127.0.0.1:${server.port}',
        token: 't',
        deviceId: 'dev',
        deviceName: 'test',
        platform: Platform.operatingSystem,
      ),
    );
    unawaited(client.start());
    final done = await finished.future.timeout(const Duration(seconds: 45));
    client.dispose();
    await server.close(force: true);

    final events = received.where((m) => m['type'] == 'agent_event').map((m) => (m['event'] as Map).cast<String, dynamic>()).toList();
    final tools = <String, Map<String, dynamic>>{};
    for (final e in events.where((e) => e['kind'] == 'tool')) {
      tools[e['id'] as String] = {...?tools[e['id']], ...e};
    }
    expect(tools.values.map((t) => '${t['name']}:${t['status']}'), ['Bash:done', 'Write:done']);
    expect(events.where((e) => e['kind'] == 'steer').single['status'], 'sent');
    final worktree = events.where((e) => e['kind'] == 'worktree').toList();
    expect(worktree.map((e) => e['status']), ['created', 'removed']);
    expect(events.any((e) => e['kind'] == 'usage'), isTrue);

    expect(done['status'], 'succeeded');
    expect(done['stdout'], 'DONE');
    expect(done['session_id'], '6f3d1184-787b-4878-a8f5-2f5ade4fb738');
    expect((done['events'] as List).length, greaterThanOrEqualTo(4));

    // The prompt and the follow-up both went in as stream-json user messages.
    final stdinLines = File(p.join(fakeDir!, 'claude_stdin.txt')).readAsLinesSync();
    final sent = stdinLines.map((l) => ((jsonDecode(l) as Map)['message'] as Map)['content']).toList();
    expect(sent, ['列一下文件', '顺便看看 README']);

    repo.deleteSync(recursive: true);
  }, skip: fakeDir == null || Platform.isWindows ? 'needs FAKE_AGENT_DIR on PATH (tool/structured_task_test.sh)' : false);
}
