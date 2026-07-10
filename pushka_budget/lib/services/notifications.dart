import 'dart:ui' show Locale;

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/money.dart';
import '../core/period.dart';
import '../core/plans.dart';
import '../data/db/database.dart';
import '../data/repos/repos.dart';
import '../l10n/app_localizations.dart';

/// Local replacement for the budget-notify Cloudflare worker.
/// Triggers, texts, thresholds and dedup keys VERIFIED against the deployed
/// worker source (2026-07-10):
///   /on-tx  → big transaction (skip internal/split, amount ≤ −big×100)
///           → category limit 80%/100% for the incoming tx's category,
///             spent = raw sum of negative non-internal txs in period
///   cron 06:00 UTC (09:00 Київ)
///           → planned payment tomorrow (day clamped to month length)
///           → period summary on the last period day
/// The worker's notify_log table becomes 'notified_marks' in settings.
///
/// FLAGGED improvements over the worker (kept deliberately):
///   • cadence plans (week/quarter/half/year) also remind a day before —
///     the worker only handled monthly `day`;
///   • installment due dates also remind a day before.
class NotificationsService {
  final AppDb db;
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _inited = false;

  NotificationsService(this.db);

  Future<void> init() async {
    if (_inited) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings();
    await _plugin.initialize(
        const InitializationSettings(android: android, iOS: darwin));
    _inited = true;
  }

