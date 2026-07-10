import 'package:flutter/material.dart' hide Column;
import 'package:flutter/material.dart' as m show Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/months.dart';
import '../../data/db/database.dart';
import '../../data/repos/repos.dart';
import '../../l10n/app_localizations.dart';
import '../../state.dart';
import '../sheets/installment_sheet.dart';
import '../util.dart';
import '../widgets/common.dart';

/// Installments «Оплати частинами» — port of renderInstallments().
class InstallmentsScreen extends ConsumerWidget {
  const InstallmentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = tk(context);
    final l = L.of(context);
    final ui = ref.watch(uiProvider);
    final money = ref.watch(moneyProvider);
    final settings = settingsOf(ref);
    final locale = localeOf(settings);
    final list = ref.watch(installmentsProvider).value ?? const <Installment>[];
    final cats = ref.watch(categoriesProvider).value ?? const <Category>[];
    final repo = ref.read(instRepoProvider);

    final active = list.where((i) => !i.archived).toList();
    final sumLeft = active.fold<int>(0, (s, i) => s + instLeftKop(i));
    final today = DateTime.now();
    final today0 = DateTime(today.year, today.month, today.day);
    final sorted = [...list]..sort((a, b) {
        final d = (a.archived ? 1 : 0) - (b.archived ? 1 : 0);
        return d != 0 ? d : instNextDue(a).compareTo(instNextDue(b));
      });

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 130,
              child: Btn(l.back, kind: 'ghost', margin: EdgeInsets.zero,
                  onTap: () => ui.setTab('more')),
            ),
          ),
        ),
        SecH(l.instTitle,
            margin: const EdgeInsets.fromLTRB(2, 0, 2, 10),
            trailing: Press(
              onTap: () => showInstallmentSheet(context, ref, null),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    border: Border.all(color: t.line),
                    borderRadius: BorderRadius.circular(8)),
                child: Text('＋',
                    style: TextStyle(fontSize: 14, color: t.accent)),
              ),
            )),
        if (active.isNotEmpty)
          AppCard(
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${l.instSum} · ${active.length}',
                      style: TextStyle(
                          color: t.ink2,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                  Text(money.fmt(sumLeft),
                      style: TextStyle(
                          fontFamily: 'Unbounded',
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: t.ink)),
                ]),
          ),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 20),
            child: Text(l.instNone,
                textAlign: TextAlign.center,
                style: TextStyle(color: t.ink3, fontSize: 14, height: 1.6)),
          )
        else
          for (final (idx, i) in sorted.indexed)
            _InstCard(
                index: idx,
                inst: i,
                cat: cats.where((c) => c.id == i.categoryId).firstOrNull,
                money: money,
                locale: locale,
                today0: today0,
                l: l,
                onPay: () async {
                  final done = await repo.pay(i.id);
                  if (context.mounted) {
                    ToastHost.show(
                        context, done ? l.instDoneBadge : l.instPlus);
                  }
                },
                onOpen: () => showInstallmentSheet(context, ref, i)),
      ],
    );
  }
}

class _InstCard extends StatelessWidget {
  final int index;
  final Installment inst;
  final Category? cat;
  final dynamic money;
  final String locale;
  final DateTime today0;
  final L l;
  final VoidCallback onPay;
  final VoidCallback onOpen;
  const _InstCard(
      {required this.index,
      required this.inst,
      required this.cat,
      required this.money,
      required this.locale,
      required this.today0,
      required this.l,
      required this.onPay,
      required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final t = tk(context);
    final paidN = inst.monthsPaid > inst.monthsTotal
        ? inst.monthsTotal
        : inst.monthsPaid;
    final pct = (100 * paidN / inst.monthsTotal).round();
    final done = inst.archived || paidN >= inst.monthsTotal;
    final due = instNextDue(inst);
    final dd = due.difference(today0).inDays;
    final when = done
        ? ''
        : dd <= 0
            ? l.today
            : dd == 1
                ? l.tomorrow
                : fmtDayMonth(due, locale);
    final own = inst.owner == 'vadim'
        ? 'В'
        : inst.owner == 'alisa'
            ? 'А'
            : null;

    return Enter(
      index: index,
      stepMs: 45,
      durMs: 400,
      child: Press(
        scale: .99,
        onTap: onOpen,
        child: Opacity(
          opacity: done ? .6 : 1,
          child: AppCard(
            child:
                m.Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Wrap(
                      spacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                            '${cat != null ? '${cat!.emoji} ' : ''}${inst.name}',
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14.5,
                                color: t.ink)),
                        if (own != null)
                          OwnerBadge(inst.owner!, own),
                        if (inst.bank.isNotEmpty)
                          Text(inst.bank,
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                  color: t.ink3)),
                      ]),
                ),
                if (done)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                        border: Border.all(
                            color: t.income.withValues(alpha: .45)),
                        borderRadius: BorderRadius.circular(8)),
                    child: Text(l.instDoneBadge,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: t.income)),
                  )
                else
                  Press(
                    onTap: onPay,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                          color: t.accent,
                          borderRadius: BorderRadius.circular(9)),
                      child: Text(l.instPlus,
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: t.accentInk)),
                    ),
                  ),
              ]),
              const SizedBox(height: 9),
              Bar(pct: pct.toDouble(), color: t.accent, gradient: t.gradient,
                  height: 8),
              const SizedBox(height: 9),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(
                    '$paidN / ${inst.monthsTotal} · ${money.fmt(instMonthly(inst))}${l.perMo}',
                    style: TextStyle(
                        fontSize: 13,
                        color: t.ink2,
                        fontWeight: FontWeight.w600)),
                Text(
                    done
                        ? money.fmt(inst.totalKop)
                        : '${l.instNext}: $when',
                    style: TextStyle(
                        fontSize: 13,
                        color: t.ink2,
                        fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 4),
              Text(
                  '${l.instPaid} ${money.fmt(instPaidKop(inst))} · ${l.instLeft} ${money.fmt(instLeftKop(inst))}',
                  style: TextStyle(fontSize: 12, color: t.ink3)),
            ]),
          ),
        ),
      ),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
