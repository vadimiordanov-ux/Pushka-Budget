import 'package:drift/drift.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../data/db/database.dart';

/// Monobank tokens — live banking credentials.
/// The token string is stored ONLY in flutter_secure_storage
/// (Android Keystore-backed EncryptedSharedPreferences / iOS Keychain);
/// never in SQLite, never in SharedPreferences. The MonoTokens table keeps
/// non-secret metadata (owner label, rate-limit clock, sync watermark).
class TokenVault {
  final AppDb db;
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  TokenVault(this.db);

  static String _key(String id) => 'mono_token_$id';

  Stream<List<MonoToken>> watch() => db.select(db.monoTokens).watch();
  Future<List<MonoToken>> all() => db.select(db.monoTokens).get();

  Future<String?> secret(String id) => _storage.read(key: _key(id));

  /// Add a token. [ownerKey] drives owner attribution & В/А badges —
  /// 'vadim' and 'alisa' keep the existing per-person credit/badge logic;
  /// any other label becomes its own owner.
  Future<String> add({
    required String token,
    required String ownerKey,
    required String label,
  }) async {
    final id = genUuid();
    await _storage.write(key: _key(id), value: token);
    await db.into(db.monoTokens).insert(MonoTokensCompanion.insert(
        id: id, ownerKey: ownerKey, label: label));
    return id;
  }

  Future<void> rename(String id,
      {required String ownerKey, required String label}) async {
    await (db.update(db.monoTokens)..where((t) => t.id.equals(id))).write(
        MonoTokensCompanion(ownerKey: Value(ownerKey), label: Value(label)));
  }

  /// Remove token + its secret. Accounts discovered by it stay (history keeps
  /// its owner attribution) unless [wipeAccounts] is set.
  Future<void> remove(String id, {bool wipeAccounts = false}) async {
    await _storage.delete(key: _key(id));
    if (wipeAccounts) {
      await (db.delete(db.accounts)..where((a) => a.tokenId.equals(id))).go();
    }
    await (db.delete(db.monoTokens)..where((t) => t.id.equals(id))).go();
  }

  // ---- persisted per-token rate-limit clock (shared with WorkManager) ----
  Future<DateTime?> lastCallAt(String id) async {
    final t = await (db.select(db.monoTokens)..where((x) => x.id.equals(id)))
        .getSingleOrNull();
    return t?.lastApiCallAt;
  }

  Future<void> markCall(String id) async {
    await (db.update(db.monoTokens)..where((x) => x.id.equals(id)))
        .write(MonoTokensCompanion(lastApiCallAt: Value(DateTime.now())));
  }

  Future<void> setSyncedAt(String id, int unixSeconds) async {
    await (db.update(db.monoTokens)..where((x) => x.id.equals(id)))
        .write(MonoTokensCompanion(lastSyncedAt: Value(unixSeconds)));
  }
}
