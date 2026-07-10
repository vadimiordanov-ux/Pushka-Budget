import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui_img;

import 'package:flutter/material.dart' hide Column;
import 'package:flutter/material.dart' as m show Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/haptics.dart';
import '../../core/money.dart';
import '../../core/period.dart';
import '../../core/tokens.dart';
import '../../data/db/database.dart';
import '../../data/repos/analytics.dart';
import '../../l10n/app_localizations.dart';
import '../../state.dart';
import '../sheets/period_picker_sheet.dart';
import '../util.dart';
import '../widgets/common.dart';
import 'lock_screen.dart';
import 'onboarding.dart';

/// More «Ще» — port of renderMore(): profile card + accordion cards.
class MoreScreen extends ConsumerStatefulWidget {
  const MoreScreen({super.key});
  @override
  ConsumerState<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends ConsumerState<MoreScreen> {
  @override
  Widget build(BuildContext context) {
    final t = tk(context);
    final l = L.of(context);
    final ui = ref.watch(uiProvider);
    final settings = settingsOf(ref);
    final db = ref.read(dbProvider);
    final money = ref.watch(moneyProvider);
    final open = ui.moreOpen;

    final name = settings['display_name'] as String? ?? 'Ви';
    final letter = (name.isNotEmpty ? name[0] : 'В').toUpperCase();
    final avatar = settings['avatar_url'] as String?;

    void toggle(String id) {
      haptic();
      ui.moreOpen = ui.moreOpen == id ? null : id;
      ui.bump();
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 120),
      children: [
        // ---- profile card ----
        Enter(
          index: 0,
          child: AppCard(
            margin: const EdgeInsets.only(bottom: 20),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            child: Row(children: [
              Press(
                onTap: _pickAvatar,
                child: Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: avatar == null ? t.gradient : null,
                    image: avatar != null
                        ? DecorationImage(
                            image: MemoryImage(base64Decode(
                                avatar.split(',').last)),
                            fit: BoxFit.cover)
                        : null,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: t.glow, blurRadius: 16)],
                  ),
                  child: avatar == null
                      ? Text(letter,
                          style: TextStyle(
                              fontFamily: 'Unbounded',
                              fontSize: 21,
                              fontWeight: FontWeight.w700,
                              color: t.accentInk))
                      : null,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: m.Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: t.ink)),
                    ]),
              ),
              Press(
                onTap: _editProfile,
                child: Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                      color: t.surface2,
                      border: Border.all(color: t.line),
                      borderRadius: BorderRadius.circular(12)),
                  child: Icon(Icons.edit_rounded, size: 19, color: t.ink3),
                ),
              ),
            ]),
          ),
        ),
        _MCard(
            id: 'look',
            icon: Icons.palette_rounded,
            title: l.xLook,
            open: open,
            onToggle: toggle,
            body: _lookBody(settings, db, l)),
        _MCard(
            id: 'lang',
            icon: Icons.translate_rounded,
            title: l.secLang,
            open: open,
            onToggle: toggle,
            body: _langBody(settings, db, l)),
        _MCard(
            id: 'notif',
            icon: Icons.notifications_rounded,
            title: l.notif,
            open: open,
            onToggle: toggle,
            body: _notifBody(settings, db, l, money)),
        _MCard(
            id: 'security',
            icon: Icons.fingerprint_rounded,
            title: l.xSecurity,
            open: open,
            onToggle: toggle,
            body: _securityBody(settings, db, l)),
        _MCard(
            id: 'tokens',
            icon: Icons.vpn_key_rounded,
            title: l.xTokensTitle,
            open: open,
            onToggle: (_) => ui.setTab('tokens'),
            body: const SizedBox.shrink()),
        _MCard(
            id: 'sync',
            icon: Icons.sync_rounded,
            title: l.xSyncTitle,
            open: open,
            onToggle: (_) => ui.setTab('sync'),
            body: const SizedBox.shrink()),
        _MCard(
            id: 'inst',
            icon: Icons.credit_card_rounded,
            title: l.instTitle,
            open: open,
            onToggle: (_) => ui.setTab('inst'),
            body: const SizedBox.shrink()),
        _MCard(
            id: 'stat',
            icon: Icons.bar_chart_rounded,
            title: l.xPeriodStats,
            open: open,
            onToggle: toggle,
            body: _statBody(l, money)),
        _MCard(
            id: 'credit',
            icon: Icons.account_balance_rounded,
            title: l.xCreditLimitSec,
            open: open,
            onToggle: toggle,
            body: _creditBody(settings, db, l, money)),
        _MCard(
            id: 'data',
            icon: Icons.storage_rounded,
            title: l.xDataBackups,
            open: open,
            onToggle: toggle,
            body: _dataBody(l)),
        _MCard(
            id: 'support',
            icon: Icons.help_rounded,
            title: l.xSupport,
            open: open,
            onToggle: toggle,
            body: _supportBody(l, settings, db)),
        _MCard(
            id: 'about',
            icon: Icons.info_rounded,
            title: l.xAbout,
            open: open,
            onToggle: toggle,
            body: _aboutBody(l)),
        // «Стерти всі дані» lives inside the About card (user's choice) —
        // no standalone destructive button next to everyday settings.
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Center(
            child: Text('Бюджет · v4.0.0 · Flutter',
                style: TextStyle(color: t.ink3, fontSize: 12)),
          ),
        ),
      ],
    );
  }

  // ================= sections =================

  Widget _lookBody(Map<String, dynamic> s, AppDb db, L l) {
    final t = tk(context);
    final skin = s['skin'] == 'basic' ? 'basic' : 'aurora';
    final theme = s['theme'] as String? ?? 'auto';
    final donut =
        const ['A', 'B', 'C'].contains(s['donut']) ? s['donut'] as String : 'A';
    final cfg = chartCfg(s);

    Widget skinCard(String id, String label, List<Color> grad, Color darkSw) {
      final on = skin == id;
      return Expanded(
        child: Press(
          onTap: () => db.setSetting('skin', id),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: t.surface2,
                border: Border.all(
                    color: on ? t.accent : t.line, width: 1.5),
                borderRadius: BorderRadius.circular(15)),
            child:
                m.Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Row(children: [
                  Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                          gradient: LinearGradient(colors: grad),
                          borderRadius: BorderRadius.circular(7))),
                  const SizedBox(width: 5),
                  Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                          color: darkSw,
                          border: Border.all(
                              color: Colors.white.withValues(alpha: .12)),
                          borderRadius: BorderRadius.circular(7))),
                ]),
                Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: on ? t.accent : Colors.transparent,
                      border: Border.all(
                          color: on ? t.accent : t.line, width: 1.5),
                      shape: BoxShape.circle),
                  child: on
                      ? Icon(Icons.check, size: 12, color: t.accentInk)
                      : null,
                ),
              ]),
              const SizedBox(height: 11),
              Text(label,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: t.ink)),
            ]),
          ),
        ),
      );
    }

    return m.Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _MLbl(l.xAppTheme),
      Row(children: [
        skinCard('aurora', 'Aurora',
            [const Color(0xFFFF9A3D), const Color(0xFFF5511E)],
            const Color(0xFF1A1613)),
        const SizedBox(width: 11),
        skinCard('basic', l.xClassic,
            [const Color(0xFFFFC94B), const Color(0xFFFF8A3C)],
            const Color(0xFF151823)),
      ]),
      const _MDiv(),
      _MLbl(l.xMode),
      Seg(
          items: [('light', l.light), ('dark', l.dark), ('auto', l.auto)],
          value: theme,
          onChanged: (v) => db.setSetting('theme', v)),
      const _MDiv(),
      _MLbl(l.xChartLook),
      Seg(
          items: [('A', l.xRing), ('B', l.xThin), ('C', l.xSegments)],
          value: donut,
          onChanged: (v) async {
            await db.setSetting('donut', v);
            if (mounted) ToastHost.show(context, l.xSavedSeeHome);
          }),
      const _MDiv(),
      _MLbl(l.xChartPalette),
      GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 3.4,
        children: [
          for (final (i, nm) in [
            l.xPal0, l.xPal1, l.xPal2, l.xPal3, l.xPal4, l.xPal5
          ].indexed)
            Press(
              onTap: () async {
                haptic();
                await db.setSetting('chart',
                    {'type': cfg.type, 'palette': i});
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
                decoration: BoxDecoration(
                    color: t.surface2,
                    border: Border.all(
                        color: cfg.palette == i ? t.accent : t.line,
                        width: 1.5),
                    borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  for (final c in kPalettes[i].take(4))
                    Container(
                        width: 12,
                        height: 12,
                        margin: const EdgeInsets.only(right: 2),
                        decoration: BoxDecoration(
                            color: c,
                            borderRadius: BorderRadius.circular(4))),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(nm,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: t.ink)),
                  ),
                  if (cfg.palette == i)
                    Icon(Icons.check, size: 16, color: t.accent),
                ]),
              ),
            ),
        ],
      ),
    ]);
  }

  Widget _langBody(Map<String, dynamic> s, AppDb db, L l) {
    final locale = s['locale'] as String? ?? 'uk';
    final currency = s['currency'] as String? ?? 'UAH';
    const flags = {
      'uk': '🇺🇦', 'en': '🇬🇧', 'de': '🇩🇪', 'fr': '🇫🇷', 'es': '🇪🇸',
      'it': '🇮🇹', 'nl': '🇳🇱', 'pl': '🇵🇱', 'zh': '🇨🇳', 'ja': '🇯🇵',
    };
    const names = {
      'uk': 'Українська', 'en': 'English', 'de': 'Deutsch', 'fr': 'Français',
      'es': 'Español', 'it': 'Italiano', 'nl': 'Nederlands', 'pl': 'Polski',
      'zh': '中文', 'ja': '日本語',
    };
    final mode = s['period_mode'] as String? ?? 'salary';
    final day = int.tryParse('${s['period_start_day'] ?? 22}') ?? 22;
    final t = tk(context);

    return m.Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _MLbl(l.language),
      Wrap(spacing: 7, runSpacing: 7, children: [
        for (final e in names.entries)
          ChipBtn('${flags[e.key]} ${e.value}', on: locale == e.key,
              onTap: () => db.setSetting('locale', e.key)),
      ]),
      const _MDiv(),
      Row(children: [
        Expanded(child: _MLbl(l.currency)),
        Flexible(
          child: Text(l.currencyNote,
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 11.5, color: t.ink3)),
        ),
      ]),
      const SizedBox(height: 4),
      Wrap(spacing: 7, runSpacing: 7, children: [
        for (final e in kCurrencies.entries)
          ChipBtn(e.value.symbol, on: currency == e.key,
              onTap: () => db.setSetting('currency', e.key)),
      ]),
      const _MDiv(),
      Btn(
          '${l.periodSetup}: ${mode == 'month' ? l.periodMonth : '${l.periodSalary} · $day'}',
          kind: 'ghost',
          onTap: () => showPeriodSetupSheet(context, ref)),
    ]);
  }

  Widget _notifBody(Map<String, dynamic> s, AppDb db, L l, Money money) {
    final t = tk(context);
    final prefs = {
      'big': 1000, 'big_on': true, 'lim': true, 'plan': true, 'sum': true,
      ...?(s['notify_prefs'] as Map?)?.cast<String, dynamic>(),
    };
    final enabled = s['push_enabled'] == true;
    final currency = s['currency'] as String? ?? 'UAH';
    final thr = const {
          'UAH': [500, 1000, 2000, 5000],
          'USD': [50, 100, 200, 500],
          'EUR': [50, 100, 200, 500],
          'GBP': [50, 100, 200, 500],
          'PLN': [200, 500, 1000, 2000],
        }[currency] ??
        const [500, 1000, 2000, 5000];
    final sym = kCurrencies[currency]?.symbol ?? '₴';

    Future<void> savePrefs(Map<String, dynamic> patch) =>
        db.setSetting('notify_prefs', {...prefs, ...patch});

    return m.Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _NRow(
          label: l.xPushNotifs,
          sub: enabled ? '● ${l.notifActive}' : null,
          subColor: t.income,
          on: enabled,
          onTap: () async {
            if (!enabled) {
              final ok =
                  await ref.read(notificationsProvider).requestPermission();
              if (!ok && mounted) {
                ToastHost.show(context, l.notifDenied);
                return;
              }
            }
            await db.setSetting('push_enabled', !enabled);
          }),
      _NRow(
          label: l.notifBig,
          on: prefs['big_on'] == true,
          onTap: () => savePrefs({'big_on': !(prefs['big_on'] == true)})),
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(l.xNotifyWhenAbove,
            style: TextStyle(fontSize: 11.5, color: t.ink3)),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Wrap(spacing: 7, runSpacing: 7, children: [
          for (final v in thr)
            ChipBtn('$v $sym', on: prefs['big'] == v,
                onTap: () => savePrefs({'big': v})),
        ]),
      ),
      _NRow(
          label: l.notifLim,
          on: prefs['lim'] == true,
          onTap: () => savePrefs({'lim': !(prefs['lim'] == true)})),
      _NRow(
          label: l.notifPlan,
          on: prefs['plan'] == true,
          onTap: () => savePrefs({'plan': !(prefs['plan'] == true)})),
      _NRow(
          label: l.notifSum,
          on: prefs['sum'] == true,
          last: true,
          onTap: () => savePrefs({'sum': !(prefs['sum'] == true)})),
      // reliability of the 15-min WorkManager cycle on aggressive OEMs:
      // ask the system to exempt us from battery optimization
      Press(
        onTap: () async {
          haptic();
          await Permission.ignoreBatteryOptimizations.request();
        },
        child: Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: t.surface2,
              border: Border.all(color: t.line),
              borderRadius: BorderRadius.circular(13)),
          child: Row(children: [
            Icon(Icons.battery_saver_rounded, size: 20, color: t.accent),
            const SizedBox(width: 11),
            Expanded(
              child: m.Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.xBatteryTitle,
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: t.ink)),
                    Text(l.xBatterySub,
                        style:
                            TextStyle(fontSize: 11.5, color: t.ink3)),
                  ]),
            ),
            Icon(Icons.chevron_right_rounded, size: 20, color: t.ink3),
          ]),
        ),
      ),
    ]);
  }

  Widget _securityBody(Map<String, dynamic> s, AppDb db, L l) {
    final t = tk(context);
    final lock = ref.read(lockServiceProvider);
    final lockOn = s['app_lock'] == true;
    final curTimeout = int.tryParse('${s['applock_timeout'] ?? 0}') ?? 0;

    return m.Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _NRow(
          label: l.xAppLock,
          sub: l.xLockSub(l.xLockBioOrPin),
          on: lockOn,
          last: !lockOn,
          onTap: () async {
            haptic();
            if (!lockOn) {
              final bioAvail = await lock.bioAvailable();
              if (!mounted) return;
              String? choice = 'pin';
              if (bioAvail) {
                choice = await showLockModeChoice(context, l);
                if (choice == null) return;
              }
              if (choice == 'bio') {
                if (!await lock.enrollBio()) {
                  if (mounted) ToastHost.show(context, l.xBioFail);
                  return;
                }
              } else {
                if (!mounted) return;
                final done = await showPinSetupFlow(context, ref);
                if (!done) return;
                if (bioAvail) await lock.enrollBio();
              }
              await db.setSetting('app_lock', true);
              if (mounted) {
                ToastHost.show(
                    context, choice == 'bio' ? l.xLockOnBio : l.xLockOn);
              }
            } else {
              await lock.disable();
              if (mounted) ToastHost.show(context, l.xLockOff);
            }
          }),
      if (lockOn) ...[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: m.Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.xAutoLock,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: t.ink)),
                Text(l.xAutoLockSub,
                    style: TextStyle(fontSize: 11.5, color: t.ink3)),
                const SizedBox(height: 8),
                Wrap(spacing: 7, runSpacing: 7, children: [
                  for (final v in [0, 1, 5, 15])
                    ChipBtn(v == 0 ? l.xImmediately : l.xNMin('$v'),
                        on: curTimeout == v,
                        onTap: () => db.setSetting('applock_timeout', v)),
                ]),
              ]),
        ),
        Press(
          onTap: () async {
            haptic();
            final done = await showPinSetupFlow(context, ref);
            if (done && mounted) {
              ToastHost.show(context, l.xPinUpdated);
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(l.xChangePin,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: t.ink)),
                  Icon(Icons.chevron_right_rounded, color: t.ink2),
                ]),
          ),
        ),
      ],
    ]);
  }

  Widget _statBody(L l, Money money) {
    final t = tk(context);
    final txs = ref.watch(periodTxsProvider).value ?? const <Transaction>[];
    final cats = ref.watch(categoriesProvider).value ?? const <Category>[];
    final ui = ref.read(uiProvider);
    final settings = settingsOf(ref);
    final period = ref.watch(periodProvider);
    final s = sums(txs);
    final now = DateTime.now();
    final endMs = period.end.isBefore(now) ? period.end : now;
    final daysGone =
        (endMs.difference(period.start).inMilliseconds / 86400000)
            .ceil()
            .clamp(1, 1 << 31);
    final txCount =
        txs.where((x) => !x.internal && x.parentId == null).length;
    final topCheck = s.expVals.fold<int>(0, (a, v) => -v.val > a ? -v.val : a);
    final noCat = nocatQueue(txs, -1, ui.skip).length +
        nocatQueue(txs, 1, ui.skip).length;
    final perCat = byCategory(s.expVals);
    final topCat = perCat.isNotEmpty ? perCat.first : null;
    final topCatC = topCat?.key == null
        ? null
        : cats.where((c) => c.id == topCat!.key).firstOrNull;
    final dow = List.filled(7, 0);
    for (final v in s.expVals) {
      dow[(v.t.time.weekday - 1) % 7]++;
    }
    var maxDow = 0;
    for (var i = 1; i < 7; i++) {
      if (dow[i] > dow[maxDow]) maxDow = i;
    }
    // toLocaleDateString(weekday:'long') parity
    String dowName;
    try {
      dowName = DateFormat.EEEE(localeOf(settings))
          .format(DateTime(2024, 1, maxDow + 1));
    } catch (_) {
      const wd = [
        'понеділок', 'вівторок', 'середа', 'четвер', 'пʼятниця', 'субота',
        'неділя'
      ];
      dowName = wd[maxDow];
    }

    Widget tile(String v, String label, {Color? color}) => Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
              color: t.surface2,
              border: Border.all(color: t.line),
              borderRadius: BorderRadius.circular(14)),
          child:
              m.Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(v,
                style: TextStyle(
                    fontFamily: 'Unbounded',
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: color ?? t.ink)),
            const SizedBox(height: 3),
            Text(label, style: TextStyle(fontSize: 12, color: t.ink2)),
          ]),
        );

    Widget irow(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label, style: TextStyle(fontSize: 13, color: t.ink2)),
                Text(value,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: t.ink)),
              ]),
        );

    return m.Column(children: [
      GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 2.1,
        children: [
          tile('$txCount', l.xTxsLbl),
          tile(money.fmt((s.expTotal / daysGone).round()), l.xAvgPerDay),
          tile(money.fmt(topCheck), l.xBiggestCheck),
          tile('$noCat', l.xNoCatLower,
              color: noCat > 0 ? t.accent : t.ink),
        ],
      ),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
            color: t.surface2,
            border: Border.all(color: t.line),
            borderRadius: BorderRadius.circular(14)),
        child: m.Column(children: [
          irow('${topCatC != null ? '${topCatC.emoji} ' : ''}${l.xTopCategory}',
              topCatC != null ? '${topCatC.name} · ${money.fmt(topCat!.value)}' : '—'),
          Divider(height: 1, color: t.line),
          irow(l.xBusiestDay, txCount > 0 ? dowName : '—'),
          Divider(height: 1, color: t.line),
          irow(l.txsInPeriod, '${txs.length}'),
        ]),
      ),
    ]);
  }

  Widget _creditBody(Map<String, dynamic> s, AppDb db, L l, Money money) {
    final t = tk(context);
    final rows = (ref.watch(creditProvider).value ?? const <CreditRow>[])
        .where((r) => r.limitKop > 0)
        .toList();

    return m.Column(children: [
      _NRow(
          label: l.xShowOnHome,
          sub: l.xCreditCardSub,
          on: s['credit_hidden'] != true,
          last: rows.isEmpty,
          onTap: () =>
              db.setSetting('credit_hidden', !(s['credit_hidden'] == true))),
      if (rows.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(l.xCreditEmpty,
              style: TextStyle(fontSize: 11.5, color: t.ink3)),
        )
      else
        Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
              color: t.surface2,
              border: Border.all(color: t.line),
              borderRadius: BorderRadius.circular(14)),
          child: m.Column(children: [
            for (final (i, r) in rows.indexed) ...[
              if (i > 0) Divider(height: 1, color: t.line),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                          r.owner[0].toUpperCase() + r.owner.substring(1),
                          style:
                              TextStyle(fontSize: 13, color: t.ink2)),
                      Text.rich(TextSpan(children: [
                        TextSpan(
                            text: money.fmt((r.limitKop - r.usedKop)
                                .clamp(0, r.limitKop)),
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: t.ink)),
                        TextSpan(
                            text: ' / ${money.fmt(r.limitKop)}',
                            style: TextStyle(
                                fontSize: 13, color: t.ink3)),
                      ])),
                    ]),
              ),
            ],
          ]),
        ),
    ]);
  }

  Widget _dataBody(L l) {
    return m.Column(children: [
      _DRow(
          icon: Icons.ios_share_rounded,
          title: l.xCsvExportTitle,
          sub: l.xCsvSub,
          onTap: () async {
            final txs =
                ref.read(periodTxsProvider).value ?? const <Transaction>[];
            final cats =
                ref.read(categoriesProvider).value ?? const <Category>[];
            final accounts =
                ref.read(accountsProvider).value ?? const <Account>[];
            final settings = settingsOf(ref);
            final period = ref.read(periodProvider);
            await ref.read(backupServiceProvider).exportCsv(
                txs,
                periodLabel(period,
                    settings['period_mode'] as String? ?? 'salary',
                    localeOf(settings)),
                {for (final c in cats) c.id: c},
                {for (final a in accounts) a.id: a});
          }),
      _DRow(
          icon: Icons.cloud_download_rounded,
          title: l.xJsonBackup,
          sub: l.xJsonSub,
          onTap: () async {
            ToastHost.show(context, l.xPreparingCopy);
            await ref.read(backupServiceProvider).exportJson();
            if (mounted) ToastHost.show(context, l.xBackupSaved);
          }),
      _DRow(
          icon: Icons.file_download_rounded,
          title: l.xImport,
          sub: l.xImportSub,
          onTap: () async {
            final svc = ref.read(backupServiceProvider);
            final info = await svc.pickAndParse();
            if (!mounted) return;
            if (info == null) {
              ToastHost.show(context, l.xNoTxInFile);
              return;
            }
            final t = tk(context);
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: t.surface,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                content: Text(
                    l.xRestoreConfirm('${info.$1}',
                        info.$2?.substring(0, 10) ?? '—'),
                    style: TextStyle(color: t.ink, fontSize: 14.5)),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child:
                          Text(l.xCancel, style: TextStyle(color: t.ink2))),
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(l.apply,
                          style: TextStyle(
                              color: t.accent,
                              fontWeight: FontWeight.w700))),
                ],
              ),
            );
            if (ok != true || !mounted) return;
            try {
              final n = await svc.applyImport();
              if (mounted) ToastHost.show(context, l.xRestored('$n'));
            } catch (e) {
              if (mounted) ToastHost.show(context, l.xImportError('$e'));
            }
          }),
    ]);
  }

  Widget _supportBody(L l, Map<String, dynamic> s, AppDb db) {
    final t = tk(context);
    return m.Column(children: [
      _DRow(
          icon: Icons.mail_rounded,
          title: l.xContactSupport,
          sub: l.xContactSub,
          onTap: () => _supportSheet(l)),
      const SizedBox(height: 4),
      Row(children: [
        for (final (icon, label, onTap) in [
          (Icons.menu_book_rounded, l.xHelp, () async {
            await db.setSetting('onboarded', false);
          }),
          (Icons.forum_rounded, l.xCommunity,
              () => ToastHost.show(context, l.xCommunitySoon)),
          (Icons.star_rounded, l.xRate,
              () => ToastHost.show(context, l.xThanks)),
        ]) ...[
          Expanded(
            child: Press(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                    color: t.surface2,
                    border: Border.all(color: t.line),
                    borderRadius: BorderRadius.circular(13)),
                child: m.Column(children: [
                  Icon(icon, size: 22, color: t.accent),
                  const SizedBox(height: 5),
                  Text(label,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: t.ink)),
                ]),
              ),
            ),
          ),
          if (label != l.xRate) const SizedBox(width: 9),
        ],
      ]),
    ]);
  }

  Widget _aboutBody(L l) {
    final t = tk(context);
    Widget irow(String a, String b) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(a, style: TextStyle(fontSize: 13, color: t.ink2)),
                Text(b,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: t.ink)),
              ]),
        );
    return m.Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              gradient: t.gradient,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: t.glow, blurRadius: 16)]),
          child: const Text('💰', style: TextStyle(fontSize: 26)),
        ),
        const SizedBox(width: 13),
        m.Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l.xAppName,
              style: TextStyle(
                  fontFamily: 'Unbounded',
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: t.ink)),
          const SizedBox(height: 2),
          Text(l.xAboutSub,
              style: TextStyle(fontSize: 11.5, color: t.ink3)),
        ]),
      ]),
      const SizedBox(height: 13),
      Text(l.xAboutText,
          style: TextStyle(fontSize: 13, height: 1.55, color: t.ink2)),
      const SizedBox(height: 13),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
            color: t.surface2,
            border: Border.all(color: t.line),
            borderRadius: BorderRadius.circular(14)),
        child: m.Column(children: [
          irow(l.xVersion, '4.0.0'),
          Divider(height: 1, color: t.line),
          irow(l.xUpdated, 'Липень 2026'),
          Divider(height: 1, color: t.line),
          irow(l.xPlatform, 'Flutter · Android'),
        ]),
      ),
      const SizedBox(height: 13),
      // erase-all is tucked away here deliberately (destructive, rarely needed)
      Press(
        onTap: () => _eraseAll(l),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
              border: Border.all(
                  color: t.expense.withValues(alpha: .35)),
              borderRadius: BorderRadius.circular(13)),
          child: Center(
            child: Text(l.xEraseData,
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: t.expense)),
          ),
        ),
      ),
    ]);
  }

  // ================= actions =================

  Future<void> _pickAvatar() async {
    final l = L.of(context);
    try {
      final img = await ImagePicker()
          .pickImage(source: ImageSource.gallery, requestFullMetadata: false);
      if (img == null) return;
      // resizeAvatar(): center-crop square → 256×256 JPEG data URL
      final bytes = await img.readAsBytes();
      final codec = await ui_img.instantiateImageCodec(bytes,
          targetWidth: 256, targetHeight: 256);
      final frame = await codec.getNextFrame();
      final data =
          await frame.image.toByteData(format: ui_img.ImageByteFormat.png);
      if (data == null) throw Exception();
      final b64 = base64Encode(data.buffer.asUint8List());
      await ref
          .read(dbProvider)
          .setSetting('avatar_url', 'data:image/png;base64,$b64');
    } catch (_) {
      if (mounted) ToastHost.show(context, l.xPhotoFail);
    }
  }

  Future<void> _editProfile() async {
    final l = L.of(context);
    final db = ref.read(dbProvider);
    final settings = settingsOf(ref);
    final ctl = TextEditingController(
        text: settings['display_name'] as String? ?? '');
    await showAppSheet(
      context,
      m.Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetTitle(l.xProfile),
            Fld(l.xFirstName, child: AppInput(controller: ctl)),
            Btn(l.save, onTap: () async {
              await db.setSetting('display_name', ctl.text.trim());
              if (mounted && context.mounted) Navigator.pop(context);
            }),
          ]),
    );
  }

  Future<void> _supportSheet(L l) async {
    final subjCtl = TextEditingController();
    final msgCtl = TextEditingController();
    await showAppSheet(
      context,
      Builder(builder: (context) {
        final t = tk(context);
        return m.Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              SheetTitle(l.xSupportTitle),
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
                decoration: BoxDecoration(
                    color: t.surface2,
                    border: Border.all(color: t.line),
                    borderRadius: BorderRadius.circular(13)),
                child: Row(children: [
                  Icon(Icons.mail_rounded, size: 19, color: t.accent),
                  const SizedBox(width: 12),
                  m.Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.xTo,
                            style:
                                TextStyle(fontSize: 12, color: t.ink3)),
                        Text('vadim.iordanov@gmail.com',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: t.ink)),
                      ]),
                ]),
              ),
              Fld(l.xSubject,
                  child:
                      AppInput(controller: subjCtl, placeholder: l.xSubjectPh)),
              Fld(l.xMessage,
                  child: AppInput(
                      controller: msgCtl,
                      placeholder: l.xMessagePh,
                      maxLines: 4)),
              Btn(l.xSendMail,
                  leading:
                      Icon(Icons.send_rounded, size: 17, color: t.accentInk),
                  onTap: () async {
                final uri = Uri(
                    scheme: 'mailto',
                    path: 'vadim.iordanov@gmail.com',
                    query:
                        'subject=${Uri.encodeComponent(subjCtl.text.isEmpty ? 'Бюджет — питання' : subjCtl.text)}'
                        '&body=${Uri.encodeComponent('${msgCtl.text}\n\n—\nversion 4.0.0 · Flutter/Android')}');
                await launchUrl(uri);
                if (context.mounted) Navigator.pop(context);
              }),
            ]);
      }),
    );
  }

  Future<void> _eraseAll(L l) async {
    final t = tk(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Text(l.xEraseDataConfirm,
            style: TextStyle(color: t.ink, fontSize: 14.5)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.xCancel, style: TextStyle(color: t.ink2))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.xEraseData,
                  style: TextStyle(
                      color: t.expense, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (ok != true) return;
    final db = ref.read(dbProvider);
    final vault = ref.read(vaultProvider);
    for (final tkn in await vault.all()) {
      await vault.remove(tkn.id, wipeAccounts: true);
    }
    await db.transaction(() async {
      await db.delete(db.transactions).go();
      await db.delete(db.categoryRules).go();
      await db.delete(db.plannedPayments).go();
      await db.delete(db.installments).go();
      await db.delete(db.creditLimitSnapshots).go();
      await db.delete(db.accounts).go();
      await db.delete(db.categories).go();
      await db.delete(db.settings).go();
    });
    await ref.read(lockServiceProvider).disable();
  }
}

// ---------------------------------------------------------------------------
class _MCard extends StatelessWidget {
  final String id;
  final IconData icon;
  final String title;
  final String? open;
  final void Function(String id) onToggle;
  final Widget body;
  const _MCard(
      {required this.id,
      required this.icon,
      required this.title,
      required this.open,
      required this.onToggle,
      required this.body});

  @override
  Widget build(BuildContext context) {
    final t = tk(context);
    final isOpen = open == id;
    return Container(
      margin: const EdgeInsets.only(bottom: 13),
      decoration: BoxDecoration(
        gradient: t.panel,
        border: Border.all(color: t.line),
        borderRadius: BorderRadius.circular(20),
        boxShadow: t.shadowCard,
      ),
      clipBehavior: Clip.antiAlias,
      child: m.Column(children: [
        Press(
          onTap: () => onToggle(id),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            child: Row(children: [
              Icon(icon, size: 20, color: t.accent),
              const SizedBox(width: 11),
              Expanded(
                child: Text(title,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: t.ink)),
              ),
              AnimatedRotation(
                turns: isOpen ? .25 : 0,
                duration: const Duration(milliseconds: 200),
                child: Icon(Icons.chevron_right_rounded,
                    size: 22, color: t.ink3),
              ),
            ]),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 280),
          curve: AppCurves.enter,
          alignment: Alignment.topCenter,
          child: isOpen
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: body,
                )
              : const SizedBox(width: double.infinity),
        ),
      ]),
    );
  }
}

