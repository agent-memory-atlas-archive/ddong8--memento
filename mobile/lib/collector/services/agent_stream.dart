import 'dart:convert';

/// Turns an agent CLI's JSONL stream into a few event kinds the server and the
/// task card understand:
///
///   {kind: session, session_id, model?}
///   {kind: text, text}                              what the agent says along the way
///   {kind: tool, id, name, detail, status, output?} status: running | done | failed
///   {kind: usage, cost_usd?, input_tokens?, output_tokens?, duration_ms?, turns?}
///   {kind: error, message}
///
/// Claude Code: `claude -p --output-format stream-json --verbose`.
/// Codex: `codex exec --json`.
abstract class AgentStreamParser {
  String? sessionId;

  /// The agent's final answer, once known.
  String? get finalText;

  /// Error text reported inside the stream (not on stderr), for retry decisions.
  final StringBuffer errors = StringBuffer();

  /// Events from one stdout line; empty for lines that carry nothing to show.
  /// Returns null when the line isn't JSON, so the caller can pass it through.
  List<Map<String, dynamic>>? feed(String line);

  static AgentStreamParser? forBinary(String binary) {
    final b = binary.toLowerCase();
    if (b.contains('claude')) return ClaudeStreamParser();
    if (b.contains('codex')) return CodexStreamParser();
    return null;
  }

  static Map<String, dynamic>? _decode(String line) {
    final text = line.trim();
    if (!text.startsWith('{')) return null;
    try {
      final value = jsonDecode(text);
      return value is Map<String, dynamic> ? value : null;
    } catch (_) {
      return null;
    }
  }
}

String _clip(String text, int max) {
  final t = text.trim();
  return t.length <= max ? t : '${t.substring(0, max)}…';
}

String _firstLine(String text) => text.trim().split('\n').first;

class ClaudeStreamParser extends AgentStreamParser {
  String? _result;
  final List<String> _texts = [];

  /// Set by the result event: user messages still waiting to be read. Zero
  /// means the run is done and stdin can be closed.
  int? queuedTurns;
  bool finished = false;

  @override
  String? get finalText => _result ?? (_texts.isEmpty ? null : _texts.join('\n\n'));

  @override
  List<Map<String, dynamic>>? feed(String line) {
    final d = AgentStreamParser._decode(line);
    if (d == null) return null;
    final events = <Map<String, dynamic>>[];
    switch (d['type']) {
      case 'system':
        if (d['subtype'] == 'init' && d['session_id'] != null) {
          sessionId = d['session_id'].toString();
          events.add({'kind': 'session', 'session_id': sessionId, if (d['model'] != null) 'model': d['model']});
        }
      case 'assistant':
        final content = (d['message'] as Map?)?['content'];
        if (content is List) {
          for (final block in content.whereType<Map>()) {
            if (block['type'] == 'text' && (block['text']?.toString().trim().isNotEmpty ?? false)) {
              final text = block['text'].toString();
              _texts.add(text);
              events.add({'kind': 'text', 'text': text});
            } else if (block['type'] == 'tool_use') {
              final input = (block['input'] as Map?)?.cast<String, dynamic>() ?? const {};
              events.add({
                'kind': 'tool',
                'id': block['id']?.toString(),
                'name': block['name']?.toString() ?? 'tool',
                'detail': claudeToolDetail(block['name']?.toString() ?? '', input),
                'status': 'running',
              });
            }
          }
        }
      case 'user':
        final content = (d['message'] as Map?)?['content'];
        if (content is List) {
          for (final block in content.whereType<Map>()) {
            if (block['type'] != 'tool_result') continue;
            events.add({
              'kind': 'tool',
              'id': block['tool_use_id']?.toString(),
              'status': block['is_error'] == true ? 'failed' : 'done',
              'output': _clip(_toolResultText(block['content']), 400),
            });
          }
        }
      case 'result':
        finished = true;
        queuedTurns = (d['queued_turn_count'] as num?)?.toInt() ?? 0;
        if (d['session_id'] != null) sessionId = d['session_id'].toString();
        if (d['result'] is String) _result = d['result'] as String;
        if (d['is_error'] == true) {
          final message = (d['result'] ?? d['subtype'] ?? 'error').toString();
          errors.writeln(message);
          events.add({'kind': 'error', 'message': _clip(message, 400)});
        }
        final usage = (d['usage'] as Map?) ?? const {};
        events.add({
          'kind': 'usage',
          if (d['total_cost_usd'] is num) 'cost_usd': d['total_cost_usd'],
          if (usage['input_tokens'] is num)
            'input_tokens': (usage['input_tokens'] as num) +
                ((usage['cache_read_input_tokens'] as num?) ?? 0) +
                ((usage['cache_creation_input_tokens'] as num?) ?? 0),
          if (usage['output_tokens'] is num) 'output_tokens': usage['output_tokens'],
          if (d['duration_ms'] is num) 'duration_ms': d['duration_ms'],
          if (d['num_turns'] is num) 'turns': d['num_turns'],
        });
    }
    return events;
  }

  static String _toolResultText(dynamic content) {
    if (content is String) return content;
    if (content is List) {
      return content
          .whereType<Map>()
          .where((b) => b['type'] == 'text')
          .map((b) => b['text']?.toString() ?? '')
          .join('\n');
    }
    return '';
  }
}

