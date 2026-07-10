import 'package:flutter/material.dart' hide Column;
import 'package:flutter/material.dart' as m show Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/haptics.dart';
import '../../core/months.dart';
import '../../data/db/database.dart';
import '../../data/repos/analytics.dart';
import '../../l10n/app_localizations.dart';
import '../../state.dart';
import '../sheets/filter_sheet.dart';
import '../sheets/tx_sheet.dart';
import '../util.dart';
import '../widgets/common.dart';
import '../widgets/tx_row.dart';

/// Advanced filter state — st.adv.
class AdvFilter {
  List<String> cats = [];
  String type = 'all';
  String min = '', max = '';
  String merchant = '';
  String method = 'all';
  int get badgeCount =>
      cats.length +
      ((min.isNotEmpty || max.isNotEmpty) ? 1 : 0) +
      (merchant.isNotEmpty ? 1 : 0) +
      (method != 'all' ? 1 : 0);
}

final advFilterProvider = Provider<AdvFilter>((ref) => AdvFilter());

/// Feed «Стрічка» — port of renderTxs()/paintFeed()/feedSource().
class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});
  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  late final TextEditingController _q;

  @override
  void initState() {
    super.initState();
    _q = TextEditingController(text: ref.read(uiProvider).q);
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  List<Transaction> _feedSource(
      List<Transaction> periodTxs,
      List<Transaction>? allTxs,
      List<Category> cats,
      UiState ui,
      AdvFilter a) {
    var list = ui.feedScope == 'all' && allTxs != null
        ? allTxs.reversed.toList()
        : periodTxs;
    if (!identical(ui.filterCatBox, UiState.unset)) {
      final fc = ui.filterCatBox as String; // '' means «без категорії»
      list = list
          .where((t) => fc.isEmpty
              ? t.categoryId == null &&
                  (ui.filterSign < 0 ? t.amount < 0 : t.amount > 0)
              : t.categoryId == fc)
          .toList();
    }
    final q = ui.q.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((t) {
        final c = cats.where((x) => x.id == t.categoryId).firstOrNull;
        final hay = [
          t.description,
          t.subcategory,
          t.note,
          c?.name,
          '${(t.amount.abs() / 100).round()}'
        ].whereType<String>().join(' ').toLowerCase();
        return hay.contains(q);
      }).toList();
    }
    if (a.type == 'expense') list = list.where((t) => t.amount < 0).toList();
    if (a.type == 'income') list = list.where((t) => t.amount > 0).toList();
    if (a.cats.isNotEmpty) {
      list = list.where((t) => a.cats.contains(t.categoryId)).toList();
    }
    final mn = a.min.isNotEmpty ? (double.tryParse(a.min) ?? 0) * 100 : null;
    final mx = a.max.isNotEmpty ? (double.tryParse(a.max) ?? 0) * 100 : null;
    if (mn != null) list = list.where((t) => t.amount.abs() >= mn).toList();
    if (mx != null) list = list.where((t) => t.amount.abs() <= mx).toList();
    if (a.merchant.trim().isNotEmpty) {
      final mrc = a.merchant.trim().toLowerCase();
      list = list
          .where((t) => t.description.toLowerCase().contains(mrc))
          .toList();
    }
    if (a.method == 'card') {
      list = list.where((t) => t.accountId != null).toList();
    } else if (a.method == 'manual') {
      list = list.where((t) => t.accountId == null).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final t = tk(context);
    final l = L.of(context);
    final ui = ref.watch(uiProvider);
    final settings = settingsOf(ref);
    final money = ref.watch(moneyProvider);
    final locale = localeOf(settings);
    final cfg = chartCfg(settings);
    final a = ref.watch(advFilterProvider);

    final periodTxs =
        ref.watch(periodTxsProvider).value ?? const <Transaction>[];
    final allTxs =
        ui.feedScope == 'all' ? ref.watch(allTxsProvider).value : null;
    final cats = ref.watch(categoriesProvider).value ?? const <Category>[];
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];

    Category? catOf(String? id) =>
        id == null ? null : cats.where((c) => c.id == id).firstOrNull;
    Account? accOf(String? id) =>
        id == null ? null : accounts.where((x) => x.id == id).firstOrNull;

    final full = _feedSource(periodTxs, allTxs, cats, ui, a);
    final capped =
        ui.feedScope == 'all' ? full.take(ui.feedLimit).toList() : full;

    // totals for the current filter, ignoring the type segment (PWA parity)
    var spent = 0, received = 0;
    {
      final saved = a.type;
      a.type = 'all';
      for (final v in computeVals(_feedSource(periodTxs, allTxs, cats, ui, a))) {
        if (v.val < 0) {
          spent -= v.val;
        } else {
          received += v.val;
        }
      }
      a.type = saved;
    }

    // group by day
    final dayVals = {for (final v in computeVals(capped)) v.t.id: v.val};
    final days = <String, List<Transaction>>{};
    for (final tx in capped) {
      final k = tx.time.toIso8601String().substring(0, 10);
      (days[k] ??= []).add(tx);
    }

    final fc = identical(ui.filterCatBox, UiState.unset)
        ? null
        : catOf((ui.filterCatBox as String).isEmpty
            ? null
            : ui.filterCatBox as String);
    final hasFilters = ui.q.isNotEmpty || a.badgeCount > 0 || a.type != 'all';

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
      children: [
        // ---- feed-bar: search + filter + scope ----
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: Row(children: [
            Expanded(
              child: AppInput(
                controller: _q,
                placeholder: l.searchPh,
                fontSize: 14,
                onChanged: (v) {
                  ui.q = v;
                  ui.feedLimit = 120;
                  ui.bump();
                },
              ),
            ),
            const SizedBox(width: 8),
            Press(
              onTap: () => showFilterSheet(context, ref),
              child: Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: a.badgeCount > 0 ? t.gradient : null,
                  color: a.badgeCount > 0 ? null : t.surface2,
                  border: Border.all(
                      color:
                          a.badgeCount > 0 ? Colors.transparent : t.line),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Stack(clipBehavior: Clip.none, children: [
                  Icon(Icons.tune_rounded,
                      size: 17,
                      color: a.badgeCount > 0 ? t.accentInk : t.ink),
                  if (a.badgeCount > 0)
                    Positioned(
                      top: -9,
                      right: -10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                            gradient: t.gradient,
                            border: Border.all(color: t.bg, width: 2),
                            borderRadius: BorderRadius.circular(99)),
                        child: Text('${a.badgeCount}',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: t.accentInk)),
                      ),
                    ),
                ]),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 154,
              child: Seg(
                items: [('period', l.periodOne), ('all', l.all)],
                value: ui.feedScope,
                onChanged: (v) {
                  ui.feedScope = v;
                  ui.feedLimit = 120;
                  ui.bump();
                },
              ),
            ),
          ]),
        ),
        // ---- type segment ----
        Padding(
          padding: const EdgeInsets.only(bottom: 11),
          child: Seg(
            pill: true,
            items: [
              ('all', l.all),
              ('expense', l.expense),
              ('income', l.income)
            ],
            value: a.type,
            onChanged: (v) {
              a.type = v;
              ui.bump();
            },
          ),
        ),
        // ---- totals ----
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            Expanded(
                child: _TotCell(label: l.spent, value: money.fmt(spent))),
            const SizedBox(width: 11),
            Expanded(
                child: _TotCell(
                    label: l.incomePill,
                    value: money.fmt(received),
                    color: t.income)),
          ]),
        ),
        // ---- active category filter chip ----
        if (!identical(ui.filterCatBox, UiState.unset))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              ChipBtn(
                  '✕ ${fc != null ? '${fc.emoji} ${fc.name}' : l.noCat}',
                  warn: true, onTap: () {
                ui.filterCatBox = UiState.unset;
                ui.bump();
              }),
            ]),
          ),
        // ---- rows grouped by day ----
        if (capped.isEmpty)
          hasFilters
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 44),
                  child: m.Column(children: [
                    Icon(Icons.search_off_rounded, size: 38, color: t.ink3),
                    const SizedBox(height: 9),
                    Text(l.xNothingFound,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: t.ink)),
                    const SizedBox(height: 4),
                    Text(l.xTryChangeQuery,
                        style: TextStyle(fontSize: 12.5, color: t.ink2)),
                  ]),
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Text(l.emptyTxs,
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(color: t.ink3, fontSize: 14, height: 1.6)),
                )
        else ...[
          for (final e in days.entries) ...[
            _DayHeader(
                date: DateTime.parse(e.key),
                showYear: ui.feedScope == 'all',
                locale: locale,
                sum: e.value.fold<int>(0, (s, tx) {
                  final v = dayVals[tx.id] ?? 0;
                  return s + (v < 0 ? v : 0);
                }),
                money: money),
            for (final tx in e.value)
              _row(context, tx, catOf(tx.categoryId), accOf(tx.accountId),
                  cats, cfg.palette, money, l),
          ],
          if (ui.feedScope == 'all' && full.length > capped.length)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 40),
              child: Btn(
                  '${l.showMore} · ${full.length - capped.length}',
                  kind: 'ghost', onTap: () {
                ui.feedLimit += 120;
                ui.bump();
              }),
            ),
        ],
      ],
    );
  }

  Widget _row(BuildContext context, Transaction tx, Category? c, Account? o,
      List<Category> cats, int palette, dynamic money, L l) {
    final title = (tx.parentId != null ? '↳ ' : '') +
        (tx.description.isNotEmpty
            ? tx.description
            : c?.name ?? (tx.amount > 0 ? l.incomePill : l.expense));
    final flags = [
      if (tx.internal) '⇄ ${l.internalLbl}',
      if (tx.reimburses != null) '↩ ${l.reimbLbl}',
    ].join(' · ');
    final sub = [
      if (c != null)
        '${c.emoji} ${c.name}'
      else if (tx.amount < 0)
        '❔ ${l.noCat}',
      if (tx.subcategory?.isNotEmpty == true) tx.subcategory!,
      if (tx.note?.isNotEmpty == true) tx.note!,
      if (flags.isNotEmpty) flags,
    ].join(' · ');

    return TxRow(
      key: ValueKey(tx.id),
      tx: tx,
      cat: c,
      catColor: c == null ? null : catColor(c, cats.indexOf(c), palette),
      title: title,
      sub: sub,
      amountText:
          '${tx.amount > 0 ? '+' : '−'}${money.fmt(tx.amount.abs())}',
      income: tx.amount > 0,
      owner: o == null
          ? null
          : (o.owner, o.owner == 'vadim' ? 'В' : o.owner == 'alisa' ? 'А' : o.owner.substring(0, 1).toUpperCase()),
      onTap: () => showTxSheet(context, ref, tx),
      onEdit: () => showTxSheet(context, ref, tx),
      onDelete: () => quickDeleteTx(context, ref, tx.id),
    );
  }
}

