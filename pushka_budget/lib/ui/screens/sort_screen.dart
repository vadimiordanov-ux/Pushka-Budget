import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart' hide Column;
import 'package:flutter/material.dart' as m show Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/haptics.dart';
import '../../core/months.dart';
import '../../data/db/database.dart';
import '../../data/repos/analytics.dart';
import '../../l10n/app_localizations.dart';
import '../../state.dart';
import '../sheets/tx_sheet.dart';
import '../util.dart';
import '../widgets/common.dart';

/// Sort helper «Розкидати» — port of renderSort(): queue of uncategorized,
/// rule checkbox, category grid, skip / internal / reimburse, optional
/// AI endpoint, confetti completion.
class SortScreen extends ConsumerStatefulWidget {
  const SortScreen({super.key});
  @override
  ConsumerState<SortScreen> createState() => _SortScreenState();
}

class _SortScreenState extends ConsumerState<SortScreen> {
  bool _makeRule = true;
  bool _aiRunning = false;
  bool _aiConfigured = false;

  @override
  void initState() {
    super.initState();
    // «✨ AI-розкидати» appears only when the Anthropic key is stored —
    // PWA parity: the button existed only when ai_endpoint was configured.
    ref.read(aiServiceProvider).configured.then((v) {
      if (mounted) setState(() => _aiConfigured = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = tk(context);
    final l = L.of(context);
    final ui = ref.watch(uiProvider);
    final settings = settingsOf(ref);
    final money = ref.watch(moneyProvider);
    final locale = localeOf(settings);
    final txs = ref.watch(periodTxsProvider).value ?? const <Transaction>[];
    final cats = ref.watch(categoriesProvider).value ?? const <Category>[];
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    final repo = ref.read(txRepoProvider);

    final sign = ui.sortSign;
    final queue = nocatQueue(txs, sign, ui.skip);

    if (queue.isEmpty) {
      return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 120), children: [
        const Confetti(colors: [
          Color(0xFFFFB937), Color(0xFFFF8A3C), Color(0xFF3DDC97),
          Color(0xFF5B9BD5), Color(0xFFE88BB5), Color(0xFFB98BE0),
          Color(0xFFFF6B81), Color(0xFF5FC9C9),
        ]),
        Center(
            child: Text(l.xAllSorted,
                style: TextStyle(fontSize: 16, color: t.ink3))),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 60),
          child: Btn(l.xToOverview, kind: 'ghost', onTap: () {
            ui.skip.clear();
            ui.setTab('home');
          }),
        ),
      ]);
    }

    final tx = queue.first;
    final acc = accounts.where((a) => a.id == tx.accountId).firstOrNull;
    final gridCats = cats
        .where((c) => c.type == (sign < 0 ? 'expense' : 'income') && !c.archived)
        .toList();

    Future<void> assign(String categoryId) async {
      await repo.updateFields(
          tx.id, TransactionsCompanion(categoryId: Value(categoryId)));
      if (_makeRule && tx.description.isNotEmpty) {
        final r = await repo.createRule(tx, categoryId, null);
        if (!context.mounted) return;
        ToastHost.show(
            context,
            l.xRuleCreatedShort +
                (r.ids.isNotEmpty ? l.xUpdatedMore('${r.ids.length}') : ''),
            undoLabel: l.cancelUndo, undo: () async {
          await repo.deleteRule(r.ruleId);
          await repo.updateMany([tx.id, ...r.ids],
              const TransactionsCompanion(categoryId: Value(null)));
        });
      }
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 8),
          child: Center(
            child: Text(l.xSortLeft('${queue.length}'),
                style: TextStyle(
                    color: t.ink2,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .4)),
          ),
        ),
        if (_aiConfigured)
          Btn(
              _aiRunning ? l.aiRunning : '${l.aiSort} (${queue.length})',
              kind: 'ghost', onTap: _aiRunning ? null : () async {
            setState(() => _aiRunning = true);
            try {
              // local reimplementation of the worker's /ai-categorize
              final r = await ref.read(aiServiceProvider).run();
              if (context.mounted) {
                ToastHost.show(
                    context, '${l.aiDone}: ${r.updated} · ${r.rules}');
              }
            } catch (e) {
              if (context.mounted) ToastHost.show(context, '${l.aiErr}: $e');
            } finally {
              if (mounted) setState(() => _aiRunning = false);
            }
          }),
        // helper card
        AppCard(
          padding: const EdgeInsets.all(20),
          margin: const EdgeInsets.only(bottom: 14),
          child: m.Column(children: [
            Text(tx.description.isNotEmpty ? tx.description : l.xNoDesc,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 17, color: t.ink)),
            const SizedBox(height: 8),
            Text('${sign < 0 ? '−' : '+'}${money.fmt(tx.amount.abs())}',
                style: TextStyle(
                    fontFamily: 'Unbounded',
                    fontSize: 26,
                    color: sign < 0 ? t.ink : t.income)),
            const SizedBox(height: 3),
            Text(
                '${fmtDayMonth(tx.time, locale)}${tx.mcc != null && tx.mcc != 0 ? ' · MCC ${tx.mcc}' : ''} · ${acc?.cardName ?? ''}',
                style: TextStyle(
                    color: t.ink3,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ]),
        ),
        if (tx.description.isNotEmpty)
          Press(
            onTap: () => setState(() => _makeRule = !_makeRule),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 20,
                  height: 20,
                  margin: const EdgeInsets.only(top: 2),
                  decoration: BoxDecoration(
                    color: _makeRule ? t.accent : Colors.transparent,
                    border:
                        Border.all(color: _makeRule ? t.accent : t.ink3),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: _makeRule
                      ? Icon(Icons.check, size: 15, color: t.accentInk)
                      : null,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                      l.xSortRule(
                          tx.description,
                          tx.mcc != null && tx.mcc != 0
                              ? ' + MCC ${tx.mcc}'
                              : ''),
                      style: TextStyle(fontSize: 13.5, color: t.ink2)),
                ),
              ]),
            ),
          ),
        // category grid
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.35,
          children: [
            for (final c in gridCats)
              Press(
                onTap: () => assign(c.id),
                child: Container(
                  decoration: BoxDecoration(
                      color: t.surface2,
                      border: Border.all(color: t.line),
                      borderRadius: BorderRadius.circular(13)),
                  child: m.Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(c.emoji, style: const TextStyle(fontSize: 21)),
                        const SizedBox(height: 5),
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 6),
                          child: Text(c.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: t.ink)),
                        ),
                      ]),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: Btn(l.xSkip, kind: 'ghost', margin: EdgeInsets.zero,
                onTap: () {
              ui.skip.add(tx.id);
              ui.bump();
            }),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: sign > 0
                ? Btn(l.xReimbBtn, kind: 'ghost', margin: EdgeInsets.zero,
                    onTap: () => showReimbSheet(context, ref, tx))
                : Btn(l.xInternalBtn, kind: 'ghost', margin: EdgeInsets.zero,
                    onTap: () async {
                    await repo.updateFields(tx.id,
                        const TransactionsCompanion(internal: Value(true)));
                    haptic();
                    if (!context.mounted) return;
                    ToastHost.show(context, l.xMarkedInternal,
                        undoLabel: l.cancelUndo,
                        undo: () => repo.updateFields(
                            tx.id,
                            const TransactionsCompanion(
                                internal: Value(false))));
                  }),
          ),
        ]),
        Btn(l.xExit, kind: 'ghost', margin: const EdgeInsets.only(top: 10),
            onTap: () {
          ui.skip.clear();
          ui.setTab('home');
        }),
      ],
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
