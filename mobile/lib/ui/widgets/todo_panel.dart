import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/theme/aurora_theme.dart';
import 'glass_card.dart';

const todoSourceLabels = <String, String>{
  'voice': '你说的',
  'session': '会话遗留',
  'agent': 'AI 记的',
  'mcp': 'AI 记的',
  'manual': '手动',
};

enum TodoDue { overdue, today, soon, later, none }

/// Where a due date (YYYY-MM-DD) stands relative to [today].
TodoDue todoDueState(String? due, DateTime today) {
  final d = due == null ? null : DateTime.tryParse(due);
  if (d == null) return TodoDue.none;
  final day = DateTime(today.year, today.month, today.day);
  final diff = DateTime(d.year, d.month, d.day).difference(day).inDays;
  if (diff < 0) return TodoDue.overdue;
  if (diff == 0) return TodoDue.today;
  if (diff <= 3) return TodoDue.soon;
  return TodoDue.later;
}

String todoDueText(String due, DateTime today) {
  final d = DateTime.parse(due);
  return switch (todoDueState(due, today)) {
    TodoDue.overdue => '逾期 ${DateTime(today.year, today.month, today.day).difference(d).inDays} 天',
    TodoDue.today => '今天到期',
    _ => '${d.month}-${d.day} 到期',
  };
}

/// Things the user said they'd do later — picked up from what they typed to their
/// AIs, left over by sessions, or added here — with done / drop / edit.
class TodoPanel extends StatefulWidget {
  const TodoPanel({super.key});

  @override
  State<TodoPanel> createState() => TodoPanelState();
}

