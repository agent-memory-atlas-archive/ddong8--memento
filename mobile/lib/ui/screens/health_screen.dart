import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/theme/aurora_theme.dart';
import '../../models/device.dart';
import '../widgets/aurora_shimmer.dart';
import '../widgets/glass_card.dart';

/// Which configured provider a model row came from, in the user's words.
const healthProviderLabels = <String, String>{
  'primary_background': '后台',
  'primary': '主模型',
  'oneapi_fallback': '备用',
};

/// Outcome of the last profile draft generation, in the user's words.
const healthProfileRunLabels = <String, String>{
  'updated': '已生成新草稿',
  'same_as_published': '和已发布的一致',
  'no_input': '输入不够，没有生成',
  'llm_failed': 'AI 没有返回可用内容',
  'no_llm': '没有配置 AI',
  'user_editing': '有未发布的手改草稿，跳过',
  'error': '出错',
};

/// Share of calls that got an answer, as a whole percent; null with no calls.
int? healthSuccessPercent(Map<String, dynamic> calls) {
  final total = (calls['total'] as num?)?.toInt() ?? 0;
  if (total == 0) return null;
  final answered = ((calls['ok'] as num?) ?? 0) + ((calls['fallback'] as num?) ?? 0);
  return (answered * 100 / total).floor();
}

/// Share of corrections that repeated something already said, as a whole percent.
int? healthRepeatPercent(Map<String, dynamic> stats) {
  final total = (stats['total'] as num?)?.toInt() ?? 0;
  if (total == 0) return null;
  return (((stats['repeat'] as num?) ?? 0) * 100 / total).round();
}

const healthTopicStatusLabels = <String, String>{
  'accepted': '已学会',
  'pending': '待确认',
  'dismissed': '已忽略',
};

/// A 0-1 ratio as a whole percent, or "—".
String healthPercent(num? ratio) => ratio == null ? '—' : '${(ratio * 100).round()}%';

String healthLatency(num? ms) {
  if (ms == null) return '—';
  return ms >= 1000 ? '${(ms / 1000).toStringAsFixed(1)} 秒' : '${ms.round()} 毫秒';
}

