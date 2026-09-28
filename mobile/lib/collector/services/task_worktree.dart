import 'dart:io';

import 'package:path/path.dart' as p;

/// A git worktree and branch of its own for one agent task, so tasks running in
/// parallel on the same repository can't overwrite each other's changes.
///
/// Lives outside the repository (~/.memento/worktrees/<repo>-<task>), on branch
/// memento/<task>. A task that changed nothing leaves no trace; one that did
/// keeps its branch for the user to review and merge.
class TaskWorktree {
  final String repoRoot;
  final String path;
  final String branch;
  final String baseSha;

  /// Where the agent runs: the same subdirectory of the repository it was sent to.
  final String workDir;

  TaskWorktree._(this.repoRoot, this.path, this.branch, this.baseSha, this.workDir);

  static Future<ProcessResult> _git(List<String> args, {String? cwd, Map<String, String>? env}) =>
      Process.run('git', args, workingDirectory: cwd, environment: env, runInShell: Platform.isWindows);

  /// Sets one up for `dir`, or explains why the task runs in place instead.
  static Future<({TaskWorktree? tree, String? reason})> create(
    String dir,
    String taskId, {
    Map<String, String>? env,
    String? homeDir,
  }) async {
    final top = await _git(['rev-parse', '--show-toplevel'], cwd: dir, env: env);
    if (top.exitCode != 0) return (tree: null, reason: '不是 git 仓库，直接在原目录运行');
    final root = p.normalize(top.stdout.toString().trim());
    final head = await _git(['rev-parse', 'HEAD'], cwd: root, env: env);
    if (head.exitCode != 0) return (tree: null, reason: '仓库还没有任何提交，直接在原目录运行');
    final base = head.stdout.toString().trim();

    final short = taskId.replaceAll('-', '');
    final id = short.length > 8 ? short.substring(0, 8) : short;
    final home = homeDir ?? Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? Directory.systemTemp.path;
    final path = p.join(home, '.memento', 'worktrees', '${p.basename(root)}-$id');
    final branch = 'memento/$id';
    await Directory(p.dirname(path)).create(recursive: true);

    final add = await _git(['worktree', 'add', '-b', branch, path, base], cwd: root, env: env);
    if (add.exitCode != 0) {
      return (tree: null, reason: '创建 worktree 失败，直接在原目录运行：${add.stderr.toString().trim()}');
    }
    // git reports the real path (/private/var/... on macOS); compare like with like.
    String real(String path) {
      try {
        return Directory(path).resolveSymbolicLinksSync();
      } catch (_) {
        return p.normalize(path);
      }
    }
    final rel = p.relative(real(dir), from: real(root));
    final workDir = rel == '.' || rel.startsWith('..') ? path : p.join(path, rel);
    return (tree: TaskWorktree._(root, path, branch, base, workDir), reason: null);
  }

  /// What the task left behind. Removes the worktree and branch when that's nothing.
  Future<Map<String, dynamic>> finish({Map<String, String>? env}) async {
    final status = await _git(['status', '--porcelain'], cwd: path, env: env);
    final changed = <String>{
      for (final line in status.stdout.toString().split('\n'))
        if (line.trim().length > 3) line.substring(3).trim(),
    };
    final diff = await _git(['diff', '--name-only', baseSha, 'HEAD'], cwd: path, env: env);
    changed.addAll(diff.stdout.toString().split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty));
    final count = await _git(['rev-list', '--count', '$baseSha..HEAD'], cwd: path, env: env);
    final commits = int.tryParse(count.stdout.toString().trim()) ?? 0;

    if (changed.isEmpty && commits == 0) {
      await _git(['worktree', 'remove', '--force', path], cwd: repoRoot, env: env);
      await _git(['branch', '-D', branch], cwd: repoRoot, env: env);
      return {'kind': 'worktree', 'status': 'removed', 'branch': branch};
    }
    final files = changed.toList()..sort();
    return {
      'kind': 'worktree',
      'status': 'kept',
      'branch': branch,
      'path': path,
      'repo': repoRoot,
      'commits': commits,
      'files': files.take(30).toList(),
      'file_count': files.length,
    };
  }
}
