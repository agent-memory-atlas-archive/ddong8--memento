import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/api_client.dart';
import '../../core/theme/aurora_theme.dart';
import '../../models/ask_turn.dart';
import 'app_markdown.dart';
import 'glass_card.dart';

class ExecutionCard extends StatefulWidget {
  final ToolCallItem call;
  final void Function(String? sessionId)? onSmartCompactAndRetry;

  const ExecutionCard({
    super.key,
    required this.call,
    this.onSmartCompactAndRetry,
  });

  @override
  State<ExecutionCard> createState() => _ExecutionCardState();
}

class _ExecutionCardState extends State<ExecutionCard> {
  bool _expanded = false;
  bool _copied = false;
  bool _showRawTerminal = false;
  String? _feedbackMsg;

  static final RegExp _uuidRegex = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  String? _resolveTaskId() {
    final resId = widget.call.result?.taskId;
    if (resId != null && resId.isNotEmpty && _uuidRegex.hasMatch(resId)) {
      return resId;
    }
    final argId = widget.call.args['task_id']?.toString();
    if (argId != null && argId.isNotEmpty && _uuidRegex.hasMatch(argId)) {
      return argId;
    }
    return null;
  }

  Future<void> _cancelTask() async {
    final tId = _resolveTaskId();
    if (tId == null) {
      setState(() => _feedbackMsg = '等待任务...');
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _feedbackMsg = null);
      });
      return;
    }

    final ok = await ApiClient().cancelTask(tId);
    if (mounted) {
      setState(() {
        _feedbackMsg = ok ? '已终止' : '终止失败';
      });
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _feedbackMsg = null);
      });
    }
  }

  bool _containsMarkdown(String text) {
    return text.contains('```') ||
        text.contains('# ') ||
        text.contains('## ') ||
        text.contains('**') ||
        text.contains('- ') ||
        text.contains('* ');
  }

  void _copyOutput() {
    final res = widget.call.result;
    final buffer = StringBuffer();
    if (widget.call.command.isNotEmpty) {
      buffer.writeln('\$ ${widget.call.command}');
    }
    if (res?.stdout != null && res!.stdout!.isNotEmpty) {
      buffer.writeln(res.stdout);
    }
    if (res?.stderr != null && res!.stderr!.isNotEmpty) {
      buffer.writeln(res.stderr);
    }
    if (res?.error != null && res!.error!.isNotEmpty) {
      buffer.writeln('Error: ${res.error}');
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final call = widget.call;
    final res = call.result;
    final isRunning = call.isRunning;
    final isStillRunning = call.isStillRunning;
    final isSuccess = call.isSuccess;
    final isFailed = call.isFailed;

    final binary = call.binary;
    final cmd = call.command;
    final isClaude = binary.contains('claude') || cmd.contains('[CLAUDE]');
    final isCodex = binary.contains('codex') || cmd.contains('[CODEX]');
    final isAgy = binary.contains('agy') || binary.contains('antigravity') || cmd.contains('[ANTIGRAVITY]');

    final IconData agentIcon = isClaude
        ? Icons.auto_awesome
        : isCodex
            ? Icons.code_rounded
            : isAgy
                ? Icons.rocket_launch_rounded
                : Icons.terminal_rounded;

    final Color agentColor = isClaude
        ? const Color(0xFFE5855E)
        : isCodex
            ? const Color(0xFF10A37F)
            : isAgy
                ? const Color(0xFF9D67EF)
                : AuroraColors.accent;

    final String agentLabel = isClaude
        ? 'Claude'
        : isCodex
            ? 'Codex'
            : isAgy
                ? 'Antigravity'
                : (call.action == 'agent' ? 'Agent' : 'Shell');

    final statusColor = isRunning
        ? AuroraColors.accent
        : isStillRunning
            ? AuroraColors.warn
            : isSuccess
                ? AuroraColors.success
                : isFailed
                    ? AuroraColors.danger
                    : AuroraColors.fg3;

    final statusText = isRunning
        ? '执行中...'
        : isStillRunning
            ? '后台运行中'
            : isSuccess
                ? '完成'
                : isFailed
                    ? (res?.exitCode != null ? '失败 · 退出码 ${res?.exitCode}' : '失败')
                    : '就绪';

    final alertCount = res?.alerts.length ?? 0;
    final title = call.command.isNotEmpty
        ? (cmd.startsWith('[') && cmd.contains('] ') ? cmd.substring(cmd.indexOf('] ') + 2) : call.command)
        : (call.prompt.isNotEmpty ? call.prompt : call.name);
    final stdout = res?.stdout ?? '';
    final rendersMarkdown =
        stdout.isNotEmpty && (isClaude || isCodex || isAgy || call.action == 'agent' || _containsMarkdown(stdout));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: GlassCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header: what it's doing on top, agent and device underneath.
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: BorderRadius.circular(13),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: agentColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(agentIcon, size: 16, color: agentColor),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: call.action == 'shell' ? 'monospace' : null,
                              fontFamilyFallback:
                                  call.action == 'shell' ? AuroraTheme.monospaceFontFamilyFallback : null,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: AuroraColors.fg1,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text.rich(
                            TextSpan(children: [
                              TextSpan(
                                text: agentLabel,
                                style: TextStyle(color: agentColor, fontWeight: FontWeight.w500),
                              ),
                              if (call.deviceName != null && call.deviceName!.isNotEmpty)
                                TextSpan(text: ' · ${call.deviceName}'),
                            ]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: AuroraColors.fg3),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Risky operations stay visible while the card is collapsed.
                    if (alertCount > 0) ...[
                      Tooltip(
                        message: '期间有 $alertCount 次危险操作',
                        child: _Pill(
                          color: AuroraColors.warn,
                          background: AuroraColors.warn.withValues(alpha: 0.12),
                          children: [
                            const Icon(Icons.warning_amber_rounded, size: 12, color: AuroraColors.warn),
                            const SizedBox(width: 4),
                            Text('$alertCount'),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    _Pill(
                      color: statusColor,
                      background: statusColor.withValues(alpha: 0.10),
                      children: [
                        if (isRunning)
                          const SizedBox(
                            width: 8,
                            height: 8,
                            child: CircularProgressIndicator(strokeWidth: 1.5, color: AuroraColors.accent),
                          )
                        else
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                          ),
                        const SizedBox(width: 5),
                        Text(statusText),
                      ],
                    ),
                    const SizedBox(width: 6),
                    Tooltip(
                      message: _expanded ? '收起详情' : '展开查看详情',
                      child: Icon(
                        _expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: AuroraColors.fg3,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (_expanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (rendersMarkdown)
                          _toolbarAction(
                            icon: _showRawTerminal ? Icons.article_outlined : Icons.terminal_rounded,
                            label: _showRawTerminal ? '渲染' : '终端',
                            onTap: () => setState(() => _showRawTerminal = !_showRawTerminal),
                          ),
                        _toolbarAction(
                          icon: _copied ? Icons.check_rounded : Icons.copy_rounded,
                          label: _copied ? '已复制' : '复制',
                          color: _copied ? AuroraColors.success : AuroraColors.fg3,
                          onTap: _copyOutput,
                        ),
                        if (isRunning)
                          _toolbarAction(
                            icon: Icons.stop_circle_outlined,
                            label: _feedbackMsg ?? '终止',
                            color: AuroraColors.danger,
                            onTap: _cancelTask,
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (res != null && res.alerts.isNotEmpty) ...[
                      RiskAlertList(alerts: res.alerts),
                      const SizedBox(height: 10),
                    ],
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
                      decoration: BoxDecoration(
                        color: AuroraColors.terminal,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AuroraColors.chip),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (call.command.isNotEmpty)
                            Text.rich(
                              TextSpan(children: [
                                const TextSpan(text: '\$ ', style: TextStyle(color: AuroraColors.accent)),
                                TextSpan(text: call.command),
                              ]),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: _mono.copyWith(color: AuroraColors.fg1),
                            ),
                          if (isRunning && stdout.isEmpty && (res?.stderr ?? '').isEmpty)
                            Text(
                              '设备已接收命令，正在运行...',
                              style: _mono.copyWith(fontStyle: FontStyle.italic, color: AuroraColors.fg3),
                            ),
                          if (stdout.isNotEmpty) ...[
                            if (call.command.isNotEmpty) const SizedBox(height: 6),
                            if (rendersMarkdown && !_showRawTerminal)
                              AppMarkdown(
                                data: stdout,
                                baseTextStyle: const TextStyle(fontSize: 13, color: AuroraColors.fgBody, height: 1.55),
                              )
                            else
                              SelectableText(stdout, style: _mono.copyWith(color: AuroraColors.fgCode)),
                          ],
                          if ((res?.stderr ?? '').isNotEmpty) ...[
                            const SizedBox(height: 4),
                            SelectableText(res!.stderr!, style: _mono.copyWith(color: AuroraColors.danger)),
                          ],
                          if ((res?.error ?? '').isNotEmpty) ...[
                            const SizedBox(height: 4),
                            SelectableText(res!.error!, style: _mono.copyWith(color: AuroraColors.danger)),
                          ],
                        ],
                      ),
                    ),
                    if ((res?.note ?? '').isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _amberNote(
                        icon: Icons.info_outline_rounded,
                        child: Text(
                          res!.note!,
                          style: const TextStyle(fontSize: 12, color: AuroraColors.warnText, height: 1.45),
                        ),
                      ),
                    ],
                    if ((res?.stdout?.contains('Prompt is too long') ?? false) ||
                        (res?.stderr?.contains('Prompt is too long') ?? false)) ...[
                      const SizedBox(height: 10),
                      _amberNote(
                        icon: Icons.warning_amber_rounded,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '历史会话超出上下文限制 (Prompt is too long)',
                              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AuroraColors.warnText),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              '不是这次的提问太长，而是续接的历史会话累计了太多消息和工具记录，超出了 200,000 Token 的上下文。'
                              '可以一键提炼前序记忆后重试，或在上方切换为「新建独立会话」。',
                              style: TextStyle(fontSize: 12, color: AuroraColors.fg2, height: 1.5),
                            ),
                            if (widget.onSmartCompactAndRetry != null) ...[
                              const SizedBox(height: 10),
                              FilledButton.icon(
                                onPressed: () {
                                  final sid = (call.args['session_id'] ?? call.args['parent_session_id'])?.toString();
                                  widget.onSmartCompactAndRetry?.call(sid);
                                },
                                icon: const Icon(Icons.auto_awesome, size: 14),
                                label: const Text('智能瘦身并重试'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFFB7791F),
                                  foregroundColor: Colors.white,
                                  textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  minimumSize: const Size(0, 34),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  static const TextStyle _mono = TextStyle(
    fontFamily: 'monospace',
    fontFamilyFallback: AuroraTheme.monospaceFontFamilyFallback,
    fontSize: 12,
    height: 1.65,
  );

  Widget _toolbarAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color color = AuroraColors.fg3,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _amberNote({required IconData icon, required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: AuroraColors.warn.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AuroraColors.warn.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 14, color: AuroraColors.warn),
          ),
          const SizedBox(width: 9),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// A 22 px status chip: tinted fill, text in the same hue.
class _Pill extends StatelessWidget {
  final Color color;
  final Color background;
  final List<Widget> children;

  const _Pill({required this.color, required this.background, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(6)),
      child: DefaultTextStyle.merge(
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}

/// Risky operations the agent performed during a task (also pushed to the phone).
class RiskAlertList extends StatelessWidget {
  final List<Map<String, dynamic>> alerts;

  const RiskAlertList({super.key, required this.alerts});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: AuroraColors.warn.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AuroraColors.warn.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, alert) in alerts.indexed)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.warning_amber_rounded, size: 14, color: AuroraColors.warn),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          alert['label']?.toString() ?? '危险操作',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AuroraColors.warnText,
                          ),
                        ),
                        if ((alert['detail']?.toString() ?? '').isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            alert['detail'].toString(),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontFamilyFallback: AuroraTheme.monospaceFontFamilyFallback,
                              fontSize: 12,
                              height: 1.45,
                              color: AuroraColors.fgCode,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
