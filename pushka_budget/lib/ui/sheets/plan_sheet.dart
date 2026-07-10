import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart' hide Column;
import 'package:flutter/material.dart' as m show Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/plans.dart';
import '../../data/db/database.dart';
import '../../data/repos/analytics.dart';
import '../../l10n/app_localizations.dart';
import '../../state.dart';
import '../widgets/common.dart';
import 'tx_sheet.dart';

/// planSheet() — create/edit a planned payment, with recurring suggestions
/// (detectRecurring) when creating a new one, cadence segment (5 options),
/// day-of-month vs anchor date, notify/active toggles, delete with undo.
Future<void> showPlanSheet(
    BuildContext context, WidgetRef ref, PlannedPayment? p) async {
  final l = L.of(context);
  final money = ref.read(moneyProvider);
  final repo = ref.read(plannedRepoProvider);
  final db = ref.read(dbProvider);
  final settings = settingsOf(ref);
  final cats = ref.read(categoriesProvider).value ?? const <Category>[];

  var cad = p == null ? 'month' : planMeta(settings, p.id).p;
  final anchorInit = p == null ? '' : (planMeta(settings, p.id).a ?? '');
  final nameCtl = TextEditingController(text: p?.name ?? '');
  final amtCtl = TextEditingController(
      text: p == null ? '' : '${p.amountKop / 100}');
  final dayCtl = TextEditingController(text: p?.day.toString() ?? '');
  final noteCtl = TextEditingController(text: p?.note ?? '');
  String? categoryId = p?.categoryId;
  var notify = p?.notify ?? true;
  var active = p?.active ?? true;
  var anchor = anchorInit.isNotEmpty
      ? anchorInit
      : DateTime.now().toIso8601String().substring(0, 10);

  // suggestions for new plans
  List<RecurringHit> suggestions = const [];
  if (p == null) {
    final all = await ref.read(txRepoProvider).all();
    final plannedNames = ((ref.read(plannedProvider).value) ?? const [])
        .map((x) => x.name.toLowerCase())
        .toSet();
    final hidden =
        ((settings['subs_hidden'] as List?) ?? const []).cast<String>().toSet();
    suggestions = detectRecurring(all)
        .where((s) =>
            !plannedNames.contains(s.nm.toLowerCase()) && !hidden.contains(s.nm))
        .toList()
      ..sort((a, b) {
        final d = (b.sameDay ? 1 : 0) - (a.sameDay ? 1 : 0);
        return d != 0 ? d : b.mean.compareTo(a.mean);
      });
    suggestions = suggestions.take(6).toList();
  }
  if (!context.mounted) return;

  await showAppSheet(
    context,
    StatefulBuilder(builder: (context, setState) {
      final t = tk(context);
      return m.Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetTitle(p == null ? l.planNew : l.planEdit),
            if (suggestions.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 8, top: 2),
                child: Text(l.suggestions.toUpperCase(),
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .5,
                        color: t.ink2)),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Wrap(spacing: 7, runSpacing: 7, children: [
                  for (final s in suggestions)
                    Press(
                      onTap: () => setState(() {
                        nameCtl.text = s.nm;
                        amtCtl.text =
                            (s.mean.round() / 100).toStringAsFixed(2);
                        cad = 'month';
                        dayCtl.text = '${s.day != 0 ? s.day : s.lastDay}';
                        if (s.lastCid != null) categoryId = s.lastCid;
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                            color: t.surface2,
                            border: Border.all(color: t.line),
                            borderRadius: BorderRadius.circular(12)),
                        child: m.Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.nm,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: t.ink)),
                              Text(
                                  '≈${money.fmt(s.mean)}${l.perMo} · ${s.sameDay ? '📌 ${s.day}' : '${s.n} ${l.moRow}'}',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: t.ink3)),
                            ]),
                      ),
                    ),
                ]),
              ),
            ],
            Fld(l.planName,
                child: AppInput(controller: nameCtl, placeholder: l.xPlanPh)),
            Fld(l.cadence,
                child: Wrap(spacing: 2, runSpacing: 4, children: [
                  for (final k in kCadOrder)
                    ChipBtn(_cadLabel(l, k), on: cad == k,
                        onTap: () => setState(() => cad = k)),
                ])),
            Row(children: [
              Expanded(
                child: Fld('${l.amountUah}, ₴',
                    child: AppInput(
                        controller: amtCtl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true))),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: cad == 'month'
                    ? Fld(l.planDay,
                        child: AppInput(
                            controller: dayCtl,
                            keyboardType: TextInputType.number))
                    : Fld(l.nextDate,
                        child: Press(
                          onTap: () async {
                            final picked = await showDatePicker(
                                context: context,
                                initialDate:
                                    DateTime.tryParse(anchor) ?? DateTime.now(),
                                firstDate: DateTime(2015),
                                lastDate: DateTime(2035));
                            if (picked != null) {
                              setState(() => anchor = picked
                                  .toIso8601String()
                                  .substring(0, 10));
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 13, vertical: 12),
                            decoration: BoxDecoration(
                                color: t.surface2,
                                border: Border.all(color: t.line),
                                borderRadius: BorderRadius.circular(13)),
                            child: Text(anchor,
                                style:
                                    TextStyle(color: t.ink, fontSize: 15)),
                          ),
                        )),
              ),
            ]),
            Fld(l.category,
                child: CatDropdown(
                    cats: cats,
                    type: 'expense',
                    selected: categoryId,
                    noCatLabel: l.noCat,
                    onChanged: (v) => setState(() => categoryId = v))),
            Fld(l.note, child: AppInput(controller: noteCtl)),
            _CheckRow(
                label: l.planNotify,
                value: notify,
                onChanged: (v) => setState(() => notify = v)),
            if (p != null)
              _CheckRow(
                  label: l.planActive,
                  value: active,
                  onChanged: (v) => setState(() => active = v)),
            Btn(l.save, onTap: () async {
              final name = nameCtl.text.trim();
              final grn = double.tryParse(amtCtl.text.replaceAll(',', '.'));
              if (name.isEmpty || grn == null || grn <= 0) {
                ToastHost.show(context, l.xNeedNameAmount);
                return;
              }
              int day;
              String? anchorOut;
              if (cad == 'month') {
                day = int.tryParse(dayCtl.text) ?? 0;
                if (day < 1 || day > 31) {
                  ToastHost.show(context, l.xNeedDay);
                  return;
                }
              } else {
                anchorOut = anchor;
                day = DateTime.parse(anchor).day;
              }
              final id = p?.id ?? genUuid();
              await repo.upsert(PlannedPaymentsCompanion(
                  id: Value(id),
                  name: Value(name),
                  amountKop: Value((grn * 100).round()),
                  day: Value(day),
                  categoryId: Value(categoryId),
                  note: Value(
                      noteCtl.text.trim().isEmpty ? null : noteCtl.text.trim()),
                  notify: Value(notify),
                  active: Value(active)));
              // plan_meta lives in settings (PWA parity)
              final meta =
                  Map<String, dynamic>.from(settings['plan_meta'] as Map? ?? {});
              if (cad != 'month') {
                meta[id] = {'p': cad, 'a': anchorOut};
              } else {
                meta.remove(id);
              }
              await db.setSetting('plan_meta', meta);
              if (!context.mounted) return;
              Navigator.pop(context);
              ToastHost.show(context, l.saved);
            }),
            if (p != null)
              Btn(l.deleteBtn, kind: 'danger', onTap: () async {
                final snap = p;
                await repo.delete(p.id);
                final meta = Map<String, dynamic>.from(
                    settings['plan_meta'] as Map? ?? {});
                final metaSnap = meta[p.id];
                meta.remove(p.id);
                await db.setSetting('plan_meta', meta);
                if (!context.mounted) return;
                Navigator.pop(context);
                ToastHost.show(context, l.deleted, undoLabel: l.cancelUndo,
                    undo: () async {
                  await repo.upsert(PlannedPaymentsCompanion(
                      id: Value(snap.id),
                      name: Value(snap.name),
                      amountKop: Value(snap.amountKop),
                      day: Value(snap.day),
                      categoryId: Value(snap.categoryId),
                      note: Value(snap.note),
                      notify: Value(snap.notify),
                      active: Value(snap.active)));
                  if (metaSnap != null) {
                    final m2 = Map<String, dynamic>.from(
                        settings['plan_meta'] as Map? ?? {});
                    m2[snap.id] = metaSnap;
                    await db.setSetting('plan_meta', m2);
                  }
                });
              }),
          ]);
    }),
  );
}

String _cadLabel(L l, String k) => switch (k) {
      'week' => l.cadWeek,
      'quarter' => l.cadQuarter,
      'half' => l.cadHalf,
      'year' => l.cadYear,
      _ => l.cadMonth,
    };

class _CheckRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _CheckRow(
      {required this.label, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final t = tk(context);
    return Press(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          Container(
            width: 20,
            height: 20,
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
