import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart' hide Column;
import 'package:flutter/material.dart' as m show Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/months.dart';
import '../../data/db/database.dart';
import '../../data/repos/analytics.dart';
import '../../l10n/app_localizations.dart';
import '../../state.dart';
import '../util.dart';
import '../widgets/common.dart';

/// subSheet() — auto-detected subscription detail: charge history, next
/// expected date, promote to planned, hide from list (with undo).
Future<void> showSubSheet(
    BuildContext context, WidgetRef ref, RecurringHit s) async {
  final l = L.of(context);
  final money = ref.read(moneyProvider);
  final db = ref.read(dbProvider);
  final settings = settingsOf(ref);
  final locale = localeOf(settings);
  final repo = ref.read(plannedRepoProvider);

  // next expected charge by last day-of-month
  DateTime next() {
    final n = DateTime.now();
    int clampDay(int y, int mo, int d) {
      final last = DateTime(y, mo + 1, 0).day;
      return d > last ? last : d;
    }

    var d = DateTime(n.year, n.month, clampDay(n.year, n.month, s.lastDay));
    if (!d.isAfter(n)) {
      d = DateTime(
          n.year, n.month + 1, clampDay(n.year, n.month + 1, s.lastDay));
    }
    return d;
  }

  final nx = next();

  await showAppSheet(
    context,
    Builder(builder: (context) {
      final t = tk(context);
      return m.Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetTitle(s.nm),
            SheetMeta(
                '${l.subsAuto}: ${s.n} ${l.moRow}, ≈${money.fmt(s.mean)}${l.perMo} · ${money.fmt(s.mean * 12)}${l.perYr}\n'
                '${l.subsNext} ${fmtDayMonth(nx, locale)}'),
            Fld(l.subsLast,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                      color: t.surface2,
                      border: Border.all(color: t.line),
                      borderRadius: BorderRadius.circular(14)),
                  child: m.Column(children: [
                    for (final h in s.hist)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                  '${h.time.day} ${monthsShort(locale)[h.time.month - 1]} ${'${h.time.year}'.substring(2)}',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w500,
                                      color: t.ink2)),
                              Text(money.fmt(h.a),
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: t.ink)),
                            ]),
                      ),
                  ]),
                )),
            Btn(l.toPlanned, onTap: () async {
              await repo.upsert(PlannedPaymentsCompanion(
                  id: Value(genUuid()),
                  name: Value(s.nm),
                  amountKop: Value(s.mean.round()),
                  day: Value(s.lastDay),
                  categoryId: Value(s.lastCid),
                  notify: const Value(true),
                  active: const Value(true)));
              if (!context.mounted) return;
              Navigator.pop(context);
              ToastHost.show(context, l.planAdded);
            }),
            Btn(l.hideFromList, kind: 'danger', onTap: () async {
              final hidden = [
                ...((settings['subs_hidden'] as List?) ?? const [])
                    .cast<String>(),
                s.nm
              ];
              await db.setSetting('subs_hidden', hidden);
              if (!context.mounted) return;
              Navigator.pop(context);
              ToastHost.show(context, l.hiddenOk, undoLabel: l.cancelUndo,
                  undo: () async {
                await db.setSetting('subs_hidden',
                    hidden.where((n) => n != s.nm).toList());
              });
            }),
          ]);
    }),
  );
}
