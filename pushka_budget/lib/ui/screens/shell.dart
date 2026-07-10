import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/haptics.dart';
import '../../core/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../state.dart';
import '../sheets/add_tx_sheet.dart';
import '../sheets/period_picker_sheet.dart';
import '../util.dart';
import '../widgets/common.dart';
import '../widgets/pull_to_refresh.dart';
import 'categories_screen.dart';
import 'feed_screen.dart';
import 'home_screen.dart';
import 'installments_screen.dart';
import 'more_screen.dart';
import 'sort_screen.dart';
import 'stats_screen.dart';
import 'sync_screen.dart';
import 'tokens_screen.dart';

/// App shell — topbar (gradient dot + title, period nav, sync), tab body,
/// FAB, floating blurred tab bar with the lock dot. Port of render().
class Shell extends ConsumerWidget {
  const Shell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = tk(context);
    final l = L.of(context);
    final ui = ref.watch(uiProvider);
    final settings = settingsOf(ref);
    final syncing = ref.watch(syncingProvider);
    final period = ref.watch(periodProvider);
    final locale = localeOf(settings);
    final mode = settings['period_mode'] as String? ?? 'salary';

    final showFab = ui.tab == 'home' || ui.tab == 'txs';
    final showNav =
        const {'home', 'txs', 'stats', 'cats', 'sort'}.contains(ui.tab);
    final title = switch (ui.tab) {
      'more' => l.settingsTitle,
      'inst' => l.instTitle.toUpperCase(),
      'tokens' => l.xTokensTitle.toUpperCase(),
      'sync' => l.xSyncTitle.toUpperCase(),
      _ => l.budget,
    };

    final body = switch (ui.tab) {
      'txs' => const FeedScreen(),
      'stats' => const StatsScreen(),
      'cats' => const CategoriesScreen(),
      'more' => const MoreScreen(),
      'sort' => const SortScreen(),
      'inst' => const InstallmentsScreen(),
      'tokens' => const TokensScreen(),
      'sync' => const SyncScreen(),
      _ => const HomeScreen(),
    };

    Future<void> doSync() async {
      ToastHost.show(context, l.syncing);
      final res = await runForegroundSync(ref);
      if (!context.mounted || res == null) return;
      if (res.errors.isNotEmpty && res.newTx == 0) {
        ToastHost.show(context, l.syncErr);
      } else {
        ToastHost.show(context, l.xSyncedN('${res.newTx}'));
      }
    }

    return Scaffold(
      backgroundColor: t.bg,
      body: Container(
        // body radial glow: radial-gradient(640px 340px at 50% -120px, glow)
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -1.4),
            radius: 1.2,
            colors: [t.glow, t.glow.withValues(alpha: 0)],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(children: [
                // ---- topbar ----
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(children: [
                    Container(
                        width: 9,
                        height: 9,
                        margin: const EdgeInsets.only(right: 9),
                        decoration: BoxDecoration(
                            gradient: t.gradient,
                            borderRadius: BorderRadius.circular(3),
                            boxShadow: [
                              BoxShadow(color: t.glow, blurRadius: 10)
                            ])),
                    Flexible(
                      child: Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontFamily: AppText.display,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2,
                              color: t.ink)),
                    ),
                    const Spacer(),
                    if (showNav) ...[
                      _NavBtn('‹', onTap: () {
                        ui.offset -= 1;
                        ui.bump();
                      }),
                      Press(
                        onTap: () => showPeriodPickerSheet(context, ref),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 13, vertical: 8),
                          decoration: BoxDecoration(
                              color: t.surface2,
                              border: Border.all(color: t.line),
                              borderRadius: BorderRadius.circular(13)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.calendar_month_rounded,
                                size: 15, color: t.accent),
                            const SizedBox(width: 7),
                            Text(periodLabel(period, mode, locale),
                                style: TextStyle(
                                    fontFamily: AppText.display,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: t.ink)),
                          ]),
                        ),
                      ),
                      _NavBtn('›',
                          disabled: ui.offset >= 0,
                          onTap: () {
                            ui.offset += 1;
                            ui.bump();
                          }),
                    ],
                    _SyncBtn(spinning: syncing, onTap: doSync),
                  ]),
                ),
                // ---- body with pull-to-refresh ----
                Expanded(
                  child: AppPullToRefresh(
                    onRefresh: doSync,
                    child: body,
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
      floatingActionButton: showFab
          ? Padding(
              padding: const EdgeInsets.only(bottom: 74),
              child: Press(
                onTap: () {
                  haptic(HapticKind.select);
                  showAddTxSheet(context, ref);
                },
                child: Container(
                  width: 58,
                  height: 58,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: t.gradient,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                          color: t.accent2.withValues(alpha: .45),
                          blurRadius: 26,
                          offset: const Offset(0, 10))
                    ],
                  ),
                  child: Text('+',
                      style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w600,
                          height: 1,
                          color: t.accentInk)),
                ),
              ),
            )
          : null,
      bottomNavigationBar: _TabBar(ui: ui, settings: settings),
    );
  }
}

