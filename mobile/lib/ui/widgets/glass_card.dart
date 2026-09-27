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
    this.borderRadius = 14,
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
    final lifted = _isHovered && widget.onTap != null;
    final fill = widget.backgroundColor ?? (lifted ? AuroraColors.surfaceSolid : AuroraColors.surface);
    final radius = BorderRadius.circular(widget.borderRadius);

    // A 1 px frame whose top edge catches the light: a vertical gradient behind
    // an opaque fill. Rounded Borders can't vary color per side, so the frame is
    // the gradient showing around the inset fill. An explicit borderColor wins.
    final frame = widget.borderColor != null
        ? BoxDecoration(color: widget.borderColor, borderRadius: radius)
        : BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0, 0.3],
              colors: [
                AuroraColors.edgeHighlight,
                lifted ? AuroraColors.borderStrong : AuroraColors.border,
              ],
            ),
          );

    Widget card = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      padding: const EdgeInsets.all(1),
      decoration: frame,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: widget.padding,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(widget.borderRadius - 1),
        ),
        child: widget.child,
      ),
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