class TodoPanelState extends State<TodoPanel> {
  final _api = ApiClient();
  List<Map<String, dynamic>> _open = const [];
  List<Map<String, dynamic>> _closed = const [];
  bool _loaded = false;
  bool _unsupported = false;
  bool _showClosed = false;
  String? _busy;
  String? _error;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    try {
      final data = await _api.getTodos();
      if (!mounted) return;
      setState(() {
        _open = ((data['open'] as List?) ?? const []).cast<Map<String, dynamic>>();
        _closed = ((data['closed'] as List?) ?? const []).cast<Map<String, dynamic>>();
        _loaded = true;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loaded = true;
        _unsupported = e is DioException && e.response?.statusCode == 404;
        _error = _unsupported ? null : '读取待办失败：${e is DioException ? (e.message ?? e.type.name) : e}';
      });
    }
  }

  Future<void> _update(Map<String, dynamic> todo, Map<String, dynamic> fields) async {
    setState(() => _busy = todo['id'] as String);
    try {
      await _api.updateTodo(todo['id'] as String, fields);
      await reload();
    } catch (e) {
      if (mounted) setState(() => _error = '保存失败：$e');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<String?> _pickDate(String? current) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(current ?? '') ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (picked == null) return null;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${picked.year}-${two(picked.month)}-${two(picked.day)}';
  }

  Future<void> _add() async {
    final title = TextEditingController();
    final project = TextEditingController();
    String? due;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: AuroraColors.surfaceSolid,
          title: const Text('新建待办', style: TextStyle(fontSize: 16)),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  autofocus: true,
                  decoration: const InputDecoration(hintText: '要做什么，如「给导出接口加分页」'),
                ),
                const SizedBox(height: 10),
                TextField(controller: project, decoration: const InputDecoration(hintText: '项目（可选）')),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(due == null ? '没有截止日期' : '截止 $due',
                        style: const TextStyle(fontSize: 13, color: AuroraColors.fg2)),
                    const Spacer(),
                    TextButton(
                      onPressed: () async {
                        final picked = await _pickDate(due);
                        if (picked != null) setLocal(() => due = picked);
                      },
                      child: const Text('选日期'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('添加')),
          ],
        ),
      ),
    );
    final text = title.text.trim();
    final proj = project.text.trim();
    title.dispose();
    project.dispose();
    if (ok != true || text.isEmpty) return;
    setState(() => _busy = 'add');
    try {
      await _api.addTodo(text, due: due, project: proj.isEmpty ? null : proj);
      await reload();
    } catch (e) {
      if (mounted) setState(() => _error = '添加失败：$e');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _unsupported) return const SizedBox.shrink();
    final today = DateTime.now();
    final overdue = _open.where((t) => todoDueState(t['due'] as String?, today) == TodoDue.overdue).length;
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.checklist_rounded, size: 18, color: AuroraColors.accent),
              const SizedBox(width: 8),
              Text('待办 ${_open.length}',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AuroraColors.fg1)),
              if (overdue > 0) ...[
                const SizedBox(width: 8),
                Text('$overdue 条逾期', style: const TextStyle(fontSize: 12, color: AuroraColors.danger)),
              ],
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.add_rounded, size: 20),
                tooltip: '新建待办',
                onPressed: _busy != null ? null : _add,
              ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6, right: 8),
              child: Text(_error!, style: const TextStyle(fontSize: 12, color: AuroraColors.danger)),
            ),
          if (_open.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(0, 2, 8, 6),
              child: Text(
                '没有待办。你在 AI 工具里说"明天再弄""记一下…"，或者会话结束时还有没做完的事，都会自动出现在这里。',
                style: TextStyle(fontSize: 12.5, color: AuroraColors.fg3, height: 1.5),
              ),
            ),
          for (final todo in _open) _item(todo, today),
          if (_closed.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _showClosed = !_showClosed),
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4)),
                child: Text(_showClosed ? '收起最近完成的' : '最近完成的 ${_closed.length} 条',
                    style: const TextStyle(fontSize: 12.5)),
              ),
            ),
          if (_showClosed) for (final todo in _closed) _item(todo, today, closed: true),
        ],
      ),
    );
  }

  Widget _item(Map<String, dynamic> todo, DateTime today, {bool closed = false}) {
    final due = todo['due'] as String?;
    final state = todoDueState(due, today);
    final busy = _busy == todo['id'];
    final evidence = (closed ? todo['close_evidence'] : todo['evidence'])?.toString();
    final meta = <String>[
      todoSourceLabels[todo['source']] ?? '${todo['source']}',
      if ((todo['project'] ?? '').toString().isNotEmpty) '${todo['project']}',
      if (closed) (todo['status'] == 'dropped' ? '不做了' : '已完成'),
    ];
    final dueColor = switch (state) {
      TodoDue.overdue => AuroraColors.danger,
      TodoDue.today => AuroraColors.warnText,
      _ => AuroraColors.fg3,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: busy
                ? const Padding(padding: EdgeInsets.all(9), child: CircularProgressIndicator(strokeWidth: 2))
                : Checkbox(
                    value: closed,
                    onChanged: _busy != null
                        ? null
                        : (v) => _update(todo, {'status': v == true ? 'done' : 'open'}),
                  ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Tooltip(
                    message: evidence == null || evidence.isEmpty ? '' : evidence,
                    child: Text(
                      todo['title'].toString(),
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.4,
                        color: closed ? AuroraColors.fg3 : AuroraColors.fgBody,
                        decoration: closed ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text.rich(
                    TextSpan(children: [
                      if (due != null && !closed)
                        TextSpan(text: '${todoDueText(due, today)} · ', style: TextStyle(color: dueColor)),
                      TextSpan(text: meta.join(' · ')),
                    ]),
                    style: const TextStyle(fontSize: 11.5, color: AuroraColors.fg3),
                  ),
                ],
              ),
            ),
          ),
          if (!closed)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz_rounded, size: 18, color: AuroraColors.fg3),
              color: AuroraColors.surfaceSolid,
              enabled: _busy == null,
              onSelected: (action) async {
                if (action == 'drop') {
                  await _update(todo, {'status': 'dropped'});
                } else if (action == 'due') {
                  final picked = await _pickDate(due);
                  if (picked != null) await _update(todo, {'due': picked});
                } else if (action == 'clear_due') {
                  await _update(todo, {'due': ''});
                }
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(value: 'due', child: Text('设截止日期')),
                if (due != null) const PopupMenuItem(value: 'clear_due', child: Text('去掉截止日期')),
                const PopupMenuItem(value: 'drop', child: Text('不做了')),
              ],
            ),
        ],
      ),
    );
  }
}
