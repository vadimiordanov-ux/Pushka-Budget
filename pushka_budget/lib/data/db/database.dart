import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

// =============================================================================
// Local schema — port of the Supabase Postgres schema to SQLite/drift.
// Sources:
//  • 001_init.sql            → accounts, categories, transactions,
//                              category_rules, settings (+ seeds)
//  • migration.sql           → category_rules.mcc
//  • migration_v3_2.sql      → installments, credit_limit_snapshots
//                              (+ credit_by_owner view, see CreditRepo)
//  • migration_v3_3_final.sql → VERIFIED against the live Supabase schema
//    dump + Table Editor census (2026-07-10): planned_payments;
//    categories.limit_kop/color; transactions.internal / parent_id /
//    reimburses / balance; accounts = id/owner/card_name/created_at with
//    lowercase 'vadim'/'alisa' owner keys. Full table list confirmed — no
//    unported surprises. push_subs and notify_log are intentionally NOT
//    ported — Web Push is replaced by local notifications ('notified_marks'
//    in settings plays the role of notify_log).
//  • updated_at / tombstones are NEW (household two-device sync, LWW).
//  • budgets (001_init) is NOT ported: v3.3 moved limits onto
//    categories.limit_kop and the client only reads that.
// Amounts are kopecks (int). Negative = expense, positive = income.
// =============================================================================

class Accounts extends Table {
  TextColumn get id => text()(); // monobank account id from client-info
  TextColumn get owner => text()(); // owner key: 'vadim' | 'alisa' | custom
  TextColumn get cardName => text()();
  /// Which stored token discovered this account — preserves per-token owner
  /// attribution (the fix for the "all transactions showing as Alisa's" bug:
  /// an account can only ever be written by the token that owns it).
  TextColumn get tokenId => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('Category')
class Categories extends Table {
  TextColumn get id => text()(); // uuid
  TextColumn get name => text()();
  TextColumn get emoji => text().withDefault(const Constant('📌'))();
  TextColumn get color => text().nullable()(); // v3.3: hex like #E8A33D
  TextColumn get type => text()(); // 'expense' | 'income'
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  IntColumn get limitKop => integer().nullable()(); // v3.3 per-period limit
    DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)(); // household-sync LWW clock
  @override
  Set<Column> get primaryKey => {id};
  @override
  List<Set<Column>> get uniqueKeys => [
        {name, type}
      ];
}

