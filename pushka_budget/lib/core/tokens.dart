import 'package:flutter/material.dart';

/// Design tokens — 1:1 port of styles.css custom properties.
/// Two skins («aurora» default, «basic»/Classic) × light/dark, exactly like
/// `[data-skin]` / `[data-theme]` in the PWA.
class Tokens {
  final Color bg, surface, surface2, line, ink, ink2, ink3;
  final Color accent, accent2, accentInk, income, expense, glow;
  final List<Color> accentGrad; // 135deg 3-stop gradient
  final List<Color> panelGrad; // card background gradient (180deg)
  final Color navBg; // translucent tab bar
  final List<BoxShadow> shadowCard;
  final bool dark;

  const Tokens({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.line,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.accent,
    required this.accent2,
    required this.accentInk,
    required this.income,
    required this.expense,
    required this.glow,
    required this.accentGrad,
    required this.panelGrad,
    required this.navBg,
    required this.shadowCard,
    required this.dark,
  });

  static const radius = 20.0; // --radius
  static const radiusS = 13.0; // --radius-s

  LinearGradient get gradient => LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: accentGrad,
      stops: const [0, .55, 1]);
  LinearGradient get panel => LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: panelGrad);

  /// [data-skin="aurora"] (default skin)
  static const auroraDark = Tokens(
    bg: Color(0xFF0E0D0F),
    surface: Color(0xFF1B1613),
    surface2: Color(0xFF251E1A),
    line: Color(0xFF362C25),
    ink: Color(0xFFF8F4F0),
    ink2: Color(0xFFAC9F96),
    ink3: Color(0xFF71645C),
    accent: Color(0xFFFF8A3C),
    accent2: Color(0xFFF5511E),
    accentInk: Color(0xFF1C0D04),
    income: Color(0xFF3DDC97),
    expense: Color(0xFFFF6B81),
    glow: Color(0x26FF7A2D), // rgba(255,122,45,.15)
    accentGrad: [Color(0xFFFF9A3D), Color(0xFFFF7A2D), Color(0xFFF5511E)],
    panelGrad: [Color(0xFF221A15), Color(0xFF181210)],
    navBg: Color(0xD6181210), // rgba(24,18,16,.84)
    shadowCard: [
      BoxShadow(color: Color(0x52000000), blurRadius: 26, offset: Offset(0, 10)),
    ],
    dark: true,
  );

  /// [data-skin="aurora"][data-theme="light"]
  static const auroraLight = Tokens(
    bg: Color(0xFFF8F2EA),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFF3E9DD),
    line: Color(0xFFE7DAC9),
    ink: Color(0xFF221B15),
    ink2: Color(0xFF6B5D52),
    ink3: Color(0xFFA2937F),
    accent: Color(0xFFE06018),
    accent2: Color(0xFFC7480E),
    accentInk: Color(0xFF2A1204),
    income: Color(0xFF149E68),
    expense: Color(0xFFE14760),
    glow: Color(0x1FE87828), // rgba(232,120,40,.12)
    accentGrad: [Color(0xFFF58A2C), Color(0xFFEB6A1C), Color(0xFFD9490F)],
    panelGrad: [Color(0xFFFFFFFF), Color(0xFFFBF4EA)],
    navBg: Color(0xE6FFFFFF), // rgba(255,255,255,.9)
    shadowCard: [
      BoxShadow(color: Color(0x0D5A3C14), blurRadius: 2, offset: Offset(0, 1)),
      BoxShadow(color: Color(0x145A3C14), blurRadius: 28, offset: Offset(0, 10)),
    ],
    dark: false,
  );

  /// :root (Classic / «basic» skin, dark)
  static const basicDark = Tokens(
    bg: Color(0xFF0C0D13),
    surface: Color(0xFF151823),
    surface2: Color(0xFF1F2432),
    line: Color(0xFF2B3143),
    ink: Color(0xFFF3F4F9),
    ink2: Color(0xFF9AA3B8),
    ink3: Color(0xFF5E6679),
    accent: Color(0xFFFFB937),
    accent2: Color(0xFFFF8A3C),
    accentInk: Color(0xFF1A1206),
    income: Color(0xFF3DDC97),
    expense: Color(0xFFFF6B81),
    glow: Color(0x1AFFA93C), // rgba(255,169,60,.10)
    accentGrad: [Color(0xFFFFC94B), Color(0xFFFFA53C), Color(0xFFFF8A3C)],
    panelGrad: [Color(0xFF1A1E2C), Color(0xFF141722)],
    navBg: Color(0xDB151823), // rgba(21,24,35,.86)
    shadowCard: [
      BoxShadow(color: Color(0x40000000), blurRadius: 24, offset: Offset(0, 8)),
    ],
    dark: true,
  );

  /// [data-theme="light"] (Classic skin)
  static const basicLight = Tokens(
    bg: Color(0xFFF7F3EB),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFF0EBDF),
    line: Color(0xFFE5DECD),
    ink: Color(0xFF1A1D28),
    ink2: Color(0xFF5B6272),
    ink3: Color(0xFF99A0B0),
    accent: Color(0xFFC67A08),
    accent2: Color(0xFFD65A18),
    accentInk: Color(0xFF2A1802),
    income: Color(0xFF149E68),
    expense: Color(0xFFE14760),
    glow: Color(0x17E08C14), // rgba(224,140,20,.09)
    accentGrad: [Color(0xFFF2A61C), Color(0xFFE88A18), Color(0xFFE0641F)],
    panelGrad: [Color(0xFFFFFFFF), Color(0xFFFBF8F1)],
    navBg: Color(0xE0FFFFFF), // rgba(255,255,255,.88)
    shadowCard: [
      BoxShadow(color: Color(0x0D503C14), blurRadius: 2, offset: Offset(0, 1)),
      BoxShadow(color: Color(0x14503C14), blurRadius: 28, offset: Offset(0, 10)),
    ],
    dark: false,
  );

  static Tokens of({required String skin, required bool dark}) =>
      skin == 'basic'
          ? (dark ? basicDark : basicLight)
          : (dark ? auroraDark : auroraLight);
}

