import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/months.dart';
import '../core/period.dart';
import '../core/tokens.dart';
import '../data/db/database.dart';
import '../state.dart';

/// periodLabel() — salary: «22 чер – 21 лип»; month: «Липень 2026».
String periodLabel(Period p, String mode, String locale) {
  if (mode == 'month') {
    return '${monthsFull(locale)[p.start.month - 1]} ${p.start.year}';
  }
  final e = p.end.subtract(const Duration(days: 1));
  final m = monthsShort(locale);
  return '${p.start.day} ${m[p.start.month - 1]} – ${e.day} ${m[e.month - 1]}';
}

/// catColor() — explicit category color or palette slot by index.
Color catColor(Category? c, int index, int palette) {
  final hex = c?.color;
  if (hex != null && hex.length == 7 && hex.startsWith('#')) {
    return Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));
  }
  final pal = kPalettes[palette.clamp(0, kPalettes.length - 1)];
  return pal[((index) + 16) % 16];
}

/// chartCfg() — {type:'donut'|'bars', palette:0..5} from settings.chart.
({String type, int palette}) chartCfg(Map<String, dynamic> settings) {
  final c = settings['chart'];
  return (
    type: (c is Map ? c['type'] as String? : null) ?? 'donut',
    palette: (c is Map ? (c['palette'] as num?)?.toInt() : null) ?? 0,
  );
}

String localeOf(Map<String, dynamic> settings) =>
    settings['locale'] as String? ?? 'uk';

/// Current-locale ARB lookups need context; these are context-free helpers
/// for repeated derived values.
extension SettingsX on WidgetRef {
  Map<String, dynamic> get settings => settingsOf(this);
}
