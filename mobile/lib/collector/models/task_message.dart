/// WebSocket protocol task messages between Memento server and collector.
class TaskDispatch {
  final String id;
  final String action; // "shell" or "agent"
  final Map<String, dynamic> payload;
  final int timeoutSeconds;

  const TaskDispatch({
    required this.id,
    required this.action,
    required this.payload,
    this.timeoutSeconds = 300,
  });

  factory TaskDispatch.fromJson(Map<String, dynamic> json) {
    final act = json['action']?.toString() ?? 'shell';
    final defaultTimeout = act == 'agent' ? 1800 : 300;
    return TaskDispatch(
      id: json['id']?.toString() ?? '',
      action: act,
      payload: (json['payload'] as Map?)?.cast<String, dynamic>() ?? {},
      timeoutSeconds: (json['timeout_seconds'] as int?) ?? defaultTimeout,
    );
  }
}

class TaskChunk {
  final String taskId;
  final String stream; // "stdout" or "stderr"
  final String text;

  const TaskChunk({
    required this.taskId,
    required this.stream,
    required this.text,
  });

  Map<String, dynamic> toJson() => {
        'type': 'task_chunk',
        'task_id': taskId,
        'stream': stream,
        'text': text,
      };
}

class TaskFinished {
  final String taskId;
  final String status; // "succeeded" | "failed" | "timeout"
  final int? exitCode;
  final String? stdout;
  final String? stderr;
  final String? error;
  final String? errorType; // e.g. "prompt_too_long"
  final String? sessionId;

  const TaskFinished({
    required this.taskId,
    required this.status,
    this.exitCode,
    this.stdout,
    this.stderr,
    this.error,
    this.errorType,
    this.sessionId,
  });

  Map<String, dynamic> toJson() => {
        'type': 'task_finished',
        'task_id': taskId,
        'status': status,
        if (exitCode != null) 'exit_code': exitCode,
        if (stdout != null) 'stdout': stdout,
        if (stderr != null) 'stderr': stderr,
        if (error != null) 'error': error,
        if (errorType != null) 'error_type': errorType,
        if (sessionId != null) 'session_id': sessionId,
      };
}
