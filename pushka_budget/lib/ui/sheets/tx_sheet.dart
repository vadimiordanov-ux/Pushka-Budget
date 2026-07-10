import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart' hide Column;
import 'package:flutter/material.dart' as m show Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/months.dart';
import '../../data/db/database.dart';
import '../../l10n/app_localizations.dart';
import '../../state.dart';
import '../util.dart';
import '../widgets/common.dart';

/// Category dropdown options — catOptions() port.
class CatDropdown extends StatelessWidget {
  final List<Category> cats;
  final String type;
  final String? selected;
  final ValueChanged<String?> onChanged;
  final String noCatLabel;
  const CatDropdown(
      {super.key,
      required this.cats,
      required this.type,
      required this.selected,
      required this.onChanged,
      required this.noCatLabel});

  @override
  Widget build(BuildContext context) {
    final t = tk(context);
    final items = cats.where((c) => c.type == type && !c.archived).toList();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(
          color: t.surface2,
          border: Border.all(color: t.line),
          borderRadius: BorderRadius.circular(13)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: items.any((c) => c.id == selected) ? selected : '',
          isExpanded: true,
          dropdownColor: t.surface,
          style: TextStyle(color: t.ink, fontSize: 15, fontFamily: 'Manrope'),
          items: [
            DropdownMenuItem(
                value: '',
                child: Text('— ${noCatLabel.toLowerCase()} —',
                    style: TextStyle(color: t.ink2))),
            for (final c in items)
              DropdownMenuItem(
                  value: c.id, child: Text('${c.emoji} ${c.name}')),
          ],
          onChanged: (v) => onChanged(v == '' ? null : v),
        ),
      ),
    );
  }
}

