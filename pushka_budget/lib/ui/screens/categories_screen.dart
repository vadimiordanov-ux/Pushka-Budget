import 'package:flutter/material.dart' hide Column;
import 'package:flutter/material.dart' as m show Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/haptics.dart';
import '../../data/db/database.dart';
import '../../data/repos/analytics.dart';
import '../../l10n/app_localizations.dart';
import '../../state.dart';
import '../sheets/category_sheets.dart';
import '../util.dart';
import '../widgets/common.dart';

/// Categories tab — port of renderCats(): summary card, drag-reorder rows
/// with limit bars, archive section, add button.
class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = tk(context);
    final l = L.of(context);
    final ui = ref.watch(uiProvider);
    final settings = settingsOf(ref);
    final money = ref.watch(moneyProvider);
    final cfg = chartCfg(settings);
    final txs = ref.watch(periodTxsProvider).value ?? const <Transaction>[];
    final cats = ref.watch(categoriesProvider).value ?? const <Category>[];

    final s = sums(txs);
    final mode = ui.catMode;
    final perCat = <String?, int>{
      for (final e in byCategory(s.expVals)) e.key: e.value,
      for (final e in byCategory(s.incVals)) e.key: e.value,
    };
    final cntMap = <String, int>{};
    for (final v in [...s.expVals, ...s.incVals]) {
      final k = v.t.categoryId;
      if (k != null) cntMap[k] = (cntMap[k] ?? 0) + 1;
    }

    final list =
        cats.where((c) => c.type == mode && !c.archived).toList();
    final archived = cats.where((c) => c.archived).toList();
    final total = list.fold<int>(0, (a, c) => a + (perCat[c.id] ?? 0));
    final limSum = mode == 'expense'
        ? list.fold<int>(0, (a, c) => a + (c.limitKop ?? 0))
        : 0;
    final maxV = list.fold<int>(1, (a, c) {
      final v = perCat[c.id] ?? 0;
      return v > a ? v : a;
    });
    final pctLim = limSum > 0 ? (100 * total / limSum).round() : 0;
    final sumFill = limSum > 0
        ? (pctLim > 100
            ? t.expense
            : pctLim >= 80
                ? t.accent
                : t.income)
        : t.accent;
    final opsTotal = list.fold<int>(0, (a, c) => a + (cntMap[c.id] ?? 0));

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 11),
          child: Seg(
            pill: true,
            items: [('expense', l.expense), ('income', l.income)],
            value: mode,
            onChanged: (v) {
              ui.catMode = v;
              ui.bump();
            },
          ),
        ),
        // summary card
        Enter(
          index: 0,
          child: AppCard(
            margin: const EdgeInsets.only(bottom: 16),
            child:
                m.Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(mode == 'expense' ? l.xSpentPeriod : l.xReceivedPeriod,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: t.ink2)),
              const SizedBox(height: 5),
              Text(money.fmt(total),
                  style: TextStyle(
                      fontFamily: 'Unbounded',
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: mode == 'income' ? t.income : t.ink)),
              const SizedBox(height: 12),
              Bar(
                  pct: limSum > 0
                      ? pctLim.clamp(0, 100).toDouble()
                      : (total > 0 ? 100 : 0),
                  color: sumFill,
                  height: 8),
              const SizedBox(height: 9),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(l.xCatsOps('${list.length}', '$opsTotal'),
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: t.ink3)),
                if (limSum > 0)
                  Text(l.xPctLimits('$pctLim'),
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: t.accent)),
              ]),
            ]),
          ),
        ),
        // drag-reorder rows (Sortable → ReorderableListView)
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          // Sortable.js 'chosen' look: lifted card w/ shadow + slight scale
          proxyDecorator: (child, index, animation) => AnimatedBuilder(
            animation: animation,
            builder: (_, __) => Transform.scale(
              scale: 1 + .02 * animation.value,
              child: Material(
                color: Colors.transparent,
                elevation: 12 * animation.value,
                borderRadius: BorderRadius.circular(16),
                shadowColor: Colors.black.withValues(alpha: .4),
                child: child,
              ),
            ),
          ),
          itemCount: list.length,
          onReorder: (oldIndex, newIndex) async {
            haptic(HapticKind.select);
            final ids = list.map((c) => c.id).toList();
            if (newIndex > oldIndex) newIndex--;
            final id = ids.removeAt(oldIndex);
            ids.insert(newIndex, id);
            // keep the other type's ordering: merge back full order
            final others = cats
                .where((c) => c.type != mode || c.archived)
                .map((c) => c.id);
            await ref.read(catRepoProvider).reorder([...ids, ...others]);
            if (context.mounted) ToastHost.show(context, l.xOrderSaved);
          },
          itemBuilder: (context, i) {
            final c = list[i];
            final col = catColor(c, cats.indexOf(c), cfg.palette);
            final val = perCat[c.id] ?? 0;
            final cnt = cntMap[c.id] ?? 0;
            final lim = mode == 'expense' ? c.limitKop : null;
            final lpct = lim != null && lim > 0 ? (100 * val / lim).round() : 0;
            final fill = lim != null && lim > 0
                ? (lpct > 100
                    ? t.expense
                    : lpct >= 80
                        ? t.accent
                        : t.income)
                : col.withValues(alpha: .55);
            final w = lim != null && lim > 0
                ? lpct.clamp(0, 100)
                : (100 * val / maxV).round();
            final leftTxt = lim != null && lim > 0
                ? (lpct > 100
                    ? l.xOverLimitBy(money.fmt(val - lim))
                    : l.xLeftAmount(money.fmt(lim - val)))
                : (val > 0
                    ? l.xPctOfTotal(
                        '${(100 * val / (total == 0 ? 1 : total)).round()}')
                    : '');
            final leftCol = lim != null && lpct > 100
                ? t.expense
                : lim != null && lpct >= 80
                    ? t.accent
                    : t.ink3;
            return Enter(
              key: ValueKey(c.id),
              index: i + 1,
              stepMs: 35,
              durMs: 420,
              child: Press(
                scale: .985,
                onTap: () => showCatDetailSheet(context, ref, c),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 9),
                  padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
                  decoration: BoxDecoration(
                    gradient: t.panel,
                    border: Border.all(color: t.line),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: t.shadowCard,
                  ),
                  child: m.Column(children: [
                    Row(children: [
                      ReorderableDragStartListener(
                        index: i,
                        child: Icon(Icons.drag_indicator_rounded,
                            size: 20, color: t.ink3),
                      ),
                      const SizedBox(width: 7),
                      EmTile(c.emoji, color: col, size: 42, fontSize: 19),
                      const SizedBox(width: 11),
                      Expanded(
                        child: m.Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(c.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14.5,
                                      color: t.ink)),
                              const SizedBox(height: 2),
                              Text(cnt > 0 ? l.xNOps('$cnt') : l.xNoOps,
                                  style: TextStyle(
                                      color: t.ink2, fontSize: 12)),
                            ]),
                      ),
                      Text(money.fmt(val),
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14.5,
                              color: t.ink)),
                      Icon(Icons.chevron_right_rounded,
                          size: 18, color: t.ink3),
                    ]),
                    const SizedBox(height: 11),
                    Bar(
                        pct: (val > 0 || (lim ?? 0) > 0)
                            ? w.toDouble()
                            : 0,
                        color: fill),
                    if ((lim ?? 0) > 0 || val > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 7),
                        child: Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Text(leftTxt,
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: leftCol)),
                              Text(
                                  (lim ?? 0) > 0
                                      ? l.xLimitAmount(money.fmt(lim!))
                                      : '',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: t.ink3)),
                            ]),
                      ),
                  ]),
                ),
              ),
            );
          },
        ),
        // archive
        if (archived.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 20, 2, 8),
            child: Text(l.xArchive,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                    color: t.ink3)),
          ),
          for (final c in archived)
            Press(
              onTap: () => showCatEditSheet(context, ref, c),
              child: Opacity(
                opacity: .65,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 7),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                      color: t.surface2,
                      border: Border.all(color: t.line),
                      borderRadius: BorderRadius.circular(13)),
                  child: Row(children: [
                    Text(c.emoji, style: const TextStyle(fontSize: 17)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(c.name,
                            style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: t.ink))),
                    Icon(Icons.unarchive_rounded, size: 17, color: t.ink3),
                  ]),
                ),
              ),
            ),
        ],
        // add button (dashed)
        Press(
          onTap: () => showCatEditSheet(context, ref, null),
          child: Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              border: Border.all(color: t.line, width: 1.5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.add_rounded, size: 19, color: t.ink2),
              const SizedBox(width: 8),
              Text(l.xAddCategory,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: t.ink2)),
            ]),
          ),
        ),
      ],
    );
  }
}
