import 'dart:math' as math;

import '../db/database.dart';

/// ============ net analytics core — 1:1 port of computeVals() ============
/// Excludes: internal transfers, reimbursement incomes.
/// A split parent counts as the remainder; a reimbursed expense counts net.
class TxVal {
  final Transaction t;
  final int val; // signed kopecks after split/reimburse math
  const TxVal(this.t, this.val);
}

List<TxVal> computeVals(List<Transaction> list) {
  final kids = <String, int>{};
  final reimb = <String, int>{};
  for (final t in list) {
    if (t.parentId != null) {
      kids[t.parentId!] = (kids[t.parentId!] ?? 0) + t.amount;
    }
    if (t.reimburses != null && t.amount > 0) {
      reimb[t.reimburses!] = (reimb[t.reimburses!] ?? 0) + t.amount;
    }
  }
  final out = <TxVal>[];
  for (final t in list) {
    if (t.internal) continue;
    if (t.amount > 0 && t.reimburses != null) continue;
    var a = t.amount;
    if (t.parentId == null && kids.containsKey(t.id)) a = t.amount - kids[t.id]!;
    if (t.amount < 0 && reimb.containsKey(t.id)) {
      final v = a + reimb[t.id]!;
      a = v < 0 ? v : 0;
    }
    if (a == 0) continue;
    out.add(TxVal(t, a));
  }
  return out;
}

class Sums {
  final List<TxVal> expVals, incVals;
  final int expTotal, incTotal;
  const Sums(this.expVals, this.incVals, this.expTotal, this.incTotal);
}

Sums sums(List<Transaction> txs) {
  final vals = computeVals(txs);
  final exp = vals.where((v) => v.val < 0).toList();
  final inc = vals.where((v) => v.val > 0).toList();
  int total(List<TxVal> a) => a.fold(0, (s, v) => s + v.val.abs());
  return Sums(exp, inc, total(exp), total(inc));
}

/// byCategory(vals) → [(categoryId|null, sumAbs)] sorted desc.
/// null key = «Без категорії» ('__none__' in the PWA).
List<MapEntry<String?, int>> byCategory(List<TxVal> vals) {
  final m = <String?, int>{};
  for (final v in vals) {
    m[v.t.categoryId] = (m[v.t.categoryId] ?? 0) + v.val.abs();
  }
  final list = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return list;
}

Set<String> splitParents(List<Transaction> txs) {
  final s = <String>{};
  for (final t in txs) {
    if (t.parentId != null) s.add(t.parentId!);
  }
  return s;
}

/// nocatQueue(sign) — uncategorized queue for the sort helper.
List<Transaction> nocatQueue(List<Transaction> txs, int sign, Set<String> skip) {
  final parents = splitParents(txs);
  return txs
      .where((t) =>
          !t.internal &&
          t.categoryId == null &&
          t.parentId == null &&
          !parents.contains(t.id) &&
          (sign < 0 ? t.amount < 0 : t.amount > 0) &&
          !(t.amount > 0 && t.reimburses != null) &&
          !skip.contains(t.id))
      .toList();
}

/// ============ recurring detection — port of detectRecurring() ============
/// Same description, stable amount (σ < 15% of mean, mean ≥ 20₴),
/// seen in ≥2 distinct months, not more rows than months×1.5.
class RecurringHit {
  final String nm;
  final double mean; // kopecks
  final int n; // distinct months
  final List<({String month, int a, DateTime time, String? cid, int day})> hist;
  final int lastDay;
  final String? lastCid;
  final int day; // rounded mean day-of-month
  final bool sameDay; // day σ ≤ 1.6
  const RecurringHit(this.nm, this.mean, this.n, this.hist, this.lastDay,
      this.lastCid, this.day, this.sameDay);
}

List<RecurringHit> detectRecurring(List<Transaction> allTx) {
  final byDesc =
      <String, List<({String month, int a, DateTime time, String? cid, int day})>>{};
  for (final v in computeVals(allTx)) {
    if (v.val >= 0 || v.t.description.isEmpty) continue;
    final t = v.t.time;
    final month =
        '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}';
    (byDesc[v.t.description] ??= []).add(
        (month: month, a: -v.val, time: t, cid: v.t.categoryId, day: t.day));
  }
  final out = <RecurringHit>[];
  byDesc.forEach((nm, arr) {
    arr.sort((a, b) => a.time.compareTo(b.time));
    final months = arr.map((x) => x.month).toSet();
    if (months.length < 2 || arr.length > months.length * 1.5) return;
    final mean = arr.fold<int>(0, (s, x) => s + x.a) / arr.length;
    final sd = _std(arr.map((x) => x.a.toDouble()).toList(), mean);
    if (!(sd < 0.15 * mean && mean >= 2000)) return;
    final last = arr.last;
    final days = arr.map((x) => x.day.toDouble()).toList();
    final dayMean = days.reduce((a, b) => a + b) / days.length;
    final daySd = _std(days, dayMean);
    out.add(RecurringHit(
        nm,
        mean,
        months.length,
        arr.length > 6 ? arr.sublist(arr.length - 6) : arr,
        last.time.day,
        last.cid,
        dayMean.round(),
        daySd <= 1.6));
  });
  out.sort((a, b) => b.mean.compareTo(a.mean));
  return out;
}

double _std(List<double> xs, double mean) {
  if (xs.isEmpty) return 0;
  final v = xs.fold<double>(0, (s, x) => s + (x - mean) * (x - mean)) / xs.length;
  return v <= 0 ? 0 : math.sqrt(v);
}
