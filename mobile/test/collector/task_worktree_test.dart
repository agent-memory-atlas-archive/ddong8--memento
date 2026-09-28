import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memento_mobile/collector/services/task_worktree.dart';
import 'package:path/path.dart' as p;

Future<void> _git(String dir, List<String> args) async {
  final r = await Process.run('git', ['-c', 'user.email=t@t', '-c', 'user.name=t', ...args], workingDirectory: dir);
  if (r.exitCode != 0) throw StateError('git ${args.join(' ')}: ${r.stderr}');
}

void main() {
  late Directory tmp;
  late String repo;
  late String home;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('worktree_test');
    repo = p.join(tmp.path, 'repo');
    home = p.join(tmp.path, 'home');
    Directory(p.join(repo, 'server')).createSync(recursive: true);
    File(p.join(repo, 'server', 'app.py')).writeAsStringSync('print(1)\n');
    await _git(repo, ['init', '-q']);
    await _git(repo, ['add', '.']);
    await _git(repo, ['commit', '-qm', 'init']);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  test('runs in the same subdirectory of its own worktree, outside the repo', () async {
    final r = await TaskWorktree.create(p.join(repo, 'server'), 'abcd1234-5678-90ef', homeDir: home);
    final tree = r.tree!;
    expect(tree.branch, 'memento/abcd1234');
    expect(p.isWithin(repo, tree.path), isFalse);
    expect(tree.workDir, p.join(tree.path, 'server'));
    expect(File(p.join(tree.workDir, 'app.py')).existsSync(), isTrue);
  });

  test('a task that changed nothing leaves no worktree or branch behind', () async {
    final tree = (await TaskWorktree.create(repo, 'task0001', homeDir: home)).tree!;
    final result = await tree.finish();
    expect(result['status'], 'removed');
    expect(Directory(tree.path).existsSync(), isFalse);
    final branches = await Process.run('git', ['branch', '--list', 'memento/*'], workingDirectory: repo);
    expect(branches.stdout.toString().trim(), isEmpty);
  });

  test('changes and commits keep the branch for review', () async {
    final tree = (await TaskWorktree.create(repo, 'task0002', homeDir: home)).tree!;
    File(p.join(tree.path, 'server', 'app.py')).writeAsStringSync('print(2)\n');
    await _git(tree.path, ['commit', '-qam', 'change']);
    File(p.join(tree.path, 'new.txt')).writeAsStringSync('x');
    final result = await tree.finish();
    expect(result['status'], 'kept');
    expect(result['commits'], 1);
    expect(result['files'], ['new.txt', 'server/app.py']);
    expect(Directory(tree.path).existsSync(), isTrue);
    // The main checkout is untouched.
    expect(File(p.join(repo, 'server', 'app.py')).readAsStringSync(), 'print(1)\n');
  });

  test('outside a repository the task runs in place', () async {
    final plain = Directory(p.join(tmp.path, 'plain'))..createSync();
    final r = await TaskWorktree.create(plain.path, 'task0003', homeDir: home);
    expect(r.tree, isNull);
    expect(r.reason, contains('不是 git 仓库'));
  });
}
