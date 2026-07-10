import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart' hide Column;
import 'package:flutter/material.dart' as m show Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/haptics.dart';
import '../../core/money.dart';
import '../../core/months.dart';
import '../../core/plans.dart';
import '../../core/tokens.dart';
import '../../data/db/database.dart';
import '../../data/repos/analytics.dart';
import '../../l10n/app_localizations.dart';
import '../../state.dart';
import '../sheets/installment_sheet.dart';
import '../sheets/plan_sheet.dart';
import '../util.dart';
import '../widgets/common.dart';
import '../widgets/donut.dart';

/// Home «Огляд» — port of renderHome().
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _swapTick = 0;

  @override
  Widget build(BuildContext context) {
    final t = tk(context);
    final l = L.of(context);
    final ui = ref.watch(uiProvider);
    final settings = settingsOf(ref);
    final money = ref.watch(moneyProvider);
    final txs = ref.watch(periodTxsProvider).value ?? const <Transaction>[];
    final cats = ref.watch(categoriesProvider).value ?? const <Category>[];
    final planned = ref.watch(plannedProvider).value;
    final insts = ref.watch(installmentsProvider).value ?? const <Installment>[];
    final credit = ref.watch(creditProvider).value ?? const [];
    final period = ref.watch(periodProvider);
    final locale = localeOf(settings);
    final cfg = chartCfg(settings);

    final s = sums(txs);
    final expense = ui.mode == 'expense';
    final vals = expense ? s.expVals : s.incVals;
    final grand = expense ? s.expTotal : s.incTotal;
    final parts = byCategory(vals);
    final perCatExp = {for (final e in byCategory(s.expVals)) e.key: e.value};

    Category? catOf(String? id) =>
        id == null ? null : cats.where((c) => c.id == id).firstOrNull;
    Color colorOf(Category? c) =>
        c == null ? t.ink3 : catColor(c, cats.indexOf(c), cfg.palette);

    // ---- safe-to-spend ----
    final daysLeft = period.daysLeft;
    final leftover = s.incTotal - s.expTotal;
    final upcoming = ui.offset == 0
        ? upcomingPayments(
            planned: planned ?? const [],
            installments: insts,
            period: period,
            settings: settings)
        : const <Upcoming>[];
    final upSum = upcoming.fold<int>(0, (a, x) => a + x.amountKop);
    final safe = leftover - upSum;
    final over = safe <= 0;

    final noCat = nocatQueue(txs, expense ? -1 : 1, ui.skip).length;
    final overLimit = expense
        ? cats
            .where((c) =>
                c.limitKop != null &&
                (perCatExp[c.id] ?? 0) > c.limitKop!)
            .length
        : 0;
    final presets = (settings['quick_presets'] as List?) ?? const [];

    // donut parts, style C groups >6 into «Інше»
    var donutParts = [
      for (final e in parts)
        (e.key, e.value, e.key == null ? t.ink3 : colorOf(catOf(e.key)))
    ];
    final donutStyle =
        const ['A', 'B', 'C'].contains(settings['donut']) ? settings['donut'] as String : 'A';
    if (donutStyle == 'C' && donutParts.length > 6) {
      final rest =
          donutParts.skip(5).fold<int>(0, (a, p) => a + p.$2);
      donutParts = [
        ...donutParts.take(5),
        ('__other__', rest, const Color(0xFF6E6870))
      ];
    }

    var enterIdx = 0;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
      children: [
        // ---- safe-to-spend card (.sts2) ----
        if (ui.offset == 0)
          Enter(
            index: enterIdx++,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 14),
              decoration: BoxDecoration(
                gradient: t.panel,
                border: Border.all(color: t.line),
                borderRadius: BorderRadius.circular(20),
                boxShadow: t.shadowCard,
              ),
              child: Row(children: [
                Expanded(
                  child: m.Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(over ? l.xOverBudget : l.safeL1,
                            style: TextStyle(fontSize: 11.5, color: t.ink2, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        over
                            ? Text('−${money.fmt(-safe)}',
                                style: TextStyle(
                                    fontFamily: AppText.display,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    color: t.expense))
                            : ShaderMask(
                                shaderCallback: (r) =>
                                    t.gradient.createShader(r),
                                child: Text(
                                    '≈ ${money.fmt(safe ~/ daysLeft)}${l.perDay}',
                                    style: const TextStyle(
                                        fontFamily: AppText.display,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white)),
                              ),
                      ]),
                ),
                Text(
                  over
                      ? l.xLimitExhausted
                      : '${upSum != 0 ? '${l.inclPlanned} −${money.fmt(upSum)}\n' : ''}$daysLeft ${l.safeL2}',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 11.5, color: t.ink2, height: 1.55),
                ),
              ]),
            ),
          ),
        // ---- mode pills ----
        Enter(
          index: enterIdx++,
          child: Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 14),
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                    color: t.surface,
                    border: Border.all(color: t.line),
                    borderRadius: BorderRadius.circular(99)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  for (final (v, label) in [
                    ('expense', l.spent),
                    ('income', l.incomePill)
                  ])
                    Press(
                      onTap: () {
                        if (ui.mode != v) {
                          haptic();
                          setState(() {
                            ui.mode = v;
                            _swapTick++;
                          });
                          ui.bump();
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 8),
                        decoration: BoxDecoration(
                            gradient: ui.mode == v ? t.gradient : null,
                            borderRadius: BorderRadius.circular(99)),
                        child: Text(label,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color:
                                    ui.mode == v ? t.accentInk : t.ink2)),
                      ),
                    ),
                ]),
              ),
            ),
          ),
        ),
        // ---- donut or bars-only center ----
        if (cfg.type == 'donut')
          Center(
            child: DonutChart(
              parts: donutParts,
              grand: grand,
              style: donutStyle,
              swapTick: _swapTick,
              onSegment: (cid) {
                ui.filterCatBox = cid ?? '';
                ui.filterSign = expense ? -1 : 1;
                ui.setTab('txs');
              },
              center: _DonutCenter(
                  grand: grand,
                  leftover: leftover,
                  money: money,
                  income: !expense,
                  leftoverLabel: l.leftover,
                  swapTick: _swapTick),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: _DonutCenter(
                grand: grand,
                leftover: leftover,
                money: money,
                income: !expense,
                leftoverLabel: l.leftover,
                swapTick: _swapTick),
          ),
        // ---- legend ----
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: m.Column(children: [
            for (final (i, e) in parts.indexed)
              _LegendRow(
                index: i,
                cat: catOf(e.key),
                color: e.key == null ? t.ink3 : colorOf(catOf(e.key)),
                sum: e.value,
                pct: grand > 0 ? (100 * e.value / grand).round() : 0,
                limit: expense ? catOf(e.key)?.limitKop : null,
                money: money,
                bars: cfg.type == 'bars',
                noCatLabel: l.noCat,
                ofLabel: l.of,
                onTap: () {
                  ui.filterCatBox = e.key ?? '';
                  ui.filterSign = expense ? -1 : 1;
                  ui.setTab('txs');
                },
              ),
          ]),
        ),
        // ---- chips ----
        SizedBox(
          height: noCat > 0 || overLimit > 0 || presets.isNotEmpty ? 52 : 0,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(top: 12, bottom: 2),
            children: [
              if (noCat > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChipBtn('❔ ${l.sortChip}: $noCat', warn: true,
                      onTap: () {
                    ui.sortSign = expense ? -1 : 1;
                    ui.setTab('sort');
                  }),
                ),
              if (overLimit > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChipBtn('⚠ ${l.limitOver}: $overLimit',
                      warn: true,
                      warnColor: t.expense,
                      onTap: () => ui.setTab('cats')),
                ),
              for (final p in presets)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChipBtn(
                      '${p['emoji']} ${p['name']} · ${((p['kop'] as num) / 100).round()}${money.symbol}',
                      onTap: () async {
                    final c = cats
                        .where((x) =>
                            x.name == p['category'] && x.type == 'expense')
                        .firstOrNull;
                    await ref.read(txRepoProvider).insert(TransactionsCompanion(
                        id: Value(genUuid()),
                        time: Value(DateTime.now()),
                        description: Value(p['name'] as String? ?? ''),
                        amount: Value(-(p['kop'] as num).abs().toInt()),
                        categoryId: Value(c?.id),
                        subcategory: Value(p['sub'] as String?),
                        source: const Value('manual')));
                    if (context.mounted) {
                      ToastHost.show(context,
                          l.xPresetAdded('${p['emoji']} ${p['name']}'));
                    }
                  }),
                ),
            ],
          ),
        ),
        // ---- upcoming payments timeline ----
        if (ui.offset == 0 && planned != null)
          _UpcomingCard(
              upcoming: upcoming,
              upSum: upSum,
              cats: cats,
              palette: cfg.palette,
              money: money,
              locale: locale,
              onPlan: (id) {
                final p =
                    (planned).where((x) => x.id == id).firstOrNull;
                if (p != null) showPlanSheet(context, ref, p);
              },
              onInst: (id) {
                final i = insts.where((x) => x.id == id).firstOrNull;
                if (i != null) showInstallmentSheet(context, ref, i);
              },
              onAdd: () => showPlanSheet(context, ref, null)),
        // ---- credit limit hero ----
        if (credit.any((r) => r.limitKop > 0) &&
            settings['credit_hidden'] != true &&
            ui.offset == 0)
          _CreditCard(rows: credit, money: money),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
