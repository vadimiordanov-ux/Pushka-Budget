import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart' hide Column;
import 'package:flutter/material.dart' as m show Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/haptics.dart';
import '../../core/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../state.dart';
import '../widgets/common.dart';

/// Lock screen — port of showLockScreen(): biometric mode (auto-attempt),
/// PIN keypad (4 dots, shake on error), escalating cooldown screen with live
/// countdown, forgot-PIN reset flow. Rendered as a blurred full-screen
/// overlay above the app.
class LockScreen extends ConsumerStatefulWidget {
  final VoidCallback onUnlocked;
  const LockScreen({super.key, required this.onUnlocked});
  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen>
    with SingleTickerProviderStateMixin {
  String _mode = 'boot'; // boot | bio | pin | locked | forgot
  String _pin = '';
  Timer? _cd;
  int _cdLeft = 0;

  late final AnimationController _shake = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 350));

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final lock = ref.read(lockServiceProvider);
    final hasBio = await lock.hasBio;
    if (!mounted) return;
    setState(() => _mode = hasBio ? 'bio' : 'pin');
    if (hasBio) _tryBio();
  }

  @override
  void dispose() {
    _cd?.cancel();
    _shake.dispose();
    super.dispose();
  }

  Future<void> _tryBio() async {
    final lock = ref.read(lockServiceProvider);
    if (await lock.verifyBio()) {
      haptic(HapticKind.select);
      widget.onUnlocked();
    } else {
      haptic();
    }
  }

  Future<void> _checkCooldown() async {
    final lock = ref.read(lockServiceProvider);
    final left = await lock.lockSecsLeft();
    if (left > 0 && _mode == 'pin') {
      setState(() {
        _mode = 'locked';
        _cdLeft = left;
      });
      _cd?.cancel();
      _cd = Timer.periodic(const Duration(milliseconds: 500), (_) async {
        final s = await lock.lockSecsLeft();
        if (!mounted) return;
        if (s <= 0) {
          _cd?.cancel();
          setState(() => _mode = 'pin');
        } else if (s != _cdLeft) {
          setState(() => _cdLeft = s);
        }
      });
    }
  }

  Future<void> _digit(String d) async {
    if (_pin.length >= 4) return;
    haptic();
    setState(() => _pin += d);
    if (_pin.length < 4) return;
    final lock = ref.read(lockServiceProvider);
    if (await lock.checkPin(_pin)) {
      await lock.registerSuccess();
      haptic(HapticKind.select);
      widget.onUnlocked();
    } else {
      await lock.registerFail();
      haptic();
      _shake.forward(from: 0);
      await Future.delayed(const Duration(milliseconds: 260));
      if (!mounted) return;
      setState(() => _pin = '');
      await _checkCooldown();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = tk(context);
    final l = L.of(context);
    final lock = ref.read(lockServiceProvider);

    return SizedBox.expand(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          color: t.bg.withValues(alpha: .88),
          child: Material(
            color: Colors.transparent,
            child: Center(
              child: AnimatedBuilder(
                animation: _shake,
                builder: (_, child) {
                  // al-shake keyframes: ±6..10px horizontal
                  final k = _shake.value;
                  final dx = k == 0 || k == 1
                      ? 0.0
                      : (k * 10).floor().isEven
                          ? -8.0 * (1 - k)
                          : 9.0 * (1 - k);
                  return Transform.translate(
                      offset: Offset(dx, 0), child: child);
                },
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: switch (_mode) {
                    'bio' => _bioCard(t, l, lock),
                    'locked' => _lockedCard(t, l, lock),
                    'forgot' => _forgotCard(t, l, lock),
                    'pin' => _pinCard(t, l, lock),
                    _ => const SizedBox.shrink(),
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _icon(Tokens t, IconData icon, {Color? color}) => Container(
        width: 84,
        height: 84,
        alignment: Alignment.center,
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
            gradient: color == null ? t.gradient : null,
            color: color,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: t.glow, blurRadius: 30)]),
        child: Icon(icon, size: 44, color: t.accentInk),
      );

  Widget _title(Tokens t, String s) => Text(s,
      style: TextStyle(
          fontFamily: AppText.display,
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: t.ink));

  Widget _sub(Tokens t, String s) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 14),
        child: Text(s,
            textAlign: TextAlign.center,
            style: TextStyle(color: t.ink2, fontSize: 13.5, height: 1.5)),
      );

  Widget _link(Tokens t, String s, VoidCallback onTap) => Press(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Text(s,
              style: TextStyle(
                  color: t.ink2,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700)),
        ),
      );

  Widget _bioCard(Tokens t, L l, dynamic lock) => m.Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _icon(t, Icons.fingerprint_rounded),
          _title(t, l.xLockedTitle),
          _sub(t, l.xConfirmYou),
          SizedBox(
              width: 200,
              child: Btn(l.xUnlock, margin: EdgeInsets.zero, onTap: _tryBio)),
          FutureBuilder<bool>(
            future: lock.hasPin as Future<bool>,
            builder: (_, snap) => snap.data == true
                ? _link(t, l.xEnterPin, () => setState(() {
                      _mode = 'pin';
                      _pin = '';
                    }))
                : _link(t, l.xResetLock,
                    () => setState(() => _mode = 'forgot')),
          ),
        ],
      );

  Widget _lockedCard(Tokens t, L l, dynamic lock) => m.Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _icon(t, Icons.lock_clock_rounded),
          _title(t, l.xTooManyTries),
          _sub(t, l.xTryInS('$_cdLeft')),
          FutureBuilder<bool>(
            future: lock.hasBio as Future<bool>,
            builder: (_, snap) => snap.data == true
                ? _link(t, l.xLockBioOrPin,
                    () => setState(() => _mode = 'bio'))
                : const SizedBox.shrink(),
          ),
        ],
      );

  Widget _forgotCard(Tokens t, L l, dynamic lock) => m.Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _icon(t, Icons.lock_open_rounded, color: t.expense),
          _title(t, l.xResetLockQ),
          _sub(t, l.xResetLockSub),
          SizedBox(
            width: 200,
            child: Press(
              onTap: () async {
                haptic(HapticKind.select);
                await (lock.disable() as Future<void>);
                widget.onUnlocked();
                if (mounted) ToastHost.show(context, l.xLockResetToast);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                    color: t.expense,
                    borderRadius: BorderRadius.circular(14)),
                child: Center(
                  child: Text(l.xReset2,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 15)),
                ),
              ),
            ),
          ),
          _link(t, l.xCancel, () => setState(() {
                _mode = 'pin';
                _pin = '';
              })),
        ],
      );

  Widget _pinCard(Tokens t, L l, dynamic lock) => m.Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _icon(t, Icons.password_rounded),
          _title(t, l.xLockedTitle),
          _sub(t, l.xTypePin),
          PinDots(len: _pin.length),
          const SizedBox(height: 22),
          Keypad(
              onDigit: _digit,
              onBack: () => setState(
                  () => _pin = _pin.isEmpty ? '' : _pin.substring(0, _pin.length - 1))),
          FutureBuilder<bool>(
            future: lock.hasBio as Future<bool>,
            builder: (_, snap) => m.Column(children: [
              if (snap.data == true)
                _link(t, l.xLockBioOrPin, () {
                  setState(() => _mode = 'bio');
                  _tryBio();
                }),
              _link(t, l.xForgotPin, () => setState(() => _mode = 'forgot')),
            ]),
          ),
        ],
      );
}

