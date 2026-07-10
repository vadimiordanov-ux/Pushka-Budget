import 'dart:async';

import 'package:drift/drift.dart';

import '../data/db/database.dart';
import '../data/repos/repos.dart';
import 'monobank_api.dart';
import 'token_vault.dart';

/// MCC → category-name fallback when no rule matched.
/// Verbatim MCC_MAP from supabase/functions/mono-webhook/index.ts.
const Map<int, String> kMccMap = {
  5411: 'Їжа/вода', 5499: 'Їжа/вода', 5451: 'Їжа/вода',
  5812: 'Кафе/ресторани', 5814: 'Кафе/ресторани',
  5813: 'Кальян/Алко', 5921: 'Кальян/Алко',
  4111: 'Траспорт/таксі', 4121: 'Траспорт/таксі', 4131: 'Траспорт/таксі',
  5541: 'Траспорт/таксі',
  5912: 'Таблетки/доктора', 8011: 'Таблетки/доктора', 8021: 'Таблетки/доктора',
  8062: 'Таблетки/доктора', 8099: 'Таблетки/доктора',
  742: 'Котовитрати', 5995: 'Котовитрати',
  4814: "Інтрнет/зв'язок/підписки", 4899: "Інтрнет/зв'язок/підписки",
  5651: 'Одяг', 5661: 'Одяг', 5691: 'Одяг', 5699: 'Одяг',
  7230: 'Догляд', 5977: 'Косметика/Гігіена',
  7832: 'Розваги', 7996: 'Розваги', 7999: 'Розваги',
  7997: 'Спорт', 5941: 'Спорт',
  5942: 'Хоббі', 5945: 'Хоббі', 5192: 'Хоббі',
  4900: 'Рахунки', 6513: 'Рахунки',
  5722: 'Для дому', 5719: 'Для дому', 5200: 'Для дому', 5712: 'Для дому',
};

class SyncProgress {
  final String stage; // 'clientInfo' | 'statement' | 'waiting' | 'done'
  final String? ownerLabel;
  final int newTx;
  const SyncProgress(this.stage, {this.ownerLabel, this.newTx = 0});
}

class SyncResult {
  final int newTx;
  final List<Transaction> inserted;
  final List<String> errors;
  const SyncResult(this.newTx, this.inserted, this.errors);
}

/// Polling replacement for the Monobank webhook + mono-credit-sync.
/// VERIFIED (2026-07-10) against the deployed mono-webhook, mono-backfill
/// and mono-credit-sync sources: substring+MCC categorization, 31-day
/// windows with 61 s waits and 429 retry, dedupe by statement id,
/// UAH-cards-only credit snapshots keyed (account_id, day).
///
/// Invariants preserved from the original backend:
///  • rate limit: 1 request / 60 s per token — persisted clock in MonoTokens,
///    shared between foreground and the WorkManager isolate; different tokens
///    are interleaved so a 2-token cycle needs no artificial waits (like the
///    old function calling vadim's then alisa's token back-to-back).
///  • statement window ≤ 31 days; response capped at 500 rows → paginate by
///    moving `to` down to the oldest returned item (API returns newest-first).
///  • dedupe: INSERT OR IGNORE on statement item id (webhook parity).
///  • owner attribution: statements are fetched ONLY for accounts discovered
///    by that same token (accounts.tokenId), so one person's transactions can
///    never be attributed to the other (the "all as Alisa's" bug fix).
///  • categorization: v3.3 semantics per migration.sql — exact description
///    match AND (rule.mcc IS NULL OR rule.mcc = tx.mcc), priority asc;
///    MCC map fallback; incomes stay uncategorized (client maps salaries).
class SyncService {
  final AppDb db;
  final MonobankApi api;
  final TokenVault vault;
  SyncService(this.db, this.api, this.vault);

  static const _rateGap = Duration(seconds: 61);
  static const _windowSec = 31 * 24 * 3600; // 31-day statement window
  static const _overlapSec = 2 * 3600; // re-fetch overlap for late postings
  static const _initialBackfillSec = 93 * 24 * 3600; // first sync: ~3 periods

