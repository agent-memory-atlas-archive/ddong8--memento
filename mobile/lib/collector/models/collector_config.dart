import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

/// Configuration for Memento Collector.
/// Compatible with ~/.memento configuration and environment variables.
class CollectorConfig {
  final String serverUrl;
  final String token;
  final String deviceId;
  final String deviceName;
  final String platform;
  final String? remoteExecKey;
  final bool autoStart;
  final List<String> extraWatchDirs;

  CollectorConfig({
    required this.serverUrl,
    required this.token,
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    this.remoteExecKey,
    this.autoStart = true,
    this.extraWatchDirs = const [],
  });

  /// Get home directory across platforms
  static String get homeDir {
    final env = Platform.environment;
    if (Platform.isWindows) {
      return env['USERPROFILE'] ?? env['HOME'] ?? 'C:\\Users\\Default';
    }
    return env['HOME'] ?? '/';
  }

  /// Default memento config directory (~/.memento)
  static Directory get mementoDir => Directory(p.join(homeDir, '.memento'));

  /// Legacy Python config.json path (~/.memento/config.json)
  static File get legacyJsonFile => File(p.join(mementoDir.path, 'config.json'));

  /// Config file path (~/.memento/collector.json)
  static File get configFile => File(p.join(mementoDir.path, 'collector.json'));

  /// Legacy TOML file path (~/.memento/config.toml)
  static File get legacyTomlFile => File(p.join(mementoDir.path, 'config.toml'));

  /// Device ID file (~/.memento/device_id)
  static File get deviceIdFile => File(p.join(mementoDir.path, 'device_id'));

  /// Remote exec key file (~/.memento/remote_exec_key)
  static File get remoteExecKeyFile => File(p.join(mementoDir.path, 'remote_exec_key'));

  /// Load configuration from disk, environment, or defaults.
  static Future<CollectorConfig> load() async {
    final env = Platform.environment;
    String serverUrl = env['MEMENTO_SERVER_URL'] ?? 'https://mem.ihasy.com';
    String token = env['MEMENTO_SERVER_TOKEN'] ?? '';
    String? execKey = env['MEMENTO_REMOTE_EXEC_KEY'];
    List<String> extraDirs = [];

    // 1. Read persistent device ID or generate a new one
    String deviceId = '';
    try {
      if (await deviceIdFile.exists()) {
        deviceId = (await deviceIdFile.readAsString()).trim();
      }
    } catch (_) {}

    if (deviceId.isEmpty) {
      deviceId = _generateUuidV4();
      try {
        if (!await mementoDir.exists()) {
          await mementoDir.create(recursive: true);
        }
        await deviceIdFile.writeAsString(deviceId);
      } catch (_) {}
    }

    // 2. Read remote exec key if stored
    if (execKey == null || execKey.isEmpty) {
      try {
        if (await remoteExecKeyFile.exists()) {
          execKey = (await remoteExecKeyFile.readAsString()).trim();
        }
      } catch (_) {}
    }

    // 3. Read JSON config if available
    try {
      if (await configFile.exists()) {
        final content = await configFile.readAsString();
        final map = jsonDecode(content) as Map<String, dynamic>;
        if (map['server_url'] is String && (map['server_url'] as String).isNotEmpty) {
          serverUrl = map['server_url'];
        }
        if (map['token'] is String && (map['token'] as String).isNotEmpty) {
          token = map['token'];
        } else if (map['server_token'] is String && (map['server_token'] as String).isNotEmpty) {
          token = map['server_token'];
        }
        if (map['remote_exec_key'] is String && (map['remote_exec_key'] as String).isNotEmpty) {
          execKey = map['remote_exec_key'];
        }
        if (map['extra_watch_dirs'] is List) {
          extraDirs = (map['extra_watch_dirs'] as List).cast<String>();
        }
      } else if (await legacyJsonFile.exists()) {
        final content = await legacyJsonFile.readAsString();
        final map = jsonDecode(content) as Map<String, dynamic>;
        if (map['server_url'] is String && (map['server_url'] as String).isNotEmpty) {
          serverUrl = map['server_url'];
        }
        if (map['token'] is String && (map['token'] as String).isNotEmpty) {
          token = map['token'];
        } else if (map['server_token'] is String && (map['server_token'] as String).isNotEmpty) {
          token = map['server_token'];
        }
        if (map['obsidian_vault_path'] is String && (map['obsidian_vault_path'] as String).isNotEmpty) {
          extraDirs.add(map['obsidian_vault_path'] as String);
        }
      } else if (await legacyTomlFile.exists()) {
        // Simple TOML line parse fallback
        final lines = await legacyTomlFile.readAsLines();
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.startsWith('url') && trimmed.contains('=')) {
            final val = trimmed.split('=').last.trim().replaceAll('"', '').replaceAll("'", "");
            if (val.isNotEmpty) serverUrl = val;
          } else if (trimmed.startsWith('token') && trimmed.contains('=')) {
            final val = trimmed.split('=').last.trim().replaceAll('"', '').replaceAll("'", "");
            if (val.isNotEmpty) token = val;
          }
        }
      }
    } catch (_) {}

    // 4. Determine device name & platform label
    final hostname = Platform.localHostname;
    final plat = Platform.operatingSystem; // "macos", "windows", "linux", etc.
    final platLabel = Platform.isMacOS
        ? "Darwin"
        : Platform.isWindows
            ? "Windows"
            : Platform.isLinux
                ? "Linux"
                : plat;
    final deviceName = "$hostname ($platLabel)";

    return CollectorConfig(
      serverUrl: serverUrl.replaceAll(RegExp(r'/+$'), ''),
      token: token,
      deviceId: deviceId,
      deviceName: deviceName,
      platform: platLabel,
      remoteExecKey: execKey,
      extraWatchDirs: extraDirs,
    );
  }

  /// Save current configuration to ~/.memento/collector.json
  Future<void> save() async {
    try {
      if (!await mementoDir.exists()) {
        await mementoDir.create(recursive: true);
      }
      final data = {
        'server_url': serverUrl,
        'token': token,
        'device_id': deviceId,
        'device_name': deviceName,
        'platform': platform,
        if (remoteExecKey != null) 'remote_exec_key': remoteExecKey,
        'extra_watch_dirs': extraWatchDirs,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      await configFile.writeAsString(const JsonEncoder.withIndent('  ').convert(data));

      if (remoteExecKey != null && remoteExecKey!.isNotEmpty) {
        await remoteExecKeyFile.writeAsString(remoteExecKey!);
      }
    } catch (e) {
      stderr.writeln('Failed to save collector config: $e');
    }
  }

  CollectorConfig copyWith({
    String? serverUrl,
    String? token,
    String? deviceId,
    String? deviceName,
    String? platform,
    String? remoteExecKey,
    bool? autoStart,
    List<String>? extraWatchDirs,
  }) {
    return CollectorConfig(
      serverUrl: serverUrl ?? this.serverUrl,
      token: token ?? this.token,
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      platform: platform ?? this.platform,
      remoteExecKey: remoteExecKey ?? this.remoteExecKey,
      autoStart: autoStart ?? this.autoStart,
      extraWatchDirs: extraWatchDirs ?? this.extraWatchDirs,
    );
  }

  static String _generateUuidV4() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final rand = (now ^ (now >> 16)) & 0xFFFFFFFF;
    return 'memento-${now.toRadixString(16)}-${rand.toRadixString(16)}';
  }
}
