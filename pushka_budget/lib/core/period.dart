/// Salary-period logic — 1:1 port of periodStart()/currentPeriod()/periodLabel()
/// from app.js. Default anchor: the 22nd of each month.
class Period {
  final DateTime start; // inclusive
  final DateTime end; // exclusive
  const Period(this.start, this.end);

  bool contains(DateTime t) => !t.isBefore(start) && t.isBefore(end);
  int get daysLeft {
    final now = DateTime.now();
    final ms = end.difference(now).inMilliseconds;
    return ms <= 0 ? 1 : (ms / 86400000).ceil().clamp(1, 1 << 31);
  }
}

/// periodStart(d, day): the period containing [d] starts on [day] of d's month
/// if d.day >= day, otherwise on [day] of the previous month.
DateTime periodStart(DateTime d, int day) => d.day >= day
    ? DateTime(d.year, d.month, day)
    : DateTime(d.year, d.month - 1, day);

/// currentPeriod(offset): salary mode — [day .. day of next month);
/// month mode — calendar month. Matches app.js currentPeriod() incl. offset nav.
Period currentPeriod({
  required String mode, // 'salary' | 'month'
  required int startDay, // 1..28, default 22
  int offset = 0,
  DateTime? now,
}) {
  final n = now ?? DateTime.now();
  if (mode == 'month') {
    final s = DateTime(n.year, n.month + offset, 1);
    return Period(s, DateTime(s.year, s.month + 1, 1));
  }
  var s = periodStart(n, startDay);
  s = DateTime(s.year, s.month + offset, startDay);
  return Period(s, DateTime(s.year, s.month + 1, startDay));
}

/// addMonths with day clamped to the target month's length —
/// port of addMonths() used by installments (instNextDue).
DateTime addMonthsClamped(DateTime d, int n) {
  final firstOfTarget = DateTime(d.year, d.month + n, 1);
  final lastDay = DateTime(firstOfTarget.year, firstOfTarget.month + 1, 0).day;
  return DateTime(firstOfTarget.year, firstOfTarget.month,
      d.day > lastDay ? lastDay : d.day);
}
