import 'package:flutter/material.dart' hide Column;
import 'package:flutter/material.dart' as m show Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/haptics.dart';
import '../../l10n/app_localizations.dart';
import '../../state.dart';
import '../screens/stats_screen.dart';
import '../widgets/common.dart';

/// statsWidgetSheet() — drag to reorder, toggle to hide analytics widgets.
Future<void> showWidgetsSheet(BuildContext context, WidgetRef ref) async {
  final l = L.of(context);
  final db = ref.read(dbProvider);
  final settings = settingsOf(ref);
  final wcfg = settings['stats_widgets'];
  final order = <String>[
    ...((wcfg is Map ? (wcfg['order'] as List?) : null)?.cast<String>() ?? [])
        .where(kStatWidgetsDefault.contains),
    ...kStatWidgetsDefault.where((k) =>
        !(((wcfg is Map ? (wcfg['order'] as List?) : null)?.cast<String>() ??
                [])
            .contains(k))),
  ];
  final hidden = statHidden(wcfg); // 'periods' hidden until user enables it

  String nameOf(String k) => switch (k) {
        'summary' => l.xWSummary,
        'cashflow' => l.xWCashflow,
        'week' => l.xWWeek,
        'compare' => l.xWCompareFull,
        'categories' => l.xWCategories,
        'cashback' => l.xWCashbackFull,
        'merchants' => l.xWMerchantsFull,
        'subs' => l.xWSubsFull,
        'install' => l.xWInstall,
        'planned' => l.xWPlanned,
        _ => l.xWPeriods,
      };
  String emojiOf(String k) => switch (k) {
        'summary' => '📊',
        'cashflow' => '📈',
        'week' => '📅',
        'compare' => '⚖️',
        'categories' => '🍩',
        'cashback' => '🪙',
        'merchants' => '🏪',
        'subs' => '🔁',
        'install' => '💳',
        'planned' => '📌',
        _ => '🧮',
      };

  await showAppSheet(
    context,
    StatefulBuilder(builder: (context, setState) {
      final t = tk(context);
      return m.Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetTitle(l.widgets),
            SheetMeta(l.widgetsHint),
            SizedBox(
              height: (order.length * 62).toDouble(),
              child: ReorderableListView.builder(
                buildDefaultDragHandles: false,
                physics: const NeverScrollableScrollPhysics(),
                proxyDecorator: (child, index, animation) => AnimatedBuilder(
                  animation: animation,
                  builder: (_, __) => Transform.scale(
                    scale: 1 + .02 * animation.value,
                    child: Material(
                      color: Colors.transparent,
                      elevation: 12 * animation.value,
                      borderRadius: BorderRadius.circular(14),
                      shadowColor: Colors.black.withValues(alpha: .4),
                      child: child,
                    ),
                  ),
                ),
                itemCount: order.length,
                onReorder: (o, n) {
                  haptic(HapticKind.shift);
                  setState(() {
                    if (n > o) n--;
                    order.insert(n, order.removeAt(o));
                  });
                },
                itemBuilder: (context, i) {
                  final k = order[i];
                  return Container(
                    key: ValueKey(k),
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                        color: t.surface2,
                        border: Border.all(color: t.line),
                        borderRadius: BorderRadius.circular(14)),
                    child: Row(children: [
                      ReorderableDragStartListener(
                        index: i,
                        child: Icon(Icons.drag_indicator_rounded,
                            size: 18, color: t.ink3),
                      ),
                      const SizedBox(width: 11),
                      EmTile(emojiOf(k), size: 34, fontSize: 17, radius: 11),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Text(nameOf(k),
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: t.ink)),
                      ),
                      Tgl(
                          on: !hidden.contains(k),
                          onTap: () => setState(() => hidden.contains(k)
                              ? hidden.remove(k)
                              : hidden.add(k))),
                    ]),
                  );
                },
              ),
            ),
            Btn(l.save, onTap: () async {
              await db.setSetting('stats_widgets',
                  {'order': order, 'hidden': hidden.toList()});
              if (context.mounted) Navigator.pop(context);
            }),
          ]);
    }),
  );
}
