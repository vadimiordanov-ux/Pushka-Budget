import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart' hide Column;
import 'package:flutter/material.dart' as m show Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/months.dart';
import '../../core/tokens.dart';
import '../../data/db/database.dart';
import '../../data/repos/analytics.dart';
import '../../l10n/app_localizations.dart';
import '../../state.dart';
import '../util.dart';
import '../widgets/common.dart';

/// catSheet() — create/edit a category: name, emoji grid + custom input,
/// color picker, period limit (expense), archive/unarchive, cascade delete.
Future<void> showCatEditSheet(
    BuildContext context, WidgetRef ref, Category? c) async {
  final l = L.of(context);
  final repo = ref.read(catRepoProvider);
  final settings = settingsOf(ref);
  final cfg = chartCfg(settings);
  final cats = ref.read(categoriesProvider).value ?? const <Category>[];

  var emoji = c?.emoji ?? '📌';
  var type = c?.type ?? 'expense';
  var color = c != null
      ? catColor(c, cats.indexOf(c), cfg.palette)
      : kPalettes[cfg.palette][cats.length % 16];
  final nameCtl = TextEditingController(text: c?.name ?? '');
  final emCtl = TextEditingController(text: emoji);
  final limCtl = TextEditingController(
      text: c?.limitKop != null ? '${c!.limitKop! ~/ 100}' : '');

  await showAppSheet(
    context,
    StatefulBuilder(builder: (context, setState) {
      final t = tk(context);
      return m.Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetTitle(c != null ? l.xCategory : l.xNewCategory),
            Fld(l.xName, child: AppInput(controller: nameCtl)),
            Fld(l.xEmojiLabel,
                child: m.Column(children: [
                  SizedBox(
                    height: 200,
                    child: GridView.count(
                      crossAxisCount: 8,
                      mainAxisSpacing: 4,
                      crossAxisSpacing: 4,
                      children: [
                        for (final e in kEmojis)
                          Press(
                            onTap: () => setState(() {
                              emoji = e;
                              emCtl.text = e;
                            }),
                            child: Container(
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: e == emoji
                                    ? t.surface2
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                border: e == emoji
                                    ? Border.all(color: t.accent, width: 2)
                                    : null,
                              ),
                              child: Text(e,
                                  style: const TextStyle(fontSize: 20)),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  AppInput(
                      controller: emCtl,
                      textAlign: TextAlign.center,
                      fontSize: 20,
                      onChanged: (v) => emoji = v.trim()),
                ])),
            Fld(l.xColorLabel,
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final pc in kPalettes[cfg.palette])
                    Press(
                      onTap: () => setState(() => color = pc),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: pc,
                          borderRadius: BorderRadius.circular(10),
                          // ignore: deprecated_member_use
                          border: pc.value == color.value
                              ? Border.all(color: t.ink, width: 2.5)
                              : null,
                        ),
                      ),
                    ),
                ])),
            if (c == null || c.type == 'expense')
              Fld(l.xLimitLabel,
                  child: AppInput(
                      controller: limCtl,
                      placeholder: l.xEg10000,
                      keyboardType: TextInputType.number)),
            if (c == null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Seg(
                  items: [('expense', l.expense), ('income', l.income)],
                  value: type,
                  onChanged: (v) => setState(() => type = v),
                ),
              ),
            Btn(l.save, onTap: () async {
              final name = nameCtl.text.trim();
              if (name.isEmpty) {
                ToastHost.show(context, l.xNameEmpty);
                return;
              }
              final limG = double.tryParse(limCtl.text);
              final limitKop =
                  (limG != null && limG > 0) ? (limG * 100).round() : null;
              // ignore: deprecated_member_use
              final hex = '#${(color.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
              try {
                if (c != null) {
                  await repo.patch(
                      c.id,
                      CategoriesCompanion(
                          name: Value(name),
                          emoji: Value(
                              emCtl.text.trim().isEmpty ? '📌' : emCtl.text.trim()),
                          color: Value(hex),
                          limitKop: Value(limitKop)));
                } else {
                  await repo.upsert(CategoriesCompanion(
                      id: Value(genUuid()),
                      name: Value(name),
                      emoji: Value(
                          emCtl.text.trim().isEmpty ? '📌' : emCtl.text.trim()),
                      color: Value(hex),
                      type: Value(type),
                      sortOrder: Value(cats.length + 1),
                      limitKop: Value(limitKop)));
                }
              } catch (_) {
                ToastHost.show(context, l.xSaveFailDup);
                return;
              }
              if (!context.mounted) return;
              Navigator.pop(context);
              ToastHost.show(context, l.saved);
            }),
            if (c != null) ...[
              Btn(c.archived ? l.xFromArchive : l.xToArchive, kind: 'ghost',
                  onTap: () async {
                await repo.patch(c.id,
                    CategoriesCompanion(archived: Value(!c.archived)));
                if (context.mounted) Navigator.pop(context);
              }),
              Btn(l.xDeleteCategory, kind: 'danger', onTap: () async {
                final count = await repo.txCount(c.id);
                if (!context.mounted) return;
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: t.surface,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                    content: Text(l.xDeleteCatConfirm(c.name, '$count'),
                        style: TextStyle(color: t.ink, fontSize: 14.5)),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text(l.xCancel,
                              style: TextStyle(color: t.ink2))),
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text(l.deleteBtn,
                              style: TextStyle(
                                  color: t.expense,
                                  fontWeight: FontWeight.w700))),
                    ],
                  ),
                );
                if (ok != true || !context.mounted) return;
                await repo.deleteCascade(c.id);
                if (!context.mounted) return;
                Navigator.pop(context);
                ToastHost.show(context, l.xCatDeleted);
              }),
            ],
          ]);
    }),
  );
}

