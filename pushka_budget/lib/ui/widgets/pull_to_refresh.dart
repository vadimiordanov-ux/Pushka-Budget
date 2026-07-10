import 'package:flutter/material.dart';

import '../../core/haptics.dart';
import 'common.dart';

/// Custom pull-to-refresh — port of initPullToRefresh():
/// circular pill with a refresh glyph descends with 0.5 drag easing,
/// rotates up to 220° approaching the 66px threshold, accent ring when armed,
/// haptic tick at threshold, then spins while syncing and eases back.
class AppPullToRefresh extends StatefulWidget {
  final Future<void> Function() onRefresh;
  final Widget child;
  const AppPullToRefresh(
      {super.key, required this.onRefresh, required this.child});

  @override
  State<AppPullToRefresh> createState() => _AppPullToRefreshState();
}

class _AppPullToRefreshState extends State<AppPullToRefresh>
    with SingleTickerProviderStateMixin {
  static const _thresh = 66.0;
  static const _max = 96.0;

  double _dy = 0; // eased pull distance
  bool _busy = false;
  bool _buzzed = false;
  late final AnimationController _spin = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 700));

  bool get _armed => _dy >= _thresh * .94;

  bool _onNotification(ScrollNotification n) {
    if (_busy) return false;
    if (n is OverscrollNotification && n.overscroll < 0 && n.metrics.pixels <= 0) {
      setState(() => _dy = (_dy - n.overscroll * .5).clamp(0, _max));
      if (_armed && !_buzzed) {
        haptic();
        _buzzed = true;
      } else if (!_armed) {
        _buzzed = false;
      }
    } else if (n is ScrollUpdateNotification && _dy > 0 && n.dragDetails != null) {
      // dragging back down
      final d = n.scrollDelta ?? 0;
      if (d > 0) setState(() => _dy = (_dy - d * .5).clamp(0, _max));
    } else if (n is ScrollEndNotification && _dy > 0) {
      _finish();
    }
    return false;
  }

  Future<void> _finish() async {
    if (_armed && !_busy) {
      haptic(HapticKind.select);
      setState(() {
        _busy = true;
        _dy = _thresh;
      });
      _spin.repeat();
      try {
        await widget.onRefresh();
      } finally {
        _spin.stop();
        _spin.value = 0;
        if (mounted)

          setState(() {
            _busy = false;
            _dy = 0;
            _buzzed = false;
          });
      }
    } else {
      setState(() {
        _dy = 0;
        _buzzed = false;
      });
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = tk(context);
    final progress = (_dy / _thresh).clamp(0.0, 1.0);
    return Stack(children: [
      NotificationListener<ScrollNotification>(
        onNotification: _onNotification,
        child: widget.child,
      ),
      // #ptr pill
      Positioned(
        top: 6,
        left: 0,
        right: 0,
        child: IgnorePointer(
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 120),
            opacity: (progress * 1.1).clamp(0.0, 1.0),
            child: Center(
              child: AnimatedContainer(
                duration: Duration(milliseconds: _dy == 0 ? 280 : 0),
                curve: AppCurves.enter,
                transform: Matrix4.translationValues(0, _dy, 0),
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: t.surface2,
                  shape: BoxShape.circle,
                  border: Border.all(color: _armed ? t.accent : t.line),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: .22),
                        blurRadius: 16,
                        offset: const Offset(0, 6))
                  ],
                ),
                child: RotationTransition(
                  turns: _busy
                      ? _spin
                      : AlwaysStoppedAnimation(progress * 220 / 360),
                  child: Icon(Icons.refresh_rounded,
                      size: 18, color: _armed ? t.accent : t.ink3),
                ),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}
