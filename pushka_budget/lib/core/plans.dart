import '../data/db/database.dart';
import '../data/repos/repos.dart';
import 'period.dart';

/// Cadence of planned payments — port of CAD/CAD_ORDER from app.js.
/// mo/yr are multipliers reducing any cadence to per-month / per-year sums.
class Cad {
  final double mo;
  final int yr;
  final String sfxKey; // i18n suffix key: per_wk / per_mo / …
  final String lblKey; // i18n label key: cad_week / …
  const Cad(this.mo, this.yr, this.sfxKey, this.lblKey);
}

const Map<String, Cad> kCad = {
  'week': Cad(52 / 12, 52, 'per_wk', 'cad_week'),
  'month': Cad(1, 12, 'per_mo', 'cad_month'),
  'quarter': Cad(1 / 3, 4, 'per_q', 'cad_quarter'),
  'half': Cad(1 / 6, 2, 'per_half', 'cad_half'),
  'year': Cad(1 / 12, 1, 'per_yr', 'cad_year'),
};
const List<String> kCadOrder = ['week', 'month', 'quarter', 'half', 'year'];

/// plan_meta lives in settings (outside the schema, PWA-parity):
/// { planId: {p: 'week|month|quarter|half|year', a: 'ISO anchor date'} }
({String p, String? a}) planMeta(Map<String, dynamic> settings, String id) {
  final all = settings['plan_meta'];
  final m = (all is Map) ? all[id] : null;
  final p = (m is Map) ? m['p'] as String? : null;
  final a = (m is Map) ? m['a'] as String? : null;
  return (p: kCad.containsKey(p) ? p! : 'month', a: a);
}

/// planOccurrence(): monthly plan trigger date inside a period; a salary
/// period can span two months (22.06–21.07) — both are checked.
DateTime? planOccurrence(PlannedPayment plan, Period period) {
  for (var m = 0; m < 2; m++) {
    final y = period.start.year, mo = period.start.month + m;
    final last = DateTime(y, mo + 1, 0).day;
    final d = DateTime(y, mo, plan.day > last ? last : plan.day);
    if (!d.isBefore(period.start) && d.isBefore(period.end)) return d;
  }
  return null;
}

/// planOccurrences(): all trigger dates in a period, honoring cadence.
/// Weekly/quarterly/half-yearly/yearly step from the anchor date.
List<DateTime> planOccurrences(
    PlannedPayment plan, Period period, Map<String, dynamic> settings) {
  final meta = planMeta(settings, plan.id);
  if (meta.p == 'month') {
    final d = planOccurrence(plan, period);
    return d == null ? [] : [d];
  }
  if (meta.a == null) return [];
  final anchor = DateTime.tryParse(meta.a!);
  if (anchor == null) return [];
  final out = <DateTime>[];
  var d = DateTime(anchor.year, anchor.month, anchor.day);
  if (meta.p == 'week') {
    while (!d.isBefore(period.start)) {
      d = d.subtract(const Duration(days: 7));
    }
    d = d.add(const Duration(days: 7));
    for (; d.isBefore(period.end); d = d.add(const Duration(days: 7))) {
      if (!d.isBefore(period.start)) out.add(d);
    }
  } else {
    final step = {'quarter': 3, 'half': 6, 'year': 12}[meta.p]!;
    while (!d.isBefore(period.start)) {
      d = DateTime(d.year, d.month - step, d.day);
    }
    d = DateTime(d.year, d.month + step, d.day);
    for (;
        d.isBefore(period.end);
        d = DateTime(d.year, d.month + step, d.day)) {
      if (!d.isBefore(period.start)) out.add(d);
    }
  }
  return out;
}

/// One upcoming row (plan or installment due) — upcomingPayments() port.
class Upcoming {
  final DateTime date;
  final String id;
  final String name;
  final int amountKop;
  final String? categoryId;
  final bool isInstallment;
  const Upcoming(this.date, this.id, this.name, this.amountKop, this.categoryId,
      {this.isInstallment = false});
}

List<Upcoming> upcomingPayments({
  required List<PlannedPayment> planned,
  required List<Installment> installments,
  required Period period,
  required Map<String, dynamic> settings,
  DateTime? now,
}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final out = <Upcoming>[];
  for (final p in planned) {
    if (!p.active) continue;
    for (final date in planOccurrences(p, period, settings)) {
      if (!date.isBefore(today)) {
        out.add(Upcoming(date, p.id, p.name, p.amountKop, p.categoryId));
      }
    }
  }
  for (final inst in installments) {
    if (inst.archived || inst.monthsTotal - inst.monthsPaid <= 0) continue;
    final date = instNextDue(inst);
    if (!date.isBefore(today) && !date.isAfter(period.end)) {
      out.add(Upcoming(date, inst.id, inst.name, instMonthly(inst),
          inst.categoryId,
          isInstallment: true));
    }
  }
  out.sort((a, b) => a.date.compareTo(b.date));
  return out;
}