/// txSheet() — transaction detail/edit sheet.
Future<void> showTxSheet(
    BuildContext context, WidgetRef ref, Transaction tx) async {
  final l = L.of(context);
  final money = ref.read(moneyProvider);
  final settings = settingsOf(ref);
  final locale = localeOf(settings);
  final repo = ref.read(txRepoProvider);
  final cats = ref.read(categoriesProvider).value ?? const <Category>[];
  final accounts = ref.read(accountsProvider).value ?? const <Account>[];
  final periodTxs = ref.read(periodTxsProvider).value ?? const <Transaction>[];

  final o = accounts.where((a) => a.id == tx.accountId).firstOrNull;
  final kids = periodTxs.where((x) => x.parentId == tx.id).toList();
  final kidsSum = kids.fold<int>(0, (s, x) => s + x.amount);
  final reimbs = periodTxs.where((x) => x.reimburses == tx.id).toList();
  final reimbSum = reimbs.fold<int>(0, (s, x) => s + x.amount);

  final amountCtl =
      TextEditingController(text: '${tx.amount.abs() / 100}');
  final subCtl = TextEditingController(text: tx.subcategory ?? '');
  final noteCtl = TextEditingController(text: tx.note ?? '');
  String? categoryId = tx.categoryId;
  var makeRule = false;
  var internal = tx.internal;

  final d = tx.time;
  final metaParts = [
    tx.description.isEmpty ? '—' : tx.description,
    '\n${d.day} ${monthsShort(locale)[d.month - 1]} ${d.year}, '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}',
    if (o != null)
      ' · ${o.cardName}'
    else if (tx.accountId != null)
      ' · ${l.card} ${tx.accountId!.substring(0, 6)}…'
    else
      ' · ${l.manual}',
    if (tx.mcc != null && tx.mcc != 0) ' · MCC ${tx.mcc}',
    if (tx.cashback != 0) ' · ${l.xCashbackMeta(money.fmt(tx.cashback))}',
    if (kids.isNotEmpty)
      '\n${l.xSplitInfo('${kids.length}', money.fmt(-kidsSum), money.fmt(-tx.amount))}',
    if (reimbSum != 0)
      '\n${l.xReimbInfo(money.fmt(reimbSum), money.fmt((-tx.amount - reimbSum).clamp(0, 1 << 62)))}',
    if (tx.reimburses != null) '\n${l.xReimbLinkedFlag}',
  ].join();

  await showAppSheet(
    context,
    StatefulBuilder(builder: (context, setState) {
      return m.Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetTitle(
                '${tx.amount > 0 ? '+' : '−'}${money.fmt(tx.amount.abs())}'),
            SheetMeta(metaParts),
            Row(children: [
              Expanded(
                child: Fld(
                    '${l.amountUah}, ₴${tx.source == 'monobank' ? ' · ${l.editAmountNote}' : ''}',
                    child: AppInput(
                        controller: amountCtl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true))),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Fld(l.category,
                    child: CatDropdown(
                        cats: cats,
                        type: tx.amount > 0 ? 'income' : 'expense',
                        selected: categoryId,
                        noCatLabel: l.noCat,
                        onChanged: (v) => setState(() => categoryId = v))),
              ),
            ]),
            Fld(l.subcategory,
                child: AppInput(controller: subCtl, placeholder: l.xSubPh)),
            Fld(l.note,
                child: AppInput(controller: noteCtl, placeholder: l.xNotePh)),
            if (tx.description.isNotEmpty)
              _Check(
                  value: makeRule,
                  onChanged: (v) => setState(() => makeRule = v),
                  label: l.xRuleRemember(
                      tx.description,
                      tx.mcc != null && tx.mcc != 0 ? ' + MCC ${tx.mcc}' : '')),
            _Check(
                value: internal,
                onChanged: (v) => setState(() => internal = v),
                label: l.xInternalCheck),
            Btn(l.save, onTap: () async {
              final grn = double.tryParse(
                  amountCtl.text.replaceAll(',', '.'));
              if (grn == null || grn <= 0) {
                ToastHost.show(context, l.xAmountInvalid);
                return;
              }
              final newAmount =
                  (tx.amount < 0 ? -1 : 1) * (grn * 100).round();
              if (kids.isNotEmpty && -newAmount < -kidsSum) {
                ToastHost.show(context, l.xAmountLtSplit);
                return;
              }
              final oldAmount = tx.amount;
              final oldCat = tx.categoryId;
              await repo.updateFields(
                  tx.id,
                  TransactionsCompanion(
                      categoryId: Value(categoryId),
                      amount: Value(newAmount),
                      subcategory: Value(
                          subCtl.text.trim().isEmpty ? null : subCtl.text.trim()),
                      note: Value(
                          noteCtl.text.trim().isEmpty ? null : noteCtl.text.trim()),
                      internal: Value(internal)));
              if (!context.mounted) return;
              Navigator.pop(context);
              if (makeRule && categoryId != null) {
                final r = await repo.createRule(tx, categoryId!,
                    subCtl.text.trim().isEmpty ? null : subCtl.text.trim(),
                    subcategoryProvided: true);
                if (!context.mounted) return;
                ToastHost.show(context, l.xRuleCreated('${r.ids.length}'),
                    undoLabel: l.cancelUndo, undo: () async {
                  await repo.deleteRule(r.ruleId);
                  for (final p in r.prev) {
                    await repo.updateFields(
                        p.$1,
                        TransactionsCompanion(
                            categoryId: Value(p.$2),
                            subcategory: Value(p.$3)));
                  }
                  await repo.updateFields(
                      tx.id,
                      TransactionsCompanion(
                          categoryId: Value(oldCat),
                          amount: Value(oldAmount)));
                });
              } else if (newAmount != oldAmount) {
                ToastHost.show(context, l.saved, undoLabel: l.cancelUndo,
                    undo: () => repo.updateFields(tx.id,
                        TransactionsCompanion(amount: Value(oldAmount))));
              } else {
                ToastHost.show(context, l.saved);
              }
            }),
            if (tx.amount < 0 && tx.parentId == null)
              Btn(l.xSplitBtn, kind: 'ghost', onTap: () {
                Navigator.pop(context);
                showSplitSheet(context, ref, tx, kids, kidsSum);
              }),
            if (tx.amount > 0)
              Btn(tx.reimburses != null ? l.xReimbUnlink : l.xReimbLink,
                  kind: 'ghost', onTap: () async {
                if (tx.reimburses != null) {
                  await repo.updateFields(tx.id,
                      const TransactionsCompanion(reimburses: Value(null)));
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  ToastHost.show(context, l.xReimbUnlinked);
                } else {
                  Navigator.pop(context);
                  showReimbSheet(context, ref, tx);
                }
              }),
            Btn(l.xDeleteTx, kind: 'danger', onTap: () async {
              final warn = tx.source == 'monobank'
                  ? l.xDeleteBankWarn
                  : l.xDeleteWarn(
                      kids.isNotEmpty ? l.xDeleteWarnSplit : '');
              final ok = await _confirm(context, warn, l);
              if (ok != true || !context.mounted) return;
              final snapshot = await repo.deleteWithChildren(tx.id);
              if (!context.mounted) return;
              Navigator.pop(context);
              ToastHost.show(context, l.deleted, undoLabel: l.cancelUndo,
                  undo: () => repo.restore(snapshot));
            }),
          ]);
    }),
  );
}

