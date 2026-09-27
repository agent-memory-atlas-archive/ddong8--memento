import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/theme/aurora_theme.dart';
import '../../models/device.dart';
import '../widgets/app_markdown.dart';
import '../widgets/aurora_shimmer.dart';
import '../widgets/glass_card.dart';

/// Tool id -> (label, instruction file the block goes into).
const personaTargetMeta = <String, (String, String)>{
  'claude_code': ('Claude Code', '~/.claude/CLAUDE.md'),
  'codex': ('Codex', '~/.codex/AGENTS.md'),
  'antigravity': ('Antigravity / Gemini', '~/.gemini/GEMINI.md'),
  'openclaw': ('OpenClaw', '~/.openclaw/workspace/USER.md'),
  'hermes': ('Hermes', '~/.hermes/SOUL.md'),
};

const _draftStatusMessages = <String, String>{
  'same_as_published': '和已发布的画像一致，没有新内容。',
  'no_input': '最近 30 天没有足够的输入来生成画像。',
  'llm_failed': '生成失败：AI 服务暂时不可用，稍后再试。',
  'no_llm': '服务端没有配置 AI 服务，无法生成草稿。你可以手动编辑后发布。',
  'user_editing': '你改过当前草稿。先发布或丢弃它，再重新生成。',
};

/// Bullet lines added to / removed from the published profile. Headings and
/// blank lines aren't meaningful changes, so only "- " lines are compared.
({List<String> added, List<String> removed}) personaLineDiff(String draft, String? published) {
  List<String> bullets(String? text) => (text ?? '')
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.startsWith('- '))
      .toList();
  final before = bullets(published).toSet();
  final after = bullets(draft).toSet();
  return (
    added: after.where((l) => !before.contains(l)).toList(),
    removed: before.where((l) => !after.contains(l)).toList(),
  );
}

/// A profile split into its "### " groups; loose lines before any heading go
/// into an untitled group. Empty when the text has no bullet lines at all.
List<({String title, List<String> items})> personaSections(String content) {
  final sections = <({String title, List<String> items})>[];
  var hasBullets = false;
  for (final raw in content.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#')) {
      sections.add((title: line.replaceFirst(RegExp(r'^#+\s*'), ''), items: <String>[]));
      continue;
    }
    if (sections.isEmpty) sections.add((title: '', items: <String>[]));
    final bullet = line.startsWith('- ') || line.startsWith('* ');
    hasBullets |= bullet;
    sections.last.items.add(bullet ? line.substring(2).trim() : line);
  }
  if (!hasBullets) return const [];
  return sections.where((s) => s.items.isNotEmpty).toList();
}

enum PersonaTargetState { pending, written, upToDate, skipped, waiting, error }

/// What to show on a device's tool toggle, or null for a tool that is off and clean.
PersonaTargetState? personaTargetState({
  required bool enabled,
  required String? result,
  required int? reportedVersion,
  required int? publishedVersion,
}) {
  if (result == null) return enabled ? PersonaTargetState.pending : null;
  if (result.startsWith('error')) return PersonaTargetState.error;
  if (result.startsWith('skipped')) return PersonaTargetState.skipped;
  if (result.startsWith('waiting')) return PersonaTargetState.waiting;
  if (result == 'removed') return enabled ? PersonaTargetState.pending : null;
  if (!enabled || reportedVersion != publishedVersion) return PersonaTargetState.pending;
  return result == 'written' ? PersonaTargetState.written : PersonaTargetState.upToDate;
}

class PersonaTab extends StatefulWidget {
  const PersonaTab({super.key});

  @override
  State<PersonaTab> createState() => _PersonaTabState();
}

