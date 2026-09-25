import 'package:flutter/material.dart';
import '../../core/theme/aurora_theme.dart';

class GlassCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final VoidCallback? onTap;
  final Color? borderColor;
  final Color? backgroundColor;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = 16,
    this.onTap,
    this.borderColor,
    this.backgroundColor,
  });

  @override
  State<GlassCard> createState() => _GlassCardState();
}

class _GlassCardState extends State<GlassCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final effectiveBorderColor = widget.borderColor ??
        (_isHovered ? AuroraColors.borderStrong : AuroraColors.border);
    final effectiveBgColor = widget.backgroundColor ??
        (_isHovered ? AuroraColors.surfaceElevated : AuroraColors.surfaceSolid);

    Widget card = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: effectiveBgColor,
        borderRadius: BorderRadius.circular(widget.borderRadius),
        border: Border.all(
          color: effectiveBorderColor,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(_isHovered ? 0.28 : 0.15),
            blurRadius: _isHovered ? 16 : 12,
            offset: Offset(0, _isHovered ? 6 : 4),
          ),
          if (_isHovered)
            BoxShadow(
              color: AuroraColors.accent.withOpacity(0.08),
              blurRadius: 18,
              spreadRadius: 1,
            ),
        ],
      ),
      child: widget.child,
    );

    if (widget.onTap != null) {
      card = InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: card,
      );
    }

    return MouseRegion(
      cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: card,
    );
  }
}