class HealthScreen extends StatefulWidget {
  const HealthScreen({super.key});

  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen> {
  final _api = ApiClient();
  Map<String, dynamic>? _data;
  String? _error;
  bool _allErrors = false;
  Map<String, dynamic>? _evalJob;
  Timer? _evalPoll;
  bool _showMisses = false;

  @override
  void dispose() {
    _evalPoll?.cancel();
    super.dispose();
  }

  Future<void> _runEval({bool rebuild = false}) async {
    try {
      final job = await _api.runEval(rebuild: rebuild);
      setState(() => _evalJob = job);
      _evalPoll?.cancel();
      _evalPoll = Timer.periodic(const Duration(seconds: 5), (_) async {
        try {
          final evals = await _api.getEvals();
          if (!mounted) return;
          final job = evals['job'] as Map<String, dynamic>?;
          setState(() => _evalJob = job);
          if (job?['status'] != 'running') {
            _evalPoll?.cancel();
            _evalPoll = null;
            await _load();
          }
        } catch (_) {}
      });
    } catch (e) {
      if (mounted) setState(() => _error = '启动评测失败：${e is DioException ? (e.message ?? e.type.name) : e}');
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _api.getHealthOverview();
      if (!mounted) return;
      setState(() {
        _data = data;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      final code = e is DioException ? e.response?.statusCode : null;
      setState(() => _error = code == 404 ? '服务端版本太旧，还没有健康检查接口。' : '读取失败：${e is DioException ? (e.message ?? e.type.name) : e}');
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
    final data = _data;
    return Scaffold(
      appBar: AppBar(
        title: const Text('系统健康'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, size: 20), tooltip: '刷新', onPressed: _load),
        ],
      ),
      body: data == null && _error == null
          ? const AuroraListSkeleton(count: 4, itemHeight: 140)
          : RefreshIndicator(
              onRefresh: _load,
              color: AuroraColors.accent,
              child: LayoutBuilder(
                builder: (context, constraints) => ListView(
                  padding: EdgeInsets.symmetric(
                    horizontal: math.max(16, (constraints.maxWidth - 880) / 2),
                    vertical: 12,
                  ),
                  children: [
                    if (_error != null) _note(_error!, AuroraColors.danger),
                    if (data != null) ...[
                      _buildStatus(data),
                      const SizedBox(height: 14),
                      if (data['evolution'] is Map) ...[
                        _buildEvolution((data['evolution'] as Map).cast<String, dynamic>()),
                        const SizedBox(height: 14),
                      ],
                      if (data['learning'] is Map) ...[
                        _buildLearning((data['learning'] as Map).cast<String, dynamic>()),
                        const SizedBox(height: 14),
                      ],
                      if (data['evolution'] is Map && (data['evolution'] as Map)['eval'] is Map) ...[
                        _buildEval(((data['evolution'] as Map)['eval'] as Map).cast<String, dynamic>()),
                        const SizedBox(height: 14),
                      ],
                      _buildAi((data['ai'] as Map).cast<String, dynamic>()),
                      const SizedBox(height: 14),
                      _buildDreaming((data['dreaming'] as Map).cast<String, dynamic>()),
                      const SizedBox(height: 14),
                      _buildProfile((data['profile'] as Map).cast<String, dynamic>()),
                      const SizedBox(height: 14),
                      _buildPipeline((data['pipeline'] as Map).cast<String, dynamic>()),
                      const SizedBox(height: 24),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  // ---- building blocks ----

  Widget _note(String text, Color color) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Text(text, style: TextStyle(fontSize: 13, color: color, height: 1.45)),
      );

  Widget _section(String title, {String? trailing, required List<Widget> children}) => GlassCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AuroraColors.fg1)),
                ),
                if (trailing != null) Text(trailing, style: const TextStyle(fontSize: 12, color: AuroraColors.fg3)),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      );

  Widget _metric(String label, String value, {Color color = AuroraColors.fg1}) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: color,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )),
            ),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 12, color: AuroraColors.fg3)),
          ],
        ),
      );

  Widget _row(String left, String right,
          {Color rightColor = AuroraColors.fg2, Widget? leading, String? sub, bool subMono = true}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (leading != null) ...[Padding(padding: const EdgeInsets.only(top: 5), child: leading), const SizedBox(width: 8)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(left, style: const TextStyle(fontSize: 13.5, color: AuroraColors.fgBody)),
                  if (sub != null)
                    Text(sub,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AuroraColors.fg3,
                          fontFamily: subMono ? 'monospace' : null,
                          fontFamilyFallback: subMono ? AuroraTheme.monospaceFontFamilyFallback : null,
                        )),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(right, style: TextStyle(fontSize: 12.5, color: rightColor)),
          ],
        ),
      );

  Widget _dot(Color color) => Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );

  Widget _divider() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Divider(height: 1, thickness: 1, color: AuroraColors.chip),
      );

  Widget _subhead(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: AuroraColors.fg3)),
      );

  // ---- sections ----

  Widget _buildStatus(Map<String, dynamic> data) {
    final level = data['level'] as String? ?? 'ok';
    final issues = ((data['issues'] as List?) ?? const []).cast<Map>();
    final devices = (data['devices'] as Map?) ?? const {};
    final (color, title) = switch (level) {
      'error' => (AuroraColors.danger, '有问题需要处理'),
      'warn' => (AuroraColors.warn, '有 ${issues.length} 处需要留意'),
      _ => (AuroraColors.success, '一切正常'),
    };

    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: color.withValues(alpha: 0.18), spreadRadius: 4)],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(title,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AuroraColors.fg1)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 22),
            child: Text(
              '${devices['total'] ?? 0} 台设备 · ${devices['online'] ?? 0} 台在线 · 更新于 ${_time(data['generated_at'] as String?)}',
              style: const TextStyle(fontSize: 12, color: AuroraColors.fg3),
            ),
          ),
          if (issues.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final issue in issues)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Icon(
                        issue['level'] == 'error' ? Icons.error_outline_rounded : Icons.warning_amber_rounded,
                        size: 16,
                        color: issue['level'] == 'error' ? AuroraColors.danger : AuroraColors.warn,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(issue['text'].toString(),
                          style: const TextStyle(fontSize: 13.5, color: AuroraColors.fgBody, height: 1.45)),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildEvolution(Map<String, dynamic> evo) {
    Map<String, dynamic> m(String k) => (evo[k] as Map?)?.cast<String, dynamic>() ?? const {};
    final skills = m('skills');
    final reviews = m('reviews');
    final todos = m('todos');
    final memory = m('memory');
    final agent = (reviews['agent_tasks'] as Map?)?.cast<String, dynamic>() ?? const {};
    final outcomes = (reviews['outcomes'] as Map?)?.cast<String, dynamic>() ?? const {};
    final sessions = (reviews['sessions'] as num?)?.toInt() ?? 0;
    final done = (outcomes['done'] as num?)?.toInt() ?? 0;
    final repeats = (reviews['pitfall_repeats'] as num?)?.toInt() ?? 0;
    final overdue = (todos['overdue'] as num?)?.toInt() ?? 0;
    final reviewRun = evo['review_run'] as Map?;
    final lifecycleRun = evo['lifecycle_run'] as Map?;
    final reconciled = (lifecycleRun?['reconcile'] as Map?)?['superseded'];
    final dormant = lifecycleRun?['dormant'];

    return _section('自我进化', trailing: '最近 7 天', children: [
      Row(children: [
        _metric('已发布技能', '${skills['published'] ?? 0}'),
        _metric('待确认技能', '${skills['draft'] ?? 0}',
            color: (skills['draft'] as num? ?? 0) > 0 ? AuroraColors.accent : AuroraColors.fg1),
        _metric('记下的坑', '${reviews['pitfalls_total'] ?? 0}'),
        _metric('又踩老坑', '$repeats', color: repeats > 0 ? AuroraColors.danger : AuroraColors.fg1),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        _metric('复盘会话', '$sessions'),
        _metric('做成的', sessions == 0 ? '—' : '${(done * 100 / sessions).round()}%'),
        _metric('Agent 成功率', healthPercent(agent['success_rate'] as num?)),
        _metric('待办 · 逾期', '${todos['open'] ?? 0} · $overdue',
            color: overdue > 0 ? AuroraColors.danger : AuroraColors.fg1),
      ]),
      const SizedBox(height: 8),
      const Text(
        '每晚复盘结束的会话：做成的流程变成技能，查明原因的失败记成坑，没做完的事进待办。'
        '"又踩老坑"应该越来越少——不少说明 AI 动手前没查规矩（检查 MCP 是否接好）。',
        style: TextStyle(fontSize: 12, color: AuroraColors.fg3, height: 1.5),
      ),
      _divider(),
      _subhead('记忆新陈代谢'),
      _row('生效中', '${memory['active'] ?? 0} 条',
          sub: '7 天内被 AI 用到 ${memory['recalled_recent'] ?? 0} 条', subMono: false),
      _row('沉睡', '${memory['dormant'] ?? 0} 条', sub: '60 天没被用到的自动总结，不再交给 AI，可在「准则」里唤醒', subMono: false),
      _row('已取代', '${memory['superseded'] ?? 0} 条',
          sub: '和新记忆重复或被新说法推翻；7 天内 ${memory['superseded_recent'] ?? 0} 条', subMono: false),
      if (reviewRun != null || lifecycleRun != null) ...[
        _divider(),
        if (reviewRun != null)
          _row('上次复盘', _time(reviewRun['at'] as String?),
              sub: (reviewRun['sessions'] is Map && (reviewRun['sessions'] as Map)['error'] == null)
                  ? '${(reviewRun['sessions'] as Map)['reviewed'] ?? 0} 个会话'
                  : '出错：${(reviewRun['sessions'] as Map?)?['error'] ?? ''}',
              subMono: false),
        if (lifecycleRun != null)
          _row('上次整理记忆', _time(lifecycleRun['at'] as String?),
              sub: '取代 ${reconciled ?? 0} 条 · 转为沉睡 ${dormant is num ? dormant : 0} 条', subMono: false),
      ],
    ]);
  }

  Widget _buildEval(Map<String, dynamic> eval) {
    final latest = (eval['latest'] as Map?)?.cast<String, dynamic>();
    final trend = ((eval['trend'] as List?) ?? const []).cast<Map>();
    final running = _evalJob?['status'] == 'running' || (eval['job'] as Map?)?['status'] == 'running';
    final metrics = (latest?['metrics'] as Map?)?.cast<String, dynamic>() ?? const {};
    Map<String, dynamic> ch(String k) => (metrics[k] as Map?)?.cast<String, dynamic>() ?? const {};
    final hybrid = ch('hybrid');
    final misses = ((metrics['misses'] as List?) ?? const []).cast<Map>();
    final regression = eval['regression'] as Map?;
    final jobError = _evalJob?['status'] == 'error' ? _evalJob!['error'] : null;

    final buttons = Wrap(
      alignment: WrapAlignment.end,
      spacing: 8,
      children: [
        TextButton(
          onPressed: running ? null : () => _runEval(rebuild: true),
          child: const Text('重建评测集'),
        ),
        FilledButton.tonal(
          onPressed: running ? null : () => _runEval(),
          child: running
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('立即评测'),
        ),
      ],
    );

    return _section('检索评测', trailing: latest == null ? '每周一 04:40' : '评测集 v${latest['set_version']} · ${latest['cases']} 题',
        children: [
          if (latest == null) ...[
            const Text(
              '从你的资料里生成一套固定的问题，每周用问 AI 时同一套检索逻辑作答，看能不能找回正确的那篇。'
              '改检索、换模型之后分数变化一目了然。第一次运行会先生成题目，需要几分钟。',
              style: TextStyle(fontSize: 12.5, color: AuroraColors.fg3, height: 1.55),
            ),
          ] else ...[
            Row(children: [
              _metric('前 5 条命中', healthPercent(hybrid['hit5'] as num?),
                  color: regression != null ? AuroraColors.danger : AuroraColors.fg1),
              _metric('第 1 条就对', healthPercent(hybrid['hit1'] as num?)),
              _metric('MRR', (hybrid['mrr'] as num?)?.toStringAsFixed(2) ?? '—'),
              _metric('关键词 / 语义', '${healthPercent(ch('keyword')['hit5'] as num?)} / ${healthPercent(ch('semantic')['hit5'] as num?)}'),
            ]),
            const SizedBox(height: 8),
            Text(
              '上次评测 ${_time(latest['created_at'] as String?)}'
              '${(metrics['semantic_unavailable'] as num? ?? 0) > 0 ? ' · ${metrics['semantic_unavailable']} 题向量服务没响应' : ''}'
              '${eval['stale'] == true ? ' · 超过 10 天没评测' : ''}',
              style: const TextStyle(fontSize: 12, color: AuroraColors.fg3),
            ),
            if (trend.length > 1) ...[
              const SizedBox(height: 10),
              _EvalTrend(trend: trend),
            ],
            if (misses.isNotEmpty) ...[
              _divider(),
              InkWell(
                onTap: () => setState(() => _showMisses = !_showMisses),
                child: Row(children: [
                  Expanded(child: _subhead('没找回来的问题（${misses.length}）')),
                  Icon(_showMisses ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 18, color: AuroraColors.fg3),
                ]),
              ),
              if (_showMisses)
                for (final miss in misses)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text('· ${miss['query']}', style: const TextStyle(fontSize: 12.5, color: AuroraColors.fg2)),
                  ),
            ],
          ],
          if (jobError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('评测出错：$jobError', style: const TextStyle(fontSize: 12, color: AuroraColors.danger)),
            ),
          const SizedBox(height: 8),
          buttons,
        ]);
  }

  Widget _buildLearning(Map<String, dynamic> learning) {
    final weekly = ((learning['weekly'] as List?) ?? const []).cast<Map>();
    final top = ((learning['top'] as List?) ?? const []).cast<Map>();
    final total = (learning['total'] as num?)?.toInt() ?? 0;
    final learnedRepeat = (learning['learned_repeat'] as num?)?.toInt() ?? 0;
    final percent = healthRepeatPercent(learning);

    return _section('学习效果', trailing: '最近 ${learning['window_days'] ?? 30} 天', children: [
      Row(
        children: [
          _metric('纠正 AI', '$total'),
          _metric('重复率', percent == null ? '—' : '$percent%'),
          _metric('学会后仍重复', '$learnedRepeat', color: learnedRepeat > 0 ? AuroraColors.danger : AuroraColors.fg1),
          _metric('待确认', '${learning['pending'] ?? 0}'),
        ],
      ),
      const SizedBox(height: 8),
      const Text(
        '重复纠正越来越少，说明它越来越懂你。学会后仍重复，说明那条规矩没传到 AI 那里：看看画像有没有发布、设备有没有开启写入。',
        style: TextStyle(fontSize: 12, color: AuroraColors.fg3, height: 1.5),
      ),
      if (weekly.isNotEmpty && weekly.any((w) => (w['total'] as num? ?? 0) > 0)) ...[
        const SizedBox(height: 14),
        _WeeklyRepeatBars(weekly: weekly),
      ],
      if (top.isNotEmpty) ...[
        _divider(),
        _subhead('说得最多的'),
        for (final t in top)
          _row(
            t['statement'].toString(),
            '${t['count']} 次 · ${healthTopicStatusLabels[t['status']] ?? t['status']}',
            sub: (t['learned_repeat'] as num? ?? 0) > 0 ? '学会之后你又说了 ${t['learned_repeat']} 次' : null,
            subMono: false,
            rightColor: (t['learned_repeat'] as num? ?? 0) > 0
                ? AuroraColors.danger
                : t['status'] == 'accepted'
                    ? AuroraColors.success
                    : AuroraColors.fg2,
          ),
      ] else if (total == 0)
        const Padding(
          padding: EdgeInsets.only(top: 10),
          child: Text('还没有记录到纠正。你在任何 AI 工具里纠正它，10 分钟内会出现在这里。',
              style: TextStyle(fontSize: 13, color: AuroraColors.fg3)),
        ),
    ]);
  }

  Widget _buildAi(Map<String, dynamic> ai) {
    final calls = ((ai['calls'] as Map?) ?? const {}).cast<String, dynamic>();
    final hourly = ((ai['hourly'] as List?) ?? const []).cast<Map>();
    final models = ((ai['models'] as List?) ?? const []).cast<Map>();
    final reasons = ((ai['reasons'] as List?) ?? const []).cast<Map>();
    final recent = ((ai['recent_errors'] as List?) ?? const []).cast<Map>();
    final percent = healthSuccessPercent(calls);
    final failed = (calls['failed'] as num?)?.toInt() ?? 0;

    return _section('AI 调用', trailing: '最近 24 小时', children: [
      if (ai['available'] == false) _note('读不到调用统计（Redis 不可用）。', AuroraColors.warn),
      Row(
        children: [
          _metric('总调用', '${calls['total'] ?? 0}'),
          _metric('成功率', percent == null ? '—' : '$percent%',
              color: percent == null || percent >= 95 ? AuroraColors.fg1 : AuroraColors.warn),
          _metric('靠备用完成', '${calls['fallback'] ?? 0}'),
          _metric('失败', '$failed', color: failed > 0 ? AuroraColors.danger : AuroraColors.fg1),
        ],
      ),
      if (hourly.isNotEmpty) ...[
        const SizedBox(height: 14),
        _HourlyBars(hourly: hourly),
      ],
      if (models.isNotEmpty) ...[
        _divider(),
        _subhead('按模型'),
        for (final m in models)
          _row(
            '${healthProviderLabels[m['provider']] ?? m['provider']} · ${m['model']}',
            '成功 ${m['ok']} · 失败 ${m['failed']} · ${healthLatency(m['avg_latency_ms'] as num?)}',
            rightColor: (m['failed'] as num? ?? 0) > 0 ? AuroraColors.warn : AuroraColors.fg2,
          ),
      ],
      if (reasons.isNotEmpty) ...[
        _divider(),
        _subhead('没答上的原因'),
        const SizedBox(height: 2),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final r in reasons)
              Container(
                height: 24,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(color: AuroraColors.chip, borderRadius: BorderRadius.circular(6)),
                child: Center(
                  widthFactor: 1,
                  child: Text('${r['label']} × ${r['count']}',
                      style: const TextStyle(fontSize: 12, color: AuroraColors.fg2)),
                ),
              ),
          ],
        ),
      ],
      if (recent.isNotEmpty) ...[
        _divider(),
        _subhead('最近的失败'),
        for (final e in (_allErrors ? recent : recent.take(4)))
          _row(
            '${e['label']} · ${e['model']}',
            _time(e['at'] as String?),
            leading: _dot(e['fatal'] == true ? AuroraColors.danger : AuroraColors.warn),
            sub: (e['detail'] as String?)?.isNotEmpty == true ? e['detail'].toString() : null,
          ),
        if (recent.length > 4)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _allErrors = !_allErrors),
              child: Text(_allErrors ? '收起' : '显示全部 ${recent.length} 条'),
            ),
          ),
      ],
    ]);
  }

  Widget _buildDreaming(Map<String, dynamic> dreaming) {
    final journals = ((dreaming['journals'] as List?) ?? const []).cast<Map>();
    final run = (dreaming['last_run'] as Map?)?.cast<String, dynamic>();

    return _section('做梦学习', trailing: '每晚 03:00', children: [
      if (run != null)
        _row(
          '上次夜间运行 ${_time(run['at'] as String?)}',
          run['ok'] == false ? '失败' : '成功',
          rightColor: run['ok'] == false ? AuroraColors.danger : AuroraColors.success,
          sub: run['ok'] == false
              ? run['error']?.toString()
              : '画像草稿：${healthProfileRunLabels[run['profile_status']] ?? run['profile_status'] ?? '—'}',
        ),
      if (run != null && journals.isNotEmpty) _divider(),
      if (journals.isEmpty)
        const Text('还没有做梦记录。', style: TextStyle(fontSize: 13.5, color: AuroraColors.fg3))
      else ...[
        _subhead('最近的记录'),
        for (final j in journals)
          _row(
            j['date'].toString(),
            [
              '扫描 ${j['scanned']}',
              '晋升 ${j['promoted']}',
              if ((j['relations'] as num? ?? 0) > 0) '关联 ${j['relations']}',
              if (j['voice'] != null) '原话 ${j['voice']}',
            ].join(' · '),
            rightColor: (j['promoted'] as num? ?? 0) > 0 ? AuroraColors.fgBody : AuroraColors.fg3,
          ),
      ],
    ]);
  }

  Widget _buildProfile(Map<String, dynamic> profile) {
    final published = (profile['published'] as Map?)?.cast<String, dynamic>();
    final draft = (profile['draft'] as Map?)?.cast<String, dynamic>();
    final run = (profile['last_run'] as Map?)?.cast<String, dynamic>();
    final devices = ((profile['devices'] as List?) ?? const []).cast<Map>();
    final runFailed = run != null && (run['status'] == 'llm_failed' || run['status'] == 'error');

    return _section('常驻画像', children: [
      _row(
        '已发布',
        published == null ? '还没有' : 'v${published['version']} · ${_time(published['published_at'] as String?)}',
        rightColor: published == null ? AuroraColors.warn : AuroraColors.fg2,
      ),
      _row('待审草稿', draft == null ? '无' : '${_time(draft['updated_at'] as String?)} 生成'),
      if (run != null)
        _row(
          '上次手动生成',
          '${healthProfileRunLabels[run['status']] ?? run['status']} · ${_time(run['at'] as String?)}',
          rightColor: runFailed ? AuroraColors.danger : AuroraColors.fg2,
          sub: run['error']?.toString(),
        ),
      if (devices.isNotEmpty) ...[
        _divider(),
        _subhead('写入设备'),
        for (final d in devices)
          _row(
            splitDeviceName(d['name'].toString()).$1,
            (d['errors'] as List).isNotEmpty
                ? '出错：${(d['errors'] as List).join('、')}'
                : d['synced'] == true
                    ? '已同步 v${d['version']}'
                    : (published == null ? '等待发布' : '待同步'),
            leading: _dot(d['online'] == true ? AuroraColors.success : AuroraColors.fg4),
            rightColor: (d['errors'] as List).isNotEmpty
                ? AuroraColors.danger
                : d['synced'] == true
                    ? AuroraColors.success
                    : AuroraColors.fg3,
          ),
      ],
    ]);
  }

  Widget _buildPipeline(Map<String, dynamic> pipeline) {
    final embedding = (pipeline['embedding_failed'] as num?)?.toInt() ?? 0;
    final knowledge = (pipeline['knowledge_failed'] as num?)?.toInt() ?? 0;
    return _section('数据管道', trailing: '每 15 分钟自动重试', children: [
      Row(
        children: [
          _metric('向量化失败', '$embedding', color: embedding > 0 ? AuroraColors.warn : AuroraColors.fg1),
          _metric('图谱抽取失败', '$knowledge', color: knowledge > 0 ? AuroraColors.warn : AuroraColors.fg1),
        ],
      ),
      const SizedBox(height: 8),
      const Text('失败的文档会自动重试，最多 5 次；超过次数的会一直留在这里，直到手动处理。',
          style: TextStyle(fontSize: 12, color: AuroraColors.fg3, height: 1.45)),
    ]);
  }
}

