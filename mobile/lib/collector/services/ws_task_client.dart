import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/collector_config.dart';
import '../models/task_message.dart';

/// WebSocket client for real-time task streaming and execution between server and device.
class WsTaskClient {
  final CollectorConfig config;
  final void Function(String message)? onLog;
  final void Function(bool online)? onConnectionStatus;

  bool _disposed = false;
  WebSocket? _ws;
  Timer? _pingTimer;
  final Map<String, Process> _runningTasks = {};

  WsTaskClient({
    required this.config,
    this.onLog,
    this.onConnectionStatus,
  });

  void _log(String msg) {
    onLog?.call(msg);
    stdout.writeln('[WsTaskClient] $msg');
  }

  void dispose() {
    _disposed = true;
    _pingTimer?.cancel();
    _ws?.close();
    // Kill any active tasks
    for (final entry in _runningTasks.entries) {
      try {
        entry.value.kill(ProcessSignal.sigterm);
      } catch (_) {}
    }
    _runningTasks.clear();
  }

  /// Start persistent connection loop with automatic reconnect.
  Future<void> start() async {
    int backoffSeconds = 2;

    while (!_disposed) {
      try {
        onConnectionStatus?.call(false);
        final base = config.serverUrl
            .replaceFirst(RegExp(r'^http://'), 'ws://')
            .replaceFirst(RegExp(r'^https://'), 'wss://');
        final wsUri = Uri.parse('$base/api/tasks/ws/${config.deviceId}');

        _log('Connecting to WebSocket: $wsUri');

        final headers = <String, dynamic>{
          'x-collector-token': config.token,
          'x-device-id': config.deviceId,
          if (config.remoteExecKey != null) 'x-remote-exec-key': config.remoteExecKey!,
        };

        // Custom HttpClient to allow self-signed certs in dev
        final customClient = HttpClient()
          ..connectionTimeout = const Duration(seconds: 15)
          ..badCertificateCallback = (cert, host, port) => true;

        _ws = await WebSocket.connect(
          wsUri.toString(),
          headers: headers,
          customClient: customClient,
        );

        backoffSeconds = 2;
        _log('WebSocket transport connected, awaiting server handshake...');

        // Start 25-second periodic heartbeat ping to prevent idle timeouts & keep DB updated
        _startPingTimer();

        // Report agent capabilities
        _reportCapabilities();

        // Listen for incoming server frames
        await for (final raw in _ws!) {
          try {
            final data = jsonDecode(raw.toString()) as Map<String, dynamic>;
            final type = data['type']?.toString();

            if (type == 'connected') {
              onConnectionStatus?.call(true);
              _log('Handshake verified by server (${data['device_name']})');
            } else if (type == 'pong') {
              // Heartbeat ack from server
              continue;
            } else if (type == 'get_agent_capabilities') {
              _reportCapabilities();
            } else if (type == 'task_dispatch') {
              final taskJson = data['task'] as Map<String, dynamic>?;
              if (taskJson != null) {
                final task = TaskDispatch.fromJson(taskJson);
                _log('Received task dispatch: ${task.id} (${task.action})');
                // Run task in background so stream listening isn't blocked
                unawaited(_executeTask(task));
              }
            } else if (type == 'task_cancel') {
              final taskId = data['task_id']?.toString();
              if (taskId != null && _runningTasks.containsKey(taskId)) {
                _log('Cancelling task $taskId');
                final proc = _runningTasks.remove(taskId);
                try {
                  proc?.kill(ProcessSignal.sigterm);
                } catch (_) {}
              }
            }
          } catch (e) {
            _log('Error processing frame: $e');
          }
        }

        if (_ws?.closeCode != null) {
          _log('WebSocket closed by server (code: ${_ws?.closeCode}, reason: ${_ws?.closeReason})');
          if (_ws?.closeCode == 4003) {
            _log('Server authentication rejected (4003 unauthorized). Re-verifying credentials...');
            backoffSeconds = 5;
          }
        }
      } catch (e) {
        _log('WebSocket disconnected or failed: $e (reconnecting in ${backoffSeconds}s)');
      } finally {
        _pingTimer?.cancel();
        _ws = null;
        onConnectionStatus?.call(false);
      }

      if (_disposed) break;
      await Future.delayed(Duration(seconds: backoffSeconds));
      backoffSeconds = (backoffSeconds * 2).clamp(2, 30);
    }
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      if (_ws != null && _ws!.readyState == WebSocket.open) {
        try {
          _ws!.add(jsonEncode({'type': 'ping'}));
        } catch (_) {}
      }
    });
  }

  void _sendJson(Map<String, dynamic> data) {
    if (_ws != null && _ws!.readyState == WebSocket.open) {
      try {
        _ws!.add(jsonEncode(data));
      } catch (e) {
        _log('Failed to send frame: $e');
      }
    }
  }

  Future<void> _reportCapabilities() async {
    final caps = await _probeCapabilities();
    _sendJson({
      'type': 'agent_capabilities',
      'capabilities': caps,
    });
    _log('Reported agent capabilities: ${caps.keys.join(", ")}');
  }

  Future<Map<String, dynamic>> _probeCapabilities() async {
    final caps = <String, dynamic>{};

    // Check Claude Code
    final claudePath = await _findExecutable(['claude', 'claude-code']);
    if (claudePath != null) {
      final claudeInfo = {
        'available': true,
        'path': claudePath,
        'models': ['claude-3-5-sonnet-20241022', 'claude-3-7-sonnet-20250219', 'claude-3-5-haiku-20241022'],
        'supports_effort': true,
      };
      caps['claude'] = claudeInfo;
      caps['claude_code'] = claudeInfo;
    }

    // Check Codex
    final codexPath = await _findExecutable(['codex', 'codex-cli']);
    if (codexPath != null) {
      caps['codex'] = {
        'available': true,
        'path': codexPath,
        'models': ['gpt-4o', 'o3-mini', 'o1'],
        'supports_effort': true,
      };
    }

    // Check Antigravity (agy)
    final agyPath = await _findExecutable(['agy', 'antigravity']);
    if (agyPath != null) {
      caps['antigravity'] = {
        'available': true,
        'path': agyPath,
        'models': ['gemini-2.5-pro', 'gemini-2.5-flash'],
        'supports_effort': false,
      };
    }

    return caps;
  }

  Future<String?> _findExecutable(List<String> names) async {
    final pathSeparator = Platform.isWindows ? ';' : ':';
    final envPath = Platform.environment['PATH'] ?? '';
    final paths = envPath.split(pathSeparator);

    // Common extra search paths
    final home = CollectorConfig.homeDir;
    if (Platform.isMacOS) {
      paths.addAll([
        '/opt/homebrew/bin',
        '/usr/local/bin',
        '$home/.local/bin',
        '$home/.gemini/antigravity/bin',
      ]);
    } else if (Platform.isWindows) {
      paths.addAll([
        '$home\\AppData\\Local\\Programs',
        '$home\\AppData\\Roaming\\npm',
      ]);
    }

    for (final name in names) {
      final exeName = Platform.isWindows ? (name.endsWith('.exe') ? name : '$name.exe') : name;
      for (final dir in paths) {
        if (dir.isEmpty) continue;
        final file = File('$dir${Platform.pathSeparator}$exeName');
        if (await file.exists()) {
          return file.path;
        }
      }
    }
    return null;
  }

  Future<void> _executeTask(TaskDispatch task) async {
    final taskId = task.id;
    final action = task.action;
    final payload = task.payload;
    final cwd = payload['cwd']?.toString().trim();
    final workingDir = (cwd != null && cwd.isNotEmpty && await Directory(cwd).exists()) ? cwd : null;

    String exe = '';
    List<String> args = [];

    if (action == 'shell') {
      final command = payload['command']?.toString() ?? '';
      if (Platform.isWindows) {
        exe = 'powershell.exe';
        args = ['-NoProfile', '-NonInteractive', '-Command', command];
      } else {
        exe = await File('/bin/zsh').exists() ? '/bin/zsh' : '/bin/sh';
        args = ['-c', command];
      }
    } else {
      // action == 'agent'
      final binary = (payload['binary']?.toString() ?? 'claude').toLowerCase();
      final prompt = payload['prompt']?.toString() ?? '';
      final sessionId = payload['session_id']?.toString() ?? '';
      final model = payload['model']?.toString() ?? '';
      final effort = payload['effort']?.toString() ?? '';
      final sysAppend = payload['system_prompt_append']?.toString() ?? '';

      final resolvedExe = await _findExecutable([binary]);
      if (resolvedExe == null) {
        _sendJson(TaskFinished(
          taskId: taskId,
          status: 'failed',
          exitCode: 1,
          error: 'Agent CLI executable not found on device: $binary',
        ).toJson());
        return;
      }
      exe = resolvedExe;

      if (binary.contains('claude')) {
        args = ['-p'];
        if (sessionId.isNotEmpty) args.addAll(['-r', sessionId]);
        if (sysAppend.isNotEmpty) args.addAll(['--append-system-prompt', sysAppend]);
        args.addAll(['--output-format', 'text', '--dangerously-skip-permissions']);
        if (model.isNotEmpty) args.addAll(['--model', model]);
        args.add(prompt);
      } else if (binary.contains('codex')) {
        args = [
          'exec',
          sessionId.isNotEmpty ? 'resume' : 'new',
          '--dangerously-bypass-approvals-and-sandbox',
          '--skip-git-repo-check',
        ];
        if (effort.isNotEmpty) args.addAll(['-c', 'model_reasoning_effort="$effort"']);
        if (model.isNotEmpty) args.addAll(['-m', model]);
        if (sessionId.isNotEmpty) args.add(sessionId);
        args.add(prompt);
      } else {
        // agy / antigravity
        args = [];
        if (sessionId.isNotEmpty) args.addAll(['--resume', sessionId]);
        args.addAll(['--prompt', prompt]);
      }
    }

    _sendJson({
      'type': 'task_progress',
      'task_id': taskId,
      'status': 'running',
    });

    final stdoutBuf = StringBuffer();
    final stderrBuf = StringBuffer();
    Process? proc;

    try {
      proc = await Process.start(
        exe,
        args,
        workingDirectory: workingDir,
        runInShell: false,
      );
      // Close stdin immediately so CLI tools know no input is piped,
      // avoiding "Warning: no stdin data received in 3s, proceeding without it."
      await proc.stdin.close();
      _runningTasks[taskId] = proc;

      // Stream stdout chunks
      proc.stdout.transform(utf8.decoder).listen((chunk) {
        stdoutBuf.write(chunk);
        _sendJson(TaskChunk(
          taskId: taskId,
          stream: 'stdout',
          text: chunk,
        ).toJson());
      });

      // Stream stderr chunks
      proc.stderr.transform(utf8.decoder).listen((chunk) {
        stderrBuf.write(chunk);
        _sendJson(TaskChunk(
          taskId: taskId,
          stream: 'stderr',
          text: chunk,
        ).toJson());
      });

      // Wait for process completion or timeout
      final exitCode = await proc.exitCode.timeout(
        Duration(seconds: task.timeoutSeconds),
        onTimeout: () {
          proc?.kill(ProcessSignal.sigterm);
          return -999;
        },
      );

      final fullOut = stdoutBuf.toString().trim();
      final fullErr = stderrBuf.toString().trim();
      final isTimeout = exitCode == -999;
      final isPromptTooLong = fullErr.contains('Prompt is too long') || fullOut.contains('Prompt is too long');

      final status = isTimeout
          ? 'timeout'
          : (exitCode == 0 ? 'succeeded' : 'failed');

      final errorMsg = isTimeout
          ? 'Task timed out after ${task.timeoutSeconds}s'
          : (exitCode != 0 ? (fullErr.isNotEmpty ? fullErr : 'Exit code $exitCode') : null);

      _sendJson(TaskFinished(
        taskId: taskId,
        status: status,
        exitCode: exitCode,
        stdout: fullOut,
        stderr: fullErr,
        error: errorMsg,
        errorType: isPromptTooLong ? 'prompt_too_long' : null,
      ).toJson());
    } catch (e) {
      _sendJson(TaskFinished(
        taskId: taskId,
        status: 'failed',
        exitCode: 1,
        error: 'Execution failed to start: $e',
      ).toJson());
    } finally {
      _runningTasks.remove(taskId);
    }
  }
}
