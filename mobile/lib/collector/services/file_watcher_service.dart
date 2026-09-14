import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

import '../models/collector_config.dart';
import '../models/tool_discovery.dart';
import 'ingest_client.dart';

class _SyncTask {
  final String filePath;
  final String toolId;
  _SyncTask(this.filePath, this.toolId);
}

/// Service that watches local tool directories and syncs updated files to Memento server.
/// Supports multi-gigabyte log files via byte-offset incremental delta streaming.
class FileWatcherService {
  final CollectorConfig config;
  final IngestClient ingestClient;
  final void Function(String message)? onLog;

  static const int _maxBatchSize = 2 * 1024 * 1024; // 2 MB per batch upload
  static const int _maxLineLength = 512 * 1024;     // 512 KB per line max (truncate giant dumps)

  final List<StreamSubscription> _subscriptions = [];
  final Map<String, int> _lastModifiedCache = {};
  final Map<String, int> _offsets = {};
  final Map<String, Timer> _debounceTimers = {};
  final List<_SyncTask> _queue = [];
  final Set<String> _queuedFiles = {};
  Timer? _periodicScanTimer;
  bool _isProcessingQueue = false;
  bool _disposed = false;

  FileWatcherService({
    required this.config,
    required this.ingestClient,
    this.onLog,
  });

  String get _offsetsFilePath =>
      p.join(CollectorConfig.homeDir, '.memento', 'offsets.json');

  void _log(String msg) {
    onLog?.call(msg);
    stdout.writeln('[FileWatcher] $msg');
  }

  void dispose() {
    _disposed = true;
    _periodicScanTimer?.cancel();
    _periodicScanTimer = null;
    for (final timer in _debounceTimers.values) {
      timer.cancel();
    }
    _debounceTimers.clear();
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    _queue.clear();
    _queuedFiles.clear();
    _saveOffsets();
  }

  Future<void> _loadOffsets() async {
    try {
      final file = File(_offsetsFilePath);
      if (await file.exists()) {
        final jsonStr = await file.readAsString();
        final map = jsonDecode(jsonStr);
        if (map is Map) {
          _offsets.clear();
          map.forEach((k, v) {
            if (v is num) {
              _offsets[k.toString()] = v.toInt();
            }
          });
        }
      }
    } catch (e) {
      _log('Warning: could not load offsets: $e');
    }
  }