class _NavBtn extends StatelessWidget {
  final String glyph;
  final VoidCallback onTap;
  final bool disabled;
  const _NavBtn(this.glyph, {required this.onTap, this.disabled = false});
  @override
  Widget build(BuildContext context) {
    final t = tk(context);
    return Opacity(
      opacity: disabled ? .3 : 1,
      child: Press(
        onTap: disabled ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          child: Text(glyph,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: t.ink2)),
        ),
      ),
    );
  }
}

/// ⟳ button — .syncb:active rotates 180°; continuous spin while syncing.
class _SyncBtn extends StatefulWidget {
  final bool spinning;
  final VoidCallback onTap;
  const _SyncBtn({required this.spinning, required this.onTap});
  @override
  State<_SyncBtn> createState() => _SyncBtnState();
}

class _SyncBtnState extends State<_SyncBtn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 700));

  @override
  void didUpdateWidget(covariant _SyncBtn old) {
    super.didUpdateWidget(old);
    if (widget.spinning && !old.spinning) {
      _c.repeat();
    } else if (!widget.spinning && old.spinning) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = tk(context);
    return Press(
      onTap: widget.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: RotationTransition(
          turns: _c,
          child: Text('⟳', style: TextStyle(fontSize: 17, color: t.ink2)),
        ),
      ),
    );
  }
}

/// Floating blurred tab bar with the lock dot on «Ще».
class _TabBar extends ConsumerWidget {
  final UiState ui;
  final Map<String, dynamic> settings;
  const _TabBar({required this.ui, required this.settings});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = tk(context);
    final l = L.of(context);
    final lockOn = settings['app_lock'] == true;
    final tabs = [
      ('home', Icons.home_rounded, l.tabHome),
      ('txs', Icons.receipt_long_rounded, l.tabTxs),
      ('stats', Icons.monitor_heart_rounded, l.tabStats),
      ('cats', Icons.category_rounded, l.tabCats),
      ('more', Icons.settings_rounded, l.tabMore),
    ];
    // sub-screens map to their parent tab highlight
    final current = switch (ui.tab) {
      'sort' => 'home',
      'inst' || 'tokens' || 'sync' => 'more',
      _ => ui.tab,
    };
    return Padding(
      padding: EdgeInsets.only(
          left: 12,
          right: 12,
          bottom: 10 + MediaQuery.of(context).padding.bottom),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 496),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: t.navBg,
                  border: Border.all(color: t.line),
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Row(children: [
                  for (final (id, icon, name) in tabs)
                    Expanded(
                      child: Press(
                        onTap: () {
                          if (ui.tab != id) haptic();
                          ui.setTab(id);
                        },
                        child: Semantics(
                          label: name,
                          selected: current == id,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            decoration: BoxDecoration(
                              color: current == id
                                  ? t.accent.withValues(alpha: .12)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Stack(
                                clipBehavior: Clip.none,
                                alignment: Alignment.center,
                                children: [
                                  Icon(icon,
                                      size: 23,
                                      color:
                                          current == id ? t.accent : t.ink3),
                                  if (id == 'more' && lockOn)
                                    Positioned(
                                      top: -4,
                                      right: 22,
                                      child: Container(
                                        width: 14,
                                        height: 14,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                            color: t.income,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                                color: t.bg, width: 2)),
                                        child: const Icon(Icons.lock,
                                            size: 7, color: Colors.white),
                                      ),
                                    ),
                                ]),
                          ),
                        ),
                      ),
                    ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
