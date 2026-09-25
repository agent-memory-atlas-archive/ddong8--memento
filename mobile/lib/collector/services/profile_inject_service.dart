import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/collector_config.dart';

/// Resident-profile injection: keeps the user's published "about me" block in
/// each enabled AI tool's global instruction file (CLAUDE.md, AGENTS.md, ...).
///
/// Which tools get the block is chosen per device in the app; this only
/// converges files to what the server says. It owns nothing outside its
/// markers: existing text is left alone, a file it created is deleted again
/// when the block is removed, and a damaged marker pair is reported rather
/// than guessed at.
///
/// Markers must match server/server/services/profile_service.py.

const profileBegin = '<!-- memento:begin';
const profileEnd = '<!-- memento:end -->';
final _blockRe = RegExp(r'<!-- memento:begin[^>]*-->[\s\S]*?<!-- memento:end -->\n?');

const profileSyncInterval = Duration(minutes: 5);

class ProfileTarget {
  /// The tool's own directory. Must already exist: injection never creates a
  /// tool's home, so a tool that isn't installed is simply skipped.
  final String toolHome;
  final String file;

  const ProfileTarget(this.toolHome, this.file);
}

Map<String, ProfileTarget> defaultProfileTargets() {
  final home = CollectorConfig.homeDir;
  final env = Platform.environment;
  final codexHome =
      (env['CODEX_HOME']?.isNotEmpty ?? false) ? env['CODEX_HOME']! : p.join(home, '.codex');
  var geminiRoot = p.join(home, '.gemini');
  if (Platform.isWindows) {
    final appData = env['APPDATA'];
    if (appData != null && Directory(p.join(appData, '.gemini')).existsSync()) {
      geminiRoot = p.join(appData, '.gemini');
    }
  }
  final openclawWorkspace = p.join(home, '.openclaw', 'workspace');
  return {
    'claude_code': ProfileTarget(p.join(home, '.claude'), p.join(home, '.claude', 'CLAUDE.md')),
    'codex': ProfileTarget(codexHome, p.join(codexHome, 'AGENTS.md')),
    'antigravity': ProfileTarget(geminiRoot, p.join(geminiRoot, 'GEMINI.md')),
    'openclaw': ProfileTarget(openclawWorkspace, p.join(openclawWorkspace, 'USER.md')),
    'hermes': ProfileTarget(p.join(home, '.hermes'), p.join(home, '.hermes', 'SOUL.md')),
  };
}

String get defaultProfileStatePath => p.join(CollectorConfig.mementoDir.path, 'profile_inject.json');

int _count(String text, String needle) => needle.allMatches(text).length;

String _trimTrailingNewlines(String text) => text.replaceFirst(RegExp(r'\n+$'), '');

bool isValidProfileBlock(String? block) =>
    block != null &&
    block.startsWith(profileBegin) &&
    _trimTrailingNewlines(block).endsWith(profileEnd) &&
    _count(block, profileBegin) == 1 &&
    _count(block, profileEnd) == 1;

/// [text] with our block replaced, or appended if absent. Null if markers are damaged.
String? upsertProfileBlock(String text, String block) {
  final begins = _count(text, profileBegin);
  final ends = _count(text, profileEnd);
  if (begins == 0 && ends == 0) {
    return text.trim().isEmpty ? block : '${_trimTrailingNewlines(text)}\n\n$block';
  }
  if (begins == 1 && ends == 1 && _blockRe.hasMatch(text)) {
    return text.replaceFirst(_blockRe, block);
  }
  return null;
}

/// [text] with our block removed. Null if markers are damaged.
String? removeProfileBlock(String text) {
  final begins = _count(text, profileBegin);
  final ends = _count(text, profileEnd);
  if (begins == 0 && ends == 0) return text;
  if (begins == 1 && ends == 1 && _blockRe.hasMatch(text)) {
    final rest = text.replaceFirst(_blockRe, '');
    return rest.trim().isEmpty ? '' : '${_trimTrailingNewlines(rest)}\n';
  }
  return null;
}

Future<Map<String, dynamic>> _loadState(File file) async {
  try {
    return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  } catch (_) {
    return {};
  }
}

const _damaged = 'error: memento markers damaged, fix the file by hand';

/// Converge instruction files to the server's wishes. Returns tool -> outcome
/// for every tool touched or wanted; tools never enabled here are left out.
Future<Map<String, String>> applyProfileInjection({
  required int? version,
  required String? block,
  required List<String> targets,
  Map<String, ProfileTarget>? files,
  String? statePath,
}) async {
  files ??= defaultProfileTargets();
  final stateFile = File(statePath ?? defaultProfileStatePath);
  final state = await _loadState(stateFile);
  final hasBlock = isValidProfileBlock(block);
  final wanted = hasBlock ? targets.toSet() : <String>{};
  final results = <String, String>{};

  for (final MapEntry(key: tool, value: target) in files.entries) {
    final entry = state[tool] as Map<String, dynamic>?;
    final file = File(target.file);
    try {
      if (wanted.contains(tool)) {
        final existed = await file.exists();
        final text = existed ? await file.readAsString() : '';
        if (entry != null && entry['version'] == version && text.contains(block!)) {
          results[tool] = 'unchanged';
          continue;
        }
        if (!await Directory(target.toolHome).exists()) {
          results[tool] = 'skipped: tool not installed';
          continue;
        }
        final updated = upsertProfileBlock(text, block!);
        if (updated == null) {
          results[tool] = _damaged;
          continue;
        }
        final backup = File('${target.file}.memento.bak');
        if (existed && !await backup.exists()) {
          await file.copy(backup.path);
        }
        // In-place write keeps the file's owner and permissions.
        await file.writeAsString(updated, flush: true);
        state[tool] = {'version': version, 'created': entry != null ? entry['created'] : !existed};
        results[tool] = 'written';
      } else if (entry != null) {
        if (await file.exists()) {
          final text = await file.readAsString();
          final updated = removeProfileBlock(text);
          if (updated == null) {
            results[tool] = _damaged;
            continue;
          }
          if (updated.trim().isEmpty && entry['created'] == true) {
            await file.delete();
          } else if (updated != text) {
            await file.writeAsString(updated, flush: true);
          }
        }
        state.remove(tool);
        results[tool] = 'removed';
      } else if (targets.contains(tool) && !hasBlock) {
        results[tool] = 'waiting: no published profile yet';
      }
    } catch (e) {
      // One broken file must not stop the others.
      final msg = 'error: $e';
      results[tool] = msg.length > 200 ? msg.substring(0, 200) : msg;
    }
  }

  await stateFile.parent.create(recursive: true);
  await stateFile.writeAsString(const JsonEncoder.withIndent('  ').convert(state), flush: true);
  return results;
}

/// Take every block this device wrote back out.
Future<Map<String, String>> removeAllProfileBlocks() =>
    applyProfileInjection(version: null, block: null, targets: const []);