/// PALETTES — verbatim from app.js (6 palettes × 16 colors).
/// Names in settings UI: Тепла, Океан, Ліс, Захід, Неон, Монохром.
const List<List<Color>> kPalettes = [
  [Color(0xFFE8A33D), Color(0xFF5B9BD5), Color(0xFF4ECB8F), Color(0xFFF26D6D), Color(0xFFB98BE0), Color(0xFF5FC9C9), Color(0xFFE88BB5), Color(0xFFA3C65C), Color(0xFFE0975F), Color(0xFF7F97E8), Color(0xFF63B8A0), Color(0xFFD8788A), Color(0xFF9E8BD0), Color(0xFF6FB6DD), Color(0xFFC9A94E), Color(0xFF8FA3AD)],
  [Color(0xFF2E9BFF), Color(0xFF00C2B8), Color(0xFF5FD0E0), Color(0xFF7A6BF0), Color(0xFF5CB6FF), Color(0xFF00E0C9), Color(0xFF8FE3ED), Color(0xFF9B8FFF), Color(0xFF1E7ED9), Color(0xFF00A398), Color(0xFF3FB8CC), Color(0xFF5C4DD1), Color(0xFF7FC4FF), Color(0xFF00CBB0), Color(0xFFB0EAF0), Color(0xFF6A5ACD)],
  [Color(0xFFFFB020), Color(0xFF2E9BFF), Color(0xFF00E08A), Color(0xFFFF4D6D), Color(0xFFB15CFF), Color(0xFF00D5D5), Color(0xFFFF6EC7), Color(0xFF9FE800), Color(0xFFFF7A2E), Color(0xFF5C7CFF), Color(0xFF00C9A7), Color(0xFFFF5C8A), Color(0xFF8A6CFF), Color(0xFF33C1FF), Color(0xFFFFD23F), Color(0xFF7E9AAB)],
  [Color(0xFF4CAF6E), Color(0xFF8BC34A), Color(0xFFC0A030), Color(0xFF6D8B3C), Color(0xFF66C285), Color(0xFFA3D65C), Color(0xFFD4B54E), Color(0xFF87A85A), Color(0xFF3B8F58), Color(0xFF7AB33C), Color(0xFFE0C878), Color(0xFF5A7A34), Color(0xFF5FCB8A), Color(0xFF9ED64C), Color(0xFFB89838), Color(0xFF4F6E2E)],
  [Color(0xFFFF6B8A), Color(0xFFFF9F45), Color(0xFFC86BE0), Color(0xFF7A6BF0), Color(0xFFFF8FA8), Color(0xFFFFB870), Color(0xFFD98DEE), Color(0xFF9385F5), Color(0xFFE8546F), Color(0xFFF58A2A), Color(0xFFB355C7), Color(0xFF5C4DD1), Color(0xFFFFA8BC), Color(0xFFFFCC94), Color(0xFFE0A8F0), Color(0xFF6F5FE0)],
  [Color(0xFFCFD5DF), Color(0xFFC2C9D4), Color(0xFFB5BDCA), Color(0xFFA8B1BF), Color(0xFF9CA5B5), Color(0xFF8F99AB), Color(0xFF838EA0), Color(0xFF778296), Color(0xFF6C778C), Color(0xFF616C82), Color(0xFF576278), Color(0xFF4E596E), Color(0xFF465266), Color(0xFF3F4A5E), Color(0xFF394356), Color(0xFF333D50)],
];

