import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memento_mobile/collector/services/skill_inject_service.dart';
import 'package:path/path.dart' as p;

String md(String name, String step) => '---\nname: $name\ndescription: "deploy it"\n---\n\n# $name\n\n1. $step\n';

void main() {
  late Directory tmp;
  late Map<String, SkillDirTarget> dirs;
  late String statePath;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('skill_inject_');
    Directory(p.join(tmp.path, '.claude')).createSync();
    dirs = {
      'claude': SkillDirTarget([p.join(tmp.path, '.claude')], p.join(tmp.path, '.claude', 'skills')),
      'agents': SkillDirTarget([p.join(tmp.path, '.codex')], p.join(tmp.path, '.agents', 'skills')),
    };
    statePath = p.join(tmp.path, 'state.json');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Future<Map<String, String>> run(List<Map<String, dynamic>> skills, List<String> targets) =>
      applySkillInjection(skills: skills, targets: targets, dirs: dirs, statePath: statePath);

  File skillFile(String dir, String name) => File(p.join(tmp.path, dir, 'skills', name, 'SKILL.md'));

  test('names follow the Agent Skills rules', () {
    expect(isValidSkillName('memento-gitops-deploy'), isTrue);
    expect(isValidSkillName('Bad Name'), isFalse);
    expect(isValidSkillName('double--hyphen'), isFalse);
    expect(isValidSkillName('-leading'), isFalse);
    expect(isValidSkillName('a' * 65), isFalse);
  });

  test('write, update, then remove when unpublished', () async {
    var out = await run([{'slug': 'deploy', 'version': 1, 'content': md('deploy', 'push main')}], ['claude']);
    expect(out['claude/deploy'], 'written');
    expect(skillFile('.claude', 'deploy').readAsStringSync(), contains('push main'));

    out = await run([{'slug': 'deploy', 'version': 1, 'content': md('deploy', 'push main')}], ['claude']);
    expect(out['claude/deploy'], 'unchanged');

    out = await run([{'slug': 'deploy', 'version': 2, 'content': md('deploy', 'push main, then watch fleet')}], ['claude']);
    expect(out['claude/deploy'], 'updated');
    expect(skillFile('.claude', 'deploy').readAsStringSync(), contains('watch fleet'));

    out = await run([], ['claude']);
    expect(out['claude/deploy'], 'removed');
    expect(Directory(p.join(tmp.path, '.claude', 'skills', 'deploy')).existsSync(), isFalse);
  });

  test("a same-named skill the user made is never touched", () async {
    final mine = skillFile('.claude', 'deploy')..createSync(recursive: true);
    mine.writeAsStringSync('my own skill');
    final out = await run([{'slug': 'deploy', 'version': 1, 'content': md('deploy', 'x')}], ['claude']);
    expect(out['claude/deploy'], startsWith('skipped'));
    expect(mine.readAsStringSync(), 'my own skill');
    await run([], ['claude']);
    expect(mine.readAsStringSync(), 'my own skill');
  });

  test('a skill edited locally is kept, not overwritten or deleted', () async {
    await run([{'slug': 'deploy', 'version': 1, 'content': md('deploy', 'a')}], ['claude']);
    skillFile('.claude', 'deploy').writeAsStringSync('edited by hand');
    var out = await run([{'slug': 'deploy', 'version': 2, 'content': md('deploy', 'b')}], ['claude']);
    expect(out['claude/deploy'], 'kept: edited locally');
    expect(skillFile('.claude', 'deploy').readAsStringSync(), 'edited by hand');
    out = await run([], ['claude']);
    expect(skillFile('.claude', 'deploy').readAsStringSync(), 'edited by hand');
  });

  test('a folder for a tool that is not installed is skipped', () async {
    final out = await run([{'slug': 'deploy', 'version': 1, 'content': md('deploy', 'a')}], ['agents']);
    expect(out['agents'], 'skipped: tool not installed');
    expect(Directory(p.join(tmp.path, '.agents')).existsSync(), isFalse);
  });

  test('switching a tool off takes its skills back out, other folders stay', () async {
    Directory(p.join(tmp.path, '.codex')).createSync();
    final skills = [{'slug': 'deploy', 'version': 1, 'content': md('deploy', 'a')}];
    await run(skills, ['claude', 'agents']);
    expect(skillFile('.agents', 'deploy').existsSync(), isTrue);
    final out = await run(skills, ['claude']);
    expect(out['agents/deploy'], 'removed');
    expect(skillFile('.claude', 'deploy').existsSync(), isTrue);
  });

  test('invalid names are refused', () async {
    final out = await run([{'slug': '../escape', 'version': 1, 'content': 'x'}], ['claude']);
    expect(out['claude/../escape'], 'error: invalid skill');
    expect(File(p.join(tmp.path, '.claude', 'escape', 'SKILL.md')).existsSync(), isFalse);
  });
}
