import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

import '../models/collector_config.dart';
import '../models/tool_discovery.dart';
import 'ingest_client.dart';

/// Service that watches local tool directories and syncs updated files to Memento server.
class FileWatcherService {
  final CollectorConfig config;
  final IngestClient ingestClient;
  final void Function(String message)? onLog;

  final List<StreamSubscription> _subscriptions = [];
  final Map<String, int> _lastModifiedCache = {};
  final Map<String, Timer> _debounceTimers = {};
  bool _disposed = false;

  FileWatcherService({
    required this.config,
    required this.ingestClient,
    this.onLog,
  });

  void _log(String msg) {
    onLog?.call(msg);
    stdout.writeln('[FileWatcher] $msg');
  }

  void dispose() {
    _disposed = true;
    for (final timer in _debounceTimers.values) {
      timer.cancel();
    }
    _debounceTimers.clear();
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
  }

  /// Start watching tool projects and extra configured directories
  Future<void> startWatching(Map<String, DiscoveredTool> tools) async {
    final watchPaths = <String, String>{}; // path -> toolId

    for (final tool in tools.values) {
      for (final proj in tool.projects) {
        if (proj.path.isNotEmpty) {
          watchPaths[proj.path] = tool.id;
        }
      }
      if (tool.id == 'claude') {
        final projDir = p.join(tool.root, 'projects');
        if (await Directory(projDir).exists()) {
          watchPaths[projDir] = 'claude';
        }
      } else if (tool.id == 'codex') {
        final sessDir = p.join(tool.root, 'sessions');
        if (await Directory(sessDir).exists()) {
          watchPaths[sessDir] = 'codex';
        }
      }
    }

    for (final dir in config.extraWatchDirs) {
      if (await Directory(dir).exists()) {
        watchPaths[dir] = 'custom';
      }
    }

    _log('Watching ${watchPaths.length} tool workspaces');

    for (final entry in watchPaths.entries) {
      final dirPath = entry.key;
      final toolId = entry.value;
      _watchDirectory(dirPath, toolId);
    }
  }

  void _watchDirectory(String dirPath, String toolId) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return;

    try {
      final sub = dir.watch(recursive: true).listen((event) {
        if (_disposed) return;
        final filePath = event.path;
        _onFileEvent(filePath, toolId);
      }, onError: (e) {
        _log('Watch error on $dirPath: $e');
      });

      _subscriptions.add(sub);
    } catch (e) {
      _log('Failed to watch $dirPath: $e');
    }
  }

  void _onFileEvent(String filePath, String toolId) {
    // Filter non-text / noise files
    final ext = p.extension(filePath).toLowerCase();
    final validExts = {'.md', '.json', '.jsonl', '.txt', '.toml'};
    if (!validExts.contains(ext)) return;

    // Ignore temporary, git, or lock files
    if (filePath.contains('.git') || filePath.contains('node_modules') || filePath.endsWith('.tmp')) {
      return;
    }

    // Debounce 1.5s
    _debounceTimers[filePath]?.cancel();
    _debounceTimers[filePath] = Timer(const Duration(milliseconds: 1500), () {
      _syncFile(filePath, toolId);
    });
  }

  Future<void> _syncFile(String filePath, String toolId) async {
    final file = File(filePath);
    if (!await file.exists()) return;

    try {
      final stat = await file.stat();
      final mtime = stat.modified.millisecondsSinceEpoch;
      final cachedMtime = _lastModifiedCache[filePath];

      if (cachedMtime != null && cachedMtime == mtime) {
        return; // File timestamp hasn't changed
      }

      // Limit initial file read to 10MB
      if (stat.size > 10 * 1024 * 1024) {
        _log('File too large, skipping: $filePath (${stat.size} bytes)');
        return;
      }

      final content = await file.readAsString();
      final contentHash = _hashString(content);

      final relPath = p.basename(filePath);
      final category = toolId == 'obsidian' ? 'notes' : 'conversation';
      final contentType = p.extension(filePath).replaceAll('.', '');

      _log('Syncing updated file: $relPath ($toolId)');
      final ok = await ingestClient.ingestDocument(
        toolId: toolId,
        category: category,
        contentType: contentType,
        relativePath: relPath,
        content: content,
        contentHash: contentHash,
      );

      if (ok) {
        _lastModifiedCache[filePath] = mtime;
      }
    } catch (e) {
      _log('Error syncing file $filePath: $e');
    }
  }

  String _hashString(String s) {
    // Fast in-memory hash
    int hash = 0;
    for (int i = 0; i < s.length; i++) {
      hash = (31 * hash + s.codeUnitAt(i)) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16);
  }
}
