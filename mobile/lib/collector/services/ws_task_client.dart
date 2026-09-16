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

  Future<void> _killTaskProcess(Process? proc) async {
    if (proc == null) return;
    try {
      if (Platform.isWindows) {
        // Recursively terminate entire process tree (node, python, git, powershell, etc.)
        final res = await Process.run('taskkill', ['/F', '/T', '/PID', proc.pid.toString()]);
        if (res.exitCode != 0) {
          proc.kill(ProcessSignal.sigkill);
        }
      } else {
        proc.kill(ProcessSignal.sigkill);
      }
    } catch (_) {
      try {
        proc.kill();
      } catch (_) {}
    }
  }

  void dispose() {
    _disposed = true;
    _pingTimer?.cancel();
    _ws?.close();
    // Kill any active tasks cleanly
    for (final entry in _runningTasks.entries) {
      _killTaskProcess(entry.value);
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
                unawaited(_killTaskProcess(proc));
              }
            } else if (type == 'task_input') {
              final taskId = data['task_id']?.toString();
              final input = data['input']?.toString();
              if (taskId != null && input != null && _runningTasks.containsKey(taskId)) {
                final proc = _runningTasks[taskId];
                if (proc != null) {
                  try {
                    proc.stdin.writeln(input);
                    unawaited(proc.stdin.flush());
                    _log('Forwarded input to task $taskId: $input');
                  } catch (e) {
                    _log('Failed to write input to task $taskId: $e');
                  }
                }
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

  static Map<String, String>? _cachedExecutionEnv;

  /// Sniff critical API keys from user shell configs (~/.zshrc, ~/.bash_profile, etc.)
  /// on macOS/Linux where GUI desktop apps lack interactive login environment.
  Future<Map<String, String>> _buildExecutionEnvironment() async {
    if (_cachedExecutionEnv != null) return _cachedExecutionEnv!;

    final env = Map<String, String>.from(Platform.environment);
    env['PYTHONUNBUFFERED'] = '1';

    if (Platform.isMacOS || Platform.isLinux) {
      final home = CollectorConfig.homeDir;
      final shellFiles = [
        '$home/.zshrc',
        '$home/.bash_profile',
        '$home/.bashrc',
        '$home/.profile',
      ];

      final targetKeys = {
        'DASHSCOPE_API_KEY',
        'OPENAI_API_KEY',
        'ANTHROPIC_API_KEY',
        'GEMINI_API_KEY',
        'DEEPSEEK_API_KEY',
        'OPENAI_BASE_URL',
        'CODEX_HOME',
        'CLAUDE_CONFIG_DIR',
      };

      for (final sf in shellFiles) {
        final f = File(sf);
        if (await f.exists()) {
          try {
            final lines = await f.readAsLines();
            for (final line in lines) {
              final trimmed = line.trim();
              if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
              var lineContent = trimmed;
              if (lineContent.startsWith('export ')) {
                lineContent = lineContent.substring(7).trim();
              }
              final eqIdx = lineContent.indexOf('=');
              if (eqIdx > 0) {
                final k = lineContent.substring(0, eqIdx).trim();
                var v = lineContent.substring(eqIdx + 1).trim();
                // Strip inline comments or semicolons
                if (v.contains(';')) {
                  v = v.substring(0, v.indexOf(';')).trim();
                }
                if ((v.startsWith('"') && v.endsWith('"')) ||
                    (v.startsWith("'") && v.endsWith("'"))) {
                  if (v.length >= 2) {
                    v = v.substring(1, v.length - 1).trim();
                  }
                }
                if (targetKeys.contains(k) && !env.containsKey(k) && v.isNotEmpty) {
                  env[k] = v;
                }
              }
            }
          } catch (_) {}
        }
      }
    } else if (Platform.isWindows) {
      final home = CollectorConfig.homeDir;
      final extraDirs = [
        '$home\\AppData\\Local\\agy\\bin',
        '$home\\AppData\\Local\\Programs\\Antigravity',
        '$home\\.gemini\\antigravity\\bin',
        '$home\\.antigravity\\bin',
        '$home\\.cargo\\bin',
        '$home\\go\\bin',
      ];
      final currentPath = env['PATH'] ?? '';
      final parts = currentPath.split(';');
      for (final ed in extraDirs) {
        if (!parts.any((p) => p.toLowerCase() == ed.toLowerCase()) && Directory(ed).existsSync()) {
          parts.insert(0, ed);
        }
      }
      env['PATH'] = parts.join(';');
    }

    _cachedExecutionEnv = env;
    return env;
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
        '/opt/homebrew/sbin',
        '/usr/local/bin',
        '/usr/local/sbin',
        '$home/.local/bin',
        '$home/.cargo/bin',
        '$home/go/bin',
        '$home/.gemini/antigravity/bin',
        '$home/.antigravity/antigravity/bin',
        '$home/.fnm/current/bin',
        '$home/.asdf/shims',
        '/Applications/ChatGPT.app/Contents/Resources',
        '/Applications/Antigravity.app/Contents/MacOS',
      ]);

      // Scan dynamic nvm / asdf node directories
      final nvmDir = Directory('$home/.nvm/versions/node');
      if (await nvmDir.exists()) {
        try {
          final entries = await nvmDir.list().toList();
          for (final entry in entries) {
            if (entry is Directory) {
              paths.add('${entry.path}/bin');
            }
          }
        } catch (_) {}
      }
    } else if (Platform.isWindows) {
      paths.addAll([
        '$home\\AppData\\Local\\agy\\bin',
        '$home\\AppData\\Local\\Programs\\Antigravity',
        '$home\\AppData\\Local\\Programs',
        '$home\\.gemini\\antigravity\\bin',
        '$home\\.antigravity\\bin',
        '$home\\AppData\\Roaming\\npm',
        'C:\\Program Files\\nodejs',
        '$home\\.local\\bin',
        '$home\\.cargo\\bin',
        '$home\\go\\bin',
      ]);
    }

    final extensions = Platform.isWindows ? ['.cmd', '.exe', '.bat', '.ps1', ''] : [''];

    for (final name in names) {
      for (final ext in extensions) {
        final targetName = name.toLowerCase().endsWith(ext.toLowerCase()) ? name : '$name$ext';
        for (final dir in paths) {
          if (dir.isEmpty) continue;
          final file = File('$dir${Platform.pathSeparator}$targetName');
          if (await file.exists()) {
            return file.path;
          }
        }
      }
    }
    return null;
  }

  Future<String?> _resolveWorkingDir(String? rawCwd, Map<String, dynamic> payload) async {
    String? candidate = rawCwd?.trim();
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];

    if (candidate != null && candidate.isNotEmpty) {
      if (candidate.startsWith('~') && home != null) {
        candidate = candidate.replaceFirst('~', home);
      }
      try {
        if (await Directory(candidate).exists()) {
          return candidate;
        }
      } catch (_) {}
    }

    // Candidate does not exist directly on this machine (e.g. cross-platform Windows path on Mac or vice versa)
    String? projectName;
    if (rawCwd != null && rawCwd.isNotEmpty) {
      final clean = rawCwd.replaceAll(r'\', '/').replaceAll(RegExp(r'/+$'), '');
      final parts = clean.split('/');
      if (parts.isNotEmpty && parts.last.isNotEmpty) {
        projectName = parts.last;
      }
    }

    if (projectName != null && projectName.isNotEmpty && home != null) {
      final probePaths = [
        '$home/$projectName',
        '$home/dev/$projectName',
        '$home/Projects/$projectName',
        '$home/Documents/$projectName',
        '$home/Workspace/$projectName',
        '$home/Desktop/$projectName',
        '$home/code/$projectName',
        '$home/src/$projectName',
      ];
      if (Platform.isWindows) {
        probePaths.addAll([
          'D:/dev/$projectName',
          'D:/Projects/$projectName',
          'E:/dev/$projectName',
          'C:/dev/$projectName',
        ]);
      }
      for (final p in probePaths) {
        try {
          if (await Directory(p).exists()) {
            _log('Auto-aligned CWD to local directory: $p');
            return p;
          }
        } catch (_) {}
      }
    }

    // Safety fallback: User home directory (NEVER fall back to root "/" on macOS/Linux)
    if (home != null) {
      try {
        if (await Directory(home).exists()) {
          _log('CWD fallback to user home directory: $home');
          return home;
        }
      } catch (_) {}
    }

    return null;
  }

  Future<void> _executeTask(TaskDispatch task) async {
    final taskId = task.id;
    final action = task.action;
    final payload = task.payload;
    final cwd = payload['cwd']?.toString().trim();
    final workingDir = await _resolveWorkingDir(cwd, payload);

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

      final candidates = <String>[binary];
      if (binary == 'agy') candidates.add('antigravity');
      if (binary == 'antigravity') candidates.add('agy');

      final resolvedExe = await _findExecutable(candidates);
      if (resolvedExe == null) {
        String installTip = '';
        if (binary.contains('agy') || binary.contains('antigravity')) {
          installTip = Platform.isWindows
              ? '\n💡 Antigravity CLI 未安装，请在 PowerShell 中执行以下命令进行安装：\nirm https://antigravity.google/cli/install.ps1 | iex'
              : '\n💡 Antigravity CLI 未安装，请在终端中执行以下命令进行安装：\ncurl -fsSL https://antigravity.google/cli/install.sh | bash';
        } else if (binary.contains('claude')) {
          installTip = '\n💡 请运行 npm install -g @anthropic-ai/claude-code 安装 Claude Code CLI';
        } else if (binary.contains('codex')) {
          installTip = '\n💡 请运行 pip install openai-codex 或参考 Codex 官方文档安装 Codex CLI';
        }
        _sendJson(TaskFinished(
          taskId: taskId,
          status: 'failed',
          exitCode: 1,
          error: 'Agent CLI executable not found on device: $binary$installTip',
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
        args = ['exec'];
        final isFork = payload['fork'] == true;
        if (sessionId.isNotEmpty) {
          args.add(isFork ? 'fork' : 'resume');
        }
        args.addAll([
          '--dangerously-bypass-approvals-and-sandbox',
          '--skip-git-repo-check',
        ]);
        if (workingDir != null && workingDir.isNotEmpty) {
          args.addAll(['-C', workingDir]);
        }
        if (effort.isNotEmpty) args.addAll(['-c', 'model_reasoning_effort="$effort"']);
        if (model.isNotEmpty) args.addAll(['-m', model]);
        if (sessionId.isNotEmpty) args.add(sessionId);
        args.add(prompt);
      } else {
        // agy / antigravity
        args = [
          '--prompt', prompt,
          '--dangerously-skip-permissions',
        ];
        if (sessionId.isNotEmpty) {
          args.addAll(['--conversation', sessionId]);
        }
        if (model.isNotEmpty) {
          args.addAll(['--model', model]);
        }
        if (effort.isNotEmpty) {
          args.addAll(['--effort', effort]);
        }
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
      final useShell = Platform.isWindows &&
          (exe.toLowerCase().endsWith('.cmd') || exe.toLowerCase().endsWith('.bat'));
      final executionEnv = await _buildExecutionEnvironment();
      proc = await Process.start(
        exe,
        args,
        workingDirectory: workingDir,
        environment: executionEnv,
        runInShell: useShell,
      );
      _runningTasks[taskId] = proc;
      if (action != 'shell') {
        try {
          await proc.stdin.close();
        } catch (_) {}
      }

      const decoder = Utf8Decoder(allowMalformed: true);

      // Stream stdout chunks
      proc.stdout.transform(decoder).listen((chunk) {
        stdoutBuf.write(chunk);
        _sendJson(TaskChunk(
          taskId: taskId,
          stream: 'stdout',
          text: chunk,
        ).toJson());
      });

      // Stream stderr chunks
      proc.stderr.transform(decoder).listen((chunk) {
        stderrBuf.write(chunk);
        _sendJson(TaskChunk(
          taskId: taskId,
          stream: 'stderr',
          text: chunk,
        ).toJson());
      });

      // Wait for process completion or timeout
      var exitCode = await proc.exitCode.timeout(
        Duration(seconds: task.timeoutSeconds),
        onTimeout: () {
          _killTaskProcess(proc);
          return -999;
        },
      );

      var fullOut = stdoutBuf.toString().trim();
      var fullErr = stderrBuf.toString().trim();

      // Reactive retry 1: if resume hit ChatGPT.app active writer lock on Mac, auto fork & retry
      if (exitCode != 0 &&
          action != 'shell' &&
          (payload['binary']?.toString() ?? '').toLowerCase().contains('codex') &&
          (payload['session_id']?.toString() ?? '').isNotEmpty &&
          payload['fork'] != true &&
          fullErr.contains('already has an active writer')) {
        const notice = '\n⚡ [自动重试] 该会话当前正被 ChatGPT 客户端占用锁定，已自动无缝切换为 Fork 分支模式重新执行（完整继承上下文记忆）...\n\n';
        stderrBuf.write(notice);
        _sendJson(TaskChunk(
          taskId: taskId,
          stream: 'stderr',
          text: notice,
        ).toJson());

        final sId = payload['session_id'].toString();
        final pText = payload['prompt']?.toString() ?? '';
        final mModel = payload['model']?.toString() ?? '';
        final mEffort = payload['effort']?.toString() ?? '';

        final retryArgs = [
          'exec',
          'fork',
          '--dangerously-bypass-approvals-and-sandbox',
          '--skip-git-repo-check',
        ];
        if (mEffort.isNotEmpty) retryArgs.addAll(['-c', 'model_reasoning_effort="$mEffort"']);
        if (mModel.isNotEmpty) retryArgs.addAll(['-m', mModel]);
        retryArgs.addAll([sId, pText]);

        final retryProc = await Process.start(
          exe,
          retryArgs,
          workingDirectory: workingDir,
          environment: executionEnv,
          runInShell: useShell,
        );
        await retryProc.stdin.close();
        _runningTasks[taskId] = retryProc;

        retryProc.stdout.transform(decoder).listen((chunk) {
          stdoutBuf.write(chunk);
          _sendJson(TaskChunk(taskId: taskId, stream: 'stdout', text: chunk).toJson());
        });
        retryProc.stderr.transform(decoder).listen((chunk) {
          stderrBuf.write(chunk);
          _sendJson(TaskChunk(taskId: taskId, stream: 'stderr', text: chunk).toJson());
        });

        exitCode = await retryProc.exitCode.timeout(
          Duration(seconds: task.timeoutSeconds),
          onTimeout: () {
            _killTaskProcess(retryProc);
            return -999;
          },
        );
        fullOut = stdoutBuf.toString().trim();
        fullErr = stderrBuf.toString().trim();
      }

      // Reactive retry 2: cross-device session missing or corrupted (no rollout found, session not found, etc.)
      final isSessionNotFound = fullErr.contains('no rollout found') ||
          fullErr.contains('thread not found') ||
          fullErr.contains('session not found') ||
          fullErr.contains('failed to resume') ||
          fullErr.contains('cannot resume') ||
          fullErr.contains('unable to resume') ||
          fullErr.contains('No conversation found') ||
          fullErr.contains('could not find session');

      if (exitCode != 0 &&
          action != 'shell' &&
          (payload['session_id']?.toString() ?? '').isNotEmpty &&
          isSessionNotFound) {
        const resetNotice = '\n⚡ [自动自愈] 本地未找到历史会话（跨设备远程调度常见），已自动重置为全新会话重新执行...\n\n';
        stderrBuf.write(resetNotice);
        _sendJson(TaskChunk(
          taskId: taskId,
          stream: 'stderr',
          text: resetNotice,
        ).toJson());

        final binary = (payload['binary']?.toString() ?? 'claude').toLowerCase();
        final pText = payload['prompt']?.toString() ?? '';
        final mModel = payload['model']?.toString() ?? '';
        final mEffort = payload['effort']?.toString() ?? '';
        final sysAppend = payload['system_prompt_append']?.toString() ?? '';

        List<String> freshArgs = [];
        if (binary.contains('claude')) {
          freshArgs = ['-p'];
          if (sysAppend.isNotEmpty) freshArgs.addAll(['--append-system-prompt', sysAppend]);
          freshArgs.addAll(['--output-format', 'text', '--dangerously-skip-permissions']);
          if (mModel.isNotEmpty) freshArgs.addAll(['--model', mModel]);
          freshArgs.add(pText);
        } else if (binary.contains('codex')) {
          freshArgs = [
            'exec',
            '--dangerously-bypass-approvals-and-sandbox',
            '--skip-git-repo-check',
          ];
          if (mEffort.isNotEmpty) freshArgs.addAll(['-c', 'model_reasoning_effort="$mEffort"']);
          if (mModel.isNotEmpty) freshArgs.addAll(['-m', mModel]);
          freshArgs.add(pText);
        } else {
          freshArgs = ['--prompt', pText];
        }

        final freshProc = await Process.start(
          exe,
          freshArgs,
          workingDirectory: workingDir,
          environment: executionEnv,
          runInShell: useShell,
        );
        try {
          await freshProc.stdin.close();
        } catch (_) {}
        _runningTasks[taskId] = freshProc;

        freshProc.stdout.transform(decoder).listen((chunk) {
          stdoutBuf.write(chunk);
          _sendJson(TaskChunk(taskId: taskId, stream: 'stdout', text: chunk).toJson());
        });
        freshProc.stderr.transform(decoder).listen((chunk) {
          stderrBuf.write(chunk);
          _sendJson(TaskChunk(taskId: taskId, stream: 'stderr', text: chunk).toJson());
        });

        exitCode = await freshProc.exitCode.timeout(
          Duration(seconds: task.timeoutSeconds),
          onTimeout: () {
            _killTaskProcess(freshProc);
            return -999;
          },
        );
        fullOut = stdoutBuf.toString().trim();
        fullErr = stderrBuf.toString().trim();
      }

      if (exitCode != 0 &&
          (fullErr.contains('Operation not permitted') || fullErr.contains('Permission denied')) &&
          Platform.isMacOS) {
        const hint = '\n💡 [权限提示] 检测到 macOS 磁盘访问受限。请在「系统设置 -> 隐私与安全性 -> 完全磁盘访问权限」中添加并开启 Memento.app。\n';
        stderrBuf.write(hint);
        _sendJson(TaskChunk(taskId: taskId, stream: 'stderr', text: hint).toJson());
        fullErr = stderrBuf.toString().trim();
      }

      final isTimeout = exitCode == -999;
      final isPromptTooLong = fullErr.contains('Prompt is too long') || fullOut.contains('Prompt is too long');

      final status = isTimeout
          ? 'timeout'
          : (exitCode == 0 ? 'succeeded' : 'failed');

      final errorMsg = isTimeout
          ? 'Task timed out after ${task.timeoutSeconds}s'
          : (exitCode != 0 ? (fullErr.isNotEmpty ? fullErr : 'Exit code $exitCode') : null);

      // Extract session ID from stdout / stderr
      String? extractedSessionId;
      final sidMatch = RegExp(r'session id:\s*([0-9a-fA-F-]+)', caseSensitive: false).firstMatch(fullOut) ??
          RegExp(r'session id:\s*([0-9a-fA-F-]+)', caseSensitive: false).firstMatch(fullErr) ??
          RegExp(r'thread[_-]id:\s*([0-9a-fA-F-]+)', caseSensitive: false).firstMatch(fullOut);
      if (sidMatch != null) {
        extractedSessionId = sidMatch.group(1);
      }
      final resolvedSessionId = extractedSessionId ??
          (payload['session_id']?.toString().isNotEmpty == true ? payload['session_id'].toString() : null);

      _sendJson(TaskFinished(
        taskId: taskId,
        status: status,
        exitCode: exitCode,
        stdout: fullOut,
        stderr: fullErr,
        error: errorMsg,
        errorType: isPromptTooLong ? 'prompt_too_long' : null,
        sessionId: resolvedSessionId,
      ).toJson());
    } catch (e) {
      _sendJson(TaskFinished(
        taskId: taskId,
        status: 'failed',
        exitCode: 1,
        error: 'Execution failed to start: $e',
      ).toJson());
    } finally {
      final active = _runningTasks.remove(taskId);
      try {
        active?.stdin.close();
      } catch (_) {}
    }
  }

  /// Open macOS System Settings directly to Full Disk Access (FDA) panel.
  static Future<bool> openMacFullDiskAccessPreferences() async {
    if (!Platform.isMacOS) return false;
    try {
      final res = await Process.run('open', [
        'x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles',
      ]);
      return res.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
