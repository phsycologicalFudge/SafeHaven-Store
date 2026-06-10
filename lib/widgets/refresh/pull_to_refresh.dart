import 'package:flutter/material.dart';
import '../../services/theme/theme_manager.dart';

class PullRefresh extends StatefulWidget {
  const PullRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
    this.threshold = 80.0,
  });

  final Future<void> Function() onRefresh;
  final Widget child;
  final double threshold;

  @override
  State<PullRefresh> createState() => _PullRefreshState();
}

class _PullRefreshState extends State<PullRefresh> {
  double _dragOffset = 0;
  bool _armed = false;
  bool _dragging = false;

  bool _handleNotification(ScrollNotification notification) {
    if (_armed) return false;

    if (notification is OverscrollNotification &&
        notification.overscroll < 0 &&
        notification.metrics.axisDirection == AxisDirection.down) {
      setState(() {
        _dragging = true;
        _dragOffset = (_dragOffset - notification.overscroll).clamp(0.0, widget.threshold * 1.6);
      });
    }

    if (notification is ScrollUpdateNotification &&
        _dragging &&
        notification.metrics.pixels > 0) {
      setState(() {
        _dragOffset = 0;
        _dragging = false;
      });
    }

    if (notification is ScrollEndNotification && _dragging) {
      _dragging = false;
      if (_dragOffset >= widget.threshold) {
        _triggerRefresh();
      } else {
        setState(() => _dragOffset = 0);
      }
    }

    return false;
  }

  Future<void> _triggerRefresh() async {
    setState(() {
      _armed = true;
      _dragOffset = 0;
    });

    try {
      await widget.onRefresh();
    } finally {
      if (mounted) setState(() => _armed = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);
    final progress = (_dragOffset / widget.threshold).clamp(0.0, 1.0);

    return NotificationListener<ScrollNotification>(
      onNotification: _handleNotification,
      child: Stack(
        children: [
          widget.child,
          if (_dragOffset > 0)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _Indicator(
                progress: progress,
                dragOffset: _dragOffset,
                threshold: widget.threshold,
                accentColor: colors.accentEnd,
              ),
            ),
        ],
      ),
    );
  }
}

class _Indicator extends StatelessWidget {
  const _Indicator({
    required this.progress,
    required this.dragOffset,
    required this.threshold,
    required this.accentColor,
  });

  final double progress;
  final double dragOffset;
  final double threshold;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: dragOffset * 0.5 + 40,
      alignment: Alignment.bottomCenter,
      padding: const EdgeInsets.only(bottom: 8),
      child: Opacity(
        opacity: progress.clamp(0.0, 1.0),
        child: Transform.scale(
          scale: (0.4 + 0.6 * progress).clamp(0.0, 1.0),
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: accentColor,
              value: progress * 0.75,
            ),
          ),
        ),
      ),
    );
  }
}