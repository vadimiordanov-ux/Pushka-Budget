import 'package:drift/drift.dart';

import '../../core/period.dart';
import '../db/database.dart';

/// ============================ transactions ============================
class TxRepo {
  final AppDb db;
  TxRepo(this.db);

  /// loadTxs() — transactions of a period, newest first.
  Stream<List<Transaction>> watchPeriod(Period p) => (db.select(db.transactions)
        ..where((t) =>
            t.time.isBiggerOrEqualValue(p.start) & t.time.isSmallerThanValue(p.end))
        ..orderBy([(t) => OrderingTerm.desc(t.time)]))
      .watch();

  Future<List<Transaction>> period(Period p) => (db.select(db.transactions)
        ..where((t) =>
            t.time.isBiggerOrEqualValue(p.start) & t.time.isSmallerThanValue(p.end))
        ..orderBy([(t) => OrderingTerm.desc(t.time)]))
      .get();

  /// loadAll() — full history ascending (no PostgREST 1000-row cap locally).
  Future<List<Transaction>> all() => (db.select(db.transactions)
        ..orderBy([(t) => OrderingTerm.asc(t.time)]))
      .get();

  Stream<List<Transaction>> watchAll() => (db.select(db.transactions)
        ..orderBy([(t) => OrderingTerm.asc(t.time)]))
      .watch();

  Future<void> insert(TransactionsCompanion c) =>
      db.into(db.transactions).insert(c);

  /// INSERT OR IGNORE — dedupe key = monobank statement id (webhook parity).
  Future<bool> insertIgnore(TransactionsCompanion c) async {
    final n = await db.into(db.transactions).insert(c,
        mode: InsertMode.insertOrIgnore);
    return n > 0;
  }

  Future<void> updateFields(String id, TransactionsCompanion patch) =>
      (db.update(db.transactions)..where((t) => t.id.equals(id))).write(patch);

  Future<void> updateMany(List<String> ids, TransactionsCompanion patch) =>
      (db.update(db.transactions)..where((t) => t.id.isIn(ids))).write(patch);

  /// Delete tx + its split children; returns a snapshot for undo.
  Future<List<Transaction>> deleteWithChildren(String id) async {
    final t = await (db.select(db.transactions)..where((x) => x.id.equals(id)))
        .getSingleOrNull();
    if (t == null) return [];
    final kids = await (db.select(db.transactions)
          ..where((x) => x.parentId.equals(id)))
        .get();
    await (db.delete(db.transactions)
          ..where((x) => x.id.equals(id) | x.parentId.equals(id)))
        .go();
    return [t, ...kids];
  }

  Future<void> restore(List<Transaction> snapshot) async {
    // parents first, then children (FK-loose but keeps order sane)
    for (final r in snapshot.where((r) => r.parentId == null)) {
      await db.into(db.transactions).insert(r, mode: InsertMode.insertOrReplace);
    }
    for (final r in snapshot.where((r) => r.parentId != null)) {
      await db.into(db.transactions).insert(r, mode: InsertMode.insertOrReplace);
    }
  }

  /// createRule() port: exact description match (+ same MCC if present),
  /// same sign; applies to ALL past matches — both uncategorized and already
  /// categorized. Returns rule id + previous values for undo.
  Future<({String ruleId, List<String> ids, List<(String, String?, String?)> prev})>
      createRule(Transaction t, String categoryId, String? subcategory,
          {bool subcategoryProvided = false}) async {
    var q = db.select(db.transactions)
      ..where((x) =>
          x.description.equals(t.description) &
          x.parentId.isNull() &
          x.id.equals(t.id).not() &
          (t.amount > 0
              ? x.amount.isBiggerThanValue(0)
              : x.amount.isSmallerThanValue(0)));
    final hits = (await q.get()).where((x) => t.mcc == null || x.mcc == t.mcc);
    final rows = hits
        .where((r) =>
            r.categoryId != categoryId ||
            (subcategoryProvided && (r.subcategory) != (subcategory)))
        .toList();
    final ids = rows.map((r) => r.id).toList();
    final prev = rows
        .map((r) => (r.id, r.categoryId, r.subcategory))
        .toList(growable: false);
    if (ids.isNotEmpty) {
      await updateMany(
          ids,
          TransactionsCompanion(
              categoryId: Value(categoryId),
              subcategory:
                  subcategoryProvided ? Value(subcategory) : const Value.absent()));
    }
    final ruleId = genUuid();
    await db.into(db.categoryRules).insert(CategoryRulesCompanion.insert(
        id: ruleId,
        pattern: t.description,
        categoryId: categoryId,
        mcc: Value(t.mcc),
        subcategory: Value(subcategory),
        priority: const Value(40)));
    return (ruleId: ruleId, ids: ids, prev: prev.toList());
  }

