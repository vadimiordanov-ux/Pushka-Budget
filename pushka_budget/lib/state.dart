import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/money.dart';
import 'core/period.dart';
import 'data/db/database.dart';
import 'data/repos/repos.dart';
import 'services/ai_categorize.dart';
import 'services/backup.dart';
import 'services/household_sync.dart';
import 'services/lock_service.dart';
import 'services/monobank_api.dart';
import 'services/notifications.dart';
import 'services/rates.dart';
import 'services/sync_service.dart';
import 'services/token_vault.dart';

// ---------------------------------------------------------------------------
// Wiring — one AppDb, repos, services.
// ---------------------------------------------------------------------------
final dbProvider = Provider<AppDb>((ref) => throw UnimplementedError());

final txRepoProvider = Provider((ref) => TxRepo(ref.watch(dbProvider)));
final catRepoProvider = Provider((ref) => CatRepo(ref.watch(dbProvider)));
final plannedRepoProvider = Provider((ref) => PlannedRepo(ref.watch(dbProvider)));
final instRepoProvider = Provider((ref) => InstRepo(ref.watch(dbProvider)));
final creditRepoProvider = Provider((ref) => CreditRepo(ref.watch(dbProvider)));
final accountsRepoProvider = Provider((ref) => AccountsRepo(ref.watch(dbProvider)));

final monoApiProvider = Provider((ref) => MonobankApi());
final vaultProvider = Provider((ref) => TokenVault(ref.watch(dbProvider)));
final syncServiceProvider = Provider((ref) => SyncService(
    ref.watch(dbProvider), ref.watch(monoApiProvider), ref.watch(vaultProvider)));
final ratesServiceProvider = Provider(
    (ref) => RatesService(ref.watch(dbProvider), ref.watch(monoApiProvider)));
final notificationsProvider =
    Provider((ref) => NotificationsService(ref.watch(dbProvider)));
final lockServiceProvider = Provider((ref) => LockService(ref.watch(dbProvider)));
final backupServiceProvider = Provider((ref) => BackupService(ref.watch(dbProvider)));
final aiServiceProvider =
    Provider((ref) => AiCategorizeService(ref.watch(dbProvider)));
final householdSyncProvider =
    ChangeNotifierProvider((ref) => HouseholdSync(ref.watch(dbProvider)));

// ---------------------------------------------------------------------------
// settings — reactive mirror of the PWA `st.settings` (key/value JSON).
// ---------------------------------------------------------------------------
final settingsProvider = StreamProvider<Map<String, dynamic>>(
    (ref) => ref.watch(dbProvider).watchSettings());

Map<String, dynamic> settingsOf(WidgetRef ref) =>
    ref.watch(settingsProvider).value ?? const {};

// ---------------------------------------------------------------------------
// UI state — mirrors the PWA `st` object fields that aren't persisted.
// ---------------------------------------------------------------------------
class UiState extends ChangeNotifier {
  String tab = 'home'; // home | txs | stats | cats | more | sort | inst | tokens
  String mode = 'expense'; // home donut mode
  int offset = 0; // period navigation offset
  /// st.filterCat: [unset] ≙ no filter; '' ≙ «без категорії»; else category id
  static const unset = Object();
  Object filterCatBox = unset;
  int filterSign = -1;
  String q = '';
  String feedScope = 'period'; // period | all
  int feedLimit = 120;
  int sortSign = -1;
  final Set<String> skip = {}; // sort-helper skipped ids
  String? moreOpen; // open accordion card in More
  String catMode = 'expense';

  // Stats widget state (st.stats)
  String statsGran = 'p';
  int? cfSel;
  double? cfScroll;
  int weekOff = 0;
  int? weekSel;
  int acm = 0;
  String? scCat;
  int scMon = 6;

  void setTab(String t) {
    if (tab == t) return;
    tab = t;
    if (t != 'txs') filterCatBox = unset;
    notifyListeners();
  }

  void bump() => notifyListeners();
}

final uiProvider = ChangeNotifierProvider((ref) => UiState());

// ---------------------------------------------------------------------------
// Derived: current period, money formatter, live queries.
// ---------------------------------------------------------------------------
final periodProvider = Provider<Period>((ref) {
  final s = settingsOf(ref);
  final ui = ref.watch(uiProvider);
  return currentPeriod(
    mode: s['period_mode'] as String? ?? 'salary',
    startDay: int.tryParse('${s['period_start_day'] ?? 22}') ?? 22,
    offset: ui.offset,
  );
});

final moneyProvider = Provider<Money>((ref) {
  final s = settingsOf(ref);
  final currency = s['currency'] as String? ?? 'UAH';
  final rates = ref.watch(ratesProvider).value;
  const codes = {'USD': 840, 'EUR': 978, 'PLN': 985, 'GBP': 826};
  final rate = rates?[codes[currency]];
  return Money(
      currency: currency,
      rate: rate,
      locale: kLocaleBcp[s['locale'] as String? ?? 'uk'] ?? 'uk-UA');
});

final ratesProvider = FutureProvider<Map<int, double>?>(
    (ref) => ref.watch(ratesServiceProvider).load());

final periodTxsProvider = StreamProvider<List<Transaction>>((ref) =>
    ref.watch(txRepoProvider).watchPeriod(ref.watch(periodProvider)));

final allTxsProvider = StreamProvider<List<Transaction>>(
    (ref) => ref.watch(txRepoProvider).watchAll());

final categoriesProvider = StreamProvider<List<Category>>(
    (ref) => ref.watch(catRepoProvider).watch());

final plannedProvider = StreamProvider<List<PlannedPayment>>(
    (ref) => ref.watch(plannedRepoProvider).watch());

final installmentsProvider = StreamProvider<List<Installment>>(
    (ref) => ref.watch(instRepoProvider).watch());

final creditProvider = StreamProvider<List<CreditRow>>(
    (ref) => ref.watch(creditRepoProvider).watchByOwner());

final accountsProvider = StreamProvider<List<Account>>(
    (ref) => ref.watch(accountsRepoProvider).watch());

final tokensProvider = StreamProvider<List<MonoToken>>(
    (ref) => ref.watch(vaultProvider).watch());

// ---------------------------------------------------------------------------
// Foreground sync orchestration (⟳ button, pull-to-refresh, app resume).
// ---------------------------------------------------------------------------
final syncingProvider = StateProvider<bool>((ref) => false);

Future<SyncResult?> runForegroundSync(WidgetRef ref,
    {void Function(SyncProgress)? onProgress}) async {
  if (ref.read(syncingProvider)) return null;
  ref.read(syncingProvider.notifier).state = true;
  try {
    final res = await ref
        .read(syncServiceProvider)
        .syncAll(onProgress: onProgress, maxDuration: const Duration(minutes: 3));
    await ref.read(notificationsProvider).evaluateAfterSync(res.inserted);
    return res;
  } finally {
    ref.read(syncingProvider.notifier).state = false;
  }
}
