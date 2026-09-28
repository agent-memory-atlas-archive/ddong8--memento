import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/aurora_theme.dart';

/// What a Claude Code / Codex tool does, in the user's words.
(IconData, String) taskToolLook(String? name) => switch (name) {
      'Bash' || 'BashOutput' || 'Shell' => (Icons.terminal_rounded, '运行命令'),
      'Read' => (Icons.description_outlined, '读取'),
      'Write' => (Icons.note_add_outlined, '新建文件'),
      'Edit' || 'MultiEdit' || 'NotebookEdit' => (Icons.edit_note_rounded, '修改'),
      'Grep' || 'Glob' => (Icons.search_rounded, '查找'),
      'WebSearch' => (Icons.travel_explore_rounded, '搜索网页'),
      'WebFetch' => (Icons.public_rounded, '打开网页'),
      'Task' || 'Agent' => (Icons.hub_outlined, '派子任务'),
      'TodoWrite' => (Icons.checklist_rounded, '更新待办'),
      _ => (Icons.extension_outlined, name ?? '工具'),
    };

/// "12 步 · $0.21 · 3 分 4 秒" from the run's usage event and tool steps.
String taskRunSummary(List<Map<String, dynamic>> events) {
  final steps = events.where((e) => e['kind'] == 'tool').length;
  final usage = events.lastWhere((e) => e['kind'] == 'usage', orElse: () => const {});
  final parts = <String>['$steps 步'];
  final cost = usage['cost_usd'];
  if (cost is num && cost > 0) parts.add('\$${cost < 0.01 ? cost.toStringAsFixed(3) : cost.toStringAsFixed(2)}');
  final ms = usage['duration_ms'];
  if (ms is num && ms > 0) {
    final s = (ms / 1000).round();
    parts.add(s >= 60 ? '${s ~/ 60} 分 ${s % 60} 秒' : '$s 秒');
  }
  return parts.join(' · ');
}

/// The steps of a structured agent run: tool calls as they happen, follow-ups,
/// the worktree it ran in, and what it cost.
class TaskTimeline extends StatefulWidget {
  final List<Map<String, dynamic>> events;
  final bool running;

  const TaskTimeline({super.key, required this.events, required this.running});

  @override
  State<TaskTimeline> createState() => _TaskTimelineState();
}

class _TaskTimelineState extends State<TaskTimeline> {
  static const _collapsedCount = 6;
  bool _showAll = false;
  String? _openTool;

  static const _mono = TextStyle(
    fontFamily: 'monospace',
    fontFamilyFallback: AuroraTheme.monospaceFontFamilyFallback,
    fontSize: 12,
    height: 1.5,
  );

