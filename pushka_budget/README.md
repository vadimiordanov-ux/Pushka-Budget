# Пушка-бюджет · Flutter port (v4.0.0)

Local-first Flutter port of the pushka-budget PWA (Android now, iOS-ready).
No Supabase, no Cloudflare — SQLite (drift) on device, Monobank polled
directly from the phone, notifications generated locally.

## Build

Requires **Flutter 3.27+** (uses `Color.withValues`, `sheetAnimationStyle`).

```bash
cd pushka_budget

# 1. generate the platform folders around this source tree
flutter create --org com.pushka --project-name pushka_budget --platforms android,ios .
#    → answer "no" if asked to overwrite lib/ or pubspec.yaml
#    → KEEP android/app/src/main/AndroidManifest.xml from this repo
#      (permissions + notification receivers); if flutter create replaced it,
#      restore it via git checkout.

# 2. deps + codegen
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # drift → database.g.dart
# l10n (lib/l10n/app_localizations.dart) is generated automatically by
# `flutter pub get` / build because pubspec has `generate: true`.

# 3. run / build
flutter run
flutter build apk --release
```

Android notes:
- `minSdk 23` (local_auth), `compileSdk 35`.
- WorkManager needs no extra manifest entries; the poll task registers itself
  on first launch (`registerBackgroundPolling` in `main.dart`).
- On Android 13+ the app asks for `POST_NOTIFICATIONS` when the push toggle
  is enabled in «Ще → Сповіщення».

## Where things live

| Piece | Path |
|---|---|
| Design tokens (both skins × light/dark), palettes, emoji set, curves | `lib/core/tokens.dart` |
| Salary-period logic (day-22 anchor) | `lib/core/period.dart` |
| Money/format + currency conversion | `lib/core/money.dart`, `lib/services/rates.dart` |
| Drift schema (ports 001_init + v3.2 + mcc + reconstructed v3.3) | `lib/data/db/database.dart` |
| computeVals / recurring detection / analytics math | `lib/data/repos/analytics.dart` |
| Repos incl. rules retro-apply, auto-transfer marking, credit_by_owner | `lib/data/repos/repos.dart` |
| Monobank API client | `lib/services/monobank_api.dart` |
| Token vault (flutter_secure_storage) | `lib/services/token_vault.dart` |
| Poll pipeline (rate limit, 31d windows, 500-row pagination, dedupe, owner attribution, MCC categorization, credit snapshots) | `lib/services/sync_service.dart` |
| WorkManager entry (15-min periodic) | `lib/services/background.dart` |
| Local notification triggers (replaces budget-notify) | `lib/services/notifications.dart` |
| CSV/JSON backup & restore (PWA-compatible dump shape) | `lib/services/backup.dart` |
| App lock (PIN sha-256 + cooldowns + biometrics) | `lib/services/lock_service.dart` |
| 10-locale ARB files (generated from i18n.js, fallback chain preserved) | `lib/l10n/app_*.arb` |
| Screens / sheets / shared widgets | `lib/ui/…` |

## Household sync (two phones)

«Ще → Синхронізація двох пристроїв». Both phones on the same Wi-Fi:
one taps «Показати код запрошення» (starts a temporary HTTP host on :8765
and shows its IP + a 6-char code), the other enters the address + code and
taps «Синхронізувати». Full snapshots are exchanged directly between the
phones (no cloud) and merged last-writer-wins per row, with deletion
tombstones maintained by SQLite triggers. Synced: transactions (incl.
categories/splits/reimburse/manual), categories, rules, planned payments,
installments, shared settings (period, plan_meta, subs_hidden, presets).
NOT synced: Monobank tokens, accounts/credit snapshots, device-local
settings. The pairing is remembered; the app retries it silently on resume.
Not realtime — bank feeds converge anyway since both phones poll Monobank.

## Notifications

Triggers, texts and dedup keys match the deployed budget-notify worker
(verified 2026-07-10). Cron-equivalent triggers (planned-tomorrow, period
summary) fire on the first poll after 09:00 local. Flagged improvements over
the worker: cadence plans and installment dues also remind a day before.
«Дозволити роботу у фоні» in the notifications card requests the battery-
optimization exemption so the 15-min WorkManager cycle survives OEM killers.

## AI categorization

Local replacement of the worker's /ai-categorize: the app calls the
Anthropic API directly (same prompt/model behavior, rules with priority 30,
exact pattern + MCC). Configure the key at the bottom of «Токени Monobank» —
it lives in flutter_secure_storage; the «✨ AI-розкидати» button then appears
in the sort helper.

## Data safety

Three layers:
1. **Android Auto Backup** — the SQLite DB is included in the user's Google
   backup (`backup_rules.xml` / `data_extraction_rules.xml`), so data
   survives uninstall and transfers to a new phone. Tokens are excluded
   (Keystore keys don't transfer; re-enter them on the new device).
2. **Daily auto-export** — the WorkManager cycle writes a rotating JSON dump
   (last 7 days) into the app documents dir (`backups/`).
3. **Manual JSON backup/restore** — «Ще → Дані та резервні копії»; the dump
   is shape-compatible with the old PWA backup (v:1), both ways.

Monobank tokens and the Anthropic key are stored exclusively in Android
Keystore-backed encrypted storage (`flutter_secure_storage`), never in
SQLite or SharedPreferences, and are excluded from every backup path and
from household sync by design.
