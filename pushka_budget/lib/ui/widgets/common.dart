import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/haptics.dart';
import '../../core/tokens.dart';

/// Shorthand: design tokens of the current skin/theme.
Tokens tk(BuildContext c) => ThemeScope.of(c);

bool reducedMotion(BuildContext c) => MediaQuery.of(c).disableAnimations;

// ============================================================================
// .card — panel gradient, 1px line border, radius 20, soft shadow
// ============================================================================
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;
  const AppCard(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(16),
      this.margin = const EdgeInsets.only(bottom: 12)});

  @override
  Widget build(BuildContext context) {
    final t = tk(context);
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        gradient: t.panel,
        border: Border.all(color: t.line),
        borderRadius: BorderRadius.circular(Tokens.radius),
        boxShadow: t.shadowCard,
      ),
      child: child,
    );
  }
}

// ============================================================================
// .sec-h — section header (Unbounded 12px, letter-spacing .1em)
// ============================================================================
class SecH extends StatelessWidget {
  final String text;
  final Widget? trailing;
  final EdgeInsets margin;
  const SecH(this.text,
      {super.key, this.trailing, this.margin = const EdgeInsets.fromLTRB(2, 24, 2, 10)});

  @override
  Widget build(BuildContext context) {
    final t = tk(context);
    final label = Text(text.toUpperCase(),
        style: TextStyle(
            fontFamily: AppText.display,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: t.ink2));
    return Padding(
      padding: margin,
      child: trailing == null
          ? label
          : Row(children: [Expanded(child: label), trailing!]),
    );
  }
}

// ============================================================================
// button:active{transform:scale(.97)} — pressed-scale wrapper for everything
// ============================================================================
class Press extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  const Press(
      {super.key, required this.child, this.onTap, this.onLongPress, this.scale = .97});
  @override
  State<Press> createState() => _PressState();
}

class _PressState extends State<Press> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

// ============================================================================
// .btn / .btn.ghost / .btn.danger
// ============================================================================
class Btn extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final String kind; // 'primary' | 'ghost' | 'danger'
  final EdgeInsets margin;
  final Widget? leading;
  const Btn(this.label,
      {super.key,
      this.onTap,
      this.kind = 'primary',
      this.margin = const EdgeInsets.only(top: 6),
      this.leading});

  @override
  Widget build(BuildContext context) {
    final t = tk(context);
    final bg = switch (kind) {
      'ghost' => BoxDecoration(
          color: t.surface2, borderRadius: BorderRadius.circular(14)),
      'danger' =>
        BoxDecoration(borderRadius: BorderRadius.circular(14)),
      _ => BoxDecoration(
          gradient: t.gradient,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: t.accent2.withValues(alpha: .3),
                blurRadius: 18,
                offset: const Offset(0, 6))
          ]),
    };
    final fg = switch (kind) {
      'ghost' => t.ink,
      'danger' => t.expense,
      _ => t.accentInk,
    };
    return Padding(
      padding: margin,
      child: Press(
        onTap: onTap == null
            ? null
            : () {
                haptic(HapticKind.select);
                onTap!();
              },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: bg,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (leading != null) ...[leading!, const SizedBox(width: 6)],
            Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: fg, fontWeight: FontWeight.w800, fontSize: 15)),
          ]),
        ),
      ),
    );
  }
}

// ============================================================================
// .seg — segmented control
// ============================================================================
class Seg extends StatelessWidget {
  final List<(String value, String label)> items;
  final String value;
  final ValueChanged<String> onChanged;
  final bool pill; // .tx-type variant uses 99px radius
  const Seg(
      {super.key,
      required this.items,
      required this.value,
      required this.onChanged,
      this.pill = false});

  @override
  Widget build(BuildContext context) {
    final t = tk(context);
    final r = pill ? 99.0 : 12.0;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
          color: t.surface2, borderRadius: BorderRadius.circular(r)),
      child: Row(
        children: [
          for (final (v, label) in items)
            Expanded(
              child: Press(
                onTap: () {
                  if (v != value) haptic();
                  onChanged(v);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: v == value ? t.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(pill ? 99 : 9),
                    boxShadow: v == value
                        ? [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: .18),
                                blurRadius: 8,
                                offset: const Offset(0, 2))
                          ]
                        : null,
                  ),
                  child: Text(label,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: v == value ? t.ink : t.ink2)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================================
// .chipbtn / .chip / .chip.warn
// ============================================================================
class ChipBtn extends StatelessWidget {
  final String label;
  final bool on;
  final bool warn;
  final VoidCallback? onTap;
  final Color? warnColor;
  const ChipBtn(this.label,
      {super.key, this.on = false, this.warn = false, this.onTap, this.warnColor});

  @override
  Widget build(BuildContext context) {
    final t = tk(context);
    final wc = warnColor ?? t.accent;
    return Press(
      onTap: onTap == null
          ? null
          : () {
              haptic();
              onTap!();
            },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: on ? t.gradient : null,
          color: on
              ? null
              : warn
                  ? wc.withValues(alpha: .13)
                  : t.surface2,
          border: Border.all(
              color: (on || warn) ? Colors.transparent : t.line),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: on
                    ? t.accentInk
                    : warn
                        ? wc
                        : t.ink)),
      ),
    );
  }
}