/// splitSheet() — split an expense into parts.
Future<void> showSplitSheet(BuildContext context, WidgetRef ref,
    Transaction tx, List<Transaction> kids, int kidsSum) async {
  final l = L.of(context);
  final money = ref.read(moneyProvider);
  final repo = ref.read(txRepoProvider);
  final cats = ref.read(categoriesProvider).value ?? const <Category>[];
  final total = -tx.amount;
  final used = -kidsSum;

  final rows = <({TextEditingController grn, TextEditingController desc, String? cid})>[
    (grn: TextEditingController(), desc: TextEditingController(), cid: null)
  ];

  await showAppSheet(
    context,
    StatefulBuilder(builder: (context, setState) {
      final assigned = rows.fold<int>(0,
          (s, r) => s + ((double.tryParse(r.grn.text.replaceAll(',', '.')) ?? 0) * 100).round());
      final left = total - used - assigned;
      final t = tk(context);
      return m.Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetTitle(l.xSplitTitle(money.fmt(total))),
            SheetMeta(l.xSplitMeta(tx.description)),
            for (final (i, r) in rows.indexed) ...[
              Row(children: [
                SizedBox(
                  width: 92,
                  child: AppInput(
                      controller: r.grn,
                      placeholder: l.xGrnPh,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      onChanged: (_) => setState(() {})),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: CatDropdown(
                      cats: cats,
                      type: 'expense',
                      selected: r.cid,
                      noCatLabel: l.noCat,
                      onChanged: (v) => setState(() =>
                          rows[i] = (grn: r.grn, desc: r.desc, cid: v))),
                ),
              ]),
              const SizedBox(height: 8),
              AppInput(controller: r.desc, placeholder: l.xSplitWhatPh),
              const SizedBox(height: 8),
            ],
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: l.xSplitLeft(money.fmt(left), money.fmt(total))),
                  if (used > 0)
                    TextSpan(text: l.xSplitUsedBefore(money.fmt(used))),
                ]),
                style: TextStyle(
                    color: left < 0 ? t.expense : t.ink2, fontSize: 13),
              ),
            ),
            Btn(l.xSplitAddPart, kind: 'ghost', onTap: () {
              setState(() => rows.add((
                    grn: TextEditingController(),
                    desc: TextEditingController(),
                    cid: null
                  )));
            }),
            Btn(l.xSplitDo, onTap: () async {
              final parts = rows
                  .map((r) => (
                        kop: ((double.tryParse(
                                        r.grn.text.replaceAll(',', '.')) ??
                                    0) *
                                100)
                            .round(),
                        cid: r.cid,
                        desc: r.desc.text.trim()
                      ))
                  .where((p) => p.kop > 0)
                  .toList();
              if (parts.isEmpty) {
                ToastHost.show(context, l.xSplitNeedAmounts);
                return;
              }
              if (parts.fold<int>(0, (s, p) => s + p.kop) + used > total) {
                ToastHost.show(context, l.xSplitTooMuch);
                return;
              }
              final ids = <String>[];
              for (final p in parts) {
                final id = genUuid();
                ids.add(id);
                await repo.insert(TransactionsCompanion(
                    id: Value(id),
                    time: Value(tx.time),
                    description: Value(
                        p.desc.isNotEmpty ? p.desc : tx.description),
                    amount: Value(-p.kop),
                    categoryId: Value(p.cid),
                    source: const Value('manual'),
                    parentId: Value(tx.id),
                    accountId: Value(tx.accountId)));
              }
              if (!context.mounted) return;
              Navigator.pop(context);
              ToastHost.show(context, l.xSplitDone, undoLabel: l.cancelUndo,
                  undo: () async {
                for (final id in ids) {
                  await repo.deleteWithChildren(id);
                }
              });
            }),
          ]);
    }),
  );
}

