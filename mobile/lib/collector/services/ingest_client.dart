import 'dart:convert';
import 'dart:io';

import '../models/collector_config.dart';
import '../models/tool_discovery.dart';
import '../security/sanitizer.dart';

/// HTTP client for document ingestion, device registration, and tool discovery reporting.
class IngestClient {
  final CollectorConfig config;
  final HttpClient _client;

  IngestClient(this.config) : _client = HttpClient() {
    _client.connectionTimeout = const Duration(seconds: 15);
    _client.idleTimeout = const Duration(seconds: 15);
    _client.maxConnectionsPerHost = 6;
    // Support self-signed or internal CA if necessary
    _client.badCertificateCallback = (cert, host, port) => true;
  }

  void close() {
    _client.close(force: true);
  }

  Map<String, String> get _authHeaders => {
        'X-Collector-Token': config.token,
        'X-Device-Id': config.deviceId,
        'X-Device-Name': config.deviceName,
        'X-Device-Platform': config.platform,
        'X-Collector-Version': 'dart-0.1.0',
      };

  /// Send device heartbeat and enroll for remote execution key
  Future<String?> sendHeartbeat() async {
    try {
      final uri = Uri.parse('${config.serverUrl}/api/ingest/heartbeat');
      final req = await _client.postUrl(uri).timeout(const Duration(seconds: 15));
      _authHeaders.forEach((k, v) => req.headers.set(k, v));
      req.headers.contentType = ContentType.json;

      final resp = await req.close().timeout(const Duration(seconds: 20));
      if (resp.statusCode == 200) {
        final body = await resp.transform(utf8.decoder).join().timeout(const Duration(seconds: 10));
        final map = jsonDecode(body) as Map<String, dynamic>;
        final key = map['remote_exec_key']?.toString();
        if (key != null && key.isNotEmpty) {
          await config.copyWith(remoteExecKey: key).save();
          return key;
        }
      } else {
        await resp.drain().timeout(const Duration(seconds: 5));
      }
    } catch (e) {
      stderr.writeln('[IngestClient] heartbeat failed: $e');
    }
    return config.remoteExecKey;
  }

  /// Report discovered tools and workspace projects to server
  Future<bool> reportDiscovery(Map<String, DiscoveredTool> tools) async {
    try {
      final uri = Uri.parse('${config.serverUrl}/api/ingest/discovery');
      final req = await _client.postUrl(uri).timeout(const Duration(seconds: 15));
      _authHeaders.forEach((k, v) => req.headers.set(k, v));
      req.headers.contentType = ContentType.json;

      final payload = {
        'device_id': config.deviceId,
        'device_name': config.deviceName,
        'platform': config.platform,
        'tools': tools.map((k, v) => MapEntry(k, v.toJson())),
      };

      req.write(jsonEncode(payload));
      final resp = await req.close().timeout(const Duration(seconds: 20));
      final isOk = resp.statusCode == 200;
      await resp.drain().timeout(const Duration(seconds: 5));
      return isOk;
    } catch (e) {
      stderr.writeln('[IngestClient] reportDiscovery failed: $e');
      return false;
    }
  }

  /// Ingest a single file or session chunk to the server
  Future<bool> ingestDocument({
    required String toolId,
    required String category,
    required String contentType,
    required String relativePath,
    required String content,
    required String contentHash,
    int offset = 0,
    String mode = 'full',
    Map<String, dynamic> metadata = const {},
  }) async {
    try {
      // Clean sensitive credentials before upload
      final sanitized = Sanitizer.sanitizeText(content).content;
      final bytes = utf8.encode(sanitized);

      final uri = Uri.parse('${config.serverUrl}/api/ingest/file');
      final req = await _client.postUrl(uri).timeout(const Duration(seconds: 15));
      _authHeaders.forEach((k, v) => req.headers.set(k, v));
      req.headers.contentType = ContentType.json;

      final payload = {
        'tool': toolId,
        'category': category,
        'content_type': contentType,
        'relative_path': relativePath,
        'content': sanitized,
        'hash': contentHash,
        'file_size': bytes.length,
        'mode': mode,
        'offset': offset,
        'metadata': metadata,
      };

      req.write(jsonEncode(payload));
      final resp = await req.close().timeout(const Duration(seconds: 30));
      if (resp.statusCode == 200 || resp.statusCode == 201) {
        // Crucial: always drain response so socket can be returned to pool
        await resp.drain().timeout(const Duration(seconds: 5));
        return true;
      } else {
        final errBody = await resp.transform(utf8.decoder).join().timeout(const Duration(seconds: 5));
        stderr.writeln('[IngestClient] ingestDocument ($relativePath) HTTP ${resp.statusCode}: $errBody');
        return false;
      }
    } catch (e) {
      stderr.writeln('[IngestClient] ingestDocument ($relativePath) failed: $e');
      return false;
    }
  }

  /// Poll control commands (resync, etc.)
  Future<List<Map<String, dynamic>>> pollCommands() async {
    try {
      final uri = Uri.parse('${config.serverUrl}/api/devices/commands');
      final req = await _client.getUrl(uri).timeout(const Duration(seconds: 15));
      _authHeaders.forEach((k, v) => req.headers.set(k, v));

      final resp = await req.close().timeout(const Duration(seconds: 20));
      if (resp.statusCode == 200) {
        final body = await resp.transform(utf8.decoder).join().timeout(const Duration(seconds: 10));
        final list = jsonDecode(body) as List;
        final commands = list.cast<Map<String, dynamic>>();

        // Ack commands
        for (final cmd in commands) {
          final id = cmd['id'];
          if (id != null) {
            _ackCommand(id);
          }
        }
        return commands;
      } else {
        await resp.drain().timeout(const Duration(seconds: 5));
      }
    } catch (_) {}
    return [];
  }

  Future<void> _ackCommand(dynamic id) async {
    try {
      final uri = Uri.parse('${config.serverUrl}/api/devices/commands/$id/ack');
      final req = await _client.postUrl(uri).timeout(const Duration(seconds: 10));
      _authHeaders.forEach((k, v) => req.headers.set(k, v));
      final resp = await req.close().timeout(const Duration(seconds: 10));
      await resp.drain().timeout(const Duration(seconds: 5));
    } catch (_) {}
  }
}