// ============================================================================
// .tgl — toggle switch (44×26, 20px knob)
// ============================================================================
class Tgl extends StatelessWidget {
  final bool on;
  final VoidCallback onTap;
  const Tgl({super.key, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = tk(context);
    return Press(
      onTap: () {
        haptic();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44,
        height: 26,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: on ? t.accent : t.surface2,
          border: Border.all(color: on ? t.accent : t.line),
          borderRadius: BorderRadius.circular(99),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment: on ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
                color: on ? Colors.white : t.ink3, shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Emoji tile — .tx .em / .cr-em: rounded square tinted by category color
// (CSS color-mix(in srgb, C 20%, transparent) bg + 42% border)
// ============================================================================
class EmTile extends StatelessWidget {
  final String emoji;
  final Color? color;
  final double size;
  final double fontSize;
  final double radius;
  const EmTile(this.emoji,
      {super.key, this.color, this.size = 40, this.fontSize = 18, this.radius = 13});

  @override
  Widget build(BuildContext context) {
    final t = tk(context);
    final c = color;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c != null ? c.withValues(alpha: .20) : t.surface2,
        border: Border.all(
            color: c != null ? c.withValues(alpha: .42) : t.line),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Text(emoji, style: TextStyle(fontSize: fontSize)),
    );
  }
}

// ============================================================================
// .owner-badge — В (accent) / А (pink #E88BB5)
// ============================================================================
class OwnerBadge extends StatelessWidget {
  final String ownerKey; // 'vadim' | 'alisa' | other
  final String letter;
  const OwnerBadge(this.ownerKey, this.letter, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = tk(context);
    final alisa = ownerKey == 'alisa';
    final color = alisa ? (t.dark ? const Color(0xFFE88BB5) : const Color(0xFFC2497F)) : t.accent;
    final bg = alisa
        ? (t.dark
            ? const Color(0xFFE88BB5).withValues(alpha: .18)
            : const Color(0xFFD85A96).withValues(alpha: .14))
        : t.accent.withValues(alpha: .16);
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(letter,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w800, color: color)),
    );
  }
}

// ============================================================================
// Staggered entrance — #view>* rowIn/hdRow: fade + translateY(12→0),
// .34-.42s enter curve, delay index*30-55ms. Honors reduced motion.
// ============================================================================
class Enter extends StatelessWidget {
  final int index;
  final Widget child;
  final double dy;
  final int stepMs;
  final int durMs;
  const Enter(
      {super.key,
      required this.index,
      required this.child,
      this.dy = 12,
      this.stepMs = 30,
      this.durMs = 340});

  @override
  Widget build(BuildContext context) {
    if (reducedMotion(context)) return child;
    return _DelayedSlideFade(
        delay: Duration(milliseconds: index * stepMs),
        duration: Duration(milliseconds: durMs),
        dy: dy,
        child: child);
  }
}

class _DelayedSlideFade extends StatefulWidget {
  final Duration delay, duration;
  final double dy;
  final Widget child;
  const _DelayedSlideFade(
      {required this.delay,
      required this.duration,
      required this.dy,
      required this.child});
  @override
  State<_DelayedSlideFade> createState() => _DelayedSlideFadeState();
}

class _DelayedSlideFadeState extends State<_DelayedSlideFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duration);
  late final Animation<double> _a =
      CurvedAnimation(parent: _c, curve: AppCurves.enter);

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _a,
      builder: (_, child) => Opacity(
        opacity: _a.value,
        child: Transform.translate(
            offset: Offset(0, widget.dy * (1 - _a.value)), child: child),
      ),
      child: widget.child,
    );
  }
}

// ============================================================================
// countUp() — 0 → target over 640ms with ease-out cubic
// ============================================================================
class CountUp extends StatelessWidget {
  final num target;
  final String Function(num) format;
  final TextStyle style;
  const CountUp(
      {super.key, required this.target, required this.format, required this.style});

  @override
  Widget build(BuildContext context) {
    if (reducedMotion(context)) return Text(format(target), style: style);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 640),
      curve: AppCurves.countUp,
      builder: (_, k, __) => Text(format(target * k), style: style),
    );
  }
}

