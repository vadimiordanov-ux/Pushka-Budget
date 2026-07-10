import 'package:flutter/material.dart' hide Column;
import 'package:flutter/material.dart' as m show Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/haptics.dart';
import '../../core/money.dart';
import '../../core/months.dart';
import '../../core/period.dart';
import '../../core/plans.dart';
import '../../data/db/database.dart';
import '../../data/repos/analytics.dart';
import '../../data/repos/repos.dart';
import '../../l10n/app_localizations.dart';
import '../../state.dart';
import '../sheets/installment_sheet.dart';
import '../sheets/plan_sheet.dart';
import '../sheets/sub_sheet.dart';
import '../sheets/widgets_sheet.dart';
import '../util.dart';
import '../widgets/common.dart';

const kStatWidgetsDefault = [
  'summary', 'cashflow', 'week', 'compare', 'categories',
  'cashback', 'merchants', 'subs', 'install', 'planned', 'periods',
];

/// 'periods' is the resurrected pre-v3.4 bar chart — hidden by default so it
/// changes nothing unless enabled in the customize sheet.
Set<String> statHidden(dynamic wcfg) {
  final saved =
      ((wcfg is Map ? (wcfg['hidden'] as List?) : null)?.cast<String>() ?? [])
          .toSet();
  final order =
      (wcfg is Map ? (wcfg['order'] as List?) : null)?.cast<String>() ?? [];
  if (!order.contains('periods')) saved.add('periods');
  return saved;
}

/// Stats «Аналітика» — port of renderStats(): 10 reorderable/hideable
/// widgets, skeleton while history loads, CSV export.
class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = tk(context);
    final l = L.of(context);
    final allAsync = ref.watch(allTxsProvider);
    final settings = settingsOf(ref);

    // skeleton while the full history loads (statsSkeleton port)
    if (allAsync.isLoading && allAsync.value == null) {
      return ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 120), children: [
        const Skel(width: 160, height: 12),
        const SizedBox(height: 12),
        AppCard(
          child: SizedBox(
            height: 200,
            child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final h in [46, 72, 58, 90, 64, 80, 52]) ...[
                    Skel(width: 26, height: 200 * h / 100),
                    const SizedBox(width: 12),
                  ]
                ]),
          ),
        ),
        const Skel(width: 120, height: 12),
        const SizedBox(height: 12),
        AppCard(
          child: m.Column(children: [
            for (var i = 0; i < 4; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(children: [
                  const Skel(width: 38, height: 38, radius: 11),
                  const SizedBox(width: 12),
                  const Expanded(child: Skel(width: double.infinity, height: 13)),
                  const SizedBox(width: 12),
                  const Skel(width: 62, height: 13),
                ]),
              ),
          ]),
        ),
      ]);
    }

    final wcfg = settings['stats_widgets'];
    final orderRaw =
        (wcfg is Map ? (wcfg['order'] as List?) : null)?.cast<String>() ?? [];
    final hidden = statHidden(wcfg);
    final order = [
      ...orderRaw.where(kStatWidgetsDefault.contains),
      ...kStatWidgetsDefault.where((k) => !orderRaw.contains(k)),
    ];

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 14, 2, 4),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l.tabStats,
                    style: TextStyle(
                        fontFamily: 'Unbounded',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: t.ink)),
                Press(
                  onTap: () => showWidgetsSheet(context, ref),
                  child: Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: t.surface2,
                        border: Border.all(color: t.line),
                        borderRadius: BorderRadius.circular(12)),
                    child: Icon(Icons.tune_rounded, size: 16, color: t.ink),
                  ),
                ),
              ]),
        ),
        for (final (i, key) in order.where((k) => !hidden.contains(k)).indexed)
          Enter(
              index: i,
              stepMs: 40,
              durMs: 400,
              child: _StatWidget(key: ValueKey(key), widgetKey: key)),
        Btn(l.csvExport, kind: 'ghost', onTap: () async {
          final txs = ref.read(periodTxsProvider).value ?? const <Transaction>[];
          final cats = ref.read(categoriesProvider).value ?? const <Category>[];
          final accounts =
              ref.read(accountsProvider).value ?? const <Account>[];
          final period = ref.read(periodProvider);
          final mode = settings['period_mode'] as String? ?? 'salary';
          await ref.read(backupServiceProvider).exportCsv(
              txs,
              periodLabel(period, mode, localeOf(settings)),
              {for (final c in cats) c.id: c},
              {for (final a in accounts) a.id: a});
        }),
      ],
    );
  }
}

// ============================================================================
class _StatWidget extends ConsumerStatefulWidget {
  final String widgetKey;
  const _StatWidget({super.key, required this.widgetKey});
  @override
  ConsumerState<_StatWidget> createState() => _StatWidgetState();
}

class _StatWidgetState extends ConsumerState<_StatWidget> {
  final ScrollController _cfScroll = ScrollController();

  @override
  void dispose() {
    _cfScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final money = ref.watch(moneyProvider);
    final settings = settingsOf(ref);
    final locale = localeOf(settings);
    final all = ref.watch(allTxsProvider).value ?? const <Transaction>[];
    final periodTxs =
        ref.watch(periodTxsProvider).value ?? const <Transaction>[];
    final cats = ref.watch(categoriesProvider).value ?? const <Category>[];
    final ui = ref.watch(uiProvider);
    final cfg = chartCfg(settings);

    return switch (widget.widgetKey) {
      'summary' => _summary(l, money, all, periodTxs, settings),
      'cashflow' => _cashflow(l, money, all, ui, locale),
      'week' => _week(l, money, all, ui, locale),
      'compare' => _compare(l, money, all, cats, ui, cfg.palette, locale),
      'categories' => _categories(l, money, all, cats, ui, cfg.palette, locale),
      'cashback' => _cashback(l, money, all, periodTxs, cats, settings),
      'merchants' => _merchants(l, money, periodTxs, cats),
      'subs' => _subs(l, money, all, settings),
      'install' => _install(l, money),
      'planned' => _planned(l, money, cats, cfg.palette),
      'periods' => _periods(l, money, all, ui, settings, locale),
      _ => const SizedBox.shrink(),
    };
  }

