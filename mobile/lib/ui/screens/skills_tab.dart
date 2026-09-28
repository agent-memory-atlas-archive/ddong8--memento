import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/theme/aurora_theme.dart';
import '../widgets/app_markdown.dart';
import '../widgets/aurora_shimmer.dart';
import '../widgets/glass_card.dart';

const skillStatusLabels = <String, String>{
  'draft': '待确认',
  'published': '已发布',
  'dismissed': '已忽略',
  'retired': '已停用',
};

const reviewOutcomeLabels = <String, String>{
  'done': '完成',
  'partial': '做了一部分',
  'failed': '没做成',
  'chat': '聊天',
  'error': '复盘出错',
  'unknown': '未知',
};

/// Per-device skill write results collapsed into counts by outcome kind.
Map<String, int> skillResultCounts(Map<String, dynamic>? results) {
  final counts = <String, int>{};
  for (final v in (results ?? const {}).values) {
    final s = v.toString();
    final kind = s.startsWith('error')
        ? 'error'
        : s.startsWith('skipped')
            ? 'skipped'
            : s.startsWith('kept')
                ? 'kept'
                : (s == 'removed' ? 'removed' : 'ok');
    counts[kind] = (counts[kind] ?? 0) + 1;
  }
  return counts;
}

/// One line saying what a session review taught.
String reviewLearned(Map<String, dynamic> result) {
  final parts = <String>[];
  if (result['skill'] != null) {
    parts.add(switch (result['skill_event']) {
      'new' => '新技能 ${result['skill']}',
      'update_pending' => '技能 ${result['skill']} 有改进',
      _ => '又用到 ${result['skill']}',
    });
  }
  final pitfalls = (result['pitfalls_new'] as num?)?.toInt() ?? 0;
  if (pitfalls > 0) parts.add('$pitfalls 个坑');
  final seen = ((result['pitfalls_seen'] as List?) ?? const []).length;
  if (seen > 0) parts.add('又踩了 $seen 个老坑');
  final todos = (result['todos_new'] as num?)?.toInt() ?? 0;
  if (todos > 0) parts.add('$todos 条待办');
  final done = (result['todos_done'] as num?)?.toInt() ?? 0;
  if (done > 0) parts.add('完成 $done 条待办');
  return parts.isEmpty ? '没有新东西' : parts.join(' · ');
}

class SkillsTab extends StatefulWidget {
  const SkillsTab({super.key});

  @override
  State<SkillsTab> createState() => _SkillsTabState();
}

class _SkillsTabState extends State<SkillsTab> with AutomaticKeepAliveClientMixin {
  final _api = ApiClient();
  Map<String, dynamic>? _data;
  Map<String, dynamic>? _reviews;
  String? _error;
  String? _notice;
  String? _busy; // skill id, or "review"
  final _expanded = <String>{};
  Timer? _poll;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  List<Map<String, dynamic>> _list(String key) =>
      ((_data?[key] as List?) ?? const []).cast<Map<String, dynamic>>();