  Future<void> deleteRule(String ruleId) =>
      (db.delete(db.categoryRules)..where((r) => r.id.equals(ruleId))).go();

  /// autoMarkTransfers() port: pairs of ±equal amounts on different accounts
  /// within 15 minutes → internal. Watermark (settings.auto_int_ts) keeps
  /// manually-unticked rows from flipping back.
  Future<int> autoMarkTransfers() async {
    final wmRaw = await db.getSetting('auto_int_ts');
    final wm = wmRaw is String ? DateTime.tryParse(wmRaw) : null;
    final txs = await (db.select(db.transactions)
          ..orderBy([(t) => OrderingTerm.desc(t.time)])
          ..limit(3000))
        .get();
    final pool =
        txs.where((t) => t.parentId == null && t.accountId != null).toList();
    final marked = <String>{};
    final ids = <String>[];
    for (final t in pool) {
      if (t.internal ||
          marked.contains(t.id) ||
          (wm != null && !t.time.isAfter(wm)) ||
          t.amount >= 0) {
        continue;
      }
      Transaction? pair;
      for (final x in pool) {
        if (identical(x, t) || marked.contains(x.id)) continue;
        if (x.amount == -t.amount &&
            x.accountId != t.accountId &&
            x.time.difference(t.time).abs() < const Duration(minutes: 15)) {
          pair = x;
          break;
        }
      }
      if (pair == null) continue;
      marked.add(t.id);
      marked.add(pair.id);
      ids.add(t.id);
      if (!pair.internal) ids.add(pair.id);
    }
    if (ids.isNotEmpty) {
      await updateMany(ids, const TransactionsCompanion(internal: Value(true)));
    }
    final newest = txs.isEmpty ? null : txs.first.time;
    if (newest != null && (wm == null || newest.isAfter(wm))) {
      await db.setSetting('auto_int_ts', newest.toIso8601String());
    }
    return ids.length;
  }
}

/// ============================ categories ============================
class CatRepo {
  final AppDb db;
  CatRepo(this.db);

  Stream<List<Category>> watch() => (db.select(db.categories)
        ..orderBy([(c) => OrderingTerm.asc(c.sortOrder)]))
      .watch();

  Future<List<Category>> all() => (db.select(db.categories)
        ..orderBy([(c) => OrderingTerm.asc(c.sortOrder)]))
      .get();

  Future<void> upsert(CategoriesCompanion c) =>
      db.into(db.categories).insertOnConflictUpdate(c);

  Future<void> patch(String id, CategoriesCompanion c) =>
      (db.update(db.categories)..where((x) => x.id.equals(id))).write(c);

  Future<void> reorder(List<String> idsInOrder) async {
    await db.transaction(() async {
      for (var i = 0; i < idsInOrder.length; i++) {
        await patch(idsInOrder[i], CategoriesCompanion(sortOrder: Value(i + 1)));
      }
    });
  }

  Future<int> txCount(String categoryId) async {
    final c = db.transactions.id.count();
    final q = db.selectOnly(db.transactions)
      ..addColumns([c])
      ..where(db.transactions.categoryId.equals(categoryId));
    return (await q.getSingle()).read(c) ?? 0;
  }

  /// delete flow parity: null out txs, delete rules, delete category.
  Future<void> deleteCascade(String id) async {
    await db.transaction(() async {
      await (db.update(db.transactions)
            ..where((t) => t.categoryId.equals(id)))
          .write(const TransactionsCompanion(categoryId: Value(null)));
      await (db.delete(db.categoryRules)
            ..where((r) => r.categoryId.equals(id)))
          .go();
      await (db.delete(db.categories)..where((c) => c.id.equals(id))).go();
    });
  }
}

/// ============================ planned payments ============================
class PlannedRepo {
  final AppDb db;
  PlannedRepo(this.db);

  Stream<List<PlannedPayment>> watch() => (db.select(db.plannedPayments)
        ..orderBy([(p) => OrderingTerm.asc(p.day)]))
      .watch();