class _MLbl extends StatelessWidget {
  final String text;
  const _MLbl(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Text(text,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: tk(context).ink2)),
      );
}

class _MDiv extends StatelessWidget {
  const _MDiv();
  @override
  Widget build(BuildContext context) => Container(
      height: 1,
      margin: const EdgeInsets.symmetric(vertical: 15),
      color: tk(context).line);
}

class _NRow extends StatelessWidget {
  final String label;
  final String? sub;
  final Color? subColor;
  final bool on;
  final bool last;
  final VoidCallback onTap;
  const _NRow(
      {required this.label,
      this.sub,
      this.subColor,
      required this.on,
      this.last = false,
      required this.onTap});
  @override
  Widget build(BuildContext context) {
    final t = tk(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
          border:
              last ? null : Border(bottom: BorderSide(color: t.line))),
      child: Row(children: [
        Expanded(
          child: m.Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: t.ink)),
                if (sub != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(sub!,
                        style: TextStyle(
                            fontSize: 11.5,
                            color: subColor ?? t.ink3)),
                  ),
              ]),
        ),
        Tgl(on: on, onTap: onTap),
      ]),
    );
  }
}

class _DRow extends StatelessWidget {
  final IconData icon;
  final String title, sub;
  final VoidCallback onTap;
  const _DRow(
      {required this.icon,
      required this.title,
      required this.sub,
      required this.onTap});
  @override
  Widget build(BuildContext context) {
    final t = tk(context);
    return Press(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: t.surface2,
            border: Border.all(color: t.line),
            borderRadius: BorderRadius.circular(13)),
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: t.accent.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(11)),
            child: Icon(icon, size: 19, color: t.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: m.Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: t.ink)),
                  Text(sub,
                      style: TextStyle(fontSize: 11.5, color: t.ink2)),
                ]),
          ),
          Icon(Icons.chevron_right_rounded, size: 20, color: t.ink3),
        ]),
      ),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
