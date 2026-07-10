import 'package:flutter/material.dart' hide Column;
import 'package:flutter/material.dart' as m show Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/database.dart';
import '../../l10n/app_localizations.dart';
import '../../state.dart';
import '../screens/feed_screen.dart';
import '../widgets/common.dart';

/// filterSheet() — advanced feed filter: type, categories, amount range,
/// payment method, merchant.
Future<void> showFilterSheet(BuildContext context, WidgetRef ref) async {
  final l = L.of(context);
  final a = ref.read(advFilterProvider);
  final cats = (ref.read(categoriesProvider).value ?? const <Category>[])
      .where((c) => !c.archived)
      .toList();
  final minCtl = TextEditingController(text: a.min);
  final maxCtl = TextEditingController(text: a.max);
  final merchCtl = TextEditingController(text: a.merchant);

  await showAppSheet(
    context,
    StatefulBuilder(builder: (context, setState) {
      return m.Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetTitle(l.filters),
            Fld(l.type,
                child: Seg(
                  items: [
                    ('all', l.all),
                    ('expense', l.expense),
                    ('income', l.income)
                  ],
                  value: a.type,
                  onChanged: (v) => setState(() => a.type = v),
                )),
            Fld(l.category,
                child: Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final c in cats)
                    ChipBtn('${c.emoji} ${c.name}',
                        on: a.cats.contains(c.id), onTap: () {
                      setState(() => a.cats.contains(c.id)
                          ? a.cats.remove(c.id)
                          : a.cats.add(c.id));
                    }),
                ])),
            Row(children: [
              Expanded(
                child: Fld('${l.amountFrom}, ₴',
                    child: AppInput(
                        controller: minCtl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true))),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Fld('${l.amountTo}, ₴',
                    child: AppInput(
                        controller: maxCtl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true))),
              ),
            ]),
            Fld(l.card,
                child: Seg(
                  items: [
                    ('all', l.all),
                    ('card', l.card),
                    ('manual', l.manual)
                  ],
                  value: a.method,
                  onChanged: (v) => setState(() => a.method = v),
                )),
            Fld(l.topMerch,
                child: AppInput(controller: merchCtl, placeholder: 'Сільпо')),
            Btn(l.apply, onTap: () {
              a.min = minCtl.text.trim();
              a.max = maxCtl.text.trim();
              a.merchant = merchCtl.text;
              ref.read(uiProvider).bump();
              Navigator.pop(context);
            }),
            Btn(l.reset, kind: 'ghost', onTap: () {
              a.cats = [];
              a.type = 'all';
              a.min = '';
              a.max = '';
              a.merchant = '';
              a.method = 'all';
              ref.read(uiProvider).bump();
              Navigator.pop(context);
            }),
          ]);
    }),
  );
}