/// A one-line description of what a Claude Code tool call does.
String claudeToolDetail(String name, Map<String, dynamic> input) {
  String? pick(List<String> keys) {
    for (final k in keys) {
      final v = input[k];
      if (v is String && v.trim().isNotEmpty) return v;
    }
    return null;
  }

  final detail = switch (name) {
    'Bash' || 'BashOutput' => pick(['command', 'bash_id']),
    'Read' || 'Write' || 'Edit' || 'MultiEdit' || 'NotebookEdit' => pick(['file_path', 'notebook_path']),
    'Grep' => [pick(['pattern']), pick(['path'])].whereType<String>().join('  '),
    'Glob' => pick(['pattern']),
    'WebFetch' => pick(['url']),
    'WebSearch' => pick(['query']),
    'Task' || 'Agent' => pick(['description', 'prompt']),
    'TodoWrite' => input['todos'] is List ? '${(input['todos'] as List).length} 项待办' : null,
    _ => pick(['description', 'command', 'file_path', 'path', 'query', 'url', 'pattern', 'prompt']),
  };
  return _clip(_firstLine(detail ?? ''), 200);
}

class CodexStreamParser extends AgentStreamParser {
  String? _lastMessage;

  @override
  String? get finalText => _lastMessage;

  @override
  List<Map<String, dynamic>>? feed(String line) {
    final d = AgentStreamParser._decode(line);
    if (d == null) return null;
    final events = <Map<String, dynamic>>[];
    final item = (d['item'] as Map?)?.cast<String, dynamic>();
    switch (d['type']) {
      case 'thread.started':
        sessionId = d['thread_id']?.toString();
        if (sessionId != null) events.add({'kind': 'session', 'session_id': sessionId});
      case 'item.started' || 'item.updated' || 'item.completed':
        if (item == null) break;
        final done = d['type'] == 'item.completed';
        switch (item['type']) {
          case 'agent_message':
            if (done && (item['text']?.toString().trim().isNotEmpty ?? false)) {
              _lastMessage = item['text'].toString();
              events.add({'kind': 'text', 'text': _lastMessage});
            }
          case 'command_execution':
            final exit = (item['exit_code'] as num?)?.toInt();
            events.add({
              'kind': 'tool',
              'id': item['id']?.toString(),
              'name': 'Shell',
              'detail': _clip(_firstLine(codexCommand(item['command']?.toString() ?? '')), 200),
              'status': !done ? 'running' : (exit != null && exit != 0 ? 'failed' : 'done'),
              if (done) 'output': _clip(item['aggregated_output']?.toString() ?? '', 400),
            });
          case 'file_change':
            final changes = (item['changes'] as List?)?.whereType<Map>().toList() ?? const [];
            events.add({
              'kind': 'tool',
              'id': item['id']?.toString(),
              'name': 'Edit',
              'detail': _clip(changes.map((c) => c['path']?.toString() ?? '').where((p) => p.isNotEmpty).join(', '), 200),
              'status': !done ? 'running' : (item['status'] == 'failed' ? 'failed' : 'done'),
            });
          case 'mcp_tool_call':
            events.add({
              'kind': 'tool',
              'id': item['id']?.toString(),
              'name': [item['server'], item['tool']].whereType<Object>().join('.'),
              'detail': '',
              'status': !done ? 'running' : (item['status'] == 'failed' ? 'failed' : 'done'),
            });
          case 'web_search':
            events.add({
              'kind': 'tool',
              'id': item['id']?.toString(),
              'name': 'WebSearch',
              'detail': _clip(item['query']?.toString() ?? '', 200),
              'status': done ? 'done' : 'running',
            });
          case 'error':
            if (done) {
              final message = item['message']?.toString() ?? 'error';
              errors.writeln(message);
              events.add({'kind': 'error', 'message': _clip(message, 400)});
            }
        }
      case 'turn.completed':
        final usage = (d['usage'] as Map?) ?? const {};
        events.add({
          'kind': 'usage',
          if (usage['input_tokens'] is num) 'input_tokens': usage['input_tokens'],
          if (usage['output_tokens'] is num) 'output_tokens': usage['output_tokens'],
        });
      case 'turn.failed' || 'error':
        final message = ((d['error'] as Map?)?['message'] ?? d['message'] ?? 'error').toString();
        errors.writeln(message);
        events.add({'kind': 'error', 'message': _clip(message, 400)});
    }
    return events;
  }
}

/// "/bin/zsh -lc 'printf hi > a.txt'" -> "printf hi > a.txt".
String codexCommand(String raw) {
  var cmd = raw.trim().replaceFirst(RegExp(r'^(?:/\S*/)?(?:ba|z)?sh\s+-l?c\s+'), '');
  if (cmd.length >= 2 && ((cmd.startsWith("'") && cmd.endsWith("'")) || (cmd.startsWith('"') && cmd.endsWith('"')))) {
    cmd = cmd.substring(1, cmd.length - 1);
  }
  return cmd;
}

/// Tool events arrive as "running" and then again as "done"; the timeline keeps
/// one row per tool, updated in place. Other events are appended.
class AgentEventLog {
  final int limit;
  final List<Map<String, dynamic>> _events = [];
  final Map<String, int> _toolIndex = {};

  AgentEventLog({this.limit = 400});

  List<Map<String, dynamic>> get events => List.unmodifiable(_events);

  /// Adds or merges the event; returns the merged row (what to send live).
  Map<String, dynamic> add(Map<String, dynamic> event) {
    final id = event['kind'] == 'tool' ? event['id']?.toString() : null;
    if (id != null && _toolIndex.containsKey(id)) {
      final i = _toolIndex[id]!;
      _events[i] = {..._events[i], ...event};
      return _events[i];
    }
    final row = {...event, 'at': DateTime.now().toUtc().toIso8601String()};
    if (_events.length < limit) {
      if (id != null) _toolIndex[id] = _events.length;
      _events.add(row);
    }
    return row;
  }
}
