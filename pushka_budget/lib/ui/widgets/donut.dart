import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/tokens.dart';
import 'common.dart';

/// Donut chart — CustomPainter port of donutSVG() with the three styles:
///   A «Кільце»   R78 W20 gap2.6° + dashed decorative ring
///   B «Тонке»    R84 W11 gap3.4°, no ring
///   C «Сегменти» R76 W23 gap2.4° + ring; >6 parts grouped into «Інше»
/// Round line caps, segments start at -90° (viewBox rotate), tap → onSegment.
///
/// Animations (CSS parity):
///   donutIn  — whole chart rotates -210°→-90° while scaling .86→1, .6s
///   donutSwap — mode switch: quick pop .9→1.03→1 with fade, .42s
class DonutChart extends StatefulWidget {
  final List<(String? cid, int sum, Color color)> parts; // grouped already
  final int grand;
  final String style; // 'A' | 'B' | 'C'
  final Widget center;
  final void Function(String? cid)? onSegment;
  final int swapTick; // increment to trigger the swap animation

  const DonutChart(
      {super.key,
      required this.parts,
      required this.grand,
      required this.style,
      required this.center,
      this.onSegment,
      this.swapTick = 0});

  @override
  State<DonutChart> createState() => _DonutChartState();
}

class _DonutChartState extends State<DonutChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 600));
  bool _swapMode = false;

  @override
  void initState() {
    super.initState();
    _c.forward();
  }

  @override
  void didUpdateWidget(DonutChart old) {
    super.didUpdateWidget(old);
    if (old.swapTick != widget.swapTick) {
      _swapMode = true;
      _c.duration = const Duration(milliseconds: 420);
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  _Cfg get _cfg => switch (widget.style) {
        'B' => const _Cfg(84, 11, 3.4, false),
        'C' => const _Cfg(76, 23, 2.4, true),
        _ => const _Cfg(78, 20, 2.6, true),
      };

  void _onTapUp(TapUpDetails d, Size size) {
    if (widget.onSegment == null || widget.grand == 0) return;
    final cfg = _cfg;
    final scale = size.width / 200;
    final center = Offset(size.width / 2, size.height / 2);
    final v = d.localPosition - center;
    final dist = v.distance / scale;
    if ((dist - cfg.r).abs() > cfg.w) return;
    // angle in the pre-rotation coordinate system (chart starts at -90°)
    var deg = math.atan2(v.dy, v.dx) * 180 / math.pi + 90;
    if (deg < 0) deg += 360;
    var angle = 0.0;
    for (final (cid, sum, _) in widget.parts) {
      final frac = sum / widget.grand * 360;
      if (deg >= angle && deg < angle + frac) {
        if (cid != '__other__') widget.onSegment!(cid);
        return;
      }
      angle += frac;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = tk(context);
    final reduce = reducedMotion(context);
    return LayoutBuilder(builder: (context, box) {
      final side = math.min(box.maxWidth * .78, 300.0);
      return AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final k = reduce ? 1.0 : _c.value;
          double rot, scale, opacity = 1;
          if (_swapMode) {
            // donutSwap: scale .9→1.03→1, opacity .35→1, no extra rotation
            final e = AppCurves.pop.transform(k);
            scale = e < .6 ? .9 + (1.03 - .9) * (e / .6) : 1.03 - .03 * ((e - .6) / .4);
            rot = 0;
            opacity = .35 + .65 * (e < .6 ? e / .6 : 1);
          } else {
            final e = AppCurves.enter.transform(k);
            rot = -120 * (1 - e) * math.pi / 180; // -210° → -90° (base -90 in painter)
            scale = .86 + .14 * e;
          }
          return Opacity(
            opacity: opacity,
            child: Transform.rotate(
              angle: rot,
              child: Transform.scale(scale: scale, child: __),
            ),
          );
        },
        child: SizedBox(
          width: side,
          height: side,
          child: Stack(children: [
            // ::before glow
            Positioned.fill(
              child: Container(
                margin: EdgeInsets.all(side * .12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                      colors: [t.glow, t.glow.withValues(alpha: 0)],
                      stops: const [0, .72]),
                ),
              ),
            ),
            GestureDetector(
              onTapUp: (d) => _onTapUp(d, Size(side, side)),
              child: CustomPaint(
                size: Size(side, side),
                painter: _DonutPainter(
                    parts: widget.parts,
                    grand: widget.grand,
                    cfg: _cfg,
                    track: t.surface2,
                    ringColor: t.accent),
              ),
            ),
            // .donut-center
            Positioned.fill(
              child: IgnorePointer(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: side * .15),
                  child: Center(child: widget.center),
                ),
              ),
            ),
          ]),
        ),
      );
    });
  }
}

class _Cfg {
  final double r, w, gap;
  final bool ring;
  const _Cfg(this.r, this.w, this.gap, this.ring);
}

class _DonutPainter extends CustomPainter {
  final List<(String?, int, Color)> parts;
  final int grand;
  final _Cfg cfg;
  final Color track;
  final Color ringColor;
  _DonutPainter(
      {required this.parts,
      required this.grand,
      required this.cfg,
      required this.track,
      required this.ringColor});

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 200;
    final c = Offset(size.width / 2, size.height / 2);
    final r = cfg.r * scale;
    final w = cfg.w * scale;

    // background track circle (opacity .45)
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w
          ..color = track.withValues(alpha: .45));

    // decorative dashed ring (styles A/C): stroke-dasharray 1 7, width 1.1
    if (cfg.ring) {
      final ringR = r + w / 2 + 6 * scale;
      final dashPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1 * scale
        ..strokeCap = StrokeCap.round
        ..color = ringColor.withValues(alpha: .3);
      final circumference = 2 * math.pi * ringR;
      final dashCount = (circumference / (8 * scale)).floor();
      for (var i = 0; i < dashCount; i++) {
        final a0 = i * 2 * math.pi / dashCount;
        canvas.drawArc(Rect.fromCircle(center: c, radius: ringR), a0,
            (1 * scale) / ringR, false, dashPaint);
      }
    }

    if (grand == 0 || parts.isEmpty) return;

    // segments: start at -90° (rotate(-90) on the svg), gap° trimmed,
    // round caps — stroke-linecap:round
    var angle = -90.0;
    for (final (_, sum, color) in parts) {
      final frac = grand > 0 ? sum / grand : 0.0;
      final sweep = frac * 360 - (parts.length > 1 ? cfg.gap : 0);
      if (sweep > 0) {
        canvas.drawArc(
            Rect.fromCircle(center: c, radius: r),
            angle * math.pi / 180,
            sweep * math.pi / 180,
            false,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = w
              ..strokeCap = StrokeCap.round
              ..color = color);
      }
      angle += frac * 360;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.parts != parts || old.grand != grand || old.cfg != cfg;
}