class _DonutCenter extends StatelessWidget {
  final int grand, leftover;
  final Money money;
  final bool income;
  final String leftoverLabel;
  final int swapTick;
  const _DonutCenter(
      {required this.grand,
      required this.leftover,
      required this.money,
      required this.income,
      required this.leftoverLabel,
      required this.swapTick});

  @override
  Widget build(BuildContext context) {
    final t = tk(context);
    final grandStr = money.fmt(grand);
    final leftStr = money.fmt(leftover);
    return m.Column(mainAxisSize: MainAxisSize.min, children: [
      // mode switch → bigPop instead of re-running count-up (PWA parity)
      CountUp(
        key: ValueKey('$swapTick-$grand'),
        target: grand,
        format: (v) => money.fmt(v),
        style: TextStyle(
            fontFamily: AppText.display,
            fontWeight: FontWeight.w700,
            fontSize: bigFontSize(grandStr),
            height: 1.08,
            color: income ? t.income : t.ink),
      ),
      const SizedBox(height: 5),
      Text(leftoverLabel,
          style: TextStyle(color: t.ink2, fontSize: 12, height: 1.5)),
      CountUp(
        key: ValueKey('$swapTick-l-$leftover'),
        target: leftover,
        format: (v) => money.fmt(v),
        style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: subFontSize(leftStr),
            color: leftover >= 0 ? t.income : t.expense),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------
class _LegendRow extends StatelessWidget {
  final int index;
  final Category? cat;
  final Color color;
  final int sum, pct;
  final int? limit;
  final Money money;
  final bool bars;
  final String noCatLabel, ofLabel;
  final VoidCallback onTap;
  const _LegendRow(
      {required this.index,
      required this.cat,
      required this.color,
      required this.sum,
      required this.pct,
      required this.limit,
      required this.money,
      required this.bars,
      required this.noCatLabel,
      required this.ofLabel,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = tk(context);
    final lpct = limit != null && limit! > 0 ? (100 * sum / limit!).round() : 0;
    final lcol = lpct > 100
        ? t.expense
        : lpct >= 80
            ? t.accent
            : color;
    return Enter(
      index: index,
      child: Press(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Stack(children: [
            if (bars)
              Positioned.fill(
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: (pct / 100).clamp(0.0, 1.0),
                  child: Container(
                      decoration: BoxDecoration(
                          color: color.withValues(alpha: .18),
                          borderRadius: BorderRadius.circular(13))),
                ),
              ),
            m.Column(children: [
              Row(children: [
                Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                        color: color, borderRadius: BorderRadius.circular(4))),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                      '${cat?.emoji ?? '❔'} ${cat?.name ?? noCatLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: t.ink)),
                ),
                SizedBox(
                  width: 38,
                  child: Text('$pct%',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          color: t.ink3,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 8),
                Text.rich(TextSpan(children: [
                  TextSpan(
                      text: money.fmt(sum),
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: t.ink)),
                  if (limit != null && limit! > 0)
                    TextSpan(
                        text: ' $ofLabel ${money.fmtInt(limit!)}',
                        style: TextStyle(fontSize: 11, color: t.ink3)),
                ])),
              ]),
              if (limit != null && limit! > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child:
                      Bar(pct: lpct.toDouble(), color: lcol, height: 3),
                ),
            ]),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
/// Upcoming payments — vertical timeline (.uptl) with rail, dots, stagger.
class _UpcomingCard extends ConsumerWidget {
  final List<Upcoming> upcoming;
  final int upSum;
  final List<Category> cats;
  final int palette;
  final Money money;
  final String locale;
  final void Function(String id) onPlan;
  final void Function(String id) onInst;
  final VoidCallback onAdd;
  const _UpcomingCard(
      {required this.upcoming,
      required this.upSum,
      required this.cats,
      required this.palette,
      required this.money,
      required this.locale,
      required this.onPlan,
      required this.onInst,
      required this.onAdd});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = tk(context);
    final l = L.of(context);
    final seen = <String>{};
    final rows = upcoming.where((x) => seen.add(x.id)).take(5).toList();
    final today = DateTime.now();
    final today0 = DateTime(today.year, today.month, today.day);

    return m.Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SecH(l.upcoming,
          trailing: Press(
            onTap: onAdd,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                  border: Border.all(color: t.line),
                  borderRadius: BorderRadius.circular(8)),
              child: Text('＋',
                  style: TextStyle(fontSize: 14, color: t.accent)),
            ),
          )),
      AppCard(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
        child: rows.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Center(
                    child: Text(l.upcomingNone,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: t.ink3, fontSize: 14))))
            : Stack(children: [
                // .uptl-line rail
                Positioned(
                  left: 61,
                  top: 22,
                  bottom: upSum != 0 ? 22 + 46 : 22,
                  child: Container(
                    width: 2,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color.lerp(t.line, t.accent, .52)!,
                            Color.lerp(t.line, t.accent, .14)!,
                          ]),
                    ),
                  ),
                ),
                m.Column(children: [
                  for (final (i, x) in rows.indexed)
                    _UpRow(
                        index: i,
                        x: x,
                        next: i == 0,
                        cat: cats
                            .where((c) => c.id == x.categoryId)
                            .firstOrNull,
                        cats: cats,
                        palette: palette,
                        money: money,
                        locale: locale,
                        today0: today0,
                        l: l,
                        onTap: () =>
                            x.isInstallment ? onInst(x.id) : onPlan(x.id)),
                  if (upSum != 0)
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 2),
                      decoration: BoxDecoration(
                          border:
                              Border(top: BorderSide(color: t.line))),
                      child: Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            Text(l.totalUpcoming.toUpperCase(),
                                style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: .5,
                                    color: t.ink2)),
                            Text('−${money.fmt(upSum)}',
                                style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                    color: t.ink)),
                          ]),
                    ),
                ]),
              ]),
      ),
    ]);
  }
}

