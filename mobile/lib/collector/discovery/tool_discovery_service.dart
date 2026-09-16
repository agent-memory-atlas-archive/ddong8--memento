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

  static String cleanPath(String path) {
    var cleaned = path.trim();
    if (cleaned.startsWith(r'\\?\')) {
      cleaned = cleaned.substring(4);
    }
    if (cleaned.startsWith('file://')) {
      final uri = Uri.tryParse(cleaned);
      if (uri != null && uri.hasScheme && uri.scheme == 'file') {
        try {
          cleaned = uri.toFilePath();
        } catch (_) {
          cleaned = cleaned.replaceFirst(RegExp(r'^file://+'), '');
          if (Platform.isWindows && cleaned.startsWith('/')) {
            cleaned = cleaned.substring(1);
          }
        }
      } else {
        cleaned = cleaned.replaceFirst(RegExp(r'^file://+'), '');
      }
    }
    try {
      cleaned = Uri.decodeComponent(cleaned);
    } catch (_) {}
    return cleaned;
  }

  static bool isInvalidProjectName(String name) {
    final lower = name.trim().toLowerCase();
    return lower.isEmpty ||
        lower == 'file:' ||
        lower == 'file' ||
        lower == 'untitled' ||
        lower == 'unknown' ||
        lower == 'tmp' ||
        lower == 'temp';
  }

  /// On macOS, check if /Volumes/<name> is currently mounted to avoid triggering TCC network volume prompts.
  static bool isVolumeMountedOnMac(String path) {
    if (!Platform.isMacOS || !path.startsWith('/Volumes/')) return true;
    try {
      final parts = path.split('/');
      if (parts.length < 3) return false;
      final volName = parts[2];
      if (volName.isEmpty) return false;
      final volDir = Directory('/Volumes');
      if (!volDir.existsSync()) return false;
      final mounted = volDir.listSync().map((e) => p.basename(e.path)).toSet();
      return mounted.contains(volName);
    } catch (_) {
      return false;
    }
  }

  static (String name, String path) decodeClaudeDir(String dirName) {
    var raw = dirName.trim();
    if (raw.startsWith('-')) {
      raw = raw.substring(1);
      final decodedPath = '/${raw.replaceAll('-', '/')}';
      final name = _prettifyProjectName(p.basename(decodedPath));
      return (name, decodedPath);
    }
    final winMatch = RegExp(r'^([a-zA-Z])--?(.+)$').firstMatch(raw);
    if (winMatch != null) {
      final drive = winMatch.group(1)!.toUpperCase();
      final rest = winMatch.group(2)!.replaceAll('-', '/');
      final decodedPath = '$drive:/$rest';
      final parts = rest.split('/');
      var name = parts.isNotEmpty ? parts.last : raw;
      name = _prettifyProjectName(name);
      return (name, decodedPath);
    }
    return (raw, raw);
  }

  static String _prettifyProjectName(String name) {
    return name.replaceFirst(RegExp(r'^\d{4}-?\d{2,4}-?'), '');
  }

  /// Discover Claude Code (~/.claude)
  static Future<DiscoveredTool?> discoverClaudeCode() async {
    final root = Directory(p.join(_home, '.claude'));
    if (!await root.exists()) return null;

    final List<DiscoveredProject> projects = [];
    final seenPaths = <String>{};
    final projectsDir = Directory(p.join(root.path, 'projects'));
    if (await projectsDir.exists()) {
      await for (final entity in projectsDir.list()) {
        if (entity is Directory) {
          final dirName = p.basename(entity.path);
          final (projName, realPath) = decodeClaudeDir(dirName);
          final cleanRealPath = cleanPath(realPath);
          if (cleanRealPath.isNotEmpty && isVolumeMountedOnMac(cleanRealPath) && seenPaths.add(cleanRealPath)) {
            if (!isInvalidProjectName(projName)) {
              projects.add(DiscoveredProject(
                name: projName,
                path: cleanRealPath,
                metadata: {'hash': dirName},
              ));
            }
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
          // Modern Codex: local-projects map
          final localProjects = data['local-projects'];
          if (localProjects is Map) {
            for (final entry in localProjects.values) {
              if (entry is Map) {
                final name = (entry['name'] ?? '').toString().trim();
                final rootPaths = entry['rootPaths'] as List? ?? [];
                for (final r in rootPaths) {
                  final pathStr = cleanPath(r.toString());
                  if (pathStr.isNotEmpty && isVolumeMountedOnMac(pathStr) && seenPaths.add(pathStr)) {
                    final projName = name.isNotEmpty ? name : p.basename(pathStr);
                    if (!isInvalidProjectName(projName)) {
                      projects.add(DiscoveredProject(
                        name: projName,
                        path: pathStr,
                      ));
                    }
                  }
                }
              }
            }
          }

          // Fallback / legacy workspace roots
          final roots = [
            ...(data['electron-saved-workspace-roots'] as List? ?? []),
            ...(data['active-workspace-roots'] as List? ?? []),
          ];
          for (final r in roots) {
            final pathStr = cleanPath(r.toString());
            if (pathStr.isNotEmpty && isVolumeMountedOnMac(pathStr) && seenPaths.add(pathStr)) {
              final projName = p.basename(pathStr);
              if (!isInvalidProjectName(projName)) {
                projects.add(DiscoveredProject(
                  name: projName,
                  path: pathStr,
                ));
              }
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

  static Future<List<String>> _extractVscWorkspaces(Directory globalStorageDir) async {
    final List<String> paths = [];
    final seen = <String>{};

    void addPath(String rawUri) {
      final cleaned = cleanPath(rawUri);
      if (cleaned.isNotEmpty && isVolumeMountedOnMac(cleaned) && !isInvalidProjectName(p.basename(cleaned))) {
        final lower = cleaned.toLowerCase();
        if (lower.contains('/.gemini/antigravity/playground/') ||
            lower.contains(r'\.gemini\antigravity\playground\') ||
            lower.endsWith('.json') ||
            lower.endsWith('.yaml') ||
            lower.endsWith('.yml') ||
            lower.endsWith('.py') ||
            lower.endsWith('.md')) {
          return;
        }
        if (seen.add(cleaned)) {
          paths.add(cleaned);
        }
      }
    }

    // 1. Read storage.json backupWorkspaces
    final storageFile = File(p.join(globalStorageDir.path, 'storage.json'));
    if (await storageFile.exists()) {
      try {
        final data = jsonDecode(await storageFile.readAsString());
        final folders = data['backupWorkspaces']?['folders'] as List? ?? [];
        for (final f in folders) {
          final uri = f['folderUri']?.toString() ?? '';
          if (uri.isNotEmpty) addPath(uri);
        }
      } catch (_) {}
    }

    // 2. Read state.vscdb for history.recentlyOpenedPathsList & file URIs
    final vscdbFile = File(p.join(globalStorageDir.path, 'state.vscdb'));
    if (await vscdbFile.exists()) {
      try {
        final bytes = await vscdbFile.readAsBytes();
        final content = utf8.decode(bytes, allowMalformed: true);
        final keyIdx = content.indexOf('history.recentlyOpenedPathsList');
        if (keyIdx != -1) {
          final chunk = content.substring(keyIdx, (keyIdx + 32768 > content.length) ? content.length : keyIdx + 32768);
          final matches = RegExp(r'"folderUri"\s*:\s*"([^"]+)"').allMatches(chunk);
          for (final m in matches) {
            final uri = m.group(1);
            if (uri != null && uri.isNotEmpty) addPath(uri);
          }
        }
        final allUris = RegExp(r'file:///[a-zA-Z0-9_%/\.\-]+').allMatches(content);
        for (final m in allUris) {
          final uri = m.group(0);
          if (uri != null && uri.isNotEmpty) addPath(uri);
        }
      } catch (_) {}
    }

    return paths;
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

    Directory? storageDir;
    if (Platform.isMacOS) {
      storageDir = Directory(p.join(_appSupport, 'Antigravity', 'User', 'globalStorage'));
    } else if (Platform.isWindows) {
      storageDir = Directory(p.join(_appData, 'Antigravity', 'User', 'globalStorage'));
    } else if (Platform.isLinux) {
      storageDir = Directory(p.join(_linuxConfig, 'Antigravity', 'User', 'globalStorage'));
    }

    final hasRoot = validRoot != null;
    final hasStorage = storageDir != null && await storageDir.exists();
    if (!hasRoot && !hasStorage) return null;

    final List<DiscoveredProject> projects = [];
    final seenPaths = <String>{};

    if (hasStorage) {
      final workspacePaths = await _extractVscWorkspaces(storageDir);
      for (final rawPath in workspacePaths) {
        if (seenPaths.add(rawPath)) {
          final name = p.basename(rawPath);
          if (!isInvalidProjectName(name)) {
            projects.add(DiscoveredProject(name: name, path: rawPath));
          }
        }
      }
    }

    return DiscoveredTool(
      id: 'antigravity',
      name: 'Google Antigravity',
      root: validRoot ?? (storageDir?.parent.path ?? ''),
      projects: projects,
    );
  }

  /// Discover Cursor (~/.cursor)
  static Future<DiscoveredTool?> discoverCursor() async {
    final root = Directory(p.join(_home, '.cursor'));
    Directory? storageDir;
    if (Platform.isMacOS) {
      storageDir = Directory(p.join(_appSupport, 'Cursor', 'User', 'globalStorage'));
    } else if (Platform.isWindows) {
      storageDir = Directory(p.join(_appData, 'Cursor', 'User', 'globalStorage'));
    } else if (Platform.isLinux) {
      storageDir = Directory(p.join(_linuxConfig, 'Cursor', 'User', 'globalStorage'));
    }

    final hasRoot = await root.exists();
    final hasStorage = storageDir != null && await storageDir.exists();
    if (!hasRoot && !hasStorage) return null;

    final List<DiscoveredProject> projects = [];
    final seenPaths = <String>{};

    if (hasStorage) {
      final workspacePaths = await _extractVscWorkspaces(storageDir);
      for (final rawPath in workspacePaths) {
        if (seenPaths.add(rawPath)) {
          final name = p.basename(rawPath);
          if (!isInvalidProjectName(name)) {
            projects.add(DiscoveredProject(name: name, path: rawPath));
          }
        }
      }
    }

    return DiscoveredTool(
      id: 'cursor',
      name: 'Cursor',
      root: root.existsSync() ? root.path : (storageDir?.parent.path ?? ''),
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
          final pathStr = cleanPath(v['path'] as String);
          final projName = p.basename(pathStr);
          if (!isInvalidProjectName(projName)) {
            projects.add(DiscoveredProject(
              name: projName,
              path: pathStr,
              metadata: {'ts': v['ts']},
            ));
          }
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
