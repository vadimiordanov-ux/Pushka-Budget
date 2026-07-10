import 'package:intl/intl.dart';

/// Month names — port of MONTHS_ALL / MONTHS_FULL from i18n.js:
/// uk/en are hand-written (the custom short forms differ from CLDR:
/// «кві», not «квіт.»); the other 8 locales are generated via Intl,
/// exactly like the PWA did.
const _ukShort = ['січ','лют','бер','кві','тра','чер','лип','сер','вер','жов','лис','гру'];
const _enShort = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
const _ukFull = ['Січень','Лютий','Березень','Квітень','Травень','Червень','Липень','Серпень','Вересень','Жовтень','Листопад','Грудень'];
const _enFull = ['January','February','March','April','May','June','July','August','September','October','November','December'];

final Map<String, List<String>> _shortCache = {};
final Map<String, List<String>> _fullCache = {};

List<String> monthsShort(String locale) {
  if (locale == 'uk') return _ukShort;
  if (locale == 'en') return _enShort;
  return _shortCache.putIfAbsent(locale, () {
    try {
      final f = DateFormat.MMM(locale);
      return [for (var m = 1; m <= 12; m++) f.format(DateTime(2026, m, 1))];
    } catch (_) {
      return _enShort;
    }
  });
}

List<String> monthsFull(String locale) {
  if (locale == 'uk') return _ukFull;
  if (locale == 'en') return _enFull;
  return _fullCache.putIfAbsent(locale, () {
    try {
      final f = DateFormat.MMMM(locale);
      return [for (var m = 1; m <= 12; m++) f.format(DateTime(2026, m, 1))];
    } catch (_) {
      return _enFull;
    }
  });
}

/// fmtDate(iso) → "5 лип" — day + short month.
String fmtDayMonth(DateTime d, String locale) =>
    '${d.day} ${monthsShort(locale)[d.month - 1]}';