@TableIndex(name: 'transactions_time_idx', columns: {#time})
@TableIndex(name: 'transactions_category_idx', columns: {#categoryId})
class Transactions extends Table {
  TextColumn get id => text()(); // monobank statementItem.id | uuid for manual
  TextColumn get accountId => text().nullable()();
  DateTimeColumn get time => dateTime()();
  TextColumn get description => text().withDefault(const Constant(''))();
  IntColumn get mcc => integer().nullable()();
  IntColumn get amount => integer()(); // kopecks, negative = expense
  IntColumn get currency => integer().withDefault(const Constant(980))();
  IntColumn get cashback => integer().withDefault(const Constant(0))();
  TextColumn get categoryId =>
      text().nullable().references(Categories, #id, onDelete: KeyAction.setNull)();
  TextColumn get subcategory => text().nullable()();
  TextColumn get note => text().nullable()();
  TextColumn get source =>
      text().withDefault(const Constant('monobank'))(); // monobank|manual|import
  // v3.3 additions ↓
  BoolColumn get internal => boolean().withDefault(const Constant(false))();
  TextColumn get parentId => text().nullable()(); // split child → parent tx
  TextColumn get reimburses => text().nullable()(); // income → reimbursed expense
  /// live-schema column (mono-webhook writes statementItem.balance):
  /// account balance after this transaction, kopecks
  IntColumn get balance => integer().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  /// household sync: LWW clock; bumped by trigger on app edits,
  /// preserved verbatim on merge writes (see HouseholdSync)
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

class CategoryRules extends Table {
  TextColumn get id => text()();
  TextColumn get pattern => text()(); // exact-match description (since v3.3)
  IntColumn get mcc => integer().nullable()(); // optional extra condition
  TextColumn get categoryId =>
      text().references(Categories, #id, onDelete: KeyAction.cascade)();
  TextColumn get subcategory => text().nullable()();
  IntColumn get priority => integer().withDefault(const Constant(100))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
    DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)(); // household-sync LWW clock
  @override
  Set<Column> get primaryKey => {id};
}

/// v3.3 (reconstructed): planned payments — the client reads/writes
/// name, amount_kop, day, category_id, note, notify, active.
/// Cadence metadata deliberately stays in settings.plan_meta, exactly like
/// the PWA ("мета живе поза схемою, щоб працювало без міграції").
class PlannedPayments extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get amountKop => integer()();
  IntColumn get day => integer()(); // day of month 1..31
  TextColumn get categoryId =>
      text().nullable().references(Categories, #id, onDelete: KeyAction.setNull)();
  TextColumn get note => text().nullable()();
  BoolColumn get notify => boolean().withDefault(const Constant(true))();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
    DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)(); // household-sync LWW clock
  @override
  Set<Column> get primaryKey => {id};
}

/// migration_v3_2.sql — installments (manual tracker).
class Installments extends Table {
  TextColumn get id => text()();
  TextColumn get bank => text().withDefault(const Constant(''))();
  TextColumn get name => text()();
  IntColumn get totalKop => integer()();
  IntColumn get monthsTotal => integer()();
  IntColumn get monthsPaid => integer().withDefault(const Constant(0))();
  TextColumn get firstDue => text()(); // ISO date yyyy-MM-dd (client format)
  TextColumn get categoryId =>
      text().nullable().references(Categories, #id, onDelete: KeyAction.setNull)();
  TextColumn get owner => text().nullable()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
    DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)(); // household-sync LWW clock
  @override
  Set<Column> get primaryKey => {id};
}

/// migration_v3_2.sql — daily credit-limit snapshots per card.
/// used_kop (generated column in Postgres) is computed in queries here.
class CreditLimitSnapshots extends Table {
  TextColumn get owner => text()();
  TextColumn get accountId => text()();
  TextColumn get day => text()(); // yyyy-MM-dd
  IntColumn get creditLimitKop => integer()();
  IntColumn get balanceKop => integer()();
  TextColumn get maskedPan => text().nullable()();
  @override
  Set<Column> get primaryKey => {accountId, day};
}

/// settings — same key/value JSON model as the PWA (`settings` table),
/// so every settings key ('theme', 'skin', 'chart', 'notify_prefs',
/// 'plan_meta', 'stats_widgets', 'quick_presets', …) ports verbatim.
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()(); // JSON-encoded
    DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)(); // household-sync LWW clock
  @override
  Set<Column> get primaryKey => {key};
}


/// household sync: deletion markers. Populated by AFTER DELETE triggers so
/// even FK-cascade deletes are captured; merged with last-writer-wins.
class Tombstones extends Table {
  TextColumn get entity => text()(); // table name
  TextColumn get rowId => text()();
  DateTimeColumn get deletedAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {entity, rowId};
}

/// Metadata for stored Monobank tokens. The token string itself lives ONLY in
/// flutter_secure_storage (Android Keystore / iOS Keychain) under
/// key 'mono_token_<id>'; this table holds non-secret bookkeeping, including
/// the persisted per-token rate-limit clock shared between the foreground app
/// and the WorkManager isolate.
class MonoTokens extends Table {
  TextColumn get id => text()();
  TextColumn get ownerKey => text()(); // 'vadim' | 'alisa' | slugified custom
  TextColumn get label => text()(); // display name, e.g. "Вадім"
  DateTimeColumn get addedAt => dateTime().withDefault(currentDateAndTime)();
  /// Monobank rate limit: 1 request / 60 s per token — persisted last-call time.
  DateTimeColumn get lastApiCallAt => dateTime().nullable()();
  /// High-water mark of synced statement time (unix seconds).
  IntColumn get lastSyncedAt => integer().withDefault(const Constant(0))();
  @override
  Set<Column> get primaryKey => {id};
}

// =============================================================================

@DriftDatabase(tables: [
  Accounts,
  Categories,
  Transactions,
  CategoryRules,
  PlannedPayments,
  Installments,
  CreditLimitSnapshots,
  Settings,
  Tombstones,
  MonoTokens,
])
class AppDb extends _$AppDb {
  AppDb() : super(driftDatabase(name: 'pushka_budget'));
  AppDb.forTesting(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _syncTriggers();
          await _seed();
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  /// Household-sync bookkeeping, done in SQL so no call-site can forget it:
  ///  • AFTER UPDATE: bump updated_at — but ONLY when the writer didn't set it
  ///    itself (WHEN NEW.updated_at = OLD.updated_at). Merge writes carry the
  ///    remote clock explicitly and are therefore left alone. SQLite recursive
  ///    triggers are off by default, so the trigger's own UPDATE can't loop.
  ///  • AFTER DELETE: record a tombstone (captures FK cascades too).
  Future<void> _syncTriggers() async {
    const synced = [
      'transactions', 'categories', 'category_rules',
      'planned_payments', 'installments', 'settings',
    ];
    for (final t in synced) {
      final pk = t == 'settings' ? 'key' : 'id';
      await customStatement('''
        CREATE TRIGGER IF NOT EXISTS trg_${t}_touch
        AFTER UPDATE ON $t
        WHEN NEW.updated_at = OLD.updated_at
        BEGIN
          UPDATE $t SET updated_at = strftime('%s','now') WHERE $pk = NEW.$pk;
        END''');
      await customStatement('''
        CREATE TRIGGER IF NOT EXISTS trg_${t}_tomb
        AFTER DELETE ON $t
        BEGIN
          INSERT OR REPLACE INTO tombstones(entity, row_id, deleted_at)
          VALUES ('$t', OLD.$pk, strftime('%s','now'));
        END''');
    }
  }

  // ---------- settings ----------
  Future<dynamic> getSetting(String key) async {
    final row = await (select(settings)..where((t) => t.key.equals(key))).getSingleOrNull();
    return row == null ? null : jsonDecode(row.value);
  }

  Future<Map<String, dynamic>> allSettings() async {
    final rows = await select(settings).get();
    return {for (final r in rows) r.key: jsonDecode(r.value)};
  }

  Stream<Map<String, dynamic>> watchSettings() => select(settings).watch().map(
      (rows) => {for (final r in rows) r.key: jsonDecode(r.value)});

  Future<void> setSetting(String key, dynamic value) =>
      into(settings).insertOnConflictUpdate(
          SettingsCompanion(key: Value(key), value: Value(jsonEncode(value))));

  // ---------- seed (001_init.sql verbatim) ----------
  Future<void> _seed() async {
    await setSetting('period_start_day', 22);
    await setSetting('theme', 'auto');
    await setSetting('savings_emoji', '🏦');

    const exp = [
      ['Їжа/вода', '🛒'], ['Кафе/ресторани', '🍽️'], ['Траспорт/таксі', '🚕'],
      ['Таблетки/доктора', '💊'], ['Рахунки', '🧾'], ['Котовитрати', '🐈'],
      ['Одяг', '👕'], ['Догляд', '💇'], ['Косметика/Гігіена', '🧼'],
      ['Інтрнет/зв\'язок/підписки', '📶'], ['Подарунки', '🎁'], ['Хоббі', '🎮'],
      ['Розваги', '🎬'], ['Спорт', '🏋️'], ['Битова хімія', '🧴'],
      ['Для дому', '🏠'], ['Кальян/Алко', '🍺'], ['Кредити', '💳'],
      ['Благодійність', '🤝'], ['Заощадження', '🏦'],
    ];
    const inc = [
      ['ЗП Вадим', '💰'], ['ЗП Аліса', '💰'], ['Перекази', '🔁'], ['Інше', '➕'],
    ];
    final byName = <String, String>{};
    for (var i = 0; i < exp.length; i++) {
      final id = genUuid();
      byName[exp[i][0]] = id;
      await into(categories).insert(CategoriesCompanion.insert(
          id: id, name: exp[i][0], type: 'expense',
          emoji: Value(exp[i][1]), sortOrder: Value(i + 1)));
    }
    for (var i = 0; i < inc.length; i++) {
      await into(categories).insert(CategoriesCompanion.insert(
          id: genUuid(), name: inc[i][0], type: 'income',
          emoji: Value(inc[i][1]), sortOrder: Value(i + 1)));
    }

    // seed rules (001_init.sql) — pattern, category, subcategory, priority
    const rules = [
      ['Bolt Food', 'Кафе/ресторани', 'Доставка', 10],
      ['Glovo', 'Кафе/ресторани', 'Доставка', 10],
      ['Bolt', 'Траспорт/таксі', 'Таксі', 50],
      ['Uklon', 'Траспорт/таксі', 'Таксі', 50],
      ['Уклон', 'Траспорт/таксі', 'Таксі', 50],
      ['метрополітен', 'Траспорт/таксі', 'Метро', 50],
      ['Фора', 'Їжа/вода', 'Їжа', 50],
      ['Novus', 'Їжа/вода', 'Їжа', 50],
      ['Новус', 'Їжа/вода', 'Їжа', 50],
      ['Сільпо', 'Їжа/вода', 'Їжа', 50],
      ['Silpo', 'Їжа/вода', 'Їжа', 50],
      ['АТБ', 'Їжа/вода', 'Їжа', 50],
      ['Охангрі', 'Їжа/вода', 'Готова їжа', 50],
      ['Fozzy', 'Їжа/вода', 'Доставка їжі', 50],
      ['McDonald', 'Кафе/ресторани', 'Фаст фуд', 50],
      ['KFC', 'Кафе/ресторани', 'Фаст фуд', 50],
      ['Croissant', 'Кафе/ресторани', 'Фаст фуд', 50],
      ['Пузата', 'Кафе/ресторани', 'Кафе', 50],
      ['Аптека', 'Таблетки/доктора', 'Ліки', 50],
      ['Подорожник', 'Таблетки/доктора', 'Ліки', 50],
      ['Petslike', 'Котовитрати', 'Корм, наповнювач', 50],
      ['MasterZoo', 'Котовитрати', null, 50],
      ['Netflix', 'Інтрнет/зв\'язок/підписки', 'Підписка', 50],
      ['Spotify', 'Інтрнет/зв\'язок/підписки', 'Підписка', 50],
      ['YouTube', 'Інтрнет/зв\'язок/підписки', 'Підписка', 50],
      ['iCloud', 'Інтрнет/зв\'язок/підписки', 'Підписка', 50],
      ['Київстар', 'Інтрнет/зв\'язок/підписки', 'Зв\'язок', 50],
      ['Kyivstar', 'Інтрнет/зв\'язок/підписки', 'Зв\'язок', 50],
      ['lifecell', 'Інтрнет/зв\'язок/підписки', 'Зв\'язок', 50],
    ];
    for (final r in rules) {
      final cid = byName[r[1]];
      if (cid == null) continue;
      await into(categoryRules).insert(CategoryRulesCompanion.insert(
          id: genUuid(),
          pattern: r[0] as String,
          categoryId: cid,
          subcategory: Value(r[2] as String?),
          priority: Value(r[3] as int)));
    }
  }
}

/// RFC-4122 v4 UUID without an extra dependency (crypto-random).
String genUuid() {
  final rng = Random.secure();
  final b = List<int>.generate(16, (_) => rng.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String h(int i) => b[i].toRadixString(16).padLeft(2, '0');
  return '${h(0)}${h(1)}${h(2)}${h(3)}-${h(4)}${h(5)}-${h(6)}${h(7)}-${h(8)}${h(9)}-${h(10)}${h(11)}${h(12)}${h(13)}${h(14)}${h(15)}';
}
