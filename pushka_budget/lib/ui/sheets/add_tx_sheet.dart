import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart' hide Column;
import 'package:flutter/material.dart' as m show Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/database.dart';
import '../../l10n/app_localizations.dart';
import '../../state.dart';
import '../widgets/common.dart';
import 'tx_sheet.dart';

/// addSheet() — manual transaction entry (FAB).
Future<void> showAddTxSheet(BuildContext context, WidgetRef ref) async {
  final l = L.of(context);
  final repo = ref.read(txRepoProvider);
  final cats = ref.read(categoriesProvider).value ?? const <Category>[];

  var type = 'expense';
  String? categoryId;
  var date = DateTime.now();
  final amountCtl = TextEditingController();
  final subCtl = TextEditingController();
  final descCtl = TextEditingController();

  await showAppSheet(
    context,
    StatefulBuilder(builder: (context, setState) {
      final t = tk(context);
      return m.Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetTitle(l.addTx),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Seg(
                items: [('expense', l.expense), ('income', l.income)],
                value: type,
                onChanged: (v) => setState(() {
                  type = v;
                  categoryId = null;
                }),
              ),
            ),
            Row(children: [
              Expanded(
                child: Fld('${l.amountUah}, ₴',
                    child: AppInput(
                        controller: amountCtl,
                        placeholder: '0',
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true))),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Fld(l.date,
                    child: Press(
                      onTap: () async {
                        final picked = await showDatePicker(
                            context: context,
                            initialDate: date,
                            firstDate: DateTime(2015),
                            lastDate:
                                DateTime.now().add(const Duration(days: 1)));
                        if (picked != null) setState(() => date = picked);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 13, vertical: 12),
                        decoration: BoxDecoration(
                            color: t.surface2,
                            border: Border.all(color: t.line),
                            borderRadius: BorderRadius.circular(13)),
                        child: Text(
                            date.toIso8601String().substring(0, 10),
                            style: TextStyle(color: t.ink, fontSize: 15)),
                      ),
                    )),
              ),
            ]),
            Fld(l.category,
                child: CatDropdown(
                    cats: cats,
                    type: type,
                    selected: categoryId,
                    noCatLabel: l.noCat,
                    onChanged: (v) => setState(() => categoryId = v))),
            Row(children: [
              Expanded(
                child: Fld(l.subcategory,
                    child: AppInput(
                        controller: subCtl, placeholder: l.xOptionalPh)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Fld(l.descr,
                    child:
                        AppInput(controller: descCtl, placeholder: l.xDescPh)),
              ),
            ]),
            Btn(l.add, onTap: () async {
              final grn =
                  double.tryParse(amountCtl.text.replaceAll(',', '.'));
              if (grn == null || grn <= 0) {
                ToastHost.show(context, l.xNeedAmount);
                return;
              }
              final kop = (grn * 100).round();
              final now = DateTime.now();
              await repo.insert(TransactionsCompanion(
                  id: Value(genUuid()),
                  time: Value(DateTime(date.year, date.month, date.day,
                      now.hour, now.minute, now.second)),
                  description: Value(descCtl.text.trim()),
                  amount: Value(type == 'expense' ? -kop : kop),
                  categoryId: Value(categoryId),
                  subcategory: Value(
                      subCtl.text.trim().isEmpty ? null : subCtl.text.trim()),
                  source: const Value('manual')));
              if (!context.mounted) return;
              Navigator.pop(context);
              ToastHost.show(context, l.xAdded);
            }),
          ]);
    }),
  );
}