  Map<String, dynamic>? get _job => _reviews?['job'] as Map<String, dynamic>?;
  bool get _reviewRunning => _job?['status'] == 'running';

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _api.getSkills(),
        _api.getReviews().catchError((_) => <String, dynamic>{}),
      ]);
      if (!mounted) return;
      setState(() {
        _data = results[0];
        _reviews = results[1];
        _error = null;
      });
      if (_reviewRunning) _startPolling();
    } catch (e) {
      if (mounted) setState(() => _error = _describe(e));
    }
  }

  void _startPolling() {
    _poll ??= Timer.periodic(const Duration(seconds: 5), (_) async {
      final wasRunning = _reviewRunning;
      await _load();
      if (!_reviewRunning) {
        _poll?.cancel();
        _poll = null;
        if (wasRunning && mounted) setState(() => _notice = _jobSummary());
      }
    });
  }

  String _jobSummary() {
    final job = _job;
    if (job == null) return '';
    if (job['status'] == 'error') return '复盘出错：${job['error'] ?? ''}';
    final sessions = ((job['result'] as Map?)?['sessions'] as Map?) ?? const {};
    final reviewed = sessions['reviewed'] ?? 0;
    final skills = ((sessions['skills_new'] as List?) ?? const []).length;
    final pitfalls = sessions['pitfalls_new'] ?? 0;
    final todos = sessions['todos_new'] ?? 0;
    if (reviewed == 0) return '复盘完成：最近没有新的、已经结束的会话。';
    return '复盘了 $reviewed 个会话：$skills 个新技能、$pitfalls 个坑、$todos 条待办。';
  }

  String _describe(Object e) {
    if (e is DioException) {
      final detail = e.response?.data is Map ? (e.response!.data as Map)['detail'] : null;
      if (detail != null) return detail.toString();
      final code = e.response?.statusCode;
      if (code == 404) return '服务端版本太旧，还没有技能功能。';
      if (code != null && code >= 500) return '服务端出错（$code），稍后再试。';
      return switch (e.type) {
        DioExceptionType.connectionError || DioExceptionType.connectionTimeout => '连不上服务端，检查网络后再试。',
        _ => e.message ?? e.toString(),
      };
    }
    return e.toString();
  }

  Future<void> _act(String id, Future<void> Function() action, {String? done}) async {
    setState(() {
      _busy = id;
      _notice = null;
    });
    try {
      await action();
      if (done != null) _notice = done;
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = _describe(e));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _reviewNow() async {
    setState(() {
      _busy = 'review';
      _notice = null;
    });
    try {
      await _api.startReview();
      setState(() => _notice = '正在复盘最近结束的会话，通常要几分钟，可以先做别的。');
      await _load();
      _startPolling();
    } catch (e) {
      if (mounted) setState(() => _error = _describe(e));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  static String _time(String? iso) {
    final t = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
    if (t == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.month}-${t.day} ${two(t.hour)}:${two(t.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_data == null && _error == null) return const AuroraListSkeleton(count: 3, itemHeight: 140);
    final drafts = _list('drafts');
    final published = _list('published');
    final archived = _list('archived');

    return RefreshIndicator(
      onRefresh: _load,
      color: AuroraColors.accent,
      child: LayoutBuilder(
        builder: (context, constraints) => ListView(
          padding: EdgeInsets.symmetric(
            horizontal: math.max(16, (constraints.maxWidth - 880) / 2),
            vertical: 12,
          ),
          children: [
            if (_error != null) _banner(_error!, AuroraColors.danger, Icons.error_outline_rounded),
            if (_notice != null && _notice!.isNotEmpty) _banner(_notice!, AuroraColors.fg2, Icons.info_outline_rounded),
            _buildIntro(drafts.length, published.length),
            if (drafts.isNotEmpty) ...[
              const SizedBox(height: 14),
              _group('待确认', '${drafts.length} 个，从你做成的事里总结出来', AuroraColors.accent, drafts),
            ],
            if (published.isNotEmpty) ...[
              const SizedBox(height: 14),
              _group('已发布', '${published.length} 个，AI 遇到同类任务会照着做', AuroraColors.success, published),
            ],
            if (drafts.isEmpty && published.isEmpty) ...[
              const SizedBox(height: 14),
              _empty(),
            ],
            if (archived.isNotEmpty) ...[
              const SizedBox(height: 14),
              _buildArchived(archived),
            ],
            const SizedBox(height: 14),
            _buildReviews(),
            if (_list('devices').isNotEmpty) ...[
              const SizedBox(height: 14),
              _buildDevices(),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _banner(String text, Color color, IconData icon) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 16, color: color)),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: color, height: 1.45))),
          ],
        ),
      );

  Widget _pill(String text, Color color) => Container(
        height: 22,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
      );

  Widget _buildIntro(int drafts, int published) {
    final running = _reviewRunning;
    final lastRun = _job?['finished_at'] as String?;
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_fix_high_rounded, size: 18, color: AuroraColors.accent),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('技能', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AuroraColors.fg1)),
              ),
              FilledButton.tonalIcon(
                onPressed: running || _busy != null ? null : _reviewNow,
                icon: running
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.replay_rounded, size: 16),
                label: Text(running ? '复盘中…' : '立即复盘'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '每晚复盘你结束的会话，把做成过的多步骤流程总结成技能。发布后写进 Claude Code（~/.claude/skills）和 '
            'Codex / Gemini（~/.agents/skills），AI 遇到同类任务就照着做，不用再摸索。写进哪些工具，跟「常驻画像」里各设备的开关一致。',
            style: TextStyle(fontSize: 12.5, color: AuroraColors.fg3, height: 1.55),
          ),
          if (lastRun != null && !running) ...[
            const SizedBox(height: 6),
            Text('上次手动复盘：${_time(lastRun)}', style: const TextStyle(fontSize: 12, color: AuroraColors.fg3)),
          ],
        ],
      ),
    );
  }

  Widget _empty() => const GlassCard(
        padding: EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(Icons.lightbulb_outline_rounded, size: 28, color: AuroraColors.fg3),
            SizedBox(height: 8),
            Text('还没有技能', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AuroraColors.fg1)),
            SizedBox(height: 4),
            Text(
              '做成一件多步骤的事（部署、发版、排障）之后，当晚复盘就会总结成技能等你确认。也可以点「立即复盘」。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: AuroraColors.fg3, height: 1.5),
            ),
          ],
        ),
      );

  Widget _group(String label, String caption, Color color, List<Map<String, dynamic>> skills) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _pill(label, color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(caption,
                    overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AuroraColors.fg3)),
              ),
            ],
          ),
          for (final (i, skill) in skills.indexed) ...[
            if (i > 0)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(height: 1, thickness: 1, color: AuroraColors.chip),
              )
            else
              const SizedBox(height: 12),
            _skillItem(skill),
          ],
        ],
      ),
    );
  }

  Widget _skillItem(Map<String, dynamic> skill) {
    final id = skill['id'] as String;
    final status = skill['status'] as String? ?? 'draft';
    final expanded = _expanded.contains(id);
    final disabled = _busy != null;
    final busy = _busy == id;
    final evidence = ((skill['evidence'] as List?) ?? const []).cast<Map>();
    final update = skill['pending_update'] as Map<String, dynamic>?;
    final meta = <String>[
      if ((skill['project'] ?? '').toString().isNotEmpty) '${skill['project']}',
      if (status == 'published') 'v${skill['version']}',
      '出现 ${skill['times_seen'] ?? 1} 次',
      if (skill['last_seen_at'] != null) '最近 ${_time(skill['last_seen_at'] as String?)}',
      if (skill['edited_by_user'] == true) '你改过',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(skill['title'].toString(),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AuroraColors.fg1)),
        const SizedBox(height: 3),
        Text(
          '/${skill['slug']}  ·  ${meta.join(' · ')}',
          style: const TextStyle(
              fontSize: 12, color: AuroraColors.fg3, fontFamilyFallback: AuroraTheme.monospaceFontFamilyFallback),
        ),
        const SizedBox(height: 8),
        SelectableText(skill['description'].toString(),
            style: const TextStyle(fontSize: 13.5, height: 1.55, color: AuroraColors.fgBody)),
        if (update != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AuroraColors.warnSoft,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AuroraColors.warn.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('新的会话里发现了改进：${update['reason'] ?? ''}',
                    style: const TextStyle(fontSize: 12.5, color: AuroraColors.warnText, height: 1.45)),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: disabled ? null : () => _act(id, () => _api.skillAction(id, 'update/discard')),
                      child: const Text('不要'),
                    ),
                    const SizedBox(width: 6),
                    OutlinedButton(
                      onPressed: disabled ? null : () => _showUpdate(skill),
                      child: const Text('看看'),
                    ),
                    const SizedBox(width: 6),
                    FilledButton(
                      onPressed: disabled
                          ? null
                          : () => _act(id, () => _api.skillAction(id, 'update/apply'), done: '已采用改进，发布了新版本。'),
                      child: const Text('采用'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => expanded ? _expanded.remove(id) : _expanded.add(id)),
            icon: Icon(expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 18),
            label: Text(expanded ? '收起步骤' : '查看步骤'),
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4)),
          ),
        ),
        if (expanded) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AuroraColors.well, borderRadius: BorderRadius.circular(8)),
            child: AppMarkdown(data: skill['body'].toString()),
          ),
          if (evidence.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final e in evidence.reversed.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text('来自会话：${e['title'] ?? ''}（${e['tool_id'] ?? ''}，${_time(e['at'] as String?)}）',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AuroraColors.fg3)),
              ),
          ],
        ],
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            if (status == 'draft') ...[
              TextButton(
                onPressed: disabled ? null : () => _act(id, () => _api.skillAction(id, 'dismiss')),
                child: const Text('不要'),
              ),
              OutlinedButton(onPressed: disabled ? null : () => _edit(skill), child: const Text('编辑')),
              FilledButton(
                onPressed: disabled
                    ? null
                    : () => _act(id, () => _api.publishSkill(id), done: '已发布：各设备 5 分钟内写进 AI 工具的技能目录。'),
                child: busy
                    ? const SizedBox(
                        width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AuroraColors.onAccent))
                    : const Text('发布'),
              ),
            ],
            if (status == 'published') ...[
              TextButton(
                onPressed: disabled
                    ? null
                    : () => _act(id, () => _api.skillAction(id, 'retire'), done: '已停用：各设备下次同步时移除。'),
                child: const Text('停用'),
              ),
              OutlinedButton(onPressed: disabled ? null : () => _edit(skill), child: const Text('编辑')),
            ],
          ],
        ),
      ],
    );
  }

  Future<void> _showUpdate(Map<String, dynamic> skill) async {
    final update = skill['pending_update'] as Map<String, dynamic>;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AuroraColors.surfaceSolid,
        title: Text('「${skill['title']}」的改进版', style: const TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 720,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(update['reason']?.toString() ?? '',
                    style: const TextStyle(fontSize: 13, color: AuroraColors.warnText, height: 1.5)),
                const SizedBox(height: 10),
                Text(update['description']?.toString() ?? '',
                    style: const TextStyle(fontSize: 13, color: AuroraColors.fgBody, height: 1.5)),
                const SizedBox(height: 10),
                AppMarkdown(data: update['body']?.toString() ?? ''),
              ],
            ),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭'))],
      ),
    );
  }

  Future<void> _edit(Map<String, dynamic> skill) async {
    final title = TextEditingController(text: skill['title']?.toString() ?? '');
    final slug = TextEditingController(text: skill['slug']?.toString() ?? '');
    final description = TextEditingController(text: skill['description']?.toString() ?? '');
    final body = TextEditingController(text: skill['body']?.toString() ?? '');
    final isDraft = skill['status'] == 'draft';
    InputDecoration deco(String label, [String? hint]) =>
        InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder(), isDense: true);

    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AuroraColors.surfaceSolid,
        title: const Text('编辑技能', style: TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 760,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(controller: title, decoration: deco('名称')),
                const SizedBox(height: 10),
                TextField(
                  controller: slug,
                  decoration: deco('命令名', '小写字母、数字和连字符，如 memento-deploy'),
                  style: const TextStyle(fontFamilyFallback: AuroraTheme.monospaceFontFamilyFallback),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: description,
                  minLines: 2,
                  maxLines: 4,
                  decoration: deco('什么时候用', 'AI 靠这句话判断要不要用这个技能'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: body,
                  minLines: 12,
                  maxLines: 24,
                  style: const TextStyle(
                      fontSize: 13, height: 1.5, fontFamilyFallback: AuroraTheme.monospaceFontFamilyFallback),
                  decoration: deco('步骤（Markdown）'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          if (isDraft) OutlinedButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('保存')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'publish'),
            child: Text(isDraft ? '保存并发布' : '保存（发布新版本）'),
          ),
        ],
      ),
    );
    final edits = {
      'title': title.text.trim(),
      'slug': slug.text.trim(),
      'description': description.text.trim(),
      'body': body.text,
    };
    for (final c in [title, slug, description, body]) {
      c.dispose();
    }
    if (choice == null) return;
    final id = skill['id'] as String;
    if (choice == 'publish' && isDraft) {
      await _act(id, () => _api.publishSkill(id, edits: edits), done: '已发布：各设备 5 分钟内写进 AI 工具的技能目录。');
    } else {
      await _act(id, () => _api.editSkill(id, edits), done: isDraft ? '已保存。' : '已保存并发布新版本。');
    }
  }

  Widget _buildArchived(List<Map<String, dynamic>> archived) => GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('不要的和停用的（${archived.length}）',
                style: const TextStyle(fontSize: 13.5, color: AuroraColors.fg2)),
            children: [
              for (final s in archived)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(s['title'].toString(), style: const TextStyle(fontSize: 13.5, color: AuroraColors.fgBody)),
                  subtitle: Text('${skillStatusLabels[s['status']] ?? s['status']} · /${s['slug']}',
                      style: const TextStyle(fontSize: 12, color: AuroraColors.fg3)),
                  trailing: TextButton(
                    onPressed: _busy != null
                        ? null
                        : () => _act(s['id'] as String, () => _api.skillAction(s['id'] as String, 'restore'),
                            done: '已恢复为待确认。'),
                    child: const Text('恢复'),
                  ),
                ),
            ],
          ),
        ),
      );

  Widget _buildReviews() {
    final reviews = ((_reviews?['reviews'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final stats = (_reviews?['stats'] as Map?)?.cast<String, dynamic>() ?? const {};
    final outcomes = (stats['outcomes'] as Map?)?.cast<String, dynamic>() ?? const {};
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('最近的复盘', style: TextStyle(fontSize: 13.5, color: AuroraColors.fg2)),
          subtitle: Text(
            reviews.isEmpty
                ? '还没有复盘过的会话'
                : '近 7 天 ${stats['sessions'] ?? 0} 个会话：完成 ${outcomes['done'] ?? 0} · 部分 ${outcomes['partial'] ?? 0} · 没做成 ${outcomes['failed'] ?? 0}',
            style: const TextStyle(fontSize: 12, color: AuroraColors.fg3),
          ),
          children: [
            for (final r in reviews.take(20))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _pill(reviewOutcomeLabels[r['outcome']] ?? '${r['outcome']}',
                            switch (r['outcome']) {
                              'done' => AuroraColors.success,
                              'failed' || 'error' => AuroraColors.danger,
                              'partial' => AuroraColors.warn,
                              _ => AuroraColors.fg3,
                            }),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(r['title']?.toString() ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13, color: AuroraColors.fgBody)),
                        ),
                        Text(_time(r['reviewed_at'] as String?),
                            style: const TextStyle(fontSize: 11.5, color: AuroraColors.fg3)),
                      ],
                    ),
                    if ((r['summary'] ?? '').toString().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(r['summary'].toString(),
                            style: const TextStyle(fontSize: 12.5, color: AuroraColors.fg2, height: 1.45)),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('学到：${reviewLearned((r['result'] as Map?)?.cast<String, dynamic>() ?? const {})}',
                          style: const TextStyle(fontSize: 12, color: AuroraColors.fg3)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDevices() {
    final devices = _list('devices');
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('各设备写入情况',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AuroraColors.fg1)),
          const SizedBox(height: 8),
          for (final d in devices)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(
                    child: Text(d['name'].toString(),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: AuroraColors.fgBody)),
                  ),
                  Text(_deviceSummary(d), style: const TextStyle(fontSize: 12, color: AuroraColors.fg3)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _deviceSummary(Map<String, dynamic> device) {
    final targets = ((device['targets'] as List?) ?? const []);
    if (targets.isEmpty) return '没有开启任何工具（在「常驻画像」里开）';
    final status = (device['status'] as Map?)?.cast<String, dynamic>() ?? const {};
    final results = (status['results'] as Map?)?.cast<String, dynamic>();
    if (results == null) return '等待设备同步';
    final c = skillResultCounts(results);
    final parts = <String>[
      if ((c['ok'] ?? 0) > 0) '已写入 ${c['ok']}',
      if ((c['kept'] ?? 0) > 0) '本地改过 ${c['kept']}',
      if ((c['skipped'] ?? 0) > 0) '跳过 ${c['skipped']}',
      if ((c['error'] ?? 0) > 0) '出错 ${c['error']}',
    ];
    return '${parts.isEmpty ? '没有技能' : parts.join(' · ')} · ${_time(status['reported_at'] as String?)}';
  }
}
