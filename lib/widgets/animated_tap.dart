import 'package:flutter/material.dart';

class AnimatedTap extends StatefulWidget {
  const AnimatedTap({
    super.key,
    required this.child,
    required this.onTap,
    this.borderRadius = 16,
    this.scale = 0.97,
    this.duration = const Duration(milliseconds: 95),
  });

  final Widget child;
  final VoidCallback? onTap;
  final double borderRadius;
  final double scale;
  final Duration duration;

  @override
  State<AnimatedTap> createState() => _AnimatedTapState();
}

class _AnimatedTapState extends State<AnimatedTap> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  void _onPointerDown(PointerDownEvent event) => _setPressed(true);

  void _onPointerUp(PointerUpEvent event) => _setPressed(false);

  void _onPointerCancel(PointerCancelEvent event) => _setPressed(false);

  Future<void> _handleTap() async {
    _setPressed(true);

    await Future.delayed(widget.duration);

    if (!mounted) return;
    _setPressed(false);

    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: widget.onTap == null ? null : _onPointerDown,
      onPointerUp: widget.onTap == null ? null : _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: AnimatedScale(
        scale: _pressed ? widget.scale : 1,
        duration: widget.duration,
        curve: Curves.easeOutCubic,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(widget.borderRadius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            onTap: widget.onTap == null ? null : _handleTap,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}