// ============================================================================
/// .pin-dots
class PinDots extends StatelessWidget {
  final int len;
  final int max;
  const PinDots({super.key, required this.len, this.max = 4});
  @override
  Widget build(BuildContext context) {
    final t = tk(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < max; i++)
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 13,
          height: 13,
          margin: const EdgeInsets.symmetric(horizontal: 7),
          decoration: BoxDecoration(
            gradient: i < len ? t.gradient : null,
            border: i < len ? null : Border.all(color: t.ink3, width: 2),
            shape: BoxShape.circle,
            boxShadow:
                i < len ? [BoxShadow(color: t.glow, blurRadius: 10)] : null,
          ),
        ),
    ]);
  }
}

/// .kp — 3×4 round keypad
class Keypad extends StatelessWidget {
  final void Function(String) onDigit;
  final VoidCallback onBack;
  const Keypad({super.key, required this.onDigit, required this.onBack});
  @override
  Widget build(BuildContext context) {
    final t = tk(context);
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', 'back'];
    return SizedBox(
      width: 3 * 64 + 2 * 14,
      child: Wrap(spacing: 14, runSpacing: 14, children: [
        for (final k in keys)
          k.isEmpty
              ? const SizedBox(width: 64, height: 64)
              : Press(
                  onTap: () => k == 'back' ? onBack() : onDigit(k),
                  child: Container(
                    width: 64,
                    height: 64,
                    alignment: Alignment.center,
                    decoration: k == 'back'
                        ? null
                        : BoxDecoration(
                            color: t.surface2,
                            border: Border.all(color: t.line),
                            shape: BoxShape.circle),
                    child: k == 'back'
                        ? Icon(Icons.backspace_rounded,
                            size: 22, color: t.ink2)
                        : Text(k,
                            style: TextStyle(
                                fontFamily: AppText.display,
                                fontSize: 20,
                                color: t.ink)),
                  ),
                ),
      ]),
    );
  }
}

