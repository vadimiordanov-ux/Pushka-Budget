import 'package:intl/intl.dart';

/// Currency map — port of CURRENCIES in app.js.
/// Data is ALWAYS stored in kopecks (₴); display currencies convert via the
/// Monobank rate (ISO numeric code `c`). If no rate is available we honestly
/// show ₴, never someone else's symbol on hryvnia numbers.
class CurrencyDef {
  final String symbol;
  final int? isoNumeric; // Monobank currencyCodeA; null for UAH
  const CurrencyDef(this.symbol, [this.isoNumeric]);
}

const Map<String, CurrencyDef> kCurrencies = {
  'UAH': CurrencyDef('₴'),
  'USD': CurrencyDef('\$', 840),
  'EUR': CurrencyDef('€', 978),
  'PLN': CurrencyDef('zł', 985),
  'GBP': CurrencyDef('£', 826),
};

/// BCP-47 tags per locale — LOCALE_BCP from i18n.js.
const Map<String, String> kLocaleBcp = {
  'uk': 'uk-UA', 'en': 'en-GB', 'de': 'de-DE', 'fr': 'fr-FR', 'es': 'es-ES',
  'it': 'it-IT', 'nl': 'nl-NL', 'pl': 'pl-PL', 'zh': 'zh-CN', 'ja': 'ja-JP',
};

/// Money formatter — port of fmt()/fmtInt(). [rate] = ₴ per 1 unit of the
/// display currency (null → show ₴).
class Money {
  final String currency; // settings.currency
  final double? rate; // curRate()
  final String locale; // BCP tag for number grouping

  const Money({this.currency = 'UAH', this.rate, this.locale = 'uk-UA'});

  String get symbol =>
      (currency == 'UAH' || rate == null) ? '₴' : kCurrencies[currency]!.symbol;

  double _toCur(int kop) =>
      (currency == 'UAH' || rate == null) ? kop.toDouble() : kop / rate!;

  /// fmt(kop) → "1 234,56 ₴" — toLocaleString(maximumFractionDigits: 2)
  /// parity: up to 2 decimals, no trailing zeros.
  String fmt(num kop) {
    final v = _toCur(kop.round()) / 100;
    final f = NumberFormat.decimalPattern(locale)..maximumFractionDigits = 2;
    return '${f.format(v)} $symbol';
  }

  /// fmtInt(kop) → full rounded number, no symbol (used for "of LIMIT")
  String fmtInt(num kop) {
    final v = (_toCur(kop.round()) / 100).round();
    return NumberFormat.decimalPattern(locale).format(v);
  }
}

/// Auto font-scaling for the donut center — bigFontSize()/subFontSize().
double bigFontSize(String s) {
  final len = s.replaceAll(RegExp(r'\s'), '').length;
  if (len <= 8) return 29;
  if (len <= 10) return 25;
  if (len <= 12) return 21;
  if (len <= 14) return 18;
  return 15;
}

double subFontSize(String s) {
  final len = s.replaceAll(RegExp(r'\s'), '').length;
  if (len <= 10) return 12;
  if (len <= 13) return 11;
  return 10;
}