/// catDetailSheet() — big header, limit bar, 6-month sparkline, last 10 ops.
Future<void> showCatDetailSheet(
    BuildContext context, WidgetRef ref, Category c) async {
  final l = L.of(context);
  final money = ref.read(moneyProvider);
  final settings = settingsOf(ref);
  final locale = localeOf(settings);
  final cfg = chartCfg(settings);
  final cats = ref.read(categoriesProvider).value ?? const <Category>[];
  final txs = ref.read(periodTxsProvider).value ?? const <Transaction>[];
  final all = await ref.read(txRepoProvider).all();
  if (!context.mounted) return;

  final ui = ref.read(uiProvider);
  final col = catColor(c, cats.indexOf(c), cfg.palette);
  final s = sums(txs);
  final vals = (c.type == 'expense' ? s.expVals : s.incVals)
      .where((v) => v.t.categoryId == c.id)
      .toList();
  final total = vals.fold<int>(0, (a, v) => a + v.val.abs());
  final cnt = vals.length;
  final lim = c.type == 'expense' ? c.limitKop : null;
  final lpct = lim != null && lim > 0 ? (100 * total / lim).round() : 0;

  // 6-month sparkline
  final now = DateTime.now();
  final months = [
    for (var i = 0; i < 6; i++) DateTime(now.year, now.month - 5 + i, 1)
  ];
  final allVals = computeVals(all);
  final sums6 = [
    for (final mStart in months)
      allVals.where((v) {
        final e = DateTime(mStart.year, mStart.month + 1, 1);
        return v.t.categoryId == c.id &&
            !v.t.time.isBefore(mStart) &&
            v.t.time.isBefore(e);
      }).fold<int>(0, (a, v) => a + v.val.abs())
  ];
  final mx = sums6.fold<int>(1, (a, v) => v > a ? v : a);

  await showAppSheet(
    context,
    Builder(builder: (context) {
      final t = tk(context);
      final fillCol = lim != null && lim > 0
          ? (lpct > 100
              ? t.expense
              : lpct >= 80
                  ? t.accent
                  : t.income)
          : col;
      return m.Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              EmTile(c.emoji, color: col, size: 54, fontSize: 26, radius: 16),
              const SizedBox(width: 13),
              Expanded(
                child: m.Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.name,
                          style: TextStyle(
                              fontFamily: 'Unbounded',
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: t.ink)),
                      const SizedBox(height: 2),
                      Text(
                          l.xOpsAvg('$cnt',
                              money.fmt(cnt > 0 ? total ~/ cnt : 0)),
                          style: TextStyle(fontSize: 12.5, color: t.ink2)),
                    ]),
              ),
              Text(money.fmt(total),
                  style: TextStyle(
                      fontFamily: 'Unbounded',
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: t.ink)),
            ]),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                  color: t.surface2,
                  border: Border.all(color: t.line),
                  borderRadius: BorderRadius.circular(16)),
              child: m.Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                          lim != null && lim > 0
                              ? '${l.limit} ${money.fmt(lim)}'
                              : l.xNoLimitRel,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: t.ink2)),
                      if (lim != null && lim > 0)
                        Text('$lpct%',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: t.accent)),
                    ]),
                const SizedBox(height: 10),
                Bar(
                    pct: lim != null && lim > 0
                        ? lpct.clamp(0, 100).toDouble()
                        : (total > 0 ? 100 : 0),
                    color: fillCol,
                    height: 8),
                const SizedBox(height: 16),
                SizedBox(
                  height: 56,
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final (i, v) in sums6.indexed) ...[
                          if (i > 0) const SizedBox(width: 5),
                          Expanded(
                            child: GrowY(
                              index: i,
                              child: Container(
                                height: 56 *
                                    (v / mx).clamp(0.07, 1.0),
                                decoration: BoxDecoration(
                                  gradient: i == 5 ? t.gradient : null,
                                  color: i == 5
                                      ? null
                                      : t.accent.withValues(alpha: .26),
                                  borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(6),
                                      bottom: Radius.circular(3)),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ]),
                ),
                const SizedBox(height: 6),
                Text(l.x6moDynamics,
                    style: TextStyle(fontSize: 11.5, color: t.ink3)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
              child: Text(l.xOperations,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .8,
                      color: t.ink2)),
            ),
            if (vals.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 26),
                decoration: BoxDecoration(
                    color: t.surface2,
                    border: Border.all(color: t.line),
                    borderRadius: BorderRadius.circular(16)),
                child: m.Column(children: [
                  const Opacity(
                      opacity: .6,
                      child: Text('🧾', style: TextStyle(fontSize: 30))),
                  const SizedBox(height: 8),
                  Text(l.xNoOpsPeriod,
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: t.ink2)),
                  const SizedBox(height: 3),
                  Text(l.xTxAutoAppear,
                      style: TextStyle(fontSize: 12, color: t.ink3)),
                ]),
              )
            else
              for (final v in vals.take(10))
                Container(
                  margin: const EdgeInsets.only(bottom: 7),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: t.surface2,
                      border: Border.all(color: t.line),
                      borderRadius: BorderRadius.circular(14)),
                  child: Row(children: [
                    EmTile(c.emoji, color: col),
                    const SizedBox(width: 12),
                    Expanded(
                      child: m.Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                v.t.description.isNotEmpty
                                    ? v.t.description
                                    : c.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: t.ink)),
                            const SizedBox(height: 2),
                            Text(
                                '${fmtDayMonth(v.t.time, locale)}${v.t.subcategory != null ? ' · ${v.t.subcategory}' : ''}',
                                style: TextStyle(
                                    color: t.ink2, fontSize: 12)),
                          ]),
                    ),
                    Text(
                        '${v.val > 0 ? '+' : '−'}${money.fmt(v.val.abs())}',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: v.val > 0 ? t.income : t.ink)),
                  ]),
                ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: Btn(l.xEdit, kind: 'ghost', margin: EdgeInsets.zero,
                    onTap: () {
                  Navigator.pop(context);
                  Future.delayed(const Duration(milliseconds: 60),
                      () {
                    if (context.mounted) showCatEditSheet(context, ref, c);
                  });
                }),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Btn(l.xAllTx, margin: EdgeInsets.zero, onTap: () {
                  Navigator.pop(context);
                  ui.filterCatBox = c.id;
                  ui.filterSign = c.type == 'expense' ? -1 : 1;
                  ui.setTab('txs');
                }),
              ),
            ]),
          ]);
    }),
  );
}
