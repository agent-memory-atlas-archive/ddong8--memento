import 'package:flutter/material.dart';
import '../../core/theme/aurora_theme.dart';
import 'app_markdown.dart';

class ThinkingBlock extends StatefulWidget {
  final String thinking;
  final bool isLive;

  const ThinkingBlock({
    super.key,
    required this.thinking,
    this.isLive = false,
  });

  @override
  State<ThinkingBlock> createState() => _ThinkingBlockState();
}

class _ThinkingBlockState extends State<ThinkingBlock>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.thinking.isEmpty && !widget.isLive) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.isLive
              ? AuroraColors.accent.withOpacity(0.3)
              : AuroraColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  widget.isLive
                      ? AnimatedBuilder(
                          animation: _pulseController,
                          builder: (context, child) {
                            return Opacity(
                              opacity: 0.4 + (_pulseController.value * 0.6),
                              child: const Icon(
                                Icons.psychology_outlined,
                                size: 16,
                                color: AuroraColors.accent,
                              ),
                            );
                          },
                        )
                      : const Icon(
                          Icons.psychology_outlined,
                          size: 16,
                          color: AuroraColors.warn,
                        ),
                  const SizedBox(width: 8),
                  Text(
                    widget.isLive ? 'AI 深度思考中...' : '已深度思考',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: widget.isLive ? AuroraColors.accent : AuroraColors.fg2,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _expanded ? '收起' : '展开',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AuroraColors.fg3,
                    ),
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    child: const Icon(
                      Icons.keyboard_arrow_down,
                      size: 14,
                      color: AuroraColors.fg3,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AuroraColors.border)),
                color: Color(0x1F000000),
              ),
              child: AppMarkdown(
                data: widget.thinking.isEmpty ? '思考中...' : widget.thinking,
                baseTextStyle: const TextStyle(
                  color: AuroraColors.fg3,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 220),
          ),
        ],
      ),
    );
  }
}
