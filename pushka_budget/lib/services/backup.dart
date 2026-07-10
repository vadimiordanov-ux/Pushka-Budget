import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/db/database.dart';
import '../data/repos/repos.dart';

/// CSV / JSON backup — port of exportCSV(), exportJSON(), importJSON().
/// With local-only storage this is the ONLY way data survives uninstall —
/// surfaced in onboarding and in «Дані та резервні копії».
class BackupService {
  final AppDb db;
  BackupService(this.db);

  /// exportCSV(): current-period transactions, ; separated, BOM for Excel.
  Future<void> exportCsv(List<Transaction> txs, String periodLabel,
      Map<String, Category> cats, Map<String, Account> accounts) async {
    final rows = <String>[
      ['дата', 'опис', 'сума_грн', 'категорія', 'підкатегорія', 'нотатка',
        'картка', 'внутрішній'].join(';')
    ];
    String q(String? s) => '"${(s ?? '').replaceAll('"', '""')}"';
    for (final t in txs) {
      rows.add([
        t.time.toIso8601String().substring(0, 10),
        q(t.description),
        (t.amount / 100).toString().replaceAll('.', ','),
        cats[t.categoryId]?.name ?? '',
        t.subcategory ?? '',
        q(t.note),
        accounts[t.accountId]?.cardName ?? 'вручну',
        t.internal ? 'так' : '',
      ].join(';'));
    }
    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}/period_${periodLabel.replaceAll(' ', '')}.csv');
    await file.writeAsBytes([0xEF, 0xBB, 0xBF, ...utf8.encode(rows.join('\n'))]);
    await Share.shareXFiles([XFile(file.path, mimeType: 'text/csv')]);
  }

  /// Daily automatic backup: writes the full JSON dump into the app's
  /// documents dir (backups/), keeps the last 7. Runs from the WorkManager
  /// poll cycle; combined with Android Auto Backup this is the uninstall /
  /// lost-phone safety net.
  Future<void> autoExport() async {
    final last = await db.getSetting('last_auto_backup');
    final today = DateTime.now().toIso8601String().substring(0, 10);
    if (last == today) return;
    final dir = Directory(
        '${(await getApplicationDocumentsDirectory()).path}/backups');
    await dir.create(recursive: true);
    final file = File('${dir.path}/budget-auto-$today.json');
    await file.writeAsString(jsonEncode(await _dump()));
    // rotate: keep the newest 7
    final files = (await dir.list().toList())
        .whereType<File>()
        .where((f) => f.path.contains('budget-auto-'))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    for (final f in files.skip(7)) {
      await f.delete();
    }
    await db.setSetting('last_auto_backup', today);
  }

  /// exportJSON(): full dump — settings, categories, planned, installments,
  /// ALL transactions. Same shape as the PWA backup (v:1) so old backups
  /// remain importable and vice versa.
  Future<void> exportJson() async {
    final dump = await _dump();
    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}/budget-backup-${DateTime.now().toIso8601String().substring(0, 10)}.json');
    await file.writeAsString(const JsonEncoder.withIndent(' ').convert(dump));
    await Share.shareXFiles([XFile(file.path, mimeType: 'application/json')]);
  }

  Future<Map<String, dynamic>> _dump() async {
    final settings = await db.allSettings();
    final cats = await CatRepo(db).all();
    final planned = await PlannedRepo(db).all();
    final inst = await InstRepo(db).all();
    final txs = await TxRepo(db).all();

    return {
      'v': 1,
      'exported': DateTime.now().toIso8601String(),
      'settings': settings,
      'categories': [
        for (final c in cats)
          {
            'id': c.id, 'name': c.name, 'emoji': c.emoji, 'color': c.color,
            'type': c.type, 'sort_order': c.sortOrder, 'archived': c.archived,
            'limit_kop': c.limitKop,
          }
      ],
      'planned': [
        for (final p in planned)
          {
            'id': p.id, 'name': p.name, 'amount_kop': p.amountKop, 'day': p.day,
            'category_id': p.categoryId, 'note': p.note, 'notify': p.notify,
            'active': p.active,
          }
      ],
      'installments': [
        for (final i in inst)
          {
            'id': i.id, 'bank': i.bank, 'name': i.name, 'total_kop': i.totalKop,
            'months_total': i.monthsTotal, 'months_paid': i.monthsPaid,
            'first_due': i.firstDue, 'category_id': i.categoryId,
            'owner': i.owner, 'archived': i.archived,
          }
      ],
      'transactions': [
        for (final t in txs)
          {
            'id': t.id, 'account_id': t.accountId,
            'time': t.time.toIso8601String(),
            'description': t.description, 'mcc': t.mcc, 'amount': t.amount,
            'currency': t.currency, 'cashback': t.cashback,
            'category_id': t.categoryId, 'subcategory': t.subcategory,
            'note': t.note, 'source': t.source, 'internal': t.internal,
            'parent_id': t.parentId, 'reimburses': t.reimburses,
            'balance': t.balance,
          }
      ],
    };
  }

  /// importJSON(): restore transactions (upsert by id) — PWA parity, plus
  /// categories/planned/installments when present in the dump.
  /// Returns (txCount, exportedDate) or null if the file is unusable.
  Future<(int, String?)?> pickAndParse() async {
    final res = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: ['json']);
    final path = res?.files.single.path;
    if (path == null) return null;
    _pending = jsonDecode(await File(path).readAsString());
    final txs = (_pending?['transactions'] as List?) ?? [];
    if (txs.isEmpty) return null;
    return (txs.length, _pending?['exported'] as String?);
  }

  Map<String, dynamic>? _pending;

  Future<int> applyImport() async {
    final d = _pending;
    if (d == null) return 0;
    _pending = null;
    var n = 0;
    await db.transaction(() async {
      for (final c in (d['categories'] as List? ?? [])) {
        await db.into(db.categories).insertOnConflictUpdate(CategoriesCompanion(
            id: Value(c['id'] as String),
            name: Value(c['name'] as String),
            emoji: Value(c['emoji'] as String? ?? '📌'),
            color: Value(c['color'] as String?),
            type: Value(c['type'] as String),
            sortOrder: Value((c['sort_order'] as num?)?.toInt() ?? 0),
            archived: Value(c['archived'] == true),
            limitKop: Value((c['limit_kop'] as num?)?.toInt())));
      }
      for (final p in (d['planned'] as List? ?? [])) {
        await db.into(db.plannedPayments).insertOnConflictUpdate(
            PlannedPaymentsCompanion(
                id: Value(p['id'] as String? ?? genUuid()),
                name: Value(p['name'] as String),
                amountKop: Value((p['amount_kop'] as num).toInt()),
                day: Value((p['day'] as num?)?.toInt() ?? 1),
                categoryId: Value(p['category_id'] as String?),
                note: Value(p['note'] as String?),
                notify: Value(p['notify'] != false),
                active: Value(p['active'] != false)));
      }
      for (final i in (d['installments'] as List? ?? [])) {
        await db.into(db.installments).insertOnConflictUpdate(
            InstallmentsCompanion(
                id: Value(i['id'] as String? ?? genUuid()),
                bank: Value(i['bank'] as String? ?? ''),
                name: Value(i['name'] as String),
                totalKop: Value((i['total_kop'] as num).toInt()),
                monthsTotal: Value((i['months_total'] as num).toInt()),
                monthsPaid: Value((i['months_paid'] as num?)?.toInt() ?? 0),
                firstDue: Value(i['first_due'] as String),
                categoryId: Value(i['category_id'] as String?),
                owner: Value(i['owner'] as String?),
                archived: Value(i['archived'] == true)));
      }
      for (final t in (d['transactions'] as List? ?? [])) {
        await db.into(db.transactions).insertOnConflictUpdate(
            TransactionsCompanion(
                id: Value(t['id'] as String),
                accountId: Value(t['account_id'] as String?),
                time: Value(DateTime.parse(t['time'] as String)),
                description: Value(t['description'] as String? ?? ''),
                mcc: Value((t['mcc'] as num?)?.toInt()),
                amount: Value((t['amount'] as num).toInt()),
                currency: Value((t['currency'] as num?)?.toInt() ?? 980),
                cashback: Value((t['cashback'] as num?)?.toInt() ?? 0),
                categoryId: Value(t['category_id'] as String?),
                subcategory: Value(t['subcategory'] as String?),
                note: Value(t['note'] as String?),
                source: Value(t['source'] as String? ?? 'import'),
                internal: Value(t['internal'] == true),
                parentId: Value(t['parent_id'] as String?),
                reimburses: Value(t['reimburses'] as String?),
                balance: Value((t['balance'] as num?)?.toInt())));
        n++;
      }
    });
    return n;
  }
}
