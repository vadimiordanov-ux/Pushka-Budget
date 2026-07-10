import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../data/db/database.dart';

/// Household two-device sync — restores the PWA's "бюджет для двох"
/// without any server: both phones must be on the same Wi-Fi, one shows an
/// invitation code (and becomes a temporary HTTP host), the other enters it.
/// They exchange full snapshots of the SHARED data set and merge with
/// last-writer-wins per row (updated_at clocks + deletion tombstones,
/// maintained by SQLite triggers — see AppDb._syncTriggers).
///
/// What syncs: transactions (incl. category/subcategory/note/internal/splits/
/// reimburse links and manual txs), categories, category_rules,
/// planned_payments, installments, and a whitelist of shared settings.
/// What NEVER syncs: Monobank tokens, accounts/credit snapshots (each phone
/// polls its own tokens), device-local settings (theme, lock, avatar,
/// notified_marks, rates cache).
///
/// Not realtime: run it manually (or it auto-runs on app open when the last
/// pairing is remembered and the host is reachable). Bank transactions
/// converge anyway because both phones poll the same statement API.
class HouseholdSync extends ChangeNotifier {
  final AppDb db;
  HouseholdSync(this.db);

  static const _port = 8765;
  static const _sharedSettings = {
    'period_start_day', 'period_mode', 'plan_meta', 'subs_hidden',
    'quick_presets',
  };

  HttpServer? _server;
  String? code; // 6-char invitation code while hosting
  List<String> addresses = const [];
  String status = ''; // last host-side event, for the UI
  ({int sent, int applied})? lastResult;

  bool get hosting => _server != null;