// ============================================================================
// Grow bars — barGrow (scaleY) / fillGrow-hdBarW (scaleX), staggered
// ============================================================================
class GrowY extends StatelessWidget {
  final Widget child;
  final int index;
  const GrowY({super.key, required this.child, this.index = 0});
  @override
  Widget build(BuildContext context) {
    if (reducedMotion(context)) return child;
    return _DelayedScale(
        delay: Duration(milliseconds: 30 + index * 50),
        duration: const Duration(milliseconds: 550),
        axis: Axis.vertical,
        child: child);
  }
}

class GrowX extends StatelessWidget {
  final Widget child;
  final int index;
  const GrowX({super.key, required this.child, this.index = 0});
  @override
  Widget build(BuildContext context) {
    if (reducedMotion(context)) return child;
    return _DelayedScale(
        delay: Duration(milliseconds: index * 40),
        duration: const Duration(milliseconds: 700),
        axis: Axis.horizontal,
        child: child);
  }
}

class _DelayedScale extends StatefulWidget {
  final Duration delay, duration;
  final Axis axis;
  final Widget child;
  const _DelayedScale(
      {required this.delay,
      required this.duration,
      required this.axis,
      required this.child});
  @override
  State<_DelayedScale> createState() => _DelayedScaleState();
}

class _DelayedScaleState extends State<_DelayedScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duration);
  late final Animation<double> _a =
      CurvedAnimation(parent: _c, curve: AppCurves.pop);

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _a,
      builder: (_, child) => Transform.scale(
        scaleY: widget.axis == Axis.vertical ? _a.value : 1,
        scaleX: widget.axis == Axis.horizontal ? _a.value : 1,
        alignment: widget.axis == Axis.vertical
            ? Alignment.bottomCenter
            : Alignment.centerLeft,
        child: child,
      ),
      child: widget.child,
    );
  }
}

// ============================================================================
// Progress bar — .cl-bar/.cr-bar/.iw-bar: track surface2, animated fill
// ============================================================================
class Bar extends StatelessWidget {
  final double pct; // 0..100
  final Color color;
  final Gradient? gradient;
  final double height;
  const Bar(
      {super.key,
      required this.pct,
      required this.color,
      this.gradient,
      this.height = 7});

  @override
  Widget build(BuildContext context) {
    final t = tk(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        height: height,
        color: t.surface2,
        alignment: Alignment.centerLeft,
        child: GrowX(
          child: FractionallySizedBox(
            widthFactor: (pct / 100).clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(
                  color: gradient == null ? color : null,
                  gradient: gradient,
                  borderRadius: BorderRadius.circular(6)),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Skeleton shimmer — .skel
// ============================================================================
class Skel extends StatefulWidget {
  final double width, height;
  final double radius;
  const Skel({super.key, required this.width, required this.height, this.radius = 9});
  @override
  State<Skel> createState() => _SkelState();
}

class _SkelState extends State<Skel> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1300))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = tk(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: t.surface2,
            gradient: LinearGradient(
              begin: Alignment(-1 + 2 * _c.value, 0),
              end: Alignment(0 + 2 * _c.value, 0),
              colors: [
                t.surface2,
                t.ink.withValues(alpha: .09),
                t.surface2,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Toast with undo — port of toast(msg, undo): pill above the tab bar,
// auto-hide 2.2s (7s with undo)
// ============================================================================
class ToastHost {
  static OverlayEntry? _entry;

  static void show(BuildContext context, String msg,
      {Future<void> Function()? undo, String undoLabel = 'Скасувати'}) {
    dismiss();
    final overlay = Overlay.of(context, rootOverlay: true);
    _entry = OverlayEntry(
        builder: (_) => _Toast(
            msg: msg,
            undo: undo,
            undoLabel: undoLabel,
            onDone: dismiss));
    overlay.insert(_entry!);
  }

  static void dismiss() {
    _entry?.remove();
    _entry = null;
  }
}

class _Toast extends StatefulWidget {
  final String msg;
  final Future<void> Function()? undo;
  final String undoLabel;
  final VoidCallback onDone;
  const _Toast(
      {required this.msg,
      required this.undo,
      required this.undoLabel,
      required this.onDone});
  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 250))
    ..forward();

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.undo != null ? 7000 : 2200),
        () {
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = tk(context);
    return Positioned(
      left: 0,
      right: 0,
      bottom: 96 + MediaQuery.of(context).padding.bottom,
      child: FadeTransition(
        opacity: _c,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, .5), end: Offset.zero)
              .animate(CurvedAnimation(parent: _c, curve: Curves.easeOut)),
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                decoration: BoxDecoration(
                  color: t.surface2.withValues(alpha: .92),
                  border: Border.all(color: t.line),
                  borderRadius: BorderRadius.circular(99),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: .35),
                        blurRadius: 24,
                        offset: const Offset(0, 8))
                  ],
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(
                      child: Text(widget.msg,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: t.ink,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700))),
                  if (widget.undo != null) ...[
                    const SizedBox(width: 12),
                    Press(onTap: () async {
                      haptic();
                      widget.onDone();
                      try {
                        await widget.undo!();
                      } catch (_) {}
                    },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 13, vertical: 5),
                          decoration: BoxDecoration(
                              gradient: t.gradient,
                              borderRadius: BorderRadius.circular(99)),
                          child: Text(widget.undoLabel,
                              style: TextStyle(
                                  color: t.accentInk,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800)),
                        )),
                  ],
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Bottom sheet — .sheet: slide-up .38s with cubic-bezier(.22,1,.36,1)
// (overshoot), grab handle, radius 24 top, 88% max height
// ============================================================================
Future<T?> showAppSheet<T>(BuildContext context, Widget child) {
  final t = tk(context);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x9905060A).withValues(alpha: .6),
    sheetAnimationStyle: AnimationStyle(
        duration: const Duration(milliseconds: 380),
        reverseDuration: const Duration(milliseconds: 260),
        curve: AppCurves.sheet,
        reverseCurve: AppCurves.exit),
    builder: (ctx) => ThemeScope(
      t: t,
      child: Container(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * .88, maxWidth: 520),
        decoration: BoxDecoration(
          color: t.surface,
          border: Border.all(color: t.line),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.only(
            left: 18,
            right: 18,
            top: 10,
            bottom: 22 + MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(top: 4, bottom: 16),
                    decoration: BoxDecoration(
                        color: t.line,
                        borderRadius: BorderRadius.circular(2))),
              ),
              child,
            ],
          ),
        ),
      ),
    ),
  );
}

