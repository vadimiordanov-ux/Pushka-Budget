import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/db/database.dart';

/// App lock — port of the PIN + WebAuthn (→ BiometricPrompt) logic.
/// PIN hash & fail counters live in SharedPreferences like the PWA kept them
/// in localStorage (they gate the UI, they are not the data encryption key);
/// the master `app_lock` flag lives in settings, PWA-parity.
class LockService {
  final AppDb db;
  final LocalAuthentication _auth = LocalAuthentication();
  LockService(this.db);

  static const _kPinHash = 'applock_pin_hash';
  static const _kFails = 'applock_pin_fails';
  static const _kLockUntil = 'applock_pin_lockuntil';
  static const _kBio = 'bio_enrolled';
  static const _kHideAt = 'applock_hide_at';

  Future<SharedPreferences> get _p => SharedPreferences.getInstance();

  // ---- state ----
  Future<bool> get lockEnabled async => (await db.getSetting('app_lock')) == true;
  Future<int> get timeoutMinutes async =>
      int.tryParse('${await db.getSetting('applock_timeout') ?? 0}') ?? 0;

  Future<bool> get hasPin async => (await _p).getString(_kPinHash) != null;
  Future<bool> get hasBio async => (await _p).getBool(_kBio) ?? false;

  Future<bool> bioAvailable() async {
    try {
      return await _auth.isDeviceSupported() && await _auth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  // ---- PIN (sha-256, same as sha256Hex in the PWA) ----
  String _hash(String pin) => sha256.convert(utf8.encode(pin)).toString();

  Future<void> setPin(String pin) async =>
      (await _p).setString(_kPinHash, _hash(pin));

  Future<bool> checkPin(String pin) async {
    final h = (await _p).getString(_kPinHash);
    return h != null && h == _hash(pin);
  }

  // ---- escalating cooldown: 30/60/120/300 s after 5 fails ----
  Future<int> get fails async => (await _p).getInt(_kFails) ?? 0;

  Future<int> lockSecsLeft() async {
    final until = (await _p).getInt(_kLockUntil) ?? 0;
    final left = ((until - DateTime.now().millisecondsSinceEpoch) / 1000).ceil();
    return left > 0 ? left : 0;
  }

  Future<void> registerFail() async {
    final p = await _p;
    final n = (p.getInt(_kFails) ?? 0) + 1;
    await p.setInt(_kFails, n);
    if (n >= 5) {
      const durations = [30, 60, 120, 300];
      final d = durations[(n - 5) > 3 ? 3 : (n - 5)];
      await p.setInt(
          _kLockUntil, DateTime.now().millisecondsSinceEpoch + d * 1000);
    }
  }

  Future<void> registerSuccess() async {
    final p = await _p;
    await p.remove(_kFails);
    await p.remove(_kLockUntil);
  }

  // ---- biometrics (platform authenticator ≙ WebAuthn enroll/verify) ----
  Future<bool> enrollBio() async {
    final ok = await verifyBio(reason: 'Підтвердь, що це ти');
    if (ok) await (await _p).setBool(_kBio, true);
    return ok;
  }

  Future<bool> verifyBio({String reason = 'Розблокувати Бюджет'}) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
            biometricOnly: true, stickyAuth: true),
      );
    } catch (_) {
      return false;
    }
  }

  // ---- enable / disable / reset (resetAppLock parity) ----
  Future<void> disable() async {
    final p = await _p;
    await p.remove(_kPinHash);
    await p.remove(_kFails);
    await p.remove(_kLockUntil);
    await p.setBool(_kBio, false);
    await db.setSetting('app_lock', false);
  }

  // ---- background/resume relock (visibilitychange parity) ----
  Future<void> markHidden() async => (await _p)
      .setInt(_kHideAt, DateTime.now().millisecondsSinceEpoch);

  Future<bool> shouldRelockOnResume() async {
    if (!await lockEnabled) return false;
    final hideAt = (await _p).getInt(_kHideAt) ?? 0;
    final timeoutMs = (await timeoutMinutes) * 60000;
    return hideAt == 0 ||
        DateTime.now().millisecondsSinceEpoch - hideAt >= timeoutMs;
  }
}