  Future<List<PlannedPayment>> all() => (db.select(db.plannedPayments)
        ..orderBy([(p) => OrderingTerm.asc(p.day)]))
      .get();

  Future<String> upsert(PlannedPaymentsCompanion c) async {
    await db.into(db.plannedPayments).insertOnConflictUpdate(c);
    return c.id.value;
  }

  Future<void> delete(String id) =>
      (db.delete(db.plannedPayments)..where((p) => p.id.equals(id))).go();
}

/// ============================ installments ============================
/// Pure helpers = instMonthly / instNextDue / instPaidKop / instLeftKop.
int instMonthly(Installment i) => (i.totalKop / i.monthsTotal).round();

DateTime instNextDue(Installment i) {
  final first = DateTime.parse(i.firstDue);
  final d = addMonthsClamped(first, i.monthsPaid);
  return DateTime(d.year, d.month, d.day);
}

int instPaidKop(Installment i) {
  final p = instMonthly(i) * i.monthsPaid;
  return p > i.totalKop ? i.totalKop : p;
}

int instLeftKop(Installment i) {
  final l = i.totalKop - instPaidKop(i);
  return l < 0 ? 0 : l;
}

class InstRepo {
  final AppDb db;
  InstRepo(this.db);

  Stream<List<Installment>> watch() => (db.select(db.installments)
        ..orderBy([(i) => OrderingTerm.asc(i.firstDue)]))
      .watch();

  Future<List<Installment>> all() => (db.select(db.installments)
        ..orderBy([(i) => OrderingTerm.asc(i.firstDue)]))
      .get();

  Future<void> upsert(InstallmentsCompanion c) =>
      db.into(db.installments).insertOnConflictUpdate(c);

  Future<void> delete(String id) =>
      (db.delete(db.installments)..where((i) => i.id.equals(id))).go();

  /// instPay(): +1 payment, auto-archive when done.
  Future<bool> pay(String id) async {
    final i = await (db.select(db.installments)..where((x) => x.id.equals(id)))
        .getSingleOrNull();
    if (i == null) return false;
    final mp =
        (i.monthsPaid + 1) > i.monthsTotal ? i.monthsTotal : i.monthsPaid + 1;
    final archived = mp >= i.monthsTotal;
    await (db.update(db.installments)..where((x) => x.id.equals(id))).write(
        InstallmentsCompanion(
            monthsPaid: Value(mp), archived: Value(archived)));
    return archived;
  }
}

/// ============================ credit limits ============================
/// Port of the `credit_now` + `credit_by_owner` views (migration_v3_2.sql),
/// rewritten from Postgres DISTINCT ON to SQLite.
class CreditRow {
  final String owner;
  final int usedKop, limitKop;
  const CreditRow(this.owner, this.usedKop, this.limitKop);
}

class CreditRepo {
  final AppDb db;
  CreditRepo(this.db);

  Stream<List<CreditRow>> watchByOwner() => db
          .customSelect(
        'SELECT owner, '
        ' SUM(MAX(0, credit_limit_kop - balance_kop)) AS used_kop, '
        ' SUM(credit_limit_kop) AS limit_kop '
        'FROM credit_limit_snapshots c1 '
        'WHERE day = (SELECT MAX(day) FROM credit_limit_snapshots c2 '
        '             WHERE c2.account_id = c1.account_id) '
        'GROUP BY owner',
        readsFrom: {db.creditLimitSnapshots},
      )
          .watch()
          .map((rows) => rows
              .map((r) => CreditRow(r.read<String>('owner'),
                  r.read<int>('used_kop'), r.read<int>('limit_kop')))
              .toList());

  Future<void> upsertSnapshot(CreditLimitSnapshotsCompanion c) =>
      db.into(db.creditLimitSnapshots).insertOnConflictUpdate(c);
}

/// ============================ accounts ============================
class AccountsRepo {
  final AppDb db;
  AccountsRepo(this.db);

  Stream<List<Account>> watch() => db.select(db.accounts).watch();
  Future<List<Account>> all() => db.select(db.accounts).get();

  Future<void> upsert(AccountsCompanion c) =>
      db.into(db.accounts).insertOnConflictUpdate(c);

  Future<void> deleteByToken(String tokenId) =>
      (db.delete(db.accounts)..where((a) => a.tokenId.equals(tokenId))).go();
}
