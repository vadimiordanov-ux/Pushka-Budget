import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../data/db/database.dart';
import 'backup.dart';
import 'monobank_api.dart';
import 'notifications.dart';
import 'sync_service.dart';
import 'token_vault.dart';

/// WorkManager glue — replaces the Monobank→Cloudflare-Worker webhook with
/// periodic polling. 15 minutes is Android's floor for periodic work; the
/// per-token 60-second Monobank budget is enforced inside SyncService via the
/// clock persisted in the MonoTokens table (shared with the foreground app).
const kPollTask = 'pushka.budget.poll';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    final db = AppDb();
    try {
      final api = MonobankApi();
      final vault = TokenVault(db);
      final sync = SyncService(db, api, vault);
      final notifications = NotificationsService(db);
      // Bounded run: WorkManager kills long jobs; waiting on the 60 s/token
      // budget is capped, the rest is picked up next cycle.
      final result =
          await sync.syncAll(maxDuration: const Duration(minutes: 8));
      // Time-based triggers (planned-tomorrow, period summary) must fire even
      // when no new transactions arrived.
      await notifications.evaluateAfterSync(result.inserted);
      // daily rotating JSON auto-backup (uninstall/lost-phone safety net)
      try {
        await BackupService(db).autoExport();
      } catch (_) {}
      return true;
    } catch (_) {
      return true; // don't let WorkManager back off into oblivion; next tick retries
    } finally {
      await db.close();
    }
  });
}

Future<void> registerBackgroundPolling() async {
  await Workmanager().initialize(callbackDispatcher);
  await Workmanager().registerPeriodicTask(
    kPollTask,
    kPollTask,
    frequency: const Duration(minutes: 15),
    existingWorkPolicy: ExistingWorkPolicy.keep,
    constraints: Constraints(networkType: NetworkType.connected),
    backoffPolicy: BackoffPolicy.linear,
    backoffPolicyDelay: const Duration(minutes: 5),
  );
}

Future<void> cancelBackgroundPolling() =>
    Workmanager().cancelByUniqueName(kPollTask);
