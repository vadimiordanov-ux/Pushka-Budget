import 'package:flutter/material.dart' hide Column;
import 'package:flutter/material.dart' as m show Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/months.dart';
import '../../core/period.dart';
import '../../l10n/app_localizations.dart';
import '../../state.dart';
import '../util.dart';
import '../widgets/common.dart';

/// pickerSheet() — month-grid period picker with year nav; future disabled.
Future<void> showPeriodPickerSheet(BuildContext context, WidgetRef ref) async {
  final l = L.of(context);
  final ui = ref.read(uiProvider);
  final settings = settingsOf(ref);
  final locale = localeOf(settings);
  final mode = settings['period_mode'] as String? ?? 'salary';
  final day = int.tryParse('${settings['period_start_day'] ?? 22}') ?? 22;

  final cur = currentPeriod(mode: mode, startDay: day, offset: ui.offset);
  final p0 = currentPeriod(mode: mode, startDay: day, offset: 0);
  var vy = cur.start.year;

  await showAppSheet(
    context,
    StatefulBuilder(builder: (context, setState) {
      final t = tk(context);
      final monFull = monthsFull(locale);
      return m.Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetTitle(l.xPickPeriod),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _Nav(icon: Icons.chevron_left_rounded,
                        onTap: () => setState(() => vy--)),
                    Text('$vy',
                        style: TextStyle(
                            fontFamily: 'Unbounded',
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: t.ink)),
                    _Nav(icon: Icons.chevron_right_rounded,
                        onTap: () => setState(() => vy++)),
                  ]),
            ),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 3,
              mainAxisSpacing: 9,
              crossAxisSpacing: 9,
              childAspectRatio: 2.2,
              children: [
                for (var mo = 0; mo < 12; mo++)
                  Builder(builder: (_) {
                    final dt = DateTime(vy, mo + 1, mode == 'month' ? 1 : day);
                    final ps = mode == 'month'
                        ? DateTime(vy, mo + 1, 1)
                        : periodStart(dt, day);
                    final off = (ps.year - p0.start.year) * 12 +
                        (ps.month - p0.start.month);
                    final inCur = ps.year == cur.start.year &&
                        ps.month == cur.start.month;
                    final future = off > 0;
                    return Press(
                      onTap: () {
                        if (future) {
                          ToastHost.show(context, l.xFuturePeriod);
                          return;
                        }
                        ui.offset = off;
                        ui.bump();
                        Navigator.pop(context);
                      },
                      child: Opacity(
                        opacity: future ? .35 : 1,
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            gradient: inCur ? t.gradient : null,
                            color: inCur ? null : t.surface2,
                            border: Border.all(
                                color: inCur ? Colors.transparent : t.line),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(monFull[mo].substring(0, 3),
                              style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: inCur ? t.accentInk : t.ink2)),
                        ),
                      ),
                    );
                  }),
              ],
            ),
            if (mode == 'salary')
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(children: [
                  Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                          gradient: t.gradient,
                          borderRadius: BorderRadius.circular(4))),
                  const SizedBox(width: 7),
                  Expanded(
                      child: Text(l.xPeriodNote('$day', '${day - 1}'),
                          style: TextStyle(fontSize: 11, color: t.ink3))),
                ]),
              ),
            const SizedBox(height: 12),
            Btn(l.periodSetup, kind: 'ghost', onTap: () {
              Navigator.pop(context);
              showPeriodSetupSheet(context, ref);
            }),
          ]);
    }),
  );
}

class _Nav extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _Nav({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final t = tk(context);
    return Press(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
            color: t.surface2,
            border: Border.all(color: t.line),
            borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, size: 19, color: t.ink),
      ),
    );
  }
}

/// periodSheet() — salary vs calendar-month mode, start day 1–28.
Future<void> showPeriodSetupSheet(BuildContext context, WidgetRef ref) async {
  final l = L.of(context);
  final db = ref.read(dbProvider);
  final ui = ref.read(uiProvider);
  final settings = settingsOf(ref);
  var mode = settings['period_mode'] as String? ?? 'salary';
  final dayCtl = TextEditingController(
      text: '${settings['period_start_day'] ?? 22}');

  await showAppSheet(
    context,
    StatefulBuilder(builder: (context, setState) {
      final t = tk(context);
      return m.Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetTitle(l.periodSetup),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Seg(
                items: [
                  ('salary', l.periodSalary),
                  ('month', l.periodMonth)
                ],
                value: mode,
                onChanged: (v) => setState(() => mode = v),
              ),
            ),
            if (mode != 'month')
              Fld(l.periodStart,
                  child: AppInput(
                      controller: dayCtl,
                      keyboardType: TextInputType.number)),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(l.periodHint,
                  style: TextStyle(color: t.ink2, fontSize: 13, height: 1.5)),
            ),
            Btn(l.save, onTap: () async {
              final day =
                  (int.tryParse(dayCtl.text) ?? 22).clamp(1, 28);
              await db.setSetting('period_mode', mode);
              await db.setSetting('period_start_day', day);
              ui.offset = 0;
              ui.bump();
              if (context.mounted) Navigator.pop(context);
            }),
          ]);
    }),
  );
}