  // ---- periods: resurrected pre-v3.4 grouped bar chart ---------------------
  // gran keys 'p' (salary periods) / 'm' (months) / 'q' (quarters) /
  // 'pq' (salary quarters); last 8 buckets, grid lines, value labels,
  // current bucket highlighted, dashed average line, tap → toast.
  Widget _periods(L l, Money money, List<Transaction> all, UiState ui,
      Map<String, dynamic> settings, String locale) {
    final t = tk(context);
    final g = ui.statsGran;
    final day = int.tryParse('${settings['period_start_day'] ?? 22}') ?? 22;

    String keyOf(DateTime d) {
      switch (g) {
        case 'p':
          final s = periodStart(d, day);
          return s.toIso8601String().substring(0, 10);
        case 'q':
          return '${d.year}-Q${(d.month - 1) ~/ 3 + 1}';
        case 'pq':
          final s = periodStart(d, day);
          return '${s.year}-Z${(s.month - 1) ~/ 3 + 1}';
        default:
          return d.toIso8601String().substring(0, 7);
      }
    }

    String labelOf(String k) => switch (g) {
          'p' => '${int.parse(k.substring(8, 10))}.${k.substring(5, 7)}',
          'q' => 'К${k.substring(6)} ${k.substring(2, 4)}',
          'pq' => 'ЗК${k.substring(6)} ${k.substring(2, 4)}',
          _ => monthsShort(locale)[int.parse(k.substring(5, 7)) - 1],
        };

    final buckets = <String, int>{};
    for (final v in computeVals(all)) {
      if (v.val >= 0) continue;
      final k = keyOf(v.t.time);
      buckets[k] = (buckets[k] ?? 0) - v.val;
    }
    final keys = buckets.keys.toList()..sort();
    final shown = keys.length > 8 ? keys.sublist(keys.length - 8) : keys;
    final maxV = shown.fold<int>(1, (a, k) => buckets[k]! > a ? buckets[k]! : a);
    final avg = shown.isEmpty
        ? 0.0
        : shown.fold<int>(0, (a, k) => a + buckets[k]!) / shown.length;
    final todayKey =
        periodStart(DateTime.now(), day).toIso8601String().substring(0, 10);

    return m.Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SecH(l.xWPeriods),
      AppCard(
        child: m.Column(children: [
          Seg(
            items: [
              ('p', l.xGranPeriods),
              ('m', l.xGranMonths),
              ('q', l.xGranQuarters),
              ('pq', l.xGranPayQ),
            ],
            value: g,
            onChanged: (v) {
              ui.statsGran = v;
              ui.bump();
            },
          ),
          const SizedBox(height: 16),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(l.noData, style: TextStyle(color: t.ink3)),
            )
          else
            SizedBox(
              height: 170,
              child: Stack(children: [
                // grid lines at 25/50/75/100%
                for (final f in [.25, .5, .75, 1.0])
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 34 + (170 - 34 - 20) * f,
                    child: Opacity(
                      opacity: .55,
                      child: CustomPaint(
                          size: const Size(double.infinity, 1),
                          painter: _DashPainter(t.line)),
                    ),
                  ),
                // avg dashed line + label
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 34 + (170 - 34 - 20) * (avg / maxV).clamp(0.0, 1.0),
                  child: Row(children: [
                    Expanded(
                        child: CustomPaint(
                            size: const Size(double.infinity, 1.5),
                            painter: _DashPainter(
                                Color.lerp(t.line, t.accent, .55)!))),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      color: t.surface,
                      child: Text('${l.avg} ${money.fmtInt(avg)}',
                          style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: t.accent)),
                    ),
                  ]),
                ),
                Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final (i, k) in shown.indexed) ...[
                        if (i > 0) const SizedBox(width: 6),
                        Expanded(
                          child: Press(
                            onTap: () => ToastHost.show(context,
                                '${labelOf(k)}: ${money.fmt(buckets[k]!)}'),
                            child: m.Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Text(money.fmtInt(buckets[k]!),
                                      style: TextStyle(
                                          fontSize: 8.5,
                                          fontWeight: FontWeight.w700,
                                          color: t.ink2)),
                                  const SizedBox(height: 5),
                                  GrowY(
                                    index: i,
                                    child: Container(
                                      height: ((170 - 34 - 20) *
                                              buckets[k]! /
                                              maxV)
                                          .clamp(3.0, 170.0 - 34 - 20),
                                      constraints: const BoxConstraints(
                                          maxWidth: 38),
                                      decoration: BoxDecoration(
                                        gradient: g == 'p' && k == todayKey
                                            ? t.gradient
                                            : null,
                                        color: g == 'p' && k == todayKey
                                            ? null
                                            : t.accent
                                                .withValues(alpha: .45),
                                        borderRadius:
                                            const BorderRadius.vertical(
                                                top: Radius.circular(5)),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(labelOf(k),
                                      style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight:
                                              g == 'p' && k == todayKey
                                                  ? FontWeight.w700
                                                  : FontWeight.w500,
                                          color: g == 'p' && k == todayKey
                                              ? t.accent
                                              : t.ink3)),
                                ]),
                          ),
                        ),
                      ],
                    ]),
              ]),
            ),
        ]),
      ),
    ]);
  }

  ({DateTime start, DateTime end, DateTime prevStart}) _periodWithPrev(
      Map<String, dynamic> settings) {
    final mode = settings['period_mode'] as String? ?? 'salary';
    final day = int.tryParse('${settings['period_start_day'] ?? 22}') ?? 22;
    final p = currentPeriod(mode: mode, startDay: day);
    final prevStart = mode == 'month'
        ? DateTime(p.start.year, p.start.month - 1, 1)
        : DateTime(p.start.year, p.start.month - 1, day);
    return (start: p.start, end: p.end, prevStart: prevStart);
  }

  bool _inR(DateTime t, DateTime s, DateTime e) =>
      !t.isBefore(s) && t.isBefore(e);

  // ---- summary: spent/income + trend vs previous period -------------------
  Widget _summary(L l, Money money, List<Transaction> all,
      List<Transaction> periodTxs, Map<String, dynamic> settings) {
    final t = tk(context);
    final s = sums(periodTxs);
    final pr = _periodWithPrev(settings);
    var prevExp = 0, prevInc = 0;
    for (final v in computeVals(all)) {
      if (_inR(v.t.time, pr.prevStart, pr.start)) {
        if (v.val < 0) {
          prevExp -= v.val;
        } else {
          prevInc += v.val;
        }
      }
    }
    int? dPct(int cur, int prev) =>
        prev != 0 ? ((cur - prev) / prev * 100).round() : null;
    final eD = dPct(s.expTotal, prevExp), iD = dPct(s.incTotal, prevInc);

    Widget cell(String label, int value, Color valueColor, int? d, bool goodDown) =>
        Expanded(
          child: AppCard(
            margin: EdgeInsets.zero,
            child:
                m.Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: t.ink2)),
              const SizedBox(height: 5),
              Text(money.fmt(value),
                  style: TextStyle(
                      fontFamily: 'Unbounded',
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: valueColor)),
              if (d != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('${d <= 0 ? '↓' : '↑'} ${d.abs()}%',
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: (d <= 0) == goodDown ? t.income : t.expense)),
                ),
            ]),
          ),
        );

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(children: [
        cell(l.spent, s.expTotal, t.ink, eD, true),
        const SizedBox(width: 11),
        cell(l.incomePill, s.incTotal, t.income, iD, false),
      ]),
    );
  }

  // ---- cashflow: paired monthly bars, horizontally scrollable --------------
  Widget _cashflow(L l, Money money, List<Transaction> all, UiState ui,
      String locale) {
    final t = tk(context);
    final valsAll = computeVals(all);
    final now = DateTime.now();
    DateTime? first;
    for (final v in valsAll) {
      if (first == null || v.t.time.isBefore(first)) first = v.t.time;
    }
    var back = first == null
        ? 5
        : (now.year - first.year) * 12 + (now.month - first.month);
    back = back.clamp(5, 35);
    final count = back + 1;
    final data = [
      for (var i = 0; i < count; i++)
        () {
          final d = DateTime(now.year, now.month - (count - 1) + i, 1);
          final e = DateTime(d.year, d.month + 1, 1);
          var inc = 0, exp = 0;
          for (final v in valsAll) {
            if (_inR(v.t.time, d, e)) {
              if (v.val > 0) {
                inc += v.val;
              } else {
                exp -= v.val;
              }
            }
          }
          return (
            lab: monthsShort(locale)[d.month - 1],
            full: '${monthsFull(locale)[d.month - 1]} ${d.year}',
            inc: inc,
            exp: exp
          );
        }()
    ];
    final maxV = data.fold<int>(
        1, (a, x) => [a, x.inc, x.exp].reduce((p, q) => p > q ? p : q));
    final sel = (ui.cfSel ?? (count - 1)).clamp(0, count - 1);
    final cur = data[sel];
    String kshort(int v) {
      final g = v / 100;
      return g >= 1000
          ? '${(g / 1000).round()}${l.xThousandSuffix}'
          : '${g.round()}';
    }

    return m.Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SecH(l.xWCashflow,
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            _legDot(t.income, l.xIncomeLeg),
            const SizedBox(width: 12),
            _legDot(t.accent, l.xExpenseLeg),
          ])),
      AppCard(
        child: m.Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(
              spacing: 11,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(cur.full,
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                        color: t.ink)),
                Text('↑ ${money.fmt(cur.inc)}',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: t.income)),
                Text('↓ ${money.fmt(cur.exp)}',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: t.accent)),
                Text('= ${money.fmt(cur.inc - cur.exp)}',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: cur.inc - cur.exp >= 0 ? t.income : t.expense)),
              ]),
          const SizedBox(height: 14),
          SizedBox(
            height: 150,
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(
                width: 28,
                child: m.Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(kshort(maxV), style: _axStyle(t)),
                      Text(kshort(maxV ~/ 2), style: _axStyle(t)),
                      Padding(
                          padding: const EdgeInsets.only(bottom: 17),
                          child: Text('0', style: _axStyle(t))),
                    ]),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ListView.builder(
                  controller: _cfScroll,
                  scrollDirection: Axis.horizontal,
                  reverse: false,
                  itemCount: count,
                  itemBuilder: (context, i) {
                    final x = data[i];
                    final isSel = i == sel;
                    return Press(
                      onTap: () {
                        ui.cfSel = i;
                        ui.bump();
                      },
                      child: Container(
                        width: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                            color: isSel
                                ? t.accent.withValues(alpha: .07)
                                : null,
                            borderRadius: BorderRadius.circular(8)),
                        child: m.Column(children: [
                          Expanded(
                            child: Opacity(
                              opacity: isSel ? 1 : .5,
                              child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    _cfBar(t.income.withValues(alpha: .9),
                                        x.inc / maxV, i),
                                    const SizedBox(width: 3),
                                    _cfBar(t.accent, x.exp / maxV, i),
                                  ]),
                            ),
                          ),
                          SizedBox(
                            height: 17,
                            child: Text(x.lab,
                                style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    color: isSel ? t.accent : t.ink3)),
                          ),
                        ]),
                      ),
                    );
                  },
                ),
              ),
            ]),
          ),
          if (count > 6)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Center(
                  child: Text(l.xCfHint,
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: t.ink3))),
            ),
        ]),
      ),
    ]);
  }

  TextStyle _axStyle(dynamic t) => TextStyle(
      fontSize: 8.5, fontWeight: FontWeight.w700, color: t.ink3);

  Widget _cfBar(Color c, double frac, int i) => GrowY(
        index: i % 8,
        child: Container(
          width: 9,
          height: (116 * frac).clamp(2.0, 116.0),
          decoration: BoxDecoration(
              color: c,
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(4), bottom: Radius.circular(2))),
        ),
      );

  Widget _legDot(Color c, String label) {
    final t = tk(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
              color: c, borderRadius: BorderRadius.circular(3))),
      const SizedBox(width: 5),
      Text(label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: t.ink2)),
    ]);
  }

  // ---- week: 7-day expenses with avg line & prev/next nav ------------------
  Widget _week(L l, Money money, List<Transaction> all, UiState ui,
      String locale) {
    final t = tk(context);
    final valsAll = computeVals(all);
    final today = DateTime.now();
    final today0 = DateTime(today.year, today.month, today.day);
    final curMon =
        today0.subtract(Duration(days: (today0.weekday - 1) % 7));
    final wkStart = curMon.add(Duration(days: ui.weekOff * 7));
    final data = [
      for (var i = 0; i < 7; i++)
        () {
          final d = wkStart.add(Duration(days: i));
          final e = d.add(const Duration(days: 1));
          var s = 0;
          for (final v in valsAll) {
            if (v.val < 0 && _inR(v.t.time, d, e)) s -= v.val;
          }
          return (d: d, v: s);
        }()
    ];
    final maxV = data.fold<int>(1, (a, x) => x.v > a ? x.v : a);
    final avg = data.fold<int>(0, (a, x) => a + x.v) / 7;
    final todayIdx = data.indexWhere((x) => x.d == today0);
    final sel = (ui.weekSel ?? (todayIdx >= 0 ? todayIdx : 6)).clamp(0, 6);
    final nxtStart = wkStart.add(const Duration(days: 7));
    final nxtEnd = nxtStart.add(const Duration(days: 7));
    final hasNext =
        valsAll.any((v) => v.val < 0 && _inR(v.t.time, nxtStart, nxtEnd));
    // toLocaleDateString(weekday:'short') parity
    String dayLabel(DateTime d) {
      if (locale == 'uk') {
        const wd = ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'нд'];
        return wd[(d.weekday - 1) % 7];
      }
      try {
        return DateFormat.E(locale).format(d).replaceAll('.', '');
      } catch (_) {
        return _wdShort(d, locale);
      }
    }

    return m.Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SecH(l.xWWeek,
          trailing: Text(
              money.fmt(data.fold<int>(0, (a, x) => a + x.v)),
              style: TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 13, color: t.ink))),
      AppCard(
        child: m.Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _acNav(Icons.chevron_left_rounded, true, () {
              haptic();
              ui.weekOff -= 1;
              ui.weekSel = null;
              ui.bump();
            }),
            Text(
                '${fmtDayMonth(wkStart, locale)} – ${fmtDayMonth(data[6].d, locale)}',
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: t.ink)),
            _acNav(Icons.chevron_right_rounded, hasNext, () {
              haptic();
              ui.weekOff += 1;
              ui.weekSel = null;
              ui.bump();
            }),
          ]),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Flexible(
              child: Text(
                  '${fmtDayMonth(data[sel].d, locale)} · ${money.fmt(data[sel].v)}',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                      color: t.ink)),
            ),
            Text('${l.xAvgShort} ${money.fmt(avg)}',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: t.ink2)),
          ]),
          const SizedBox(height: 10),
          SizedBox(
            height: 104,
            child: Stack(children: [
              // avg dashed line
              Positioned(
                left: 0,
                right: 0,
                bottom: (104 * avg / maxV).clamp(0, 98).toDouble(),
                child: CustomPaint(
                    size: const Size(double.infinity, 1.5),
                    painter: _DashPainter(
                        Color.lerp(t.line, t.accent, .55)!)),
              ),
              Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final (i, x) in data.indexed) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(
                        child: Press(
                          onTap: () {
                            ui.weekSel = i;
                            ui.bump();
                          },
                          child: GrowY(
                            index: i,
                            child: Container(
                              height:
                                  (104 * x.v / maxV).clamp(3.0, 104.0),
                              decoration: BoxDecoration(
                                gradient: i == sel ? t.gradient : null,
                                color: i == sel ? null : t.surface2,
                                border: i == sel
                                    ? null
                                    : Border.all(color: t.line),
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(7),
                                    bottom: Radius.circular(3)),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ]),
            ]),
          ),
          const SizedBox(height: 9),
          Row(children: [
            for (final (i, x) in data.indexed)
              Expanded(
                child: Text(dayLabel(x.d),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: i == sel ? t.accent : t.ink3)),
              ),
          ]),
        ]),
      ),
    ]);
  }

  String _wdShort(DateTime d, String locale) {
    const en = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return en[(d.weekday - 1) % 7];
  }

  Widget _acNav(IconData icon, bool enabled, VoidCallback onTap) {
    final t = tk(context);
    return Opacity(
      opacity: enabled ? 1 : .35,
      child: Press(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
              color: t.surface2,
              border: Border.all(color: t.line),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, size: 19, color: t.ink),
        ),
      ),
    );
  }

  // ---- compare: one category across 3/6/12 months ---------------------------
  Widget _compare(L l, Money money, List<Transaction> all, List<Category> cats,
      UiState ui, int palette, String locale) {
    final t = tk(context);
    final expCats =
        cats.where((c) => c.type == 'expense' && !c.archived).toList();
    if (expCats.isEmpty) return const SizedBox.shrink();
    final scId = expCats.any((c) => c.id == ui.scCat)
        ? ui.scCat!
        : expCats.first.id;
    final scC = expCats.firstWhere((c) => c.id == scId);
    final scN = ui.scMon;
    final now = DateTime.now();
    final valsAll = computeVals(all);
    final data = [
      for (var i = 0; i < scN; i++)
        () {
          final d = DateTime(now.year, now.month - scN + 1 + i, 1);
          final e = DateTime(d.year, d.month + 1, 1);
          var s = 0;
          for (final v in valsAll) {
            if (v.val < 0 &&
                v.t.categoryId == scId &&
                _inR(v.t.time, d, e)) {
              s -= v.val;
            }
          }
          return (m: monthsShort(locale)[d.month - 1], v: s);
        }()
    ];
    final maxV = data.fold<int>(1, (a, x) => x.v > a ? x.v : a);
    final avg = data.fold<int>(0, (a, x) => a + x.v) / scN;
    final prevAvg = scN > 1
        ? data.take(scN - 1).fold<int>(0, (a, x) => a + x.v) / (scN - 1)
        : 0.0;
    final last = data[scN - 1].v;
    final d = prevAvg != 0 ? ((last - prevAvg) / prevAvg * 100).round() : null;
    final scCol = catColor(scC, cats.indexOf(scC), palette);

    return m.Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SecH(l.compare),
      AppCard(
        child: m.Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            height: 40,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final c in expCats)
                Padding(
                  padding: const EdgeInsets.only(right: 7),
                  child: ChipBtn('${c.emoji} ${c.name}', on: c.id == scId,
                      onTap: () {
                    ui.scCat = c.id;
                    ui.bump();
                  }),
                ),
            ]),
          ),
          const SizedBox(height: 13),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Expanded(
              child: m.Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${scC.emoji} ${scC.name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: t.ink)),
                    const SizedBox(height: 2),
                    Text(l.xAvgPerMo(money.fmt(avg.round())),
                        style: TextStyle(fontSize: 11, color: t.ink3)),
                  ]),
            ),
            if (d != null)
              Text('${d <= 0 ? '↓' : '↑'} ${d.abs()}%',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: d <= 0 ? t.income : t.expense)),
          ]),
          const SizedBox(height: 12),
          Seg(
            items: [
              for (final n in [3, 6, 12]) ('$n', l.xNMonths('$n'))
            ],
            value: '$scN',
            onChanged: (v) {
              ui.scMon = int.parse(v);
              ui.bump();
            },
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 112,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (final (i, x) in data.indexed) ...[
                if (i > 0) const SizedBox(width: 4),
                Expanded(
                  child: m.Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        GrowY(
                          index: i,
                          child: Container(
                            height: (94 * x.v / maxV).clamp(3.0, 94.0),
                            constraints:
                                const BoxConstraints(maxWidth: 34),
                            decoration: BoxDecoration(
                              gradient:
                                  i == scN - 1 ? t.gradient : null,
                              color: i == scN - 1
                                  ? null
                                  : scCol.withValues(alpha: .4),
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(8),
                                  bottom: Radius.circular(3)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(x.m,
                            style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: t.ink3)),
                      ]),
                ),
              ],
            ]),
          ),
        ]),
      ),
    ]);
  }

  // ---- categories by month with swipe/arrows nav ---------------------------
  Widget _categories(L l, Money money, List<Transaction> all,
      List<Category> cats, UiState ui, int palette, String locale) {
    final t = tk(context);
    final now = DateTime.now();
    final acm = ui.acm;
    final acD = DateTime(now.year, now.month + acm, 1);
    final acE = DateTime(acD.year, acD.month + 1, 1);
    final map = <String?, int>{};
    var tot = 0;
    for (final v in computeVals(all)) {
      if (v.val < 0 && _inR(v.t.time, acD, acE)) {
        map[v.t.categoryId] = (map[v.t.categoryId] ?? 0) - v.val;
        tot -= v.val;
      }
    }
    final rows = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = rows.take(7).toList();
    final maxV = top.fold<int>(1, (a, e) => e.value > a ? e.value : a);

    return m.Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SecH(l.xWCategories),
      GestureDetector(
        // horizontal swipe month nav (ac-swipe port)
        onHorizontalDragEnd: (d) {
          final vx = d.primaryVelocity ?? 0;
          if (vx.abs() < 100) return;
          haptic();
          ui.acm = vx < 0 ? (acm + 1).clamp(-120, 0) : acm - 1;
          ui.bump();
        },
        child: AppCard(
          child: m.Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              _acNav(Icons.chevron_left_rounded, true, () {
                ui.acm = acm - 1;
                ui.bump();
              }),
              m.Column(children: [
                Text('${monthsFull(locale)[acD.month - 1]} ${acD.year}',
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: t.ink)),
                Text(tot != 0 ? l.xSpentAmount(money.fmt(tot)) : l.noData,
                    style: TextStyle(fontSize: 11, color: t.ink3)),
              ]),
              _acNav(Icons.chevron_right_rounded, acm < 0, () {
                ui.acm = (acm + 1).clamp(-120, 0);
                ui.bump();
              }),
            ]),
            const SizedBox(height: 14),
            if (top.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(l.noData, style: TextStyle(color: t.ink3)),
              )
            else
              for (final (i, e) in top.indexed)
                Builder(builder: (_) {
                  final c = e.key == null
                      ? null
                      : cats.where((x) => x.id == e.key).firstOrNull;
                  final col = c == null
                      ? t.ink3
                      : catColor(c, cats.indexOf(c), palette);
                  return Enter(
                    index: i,
                    stepMs: 40,
                    durMs: 400,
                    child: Padding(
                      padding: EdgeInsets.only(bottom: i == top.length - 1 ? 0 : 12),
                      child: m.Column(children: [
                        Row(children: [
                          EmTile(c?.emoji ?? '❔',
                              color: col, size: 30, fontSize: 15, radius: 10),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(c?.name ?? l.noCat,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                    color: t.ink)),
                          ),
                          Text(
                              '${(100 * e.value / (tot == 0 ? 1 : tot)).round()}%',
                              style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: t.ink3)),
                          const SizedBox(width: 7),
                          Text(money.fmt(e.value),
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: t.ink)),
                        ]),
                        const SizedBox(height: 6),
                        Bar(
                            pct: (100 * e.value / maxV).toDouble(),
                            color: col.withValues(alpha: .55),
                            height: 8),
                      ]),
                    ),
                  );
                }),
          ]),
        ),
      ),
    ]);
  }

  // ---- cashback -------------------------------------------------------------
  Widget _cashback(L l, Money money, List<Transaction> all,
      List<Transaction> periodTxs, List<Category> cats,
      Map<String, dynamic> settings) {
    final t = tk(context);
    final cashback = periodTxs.fold<int>(0, (s, x) => s + x.cashback);
    final pr = _periodWithPrev(settings);
    var prev = 0;
    final merch = <String, ({int sum, int n, String? cid})>{};
    for (final x in all) {
      if (x.cashback == 0) continue;
      if (_inR(x.time, pr.start, pr.end)) {
        final k = x.description.isNotEmpty
            ? x.description
            : cats.where((c) => c.id == x.categoryId).firstOrNull?.name ?? '—';
        final cur = merch[k] ?? (sum: 0, n: 0, cid: x.categoryId);
        merch[k] = (sum: cur.sum + x.cashback, n: cur.n + 1, cid: cur.cid);
      } else if (_inR(x.time, pr.prevStart, pr.start)) {
        prev += x.cashback;
      }
    }
    final topM = merch.entries.toList()
      ..sort((a, b) => b.value.sum.compareTo(a.value.sum));
    final top5 = topM.take(5).toList();
    final trend = prev != 0
        ? ((cashback - prev) / prev * 100).round()
        : (cashback != 0 ? 100 : 0);
    final up = trend >= 0;

    return m.Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SecH('🪙 ${l.cashbackPeriod}'),
      AppCard(
        child: m.Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                m.Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.cashbackEarned,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: t.ink2)),
                      const SizedBox(height: 4),
                      Text(money.fmt(cashback),
                          style: TextStyle(
                              fontFamily: 'Unbounded',
                              fontSize: 23,
                              fontWeight: FontWeight.w700,
                              color: t.accent)),
                    ]),
                if (cashback != 0 || prev != 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                        color: (up ? t.income : t.expense)
                            .withValues(alpha: .14),
                        borderRadius: BorderRadius.circular(12)),
                    child: m.Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('${up ? '▲' : '▼'} ${trend.abs()}%',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: up ? t.income : t.expense)),
                          Opacity(
                            opacity: .7,
                            child: Text(l.vsPrev,
                                style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w600,
                                    color: up ? t.income : t.expense)),
                          ),
                        ]),
                  ),
              ]),
          if (top5.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              child: Text(l.cashbackTop.toUpperCase(),
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .5,
                      color: t.ink3)),
            ),
            for (final e in top5)
              _fillRow(
                  leading: EmTile(
                      cats
                              .where((c) => c.id == e.value.cid)
                              .firstOrNull
                              ?.emoji ??
                          '🪙',
                      size: 30,
                      fontSize: 15,
                      radius: 9),
                  name: e.key,
                  sub: '${e.value.n} ${l.purchases}',
                  amount: money.fmt(e.value.sum),
                  frac: top5.first.value.sum > 0
                      ? e.value.sum / top5.first.value.sum
                      : 0),
          ] else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                  child:
                      Text(l.noData, style: TextStyle(color: t.ink3))),
            ),
        ]),
      ),
    ]);
  }

  // ---- merchants ------------------------------------------------------------
  Widget _merchants(
      L l, Money money, List<Transaction> periodTxs, List<Category> cats) {
    final t = tk(context);
    final s = sums(periodTxs);
    final merch = <String, ({int sum, int n})>{};
    for (final v in s.expVals) {
      final k = v.t.description.isNotEmpty
          ? v.t.description
          : cats.where((c) => c.id == v.t.categoryId).firstOrNull?.name ?? '—';
      final cur = merch[k] ?? (sum: 0, n: 0);
      merch[k] = (sum: cur.sum - v.val, n: cur.n + 1);
    }
    final top = merch.entries.toList()
      ..sort((a, b) => b.value.sum.compareTo(a.value.sum));
    final top8 = top.take(8).toList();

    return m.Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SecH(l.topMerch),
      AppCard(
        child: top8.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                    child: Text(l.noData, style: TextStyle(color: t.ink3))))
            : m.Column(children: [
                for (final (i, e) in top8.indexed)
                  _fillRow(
                      leading: SizedBox(
                        width: 20,
                        child: Text('${i + 1}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                                color: t.ink3)),
                      ),
                      name: e.key,
                      sub: '${e.value.n} ${l.purchases}',
                      amount: money.fmt(e.value.sum),
                      frac: top8.first.value.sum > 0
                          ? e.value.sum / top8.first.value.sum
                          : 0),
              ]),
      ),
    ]);
  }

  Widget _fillRow(
      {required Widget leading,
      required String name,
      required String sub,
      required String amount,
      required double frac}) {
    final t = tk(context);
    return Stack(children: [
      Positioned.fill(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: GrowX(
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: frac.clamp(0.0, 1.0),
              child: Container(
                  decoration: BoxDecoration(
                      color: t.accent.withValues(alpha: .13),
                      borderRadius: BorderRadius.circular(9))),
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(children: [
          leading,
          const SizedBox(width: 10),
          Expanded(
            child: m.Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: t.ink)),
                  Text(sub, style: TextStyle(fontSize: 12, color: t.ink3)),
                ]),
          ),
          Text(amount,
              style: TextStyle(fontWeight: FontWeight.w800, color: t.ink)),
        ]),
      ),
    ]);
  }

  // ---- subs: planned + auto-detected recurring ------------------------------
  Widget _subs(
      L l, Money money, List<Transaction> all, Map<String, dynamic> settings) {
    final t = tk(context);
    final planned =
        ref.watch(plannedProvider).value ?? const <PlannedPayment>[];
    final cats = ref.watch(categoriesProvider).value ?? const <Category>[];
    final subs = detectRecurring(all);
    final hidden =
        ((settings['subs_hidden'] as List?) ?? const []).cast<String>().toSet();
    final plannedNames = planned.map((p) => p.name.toLowerCase()).toSet();
    final shown = subs
        .take(12)
        .where((s) =>
            !hidden.contains(s.nm) &&
            !plannedNames.contains(s.nm.toLowerCase()))
        .toList();
    final activePlans = planned.where((p) => p.active).toList();
    var mo = 0.0, yr = 0.0;
    for (final p in activePlans) {
      final c = kCad[planMeta(settings, p.id).p]!;
      mo += p.amountKop * c.mo;
      yr += p.amountKop * c.yr;
    }
    for (final s in shown) {
      mo += s.mean;
      yr += s.mean * 12;
    }
    final count = activePlans.length + shown.length;

    String cadSfx(String k) => switch (k) {
          'week' => l.perWk,
          'quarter' => l.perQ,
          'half' => l.perHalf,
          'year' => l.perYr,
          _ => l.perMo,
        };

    return m.Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SecH(l.subsHead),
      AppCard(
        child: m.Column(children: [
          for (final p in planned)
            Builder(builder: (_) {
              final meta = planMeta(settings, p.id);
              final c = cats.where((x) => x.id == p.categoryId).firstOrNull;
              final when = meta.p == 'month'
                  ? l.xDayOrd('${p.day}')
                  : meta.p == 'week'
                      ? l.cadWeek.toLowerCase()
                      : _cadLbl(l, meta.p).toLowerCase();
              return Opacity(
                opacity: p.active ? 1 : .45,
                child: Press(
                  onTap: () => showPlanSheet(context, ref, p),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(children: [
                      Expanded(
                        child: m.Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${c?.emoji ?? '📌'} ${p.name}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                      color: t.ink)),
                              Text(
                                  '$when${p.notify ? ' · 🔔' : ''}${p.active ? '' : ' · ${l.xOff2}'}',
                                  style: TextStyle(
                                      fontSize: 12, color: t.ink3)),
                            ]),
                      ),
                      Text.rich(TextSpan(children: [
                        TextSpan(
                            text: money.fmt(p.amountKop),
                            style: TextStyle(
                                fontWeight: FontWeight.w800, color: t.ink)),
                        TextSpan(
                            text: cadSfx(meta.p),
                            style:
                                TextStyle(fontSize: 11, color: t.ink3)),
                      ])),
                    ]),
                  ),
                ),
              );
            }),
          for (final s in shown)
            Press(
              onTap: () => showSubSheet(context, ref, s),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(children: [
                  Expanded(
                    child: m.Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.nm,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: t.ink)),
                          Text('${s.n} ${l.moRow} · ${l.subsAuto}',
                              style:
                                  TextStyle(fontSize: 12, color: t.ink3)),
                        ]),
                  ),
                  Text.rich(TextSpan(children: [
                    TextSpan(
                        text: '≈${money.fmt(s.mean)}',
                        style: TextStyle(
                            fontWeight: FontWeight.w800, color: t.ink)),
                    TextSpan(
                        text: l.perMo,
                        style: TextStyle(fontSize: 11, color: t.ink3)),
                  ])),
                ]),
              ),
            ),
          if (planned.isEmpty && shown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(l.subsNone, style: TextStyle(color: t.ink3)),
            ),
          if (count > 0)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: t.line))),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(l.totalSubs.toUpperCase(),
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: .5,
                            color: t.ink2)),
                    Text(
                        '${money.fmt(mo)}${l.perMo} · ${money.fmt(yr)}${l.perYr}',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: t.ink)),
                  ]),
            ),
          Btn('＋ ${l.planNew}', kind: 'ghost',
              margin: const EdgeInsets.only(top: 8),
              onTap: () => showPlanSheet(context, ref, null)),
        ]),
      ),
    ]);
  }

  String _cadLbl(L l, String k) => switch (k) {
        'week' => l.cadWeek,
        'quarter' => l.cadQuarter,
        'half' => l.cadHalf,
        'year' => l.cadYear,
        _ => l.cadMonth,
      };

  // ---- installments widget ---------------------------------------------------
  Widget _install(L l, Money money) {
    final t = tk(context);
    final ui = ref.read(uiProvider);
    final insts = (ref.watch(installmentsProvider).value ?? const <Installment>[])
        .where((x) => !x.archived)
        .toList();
    final instMo =
        insts.fold<int>(0, (s, x) => s + (x.totalKop / x.monthsTotal).round());

    return m.Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SecH(l.xWInstall,
          trailing: instMo > 0
              ? Text('${money.fmt(instMo)} ${l.xPerMoShort}',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: t.accent))
              : null),
      if (insts.isEmpty)
        AppCard(
          child: m.Column(children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child:
                  Text(l.xNoActiveInst, style: TextStyle(color: t.ink3)),
            ),
            Btn('＋ ${l.instTitle}', kind: 'ghost',
                onTap: () => ui.setTab('inst')),
          ]),
        )
      else
        for (final (i, x) in insts.indexed)
          Enter(
            index: i,
            stepMs: 50,
            durMs: 400,
            child: Press(
              onTap: () => showInstallmentSheet(context, ref, x),
              child: AppCard(
                child: m.Column(children: [
                  Row(children: [
                    EmTile('💳', size: 42, fontSize: 19),
                    const SizedBox(width: 12),
                    Expanded(
                      child: m.Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(x.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14.5,
                                    color: t.ink)),
                            const SizedBox(height: 2),
                            Text(
                                '${l.xNofM('${x.monthsPaid}', '${x.monthsTotal}')}${x.bank.isNotEmpty ? ' · ${x.bank}' : ''}',
                                style: TextStyle(
                                    fontSize: 12, color: t.ink2)),
                          ]),
                    ),
                    m.Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                              money
                                  .fmt((x.totalKop / x.monthsTotal).round()),
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                  color: t.ink)),
                          Text(l.xPerMonth2,
                              style: TextStyle(
                                  fontSize: 11, color: t.ink3)),
                        ]),
                  ]),
                  const SizedBox(height: 12),
                  Bar(
                      pct: (100 * x.monthsPaid / x.monthsTotal)
                          .clamp(0, 100)
                          .toDouble(),
                      color: t.accent,
                      gradient: t.gradient,
                      height: 8),
                  const SizedBox(height: 8),
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                            l.xPctPaid(
                                '${(100 * x.monthsPaid / x.monthsTotal).round()}'),
                            style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: t.ink3)),
                        Text(
                            l.xLeftAmount(money.fmt((x.totalKop -
                                    x.monthsPaid *
                                        (x.totalKop / x.monthsTotal).round())
                                .clamp(0, x.totalKop))),
                            style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: t.ink3)),
                      ]),
                ]),
              ),
            ),
          ),
    ]);
  }

  // ---- planned payments widget -------------------------------------------
  Widget _planned(L l, Money money, List<Category> cats, int palette) {
    final t = tk(context);
    final planned =
        ref.watch(plannedProvider).value ?? const <PlannedPayment>[];
    final plans = planned.where((p) => p.active).toList();
    final tot = plans.fold<int>(0, (a, p) => a + p.amountKop);

    return m.Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SecH(l.xWPlanned,
          trailing: Press(
            onTap: () => showPlanSheet(context, ref, null),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
              decoration: BoxDecoration(
                  color: t.accent.withValues(alpha: .13),
                  borderRadius: BorderRadius.circular(99)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.add_rounded, size: 15, color: t.accent),
                Text(l.xAddBtn,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: t.accent)),
              ]),
            ),
          )),
      AppCard(
        child: m.Column(children: [
          if (plans.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(l.xNoPlanned, style: TextStyle(color: t.ink3)),
            )
          else ...[
            for (final (i, p) in plans.indexed)
              Builder(builder: (_) {
                final c =
                    cats.where((x) => x.id == p.categoryId).firstOrNull;
                final col = c == null
                    ? t.ink3
                    : catColor(c, cats.indexOf(c), palette);
                return Enter(
                  index: i,
                  stepMs: 40,
                  durMs: 420,
                  child: Press(
                    onTap: () => showPlanSheet(context, ref, p),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      decoration: BoxDecoration(
                          border: i == plans.length - 1
                              ? null
                              : Border(
                                  bottom: BorderSide(color: t.line))),
                      child: Row(children: [
                        EmTile(c?.emoji ?? '📌', color: col),
                        const SizedBox(width: 10),
                        Expanded(
                          child: m.Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: t.ink)),
                                Text(
                                    '${l.xOnDay('${p.day}')}${p.notify ? ' · 🔔' : ''}',
                                    style: TextStyle(
                                        fontSize: 11.5, color: t.ink3)),
                              ]),
                        ),
                        Text(money.fmt(p.amountKop),
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: t.ink)),
                      ]),
                    ),
                  ),
                );
              }),
            Container(
              padding: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: t.line))),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(l.xNPayments('${plans.length}'),
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: t.ink2)),
                    Text(money.fmt(tot),
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: t.ink)),
                  ]),
            ),
          ],
        ]),
      ),
    ]);
  }
}

class _DashPainter extends CustomPainter {
  final Color color;
  _DashPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    for (var x = 0.0; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, 0), Offset(x + 4, 0), paint);
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