class _UpRow extends StatelessWidget {
  final int index;
  final Upcoming x;
  final bool next;
  final Category? cat;
  final List<Category> cats;
  final int palette;
  final Money money;
  final String locale;
  final DateTime today0;
  final L l;
  final VoidCallback onTap;
  const _UpRow(
      {required this.index,
      required this.x,
      required this.next,
      required this.cat,
      required this.cats,
      required this.palette,
      required this.money,
      required this.locale,
      required this.today0,
      required this.l,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = tk(context);
    final col = cat == null ? t.ink3 : catColor(cat, cats.indexOf(cat!), palette);
    final dd = x.date.difference(today0).inDays;
    final when = dd == 0
        ? l.today
        : dd == 1
            ? l.tomorrow
            : '${l.inDays} $dd ${l.daysS}';
    return Enter(
      index: index,
      stepMs: 50,
      dy: 9,
      durMs: 420,
      child: Press(
        onTap: onTap,
        scale: .99,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [
            SizedBox(
              width: 44,
              child: Text(fmtDayMonth(x.date, locale),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: t.ink3)),
            ),
            SizedBox(
              width: 18 + 9 * 2,
              child: Center(
                child: Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: col,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                          color: col.withValues(alpha: .22),
                          spreadRadius: 4)
                    ],
                    border: next
                        ? Border.all(
                            color: col.withValues(alpha: .4), width: 2,
                            strokeAlign: BorderSide.strokeAlignOutside)
                        : null,
                  ),
                ),
              ),
            ),
            EmTile(cat?.emoji ?? (x.isInstallment ? '💳' : '📌'),
                color: col, size: 40, fontSize: 18),
            const SizedBox(width: 9),
            Expanded(
              child: m.Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(x.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: t.ink)),
                    const SizedBox(height: 2),
                    Text(when,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: dd <= 1 ? t.accent : t.ink3)),
                  ]),
            ),
            Text('−${money.fmt(x.amountKop)}',
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: t.ink)),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
/// Credit-limit hero card (.cl-hero) — glow, available, % badge, bars,
/// per-person rows with В/А badges.
class _CreditCard extends StatelessWidget {
  final List<CreditRow> rows;
  final Money money;
  const _CreditCard({required this.rows, required this.money});