/// EMOJIS — verbatim category emoji picker set from app.js.
const List<String> kEmojis = [
  '🛒','🍽️','🍕','🍔','🍣','🍰','🍎','🥦','☕','🧋','🍺','🍷','🚕','🚌','🚇','🚗','🛴','⛽','🚲','✈️','🚂','🏖️','🗺️','💊','🩺','🦷','🧠','💉','🏥','🧾','🏠','🛋️','🔑','💡','🧺','🐈','🐶','🐾','👕','👗','👟','🧥','💍','💇','💅','🧼','💄','🧴','📶','📱','💻','🖥️','🎧','📷','🎁','🎮','🎬','🎵','🎤','🎨','📚','📰','🏋️','🧘','⚽','🏊','🎿','🧹','🧽','🔧','🔨','🪴','🌸','🌳','🚬','💳','🏦','💸','💰','🪙','📈','🤝','🎓','✏️','👶','🧸','🎪','⚡','🔥','❤️','🎄','🎂','⛪','⚖️','🛡️','📦','🚚','🗑️','🚿','🪥','💧','🔁','📌','➕',
];

/// Animation curves matching the CSS cubic-beziers.
class AppCurves {
  /// cubic-bezier(.2,.8,.3,1) — the workhorse entrance curve
  static const enter = Cubic(.2, .8, .3, 1);
  /// cubic-bezier(.2,.85,.3,1) — bars/pops
  static const pop = Cubic(.2, .85, .3, 1);
  /// cubic-bezier(.22,1,.36,1) — sheet slide-up (slight overshoot feel)
  static const sheet = Cubic(.22, 1, .36, 1);
  /// cubic-bezier(.4,0,.7,1) — sheet down / exits
  static const exit = Cubic(.4, 0, .7, 1);
  /// ease-out cubic for count-up (1-(1-x)^3)
  static const countUp = Curves.easeOutCubic;
}

/// Text styles — Unbounded for display, Manrope for body (see pubspec fonts).
class AppText {
  static const display = 'Unbounded';
  static const body = 'Manrope';
}