/// reimbSheet() — link an income to the expense it reimburses.
Future<void> showReimbSheet(
    BuildContext context, WidgetRef ref, Transaction inc) async {
  final l = L.of(context);
  final money = ref.read(moneyProvider);
  final settings = settingsOf(ref);
  final locale = localeOf(settings);
  final repo = ref.read(txRepoProvider);
  final cats = ref.read(categoriesProvider).value ?? const <Category>[];
  final all = (await repo.all())
      .reversed
      .where((t) =>
          t.amount < 0 && !t.internal && t.parentId == null && t.id != inc.id)
      .toList();
  if (!context.mounted) return;

  final qCtl = TextEditingController();
  await showAppSheet(
    context,
    StatefulBuilder(builder: (context, setState) {
      final t = tk(context);
      final needle =
          qCtl.text.trim().toLowerCase().replaceAll(',', '.');
      final list = (needle.isEmpty
              ? all
              : all.where((x) =>
                  x.description.toLowerCase().contains(needle) ||
                  (x.amount.abs() / 100).toStringAsFixed(2).contains(needle)))
          .take(40)
          .toList();
      return m.Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetTitle(l.xReimbTitle(money.fmt(inc.amount))),
            SheetMeta(l.xReimbMeta),
            AppInput(
                controller: qCtl,
                placeholder: l.xReimbSearchPh,
                onChanged: (_) => setState(() {})),
            const SizedBox(height: 8),
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 30),
                child: Center(
                    child: Text(l.xNothingFound,
                        style: TextStyle(color: t.ink3))),
              )
            else
              for (final x in list)
                Press(
                  onTap: () async {
                    final prev = inc.reimburses;
                    await repo.updateFields(inc.id,
                        TransactionsCompanion(reimburses: Value(x.id)));
                    if (!context.mounted) return;
                    Navigator.pop(context);
                    ToastHost.show(context, l.xReimbLinked,
                        undoLabel: l.cancelUndo,
                        undo: () => repo.updateFields(
                            inc.id,
                            TransactionsCompanion(
                                reimburses: Value(prev))));
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(children: [
                      EmTile(
                          cats
                                  .where((c) => c.id == x.categoryId)
                                  .firstOrNull
                                  ?.emoji ??
                              '❔'),
                      const SizedBox(width: 12),
                      Expanded(
                        child: m.Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  x.description.isNotEmpty
                                      ? x.description
                                      : l.xExpenseFallback,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14.5,
                                      color: t.ink)),
                              Text(
                                  '${x.time.day} ${monthsShort(locale)[x.time.month - 1]} ${x.time.year}',
                                  style: TextStyle(
                                      color: t.ink2, fontSize: 12)),
                            ]),
                      ),
                      Text('−${money.fmt(-x.amount)}',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, color: t.ink)),
                    ]),
                  ),
                ),
          ]);
    }),
  );
}

// ---------------------------------------------------------------------------
class _Check extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;
  const _Check(
      {required this.value, required this.onChanged, required this.label});
  @override
  Widget build(BuildContext context) {
    final t = tk(context);
    return Press(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 20,
            height: 20,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              color: value ? t.accent : Colors.transparent,
              border: Border.all(color: value ? t.accent : t.ink3),
              borderRadius: BorderRadius.circular(5),
            ),
            child: value
                ? Icon(Icons.check, size: 15, color: t.accentInk)
                : null,
          ),
          const SizedBox(width: 9),
          Expanded(
              child: Text(label,
                  style: TextStyle(fontSize: 13.5, color: t.ink2))),
        ]),
      ),
    );
  }
}

Future<bool?> _confirm(BuildContext context, String message, L l) {
  final t = tk(context);
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: t.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      content: Text(message, style: TextStyle(color: t.ink, fontSize: 14.5)),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.xCancel, style: TextStyle(color: t.ink2))),
        TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.deleteBtn,
                style: TextStyle(
                    color: t.expense, fontWeight: FontWeight.w700))),
      ],
    ),
  );
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