/// Sheet <h2> — Unbounded 17px
class SheetTitle extends StatelessWidget {
  final String text;
  const SheetTitle(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: TextStyle(
                fontFamily: AppText.display,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: tk(context).ink)),
      );
}

/// .meta — sheet caption
class SheetMeta extends StatelessWidget {
  final String text;
  const SheetMeta(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Text(text,
            style: TextStyle(color: tk(context).ink2, fontSize: 13, height: 1.55)),
      );
}

// ============================================================================
// .fld — labeled field
// ============================================================================
class Fld extends StatelessWidget {
  final String label;
  final Widget child;
  const Fld(this.label, {super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    final t = tk(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(label.toUpperCase(),
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .6,
                  color: t.ink2)),
        ),
        child,
      ]),
    );
  }
}

/// Styled TextField matching input{} CSS
class AppInput extends StatelessWidget {
  final TextEditingController? controller;
  final String? placeholder;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final bool obscure;
  final int maxLines;
  final TextAlign textAlign;
  final double fontSize;
  const AppInput(
      {super.key,
      this.controller,
      this.placeholder,
      this.keyboardType,
      this.onChanged,
      this.obscure = false,
      this.maxLines = 1,
      this.textAlign = TextAlign.start,
      this.fontSize = 16});

  @override
  Widget build(BuildContext context) {
    final t = tk(context);
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      onChanged: onChanged,
      obscureText: obscure,
      maxLines: maxLines,
      textAlign: textAlign,
      style: TextStyle(color: t.ink, fontSize: fontSize),
      decoration: InputDecoration(
        hintText: placeholder,
        hintStyle: TextStyle(color: t.ink3),
        filled: true,
        fillColor: t.surface2,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(Tokens.radiusS),
            borderSide: BorderSide(color: t.line)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(Tokens.radiusS),
            borderSide: BorderSide(color: t.accent, width: 2)),
      ),
    );
  }
}

// ============================================================================
// Confetti — @keyframes confetti: fall 190px + rotate 540°, loop, staggered
// ============================================================================
class Confetti extends StatefulWidget {
  final List<Color> colors;
  final double height;
  const Confetti({super.key, required this.colors, this.height = 190});
  @override
  State<Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<Confetti>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1600))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (reducedMotion(context)) return const SizedBox.shrink();
    return SizedBox(
      height: widget.height,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => CustomPaint(
            size: Size.infinite,
            painter: _ConfettiPainter(widget.colors, _c.value)),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  final List<Color> colors;
  final double t;
  _ConfettiPainter(this.colors, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < colors.length; i++) {
      final delay = (i % 5) * .22 / 1.6;
      var k = t - delay;
      if (k < 0) k += 1;
      final x = size.width * (.08 + i * .12);
      final y = -10 + k * size.height;
      final paint = Paint()..color = colors[i].withValues(alpha: 1 - k);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(k * 3 * 3.14159);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              const Rect.fromLTWH(-4.5, -7, 9, 14), const Radius.circular(3)),
          paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}