  Future<void> _saveOffsets() async {
    try {
      final file = File(_offsetsFilePath);
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(_offsets));
    } catch (_) {}
  }

  void _enqueue(String filePath, String toolId) {
    if (_disposed) return;
    if (_queuedFiles.contains(filePath)) return;
    _queuedFiles.add(filePath);
    _queue.add(_SyncTask(filePath, toolId));
    _processQueue();
  }

  Future<void> _processQueue() async {
    if (_isProcessingQueue || _disposed) return;
    _isProcessingQueue = true;
    try {
      while (_queue.isNotEmpty && !_disposed) {
        final task = _queue.removeAt(0);
        _queuedFiles.remove(task.filePath);
        await _syncFile(task.filePath, task.toolId);
        // Small delay between file tasks to keep connection pool and server happy
        if (_queue.isNotEmpty) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }
    } finally {
      _isProcessingQueue = false;
    }
  }

  /// Start watching tool session directories and extra configured directories
  Future<void> startWatching(Map<String, DiscoveredTool> tools) async {
    await _loadOffsets();

    final watchPaths = <String, String>{}; // path -> toolId

    for (final tool in tools.values) {
      if (tool.id == 'claude' || tool.id == 'claude_code') {
        final projDir = p.join(tool.root, 'projects');
        if (await Directory(projDir).exists()) {
          watchPaths[projDir] = 'claude_code';
        }
        final plansDir = p.join(tool.root, 'plans');
        if (await Directory(plansDir).exists()) {
          watchPaths[plansDir] = 'claude_code';
        }
      } else if (tool.id == 'codex') {
        final sessDir = p.join(tool.root, 'sessions');
        if (await Directory(sessDir).exists()) {
          watchPaths[sessDir] = 'codex';
        }
      } else if (tool.id == 'antigravity') {
        final brainDir = p.join(tool.root, 'brain');
        if (await Directory(brainDir).exists()) {
          watchPaths[brainDir] = 'antigravity';
        }
      } else if (tool.id == 'cursor') {
        final projDir = p.join(tool.root, 'projects');
        if (await Directory(projDir).exists()) {
          watchPaths[projDir] = 'cursor';
        }
      }
    }

    for (final dir in config.extraWatchDirs) {
      if (await Directory(dir).exists()) {
        watchPaths[dir] = 'obsidian';
      }
    }

    _log('Watching ${watchPaths.length} tool data directories');

    for (final entry in watchPaths.entries) {
      final dirPath = entry.key;
      final toolId = entry.value;
      _watchDirectory(dirPath, toolId);
      // Gentle background scan for initial or missed files
      unawaited(_initialScan(dirPath, toolId));
    }

    // Periodic light rescan every 60s to catch files that failed during temporary network glitches
    _periodicScanTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (_disposed) return;
      for (final entry in watchPaths.entries) {
        unawaited(_initialScan(entry.key, entry.value));
      }
    });
  }

  Future<void> _initialScan(String dirPath, String toolId) async {
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) return;

      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (_disposed) break;
        if (entity is File) {
          if (_isValidWatchedFile(entity.path, toolId)) {
            _enqueue(entity.path, toolId);
          }
        }
      }
    } catch (e) {
      _log('Initial scan note on $dirPath: $e');
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

  bool _isValidWatchedFile(String filePath, String toolId) {
    final normalized = filePath.replaceAll(r'\', '/');
    final fileName = p.basename(normalized);

    // Filter noise directories and temporary files
    if (normalized.contains('/.git/') ||
        normalized.contains('/node_modules/') ||
        normalized.contains('/build/') ||
        normalized.contains('/.dart_tool/') ||
        normalized.contains('/__pycache__/') ||
        normalized.contains('/.memento/') ||
        normalized.contains('/.system_generated/steps/') ||
        normalized.contains('/.system_generated/tasks/') ||
        fileName.startsWith('.') ||
        fileName.endsWith('.tmp') ||
        fileName.endsWith('.lock') ||
        fileName.startsWith('polling-lease-') ||
        fileName == 'output.txt' ||
        fileName == 'read.json') {
      return false;
    }

    // Tool-specific strict filtering
    if (toolId == 'antigravity') {
      // Only sync canonical transcripts (compact format)
      // Ignore transcript_full.jsonl which duplicates conversation with massive raw base64 images
      return fileName == 'transcript.jsonl';
    } else if (toolId == 'claude' || toolId == 'claude_code') {
      if (!fileName.endsWith('.jsonl') && !fileName.endsWith('.meta.json') && !fileName.endsWith('.md')) {
        return false;
      }
      if (fileName.contains('lease') || fileName.contains('storage') || fileName.contains('prefs')) {
        return false;
      }
      return true;
    } else if (toolId == 'codex') {
      return fileName.endsWith('.jsonl') || fileName.endsWith('.json');
    } else if (toolId == 'cursor') {
      return fileName.endsWith('.jsonl') || fileName.endsWith('.json');
    } else if (toolId == 'obsidian') {
      return fileName.endsWith('.md');
    } else {
      final ext = p.extension(fileName).toLowerCase();
      return {'.md', '.json', '.jsonl', '.txt'}.contains(ext);
    }
  }

  void _onFileEvent(String filePath, String toolId) {
    if (!_isValidWatchedFile(filePath, toolId)) return;

    // Debounce 2.0s
    _debounceTimers[filePath]?.cancel();
    _debounceTimers[filePath] = Timer(const Duration(milliseconds: 2000), () {
      _enqueue(filePath, toolId);
    });
  }

  String _getRelativePath(String filePath, String toolId) {
    final normalized = filePath.replaceAll(r'\', '/');
    if (toolId == 'antigravity') {
      final brainMatch = RegExp(r'/brain/([^/]+)/').firstMatch(normalized);
      if (brainMatch != null) {
        final cascadeId = brainMatch.group(1);
        return 'antigravity/brain/$cascadeId/transcript.jsonl';
      }
    } else if (toolId == 'claude' || toolId == 'claude_code') {
      final idx = normalized.indexOf('/projects/');
      if (idx != -1) {
        return normalized.substring(idx + 1);
      }
      final plansIdx = normalized.indexOf('/plans/');
      if (plansIdx != -1) {
        return normalized.substring(plansIdx + 1);
      }
    } else if (toolId == 'codex') {
      final idx = normalized.indexOf('/sessions/');
      if (idx != -1) {
        return normalized.substring(idx + 1);
      }
    } else if (toolId == 'obsidian') {
      for (final dir in config.extraWatchDirs) {
        final normDir = dir.replaceAll(r'\', '/');
        if (normalized.startsWith(normDir)) {
          return normalized.substring(normDir.length).replaceAll(RegExp(r'^/'), '');
        }
      }
    }
    return p.basename(filePath);
  }

  Future<void> _syncFile(String filePath, String toolId) async {
    final file = File(filePath);
    if (!await file.exists()) return;

    try {
      final relPath = _getRelativePath(filePath, toolId);
      final ext = p.extension(filePath).toLowerCase();

      if (ext == '.jsonl') {
        await _syncJsonlFile(file, filePath, toolId, relPath);
      } else {
        await _syncFullFile(file, filePath, toolId, relPath);
      }
    } catch (e) {
      _log('Error syncing file $filePath: $e');
    }
  }

  /// Incremental delta stream sync for JSONL logs (handles files of any size, up to multi-GB)
  Future<void> _syncJsonlFile(File file, String filePath, String toolId, String relPath) async {
    final stat = await file.stat();
    final fileSize = stat.size;
    int lastOffset = _offsets[filePath] ?? 0;

    // File was truncated or recreated
    if (fileSize < lastOffset) {
      _log('File shrunk ($fileSize < $lastOffset), resetting offset: $relPath');
      lastOffset = 0;
      _offsets[filePath] = 0;
    }

    if (fileSize == lastOffset) {
      return; // Up to date
    }

    final raf = await file.open(mode: FileMode.read);
    try {
      while (!_disposed) {
        final currentStat = await file.stat();
        final currentSize = currentStat.size;
        if (currentSize <= lastOffset) {
          break;
        }

        await raf.setPosition(lastOffset);
        final bytesToRead = (currentSize - lastOffset > _maxBatchSize)
            ? _maxBatchSize
            : (currentSize - lastOffset);

        final rawBytes = await raf.read(bytesToRead);
        if (rawBytes.isEmpty) break;

        // Ensure we end on a newline boundary if not at EOF
        int validLength = rawBytes.length;
        if (lastOffset + rawBytes.length < currentSize) {
          final lastNewline = rawBytes.lastIndexOf(10); // 0x0A = '\n'
          if (lastNewline != -1) {
            validLength = lastNewline + 1;
          }
        }

        final sliceBytes = (validLength == rawBytes.length)
            ? rawBytes
            : rawBytes.sublist(0, validLength);

        final rawContent = utf8.decode(sliceBytes, allowMalformed: true);
        if (rawContent.trim().isEmpty) {
          lastOffset += sliceBytes.length;
          _offsets[filePath] = lastOffset;
          continue;
        }

        // Process lines and truncate abnormally large lines (e.g. base64 dumps)
        final lines = rawContent.split('\n');
        final cleanLines = <String>[];
        for (var line in lines) {
          if (line.isEmpty) continue;
          if (line.length > _maxLineLength) {
            final head = line.substring(0, 256 * 1024);
            final tail = line.substring(line.length - 128 * 1024);
            line = '$head\n...[TRUNCATED: line exceeded 512KB limit]...\n$tail';
          }
          cleanLines.add(line);
        }

        if (cleanLines.isEmpty) {
          lastOffset += sliceBytes.length;
          _offsets[filePath] = lastOffset;
          continue;
        }

        final batchContent = cleanLines.join('\n');
        final batchHash = _hashString(batchContent);
        final mode = lastOffset > 0 ? 'delta' : 'full';

        final deltaDesc = (lastOffset > 0)
            ? 'delta: ${sliceBytes.length}B at offset $lastOffset'
            : 'initial: ${sliceBytes.length}B';
        _log('Syncing $relPath ($toolId) $deltaDesc (file size: ${currentSize}B)');

        bool ok = await ingestClient.ingestDocument(
          toolId: toolId,
          category: 'conversation',
          contentType: 'jsonl',
          relativePath: relPath,
          content: batchContent,
          contentHash: batchHash,
          offset: lastOffset,
          mode: mode,
          metadata: {
            'session_id': p.basenameWithoutExtension(filePath),
          },
        );

        if (!ok && !_disposed) {
          // Retry once after brief pause if handshake or socket glitched
          await Future.delayed(const Duration(milliseconds: 500));
          ok = await ingestClient.ingestDocument(
            toolId: toolId,
            category: 'conversation',
            contentType: 'jsonl',
            relativePath: relPath,
            content: batchContent,
            contentHash: batchHash,
            offset: lastOffset,
            mode: mode,
            metadata: {
              'session_id': p.basenameWithoutExtension(filePath),
            },
          );
        }

        if (ok) {
          lastOffset += sliceBytes.length;
          _offsets[filePath] = lastOffset;
          await _saveOffsets();
        } else {
          _log('Failed to ingest batch for $relPath at offset $lastOffset, will retry later');
          break;
        }

        // Yield to event loop if more batches remain
        if (lastOffset < currentSize) {
          await Future.delayed(const Duration(milliseconds: 50));
        } else {
          break;
        }
      }
    } finally {
      await raf.close();
    }
  }

  /// Full file sync for non-jsonl documents (notes, configurations)
  Future<void> _syncFullFile(File file, String filePath, String toolId, String relPath) async {
    final stat = await file.stat();
    final mtime = stat.modified.millisecondsSinceEpoch;
    final cachedMtime = _lastModifiedCache[filePath];

    if (cachedMtime != null && cachedMtime == mtime) {
      return; // Timestamp unchanged
    }

    if (stat.size > 20 * 1024 * 1024) {
      _log('Non-jsonl file exceeds 20MB limit, skipping: $filePath (${stat.size} bytes)');
      return;
    }

    final content = await file.readAsString();
    final contentHash = _hashString(content);
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
      mode: 'full',
      offset: 0,
    );

    if (ok) {
      _lastModifiedCache[filePath] = mtime;
    }
  }

  String _hashString(String s) {
    // Fast in-memory 32-bit hash
    int hash = 0;
    for (int i = 0; i < s.length; i++) {
      hash = (31 * hash + s.codeUnitAt(i)) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16);
  }
}