/// 24 hourly bars: answered calls in a quiet tone, failures stacked in red on top.
class _HourlyBars extends StatelessWidget {
  final List<Map> hourly;

  const _HourlyBars({required this.hourly});

  @override
  Widget build(BuildContext context) {
    int n(Map h, String k) => (h[k] as num?)?.toInt() ?? 0;
    final peak = hourly.fold<int>(0, (m, h) => math.max(m, n(h, 'ok') + n(h, 'fallback') + n(h, 'failed')));
    const height = 44.0;
    const usable = height - 2; // leaves room for the 2 px minimum on stacked bars

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final h in hourly)
                Expanded(
                  child: Tooltip(
                    message: '${DateTime.tryParse(h['hour'].toString())?.toLocal().hour ?? ''} 点：'
                        '成功 ${n(h, 'ok') + n(h, 'fallback')}，失败 ${n(h, 'failed')}',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1.5),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (n(h, 'failed') > 0)
                            Container(
                              height: math.max(2, usable * n(h, 'failed') / math.max(peak, 1)),
                              decoration: const BoxDecoration(
                                color: AuroraColors.danger,
                                borderRadius: BorderRadius.vertical(top: Radius.circular(2)),
                              ),
                            ),
                          Container(
                            height: peak == 0
                                ? 2
                                : math.max(2, usable * (n(h, 'ok') + n(h, 'fallback')) / peak),
                            decoration: BoxDecoration(
                              color: AuroraColors.accent.withValues(alpha: peak == 0 ? 0.15 : 0.45),
                              borderRadius: n(h, 'failed') > 0
                                  ? null
                                  : const BorderRadius.vertical(top: Radius.circular(2)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        const Row(
          children: [
            Text('24 小时前', style: TextStyle(fontSize: 11, color: AuroraColors.fg4)),
            Spacer(),
            Text('现在', style: TextStyle(fontSize: 11, color: AuroraColors.fg4)),
          ],
        ),
      ],
    );
  }
}

/// One bar per week: all corrections, with repeats in amber and repeats of
/// already-learned rules in red on top. Shrinking amber is the goal.
class _WeeklyRepeatBars extends StatelessWidget {
  final List<Map> weekly;

