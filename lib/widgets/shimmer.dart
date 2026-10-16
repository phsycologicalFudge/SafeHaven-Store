import 'package:flutter/material.dart';
import '../services/theme/theme_manager.dart';

class Shimmer extends StatefulWidget {
  const Shimmer({
    super.key,
    required this.child,
    this.borderRadius = 0,
    this.enabled = true,
  });

  final Widget child;
  final double borderRadius;
  final bool enabled;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3800),
  );

  @override
  void initState() {
    super.initState();
    if (widget.enabled) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant Shimmer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled == oldWidget.enabled) return;
    widget.enabled ? _controller.repeat() : _controller.stop();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sheen = SafeHavenTheme.of(context).text.withOpacity(0.08);

    return RepaintBoundary(
      child: Stack(
        children: [
          widget.child,
          if (widget.enabled)
            Positioned.fill(
              child: IgnorePointer(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(widget.borderRadius),
                  child: LayoutBuilder(
                    builder: (context, constraints) => AnimatedBuilder(
                      animation: _controller,
                      builder: (context, child) => Transform.translate(
                        offset: Offset(
                          (Curves.easeInOut.transform(_controller.value) * 3 - 1) * constraints.maxWidth,
                          0,
                        ),
                        child: child,
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.transparent, sheen, Colors.transparent],
                            stops: const [0.0, 0.5, 1.0],
                          ),
                        ),
                      ),
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