// ============================================================================
/// lockModeChoiceSheet() — biometric vs PIN when enabling the lock.
Future<String?> showLockModeChoice(BuildContext context, L l) {
  final t = tk(context);
  return showDialog<String>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
            color: t.surface, borderRadius: BorderRadius.circular(24)),
        child: m.Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 84,
            height: 84,
            alignment: Alignment.center,
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
                gradient: t.gradient,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: t.glow, blurRadius: 30)]),
            child: Icon(Icons.shield_rounded, size: 40, color: t.accentInk),
          ),
          Text(l.xHowProtect,
              style: TextStyle(
                  fontFamily: AppText.display,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: t.ink)),
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 14),
            child: Text(l.xChooseUnlock,
                style: TextStyle(color: t.ink2, fontSize: 13.5)),
          ),
          Btn(l.xLockBioOrPin.split(' або').first, margin: EdgeInsets.zero,
              onTap: () {
            haptic();
            Navigator.pop(ctx, 'bio');
          }),
          Btn(l.xPinCode, kind: 'ghost', onTap: () {
            haptic();
            Navigator.pop(ctx, 'pin');
          }),
          Press(
              onTap: () => Navigator.pop(ctx),
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(l.xCancel,
                    style: TextStyle(
                        color: t.ink2,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700)),
              )),
        ]),
      ),
    ),
  );
}

/// pinSetupFlow() — set a new PIN with confirmation; true when done.
Future<bool> showPinSetupFlow(BuildContext context, WidgetRef ref) async {
  final l = L.of(context);
  final lock = ref.read(lockServiceProvider);
  var stage = 'new';
  var first = '';
  var pin = '';
  var done = false;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
      final t = tk(ctx);
      Future<void> onDigit(String d) async {
        if (pin.length >= 4) return;
        haptic();
        setState(() => pin += d);
        if (pin.length < 4) return;
        await Future.delayed(const Duration(milliseconds: 150));
        if (stage == 'new') {
          setState(() {
            first = pin;
            pin = '';
            stage = 'confirm';
          });
        } else if (pin == first) {
          await lock.setPin(pin);
          haptic(HapticKind.select);
          done = true;
          if (ctx.mounted) Navigator.pop(ctx);
        } else {
          haptic();
          if (ctx.mounted) ToastHost.show(ctx, l.xPinMismatch);
          setState(() {
            pin = '';
            first = '';
            stage = 'new';
          });
        }
      }

      return Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
              color: t.surface, borderRadius: BorderRadius.circular(24)),
          child: m.Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 84,
              height: 84,
              alignment: Alignment.center,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                  gradient: t.gradient,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: t.glow, blurRadius: 30)]),
              child:
                  Icon(Icons.password_rounded, size: 40, color: t.accentInk),
            ),
            Text(stage == 'new' ? l.xSetPin : l.xRepeatPin,
                style: TextStyle(
                    fontFamily: AppText.display,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: t.ink)),
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 14),
              child: Text(
                  stage == 'new' ? l.xPinBackupSub : l.xRepeatSub,
                  style: TextStyle(color: t.ink2, fontSize: 13.5)),
            ),
            PinDots(len: pin.length),
            const SizedBox(height: 22),
            Keypad(
                onDigit: onDigit,
                onBack: () => setState(() =>
                    pin = pin.isEmpty ? '' : pin.substring(0, pin.length - 1))),
            Press(
                onTap: () => Navigator.pop(ctx),
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(l.xCancel,
                      style: TextStyle(
                          color: t.ink2,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700)),
                )),
          ]),
        ),
      );
    }),
  );
  return done;
}