  const _WeeklyRepeatBars({required this.weekly});

  @override
  Widget build(BuildContext context) {
    int n(Map w, String k) => (w[k] as num?)?.toInt() ?? 0;
    final peak = weekly.fold<int>(1, (m, w) => math.max(m, n(w, 'total')));
    const height = 56.0;
    const usable = height - 2; // room for the 2 px minimum on the base segment

    Widget part(double h, Color color, {bool top = false}) => Container(
          height: h,
          decoration: BoxDecoration(
            color: color,
            borderRadius: top ? const BorderRadius.vertical(top: Radius.circular(3)) : null,
          ),
        );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final w in weekly)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Column(
                children: [
                  SizedBox(
                    height: height,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (n(w, 'learned_repeat') > 0)
                          part(usable * n(w, 'learned_repeat') / peak, AuroraColors.danger, top: true),
                        if (n(w, 'repeat') - n(w, 'learned_repeat') > 0)
                          part(usable * (n(w, 'repeat') - n(w, 'learned_repeat')) / peak, AuroraColors.warn,
                              top: n(w, 'learned_repeat') == 0),
                        part(math.max(2, usable * (n(w, 'total') - n(w, 'repeat')) / peak),
                            AuroraColors.accent.withValues(alpha: n(w, 'total') == 0 ? 0.15 : 0.45),
                            top: n(w, 'repeat') == 0),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    n(w, 'total') == 0 ? '—' : '重复 ${(n(w, 'repeat') * 100 / n(w, 'total')).round()}%',
                    style: const TextStyle(fontSize: 11, color: AuroraColors.fg2),
                  ),
                  Text(
                    _weekLabel(w['end'] as String?),
                    style: const TextStyle(fontSize: 10.5, color: AuroraColors.fg4),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  static String _weekLabel(String? endIso) {
    final end = endIso == null ? null : DateTime.tryParse(endIso)?.toLocal();
    if (end == null) return '';
    final start = end.subtract(const Duration(days: 7));
    return '${start.month}/${start.day}–${end.month}/${end.day}';
  }
}


/// Hit@5 per evaluation run, oldest first; a new question set starts a new colour.
class _EvalTrend extends StatelessWidget {
  final List<Map> trend;

  const _EvalTrend({required this.trend});

  @override
  Widget build(BuildContext context) {
    final latestSet = trend.last['set_version'];
    return SizedBox(
      height: 56,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final t in trend)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Tooltip(
                  message: 'v${t['set_version']} · ${healthPercent(t['hit5'] as num?)}',
                  child: Container(
                    height: 4 + 48 * ((t['hit5'] as num?)?.toDouble() ?? 0),
                    decoration: BoxDecoration(
                      color: t['set_version'] == latestSet
                          ? AuroraColors.accent.withValues(alpha: 0.75)
                          : AuroraColors.fg4.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
