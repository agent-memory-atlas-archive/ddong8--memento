import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/api_client.dart';
import '../../core/theme/aurora_theme.dart';
import '../../models/ask_turn.dart';
import 'app_markdown.dart';

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
  final TextEditingController _inputCtrl = TextEditingController();
  bool _isSendingInput = false;
  String? _feedbackMsg;

  static final RegExp _uuidRegex = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

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

  Future<void> _sendInput(String text) async {
    final tId = _resolveTaskId();
    final toSend = text.isEmpty ? '\n' : text.trim();
    if (tId == null) {
      setState(() => _feedbackMsg = '等待任务就绪...');
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _feedbackMsg = null);
      });
      return;
    }

    setState(() => _isSendingInput = true);
    final ok = await ApiClient().sendTaskInput(tId, toSend);
    if (mounted) {
      setState(() {
        _isSendingInput = false;
        _feedbackMsg = ok
            ? (toSend == '\n' ? '✓ 已发送: 回车' : '✓ 已发送: $toSend')
            : '✗ 发送失败';
      });
      _inputCtrl.clear();
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _feedbackMsg = null);
      });
    }
  }

  Future<void> _cancelTask() async {
    final tId = _resolveTaskId();
    if (tId == null) {
      setState(() => _feedbackMsg = '等待任务就绪...');
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _feedbackMsg = null);
      });
      return;
    }

    final ok = await ApiClient().cancelTask(tId);
    if (mounted) {
      setState(() {
        _feedbackMsg = ok ? '✓ 已请求终止' : '✗ 终止失败';
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
            ? const Color(0xFFF59E0B)
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
                ? (res?.exitCode != null ? '完成 (0)' : '成功')
                : isFailed
                    ? (res?.exitCode != null ? '失败 (${res?.exitCode})' : '失败')
                    : '就绪';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: AuroraColors.surfaceSolid,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AuroraColors.borderStrong),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: _expanded
                ? const BorderRadius.vertical(top: Radius.circular(14))
                : BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AuroraColors.chip,
                borderRadius: _expanded
                    ? const BorderRadius.vertical(top: Radius.circular(14))
                    : BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: agentColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      agentIcon,
                      size: 14,
                      color: agentColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Agent Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: agentColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: agentColor.withOpacity(0.3)),
                    ),
                    child: Text(
                      agentLabel,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: agentColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (call.deviceName != null && call.deviceName!.isNotEmpty) ...[
                    Flexible(
                      child: Text(
                        '${call.deviceName}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: AuroraColors.fg3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      call.command.isNotEmpty
                          ? (cmd.startsWith('[') && cmd.contains('] ') ? cmd.substring(cmd.indexOf('] ') + 2) : call.command)
                          : (call.prompt.isNotEmpty ? call.prompt : call.name),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11.5,
                        color: AuroraColors.fg2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Status pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: statusColor.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isRunning) ...[
                          const SizedBox(
                            width: 8,
                            height: 8,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: AuroraColors.accent,
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          statusText,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Tooltip(
                    message: _expanded ? '收起详情' : '展开查看详情',
                    child: Icon(
                      _expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: AuroraColors.fg3,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Console Output
          if (_expanded)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: Color(0xFF080C14),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(14)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          call.command.isNotEmpty ? '\$ ${call.command}' : '',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF38BDF8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (res?.stdout != null && (isClaude || isCodex || isAgy || call.action == 'agent' || _containsMarkdown(res!.stdout!))) ...[
                        InkWell(
                          onTap: () => setState(() => _showRawTerminal = !_showRawTerminal),
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _showRawTerminal ? Icons.article_outlined : Icons.terminal_rounded,
                                  size: 12,
                                  color: AuroraColors.fg3,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _showRawTerminal ? '渲染' : '终端',
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    color: AuroraColors.fg3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                      InkWell(
                        onTap: _copyOutput,
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _copied ? Icons.check : Icons.copy,
                                size: 12,
                                color: _copied ? AuroraColors.success : AuroraColors.fg3,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _copied ? '已复制' : '复制',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: _copied ? AuroraColors.success : AuroraColors.fg3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (isRunning &&
                      (res?.stdout == null || res!.stdout!.isEmpty) &&
                      (res?.stderr == null || res!.stderr!.isEmpty))
                    const Text(
                      '设备已接收命令，正在运行...',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11.5,
                        fontStyle: FontStyle.italic,
                        color: AuroraColors.fg3,
                      ),
                    ),
                  if (res?.stdout != null && res!.stdout!.isNotEmpty) ...[
                    if ((isClaude || isCodex || isAgy || call.action == 'agent' || _containsMarkdown(res.stdout!)) && !_showRawTerminal)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: AppMarkdown(
                          data: res.stdout!,
                          baseTextStyle: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFFF1F5F9),
                            height: 1.5,
                          ),
                        ),
                      )
                    else
                      SelectableText(
                        res.stdout!,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11.5,
                          color: Color(0xFFF1F5F9),
                          height: 1.45,
                        ),
                      ),
                  ],
                  if (res?.stderr != null && res!.stderr!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    SelectableText(
                      res.stderr!,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11.5,
                        color: Color(0xFFF87171),
                        height: 1.45,
                      ),
                    ),
                  ],
                  if (res?.error != null && res!.error!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    SelectableText(
                      res.error!,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11.5,
                        color: Color(0xFFEF4444),
                        height: 1.45,
                      ),
                    ),
                  ],
                  if (res?.note != null && res!.note!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0x19F59E0B),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0x40F59E0B)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline_rounded, size: 14, color: Color(0xFFF59E0B)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              res.note!,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFFFBBF24),
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if ((res?.stdout?.contains('Prompt is too long') ?? false) ||
                      (res?.stderr?.contains('Prompt is too long') ?? false)) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0x1EF59E0B),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0x59F59E0B)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFF59E0B)),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '历史会话超出上下文限制 (Prompt is too long)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFF59E0B),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            '“Prompt is too long” 并非指您输入的提问过长，而是当前续接的历史会话已累计大量消息与工具记录（超出了 200,000 Token 上下文限制）。\n👉 推荐解决办法：点击下方按钮一键智能提炼前序记忆并轻装重试；或在上方切换为【➕ 新建独立会话】。',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: AuroraColors.fg2,
                              height: 1.45,
                            ),
                          ),
                          if (widget.onSmartCompactAndRetry != null) ...[
                            const SizedBox(height: 10),
                            ElevatedButton.icon(
                              onPressed: () {
                                final sid = (call.args['session_id'] ?? call.args['parent_session_id'])?.toString();
                                widget.onSmartCompactAndRetry?.call(sid);
                              },
                              icon: const Icon(Icons.auto_awesome, size: 14, color: Colors.white),
                              label: const Text(
                                '⚡ 立即智能瘦身并重试 (Smart Compact & Retry)',
                                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFD97706),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  // Interactive Stdin Bar (when running)
                  if (isRunning) _buildInteractiveTerminalBar(),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInteractiveTerminalBar() {
    final tId = _resolveTaskId();
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0D131F),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1E293B)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Status indicator + Feedback pill + Cancel button
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: AuroraColors.accent,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x8038BDF8),
                      blurRadius: 4,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 7),
              const Text(
                '交互控制台',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AuroraColors.fg1,
                  letterSpacing: 0.2,
                ),
              ),
              if (tId == null) ...[
                const SizedBox(width: 6),
                const Text(
                  '(就绪中)',
                  style: TextStyle(fontSize: 10, color: AuroraColors.fg4),
                ),
              ],
              if (_feedbackMsg != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: _feedbackMsg!.startsWith('✓')
                        ? const Color(0x2010B981)
                        : _feedbackMsg!.startsWith('✗')
                            ? const Color(0x20EF4444)
                            : const Color(0x2038BDF8),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _feedbackMsg!,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: _feedbackMsg!.startsWith('✓')
                          ? AuroraColors.success
                          : _feedbackMsg!.startsWith('✗')
                              ? AuroraColors.danger
                              : AuroraColors.accent,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              // Terminate button
              InkWell(
                onTap: _isSendingInput ? null : _cancelTask,
                borderRadius: BorderRadius.circular(5),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0x18EF4444),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: const Color(0x40EF4444), width: 0.8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.stop_rounded, size: 12, color: Color(0xFFEF4444)),
                      SizedBox(width: 3),
                      Text(
                        '终止',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFEF4444),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Quick action chips row
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _buildQuickInputChip(label: 'y 确认', value: 'y', highlight: true),
              _buildQuickInputChip(label: 'n 取消', value: 'n'),
              _buildQuickInputChip(label: '↵ 回车', value: ''),
              _buildQuickInputChip(label: 'q 退出', value: 'q'),
            ],
          ),

          const SizedBox(height: 8),

          // Command input row with terminal prompt prefix
          Container(
            height: 34,
            padding: const EdgeInsets.only(left: 10, right: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF050811),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: Row(
              children: [
                const Text(
                  '>',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AuroraColors.accent,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _inputCtrl,
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: Color(0xFFF1F5F9),
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                      border: InputBorder.none,
                      hintText: '输入控制台按键或命令，回车发送...',
                      hintStyle: TextStyle(
                        fontSize: 11,
                        fontFamily: 'sans-serif',
                        color: AuroraColors.fg4,
                      ),
                    ),
                    onSubmitted: _sendInput,
                  ),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  height: 26,
                  child: TextButton(
                    onPressed: _isSendingInput ? null : () => _sendInput(_inputCtrl.text),
                    style: TextButton.styleFrom(
                      backgroundColor: AuroraColors.accent.withOpacity(0.18),
                      foregroundColor: AuroraColors.accent,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(5),
                        side: BorderSide(color: AuroraColors.accent.withOpacity(0.4)),
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: _isSendingInput
                        ? const SizedBox(
                            width: 11,
                            height: 11,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: AuroraColors.accent,
                            ),
                          )
                        : const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '发送',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(width: 2),
                              Icon(Icons.send_rounded, size: 10),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickInputChip({
    required String label,
    required String value,
    bool highlight = false,
  }) {
    return InkWell(
      onTap: _isSendingInput ? null : () => _sendInput(value),
      borderRadius: BorderRadius.circular(5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
        decoration: BoxDecoration(
          color: highlight
              ? AuroraColors.accent.withOpacity(0.12)
              : const Color(0xFF1E293B).withOpacity(0.5),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: highlight
                ? AuroraColors.accent.withOpacity(0.35)
                : const Color(0xFF334155).withOpacity(0.6),
            width: 0.8,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
            color: highlight ? AuroraColors.accent : AuroraColors.fg2,
          ),
        ),
      ),
    );
  }
}
