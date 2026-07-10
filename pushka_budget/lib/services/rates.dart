import '../data/db/database.dart';
import 'monobank_api.dart';

/// Currency rates — port of loadRates()/curRate() from app.js.
/// Cached in settings under 'rates1' as {t: epochMs, r: {isoCode: uahPerUnit}},
/// 30-minute TTL; on network failure the stale cache is kept (honest ₴
/// fallback happens in Money when no rate is available).
class RatesService {
  final AppDb db;
  final MonobankApi api;
  RatesService(this.db, this.api);

  Map<int, double>? _mem;

  Future<Map<int, double>?> load({bool force = false}) async {
    final cached = await db.getSetting('rates1');
    if (!force && cached is Map) {
      final t = (cached['t'] as num?)?.toInt() ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - t < 30 * 60000) {
        _mem = _parse(cached['r']);
        return _mem;
      }
    }
    try {
      final m = await api.currencyRates();
      if (m.isNotEmpty) {
        _mem = m;
        await db.setSetting('rates1', {
          't': DateTime.now().millisecondsSinceEpoch,
          'r': m.map((k, v) => MapEntry('$k', v)),
        });
      }
    } catch (_) {
      if (cached is Map) _mem = _parse(cached['r']);
    }
    return _mem;
  }

  Map<int, double>? _parse(dynamic r) => r is Map
      ? r.map((k, v) => MapEntry(int.parse('$k'), (v as num).toDouble()))
      : null;

  /// curRate(): ₴ per 1 unit of the display currency, or null.
  double? rateFor(String currency) {
    const codes = {'USD': 840, 'EUR': 978, 'PLN': 985, 'GBP': 826};
    final c = codes[currency];
    return c == null ? null : _mem?[c];
  }
}