/// quickDeleteTx() — delete with undo toast (snapshot incl. split children).
Future<void> quickDeleteTx(
    BuildContext context, WidgetRef ref, String id) async {
  final l = L.of(context);
  final repo = ref.read(txRepoProvider);
  final snapshot = await repo.deleteWithChildren(id);
  if (snapshot.isEmpty || !context.mounted) return;
  haptic(HapticKind.select);
  ToastHost.show(context, l.deleted,
      undoLabel: l.cancelUndo, undo: () => repo.restore(snapshot));
}

class _TotCell extends StatelessWidget {
  final String label, value;
  final Color? color;
  const _TotCell({required this.label, required this.value, this.color});
  @override
  Widget build(BuildContext context) {
    final t = tk(context);
    return AppCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      child:
          m.Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: TextStyle(
                fontSize: 11.5, fontWeight: FontWeight.w600, color: t.ink2)),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: color ?? t.ink)),
      ]),
    );
  }
}

class _DayHeader extends StatelessWidget {
  final DateTime date;
  final bool showYear;
  final String locale;
  final int sum; // negative day expense total
  final dynamic money;
  const _DayHeader(
      {required this.date,
      required this.showYear,
      required this.locale,
      required this.sum,
      required this.money});
  @override
  Widget build(BuildContext context) {
    final t = tk(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 14, 2, 7),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(
            '${fmtDayMonth(date, locale)}${showYear ? ' ${date.year}' : ''}'
                .toUpperCase(),
            style: TextStyle(
                color: t.ink3,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1)),
        if (sum != 0)
          Text('−${money.fmt(-sum)}',
              style: TextStyle(
                  color: t.ink3,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800)),
      ]),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