  @override
  Widget build(BuildContext context) {
    final rows = widget.events.where((e) => e['kind'] != 'usage' && e['kind'] != 'session').toList();
    final kept = widget.events.lastWhere(
      (e) => e['kind'] == 'worktree' && e['status'] == 'kept',
      orElse: () => const {},
    );
    final hidden = !_showAll && rows.length > _collapsedCount ? rows.length - _collapsedCount : 0;
    final visible = hidden > 0 ? rows.sublist(hidden) : rows;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AuroraColors.well,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AuroraColors.chip),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text('过程', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AuroraColors.fg2)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(taskRunSummary(widget.events),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AuroraColors.fg3)),
              ),
              if (rows.length > _collapsedCount)
                InkWell(
                  onTap: () => setState(() => _showAll = !_showAll),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Text(_showAll ? '只看最近' : '全部 ${rows.length} 条',
                        style: const TextStyle(fontSize: 12, color: AuroraColors.accent)),
                  ),
                ),
            ],
          ),
          if (hidden > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('… 前面还有 $hidden 条', style: const TextStyle(fontSize: 11.5, color: AuroraColors.fg4)),
            ),
          const SizedBox(height: 4),
          for (final e in visible) _row(e),
          if (kept.isNotEmpty) ...[
            const SizedBox(height: 8),
            _worktreeKept(kept),
          ],
        ],
      ),
    );
  }

  Widget _row(Map<String, dynamic> e) {
    switch (e['kind']) {
      case 'tool':
        final (icon, label) = taskToolLook(e['name']?.toString());
        final status = e['status']?.toString();
        final id = e['id']?.toString();
        final output = e['output']?.toString() ?? '';
        final open = id != null && _openTool == id && output.isNotEmpty;
        return InkWell(
          onTap: output.isEmpty ? null : () => setState(() => _openTool = open ? null : id),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 14, color: AuroraColors.fg3),
                    const SizedBox(width: 8),
                    Text(label, style: const TextStyle(fontSize: 12.5, color: AuroraColors.fg2)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(e['detail']?.toString() ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _mono.copyWith(color: AuroraColors.fgCode)),
                    ),
                    const SizedBox(width: 8),
                    _status(status),
                  ],
                ),
                if (open)
                  Container(
                    margin: const EdgeInsets.only(top: 6, left: 22),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: AuroraColors.terminal, borderRadius: BorderRadius.circular(6)),
                    child: SelectableText(output, style: _mono.copyWith(fontSize: 11.5, color: AuroraColors.fg2)),
                  ),
              ],
            ),
          ),
        );
      case 'steer':
        final status = e['status']?.toString();
        final note = switch (status) {
          'late' => '任务已结束，没来得及送达',
          'unsupported' => '这个 agent 不支持中途补充，等它做完后续接再说',
          _ => '已送达，会在下一步读到',
        };
        return _plain(Icons.subdirectory_arrow_right_rounded, '你补充：${e['text']}', note,
            color: status == 'sent' ? AuroraColors.accent : AuroraColors.warn);
      case 'worktree':
        final status = e['status']?.toString();
        return switch (status) {
          'created' => _plain(Icons.call_split_rounded, '在独立分支 ${e['branch']} 上运行', null),
          'removed' => _plain(Icons.call_split_rounded, '没有改动，已清理独立分支', null),
          'skipped' => _plain(Icons.call_split_rounded, '没用独立分支', e['reason']?.toString(), color: AuroraColors.warn),
          _ => const SizedBox.shrink(),
        };
      case 'error':
        return _plain(Icons.error_outline_rounded, e['message']?.toString() ?? '出错', null, color: AuroraColors.danger);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _plain(IconData icon, String text, String? note, {Color color = AuroraColors.fg3}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 14, color: color)),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: text, style: const TextStyle(color: AuroraColors.fgBody)),
                  if (note != null) TextSpan(text: '  $note', style: const TextStyle(color: AuroraColors.fg3)),
                ]),
                style: const TextStyle(fontSize: 12.5, height: 1.45),
              ),
            ),
          ],
        ),
      );

  Widget _status(String? status) {
    if (status == 'running' && widget.running) {
      return const SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(strokeWidth: 1.5, color: AuroraColors.accent),
      );
    }
    return switch (status) {
      'failed' => const Icon(Icons.close_rounded, size: 14, color: AuroraColors.danger),
      'running' => const Icon(Icons.more_horiz_rounded, size: 14, color: AuroraColors.fg4),
      _ => const Icon(Icons.check_rounded, size: 14, color: AuroraColors.success),
    };
  }

  Widget _worktreeKept(Map<String, dynamic> e) {
    final branch = e['branch']?.toString() ?? '';
    final files = (e['file_count'] as num?)?.toInt() ?? 0;
    final commits = (e['commits'] as num?)?.toInt() ?? 0;
    final merge = 'git merge $branch';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AuroraColors.accentSoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '改动留在独立分支 $branch：$files 个文件${commits > 0 ? '，$commits 个提交' : '（还没提交）'}',
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AuroraColors.fg1),
          ),
          const SizedBox(height: 2),
          Text('目录 ${e['path']}', style: _mono.copyWith(fontSize: 11.5, color: AuroraColors.fg3)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: Text('看过没问题就在原仓库里合并：$merge', style: const TextStyle(fontSize: 12, color: AuroraColors.fg2))),
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: merge));
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                    const SnackBar(content: Text('已复制合并命令'), duration: Duration(seconds: 2), behavior: SnackBarBehavior.floating),
                  );
                },
                borderRadius: BorderRadius.circular(6),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.copy_rounded, size: 14, color: AuroraColors.accent),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