  Future<bool> requestPermission() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final granted = await android?.requestNotificationsPermission();
    return granted ?? true;
  }

  Future<void> _show(int id, String title, String body, {String? tag}) async {
    await init();
    await _plugin.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'budget', 'Бюджет',
          channelDescription: 'Транзакції, ліміти, планові платежі',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          tag: tag,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }

  Future<Map<String, dynamic>> _prefs() async {
    final s = await db.getSetting('notify_prefs');
    return {
      'big': 1000,
      'big_on': true,
      'lim': true,
      'plan': true,
      'sum': true,
      if (s is Map) ...s.cast<String, dynamic>(),
    };
  }

  Future<bool> _enabled() async =>
      (await db.getSetting('push_enabled')) == true;

  /// once(key) — worker's notify_log INSERT-or-conflict, kept in settings.
  Future<bool> _once(String mark) async {
    final marks = await db.getSetting('notified_marks');
    final m =
        marks is Map ? Map<String, dynamic>.from(marks) : <String, dynamic>{};
    if (m[mark] == true) return false;
    m[mark] = true;
    if (m.length > 400) {
      final keys = m.keys.toList()..sort();
      for (final k in keys.take(m.length - 300)) {
        m.remove(k);
      }
    }
    await db.setSetting('notified_marks', m);
    return true;
  }

  /// Evaluate all triggers. [newTxs] — rows inserted by the poll that just ran.
  Future<void> evaluateAfterSync(List<Transaction> newTxs) async {
    if (!await _enabled()) return;
    final prefs = await _prefs();
    final settings = await db.allSettings();
    final money = Money(); // ₴, uk-UA grouping — fmtGrn parity
    final l = lookupL(Locale(settings['locale'] as String? ?? 'uk'));

    final mode = settings['period_mode'] as String? ?? 'salary';
    final startDay =
        int.tryParse('${settings['period_start_day'] ?? 22}') ?? 22;
    final period = currentPeriod(mode: mode, startDay: startDay);
    final periodKey = period.start.toIso8601String().substring(0, 10);

    // -- 1. big transaction (worker /on-tx §1) --------------------------------
    if (prefs['big_on'] == true) {
      final thr = ((prefs['big'] as num?) ?? 1000).toInt() * 100;
      for (final t in newTxs) {
        if (t.internal || t.parentId != null) continue; // worker skip
        if (t.amount > -thr) continue; // amount <= -big*100
        if (await _once('big:${t.id}')) {
          await _show(
            t.id.hashCode & 0x7fffffff,
            '−${money.fmt(-t.amount)}',
            '${t.description.isEmpty ? l.ntfBigFallback : t.description}'
                '${t.mcc != null && t.mcc != 0 ? ' · MCC ${t.mcc}' : ''}',
            tag: 'big-tx',
          );
        }
      }
    }

    // -- 2. category limit 80% / 100% (worker /on-tx §2) ----------------------
    // Worker checked only the incoming tx's category; spent = raw sum of
    // negative non-internal txs in the period (no split/reimburse netting).
    if (prefs['lim'] == true) {
      final touched = newTxs
          .where((t) => t.amount < 0 && !t.internal && t.categoryId != null)
          .map((t) => t.categoryId!)
          .toSet();
      if (touched.isNotEmpty) {
        final cats = await CatRepo(db).all();
        final periodTxs = await TxRepo(db).period(period);
        for (final cid in touched) {
          final cat = cats.where((c) => c.id == cid).firstOrNull;
          final lim = cat?.limitKop;
          if (cat == null || lim == null || lim <= 0) continue;
          var spent = 0;
          for (final t in periodTxs) {
            if (t.categoryId == cid && !t.internal && t.amount < 0) {
              spent -= t.amount;
            }
          }
          final pct = (100 * spent / lim).round();
          final catLabel = '${cat.emoji} ${cat.name}';
          final body = l.ntfLimitBody(money.fmt(spent), money.fmt(lim), '$pct');
          if (pct >= 100 && await _once('lim100:$cid:$periodKey')) {
            await _show(('l1$cid').hashCode & 0x7fffffff,
                l.ntfLimitOverTitle(catLabel), body,
                tag: 'lim-$cid');
          } else if (pct >= 80 &&
              pct < 100 &&
              await _once('lim80:$cid:$periodKey')) {
            await _show(('l8$cid').hashCode & 0x7fffffff,
                l.ntfLimitNearTitle(catLabel), body,
                tag: 'lim-$cid');
          }
        }
      }
    }

    // -- cron-equivalent triggers fire from 09:00 local (worker: 09:00 Київ) --
    final now = DateTime.now();
    if (now.hour < 9) return;
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    // -- 3. planned payment tomorrow (worker cron §1) -------------------------
    if (prefs['plan'] == true) {
      final plans = await PlannedRepo(db).all();
      // worker logic: monthly day clamped to the target month's length
      final lastDayOfMonth =
          DateTime(tomorrow.year, tomorrow.month + 1, 0).day;
      for (final p in plans) {
        if (!p.active || !p.notify) continue;
        final meta = planMeta(settings, p.id);
        bool due;
        if (meta.p == 'month') {
          final effDay =
              p.day > lastDayOfMonth ? lastDayOfMonth : p.day;
          due = effDay == tomorrow.day;
        } else {
          // FLAGGED improvement: cadence plans remind too
          due = planOccurrences(p, period, settings)
              .any((d) => d == tomorrow);
        }
        if (!due) continue;
        final mark =
            'plan:${p.id}:${tomorrow.toIso8601String().substring(0, 10)}';
        if (await _once(mark)) {
          await _show(
            mark.hashCode & 0x7fffffff,
            l.ntfPlanTitle(p.name),
            l.ntfPlanBody(money.fmt(p.amountKop),
                p.note?.isNotEmpty == true ? ' · ${p.note}' : ''),
            tag: 'plan-${p.id}',
          );
        }
      }
      // FLAGGED improvement: installment dues remind a day before
      for (final i in await InstRepo(db).all()) {
        if (i.archived || i.monthsPaid >= i.monthsTotal) continue;
        if (instNextDue(i) != tomorrow) continue;
        final mark =
            'plan:inst:${i.id}:${tomorrow.toIso8601String().substring(0, 10)}';
        if (await _once(mark)) {
          await _show(
            mark.hashCode & 0x7fffffff,
            l.ntfPlanTitle(i.name),
            l.ntfPlanBody(money.fmt(instMonthly(i)),
                i.bank.isNotEmpty ? ' · ${i.bank}' : ''),
            tag: 'plan-${i.id}',
          );
        }
      }
    }

    // -- 4. period summary on the last day (worker cron §2) -------------------
    if (prefs['sum'] == true) {
      final lastDay = period.end.subtract(const Duration(days: 1));
      if (today == DateTime(lastDay.year, lastDay.month, lastDay.day) &&
          await _once('sum:$periodKey')) {
        // worker formula: internal excluded, reimbursing incomes skipped,
        // otherwise raw sums (NO split netting — deliberate worker parity)
        final rows = await (db.select(db.transactions)
              ..where((t) =>
                  t.internal.equals(false) &
                  t.time.isBiggerOrEqualValue(period.start) &
                  t.time.isSmallerThanValue(period.end))
              ..orderBy([(t) => OrderingTerm.asc(t.time)]))
            .get();
        var exp = 0, inc = 0;
        for (final r in rows) {
          if (r.amount > 0 && r.reimburses != null) continue;
          if (r.amount < 0) {
            exp -= r.amount;
          } else {
            inc += r.amount;
          }
        }
        await _show(
          ('sum$periodKey').hashCode & 0x7fffffff,
          l.ntfSummaryTitle,
          l.ntfSummaryBody(
              money.fmt(exp), money.fmt(inc), money.fmt(inc - exp)),
          tag: 'summary',
        );
      }
    }
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
