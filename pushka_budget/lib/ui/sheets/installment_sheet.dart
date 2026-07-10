import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart' hide Column;
import 'package:flutter/material.dart' as m show Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/database.dart';
import '../../l10n/app_localizations.dart';
import '../../state.dart';
import '../widgets/common.dart';
import 'tx_sheet.dart';

/// instSheet() — create/edit an installment: bank, name, total, months
/// total/paid, next due date, category, owner segment, delete.
Future<void> showInstallmentSheet(
    BuildContext context, WidgetRef ref, Installment? i) async {
  final l = L.of(context);
  final repo = ref.read(instRepoProvider);
  final cats = ref.read(categoriesProvider).value ?? const <Category>[];
  final tokens = ref.read(tokensProvider).value ?? const <MonoToken>[];

  final nameCtl = TextEditingController(text: i?.name ?? '');
  final bankCtl = TextEditingController(text: i?.bank ?? '');
  final totalCtl = TextEditingController(
      text: i != null && i.totalKop > 0 ? '${i.totalKop / 100}' : '');
  final mtCtl = TextEditingController(text: '${i?.monthsTotal ?? 6}');
  final mpCtl = TextEditingController(text: '${i?.monthsPaid ?? 0}');
  var firstDue =
      i?.firstDue ?? DateTime.now().toIso8601String().substring(0, 10);
  String? categoryId = i?.categoryId;
  String owner = i?.owner ?? '';

  // owner options: legacy vadim/alisa always, plus any custom token owners
  final ownerKeys = <String>{'vadim', 'alisa', ...tokens.map((t) => t.ownerKey)};

  await showAppSheet(
    context,
    StatefulBuilder(builder: (context, setState) {
      final t = tk(context);
      return m.Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetTitle(i == null ? l.instAdd : i.name),
            Fld(l.planName,
                child: AppInput(controller: nameCtl, placeholder: 'iPhone 15')),
            Fld(l.instBank,
                child: AppInput(controller: bankCtl, placeholder: 'Monobank')),
            Fld('${l.instTotal}, ₴',
                child: AppInput(
                    controller: totalCtl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true))),
            Row(children: [
              Expanded(
                child: Fld(l.instPays,
                    child: AppInput(
                        controller: mtCtl,
                        keyboardType: TextInputType.number)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Fld(l.instDoneN,
                    child: AppInput(
                        controller: mpCtl,
                        keyboardType: TextInputType.number)),
              ),
            ]),
            Fld(l.instNext,
                child: Press(
                  onTap: () async {
                    final picked = await showDatePicker(
                        context: context,
                        initialDate:
                            DateTime.tryParse(firstDue) ?? DateTime.now(),
                        firstDate: DateTime(2015),
                        lastDate: DateTime(2035));
                    if (picked != null) {
                      setState(() => firstDue =
                          picked.toIso8601String().substring(0, 10));
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 13, vertical: 12),
                    decoration: BoxDecoration(
                        color: t.surface2,
                        border: Border.all(color: t.line),
                        borderRadius: BorderRadius.circular(13)),
                    child: Text(firstDue,
                        style: TextStyle(color: t.ink, fontSize: 15)),
                  ),
                )),
            Fld(l.category,
                child: CatDropdown(
                    cats: cats,
                    type: 'expense',
                    selected: categoryId,
                    noCatLabel: l.noCat,
                    onChanged: (v) => setState(() => categoryId = v))),
            Fld('👤',
                child: Seg(
                  items: [
                    ('', '—'),
                    for (final k in ownerKeys)
                      (k, k == 'vadim' ? 'В' : k == 'alisa' ? 'А' : k.substring(0, 1).toUpperCase()),
                  ],
                  value: owner,
                  onChanged: (v) => setState(() => owner = v),
                )),
            Btn(l.save, onTap: () async {
              final total = ((double.tryParse(
                          totalCtl.text.replaceAll(',', '.')) ??
                      0) *
                  100)
                  .round();
              final mt = (int.tryParse(mtCtl.text) ?? 1).clamp(1, 1 << 31);
              final mp = (int.tryParse(mpCtl.text) ?? 0).clamp(0, mt);
              final name = nameCtl.text.trim();
              if (name.isEmpty || total <= 0) {
                ToastHost.show(context, l.instTotal);
                return;
              }
              await repo.upsert(InstallmentsCompanion(
                  id: Value(i?.id ?? genUuid()),
                  bank: Value(bankCtl.text.trim()),
                  name: Value(name),
                  totalKop: Value(total),
                  monthsTotal: Value(mt),
                  monthsPaid: Value(mp),
                  firstDue: Value(firstDue),
                  categoryId: Value(categoryId),
                  owner: Value(owner.isEmpty ? null : owner),
                  archived: Value(mp >= mt)));
              if (!context.mounted) return;
              Navigator.pop(context);
              ToastHost.show(context, l.saved);
            }),
            if (i != null)
              Btn(l.deleteBtn, kind: 'danger', onTap: () async {
                await repo.delete(i.id);
                if (!context.mounted) return;
                Navigator.pop(context);
                ToastHost.show(context, l.deleted);
              }),
          ]);
    }),
  );
}
