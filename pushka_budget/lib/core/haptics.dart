import 'package:flutter/services.dart';

/// Тактильний відгук — port of haptic() from app.js:
/// 'tick'   (7ms)      → light: threshold/step feedback
/// 'select' (14ms)     → medium: action confirmation
/// 'shift'  ([8,30,8]) → short double: value change
enum HapticKind { tick, select, shift }

Future<void> haptic([HapticKind kind = HapticKind.tick]) async {
  switch (kind) {
    case HapticKind.tick:
      await HapticFeedback.lightImpact();
    case HapticKind.select:
      await HapticFeedback.mediumImpact();
    case HapticKind.shift:
      await HapticFeedback.lightImpact();
      await Future.delayed(const Duration(milliseconds: 30));
      await HapticFeedback.lightImpact();
  }
}