  @override
  Widget build(BuildContext context) {
    final t = tk(context);
    final l = L.of(context);
    final active = rows.where((r) => r.limitKop > 0).toList();
    final usedTotal = active.fold<int>(0, (a, r) => a + r.usedKop);
    final limTotal = active.fold<int>(0, (a, r) => a + r.limitKop);
    final availTotal = (limTotal - usedTotal).clamp(0, limTotal);
    final pctTotal =
        limTotal > 0 ? (100 * usedTotal / limTotal).clamp(0, 100).round() : 0;

    Color barColor(int used, int lim) {
      final pct = lim > 0 ? (100 * used / lim).round() : 0;
      return pct >= 90
          ? t.expense
          : pct >= 60
              ? t.accent
              : t.income;
    }

    String nameOf(String o) =>
        o == 'vadim' ? 'Вадім' : o == 'alisa' ? 'Аліса' : o;

    final people = active
        .where((r) => r.owner == 'vadim' || r.owner == 'alisa')
        .toList()
      ..sort((a, b) => a.owner.compareTo(b.owner));
    final others =
        active.where((r) => r.owner != 'vadim' && r.owner != 'alisa').toList();

    return m.Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SecH(l.creditHead),
      AppCard(
        child: Stack(children: [
          // .cl-glow
          Positioned(
            top: -42,
            right: -32,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  t.accent.withValues(alpha: .22),
                  t.accent.withValues(alpha: 0)
                ], stops: const [0, .72]),
              ),
            ),
          ),
          m.Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  m.Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.creditAvail,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: t.ink2)),
                        const SizedBox(height: 3),
                        Text(money.fmt(availTotal),
                            style: TextStyle(
                                fontFamily: AppText.display,
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                height: 1,
                                color: t.ink)),
                      ]),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                    decoration: BoxDecoration(
                        color: t.accent.withValues(alpha: .13),
                        borderRadius: BorderRadius.circular(13)),
                    child: m.Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('$pctTotal%',
                              style: TextStyle(
                                  fontFamily: AppText.display,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: t.accent)),
                          Text(l.creditUsed.toUpperCase(),
                              style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: .4,
                                  color: t.ink3)),
                        ]),
                  ),
                ]),
            const SizedBox(height: 10),
            Bar(
                pct: pctTotal.toDouble(),
                color: t.expense,
                gradient: pctTotal >= 90 ? null : t.gradient,
                height: 9),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('${l.creditUsed} ${money.fmt(usedTotal)}',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: t.ink3)),
              Text('${l.limit} ${money.fmt(limTotal)}',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: t.ink3)),
            ]),
            for (final r in [...people, ...others]) ...[
              const SizedBox(height: 12),
              Row(children: [
                if (r.owner == 'vadim' || r.owner == 'alisa')
                  OwnerBadge(r.owner, r.owner == 'vadim' ? 'В' : 'А'),
                const SizedBox(width: 7),
                Expanded(
                    child: Text(nameOf(r.owner),
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                            color: t.ink))),
                Text.rich(TextSpan(children: [
                  TextSpan(
                      text: money.fmt(r.usedKop),
                      style: TextStyle(fontSize: 13, color: t.ink)),
                  TextSpan(
                      text: ' / ${money.fmt(r.limitKop)}',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: t.ink3)),
                ])),
              ]),
              const SizedBox(height: 5),
              Bar(
                  pct: r.limitKop > 0
                      ? (100 * r.usedKop / r.limitKop).clamp(0, 100).toDouble()
                      : 0,
                  color: barColor(r.usedKop, r.limitKop)),
            ],
          ]),
        ]),
      ),
    ]);
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