  /// Waits until [tokenId]'s 60-second budget allows another call.
  /// [budget] (background) caps total waiting so a WorkManager run finishes.
  Future<bool> _waitBudget(String tokenId, DateTime? deadline,
      void Function(SyncProgress)? onProgress, String label) async {
    final last = await vault.lastCallAt(tokenId);
    if (last == null) return true;
    final ready = last.add(_rateGap);
    final now = DateTime.now();
    if (!ready.isAfter(now)) return true;
    if (deadline != null && ready.isAfter(deadline)) return false;
    onProgress?.call(SyncProgress('waiting', ownerLabel: label));
    await Future.delayed(ready.difference(now));
    return true;
  }

  Future<T> _call<T>(String tokenId, Future<T> Function() fn) async {
    await vault.markCall(tokenId);
    try {
      return await fn();
    } on MonoRateLimitException {
      // 429 → wait a full budget and retry once (mono-backfill parity)
      await Future.delayed(_rateGap);
      await vault.markCall(tokenId);
      return await fn();
    }
  }

  /// Full sync cycle over all stored tokens.
  /// [maxDuration] bounds the run (WorkManager); foreground passes null.
  Future<SyncResult> syncAll({
    void Function(SyncProgress)? onProgress,
    Duration? maxDuration,
  }) async {
    final deadline =
        maxDuration == null ? null : DateTime.now().add(maxDuration);
    final tokens = await vault.all();
    final inserted = <Transaction>[];
    final errors = <String>[];
    final today = DateTime.now().toIso8601String().substring(0, 10);

    // Round-robin over tokens: client-info (accounts + credit) first when the
    // daily snapshot is missing, then statement windows per account.
    for (final t in tokens) {
      final secret = await vault.secret(t.id);
      if (secret == null || secret.isEmpty) {
        errors.add('${t.label}: no token');
        continue;
      }
      try {
        // -- 1. accounts + credit snapshot (once per day per token) --
        final haveToday = await (db.select(db.creditLimitSnapshots)
              ..where((s) => s.day.equals(today) & s.owner.equals(t.ownerKey))
              ..limit(1))
            .get();
        final accountsKnown = await (db.select(db.accounts)
              ..where((a) => a.tokenId.equals(t.id)))
            .get();
        if (haveToday.isEmpty || accountsKnown.isEmpty) {
          if (!await _waitBudget(t.id, deadline, onProgress, t.label)) break;
          onProgress?.call(SyncProgress('clientInfo', ownerLabel: t.label));
          final info = await _call(t.id, () => api.clientInfo(secret));
          for (final a in info.accounts) {
            if (a.currencyCode != 980) continue; // UAH cards only, as before
            await db.into(db.accounts).insertOnConflictUpdate(
                AccountsCompanion(
                    id: Value(a.id),
                    owner: Value(t.ownerKey),
                    cardName: Value(
                        '${t.label} mono ${a.type}${a.maskedPan != null ? ' ${a.maskedPan}' : ''}'),
                    tokenId: Value(t.id)));
            if (a.creditLimit > 0) {
              await db.into(db.creditLimitSnapshots).insertOnConflictUpdate(
                  CreditLimitSnapshotsCompanion(
                      owner: Value(t.ownerKey),
                      accountId: Value(a.id),
                      day: Value(today),
                      creditLimitKop: Value(a.creditLimit),
                      balanceKop: Value(a.balance),
                      maskedPan: Value(a.maskedPan)));
            }
          }
        }

        // -- 2. statements per account of THIS token only --
        final accounts = await (db.select(db.accounts)
              ..where((a) => a.tokenId.equals(t.id)))
            .get();
        final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        var from = t.lastSyncedAt > 0
            ? t.lastSyncedAt - _overlapSec
            : nowSec - _initialBackfillSec;
        var maxSeen = t.lastSyncedAt;

        for (final acc in accounts) {
          for (var start = from; start < nowSec; start += _windowSec) {
            final end = start + _windowSec > nowSec ? nowSec : start + _windowSec;
            var to = end;
            // paginate inside the window: 500-row cap, newest-first
            while (true) {
              if (!await _waitBudget(t.id, deadline, onProgress, t.label)) {
                return _finish(inserted, errors);
              }
              onProgress?.call(SyncProgress('statement', ownerLabel: t.label));
              final items =
                  await _call(t.id, () => api.statement(secret, acc.id, start, to));
              for (final item in items) {
                final isNew = await _insertItem(acc.id, item);
                if (isNew != null) {
                  inserted.add(isNew);
                  if (item.time > maxSeen) maxSeen = item.time;
                }
              }
              if (items.length < 500) break;
              // more rows below: move `to` to the oldest item returned
              final oldest =
                  items.map((i) => i.time).reduce((a, b) => a < b ? a : b);
              if (oldest <= start) break;
              to = oldest - 1;
            }
          }
        }
        if (maxSeen > t.lastSyncedAt) await vault.setSyncedAt(t.id, maxSeen);
      } on MonoApiException catch (e) {
        errors.add('${t.label}: $e');
      } catch (e) {
        errors.add('${t.label}: $e');
      }
    }

    // auto-mark internal transfers, PWA-parity (runs after every sync)
    if (inserted.isNotEmpty) await TxRepo(db).autoMarkTransfers();
    return _finish(inserted, errors);
  }

