import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../data/db/database.dart';

/// «✨ AI-розкидати» — local reimplementation of the worker's /ai-categorize
/// (the deployed worker wrote to Supabase REST, which no longer exists).
/// Behavior kept 1:1 with the worker source:
///   • uncategorized expenses → unique merchants (desc+mcc), max 40 per run;
///   • Anthropic Messages API, JSON-array answer, «null якщо незрозуміло»;
///   • per accepted answer: category_rule (pattern = exact description,
///     mcc, priority 30) + patch all matching txs.
/// The Anthropic key is stored ONLY in flutter_secure_storage
/// (same vault policy as Monobank tokens), configured on the tokens screen.
class AiCategorizeService {
  final AppDb db;
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _keyName = 'anthropic_key';

  AiCategorizeService(this.db);

  Future<bool> get configured async =>
      ((await _storage.read(key: _keyName)) ?? '').isNotEmpty;

  Future<void> setKey(String key) async {
    if (key.trim().isEmpty) {
      await _storage.delete(key: _keyName);
    } else {
      await _storage.write(key: _keyName, value: key.trim());
    }
  }

  Future<({int updated, int rules, int merchants})> run() async {
    final apiKey = await _storage.read(key: _keyName);
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('no key');
    }

    // uncategorized expenses → unique merchants (worker query parity)
    final txs = await (db.select(db.transactions)
          ..where((t) =>
              t.categoryId.isNull() &
              t.internal.equals(false) &
              t.parentId.isNull() &
              t.amount.isSmallerThanValue(0) &
              t.description.equals('').not())
          ..orderBy([(t) => OrderingTerm.desc(t.time)])
          ..limit(500))
        .get();
    final merchants =
        <String, ({String description, int? mcc, double sample, List<String> ids})>{};
    for (final t in txs) {
      final key = '${t.description}|${t.mcc ?? ''}';
      final cur = merchants[key];
      if (cur == null) {
        merchants[key] = (
          description: t.description,
          mcc: t.mcc,
          sample: t.amount / 100,
          ids: [t.id]
        );
      } else {
        cur.ids.add(t.id);
      }
    }
    final list = merchants.values.take(40).toList();
    if (list.isEmpty) return (updated: 0, rules: 0, merchants: 0);

    final cats = await (db.select(db.categories)
          ..where((c) => c.type.equals('expense') & c.archived.equals(false)))
        .get();
    final catLines =
        cats.map((c) => '- ${c.id} :: ${c.emoji} ${c.name}').join('\n');
    final merchLines = [
      for (final (i, m) in list.indexed)
        '$i. "${m.description}"${m.mcc != null && m.mcc != 0 ? ' (MCC ${m.mcc})' : ''}, приклад суми ${m.sample} грн'
    ].join('\n');

    // prompt verbatim from the worker
    final resp = await http.post(
      Uri.parse('https://api.anthropic.com/v1/messages'),
      headers: {
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': 'claude-haiku-4-5',
        'max_tokens': 2000,
        'system':
            'Ти категоризуєш банківські транзакції українського сімейного бюджету. Відповідай ЛИШЕ валідним JSON-масивом без markdown.',
        'messages': [
          {
            'role': 'user',
            'content': 'Категорії (id :: назва):\n$catLines\n\nМерчанти:\n$merchLines\n\n'
                'Поверни JSON-масив: [{"i": <номер мерчанта>, "category_id": "<id або null якщо незрозуміло>"}]. '
                'MCC-код — сильна підказка (5411 продукти, 5812 ресторани, 4121 таксі, 4900 комуналка тощо). '
                'Якщо впевненості немає — null, не вгадуй.'
          }
        ],
      }),
    );
    if (resp.statusCode != 200) {
      throw Exception('anthropic: ${resp.statusCode} ${resp.body}');
    }
    final data = jsonDecode(utf8.decode(resp.bodyBytes));
    final text = (data['content'] as List)
        .where((b) => b['type'] == 'text')
        .map((b) => b['text'])
        .join('');
    final answers = jsonDecode(
        text.replaceAll(RegExp(r'```json|```'), '').trim()) as List;

    var updated = 0, rules = 0;
    final catIds = cats.map((c) => c.id).toSet();
    for (final a in answers) {
      final i = (a['i'] as num?)?.toInt();
      final cid = a['category_id'] as String?;
      if (i == null || i < 0 || i >= list.length) continue;
      if (cid == null || !catIds.contains(cid)) continue;
      final m = list[i];
      try {
        await db.into(db.categoryRules).insert(
            CategoryRulesCompanion.insert(
                id: genUuid(),
                pattern: m.description,
                categoryId: cid,
                mcc: Value(m.mcc),
                priority: const Value(30)),
            mode: InsertMode.insertOrIgnore);
        rules++;
      } catch (_) {/* дублікати правил не страшні */}
      await (db.update(db.transactions)..where((t) => t.id.isIn(m.ids)))
          .write(TransactionsCompanion(categoryId: Value(cid)));
      updated += m.ids.length;
    }
    return (updated: updated, rules: rules, merchants: list.length);
  }
}
