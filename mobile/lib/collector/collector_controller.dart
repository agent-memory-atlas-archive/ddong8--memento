import 'dart:async';
import 'dart:io';

import 'discovery/tool_discovery_service.dart';
import 'models/collector_config.dart';
import 'models/tool_discovery.dart';
import 'services/file_watcher_service.dart';
import 'services/ingest_client.dart';
import 'services/profile_inject_service.dart';
import 'services/ws_task_client.dart';

class CollectorStatus {
  final bool isRunning;
  final bool isOnline;
  final String deviceName;
  final String deviceId;
  final String serverUrl;
  final Map<String, DiscoveredTool> tools;
  final List<String> recentLogs;

  const CollectorStatus({
    required this.isRunning,
    required this.isOnline,
    required this.deviceName,
    required this.deviceId,
    required this.serverUrl,
    required this.tools,
    required this.recentLogs,
  });

  CollectorStatus copyWith({
    bool? isRunning,
    bool? isOnline,
    String? deviceName,
    String? deviceId,
    String? serverUrl,
    Map<String, DiscoveredTool>? tools,
    List<String>? recentLogs,
  }) {
    return CollectorStatus(
      isRunning: isRunning ?? this.isRunning,
      isOnline: isOnline ?? this.isOnline,
      deviceName: deviceName ?? this.deviceName,
      deviceId: deviceId ?? this.deviceId,
      serverUrl: serverUrl ?? this.serverUrl,
      tools: tools ?? this.tools,
      recentLogs: recentLogs ?? this.recentLogs,
    );
  }
}

/// Master controller coordinating Memento Collector lifecycle and status.
class CollectorController {
  CollectorConfig? _config;
  IngestClient? _ingestClient;
  WsTaskClient? _wsClient;
  FileWatcherService? _watcherService;
  Timer? _commandPollTimer;
  Timer? _profileSyncTimer;
  Map<String, String>? _lastProfileReport;
  bool _profileSyncing = false;

  bool _isRunning = false;
  bool _isOnline = false;
  Map<String, DiscoveredTool> _discoveredTools = {};
  final List<String> _logs = [];

  final _statusController = StreamController<CollectorStatus>.broadcast();
  Stream<CollectorStatus> get statusStream => _statusController.stream;

  CollectorStatus get currentStatus => CollectorStatus(
        isRunning: _isRunning,
        isOnline: _isOnline,
        deviceName: _config?.deviceName ?? Platform.localHostname,
        deviceId: _config?.deviceId ?? 'unknown',
        serverUrl: _config?.serverUrl ?? '',
        tools: _discoveredTools,
        recentLogs: List.unmodifiable(_logs),
      );

  void _notify() {
    if (!_statusController.isClosed) {
      _statusController.add(currentStatus);
    }
  }

  void _addLog(String msg) {
    final timeStr = DateTime.now().toIso8601String().substring(11, 19);
    final line = '[$timeStr] $msg';
    _logs.add(line);
    if (_logs.length > 200) {
      _logs.removeAt(0);
    }
    _notify();
  }

  /// Initialize and start the collector daemon
  Future<void> start({CollectorConfig? configOverride}) async {
    if (_isRunning) return;

    _addLog('Starting Memento Collector (Dart Engine)...');
    _config = configOverride ?? await CollectorConfig.load();
    _isRunning = true;
    _notify();

    // 1. Initialize Ingest Client
    _ingestClient = IngestClient(_config!, onLog: _addLog);

    // 2. Discover local AI tools
    _addLog('Discovering installed AI tools on ${_config!.deviceName}...');
    _discoveredTools = await ToolDiscoveryService.discoverAll();
    _addLog('Discovered ${_discoveredTools.length} tools: ${_discoveredTools.keys.join(", ")}');

    // 3. Register & Enroll heartbeat with server
    _addLog('Connecting to server ${_config!.serverUrl}...');
    final key = await _ingestClient!.sendHeartbeat();
    if (key != null && key.isNotEmpty) {
      _config = _config!.copyWith(remoteExecKey: key);
      try {
        await _config!.save();
      } catch (_) {}
      _addLog('Enrolled for remote execution (key verified)');
    }
    await _ingestClient!.reportDiscovery(_discoveredTools);

    // 4. Start File Watcher
    _watcherService = FileWatcherService(
      config: _config!,
      ingestClient: _ingestClient!,
      onLog: _addLog,
    );
    unawaited(_watcherService!.startWatching(_discoveredTools));

    // 5. Start WebSocket task streaming client
    _wsClient = WsTaskClient(
      config: _config!,
      onLog: _addLog,
      onConnectionStatus: (online) {
        _isOnline = online;
        _notify();
      },
    );
    unawaited(_wsClient!.start());

    // 6. Periodic HTTP command poll every 30s as secondary channel
    _commandPollTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      await _ingestClient?.pollCommands();
    });

    // 7. Resident profile: keep enabled tools' instruction files in step with
    //    the published profile, and clean up tools switched off in the app.
    unawaited(_syncProfile());
    _profileSyncTimer = Timer.periodic(profileSyncInterval, (_) => _syncProfile());

    _addLog('Memento Collector is running.');
  }

  Future<void> _syncProfile() async {
    final client = _ingestClient;
    if (client == null || _profileSyncing) return;
    _profileSyncing = true;
    try {
      final data = await client.fetchProfileInjection();
      if (data == null) return; // older server, or offline
      final version = data['version'] as int?;
      final results = await applyProfileInjection(
        version: version,
        block: data['block'] as String?,
        targets: ((data['targets'] as List?) ?? const []).map((e) => e.toString()).toList(),
      );
      results.forEach((tool, outcome) {
        if (outcome != 'unchanged') _addLog('Profile $tool: $outcome');
      });
      if (!_sameReport(results, _lastProfileReport)) {
        await client.reportProfileInjection(version, results);
        _lastProfileReport = results;
      }
    } catch (e) {
      _addLog('Profile sync skipped: $e');
    } finally {
      _profileSyncing = false;
    }
  }

  static bool _sameReport(Map<String, String> a, Map<String, String>? b) =>
      b != null && a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

  /// Stop the collector daemon
  void stop() {
    if (!_isRunning) return;
    _addLog('Stopping Memento Collector...');

    _commandPollTimer?.cancel();
    _commandPollTimer = null;
    _profileSyncTimer?.cancel();
    _profileSyncTimer = null;

    _watcherService?.dispose();
    _watcherService = null;

    _wsClient?.dispose();
    _wsClient = null;

    _ingestClient?.close();
    _ingestClient = null;

    _isRunning = false;
    _isOnline = false;
    _notify();
    _addLog('Collector stopped.');
  }

  void dispose() {
    stop();
    _statusController.close();
  }
}
