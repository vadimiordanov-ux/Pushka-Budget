import 'dart:convert';

import 'package:http/http.dart' as http;

/// Thin Monobank personal API client.
/// Rate limit: 1 request / 60 s PER TOKEN (per endpoint family) — enforced by
/// SyncService via the persisted per-token clock, not here.
class MonoRateLimitException implements Exception {
  @override
  String toString() => 'mono 429 (rate limit)';
}

class MonoApiException implements Exception {
  final int status;
  final String body;
  MonoApiException(this.status, this.body);
  @override
  String toString() => 'mono $status: $body';
}

class MonoAccount {
  final String id;
  final int balance; // minor units (kopecks)
  final int creditLimit; // minor units
  final int currencyCode;
  final String? maskedPan;
  final String type; // 'black', 'white', …
  const MonoAccount(this.id, this.balance, this.creditLimit, this.currencyCode,
      this.maskedPan, this.type);
}

class MonoClientInfo {
  final String name;
  final List<MonoAccount> accounts;
  const MonoClientInfo(this.name, this.accounts);
}

class MonoStatementItem {
  final String id;
  final int time; // unix seconds
  final String description;
  final int mcc;
  final int amount; // kopecks, negative = expense
  final int currencyCode;
  final int cashbackAmount;
  final String? comment;
  final int? balance; // account balance after tx (live-schema column)
  const MonoStatementItem(this.id, this.time, this.description, this.mcc,
      this.amount, this.currencyCode, this.cashbackAmount, this.comment,
      this.balance);
}

class MonobankApi {
  static const _base = 'https://api.monobank.ua';
  final http.Client _client;
  MonobankApi([http.Client? client]) : _client = client ?? http.Client();

  Future<dynamic> _get(String path, {String? token}) async {
    final r = await _client.get(Uri.parse('$_base$path'),
        headers: token == null ? null : {'X-Token': token});
    if (r.statusCode == 429) throw MonoRateLimitException();
    if (r.statusCode != 200) throw MonoApiException(r.statusCode, r.body);
    return jsonDecode(utf8.decode(r.bodyBytes));
  }

  Future<MonoClientInfo> clientInfo(String token) async {
    final j = await _get('/personal/client-info', token: token) as Map;
    final accs = (j['accounts'] as List? ?? [])
        .map((a) => MonoAccount(
              a['id'] as String,
              (a['balance'] as num?)?.toInt() ?? 0,
              (a['creditLimit'] as num?)?.toInt() ?? 0,
              (a['currencyCode'] as num?)?.toInt() ?? 980,
              (a['maskedPan'] as List?)?.cast<String>().firstOrNull,
              a['type'] as String? ?? '',
            ))
        .toList();
    return MonoClientInfo(j['name'] as String? ?? '', accs);
  }

  /// GET /personal/statement/{account}/{from}/{to} — unix seconds.
  /// Max 31 days + 1 hour per request; max 500 items per response
  /// (SyncService paginates when exactly 500 come back).
  Future<List<MonoStatementItem>> statement(
      String token, String account, int from, int to) async {
    final j = await _get('/personal/statement/$account/$from/$to',
        token: token) as List;
    return j
        .map((i) => MonoStatementItem(
              i['id'] as String,
              (i['time'] as num).toInt(),
              i['description'] as String? ?? '',
              (i['mcc'] as num?)?.toInt() ?? 0,
              (i['amount'] as num).toInt(),
              (i['currencyCode'] as num?)?.toInt() ?? 980,
              (i['cashbackAmount'] as num?)?.toInt() ?? 0,
              i['comment'] as String?,
              (i['balance'] as num?)?.toInt(),
            ))
        .toList();
  }

  /// Public endpoint (no token, no personal rate limit): currency rates.
  /// Port of loadRates(): rateCross || mid(buy,sell) || sell || buy for
  /// pairs against UAH (980).
  Future<Map<int, double>> currencyRates() async {
    final j = await _get('/bank/currency') as List;
    final m = <int, double>{};
    for (final x in j) {
      if ((x['currencyCodeB'] as num?)?.toInt() != 980) continue;
      final a = (x['currencyCodeA'] as num).toInt();
      final rate = (x['rateCross'] as num?)?.toDouble() ??
          (((x['rateBuy'] as num?) != null && (x['rateSell'] as num?) != null)
              ? ((x['rateBuy'] as num).toDouble() +
                      (x['rateSell'] as num).toDouble()) /
                  2
              : null) ??
          (x['rateSell'] as num?)?.toDouble() ??
          (x['rateBuy'] as num?)?.toDouble();
      if (rate != null && rate > 0) m[a] = rate;
    }
    return m;
  }
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