  SyncResult _finish(List<Transaction> inserted, List<String> errors) =>
      SyncResult(inserted.length, inserted, errors);

  /// Insert one statement item with dedupe + categorization.
  /// Returns the inserted row, or null when it already existed.
  Future<Transaction?> _insertItem(String accountId, MonoStatementItem item) async {
    final exists = await (db.select(db.transactions)
          ..where((x) => x.id.equals(item.id))
          ..limit(1))
        .getSingleOrNull();
    if (exists != null) return null;

    String? categoryId;
    String? subcategory;
    if (item.amount < 0) {
      final c = await _categorize(item.description, item.mcc);
      categoryId = c.$1;
      subcategory = c.$2;
    }
    final row = TransactionsCompanion(
      id: Value(item.id),
      accountId: Value(accountId),
      time: Value(DateTime.fromMillisecondsSinceEpoch(item.time * 1000)),
      description: Value(item.description),
      mcc: Value(item.mcc),
      amount: Value(item.amount),
      currency: Value(item.currencyCode),
      cashback: Value(item.cashbackAmount),
      categoryId: Value(categoryId),
      subcategory: Value(subcategory),
      note: Value(item.comment),
      balance: Value(item.balance),
      source: const Value('monobank'),
    );
    final n =
        await db.into(db.transactions).insert(row, mode: InsertMode.insertOrIgnore);
    if (n == 0) return null;
    return await (db.select(db.transactions)..where((x) => x.id.equals(item.id)))
        .getSingle();
  }

  /// Matching semantics VERIFIED against the deployed mono-webhook source:
  /// case-insensitive SUBSTRING (`desc.includes(pattern)`) + optional MCC,
  /// priority asc — the migration.sql "switch to exact" note was never
  /// applied to the worker. Exact patterns still match (a string contains
  /// itself), and seed rules like 'Bolt'/'Аптека' keep working.
  /// Client-side rule creation stays exact-match (createRule, v3.3 parity).
  Future<(String?, String?)> _categorize(String description, int mcc) async {
    final rules = await (db.select(db.categoryRules)
          ..orderBy([(r) => OrderingTerm.asc(r.priority)]))
        .get();
    final desc = description.toLowerCase();
    for (final r in rules) {
      if (desc.contains(r.pattern.toLowerCase()) &&
          (r.mcc == null || r.mcc == mcc)) {
        return (r.categoryId, r.subcategory);
      }
    }
    final catName = kMccMap[mcc];
    if (catName != null) {
      final cat = await (db.select(db.categories)
            ..where((c) => c.name.equals(catName) & c.type.equals('expense'))
            ..limit(1))
          .getSingleOrNull();
      if (cat != null) return (cat.id, null);
    }
    return (null, null);
  }
}