class _PersonaTabState extends State<PersonaTab> with AutomaticKeepAliveClientMixin {
  final _api = ApiClient();
  Map<String, dynamic>? _state;
  String? _error;
  String? _notice;
  String? _busy; // regenerate | publish | save | discard
  String? _editing; // draft | published
  final _editor = TextEditingController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _editor.dispose();
    super.dispose();
  }

  Map<String, dynamic>? get _draft => _state?['draft'] as Map<String, dynamic>?;
  Map<String, dynamic>? get _published => _state?['published'] as Map<String, dynamic>?;

  Future<void> _load() async {
    try {
      final state = await _api.getProfile();
      if (!mounted) return;
      setState(() {
        _state = state;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = _describe(e));
    }
  }

  String _describe(Object e) {
    if (e is DioException) {
      final detail = e.response?.data is Map ? (e.response!.data as Map)['detail'] : null;
      if (detail != null) return detail.toString();
      final code = e.response?.statusCode;
      if (code != null && code >= 500) return '服务端出错（$code），稍后再试。';
      return switch (e.type) {
        DioExceptionType.receiveTimeout => '等待超时：服务端可能还在生成，过一会儿下拉刷新看看。',
        DioExceptionType.connectionError || DioExceptionType.connectionTimeout => '连不上服务端，检查网络后再试。',
        _ => e.message ?? e.toString(),
      };
    }
    return e.toString();
  }

  Future<void> _run(String kind, Future<void> Function() action) async {
    setState(() {
      _busy = kind;
      _notice = null;
    });
    try {
      await action();
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = _describe(e));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _regenerate() => _run('regenerate', () async {
        final res = await _api.regenerateProfileDraft();
        final status = res['status']?.toString() ?? '';
        if (status != 'updated') _notice = _draftStatusMessages[status] ?? status;
      });

  void _startEditing(String which, String initial) {
    _editor.text = initial;
    setState(() => _editing = which);
  }

  void _saveDraft() => _run('save', () async {
        await _api.saveProfileDraft(_editor.text);
        _editing = null;
      });

  Future<void> _toggleTarget(Map<String, dynamic> device, String tool) async {
    final current = ((device['targets'] as List?) ?? const []).cast<String>();
    final next = current.contains(tool) ? current.where((t) => t != tool).toList() : [...current, tool];
    setState(() => device['targets'] = next); // optimistic
    try {
      await _api.setProfileTargets(device['device_id'].toString(), next);
    } catch (e) {
      if (mounted) setState(() => _error = _describe(e));
    }
    await _load();
  }

  static String _formatTime(String? iso) {
    if (iso == null) return '';
    final t = DateTime.tryParse(iso)?.toLocal();
    if (t == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.month}-${t.day} ${two(t.hour)}:${two(t.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_state == null && _error == null) return const AuroraListSkeleton(count: 3, itemHeight: 120);

    return RefreshIndicator(
      onRefresh: _load,
      color: AuroraColors.accent,
      // A readable column on wide windows instead of spanning the whole page.
      child: LayoutBuilder(
        builder: (context, constraints) => ListView(
          padding: EdgeInsets.symmetric(
            horizontal: math.max(16, (constraints.maxWidth - 880) / 2),
            vertical: 12,
          ),
          children: [
            if (_error != null) _banner(_error!, AuroraColors.danger, Icons.error_outline_rounded),
            if (_notice != null) _banner(_notice!, AuroraColors.fg2, Icons.info_outline_rounded),
            _buildDraftCard(),
            const SizedBox(height: 14),
            _buildPublishedCard(),
            const SizedBox(height: 14),
            _buildDevicesCard(),
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

  /// 22 px label chip: tinted fill, text in the same hue.
  Widget _pill(String text, Color color) => Container(
        height: 22,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
      );

  Widget _buildEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _editor,
          maxLines: null,
          minLines: 10,
          style: const TextStyle(fontSize: 13, height: 1.55, fontFamilyFallback: AuroraTheme.monospaceFontFamilyFallback),
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(onPressed: _busy != null ? null : () => setState(() => _editing = null), child: const Text('取消')),
            const SizedBox(width: 8),
            FilledButton(onPressed: _busy != null ? null : _saveDraft, child: const Text('保存草稿')),
          ],
        ),
      ],
    );
  }

  /// The profile as labelled groups (沟通 / 铁律 / …) with hairlines between them.
  Widget _buildProfileBody(String content) {
    final sections = personaSections(content);
    if (sections.isEmpty) return AppMarkdown(data: content);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, section) in sections.indexed) ...[
          if (i > 0)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Divider(height: 1, thickness: 1, color: AuroraColors.chip),
            ),
          if (section.title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text(
                section.title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  color: AuroraColors.fg3,
                ),
              ),
            ),
          for (final item in section.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: SelectableText(
                item,
                style: const TextStyle(fontSize: 14, height: 1.55, color: AuroraColors.fgBody),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildDiff(({List<String> added, List<String> removed}) diff) {
    Widget line(String sign, String text, Color signColor, Color textColor, {bool struck = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                sign,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: signColor,
                  fontFamily: 'monospace',
                  fontFamilyFallback: AuroraTheme.monospaceFontFamilyFallback,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: textColor,
                    decoration: struck ? TextDecoration.lineThrough : null,
                    decorationColor: textColor,
                  ),
                ),
              ),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AuroraColors.well,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AuroraColors.chip),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final l in diff.added) line('+', l.substring(2), AuroraColors.success, const Color(0xFF7FE0AE)),
          for (final l in diff.removed)
            line('−', l.substring(2), AuroraColors.danger, const Color(0xFFF2888C), struck: true),
        ],
      ),
    );
  }

  Widget _buildDraftCard() {
    final draft = _draft;
    final published = _published;
    final stats = (draft?['stats'] as Map?) ?? const {};
    final voice = stats['user_voice'] as Map?;
    final diff = draft == null ? null : personaLineDiff(draft['content'].toString(), published?['content']?.toString());
    final regenerating = _busy == 'regenerate';

    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _pill('待审草稿', draft != null ? AuroraColors.accent : AuroraColors.fg3),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  draft != null ? '${_formatTime(draft['updated_at']?.toString())} 生成' : '',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AuroraColors.fg3),
                ),
              ),
              if (_editing == null)
                TextButton.icon(
                  onPressed: _busy != null ? null : _regenerate,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  icon: regenerating
                      ? const SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 1.8))
                      : const Icon(Icons.refresh_rounded, size: 16),
                  label: Text(regenerating ? '生成中…' : (draft != null ? '重新生成' : '现在生成')),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_editing == 'draft')
            _buildEditor()
          else if (draft == null) ...[
            Text(
              regenerating ? '正在根据你最近的原话和记忆生成草稿，大约需要一两分钟。' : '暂无待审草稿。',
              style: const TextStyle(fontSize: 14, color: AuroraColors.fg2),
            ),
            const SizedBox(height: 4),
            const Text(
              '常驻画像是每次打开 AI 工具时自动加载的「关于我」。每晚做梦后根据你亲口说的话生成草稿，你发布后才会写进各工具。',
              style: TextStyle(fontSize: 12.5, color: AuroraColors.fg3, height: 1.5),
            ),
          ] else ...[
            if (voice != null) ...[
              Text(
                '依据你最近 30 天亲口说的 ${voice['kept']} 句话（其中 ${voice['corrections']} 句是纠正）和 ${stats['memories'] ?? 0} 条记忆',
                style: const TextStyle(fontSize: 12.5, color: AuroraColors.fg2, height: 1.5),
              ),
              const SizedBox(height: 12),
            ],
            if (stats['edited_by_user'] == true)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('你改过这份草稿，夜间生成不会覆盖它。', style: TextStyle(fontSize: 12.5, color: AuroraColors.fg3)),
              ),
            if (diff != null && published != null && (diff.added.isNotEmpty || diff.removed.isNotEmpty)) ...[
              _buildDiff(diff),
              const SizedBox(height: 14),
            ],
            _buildProfileBody(draft['content'].toString()),
            const SizedBox(height: 14),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: _busy != null ? null : () => _run('discard', _api.discardProfileDraft),
                  child: const Text('丢弃'),
                ),
                OutlinedButton(
                  onPressed: _busy != null ? null : () => _startEditing('draft', draft['content'].toString()),
                  child: const Text('编辑'),
                ),
                FilledButton(
                  onPressed: _busy != null ? null : () => _run('publish', () => _api.publishProfile()),
                  child: _busy == 'publish'
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AuroraColors.onAccent),
                        )
                      : const Text('发布'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPublishedCard() {
    final published = _published;
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _pill('已发布', published != null ? AuroraColors.success : AuroraColors.fg3),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  published != null
                      ? 'v${published['version']} · ${_formatTime(published['published_at']?.toString())}'
                      : '',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AuroraColors.fg3),
                ),
              ),
              if (_draft == null && _editing == null)
                TextButton(
                  onPressed: () => _startEditing(
                      'published', published?['content']?.toString() ?? '### 沟通\n- \n\n### 铁律\n- \n'),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: Text(published != null ? '编辑' : '手动编写'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_editing == 'published' && _draft == null)
            _buildEditor()
          else if (published != null)
            _buildProfileBody(published['content'].toString())
          else
            const Text('还没有发布过画像。', style: TextStyle(fontSize: 14, color: AuroraColors.fg3)),
        ],
      ),
    );
  }

  Widget _buildDevicesCard() {
    final devices = ((_state?['devices'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final targets = ((_state?['targets'] as List?) ?? personaTargetMeta.keys.toList()).cast<String>();
    final publishedVersion = _published?['version'] as int?;

    return GlassCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('写入哪些工具', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AuroraColors.fg1)),
                SizedBox(height: 3),
                Text(
                  '按设备单独开启，5 分钟内同步。关闭后会把这段删掉；文件是 Memento 新建的会整个删除。',
                  style: TextStyle(fontSize: 12, color: AuroraColors.fg3, height: 1.45),
                ),
              ],
            ),
          ),
          if (devices.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text('还没有注册的设备。', style: TextStyle(fontSize: 13, color: AuroraColors.fg3)),
            ),
          for (final device in devices) _buildDevice(device, targets, publishedVersion),
        ],
      ),
    );
  }

  Widget _buildDevice(Map<String, dynamic> device, List<String> targets, int? publishedVersion) {
    final enabled = ((device['targets'] as List?) ?? const []).cast<String>();
    final status = (device['status'] as Map?) ?? const {};
    final results = ((status['results'] as Map?) ?? const {}).cast<String, dynamic>();
    final online = device['online'] == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          decoration: const BoxDecoration(
            color: Color(0x05FFFFFF),
            border: Border(top: BorderSide(color: AuroraColors.chip)),
          ),
          child: Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: online ? AuroraColors.success : AuroraColors.fg4,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  splitDeviceName(device['name'].toString()).$1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AuroraColors.fg2),
                ),
              ),
              Text(
                status['reported_at'] != null
                    ? '上次同步 ${_formatTime(status['reported_at'].toString())}'
                    : (online ? '在线' : '离线'),
                style: const TextStyle(fontSize: 11.5, color: AuroraColors.fg3),
              ),
            ],
          ),
        ),
        for (final tool in targets)
          _buildToolRow(
            device,
            tool,
            on: enabled.contains(tool),
            result: results[tool]?.toString(),
            publishedVersion: publishedVersion,
            state: personaTargetState(
              enabled: enabled.contains(tool),
              result: results[tool]?.toString(),
              reportedVersion: status['version'] as int?,
              publishedVersion: publishedVersion,
            ),
          ),
      ],
    );
  }

  Widget _buildToolRow(Map<String, dynamic> device, String tool,
      {required bool on, required String? result, required int? publishedVersion, required PersonaTargetState? state}) {
    final (label, file) = personaTargetMeta[tool] ?? (tool, '');
    final (letter, tint) = _toolBadges[tool] ?? (label.isEmpty ? '?' : label[0].toUpperCase(), AuroraColors.accent);
    final version = publishedVersion != null ? ' v$publishedVersion' : '';
    final (stateText, stateColor) = switch (state) {
      PersonaTargetState.written => ('已写入$version', AuroraColors.success),
      PersonaTargetState.upToDate => ('已是最新$version', AuroraColors.success),
      PersonaTargetState.skipped => ('未安装', AuroraColors.warn),
      PersonaTargetState.waiting => ('等待发布', AuroraColors.fg3),
      PersonaTargetState.error => ('出错', AuroraColors.danger),
      PersonaTargetState.pending => ('待同步', AuroraColors.fg2),
      null => ('', AuroraColors.fg3),
    };

    return InkWell(
      onTap: () => _toggleTarget(device, tool),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: AuroraColors.chip))),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: tint.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8)),
              child: Text(letter, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: tint)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: on ? AuroraColors.fg1 : AuroraColors.fg2),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    file,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AuroraColors.fg3,
                      fontFamily: 'monospace',
                      fontFamilyFallback: AuroraTheme.monospaceFontFamilyFallback,
                    ),
                  ),
                ],
              ),
            ),
            if (stateText.isNotEmpty) ...[
              const SizedBox(width: 8),
              Tooltip(
                message: state == PersonaTargetState.error ? (result ?? '') : '',
                child: Text(stateText, style: TextStyle(fontSize: 12, color: stateColor)),
              ),
            ],
            SizedBox(
              width: 60,
              height: 44,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Switch(value: on, onChanged: (_) => _toggleTarget(device, tool)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Letter badge and tint per tool, matching each tool's own brand hue.
const _toolBadges = <String, (String, Color)>{
  'claude_code': ('C', Color(0xFFE8916C)),
  'codex': ('X', Color(0xFF2FC499)),
  'antigravity': ('G', Color(0xFF5B9DFF)),
  'openclaw': ('O', Color(0xFFFF7A7A)),
  'hermes': ('H', Color(0xFF4CC1F2)),
};
