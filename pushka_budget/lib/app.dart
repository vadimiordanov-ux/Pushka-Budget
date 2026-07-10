import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/tokens.dart';
import 'l10n/app_localizations.dart';
import 'state.dart';
import 'ui/screens/lock_screen.dart';
import 'ui/screens/onboarding.dart';
import 'ui/screens/shell.dart';

/// applyTheme() port: skin ('aurora' default | 'basic') × theme
/// ('light'|'dark'|'auto') → Tokens. Exposed via an InheritedWidget so every
/// widget reads `T.of(context)` like the CSS custom properties.
class ThemeScope extends InheritedWidget {
  final Tokens t;
  const ThemeScope({super.key, required this.t, required super.child});
  static Tokens of(BuildContext c) =>
      c.dependOnInheritedWidgetOfExactType<ThemeScope>()!.t;
  @override
  bool updateShouldNotify(ThemeScope old) => old.t != t;
}

class BudgetApp extends ConsumerStatefulWidget {
  const BudgetApp({super.key});
  @override
  ConsumerState<BudgetApp> createState() => _BudgetAppState();
}

class _BudgetAppState extends ConsumerState<BudgetApp>
    with WidgetsBindingObserver {
  bool _locked = false;
  bool _bootChecked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootLock();
  }

  Future<void> _bootLock() async {
    final lock = ref.read(lockServiceProvider);
    final enabled = await lock.lockEnabled;
    if (mounted) {
      setState(() {
        _locked = enabled;
        _bootChecked = true;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// visibilitychange parity: mark hide time; on resume relock past timeout
  /// and refresh data (the PWA re-pulled on visible).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    final lock = ref.read(lockServiceProvider);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      await lock.markHidden();
    } else if (state == AppLifecycleState.resumed) {
      if (await lock.shouldRelockOnResume() && mounted) {
        setState(() => _locked = true);
      }
      ref.invalidate(ratesProvider);
      // household sync: best-effort re-sync with the remembered pairing
      // (silently skipped when the other phone isn't hosting)
      ref.read(householdSyncProvider).trySyncRemembered();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).value ?? const {};
    final skin = settings['skin'] == 'basic' ? 'basic' : 'aurora';
    final themePref = settings['theme'] as String? ?? 'auto';
    final platformDark =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final dark =
        themePref == 'dark' || (themePref == 'auto' && platformDark);
    final t = Tokens.of(skin: skin, dark: dark);

    final localeCode = settings['locale'] as String? ?? 'uk';
    final onboarded = settings['onboarded'] == true;

    return ThemeScope(
      t: t,
      child: MaterialApp(
        title: 'Бюджет',
        debugShowCheckedModeBanner: false,
        locale: Locale(localeCode),
        supportedLocales: L.supportedLocales,
        localizationsDelegates: const [
          L.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ThemeData(
          useMaterial3: true,
          brightness: dark ? Brightness.dark : Brightness.light,
          scaffoldBackgroundColor: t.bg,
          fontFamily: AppText.body,
          colorScheme: ColorScheme.fromSeed(
              seedColor: t.accent,
              brightness: dark ? Brightness.dark : Brightness.light,
              surface: t.surface),
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
        ),
        home: !_bootChecked
            ? Container(color: t.bg)
            : Stack(children: [
                if (!onboarded)
                  const OnboardingScreen()
                else
                  const Shell(),
                if (_locked)
                  LockScreen(onUnlocked: () => setState(() => _locked = false)),
              ]),
      ),
    );
  }
}