  // ---------------------------------------------------------------- hosting
  Future<void> startHost() async {
    await stopHost();
    final rng = Random.secure();
    const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    code = List.generate(6, (_) => alphabet[rng.nextInt(alphabet.length)])
        .join();
    _server = await HttpServer.bind(InternetAddress.anyIPv4, _port);
    addresses = [
      for (final ni in await NetworkInterface.list(
          type: InternetAddressType.IPv4, includeLinkLocal: false))
        for (final a in ni.addresses)
          if (!a.isLoopback) a.address
    ];
    status = '';
    notifyListeners();
    _server!.listen((req) async {
      try {
        if (req.method != 'POST' ||
            req.uri.path != '/sync' ||
            req.headers.value('x-sync-key') != code) {
          req.response.statusCode = 404;
          await req.response.close();
          return;
        }
        final body = await utf8.decoder.bind(req).join();
        final mine = await _snapshot(); // pre-merge state for the peer
        final applied = await _merge(jsonDecode(body) as Map<String, dynamic>);
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({'applied': applied, ...mine}));
        await req.response.close();
        status = 'ok:$applied';
        notifyListeners();
      } catch (e) {
        status = 'err:$e';
        notifyListeners();
        try {
          req.response.statusCode = 500;
          await req.response.close();
        } catch (_) {}
      }
    });
  }

  Future<void> stopHost() async {
    await _server?.close(force: true);
    _server = null;
    code = null;
    addresses = const [];
    notifyListeners();
  }

  // ---------------------------------------------------------------- joining
  /// Connect to [host] ("192.168.1.5" or "192.168.1.5:8765") with the
  /// invitation [key]; exchanges snapshots both ways. Remembers the pairing
  /// for one-tap re-sync.
  Future<({int sent, int applied})> joinAndSync(String host, String key) async {
    final addr = host.contains(':') ? host : '$host:$_port';
    final snap = await _snapshot();
    final r = await http
        .post(Uri.parse('http://$addr/sync'),
            headers: {
              'Content-Type': 'application/json',
              'x-sync-key': key.trim().toUpperCase(),
            },
            body: jsonEncode(snap))
        .timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) {
      throw Exception('sync ${r.statusCode}');
    }
    final remote = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    final applied = await _merge(remote);
    await db.setSetting('pair', {'host': addr, 'key': key.trim().toUpperCase()});
    lastResult = (sent: (remote['applied'] as num?)?.toInt() ?? 0, applied: applied);
    notifyListeners();
    return lastResult!;
  }

  /// Best-effort re-sync with the remembered pairing (e.g. on app resume).
  Future<void> trySyncRemembered() async {
    final pair = await db.getSetting('pair');
    if (pair is! Map) return;
    try {
      await joinAndSync(pair['host'] as String, pair['key'] as String);
    } catch (_) {/* host not up — silently skip */}
  }

  // ---------------------------------------------------------------- snapshot
  int _epoch(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;
  DateTime _fromEpoch(num s) =>
      DateTime.fromMillisecondsSinceEpoch(s.toInt() * 1000);

  Future<Map<String, dynamic>> _snapshot() async {
    final txs = await db.select(db.transactions).get();
    final cats = await db.select(db.categories).get();
    final rules = await db.select(db.categoryRules).get();
    final planned = await db.select(db.plannedPayments).get();
    final insts = await db.select(db.installments).get();
    final sets = await db.select(db.settings).get();
    final tombs = await db.select(db.tombstones).get();
    return {
      'v': 1,
      'transactions': [
        for (final t in txs)
          {
            'id': t.id, 'account_id': t.accountId, 'time': _epoch(t.time),
            'description': t.description, 'mcc': t.mcc, 'amount': t.amount,
            'currency': t.currency, 'cashback': t.cashback,
            'category_id': t.categoryId, 'subcategory': t.subcategory,
            'note': t.note, 'source': t.source, 'internal': t.internal,
            'parent_id': t.parentId, 'reimburses': t.reimburses,
            'balance': t.balance, 'u': _epoch(t.updatedAt),
          }
      ],
      'categories': [
        for (final c in cats)
          {
            'id': c.id, 'name': c.name, 'emoji': c.emoji, 'color': c.color,
            'type': c.type, 'sort_order': c.sortOrder, 'archived': c.archived,
            'limit_kop': c.limitKop, 'u': _epoch(c.updatedAt),
          }
      ],
      'category_rules': [
        for (final r in rules)
          {
            'id': r.id, 'pattern': r.pattern, 'mcc': r.mcc,
            'category_id': r.categoryId, 'subcategory': r.subcategory,
            'priority': r.priority, 'u': _epoch(r.updatedAt),
          }
      ],
      'planned_payments': [
        for (final p in planned)
          {
            'id': p.id, 'name': p.name, 'amount_kop': p.amountKop,
            'day': p.day, 'category_id': p.categoryId, 'note': p.note,
            'notify': p.notify, 'active': p.active, 'u': _epoch(p.updatedAt),
          }
      ],
      'installments': [
        for (final i in insts)
          {
            'id': i.id, 'bank': i.bank, 'name': i.name,
            'total_kop': i.totalKop, 'months_total': i.monthsTotal,
            'months_paid': i.monthsPaid, 'first_due': i.firstDue,
            'category_id': i.categoryId, 'owner': i.owner,
            'archived': i.archived, 'u': _epoch(i.updatedAt),
          }
      ],
      'settings': [
        for (final s in sets)
          if (_sharedSettings.contains(s.key))
            {'key': s.key, 'value': s.value, 'u': _epoch(s.updatedAt)}
      ],
      'tombstones': [
        for (final t in tombs)
          {'entity': t.entity, 'id': t.rowId, 'at': _epoch(t.deletedAt)}
      ],
    };
  }

  // ---------------------------------------------------------------- merge
  /// LWW merge. Returns the number of applied changes.
  /// Merge writes carry the remote updated_at explicitly, so the touch
  /// triggers (WHEN NEW.updated_at = OLD.updated_at) leave them untouched
  /// and clocks converge instead of ping-ponging.
  Future<int> _merge(Map<String, dynamic> snap) async {
    var applied = 0;
    await db.transaction(() async {
      // 1. tombstones first: newest event wins
      final localTombs = {
        for (final t in await db.select(db.tombstones).get())
          '${t.entity}|${t.rowId}': _epoch(t.deletedAt)
      };
      for (final t in (snap['tombstones'] as List? ?? [])) {
        final entity = t['entity'] as String;
        final id = t['id'] as String;
        final at = (t['at'] as num).toInt();
        final key = '$entity|$id';
        if ((localTombs[key] ?? 0) < at) {
          await db.into(db.tombstones).insert(
              TombstonesCompanion.insert(
                  entity: entity,
                  rowId: id,
                  deletedAt: Value(_fromEpoch(at))),
              mode: InsertMode.insertOrReplace);
          localTombs[key] = at;
        }
        // delete the local row if it wasn't edited after the deletion
        final deleted = await _deleteIfOlder(entity, id, at);
        if (deleted) applied++;
      }

      // 2. rows: apply when newer than local AND newer than any tombstone
      Future<void> rows(
        String entity,
        List<dynamic>? list,
        Future<int> Function(Map<String, dynamic> r) localClock,
        Future<void> Function(Map<String, dynamic> r) write,
      ) async {
        for (final raw in (list ?? [])) {
          final r = (raw as Map).cast<String, dynamic>();
          final u = (r['u'] as num).toInt();
          final id = (r['id'] ?? r['key']) as String;
          if ((localTombs['$entity|$id'] ?? 0) >= u) continue;
          if (await localClock(r) >= u) continue;
          await write(r);
          applied++;
        }
      }

      // categories BEFORE transactions/rules (FK targets)
      await rows('categories', snap['categories'] as List?, (r) async {
        final row = await (db.select(db.categories)
              ..where((c) => c.id.equals(r['id'] as String)))
            .getSingleOrNull();
        return row == null ? -1 : _epoch(row.updatedAt);
      }, (r) async {
        await db.into(db.categories).insertOnConflictUpdate(
            CategoriesCompanion(
                id: Value(r['id'] as String),
                name: Value(r['name'] as String),
                emoji: Value(r['emoji'] as String? ?? '📌'),
                color: Value(r['color'] as String?),
                type: Value(r['type'] as String),
                sortOrder: Value((r['sort_order'] as num?)?.toInt() ?? 0),
                archived: Value(r['archived'] == true),
                limitKop: Value((r['limit_kop'] as num?)?.toInt()),
                updatedAt: Value(_fromEpoch(r['u'] as num))));
      });

      await rows('transactions', snap['transactions'] as List?, (r) async {
        final row = await (db.select(db.transactions)
              ..where((t) => t.id.equals(r['id'] as String)))
            .getSingleOrNull();
        return row == null ? -1 : _epoch(row.updatedAt);
      }, (r) async {
        await db.into(db.transactions).insertOnConflictUpdate(
            TransactionsCompanion(
                id: Value(r['id'] as String),
                accountId: Value(r['account_id'] as String?),
                time: Value(_fromEpoch(r['time'] as num)),
                description: Value(r['description'] as String? ?? ''),
                mcc: Value((r['mcc'] as num?)?.toInt()),
                amount: Value((r['amount'] as num).toInt()),
                currency: Value((r['currency'] as num?)?.toInt() ?? 980),
                cashback: Value((r['cashback'] as num?)?.toInt() ?? 0),
                categoryId: Value(r['category_id'] as String?),
                subcategory: Value(r['subcategory'] as String?),
                note: Value(r['note'] as String?),
                source: Value(r['source'] as String? ?? 'monobank'),
                internal: Value(r['internal'] == true),
                parentId: Value(r['parent_id'] as String?),
                reimburses: Value(r['reimburses'] as String?),
                balance: Value((r['balance'] as num?)?.toInt()),
                updatedAt: Value(_fromEpoch(r['u'] as num))));
      });

      await rows('category_rules', snap['category_rules'] as List?, (r) async {
        final row = await (db.select(db.categoryRules)
              ..where((x) => x.id.equals(r['id'] as String)))
            .getSingleOrNull();
        return row == null ? -1 : _epoch(row.updatedAt);
      }, (r) async {
        await db.into(db.categoryRules).insertOnConflictUpdate(
            CategoryRulesCompanion(
                id: Value(r['id'] as String),
                pattern: Value(r['pattern'] as String),
                mcc: Value((r['mcc'] as num?)?.toInt()),
                categoryId: Value(r['category_id'] as String),
                subcategory: Value(r['subcategory'] as String?),
                priority: Value((r['priority'] as num?)?.toInt() ?? 100),
                updatedAt: Value(_fromEpoch(r['u'] as num))));
      });

      await rows('planned_payments', snap['planned_payments'] as List?,
          (r) async {
        final row = await (db.select(db.plannedPayments)
              ..where((x) => x.id.equals(r['id'] as String)))
            .getSingleOrNull();
        return row == null ? -1 : _epoch(row.updatedAt);
      }, (r) async {
        await db.into(db.plannedPayments).insertOnConflictUpdate(
            PlannedPaymentsCompanion(
                id: Value(r['id'] as String),
                name: Value(r['name'] as String),
                amountKop: Value((r['amount_kop'] as num).toInt()),
                day: Value((r['day'] as num?)?.toInt() ?? 1),
                categoryId: Value(r['category_id'] as String?),
                note: Value(r['note'] as String?),
                notify: Value(r['notify'] != false),
                active: Value(r['active'] != false),
                updatedAt: Value(_fromEpoch(r['u'] as num))));
      });

      await rows('installments', snap['installments'] as List?, (r) async {
        final row = await (db.select(db.installments)
              ..where((x) => x.id.equals(r['id'] as String)))
            .getSingleOrNull();
        return row == null ? -1 : _epoch(row.updatedAt);
      }, (r) async {
        await db.into(db.installments).insertOnConflictUpdate(
            InstallmentsCompanion(
                id: Value(r['id'] as String),
                bank: Value(r['bank'] as String? ?? ''),
                name: Value(r['name'] as String),
                totalKop: Value((r['total_kop'] as num).toInt()),
                monthsTotal: Value((r['months_total'] as num).toInt()),
                monthsPaid: Value((r['months_paid'] as num?)?.toInt() ?? 0),
                firstDue: Value(r['first_due'] as String),
                categoryId: Value(r['category_id'] as String?),
                owner: Value(r['owner'] as String?),
                archived: Value(r['archived'] == true),
                updatedAt: Value(_fromEpoch(r['u'] as num))));
      });

      await rows('settings', snap['settings'] as List?, (r) async {
        final row = await (db.select(db.settings)
              ..where((x) => x.key.equals(r['key'] as String)))
            .getSingleOrNull();
        return row == null ? -1 : _epoch(row.updatedAt);
      }, (r) async {
        if (!_sharedSettings.contains(r['key'])) return;
        await db.into(db.settings).insertOnConflictUpdate(SettingsCompanion(
            key: Value(r['key'] as String),
            value: Value(r['value'] as String),
            updatedAt: Value(_fromEpoch(r['u'] as num))));
      });
    });
    return applied;
  }

  /// Apply a remote deletion locally, unless the local row was edited after
  /// the deletion happened (edit-after-delete resurrects, per LWW).
  Future<bool> _deleteIfOlder(String entity, String id, int at) async {
    switch (entity) {
      case 'transactions':
        final r = await (db.select(db.transactions)
              ..where((t) => t.id.equals(id)))
            .getSingleOrNull();
        if (r == null || _epoch(r.updatedAt) > at) return false;
        await (db.delete(db.transactions)..where((t) => t.id.equals(id))).go();
        return true;
      case 'categories':
        final r = await (db.select(db.categories)
              ..where((t) => t.id.equals(id)))
            .getSingleOrNull();
        if (r == null || _epoch(r.updatedAt) > at) return false;
        await (db.delete(db.categories)..where((t) => t.id.equals(id))).go();
        return true;
      case 'category_rules':
        final r = await (db.select(db.categoryRules)
              ..where((t) => t.id.equals(id)))
            .getSingleOrNull();
        if (r == null || _epoch(r.updatedAt) > at) return false;
        await (db.delete(db.categoryRules)..where((t) => t.id.equals(id))).go();
        return true;
      case 'planned_payments':
        final r = await (db.select(db.plannedPayments)
              ..where((t) => t.id.equals(id)))
            .getSingleOrNull();
        if (r == null || _epoch(r.updatedAt) > at) return false;
        await (db.delete(db.plannedPayments)..where((t) => t.id.equals(id)))
            .go();
        return true;
      case 'installments':
        final r = await (db.select(db.installments)
              ..where((t) => t.id.equals(id)))
            .getSingleOrNull();
        if (r == null || _epoch(r.updatedAt) > at) return false;
        await (db.delete(db.installments)..where((t) => t.id.equals(id))).go();
        return true;
      case 'settings':
        if (!_sharedSettings.contains(id)) return false;
        final r = await (db.select(db.settings)
              ..where((t) => t.key.equals(id)))
            .getSingleOrNull();
        if (r == null || _epoch(r.updatedAt) > at) return false;
        await (db.delete(db.settings)..where((t) => t.key.equals(id))).go();
        return true;
      default:
        return false;
    }
  }
}
