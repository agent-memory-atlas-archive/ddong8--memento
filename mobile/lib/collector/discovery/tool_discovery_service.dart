import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

import '../models/collector_config.dart';
import '../models/tool_discovery.dart';

/// Cross-platform auto-discovery of installed AI developer tools and workspace folders.
class ToolDiscoveryService {
  static String get _home => CollectorConfig.homeDir;

  static String get _appData {
    if (Platform.isWindows) {
      return Platform.environment['APPDATA'] ?? p.join(_home, 'AppData', 'Roaming');
    }
    return '';
  }

  static String get _appSupport {
    if (Platform.isMacOS) {
      return p.join(_home, 'Library', 'Application Support');
    }
    return '';
  }

  static String get _linuxConfig {
    if (Platform.isLinux) {
      return Platform.environment['XDG_CONFIG_HOME'] ?? p.join(_home, '.config');
    }
    return '';
  }

  static String _cleanPath(String path) {
    var cleaned = path;
    if (cleaned.startsWith(r'\\?\')) {
      cleaned = cleaned.substring(4);
    }
    try {
      cleaned = Uri.decodeComponent(cleaned);
    } catch (_) {}
    return cleaned;
  }

  /// Discover Claude Code (~/.claude)
  static Future<DiscoveredTool?> discoverClaudeCode() async {
    final root = Directory(p.join(_home, '.claude'));
    if (!await root.exists()) return null;

    final List<DiscoveredProject> projects = [];
    final projectsDir = Directory(p.join(root.path, 'projects'));
    if (await projectsDir.exists()) {
      await for (final entity in projectsDir.list()) {
        if (entity is Directory) {
          final dirName = p.basename(entity.path);
          if (dirName.startsWith('-')) {
            // e.g. -Users-haixingdong-dev-memento -> /Users/haixingdong/dev/memento
            final decoded = '/${dirName.substring(1).replaceAll('-', '/')}';
            projects.add(DiscoveredProject(
              name: p.basename(decoded),
              path: _cleanPath(decoded),
              metadata: {'hash': dirName},
            ));
          } else {
            // Windows path encoding or plain
            projects.add(DiscoveredProject(
              name: dirName,
              path: _cleanPath(entity.path),
            ));
          }
        }
      }
    }

    return DiscoveredTool(
      id: 'claude_code',
      name: 'Claude Code',
      root: root.path,
      projects: projects,
    );
  }

  /// Discover OpenAI Codex (~/.codex)
  static Future<DiscoveredTool?> discoverCodex() async {
    final root = Directory(p.join(_home, '.codex'));
    if (!await root.exists()) return null;

    final List<DiscoveredProject> projects = [];
    final seenPaths = <String>{};

    // 1. .codex-global-state.json
    final stateFile = File(p.join(root.path, '.codex-global-state.json'));
    if (await stateFile.exists()) {
      try {
        final data = jsonDecode(await stateFile.readAsString());
        if (data is Map) {
          final roots = [
            ...(data['electron-saved-workspace-roots'] as List? ?? []),
            ...(data['active-workspace-roots'] as List? ?? []),
          ];
          for (final r in roots) {
            final pathStr = _cleanPath(r.toString());
            if (pathStr.isNotEmpty && seenPaths.add(pathStr)) {
              projects.add(DiscoveredProject(
                name: p.basename(pathStr),
                path: pathStr,
              ));
            }
          }
        }
      } catch (_) {}
    }

    // 2. sessions directory check
    final sessionsDir = Directory(p.join(root.path, 'sessions'));
    int sessionCount = 0;
    if (await sessionsDir.exists()) {
      try {
        await for (final _ in sessionsDir.list()) {
          sessionCount++;
        }
      } catch (_) {}
    }

    return DiscoveredTool(
      id: 'codex',
      name: 'OpenAI Codex',
      root: root.path,
      projects: projects,
      metadata: {'total_sessions': sessionCount},
    );
  }

  /// Discover Google Antigravity (~/.gemini/antigravity or ~/.antigravity)
  static Future<DiscoveredTool?> discoverAntigravity() async {
    final geminiRoot = Directory(p.join(_home, '.gemini', 'antigravity'));
    final agRoot = Directory(p.join(_home, '.antigravity'));

    String? validRoot;
    if (await geminiRoot.exists()) {
      validRoot = geminiRoot.path;
    } else if (await agRoot.exists()) {
      validRoot = agRoot.path;
    }

    if (validRoot == null) return null;

    final List<DiscoveredProject> projects = [];
    final seenPaths = <String>{};

    // Storage.json for backup workspaces
    File? storageFile;
    if (Platform.isMacOS) {
      storageFile = File(p.join(_appSupport, 'Antigravity', 'User', 'globalStorage', 'storage.json'));
    } else if (Platform.isWindows) {
      storageFile = File(p.join(_appData, 'Antigravity', 'User', 'globalStorage', 'storage.json'));
    } else if (Platform.isLinux) {
      storageFile = File(p.join(_linuxConfig, 'Antigravity', 'User', 'globalStorage', 'storage.json'));
    }

    if (storageFile != null && await storageFile.exists()) {
      try {
        final data = jsonDecode(await storageFile.readAsString());
        final folders = data['backupWorkspaces']?['folders'] as List? ?? [];
        for (final f in folders) {
          final uri = f['folderUri']?.toString() ?? '';
          if (uri.startsWith('file:///')) {
            var raw = uri.substring(Platform.isWindows ? 8 : 7);
            raw = _cleanPath(raw);
            if (raw.isNotEmpty && seenPaths.add(raw)) {
              projects.add(DiscoveredProject(name: p.basename(raw), path: raw));
            }
          }
        }
      } catch (_) {}
    }

    return DiscoveredTool(
      id: 'antigravity',
      name: 'Google Antigravity',
      root: validRoot,
      projects: projects,
    );
  }

  /// Discover Cursor (~/.cursor)
  static Future<DiscoveredTool?> discoverCursor() async {
    final root = Directory(p.join(_home, '.cursor'));
    File? storageFile;
    if (Platform.isMacOS) {
      storageFile = File(p.join(_appSupport, 'Cursor', 'User', 'globalStorage', 'storage.json'));
    } else if (Platform.isWindows) {
      storageFile = File(p.join(_appData, 'Cursor', 'User', 'globalStorage', 'storage.json'));
    } else if (Platform.isLinux) {
      storageFile = File(p.join(_linuxConfig, 'Cursor', 'User', 'globalStorage', 'storage.json'));
    }

    final hasRoot = await root.exists();
    final hasStorage = storageFile != null && await storageFile.exists();
    if (!hasRoot && !hasStorage) return null;

    final List<DiscoveredProject> projects = [];
    final seenPaths = <String>{};

    if (hasStorage) {
      try {
        final data = jsonDecode(await storageFile.readAsString());
        final folders = data['backupWorkspaces']?['folders'] as List? ?? [];
        for (final f in folders) {
          final uri = f['folderUri']?.toString() ?? '';
          if (uri.startsWith('file:///')) {
            var raw = uri.substring(Platform.isWindows ? 8 : 7);
            raw = _cleanPath(raw);
            if (raw.isNotEmpty && seenPaths.add(raw)) {
              projects.add(DiscoveredProject(name: p.basename(raw), path: raw));
            }
          }
        }
      } catch (_) {}
    }

    return DiscoveredTool(
      id: 'cursor',
      name: 'Cursor',
      root: root.existsSync() ? root.path : (storageFile?.parent.path ?? ''),
      projects: projects,
    );
  }

  /// Discover Obsidian vaults from obsidian.json
  static Future<DiscoveredTool?> discoverObsidian() async {
    File? obsFile;
    if (Platform.isMacOS) {
      obsFile = File(p.join(_appSupport, 'obsidian', 'obsidian.json'));
    } else if (Platform.isWindows) {
      obsFile = File(p.join(_appData, 'obsidian', 'obsidian.json'));
    } else if (Platform.isLinux) {
      obsFile = File(p.join(_linuxConfig, 'obsidian', 'obsidian.json'));
    }

    if (obsFile == null || !await obsFile.exists()) {
      return null;
    }

    final List<DiscoveredProject> projects = [];
    try {
      final data = jsonDecode(await obsFile.readAsString());
      final vaults = data['vaults'] as Map? ?? {};
      for (final v in vaults.values) {
        if (v is Map && v['path'] is String) {
          final pathStr = _cleanPath(v['path'] as String);
          projects.add(DiscoveredProject(
            name: p.basename(pathStr),
            path: pathStr,
            metadata: {'ts': v['ts']},
          ));
        }
      }
    } catch (_) {}

    return DiscoveredTool(
      id: 'obsidian',
      name: 'Obsidian',
      root: obsFile.parent.path,
      projects: projects,
    );
  }

  /// Run full discovery across all supported tools
  static Future<Map<String, DiscoveredTool>> discoverAll() async {
    final Map<String, DiscoveredTool> tools = {};

    final results = await Future.wait([
      discoverClaudeCode(),
      discoverCodex(),
      discoverAntigravity(),
      discoverCursor(),
      discoverObsidian(),
    ]);

    for (final tool in results) {
      if (tool != null) {
        tools[tool.id] = tool;
      }
    }

    return tools;
  }
}
