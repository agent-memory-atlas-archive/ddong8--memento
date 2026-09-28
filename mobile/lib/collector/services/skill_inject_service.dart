import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../models/collector_config.dart';

/// Skill injection: keeps each published Memento skill as `<skills dir>/<name>/SKILL.md`
/// in the tools' personal skills folders — `~/.claude/skills` for Claude Code,
/// `~/.agents/skills` for Codex and Gemini CLI. The tools pick skills up by their
/// description, and reload them without a restart.
///
/// It owns only what it wrote: a skill directory is ours while the state file
/// records it and its SKILL.md still hashes to what we wrote. A same-named skill
/// the user made is never touched, and one we wrote that the user then edited is
/// left alone (neither overwritten nor deleted) and handed over to the user.

const skillSyncInterval = Duration(minutes: 5);

final _slugRe = RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$');

class SkillDirTarget {
  /// Tool homes; the folder is only used when at least one of them exists
  /// (injection never installs a tool's home, so an absent tool is skipped).
  final List<String> toolHomes;
  final String dir;

  const SkillDirTarget(this.toolHomes, this.dir);
}

Map<String, SkillDirTarget> defaultSkillDirs() {
  final home = CollectorConfig.homeDir;
  final env = Platform.environment;
  final codexHome =
      (env['CODEX_HOME']?.isNotEmpty ?? false) ? env['CODEX_HOME']! : p.join(home, '.codex');
  return {
    'claude': SkillDirTarget([p.join(home, '.claude')], p.join(home, '.claude', 'skills')),
    'agents': SkillDirTarget(
      [codexHome, p.join(home, '.gemini'), p.join(home, '.agents')],
      p.join(home, '.agents', 'skills'),
    ),
  };
}

String get defaultSkillStatePath => p.join(CollectorConfig.mementoDir.path, 'skill_inject.json');

String contentHash(String text) => sha256.convert(utf8.encode(text)).toString();

bool isValidSkillName(String name) => name.length <= 64 && _slugRe.hasMatch(name);

Future<Map<String, dynamic>> _loadState(File file) async {
  try {
    return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  } catch (_) {
    return {};
  }
}

Future<bool> _anyExists(List<String> dirs) async {
  for (final d in dirs) {
    if (await Directory(d).exists()) return true;
  }
  return false;
}

/// Converge the skills folders to what the server publishes. [skills]: each
/// `{slug, version, content}`; [targets]: folder keys ("claude", "agents") this
/// device should carry them in. Returns "<folder>/<slug>" (or "<folder>") -> outcome
/// for everything touched or wanted.
Future<Map<String, String>> applySkillInjection({
  required List<Map<String, dynamic>> skills,
  required List<String> targets,
  Map<String, SkillDirTarget>? dirs,
  String? statePath,
}) async {
  dirs ??= defaultSkillDirs();
  final stateFile = File(statePath ?? defaultSkillStatePath);
  final state = await _loadState(stateFile);
  final results = <String, String>{};

  for (final MapEntry(key: key, value: target) in dirs.entries) {
    final owned = Map<String, dynamic>.from((state[key] as Map?) ?? const {});
    final wanted = targets.contains(key) ? skills : const <Map<String, dynamic>>[];
    if (wanted.isEmpty && owned.isEmpty) continue;
    final installed = await _anyExists(target.toolHomes);
    if (wanted.isNotEmpty && !installed) {
      results[key] = 'skipped: tool not installed';
    }
    final wantedNames = <String>{};

    if (installed) {
      for (final skill in wanted) {
        final name = (skill['slug'] ?? '').toString();
        final content = (skill['content'] ?? '').toString();
        final label = '$key/$name';
        if (!isValidSkillName(name) || content.isEmpty) {
          results[label] = 'error: invalid skill';
          continue;
        }
        wantedNames.add(name);
        try {
          final file = File(p.join(target.dir, name, 'SKILL.md'));
          final mine = owned[name] as Map<String, dynamic>?;
          if (await file.exists()) {
            final current = await file.readAsString();
            if (mine == null) {
              results[label] = 'skipped: a skill with this name already exists';
              continue;
            }
            if (contentHash(current) != mine['hash']) {
              // Edited by hand after we wrote it: the user's now.
              owned.remove(name);
              results[label] = 'kept: edited locally';
              continue;
            }
            if (current == content) {
              results[label] = 'unchanged';
              continue;
            }
          }
          await file.parent.create(recursive: true);
          await file.writeAsString(content, flush: true);
          owned[name] = {'hash': contentHash(content), 'version': skill['version']};
          results[label] = mine == null ? 'written' : 'updated';
        } catch (e) {
          final msg = 'error: $e';
          results[label] = msg.length > 200 ? msg.substring(0, 200) : msg;
        }
      }
    }

    // Anything we wrote that is no longer wanted here comes back out.
    for (final name in owned.keys.toList()) {
      if (wantedNames.contains(name)) continue;
      final label = '$key/$name';
      try {
        final file = File(p.join(target.dir, name, 'SKILL.md'));
        if (await file.exists()) {
          final current = await file.readAsString();
          if (contentHash(current) == (owned[name] as Map)['hash']) {
            await file.delete();
            final dir = file.parent;
            if (await dir.exists() && await dir.list().isEmpty) await dir.delete();
            results[label] = 'removed';
          } else {
            results[label] = 'kept: edited locally';
          }
        }
        owned.remove(name);
      } catch (e) {
        final msg = 'error: $e';
        results[label] = msg.length > 200 ? msg.substring(0, 200) : msg;
      }
    }

    if (owned.isEmpty) {
      state.remove(key);
    } else {
      state[key] = owned;
    }
  }

  await stateFile.parent.create(recursive: true);
  await stateFile.writeAsString(const JsonEncoder.withIndent('  ').convert(state), flush: true);
  return results;
}
