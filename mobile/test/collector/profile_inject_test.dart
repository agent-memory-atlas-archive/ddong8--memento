import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memento_mobile/collector/services/profile_inject_service.dart';
import 'package:path/path.dart' as p;

const blockV1 = '<!-- memento:begin v1 · x -->\n## 关于我\n\n- 用中文回复\n<!-- memento:end -->\n';
const blockV2 = '<!-- memento:begin v2 · x -->\n## 关于我\n\n- 用中文回复\n- 只走 GitOps\n<!-- memento:end -->\n';

void main() {
  late Directory tmp;
  late Map<String, ProfileTarget> files;
  late String statePath;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('profile_inject_');
    for (final h in ['claude', 'codex', 'gemini']) {
      Directory(p.join(tmp.path, h)).createSync();
    }
    files = {
      'claude_code': ProfileTarget(p.join(tmp.path, 'claude'), p.join(tmp.path, 'claude', 'CLAUDE.md')),
      'codex': ProfileTarget(p.join(tmp.path, 'codex'), p.join(tmp.path, 'codex', 'AGENTS.md')),
      'antigravity': ProfileTarget(p.join(tmp.path, 'gemini'), p.join(tmp.path, 'gemini', 'GEMINI.md')),
      'hermes': ProfileTarget(p.join(tmp.path, 'not-installed'), p.join(tmp.path, 'not-installed', 'SOUL.md')),
    };
    statePath = p.join(tmp.path, 'state.json');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Future<Map<String, String>> run(int? version, String? block, List<String> targets) =>
      applyProfileInjection(version: version, block: block, targets: targets, files: files, statePath: statePath);

  String read(String tool) => File(files[tool]!.file).readAsStringSync();

  test('upsert appends to existing text, then replaces in place', () {
    const text = '# mine\n\nkeep\n';
    final once = upsertProfileBlock(text, blockV1)!;
    expect(once.startsWith('# mine\n\nkeep'), isTrue);
    final twice = upsertProfileBlock(once, blockV2)!;
    expect('memento:begin'.allMatches(twice).length, 1);
    expect(twice, contains('GitOps'));
  });

  test('damaged markers are refused, not guessed at', () {
    const damaged = '# mine\n<!-- memento:begin v1 -->\nhalf a block\n';
    expect(upsertProfileBlock(damaged, blockV1), isNull);
    expect(removeProfileBlock(damaged), isNull);
  });

  test('block validation rejects nested or missing markers', () {
    expect(isValidProfileBlock(blockV1), isTrue);
    expect(isValidProfileBlock(blockV1 + blockV2), isFalse);
    expect(isValidProfileBlock('no markers'), isFalse);
    expect(isValidProfileBlock(null), isFalse);
  });

  test('write, update, and remove round trip leaves user files untouched', () async {
    File(files['codex']!.file).writeAsStringSync('# my codex rules\n');

    expect(await run(1, blockV1, ['claude_code', 'codex', 'hermes']), {
      'claude_code': 'written',
      'codex': 'written',
      'hermes': 'skipped: tool not installed',
    });
    expect(read('claude_code'), blockV1);
    expect(read('codex').startsWith('# my codex rules'), isTrue);
    expect(File('${files['codex']!.file}.memento.bak').readAsStringSync(), '# my codex rules\n');

    expect(await run(1, blockV1, ['claude_code', 'codex']), {'claude_code': 'unchanged', 'codex': 'unchanged'});
    expect((await run(2, blockV2, ['claude_code', 'codex']))['codex'], 'written');
    expect(read('codex'), contains('GitOps'));

    // Switched off in the app: the file we created goes away, the user's file is restored.
    expect(await run(2, blockV2, []), {'claude_code': 'removed', 'codex': 'removed'});
    expect(File(files['claude_code']!.file).existsSync(), isFalse);
    expect(read('codex'), '# my codex rules\n');
  });

  test('hand-edited block is restored on next sync', () async {
    await run(1, blockV1, ['antigravity']);
    final path = files['antigravity']!.file;
    File(path).writeAsStringSync(read('antigravity').replaceAll('用中文回复', '随便'));
    expect(await run(1, blockV1, ['antigravity']), {'antigravity': 'written'});
    expect(read('antigravity'), contains('用中文回复'));
  });

  test('created file the user added to is kept on removal', () async {
    await run(1, blockV1, ['claude_code']);
    final path = files['claude_code']!.file;
    File(path).writeAsStringSync('# added by me\n\n${read('claude_code')}');
    await run(1, blockV1, []);
    expect(read('claude_code'), '# added by me\n');
  });

  test('invalid block from server writes nothing', () async {
    expect(await run(3, '<!-- memento:begin --> no end', ['claude_code']),
        {'claude_code': 'waiting: no published profile yet'});
    expect(File(files['claude_code']!.file).existsSync(), isFalse);
  });

  test('server-rendered block format is accepted', () {
    // Shape produced by render_profile_block() in server/server/services/profile_service.py.
    const rendered = '<!-- memento:begin v7 · 由 Memento 生成，请在 Memento 中修改，手改此段会被覆盖 -->\n'
        '## 关于我（Memento 长期记忆）\n\n### 沟通\n- 始终用中文回复\n\n'
        '需要更多上下文时，用 memento-memory MCP 的 memory_search / memory_core 查询。\n'
        '<!-- memento:end -->\n';
    expect(isValidProfileBlock(rendered), isTrue);
  });
}
