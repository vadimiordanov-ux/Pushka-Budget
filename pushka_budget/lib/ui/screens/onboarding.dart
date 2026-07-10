import 'package:flutter/material.dart' hide Column;
import 'package:flutter/material.dart' as m show Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/haptics.dart';
import '../../core/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../state.dart';
import '../widgets/common.dart';

/// Onboarding — port of showOnboarding(): 4 steps, swipe + buttons,
/// animated dots, badge pop (scale .7 + rotate -8° in), directional
/// slide-out/slide-in between steps, confetti on the last one.
/// Replaces the Supabase login screen as the first-run experience (flagged).
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  int _i = 0;
  int _dir = 1; // 1 = next (in from right), -1 = back (in from left)
  bool _animating = false;
  bool _leaving = false;

  late final AnimationController _swap = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 520));

  @override
  void initState() {
    super.initState();
    _swap.value = 1;
  }

  @override
  void dispose() {
    _swap.dispose();
    super.dispose();
  }

  Future<void> _go(int dir) async {
    if (_animating) return;
    _animating = true;
    _dir = dir;
    // obOut: .2s out, then obIn: .32s in — approximated with one controller
    await _swap.animateBack(0,
        duration: const Duration(milliseconds: 200), curve: Curves.easeIn);
    setState(() => _i += dir);
    await _swap.animateTo(1,
        duration: const Duration(milliseconds: 320), curve: AppCurves.enter);
    _animating = false;
  }

  Future<void> _finish() async {
    setState(() => _leaving = true);
    await Future.delayed(const Duration(milliseconds: 260));
    await ref.read(dbProvider).setSetting('onboarded', true);
  }

  @override
  Widget build(BuildContext context) {
    final t = tk(context);
    final l = L.of(context);
    final steps = [
      (l.onb1Icon, l.onb1Title, l.onb1Desc),
      (l.onb2Icon, l.onb2Title, l.onb2Desc),
      (l.onb3Icon, l.onb3Title, l.onb3Desc),
      (l.onb4Icon, l.onb4Title, l.onb4Desc),
    ];
    final last = _i == steps.length - 1;
    final s = steps[_i];

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 260),
      opacity: _leaving ? 0 : 1,
      child: Scaffold(
        backgroundColor: t.bg,
        body: Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
                center: const Alignment(.7, -.9),
                radius: 1.1,
                colors: [t.glow, t.glow.withValues(alpha: 0)]),
          ),
          child: SafeArea(
            child: GestureDetector(
              // свайп між кроками, як у решті застосунку
              onHorizontalDragEnd: (d) {
                final vx = d.primaryVelocity ?? 0;
                if (vx.abs() < 100) return;
                if (vx < 0 && _i < steps.length - 1) {
                  haptic();
                  _go(1);
                } else if (vx > 0 && _i > 0) {
                  haptic();
                  _go(-1);
                }
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(26, 12, 26, 30),
                child: m.Column(children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: Press(
                      onTap: _finish,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(l.onbSkip,
                            style: TextStyle(
                                color: t.ink3,
                                fontSize: 13,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                  Expanded(
                    child: AnimatedBuilder(
                      animation: _swap,
                      builder: (_, child) {
                        final k = _swap.value;
                        return Opacity(
                          opacity: k,
                          child: Transform.translate(
                            offset: Offset(_dir * 30 * (1 - k), 0),
                            child: child,
                          ),
                        );
                      },
                      child: Stack(alignment: Alignment.center, children: [
                        if (last)
                          const Positioned.fill(
                            child: IgnorePointer(
                              child: Confetti(colors: [
                                Color(0xFFFFB937), Color(0xFFFF8A3C),
                                Color(0xFF3DDC97), Color(0xFF5B9BD5),
                                Color(0xFFE88BB5), Color(0xFFB98BE0),
                              ], height: double.infinity),
                            ),
                          ),
                        m.Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _Badge(key: ValueKey(_i), emoji: s.$1),
                              const SizedBox(height: 16),
                              Text(s.$2,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontFamily: AppText.display,
                                      fontSize: 25,
                                      height: 1.15,
                                      fontWeight: FontWeight.w700,
                                      color: t.ink)),
                              const SizedBox(height: 16),
                              ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 330),
                                child: Text(s.$3,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        color: t.ink2,
                                        fontSize: 15.5,
                                        height: 1.62,
                                        fontWeight: FontWeight.w500)),
                              ),
                            ]),
                      ]),
                    ),
                  ),
                  // dots
                  Padding(
                    padding: const EdgeInsets.only(top: 18, bottom: 22),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var k = 0; k < steps.length; k++)
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 320),
                              curve: AppCurves.enter,
                              width: k == _i ? 22 : 7,
                              height: 7,
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 3.5),
                              decoration: BoxDecoration(
                                  color: k == _i ? t.accent : t.line,
                                  borderRadius: BorderRadius.circular(99)),
                            ),
                        ]),
                  ),
                  Row(children: [
                    if (_i > 0)
                      SizedBox(
                        width: 62,
                        child: Btn('←', kind: 'ghost',
                            margin: EdgeInsets.zero, onTap: () => _go(-1)),
                      ),
                    if (_i > 0) const SizedBox(width: 10),
                    Expanded(
                      child: Btn(last ? l.onbStart : l.onbNext,
                          margin: EdgeInsets.zero,
                          onTap: () => last ? _finish() : _go(1)),
                    ),
                  ]),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// .ob-badge — 104px rounded tile, obBadgeIn: scale .7 rotate -8° → 1/0
class _Badge extends StatelessWidget {
  final String emoji;
  const _Badge({super.key, required this.emoji});
  @override
  Widget build(BuildContext context) {
    final t = tk(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 500),
      curve: AppCurves.enter,
      builder: (_, k, child) => Opacity(
        opacity: k,
        child: Transform.rotate(
          angle: -8 * (1 - k) * 3.14159 / 180,
          child: Transform.scale(scale: .7 + .3 * k, child: child),
        ),
      ),
      child: Container(
        width: 104,
        height: 104,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Color.alphaBlend(t.accent.withValues(alpha: .16), t.surface2),
          border: Border.all(color: t.line),
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(color: t.glow, blurRadius: 34, offset: const Offset(0, 16))
          ],
        ),
        child: Text(emoji, style: const TextStyle(fontSize: 52)),
      ),
    );
  }
}
